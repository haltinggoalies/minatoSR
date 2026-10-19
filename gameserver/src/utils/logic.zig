const std = @import("std");
const ArrayList = std.ArrayList;

pub fn FunMode() type {
    return struct {
        var on_funmode: bool = false;
        var max_Hp: u32 = 0;

        pub fn FunMode() bool {
            return on_funmode;
        }
        pub fn SetFunMode(set: bool) void {
            on_funmode = set;
        }
        pub fn SetHp(Hp: u32) void {
            max_Hp = Hp;
        }
        pub fn GetHp() u32 {
            return max_Hp;
        }
    };
}

pub fn Challenge() type {
    return struct {
        var challenge_blessing: std.ArrayList(u32) = std.ArrayList(u32).init(std.heap.page_allocator);

        var on_challenge: bool = false;

        var challenge_mode: u32 = 0;

        var challenge_planeID: u32 = 0;
        var challenge_floorID: u32 = 0;
        var challenge_entryID: u32 = 0;
        var challenge_worldID: u32 = 0;
        var challenge_monsterID: u32 = 0;
        var challenge_eventID: u32 = 0;
        var challenge_groupID: u32 = 0;
        var challenge_maze_groupID: u32 = 0;
        var challenge_stageID: u32 = 0;

        var challengeID: u32 = 0;
        var challenge_buffID: u32 = 0;

        var challenge_peak_hard: bool = true;
        var on_peak_king_stage: bool = false;

        var avatar_list: std.ArrayList(u32) = std.ArrayList(u32).init(std.heap.page_allocator);

        // Which challenge handler owns the current run. Only `.maze` (MoC/PF/AS) runs switch nodes on the server.
        pub const Kind = enum { none, maze, peak, tierce };
        pub const Status = enum { doing, finish, failed };

        // A node team; lineups never hold more than 4 avatars.
        pub const NodeLineup = struct {
            ids: [4]u32 = .{ 0, 0, 0, 0 },
            len: usize = 0,

            pub fn fromSlice(src: []const u32) NodeLineup {
                var lineup = NodeLineup{};
                for (src) |id| {
                    if (id == 0 or lineup.len == lineup.ids.len) continue;
                    lineup.ids[lineup.len] = id;
                    lineup.len += 1;
                }
                return lineup;
            }
            pub fn slice(self: *const NodeLineup) []const u32 {
                return self.ids[0..self.len];
            }
        };

        var kind: Kind = .none;
        var status: Status = .doing;
        var cur_node: u32 = 1;
        var last_node: u32 = 1;
        var awaiting_next_phase: bool = false;
        var node_lineups: [2]NodeLineup = .{ .{}, .{} };
        var node_buffs: [2]u32 = .{ 0, 0 };
        var node_scores: [2]u32 = .{ 0, 0 };
        var round_count: u32 = 0;
        // Leader of the challenge team, apart from the team presets' leaders.
        var leader_slot: u32 = 0;

        // Teams from the last full start (or challenge team edits), kept across runs for single-node starts.
        var saved_lineups: [2]NodeLineup = .{ .{}, .{} };

        pub fn GetAvatarIDs() std.ArrayList(u32) {
            return avatar_list;
        }
        pub fn AddAvatar(ids: []const u32) !void {
            for (ids) |id| {
                try avatar_list.append(id);
            }
        }

        pub fn GetKind() Kind {
            return kind;
        }
        pub fn SetKind(k: Kind) void {
            kind = k;
        }
        pub fn GetStatus() Status {
            return status;
        }
        pub fn SetStatus(s: Status) void {
            status = s;
        }
        pub fn CurNode() u32 {
            return cur_node;
        }
        pub fn SetCurNode(node: u32) void {
            cur_node = node;
        }
        pub fn LastNode() u32 {
            return last_node;
        }
        pub fn SetLastNode(node: u32) void {
            last_node = node;
        }
        pub fn AwaitingNextPhase() bool {
            return awaiting_next_phase;
        }
        pub fn SetAwaitingNextPhase(set: bool) void {
            awaiting_next_phase = set;
        }
        pub fn GetNodeLineup(node: u32) NodeLineup {
            return node_lineups[node - 1];
        }
        pub fn SetNodeLineup(node: u32, lineup: NodeLineup) void {
            node_lineups[node - 1] = lineup;
        }
        pub fn GetNodeBuff(node: u32) u32 {
            return node_buffs[node - 1];
        }
        pub fn SetNodeBuff(node: u32, buff: u32) void {
            node_buffs[node - 1] = buff;
        }
        pub fn GetNodeScore(node: u32) u32 {
            return node_scores[node - 1];
        }
        pub fn SetNodeScore(node: u32, score: u32) void {
            node_scores[node - 1] = score;
        }
        pub fn GetRoundCount() u32 {
            return round_count;
        }
        pub fn AddRounds(rounds: u32) void {
            round_count +|= rounds;
        }
        pub fn LeaderSlot() u32 {
            return leader_slot;
        }
        pub fn SetLeaderSlot(slot: u32) void {
            leader_slot = slot;
        }
        pub fn GetSavedLineup(node: u32) NodeLineup {
            return saved_lineups[node - 1];
        }
        pub fn SaveLineup(node: u32, lineup: NodeLineup) void {
            saved_lineups[node - 1] = lineup;
        }
        // Makes `node`'s team the active one (scene actors, lineup and battle avatars read avatar_list).
        pub fn UseNodeLineup(node: u32) !void {
            // A node's team reaches the client with its leader in slot 0.
            leader_slot = 0;
            avatar_list.clearRetainingCapacity();
            try AddAvatar(node_lineups[node - 1].slice());
        }
        pub fn ClearBlessing() void {
            challenge_blessing.clearRetainingCapacity();
        }

        pub fn resetChallengeState() void {
            kind = .none;
            status = .doing;
            cur_node = 1;
            last_node = 1;
            awaiting_next_phase = false;
            node_lineups = .{ .{}, .{} };
            node_buffs = .{ 0, 0 };
            node_scores = .{ 0, 0 };
            round_count = 0;
            leader_slot = 0;
            on_challenge = false;
            challenge_mode = 0;
            challenge_planeID = 0;
            challenge_floorID = 0;
            challenge_entryID = 0;
            challenge_worldID = 0;
            challenge_monsterID = 0;
            challenge_eventID = 0;
            challenge_groupID = 0;
            challenge_maze_groupID = 0;
            challenge_stageID = 0;
            challengeID = 0;
            challenge_buffID = 0;
            _ = challenge_blessing.clearRetainingCapacity();
            _ = avatar_list.clearRetainingCapacity();
            tierce_stage = 0;
            tierce_single = false;
            tierce_results = .{ .{}, .{}, .{} };
        }

        var saved_peak_lineups: std.AutoHashMap(u32, std.ArrayList(u32)) = std.AutoHashMap(u32, std.ArrayList(u32)).init(std.heap.page_allocator);

        pub fn SavePeakLineup(peak_id: u32, list: []const u32) !void {
            var avatar_copy = std.ArrayList(u32).init(std.heap.page_allocator);
            try avatar_copy.appendSlice(list);
            try saved_peak_lineups.put(peak_id, avatar_copy);
        }
        pub fn LoadPeakLineup(peak_id: u32) !void {
            if (saved_peak_lineups.get(peak_id)) |saved_list| {
                try AddAvatar(saved_list.items);
            }
        }

        pub fn ChallengeMode() bool {
            return on_challenge;
        }
        pub fn SetChallenge() void {
            on_challenge = true;
        }
        pub fn SetPeakBoss(set: bool) void {
            on_peak_king_stage = set;
        }
        pub fn ChallengePeakHard() bool {
            return challenge_peak_hard and on_peak_king_stage;
        }
        pub fn SetChallengePeakHard(set: bool) void {
            challenge_peak_hard = set;
        }
        pub fn GetChallengeID() u32 {
            return challengeID;
        }
        pub fn SetChallengeID(id: u32) void {
            challengeID = id;
        }
        pub fn SetChallengeMode(mode: u32) void {
            challenge_mode = mode;
        }
        pub fn FoundStage() bool {
            return challenge_stageID != 0;
        }
        pub fn GetChallengeStageID() u32 {
            return challenge_stageID;
        }
        pub fn GetChallengeBuffID() u32 {
            return challenge_buffID;
        }
        pub fn SetChallengeBuffID(id: u32) void {
            challenge_buffID = id;
        }
        pub fn GetChallengeMode() u32 {
            return challenge_mode;
        }
        pub fn GameModePF() bool {
            return challengeID > 20000 and challengeID < 30000;
        }
        pub fn GameModeAS() bool {
            return challengeID > 30000;
        }
        pub fn GetChallengeBlessingID() []const u32 {
            return challenge_blessing.items;
        }
        pub fn AddBlessing(id: []const u32) !void {
            try challenge_blessing.appendSlice(id);
        }
        pub fn GetCurChallengeStatus() void {
            std.debug.print("CURRENT CHALLENGE STAGE ID:{}\n", .{challenge_stageID});
            std.debug.print("CURRENT CHALLENGE LINEUP AVATAR ID:{}\n", .{GetAvatarIDs()});
            std.debug.print("CURRENT CHALLENGE MONSTER ID:{}\n", .{challenge_monsterID});

            switch (challenge_mode) {
                0 => std.debug.print("CURRENT CHALLENGE: MOC\n", .{}),
                1 => {
                    std.debug.print("CURRENT CHALLENGE: PF\n", .{});
                    if (challenge_blessing.items.len >= 2) {
                        std.debug.print("CURRENT CHALLENGE STAGE BLESSING ID:{}, SELECTED BLESSING ID:{}\n", .{ challenge_blessing.items[0], challenge_blessing.items[1] });
                    }
                },
                else => {
                    std.debug.print("CURRENT CHALLENGE: AS\n", .{});
                    if (challenge_blessing.items.len >= 2) {
                        std.debug.print("CURRENT CHALLENGE STAGE BLESSING ID:{}, SELECTED BLESSING ID:{}\n", .{ challenge_blessing.items[0], challenge_blessing.items[1] });
                    }
                },
            }
        }

        pub fn SetChallengeInfo(
            floor: u32,
            world: u32,
            monster: u32,
            event: u32,
            group: u32,
            maze: u32,
            plane: u32,
            entry: u32,
        ) void {
            challenge_floorID = floor;
            challenge_worldID = world;
            challenge_monsterID = monster;
            challenge_eventID = event;
            challenge_groupID = group;
            challenge_maze_groupID = maze;
            challenge_planeID = plane;
            challenge_entryID = entry;
            challenge_stageID = challenge_eventID;
        }
        pub fn SetChallengePeakInfo(
            floor: u32,
            monster: u32,
            event: u32,
            group: u32,
            maze: u32,
            plane: u32,
            entry: u32,
        ) void {
            challenge_floorID = floor;
            challenge_monsterID = monster;
            challenge_eventID = event;
            challenge_groupID = group;
            challenge_maze_groupID = maze;
            challenge_planeID = plane;
            challenge_entryID = entry;
            challenge_stageID = challenge_eventID;
        }
        pub fn CalChallengePeakEventID(event: u32) u32 {
            return if (ChallengePeakHard())
                event + 1
            else
                event;
        }
        pub fn GetSceneIDs() [8]u32 {
            return .{
                challenge_planeID,
                challenge_floorID,
                challenge_entryID,
                challenge_worldID,
                challenge_monsterID,
                challenge_eventID,
                challenge_groupID,
                challenge_maze_groupID,
            };
        }
        pub fn GetPeakSceneIDs() [7]u32 {
            return .{
                challenge_planeID,
                challenge_floorID,
                challenge_entryID,
                challenge_monsterID,
                challenge_eventID,
                challenge_groupID,
                challenge_maze_groupID,
            };
        }
        pub fn GetCurSceneStatus() void {
            std.debug.print("SEND PLANE ID {} FLOOR ID {} ENTRY ID {} GROUP ID {} MAZE GROUP ID {}\n", .{
                challenge_planeID,
                challenge_floorID,
                challenge_entryID,
                challenge_groupID,
                challenge_maze_groupID,
            });
        }
        // Makes `ids` the team the scene and the battle are built from.
        pub fn SetAvatars(ids: []const u32) !void {
            avatar_list.clearRetainingCapacity();
            try AddAvatar(ids);
        }

        // A Starward (Challenge Tierce) run: the node being fought (0..2), whether the player replays only that
        // node, and each node's result for the sync notifies. `end_status` holds a protocol BattleEndStatus;
        // `deaths` counts the node's downed characters.
        pub const TierceResult = struct { end_status: u32 = 0, score: u32 = 0, cycles: u32 = 0, deaths: u32 = 0 };
        var tierce_stage: u32 = 0;
        var tierce_single: bool = false;
        var tierce_results: [3]TierceResult = .{ .{}, .{}, .{} };

        pub fn SetTierceRun(stage: u32, single: bool) void {
            tierce_stage = stage;
            tierce_single = single;
            tierce_results = .{ .{}, .{}, .{} };
        }
        pub fn TierceStage() u32 {
            return tierce_stage;
        }
        pub fn SetTierceStage(stage: u32) void {
            tierce_stage = stage;
        }
        pub fn TierceSingle() bool {
            return tierce_single;
        }
        pub fn TierceResults() *[3]TierceResult {
            return &tierce_results;
        }
    };
}

