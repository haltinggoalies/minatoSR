const std = @import("std");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.profile);

const save_path = "profile.json";
const bad_path = "profile.json.bad";

pub const DisplayAvatar = struct { avatar_id: u32, pos: u32 };
// The party's last overworld spot (millimetres; rotation around the vertical axis in thousandths of a degree).
pub const Location = struct { plane_id: u32, floor_id: u32, entry_id: u32, x: i32, y: i32, z: i32, rot_y: i32 = 0 };
pub const MailState = struct {
    read: []const u32 = &.{},
    deleted: []const u32 = &.{},
    taken: []const u32 = &.{},
};

// Everything the player picks in menus that should survive a restart. Each field defaults to what the server
// reported before it was saved, so an old profile.json (only pam_skin) or none at all changes nothing.
pub const Profile = struct {
    pam_skin: u32 = 252000,
    nickname: []const u8 = "ReversedRooms",
    chat_bubble: u32 = 0,
    phone_theme: u32 = 0,
    phone_case: u32 = 254001,
    head_icon: u32 = 0,
    personal_card: u32 = 253001,
    signature: []const u8 = "",
    display_avatars: []const DisplayAvatar = &.{},
    assist_avatars: []const u32 = &.{},
    mail: MailState = .{},
    pet: u32 = 0,
    jukebox_track: u32 = 0,
    peak_group: u32 = 0,
    fake_date: u32 = 0,
    college_finished: []const u32 = &.{},
    outfit: []const u32 = &.{},
    location: ?Location = null,
    // /calyx on (true): Calyx-type and overworld fights use config.json's battle; /calyx off: their own stages.
    calyx_sync: bool = true,
};

// `current` and every slice in it live in `arena`; set() builds the next value in a fresh arena first.
var arena: ?std.heap.ArenaAllocator = null;
var current: Profile = .{};

pub fn get() *const Profile {
    return &current;
}

// Replaces one field and saves. The value is copied, so it may point into a request that is freed afterwards.
pub fn set(comptime field: []const u8, value: anytype) void {
    var next = current;
    @field(next, field) = value;
    adopt(next) catch |err| {
        log.err("{s} could not be changed: {s}", .{ field, @errorName(err) });
        return;
    };
    save();
}

fn adopt(value: Profile) !void {
    var next_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer next_arena.deinit();
    const copy = try dupe(next_arena.allocator(), value);
    if (arena) |*old| old.deinit();
    arena = next_arena;
    current = copy;
}

fn dupe(allocator: Allocator, value: anytype) !@TypeOf(value) {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size != .slice) @compileError("only slices are copied");
            const out = try allocator.alloc(p.child, value.len);
            for (value, out) |v, *o| o.* = try dupe(allocator, v);
            return out;
        },
        .@"struct" => |s| {
            var out: T = undefined;
            inline for (s.fields) |f| @field(out, f.name) = try dupe(allocator, @field(value, f.name));
            return out;
        },
        else => return value,
    }
}

// Loaded once at startup. A missing file is normal; a broken one is kept as profile.json.bad and the
// defaults are used.
pub fn load() void {
    loadFile() catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); using the defaults", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadFile() !void {
    const allocator = std.heap.page_allocator;
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, 1 << 20);
    defer allocator.free(bytes);
    const parsed = try parse(allocator, bytes);
    defer parsed.deinit();
    try adopt(parsed.value);
}
fn parse(allocator: Allocator, bytes: []const u8) !std.json.Parsed(Profile) {
    const parsed = try std.json.parseFromSlice(Profile, allocator, bytes, .{ .ignore_unknown_fields = true });
    errdefer parsed.deinit();
    if (!std.unicode.utf8ValidateSlice(parsed.value.nickname) or !std.unicode.utf8ValidateSlice(parsed.value.signature)) {
        return error.InvalidProfile;
    }
    return parsed;
}

// Written after every change; a failed write is logged and never drops the player.
pub fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    defer out.deinit();
    try std.json.stringify(current, .{ .whitespace = .indent_2 }, out.writer());
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(out.items);
    try file.finish();
}

test "an old profile.json with only the outfit keeps every other default" {
    const parsed = try parse(std.testing.allocator, "{\"pam_skin\": 252003}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 252003), parsed.value.pam_skin);
    try std.testing.expectEqualStrings("ReversedRooms", parsed.value.nickname);
    try std.testing.expectEqual(@as(u32, 254001), parsed.value.phone_case);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.display_avatars.len);
    try std.testing.expect(parsed.value.calyx_sync);
}

test "unknown fields are ignored and broken JSON is an error" {
    const parsed = try parse(std.testing.allocator, "{\"pet\": 1003, \"future_field\": [1, 2]}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1003), parsed.value.pet);
    try std.testing.expectError(error.UnexpectedEndOfInput, parse(std.testing.allocator, "{\"pet\": "));
}

test "dupe copies nested slices" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    var ids = [_]u32{ 1, 2 };
    const src = Profile{ .assist_avatars = &ids, .mail = .{ .read = &ids }, .signature = "hi" };
    const copy = try dupe(a.allocator(), src);
    ids[0] = 9;
    try std.testing.expectEqual(@as(u32, 1), copy.assist_avatars[0]);
    try std.testing.expectEqual(@as(u32, 1), copy.mail.read[0]);
    try std.testing.expectEqualStrings("hi", copy.signature);
}
