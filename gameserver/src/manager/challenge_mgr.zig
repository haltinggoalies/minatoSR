const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Logic = @import("../utils/logic.zig");
const ChallengeConfig = @import("../data/challenge_config.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const challenge_config = &ConfigManager.global_game_config_cache.challenge_maze_config;
const entrance_config = &ConfigManager.global_game_config_cache.map_entrance_config;
const maze_config = &ConfigManager.global_game_config_cache.maze_config;
const peak_config = &ConfigManager.global_game_config_cache.challenge_peak_config;
const challenge_tierce = &ConfigManager.global_game_config_cache.challenge_tierce_config;
const peak_boss_config = &ConfigManager.global_game_config_cache.challenge_peak_boss_config;
const res_config = &ConfigManager.global_game_config_cache.res_config;

pub const ChallengeManager = struct {
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) ChallengeManager {
        return ChallengeManager{ .allocator = allocator };
    }
    // Points the challenge globals (scene ids, stage, blessings, mode) at `node` (1 or 2) of a MoC/PF/AS challenge.
    pub fn setupNode(_: *ChallengeManager, challenge_id: u32, node: u32) !void {
        const conf = findChallengeConfig(challenge_id) orelse return error.ChallengeNotFound;
        const second = node == 2;
        const entrance_id = if (second) conf.map_entrance_id2 else conf.map_entrance_id;
        const group_id = if (second) conf.maze_group_id2 orelse return error.NoSecondNode else conf.maze_group_id1;
        const npc_list = if (second) &conf.npc_monster_id_list2 else &conf.npc_monster_id_list1;
        const event_list = if (second) &conf.event_id_list2 else &conf.event_id_list1;
        if (npc_list.items.len == 0 or event_list.items.len == 0) return error.NoSecondNode;

        const entrance = for (entrance_config.map_entrance_config.items) |e| {
            if (e.id == entrance_id) break e;
        } else return error.EntranceNotFound;
        const maze = for (maze_config.maze_plane_config.items) |m| {
            if (Logic.contains(&m.floor_id_list, entrance.floor_id)) break m;
        } else return error.MazePlaneNotFound;

        std.debug.print("CHALLENGE {} NODE {}: ENTRANCE {} GROUP {}\n", .{ challenge_id, node, entrance_id, group_id });
        Logic.Challenge().SetChallengeMode(challengeModeOf(challenge_id));
        Logic.Challenge().ClearBlessing();
        if (challenge_id > 20000) {
            // Node 1 lists the chosen buff first, node 2 lists the floor buff first.
            const buff = Logic.Challenge().GetNodeBuff(node);
            const ordered = if (second) [_]u32{ conf.maze_buff_id, buff } else [_]u32{ buff, conf.maze_buff_id };
            for (ordered) |id| {
                if (id != 0) try Logic.Challenge().AddBlessing(&[_]u32{id});
            }
        }
        Logic.Challenge().SetChallengeInfo(
            entrance.floor_id,
            maze.world_id,
            npc_list.items[npc_list.items.len - 1],
            event_list.items[event_list.items.len - 1],
            group_id,
            group_id,
            maze.challenge_plane_id,
            entrance_id,
        );
    }
    // CurChallenge for the current MoC/PF/AS run, built from stored state only.
    pub fn buildCurChallenge(self: *ChallengeManager) !protocol.CurChallenge {
        const C = Logic.Challenge();
        const challenge_id = C.GetChallengeID();
        var cur = protocol.CurChallenge.init(self.allocator);
        cur.challenge_id = challenge_id;
        cur.status = switch (C.GetStatus()) {
            .doing => .CHALLENGE_DOING,
            .finish => .CHALLENGE_FINISH,
            .failed => .CHALLENGE_FAILED,
        };
        cur.extra_lineup_type = lineupTypeOf(C.CurNode());
        cur.round_count = C.GetRoundCount();
        cur.score_id = C.GetNodeScore(1);
        cur.score_two = C.GetNodeScore(2);
        switch (challengeModeOf(challenge_id)) {
            1 => {
                var buffs = ArrayList(u32).init(self.allocator);
                try appendNodeBuffs(&buffs);
                cur.stage_info = .{ .KKNBOACNCON = .{ .cur_story_buffs = .{ .buff_list = buffs } } };
            },
            2 => {
                var buffs = ArrayList(u32).init(self.allocator);
                try appendNodeBuffs(&buffs);
                cur.stage_info = .{ .KKNBOACNCON = .{ .cur_boss_buffs = .{ .buff_list = buffs, .challenge_boss_const = 1 } } };
            },
            else => {},
        }
        return cur;
    }
    pub fn createChallengePeak(
        _: *ChallengeManager,
        challenge_peak_id: u32,
        buff_id: u32,
    ) !void {
        for (peak_config.challenge_peak.items) |peak| {
            if (peak.id == challenge_peak_id) {
                // A season whose arena is not in res.json fights in season one's arena: the floor is
                // only a backdrop for the monster, and the stage comes from the node.
                const own_arena = arenaInResConfig(peak.map_entrance_id, peak.maze_group_id);
                const entrance_id = if (own_arena) peak.map_entrance_id else fallback_peak_entrance;
                const group_id = if (own_arena) peak.maze_group_id else fallback_peak_group;
                for (entrance_config.map_entrance_config.items) |entrance| {
                    if (entrance.id == entrance_id) {
                        if (buff_id != 0) try Logic.Challenge().AddBlessing(&[_]u32{buff_id});
                        if (Logic.Challenge().ChallengePeakHard()) {
                            for (peak_boss_config.challenge_peak_boss_config.items) |boss| {
                                if (boss.id == challenge_peak_id) try Logic.Challenge().AddBlessing(boss.hard_tag_list.items);
                            }
                        } else {
                            try Logic.Challenge().AddBlessing(peak.tag_list.items);
                        }
                        Logic.Challenge().SetChallengePeakInfo(
                            entrance.floor_id,
                            peak.npc_monster_id_list.items[peak.npc_monster_id_list.items.len - 1],
                            Logic.Challenge().CalChallengePeakEventID(peak.event_id_list.items[peak.event_id_list.items.len - 1]),
                            group_id,
                            group_id,
                            entrance.plane_id,
                            entrance_id,
                        );
                    }
                }
            }
        }
    }
    pub fn createChallengeTierce(
        self: *ChallengeManager,
        challenge_id: u32,
        is_single_stage: bool,
        stage_index: u32,
        buff_id: u32,
        lineups: []const protocol.LineupInfo,
    ) !protocol.ChallengeTierceChallengeInfo {
        var cur_tierce_challenge = protocol.ChallengeTierceChallengeInfo.init(self.allocator);
        cur_tierce_challenge.challenge_id = challenge_id;
        cur_tierce_challenge.is_single_stage = is_single_stage;
        cur_tierce_challenge.stage_index = stage_index;
        try cur_tierce_challenge.lineup_list.appendSlice(lineups);

        const tierce = for (challenge_tierce.challenge_tierce.items) |*t| {
            if (t.id == challenge_id) break t;
        } else return error.ChallengeNotFound;
        // Every tierce id is its pre-challenge id + 1 (5513 -> 5512, 20275 -> 20274, 30215 -> 30214).
        const conf = findChallengeConfig(challenge_id - 1) orelse return error.ChallengeNotFound;

        const StageParams = struct { npc_monster_id: u32, event_id: u32, maze_group_id: u32, map_entrance_id: u32 };
        // Stages 0 and 1 are the pre-challenge's two nodes; stage 2 is the tierce node, with its own entrance for PF/AS.
        const p: StageParams = switch (stage_index) {
            0 => .{
                .npc_monster_id = try lastOf(&conf.npc_monster_id_list1),
                .event_id = try lastOf(&conf.event_id_list1),
                .maze_group_id = conf.maze_group_id1,
                .map_entrance_id = conf.map_entrance_id,
            },
            1 => .{
                .npc_monster_id = try lastOf(&conf.npc_monster_id_list2),
                .event_id = try lastOf(&conf.event_id_list2),
                .maze_group_id = conf.maze_group_id2 orelse conf.maze_group_id1,
                .map_entrance_id = conf.map_entrance_id2,
            },
            2 => .{
                .npc_monster_id = try lastOf(&tierce.npc_monster_id_list),
                .event_id = try lastOf(&tierce.event_id_list),
                .maze_group_id = tierce.maze_group_id,
                .map_entrance_id = tierce.map_entrance_id,
            },
            else => return error.ChallengeNotFound,
        };
        const entrance = for (entrance_config.map_entrance_config.items) |e| {
            if (e.id == p.map_entrance_id) break e;
        } else return error.ChallengeNotFound;
        const maze = for (maze_config.maze_plane_config.items) |m| {
            if (Logic.contains(&m.floor_id_list, entrance.floor_id)) break m;
        } else return error.ChallengeNotFound;

        std.debug.print("CHALLENGE TIERCE {} STAGE {}: ENTRANCE {} GROUP {}\n", .{ challenge_id, stage_index, p.map_entrance_id, p.maze_group_id });
        const mode = challengeModeOf(challenge_id);
        Logic.Challenge().SetChallengeMode(mode);
        Logic.Challenge().ClearBlessing();
        if (mode != 0) {
            for ([_]u32{ buff_id, conf.maze_buff_id }) |id| {
                if (id != 0) try Logic.Challenge().AddBlessing(&[_]u32{id});
            }
        }
        Logic.Challenge().SetChallengeInfo(
            entrance.floor_id,
            maze.world_id,
            p.npc_monster_id,
            p.event_id,
            p.maze_group_id,
            p.maze_group_id,
            maze.challenge_plane_id,
            p.map_entrance_id,
        );
        return cur_tierce_challenge;
    }
};

