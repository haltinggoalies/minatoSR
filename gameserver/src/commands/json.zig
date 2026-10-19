const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const GameConfig = @import("../data/game_config.zig");
const Battle = @import("../services/battle.zig");
const sync_command = @import("sync.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;

// Named copies of config.json, so several SRTools setups can be kept and switched in game.
const configs_dir = "configs";
const backups_dir = "config-backups";
const max_config_size = 16 << 20;

const usage =
    \\/json - list the saved configs (configs folder)
    \\/json export <name> [force] - save config.json as configs/<name>.json
    \\/json load <number or name> - make that saved config the config.json and apply it
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse "list";
    if (std.ascii.eqlIgnoreCase(mode, "list")) return list(session, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "export")) {
        const name = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        const force = if (tokens.next()) |t| std.ascii.eqlIgnoreCase(t, "force") else false;
        return exportConfig(session, name, force, allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "load")) {
        const arg = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        return load(session, arg, allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn list(session: *Session, allocator: Allocator) !void {
    const names = try savedConfigs(allocator);
    if (names.len == 0) return commandhandler.sendMessage(session, "No saved configs; /json export <name> saves config.json.", allocator);
    var text = std.ArrayList(u8).init(allocator);
    for (names, 1..) |name, i| {
        if (i > 1) try text.append('\n');
        try text.writer().print("{d}. {s}", .{ i, name[0 .. name.len - ".json".len] });
    }
    try commandhandler.sendMessage(session, text.items, allocator);
}

fn exportConfig(session: *Session, name: []const u8, force: bool, allocator: Allocator) !void {
    if (!validName(name)) return commandhandler.sendMessage(session, "Names are 1-40 letters, digits, '-' or '_'.", allocator);
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ configs_dir, name });
    try std.fs.cwd().makePath(configs_dir);
    if (!force) {
        if (std.fs.cwd().access(path, .{})) {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "{s} exists; add force to overwrite it.", .{path}), allocator);
        } else |_| {}
    }
    try std.fs.cwd().copyFile("config.json", std.fs.cwd(), path, .{});
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "config.json saved as {s}.", .{path}), allocator);
}

fn load(session: *Session, arg: []const u8, allocator: Allocator) !void {
    if (Battle.on_battle) return commandhandler.sendMessage(session, "Finish the battle first.", allocator);
    // A challenge keeps the avatars it started with; SRTools' auto-sync waits for it to end too.
    if (Logic.Challenge().ChallengeMode()) return commandhandler.sendMessage(session, "Leave the challenge first.", allocator);
    const names = try savedConfigs(allocator);
    const name = pick(names, arg) orelse {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "No saved config '{s}' (see /json).", .{arg}), allocator);
    };
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ configs_dir, name });
    // Checked with the same parser as config.json before anything is touched.
    var parsed = ConfigManager.loadConfig(GameConfig.GameConfig, GameConfig.parseConfig, allocator, path) catch |err| {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "{s} is not a valid config ({s}); nothing changed.", .{ path, @errorName(err) }), allocator);
    };
    const avatars = parsed.avatar_config.items.len;
    parsed.deinit();
    if (avatars == 0) return commandhandler.sendMessage(session, "That config has no avatars; nothing changed.", allocator);

    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, max_config_size);
    try std.fs.cwd().makePath(backups_dir);
    const backup = try freeBackupName(allocator);
    try std.fs.cwd().copyFile("config.json", std.fs.cwd(), backup, .{});
    var file = try std.fs.cwd().atomicFile("config.json", .{});
    defer file.deinit();
    try file.file.writeAll(bytes);
    try file.finish();

    try sync_command.applyConfig(session, allocator);
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Loaded {s}; the old config.json is in {s}.", .{ path, backup }), allocator);
}

// The *.json files directly in configs/, sorted by name; none if the folder does not exist.
fn savedConfigs(allocator: Allocator) ![]const []const u8 {
    var dir = std.fs.cwd().openDir(configs_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer dir.close();
    var names = std.ArrayList([]const u8).init(allocator);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.ascii.endsWithIgnoreCase(entry.name, ".json")) continue;
        try names.append(try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.lessThan);
    return names.items;
}

// A number from the list or a listed name (".json" may be left out); nothing outside configs/ can be named.
fn pick(names: []const []const u8, arg: []const u8) ?[]const u8 {
    if (std.fmt.parseInt(usize, arg, 10)) |n| {
        return if (n >= 1 and n <= names.len) names[n - 1] else null;
    } else |_| {}
    const stem = if (std.ascii.endsWithIgnoreCase(arg, ".json")) arg[0 .. arg.len - ".json".len] else arg;
    for (names) |name| {
        if (std.ascii.eqlIgnoreCase(name[0 .. name.len - ".json".len], stem)) return name;
    }
    return null;
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 40) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') return false;
    }
    return true;
}

// A backup name nobody has used: two loads in the same second must not overwrite the first one's backup.
fn freeBackupName(allocator: Allocator) ![]const u8 {
    const stamp = try timestamp(allocator);
    var n: u32 = 1;
    while (true) : (n += 1) {
        const name = if (n == 1)
            try std.fmt.allocPrint(allocator, "{s}/config-{s}-before-json-load.json", .{ backups_dir, stamp })
        else
            try std.fmt.allocPrint(allocator, "{s}/config-{s}-{d}-before-json-load.json", .{ backups_dir, stamp, n });
        std.fs.cwd().access(name, .{}) catch |err| switch (err) {
            error.FileNotFound => return name,
            else => return err,
        };
    }
}

fn timestamp(allocator: Allocator) ![]const u8 {
    const secs = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
    const day = secs.getEpochDay().calculateYearDay();
    const md = day.calculateMonthDay();
    const t = secs.getDaySeconds();
    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}-UTC", .{
        day.year, md.month.numeric(), md.day_index + 1, t.getHoursIntoDay(), t.getMinutesIntoHour(), t.getSecondsIntoMinute(),
    });
}

test "config names" {
    try std.testing.expect(validName("team-A_2"));
    try std.testing.expect(!validName(""));
    try std.testing.expect(!validName("../config"));
    try std.testing.expect(!validName("a b"));
    const names = [_][]const u8{ "boss.json", "farm.json" };
    try std.testing.expectEqualStrings("farm.json", pick(&names, "2").?);
    try std.testing.expectEqualStrings("boss.json", pick(&names, "BOSS").?);
    try std.testing.expectEqualStrings("boss.json", pick(&names, "boss.json").?);
    try std.testing.expect(pick(&names, "3") == null);
    try std.testing.expect(pick(&names, "../config") == null);
}
