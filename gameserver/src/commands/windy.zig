const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const Misc = @import("../services/misc.zig");

const Allocator = std.mem.Allocator;

const lua_dir = "lua";
const max_script_size = 64 * 1024;

const usage =
    \\/windy - list the .lua files in the lua folder
    \\/windy <number or name> - send that script to the game (with the next heartbeat)
    \\/windy loaded - scripts sent since this login
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    var arg = tokens.next() orelse "list";
    if (std.ascii.eqlIgnoreCase(arg, "load")) arg = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
    if (std.ascii.eqlIgnoreCase(arg, "loaded")) {
        const sent = Misc.sentLua();
        if (sent.len == 0) return commandhandler.sendMessage(session, "No script sent since this login.", allocator);
        const text = try std.mem.join(allocator, ", ", sent);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Sent since this login: {s}", .{text}), allocator);
    }
    const files = listScripts(allocator) catch |err| switch (err) {
        error.FileNotFound => return commandhandler.sendMessage(session, "Create a lua folder next to config.json and put .lua files in it.", allocator),
        else => return err,
    };
    if (std.ascii.eqlIgnoreCase(arg, "list")) {
        if (files.len == 0) return commandhandler.sendMessage(session, "The lua folder has no .lua files.", allocator);
        var text = std.ArrayList(u8).init(allocator);
        for (files, 1..) |name, i| {
            if (i > 1) try text.append('\n');
            try text.writer().print("{d}. {s}", .{ i, name });
        }
        return commandhandler.sendMessage(session, text.items, allocator);
    }
    const name = pick(files, arg, allocator) catch {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "No script '{s}' in the lua folder (see /windy).", .{arg}), allocator);
    };
    var dir = try std.fs.cwd().openDir(lua_dir, .{});
    defer dir.close();
    const text = dir.readFileAlloc(allocator, name, max_script_size) catch |err| switch (err) {
        error.FileTooBig => return commandhandler.sendMessage(session, "Scripts may be at most 64 KB.", allocator),
        else => return err,
    };
    Misc.queueLua(name, text) catch {
        return commandhandler.sendMessage(session, "Too many scripts waiting; try again in a few seconds.", allocator);
    };
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Sending {s} with the next heartbeat.", .{name}), allocator);
}

// The .lua files directly in lua/, sorted by name.
fn listScripts(allocator: Allocator) ![]const []const u8 {
    var dir = try std.fs.cwd().openDir(lua_dir, .{ .iterate = true });
    defer dir.close();
    var names = std.ArrayList([]const u8).init(allocator);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.ascii.endsWithIgnoreCase(entry.name, ".lua")) continue;
        try names.append(try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.lessThan);
    return names.items;
}

// A number from the list, or a listed file name (".lua" may be left out). Only listed names are accepted, so a
// path such as ../config.json can never be read.
fn pick(files: []const []const u8, arg: []const u8, allocator: Allocator) ![]const u8 {
    if (std.fmt.parseInt(usize, arg, 10)) |n| {
        if (n >= 1 and n <= files.len) return files[n - 1];
        return error.NotFound;
    } else |_| {}
    const want = if (std.ascii.endsWithIgnoreCase(arg, ".lua")) arg else try std.fmt.allocPrint(allocator, "{s}.lua", .{arg});
    for (files) |name| {
        if (std.ascii.eqlIgnoreCase(name, want)) return name;
    }
    return error.NotFound;
}

test "only listed scripts can be picked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_][]const u8{ "a.lua", "Watermark.lua" };
    try std.testing.expectEqualStrings("a.lua", try pick(&files, "1", a));
    try std.testing.expectEqualStrings("Watermark.lua", try pick(&files, "watermark", a));
    try std.testing.expectError(error.NotFound, pick(&files, "3", a));
    try std.testing.expectError(error.NotFound, pick(&files, "../config.json", a));
    try std.testing.expectError(error.NotFound, pick(&files, "0", a));
}
