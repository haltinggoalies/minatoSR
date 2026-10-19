const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const ChallengeService = @import("../services/challenge.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;

const groups = &ConfigManager.global_game_config_cache.challenge_peak_group_config.challenge_peak_group;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    const arg = std.mem.trim(u8, args, commandhandler.whitespace);
    if (arg.len == 0) {
        const how = if (ProfileStore.get().peak_group != 0) "chosen with /peak" else "from SRTools or the newest";
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Anomaly Arbitration season {d} ({s}). Seasons: {s}. /peak 0 = automatic.", .{ ChallengeService.currentPeakGroupId(), how, try seasonList(allocator) }), allocator);
    }
    const group_id = std.fmt.parseInt(u32, arg, 10) catch return commandhandler.sendMessage(session, "Usage: /peak <season>, /peak 0 = automatic", allocator);
    if (group_id != 0 and !hasGroup(group_id)) {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "No season {d}. Seasons: {s}.", .{ group_id, try seasonList(allocator) }), allocator);
    }
    ProfileStore.set("peak_group", group_id);
    const now = ChallengeService.currentPeakGroupId();
    // A fight in progress keeps its season; the menus pick up the new one after it.
    if (Logic.Challenge().ChallengeMode()) {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Season {d} after this challenge.", .{now}), allocator);
    }
    try ChallengeService.pushPeakData(session, allocator);
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Anomaly Arbitration season {d}. If the banner did not change, log in again.", .{now}), allocator);
}

fn hasGroup(id: u32) bool {
    for (groups.items) |group| {
        if (group.id == id) return true;
    }
    return false;
}

fn seasonList(allocator: Allocator) ![]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    for (groups.items, 0..) |group, i| {
        if (i > 0) try text.appendSlice(" ");
        try text.writer().print("{d}", .{group.id});
    }
    return text.items;
}
