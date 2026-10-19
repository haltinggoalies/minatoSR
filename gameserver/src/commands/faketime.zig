const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const Clock = @import("../utils/clock.zig");

const Allocator = std.mem.Allocator;

const usage = "Usage: /faketime <YYYYMMDD or YYYY-MM-DD>, /faketime off";

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    const arg = std.mem.trim(u8, args, commandhandler.whitespace);
    if (arg.len == 0) {
        const date = ProfileStore.get().fake_date;
        if (date == 0) return commandhandler.sendMessage(session, "Server time: real time. " ++ usage, allocator);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Server time starts at {d:0>4}-{d:0>2}-{d:0>2} 12:00 (UTC+8) at every login.", .{ date / 10000, date / 100 % 100, date % 100 }), allocator);
    }
    if (std.ascii.eqlIgnoreCase(arg, "off")) {
        ProfileStore.set("fake_date", 0);
        Clock.resetAtLogin();
        return commandhandler.sendMessage(session, "Server time is the real time again. Log in again so the challenge menus read it.", allocator);
    }
    const date = Clock.parseDate(arg) orelse return commandhandler.sendMessage(session, usage ++ " (a real day in 2023-2099)", allocator);
    ProfileStore.set("fake_date", date);
    Clock.resetAtLogin();
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Server time now starts at {d:0>4}-{d:0>2}-{d:0>2} 12:00 (UTC+8) at every login. Log in again so the challenge menus read it.", .{ date / 10000, date / 100 % 100, date % 100 }), allocator);
}