const fallback_peak_entrance: u32 = 3013501;
const fallback_peak_group: u32 = 8;
fn arenaInResConfig(entry_id: u32, group_id: u32) bool {
    for (res_config.scene_config.items) |scene| {
        if (scene.entryID != entry_id) continue;
        for (scene.monsters.items) |monster| {
            if (monster.groupId == group_id) return true;
        }
    }
    return false;
}
fn lastOf(list: *const ArrayList(u32)) !u32 {
    if (list.items.len == 0) return error.ChallengeNotFound;
    return list.items[list.items.len - 1];
}
pub fn findChallengeConfig(challenge_id: u32) ?*const ChallengeConfig.ChallengeConfig {
    for (challenge_config.challenge_config.items) |*conf| {
        if (conf.id == challenge_id) return conf;
    }
    return null;
}
pub fn hasSecondNode(challenge_id: u32) bool {
    const conf = findChallengeConfig(challenge_id) orelse return false;
    return conf.maze_group_id2 != null and conf.event_id_list2.items.len > 0 and conf.npc_monster_id_list2.items.len > 0;
}
// 0 = MoC, 1 = PF, 2 = AS (same split as Logic.Challenge().GameModePF/AS).
pub fn challengeModeOf(challenge_id: u32) u32 {
    if (challenge_id > 20000 and challenge_id < 30000) return 1;
    if (challenge_id > 30000) return 2;
    return 0;
}
pub fn lineupTypeOf(node: u32) protocol.ExtraLineupType {
    return if (node == 1) .LINEUP_CHALLENGE else .LINEUP_CHALLENGE_2;
}
// Both nodes' buffs, skipping the unset second one (e.g. a single-node run with no saved buff).
fn appendNodeBuffs(list: *ArrayList(u32)) !void {
    const C = Logic.Challenge();
    try list.append(C.GetNodeBuff(1));
    if (C.GetNodeBuff(2) != 0) try list.append(C.GetNodeBuff(2));
}

pub fn deinitCurChallenge(challenge: *protocol.CurChallenge) void {
    if (challenge.stage_info) |*stage_info| {
        if (stage_info.KKNBOACNCON) |*union_val| {
            switch (union_val.*) {
                .cur_story_buffs => |*story_buffs| {
                    story_buffs.buff_list.deinit();
                },
                .cur_boss_buffs => |*boss_buffs| {
                    boss_buffs.buff_list.deinit();
                },
            }
        }
    }
}
