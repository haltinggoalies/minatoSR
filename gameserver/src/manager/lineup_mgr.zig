const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const BattleManager = @import("../manager/battle_mgr.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const Logic = @import("../utils/logic.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const config = &ConfigManager.global_game_config_cache.game_config;

pub const LineupManager = struct {
    allocator: Allocator,
    pub fn init(allocator: Allocator) LineupManager {
        return LineupManager{ .allocator = allocator };
    }
    // The current team preset.
    pub fn createLineup(self: *LineupManager) !protocol.LineupInfo {
        return try buildPresetLineup(self.allocator, PresetManager.curIndex());
    }
};

// One of the team presets. Members go out as base ids (8001, 1001) like the avatar list, so the
// presets that are not re-sent after a path switch stay right.
pub fn buildPresetLineup(allocator: Allocator, index: u32) !protocol.LineupInfo {
    const team = PresetManager.teamOf(index);
    var ids: [4]u32 = undefined;
    for (team.slice(), 0..) |id, i| ids[i] = PresetManager.baseId(id);
    var lineup = try buildLineup(allocator, ids[0..team.len], null);
    lineup.index = index;
    lineup.leader_slot = team.leader_slot;
    // The game's default names ("Team_Default_Name_0%d") stop at team 9, so later unnamed teams get one here.
    const name = PresetManager.presetName(index);
    lineup.name = .{ .Const = if (name.len == 0 and index >= PresetManager.game_presets)
        try std.fmt.allocPrint(allocator, "Team {d}", .{index + 1})
    else
        name };
    lineup.IECKKCHJMLP = PresetManager.isFavourite(index);
    return lineup;
}
pub fn buildAllPresets(allocator: Allocator, list: *ArrayList(protocol.LineupInfo)) !void {
    for (0..PresetManager.max_presets) |i| try list.append(try buildPresetLineup(allocator, @intCast(i)));
}

// The first 4 config.json avatars, with one Trailblazer and one March 7th at most. Seeds team 1 and
// stands in for a current team config.json no longer has anyone of.
pub fn overworldAvatarIds(out: *[4]u32) usize {
    var len: usize = 0;
    var picked_mc = false;
    var picked_m7th = false;
    for (config.avatar_config.items) |avatarConf| {
        if (len >= out.len) break;
        const id = switch (avatarConf.id) {
            8001...8010 => if (!picked_mc) blk: {
                picked_mc = true;
                break :blk AvatarManager.mc_id;
            } else continue,
            1224, 1001 => if (!picked_m7th) blk: {
                picked_m7th = true;
                break :blk AvatarManager.m7th;
            } else continue,
            else => avatarConf.id,
        };
        out[len] = id;
        len += 1;
    }
    return len;
}

pub const ChallengeLineupManager = struct {
    allocator: Allocator,
    pub fn init(allocator: Allocator) ChallengeLineupManager {
        return ChallengeLineupManager{ .allocator = allocator };
    }
    pub fn createPeakLineup(self: *ChallengeLineupManager, avatar_list: ArrayList(u32)) !protocol.LineupInfo {
        return try buildLineup(self.allocator, avatar_list.items, .LINEUP_CHALLENGE);
    }
    pub fn createLineup(self: *ChallengeLineupManager, avatar_list: ArrayList(u32)) !protocol.LineupInfo {
        return try self.createNodeLineup(avatar_list.items, Logic.Challenge().CurNode());
    }
    pub fn createNodeLineup(self: *ChallengeLineupManager, ids: []const u32, node: u32) !protocol.LineupInfo {
        const t = if (node == 1)
            protocol.ExtraLineupType.LINEUP_CHALLENGE
        else
            protocol.ExtraLineupType.LINEUP_CHALLENGE_2;
        return try buildLineup(self.allocator, ids, t);
    }
};

pub fn buildLineup(
    allocator: Allocator,
    ids: []const u32,
    extra_type: ?protocol.ExtraLineupType,
) !protocol.LineupInfo {
    var lineup = protocol.LineupInfo.init(allocator);
    lineup.mp = 5;
    lineup.max_mp = 5;
    if (extra_type) |t| {
        lineup.extra_lineup_type = t;
    } else {
        lineup.name = .{ .Const = "MushiSR" };
    }

    for (ids, 0..) |id, idx| {
        var avatar = protocol.LineupAvatar.init(allocator);
        avatar.id = id;
        if (id == 1408 or id == 1510) {
            lineup.mp = 7;
            lineup.max_mp = 7;
        }
        avatar.slot = @intCast(idx);
        avatar.satiety = 0;
        avatar.hp = 10000;
        avatar.sp_bar = .{ .cur_sp = 10000, .max_sp = 10000 };
        avatar.avatar_type = protocol.AvatarType.AVATAR_FORMAL_TYPE;
        try lineup.avatar_list.append(avatar);
    }
    return lineup;
}

pub fn deinitLineupInfo(lineup: *protocol.LineupInfo) void {
    lineup.avatar_list.deinit();
}

pub fn deinitChallengeLineupInfo(lineup: *protocol.LineupInfo) void {
    lineup.avatar_list.deinit();
}

pub fn getFunModeAvatarID(input: []const u32) !void {
    BattleManager.funmodeAvatarID.clearRetainingCapacity();
    try BattleManager.funmodeAvatarID.appendSlice(input);
}