pub fn CustomMode() type {
    return struct {
        var aha_buff: bool = true;
        var challenge_node: u32 = 0;
        var selected_challenge_id: u32 = 0;
        var selected_buff_id: u32 = 0;
        var custom_mode: bool = false;

        pub fn FirstNode() bool {
            return challenge_node == 0;
        }

        pub fn ChangeNode() []const u8 {
            if (FirstNode()) {
                challenge_node += 1;
                return "Change Challenge Node 2\n";
            } else {
                challenge_node -= 1;
                return "Change Challenge Node 1\n";
            }
        }

        pub fn SelectCustomNode(node: u32) void {
            challenge_node = node - 1;
        }

        // Node a custom (/id) run starts from; the run still continues to node 2 afterwards.
        pub fn StartNode() u32 {
            return challenge_node + 1;
        }

        pub fn CustomMode() bool {
            return custom_mode;
        }

        pub fn SetCustomMode(check: bool) void {
            custom_mode = check;
        }

        pub fn AhaBuff() bool {
            return aha_buff;
        }

        pub fn ToggleAhaBuff(check: bool) void {
            aha_buff = check;
        }
        pub fn GetCustomChallengeID() u32 {
            return selected_challenge_id;
        }
        pub fn SetCustomChallengeID(id: u32) void {
            selected_challenge_id = id;
        }

        pub fn GetCustomBuffID() u32 {
            return selected_buff_id;
        }
        pub fn SetCustomBuffID(id: u32) void {
            selected_buff_id = id;
        }
    };
}

pub fn Banner() type {
    return struct {
        var StandardBanner = [_]u32{ 1003, 1004, 1101, 1104, 1209, 1211 };
        var RateUp = [_]u32{1503};
        var RateUpFourStars = [_]u32{ 1210, 1108, 1207 };

        pub fn GetStandardBanner() []const u32 {
            return &StandardBanner;
        }

        pub fn SetStandardBanner() []u32 {
            return &StandardBanner;
        }

        pub fn GetRateUp() []const u32 {
            return &RateUp;
        }

        pub fn SetRateUp() []u32 {
            return &RateUp;
        }

        pub fn GetRateUpFourStar() []const u32 {
            return &RateUpFourStars;
        }

        pub fn SetRateUpFourStar() []u32 {
            return &RateUpFourStars;
        }
    };
}
pub fn inlist(id: u32, list: []const u32) bool {
    for (list) |item| {
        if (item == id) {
            return true;
        }
    }
    return false;
}
pub fn contains(list: *const std.ArrayListAligned(u32, null), value: u32) bool {
    for (list.items) |item| {
        if (item == value) {
            return true;
        }
    }
    return false;
}
