const std = @import("std");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.prefs);

// ServerPrefs: settings the client stores on the server as opaque blobs, by id. Kept in server_prefs.json next to
// config.json as {"prefs":[{"id":N,"data":"<base64>"}]}.
const save_path = "server_prefs.json";
const bad_path = "server_prefs.json.bad";
pub const max_entries = 256;
pub const max_data_len = 64 * 1024;
// 256 entries of 64 KB in base64, with room for the JSON around them.
const max_file_len = 32 << 20;

pub const Error = error{ TooManyPrefs, PrefsTooLarge };

pub const Entry = struct { id: u32, data: []const u8 };

// Every entry's data is owned by page_allocator.
var entries = std.ArrayList(Entry).init(std.heap.page_allocator);

pub fn all() []const Entry {
    return entries.items;
}
pub fn find(id: u32) ?[]const u8 {
    for (entries.items) |entry| {
        if (entry.id == id) return entry.data;
    }
    return null;
}

// Stores a copy of `data` under `id`, replacing what was there, and saves.
pub fn put(id: u32, data: []const u8) !void {
    try putIn(&entries, std.heap.page_allocator, id, data);
    save();
}
fn putIn(list: *std.ArrayList(Entry), allocator: Allocator, id: u32, data: []const u8) !void {
    if (data.len > max_data_len) return error.PrefsTooLarge;
    const index = for (list.items, 0..) |entry, i| {
        if (entry.id == id) break i;
    } else null;
    if (index == null and list.items.len >= max_entries) return error.TooManyPrefs;
    const copy = try allocator.dupe(u8, data);
    if (index) |i| {
        allocator.free(list.items[i].data);
        list.items[i].data = copy;
    } else {
        list.append(.{ .id = id, .data = copy }) catch |err| {
            allocator.free(copy);
            return err;
        };
    }
}
fn freeAll(list: *std.ArrayList(Entry), allocator: Allocator) void {
    for (list.items) |entry| allocator.free(entry.data);
    list.deinit();
}

const SavedEntry = struct { id: u32, data: []const u8 };
const SaveFile = struct { prefs: []const SavedEntry = &.{} };

// Loaded once at startup. A missing file is normal; a broken one is kept as server_prefs.json.bad and the game
// starts with no saved settings.
pub fn load() void {
    loadFile() catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); starting without saved settings", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadFile() !void {
    const allocator = std.heap.page_allocator;
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, max_file_len);
    defer allocator.free(bytes);
    const loaded = try parse(allocator, bytes);
    freeAll(&entries, allocator);
    entries = loaded;
}
// Nothing is used unless the whole file is valid.
fn parse(allocator: Allocator, bytes: []const u8) !std.ArrayList(Entry) {
    const parsed = try std.json.parseFromSlice(SaveFile, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.prefs.len > max_entries) return error.TooManyPrefs;
    var list = std.ArrayList(Entry).init(allocator);
    errdefer freeAll(&list, allocator);
    const decoder = std.base64.standard.Decoder;
    for (parsed.value.prefs) |saved| {
        for (list.items) |entry| {
            if (entry.id == saved.id) return error.DuplicatePrefs;
        }
        const len = try decoder.calcSizeForSlice(saved.data);
        if (len > max_data_len) return error.PrefsTooLarge;
        const data = try allocator.alloc(u8, len);
        errdefer allocator.free(data);
        try decoder.decode(data, saved.data);
        try list.append(.{ .id = saved.id, .data = data });
    }
    return list;
}

fn render(allocator: Allocator, list: []const Entry) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const encoder = std.base64.standard.Encoder;
    const saved = try arena.allocator().alloc(SavedEntry, list.len);
    for (list, saved) |entry, *s| {
        const text = try arena.allocator().alloc(u8, encoder.calcSize(entry.data.len));
        s.* = .{ .id = entry.id, .data = encoder.encode(text, entry.data) };
    }
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try std.json.stringify(SaveFile{ .prefs = saved }, .{ .whitespace = .indent_2 }, out.writer());
    return out.toOwnedSlice();
}

// Written after every change; a failed write is logged and never drops the player.
fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    const text = try render(std.heap.page_allocator, entries.items);
    defer std.heap.page_allocator.free(text);
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(text);
    try file.finish();
}

test "prefs survive a save and a load, as base64 in the file" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(Entry).init(allocator);
    defer freeAll(&list, allocator);
    try putIn(&list, allocator, 7, &[_]u8{ 0, 1, 2, 255 });
    try putIn(&list, allocator, 9, "hello");
    try putIn(&list, allocator, 7, "new");
    const text = try render(allocator, list.items);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"aGVsbG8=\"") != null);
    var loaded = try parse(allocator, text);
    defer freeAll(&loaded, allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded.items.len);
    try std.testing.expectEqual(@as(u32, 7), loaded.items[0].id);
    try std.testing.expectEqualStrings("new", loaded.items[0].data);
    try std.testing.expectEqualStrings("hello", loaded.items[1].data);
}

test "at most 256 ids of at most 64 KB each" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(Entry).init(allocator);
    defer freeAll(&list, allocator);
    for (0..max_entries) |i| try putIn(&list, allocator, @intCast(i), "p");
    try std.testing.expectError(error.TooManyPrefs, putIn(&list, allocator, 1000, "q"));
    try putIn(&list, allocator, 5, "q");
    const big = try allocator.alloc(u8, max_data_len + 1);
    defer allocator.free(big);
    @memset(big, 'x');
    try std.testing.expectError(error.PrefsTooLarge, putIn(&list, allocator, 5, big));
    try putIn(&list, allocator, 5, big[0..max_data_len]);
}

test "a broken file is refused" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicatePrefs, parse(allocator, "{\"prefs\":[{\"id\":1,\"data\":\"\"},{\"id\":1,\"data\":\"\"}]}"));
    if (parse(allocator, "{\"prefs\":[{\"id\":1,\"data\":\"!!!!\"}]}")) |list| {
        var l = list;
        freeAll(&l, allocator);
        return error.TestUnexpectedResult;
    } else |_| {}
    if (parse(allocator, "{\"prefs\":")) |list| {
        var l = list;
        freeAll(&l, allocator);
        return error.TestUnexpectedResult;
    } else |_| {}
}
