const std = @import("std");
const protocol = @import("protocol");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const OverrideManager = @import("../manager/override_mgr.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const usage =
    \\/hero gender <1 male | 2 female> - same path, other Trailblazer
    \\/hero type <8001 Destruction | 8003 Preservation | 8005 Harmony | 8007 Remembrance | 8009 Elation> - same gender
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
    const value = std.fmt.parseInt(u32, tokens.next() orelse "", 10) catch return commandhandler.sendMessage(session, usage, allocator);
    // The lineup sent below is the overworld team, which a challenge in progress must not get.
    if (Logic.Challenge().ChallengeMode()) return commandhandler.sendMessage(session, "Leave the challenge first.", allocator);
    // Trailblazer ids come in pairs per path: odd male, even female.
    const target: u32 = if (std.ascii.eqlIgnoreCase(mode, "gender")) blk: {
        if (value != 1 and value != 2) return commandhandler.sendMessage(session, usage, allocator);
        break :blk pathBase(AvatarManager.mc_id) + value - 1;
    } else if (std.ascii.eqlIgnoreCase(mode, "type")) blk: {
        if (value < 8001 or value > 8010) return commandhandler.sendMessage(session, usage, allocator);
        break :blk pathBase(value) + @intFromBool(AvatarManager.gender == 2);
    } else return commandhandler.sendMessage(session, usage, allocator);

    if (!OverrideManager.inConfig(target)) {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "config.json has no {d}; add that Trailblazer in SRTools first.", .{target}), allocator);
    }
    AvatarManager.mc_id = target;
    AvatarManager.gender = if (target % 2 == 0) 2 else 1;

    // What the in-game path switch (services/avatar.zig onSetAvatarPath) sends.
    var change = protocol.AvatarPathChangedNotify.init(allocator);
    change.base_avatar_id = 8001;
    change.cur_multi_path_avatar_type = @enumFromInt(target);
    try session.send(CmdID.CmdAvatarPathChangedNotify, change);
    try AvatarManager.syncAvatarData(session, allocator);
    var lineup = protocol.SyncLineupNotify.init(allocator);
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    lineup.lineup = try lineup_mgr.createLineup();
    try session.send(CmdID.CmdSyncLineupNotify, lineup);
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Trailblazer is now {d}. If the model did not change, log in again.", .{target}), allocator);
}

// The male id of a Trailblazer path; an id that is no Trailblazer (the in-game path switch can store 0) counts as
// Destruction.
fn pathBase(id: u32) u32 {
    if (id < 8001 or id > 8010) return 8001;
    return id - (id - 8001) % 2;
}
