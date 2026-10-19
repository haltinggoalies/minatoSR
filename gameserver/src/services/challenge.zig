const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const SceneManager = @import("../manager/scene_mgr.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const Lineup = @import("lineup.zig");
const ChallengeManager = @import("../manager/challenge_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Logic = @import("../utils/logic.zig");
const BattleManager = @import("../manager/battle_mgr.zig");
const TierceManager = @import("../manager/tierce_mgr.zig");
const RecordManager = @import("../manager/record_mgr.zig");
const ChallengeConfig = @import("../data/challenge_config.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const OverrideManager = @import("../manager/override_mgr.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const challenge_config = &ConfigManager.global_game_config_cache.challenge_maze_config;
const challenge_tierce = &ConfigManager.global_game_config_cache.challenge_tierce_config;
const peak_group = &ConfigManager.global_game_config_cache.challenge_peak_group_config;
const peak_boss = &ConfigManager.global_game_config_cache.challenge_peak_boss_config;
const peak_config = &ConfigManager.global_game_config_cache.challenge_peak_config;

pub fn onGetChallenge(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChallengeScRsp.init(allocator);
    rsp.retcode = 0;

    for (challenge_config.challenge_config.items) |ids| {
        var challenge = protocol.Challenge.init(allocator);

        challenge.challenge_id = ids.id;
        challenge.taken_reward = 42;
        // A floor with a record shows it; any other shows fully cleared, as before records were kept.
        if (RecordManager.findClassic(ids.id)) |record| {
            challenge.star = record.stars_mask;
            if (ids.id > 20000) {
                challenge.score_id = record.scores[0];
                challenge.score_two = record.scores[1];
            }
        } else {
            challenge.star = 7;
            if (ids.id > 20000 and ids.id < 30000) {
                challenge.score_id = 40000;
                challenge.score_two = 40000;
            }
        }

        try rsp.challenge_list.append(challenge);
    }

    try session.send(CmdID.CmdGetChallengeScRsp, rsp);
}
// The record of a group's highest floor that has one; a group without a record shows none, as before.
pub fn onGetChallengeGroupStatistics(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetChallengeGroupStatisticsCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.GetChallengeGroupStatisticsScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.group_id = req.group_id;
    var best: ?*const ChallengeConfig.ChallengeConfig = null;
    for (challenge_config.challenge_config.items) |*conf| {
        if (conf.group_id != req.group_id or RecordManager.findClassic(conf.id) == null) continue;
        if (best) |b| {
            if ((b.floor orelse 0) >= (conf.floor orelse 0)) continue;
        }
        best = conf;
    }
    if (best) |conf| rsp.EDKOHAAMONH = try groupStatistics(allocator, conf, RecordManager.findClassic(conf.id).?);
    try session.send(CmdID.CmdGetChallengeGroupStatisticsScRsp, rsp);
}
fn groupStatistics(
    allocator: Allocator,
    conf: *const ChallengeConfig.ChallengeConfig,
    record: *const RecordManager.Classic,
) !protocol.GetChallengeGroupStatisticsScRsp.EDKOHAAMONH_union {
    const level = conf.floor orelse 0;
    var lineups = ArrayList(protocol.ChallengeLineupList).init(allocator);
    for (&record.lineups) |*team| {
        if (team.len == 0) continue;
        var list = protocol.ChallengeLineupList.init(allocator);
        for (team.slice(), 0..) |id, index| {
            try list.avatar_list.append(.{ .id = id, .level = avatarLevel(id), .index = @intCast(index), .avatar_type = .AVATAR_FORMAL_TYPE });
        }
        try lineups.append(list);
    }
    // EEJCPNAEKLJ is the star count here (M7H), not the mask GetChallenge sends.
    return switch (ChallengeManager.challengeModeOf(conf.id)) {
        0 => .{ .challenge_default = .{
            .record_id = conf.id,
            .PPBHLLOJNEK = .{ .level = level, .EEJCPNAEKLJ = record.stars(), .round_count = record.rounds, .lineup_list = lineups },
        } },
        1 => .{ .challenge_story = .{
            .record_id = conf.id,
            .PPBHLLOJNEK = .{
                .level = level,
                .EEJCPNAEKLJ = record.stars(),
                .score_id = record.score(),
                .buff_one = record.buffs[0],
                .buff_two = record.buffs[1],
                .lineup_list = lineups,
            },
        } },
        else => .{ .challenge_boss = .{
            .record_id = conf.id,
            .PPBHLLOJNEK = .{
                .level = level,
                .EEJCPNAEKLJ = record.stars(),
                .score_id = record.score(),
                .buff_one = record.buffs[0],
                .buff_two = record.buffs[1],
                .lineup_list = lineups,
            },
        } },
    };
}
// The level config.json gives a character; 80 for one it no longer has.
fn avatarLevel(id: u32) u32 {
    for (ConfigManager.global_game_config_cache.game_config.avatar_config.items) |avatar| {
        if (avatar.id == id) return avatar.level;
    }
    return 80;
}
pub fn onLeaveChallenge(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    var lineup = try lineup_mgr.createLineup();
    _ = &lineup;
    var scene_manager = SceneManager.SceneManager.init(allocator);
    var scene_info = try scene_manager.createScene(20503, 20503001, 2050301, 1029);
    _ = &scene_info;
    try session.send(CmdID.CmdQuitBattleScNotify, protocol.QuitBattleScNotify{});
    try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
        .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
        .lineup = lineup,
        .scene = scene_info,
    });
    Logic.Challenge().resetChallengeState();
    try Lineup.sendUnsentPresets(session, allocator);
    try session.send(CmdID.CmdLeaveChallengeScRsp, protocol.LeaveChallengeScRsp{
        .retcode = 0,
    });
}

pub fn onLeaveChallengePeak(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    var lineup = try lineup_mgr.createLineup();
    _ = &lineup;
    var scene_manager = SceneManager.SceneManager.init(allocator);
    var scene_info = try scene_manager.createScene(10000, 10000003, 100000352, 0);
    _ = &scene_info;
    try session.send(CmdID.CmdQuitBattleScNotify, protocol.QuitBattleScNotify{});
    try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
        .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
        .lineup = lineup,
        .scene = scene_info,
    });
    Logic.Challenge().resetChallengeState();
    peak_run = .{};
    try Lineup.sendUnsentPresets(session, allocator);
    try session.send(CmdID.CmdLeaveChallengePeakScRsp, protocol.LeaveChallengePeakScRsp{
        .retcode = 0,
    });
}

pub fn onLeaveChallengeTierce(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    var lineup = try lineup_mgr.createLineup();
    _ = &lineup;
    var scene_manager = SceneManager.SceneManager.init(allocator);
    const challenge_mode = Logic.Challenge().GetChallengeMode();
    const scene_info: protocol.SceneInfo = switch (challenge_mode) {
        0 => try scene_manager.createScene(10000, 10000000, 100000104, 2206),
        1 => try scene_manager.createScene(10202, 10202001, 102020107, 0),
        else => try scene_manager.createScene(10304, 10304001, 1030402, 0),
    };
    try session.send(CmdID.CmdQuitBattleScNotify, protocol.QuitBattleScNotify{});
    try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
        .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
        .lineup = lineup,
        .scene = scene_info,
    });
    Logic.Challenge().resetChallengeState();
    try Lineup.sendUnsentPresets(session, allocator);
    try session.send(CmdID.CmdLeaveChallengeTierceScRsp, protocol.LeaveChallengeTierceScRsp{
        .retcode = 0,
    });
}

pub fn onGetCurChallengeScRsp(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetCurChallengeScRsp.init(allocator);
    rsp.retcode = 0;
    const C = Logic.Challenge();
    if (C.ChallengeMode()) {
        if (C.GetKind() == .maze) {
            var challenge_manager = ChallengeManager.ChallengeManager.init(allocator);
            rsp.cur_challenge = try challenge_manager.buildCurChallenge();
            try appendRunLineups(&rsp.lineup_list, allocator);
        } else {
            var cur = protocol.CurChallenge.init(allocator);
            cur.challenge_id = C.GetChallengeID();
            cur.status = .CHALLENGE_DOING;
            cur.extra_lineup_type = ChallengeManager.lineupTypeOf(C.CurNode());
            if (C.GameModePF()) cur.score_id = 40000;
            rsp.cur_challenge = cur;
            var lineup_manager = LineupManager.ChallengeLineupManager.init(allocator);
            try rsp.lineup_list.append(try lineup_manager.createLineup(C.GetAvatarIDs()));
        }
        C.GetCurChallengeStatus();
    } else {
        std.debug.print("NOT ON CHALLENGE\n", .{});
    }

    try session.send(CmdID.CmdGetCurChallengeScRsp, rsp);
}
pub fn onStartChallenge(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartChallengeCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.StartChallengeScRsp.init(allocator);
    const C = Logic.Challenge();
    const custom = Logic.CustomMode().CustomMode();
    const challenge_id = if (custom) Logic.CustomMode().GetCustomChallengeID() else req.challenge_id;

    if (ChallengeManager.findChallengeConfig(challenge_id) == null) {
        std.log.err("challenge {} is not in ChallengeMazeConfig", .{challenge_id});
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdStartChallengeScRsp, rsp);
    }
    const first = teamFrom(req.avatar_lineup_first.items, req.first_lineup.items);
    var second = teamFrom(req.avatar_lineup_second.items, req.second_lineup.items);
    if (first.len == 0) {
        rsp.retcode = retcodeOf(.RET_CHALLENGE_LINEUP_EMPTY);
        return session.send(CmdID.CmdStartChallengeScRsp, rsp);
    }
    const two_nodes = ChallengeManager.hasSecondNode(challenge_id);
    if (two_nodes and second.len == 0) second = first;

    var buffs = [2]u32{ 0, 0 };
    // The client's buffs belong to the challenge it opened, so a custom (/id) challenge only keeps them if it is the same one.
    if (req.challenge_id == challenge_id) if (req.stage_info) |info| if (info.KKNBOACNCON) |selected| switch (selected) {
        .story_info => |b| buffs = .{ b.buff_one, b.buff_two },
        .boss_info => |b| buffs = .{ b.buff_one, b.buff_two },
    };
    // An /id buff comes from one node's pool, so it only replaces that node's buff.
    if (custom) buffs[Logic.CustomMode().StartNode() - 1] = Logic.CustomMode().GetCustomBuffID();

    C.resetChallengeState();
    C.SetKind(.maze);
    C.SetChallengeID(challenge_id);
    C.SetLastNode(if (two_nodes) 2 else 1);
    C.SetNodeLineup(1, first);
    C.SetNodeLineup(2, if (two_nodes) second else NodeLineup{});
    C.SetNodeBuff(1, buffs[0]);
    C.SetNodeBuff(2, buffs[1]);
    C.SaveLineup(1, first);
    if (two_nodes) C.SaveLineup(2, second);
    // A full run always goes node 1 -> node 2; only /id custom mode may start from node 2.
    const start_node: u32 = if (custom and two_nodes) Logic.CustomMode().StartNode() else 1;

    const entered = enterNode(allocator, start_node) catch |err| {
        std.log.err("failed to enter challenge {} node {}: {}", .{ challenge_id, start_node, err });
        C.resetChallengeState();
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdStartChallengeScRsp, rsp);
    };
    var challenge_manager = ChallengeManager.ChallengeManager.init(allocator);
    rsp.retcode = 0;
    rsp.scene = entered.scene;
    rsp.cur_challenge = try challenge_manager.buildCurChallenge();
    try appendRunLineups(&rsp.lineup_list, allocator);
    if (ChallengeManager.challengeModeOf(challenge_id) == 2) rsp.stage_info = try bossStageInfo(allocator);

    C.SetChallenge();
    RecordManager.startClassicRun(start_node == 1);
    try session.send(CmdID.CmdStartChallengeScRsp, rsp);
    C.GetCurSceneStatus();
    try sendAnchorMoves(session, &entered.scene);
}
// The in-game "challenge a single node" option; that node settles as the end of the run.
pub fn onStartPartialChallenge(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartPartialChallengeCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.StartPartialChallengeScRsp{ .retcode = 0 };
    const C = Logic.Challenge();
    const custom = Logic.CustomMode().CustomMode();
    const challenge_id = if (custom) Logic.CustomMode().GetCustomChallengeID() else req.challenge_id;
    const node: u32 = if (req.is_first_half) 1 else 2;
    std.log.debug("START PARTIAL CHALLENGE ID: {}, NODE: {}, BUFF ID: {}", .{ challenge_id, node, req.buff_id });

    if (ChallengeManager.findChallengeConfig(challenge_id) == null or (node == 2 and !ChallengeManager.hasSecondNode(challenge_id))) {
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdStartPartialChallengeScRsp, rsp);
    }
    // No lineup in this request: use the team last set for that node, then the other node's, then the current team preset.
    var team = C.GetSavedLineup(node);
    if (team.len == 0) team = C.GetSavedLineup(3 - node);
    if (team.len == 0) {
        const preset = PresetManager.curTeam();
        team = NodeLineup.fromSlice(preset.slice());
    }
    if (team.len == 0) {
        rsp.retcode = retcodeOf(.RET_CHALLENGE_LINEUP_EMPTY);
        return session.send(CmdID.CmdStartPartialChallengeScRsp, rsp);
    }

    C.resetChallengeState();
    C.SetKind(.maze);
    C.SetChallengeID(challenge_id);
    C.SetLastNode(node);
    C.SetNodeLineup(1, C.GetSavedLineup(1));
    C.SetNodeLineup(2, C.GetSavedLineup(2));
    C.SetNodeLineup(node, team);
    if (custom and node == Logic.CustomMode().StartNode()) {
        C.SetNodeBuff(node, Logic.CustomMode().GetCustomBuffID());
    } else if (req.challenge_id == challenge_id) {
        C.SetNodeBuff(node, req.buff_id);
    }

    const entered = enterNode(allocator, node) catch |err| {
        std.log.err("failed to enter challenge {} node {}: {}", .{ challenge_id, node, err });
        C.resetChallengeState();
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdStartPartialChallengeScRsp, rsp);
    };
    var challenge_manager = ChallengeManager.ChallengeManager.init(allocator);
    rsp.scene = entered.scene;
    rsp.lineup = entered.lineup;
    rsp.cur_challenge = try challenge_manager.buildCurChallenge();

    C.SetChallenge();
    // A single node never becomes the floor's record.
    RecordManager.startClassicRun(false);
    try session.send(CmdID.CmdChallengeLineupNotify, protocol.ChallengeLineupNotify{
        .extra_lineup_type = ChallengeManager.lineupTypeOf(node),
    });
    try session.send(CmdID.CmdStartPartialChallengeScRsp, rsp);
    C.GetCurSceneStatus();
    try sendAnchorMoves(session, &entered.scene);
}
// Sent by the client from the AS node-1 result page.
pub fn onEnterChallengeNextPhase(session: *Session, _: *const Packet, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (C.GetKind() != .maze or !C.ChallengeMode() or C.GetStatus() != .doing) {
        return session.send(CmdID.CmdEnterChallengeNextPhaseScRsp, protocol.EnterChallengeNextPhaseScRsp{
            .retcode = retcodeOf(.RET_CHALLENGE_NOT_DOING),
        });
    }
    var node = C.CurNode();
    if (C.AwaitingNextPhase()) node += 1;
    const entered = enterNode(allocator, node) catch |err| {
        std.log.err("failed to enter challenge {} node {}: {}", .{ C.GetChallengeID(), node, err });
        return session.send(CmdID.CmdEnterChallengeNextPhaseScRsp, protocol.EnterChallengeNextPhaseScRsp{
            .retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST),
        });
    };
    C.SetAwaitingNextPhase(false);
    try sendNodeLineup(session, entered.lineup, node, allocator);
    try session.send(CmdID.CmdEnterChallengeNextPhaseScRsp, protocol.EnterChallengeNextPhaseScRsp{
        .retcode = 0,
        .scene = entered.scene,
    });
    try sendAnchorMoves(session, &entered.scene);
}
// Retry the current node; its score is dropped.
pub fn onRestartChallengePhase(session: *Session, _: *const Packet, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (C.GetKind() != .maze or !C.ChallengeMode()) {
        return session.send(CmdID.CmdRestartChallengePhaseScRsp, protocol.RestartChallengePhaseScRsp{
            .retcode = retcodeOf(.RET_CHALLENGE_NOT_DOING),
        });
    }
    const node = C.CurNode();
    const entered = enterNode(allocator, node) catch |err| {
        std.log.err("failed to enter challenge {} node {}: {}", .{ C.GetChallengeID(), node, err });
        return session.send(CmdID.CmdRestartChallengePhaseScRsp, protocol.RestartChallengePhaseScRsp{
            .retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST),
        });
    };
    C.SetAwaitingNextPhase(false);
    C.SetStatus(.doing);
    C.SetNodeScore(node, 0);
    try sendNodeLineup(session, entered.lineup, node, allocator);
    try session.send(CmdID.CmdRestartChallengePhaseScRsp, protocol.RestartChallengePhaseScRsp{
        .retcode = 0,
        .scene = entered.scene,
    });
    try sendAnchorMoves(session, &entered.scene);
}
// Called from PVEBattleResult before its response: moves a MoC/PF/AS run to the next node or settles it.
pub fn onChallengeBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (C.GetKind() == .tierce) return onTierceBattleEnd(session, req, allocator);
    if (C.GetKind() == .peak) return onPeakBattleEnd(session, req, allocator);
    if (C.GetKind() != .maze or !C.ChallengeMode() or C.GetStatus() != .doing or C.AwaitingNextPhase()) return;
    if (req.stage_id != 0 and req.stage_id != C.GetChallengeStageID()) return;

    const mode = ChallengeManager.challengeModeOf(C.GetChallengeID());
    const node = C.CurNode();
    const turn_limit = if (req.stt) |stt| stt.end_reason == .BATTLE_END_REASON_TURN_LIMIT else false;
    const cleared = switch (req.end_status) {
        .BATTLE_END_WIN => true,
        // PF/AS nodes end when the cycles run out; that finishes the node rather than failing it.
        .BATTLE_END_LOSE => mode != 0 and turn_limit,
        // Retreat: the node can simply be fought again.
        else => return,
    };
    if (req.stt) |stt| {
        C.AddRounds(stt.round_cnt);
        RecordManager.endClassicNode(node, stt.round_cnt, downedAvatars(&stt));
    }
    if (mode != 0) C.SetNodeScore(node, nodeScore(req, mode, node));
    std.log.info("CHALLENGE {} NODE {}/{} {s} (scores {} / {})", .{
        C.GetChallengeID(),
        node,
        C.LastNode(),
        if (cleared) "CLEARED" else "FAILED",
        C.GetNodeScore(1),
        C.GetNodeScore(2),
    });

    if (!cleared) {
        C.SetStatus(.failed);
        if (mode == 2) {
            try sendBossPhaseSettle(session, null, node, false, 0, allocator);
        } else {
            try sendChallengeSettle(session, false, 0, allocator);
        }
        return;
    }
    if (node < C.LastNode()) {
        if (mode == 2) {
            // AS shows the node-1 result page and waits for EnterChallengeNextPhaseCsReq.
            C.SetAwaitingNextPhase(true);
            try sendBossPhaseSettle(session, req, node, false, 0, allocator);
            return;
        }
        const entered = try enterNode(allocator, node + 1);
        try sendNodeLineup(session, entered.lineup, node + 1, allocator);
        try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
            .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
            .lineup = entered.lineup,
            .scene = entered.scene,
        });
        try sendAnchorMoves(session, &entered.scene);
        return;
    }
    C.SetStatus(.finish);
    const star = RecordManager.settleClassicRun(ChallengeManager.findChallengeConfig(C.GetChallengeID()), .{
        .is_moc = mode == 0,
        .scores = .{ C.GetNodeScore(1), C.GetNodeScore(2) },
        .buffs = .{ C.GetNodeBuff(1), C.GetNodeBuff(2) },
        .lineups = .{ C.GetNodeLineup(1), C.GetNodeLineup(2) },
    });
    if (mode == 2) try sendBossPhaseSettle(session, req, node, true, star, allocator);
    try sendChallengeSettle(session, true, star, allocator);
}

const NodeLineup = Logic.Challenge().NodeLineup;
const EnteredNode = struct {
    lineup: protocol.LineupInfo,
    scene: protocol.SceneInfo,
};

// Makes `node` the current node and builds its lineup and scene.
fn enterNode(allocator: Allocator, node: u32) !EnteredNode {
    const C = Logic.Challenge();
    var challenge_manager = ChallengeManager.ChallengeManager.init(allocator);
    try challenge_manager.setupNode(C.GetChallengeID(), node);
    C.SetCurNode(node);
    try C.UseNodeLineup(node);

    var lineup_manager = LineupManager.ChallengeLineupManager.init(allocator);
    const lineup = try lineup_manager.createLineup(C.GetAvatarIDs());
    const ids = C.GetSceneIDs();
    var scene_manager = SceneManager.ChallengeSceneManager.init(allocator);
    var scene_info = try scene_manager.createScene(
        C.GetAvatarIDs(),
        ids[0],
        ids[1],
        ids[2],
        ids[3],
        ids[4],
        ids[5],
        ids[6],
    );
    SceneManager.ChallengeSceneManager.placeActorsAtAnchor(&scene_info);
    return .{ .lineup = lineup, .scene = scene_info };
}
fn appendRunLineups(list: *ArrayList(protocol.LineupInfo), allocator: Allocator) !void {
    var lineup_manager = LineupManager.ChallengeLineupManager.init(allocator);
    for ([_]u32{ 1, 2 }) |node| {
        const team = Logic.Challenge().GetNodeLineup(node);
        if (team.len == 0) continue;
        try list.append(try lineup_manager.createNodeLineup(team.slice(), node));
    }
}
fn teamFrom(avatars: []const protocol.AvatarLineup, legacy: []const u32) NodeLineup {
    var ids: [4]u32 = .{ 0, 0, 0, 0 };
    var len: usize = 0;
    for (avatars) |avatar| {
        if (avatar.id == 0 or len == ids.len) continue;
        ids[len] = avatar.id;
        len += 1;
    }
    return if (len > 0) NodeLineup.fromSlice(ids[0..len]) else NodeLineup.fromSlice(legacy);
}
fn bossStageInfo(allocator: Allocator) !protocol.ChallengeStageInfo {
    const C = Logic.Challenge();
    var info = protocol.ChallengeBossInfo.init(allocator);
    info.unk1 = true;
    info.first_node = .{ .buff_id = C.GetNodeBuff(1) };
    info.second_node = .{ .buff_id = C.GetNodeBuff(2) };
    const first = C.GetNodeLineup(1);
    for (first.slice()) |id| try info.avatar_lineup_first.append(.{ .id = id, .avatar_type = .AVATAR_FORMAL_TYPE });
    const second = C.GetNodeLineup(2);
    for (second.slice()) |id| try info.avatar_lineup_second.append(.{ .id = id, .avatar_type = .AVATAR_FORMAL_TYPE });
    return .{ .boss_info = info };
}
fn sendNodeLineup(session: *Session, lineup: protocol.LineupInfo, node: u32, allocator: Allocator) !void {
    try session.send(CmdID.CmdChallengeLineupNotify, protocol.ChallengeLineupNotify{
        .extra_lineup_type = ChallengeManager.lineupTypeOf(node),
    });
    var sync = protocol.SyncLineupNotify.init(allocator);
    sync.lineup = lineup;
    try session.send(CmdID.CmdSyncLineupNotify, sync);
}
fn sendAnchorMoves(session: *Session, scene_info: *const protocol.SceneInfo) !void {
    const motion = SceneManager.ChallengeSceneManager.spawnMotion(scene_info) orelse return;
    try sendActorMoves(session, scene_info, motion);
}
fn sendActorMoves(session: *Session, scene_info: *const protocol.SceneInfo, motion: protocol.MotionInfo) !void {
    for (scene_info.entity_group_list.items) |group| {
        for (group.entity_list.items) |entity| {
            if (entity.entity) |ent| if (ent == .actor) {
                try session.send(CmdID.CmdSceneEntityMoveScNotify, protocol.SceneEntityMoveScNotify{
                    .entity_id = entity.entity_id,
                    .entry_id = scene_info.entry_id,
                    .motion = motion,
                });
            };
        }
    }
}
// PF: score above this node's target seed. AS: sum of the key-1 battle target progress.
fn nodeScore(req: *const protocol.PVEBattleResultCsReq, mode: u32, node: u32) u32 {
    const stt = req.stt orelse return 0;
    if (mode == 1) {
        const seed = BattleManager.pfTargetSeed(node);
        return if (stt.challenge_score >= seed) stt.challenge_score - seed else stt.challenge_score;
    }
    var total: u32 = 0;
    for (stt.battle_target_info.items) |entry| {
        if (entry.key != 1) continue;
        if (entry.value) |list| {
            for (list.battle_target_list.items) |target| total +|= target.progress;
        }
    }
    return total;
}
fn sendChallengeSettle(session: *Session, is_win: bool, star: u32, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var notify = protocol.ChallengeSettleNotify.init(allocator);
    notify.challenge_id = C.GetChallengeID();
    notify.is_win = is_win;
    notify.star = star;
    notify.challenge_score = C.GetNodeScore(1);
    notify.score_two = C.GetNodeScore(2);
    notify.reward = protocol.ItemList.init(allocator);
    try session.send(CmdID.CmdChallengeSettleNotify, notify);
}
// `req` carries the AS score targets; null leaves them out (failed node).
fn sendBossPhaseSettle(session: *Session, req: ?*const protocol.PVEBattleResultCsReq, node: u32, is_win: bool, star: u32, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var notify = protocol.ChallengeBossPhaseSettleNotify.init(allocator);
    notify.challenge_id = C.GetChallengeID();
    notify.phase = node;
    notify.is_win = is_win;
    notify.star = star;
    notify.challenge_score = C.GetNodeScore(1);
    notify.score_two = C.GetNodeScore(2);
    notify.page_type = 1;
    notify.is_reward = true;
    notify.is_second_half = node == C.LastNode();
    if (req) |r| if (r.stt) |stt| {
        for (stt.battle_target_info.items) |entry| {
            if (entry.key != 1) continue;
            if (entry.value) |list| try notify.battle_target_list.appendSlice(list.battle_target_list.items);
        }
    };
    try session.send(CmdID.CmdChallengeBossPhaseSettleNotify, notify);
}
fn retcodeOf(code: protocol.Retcode) u32 {
    return @intCast(@intFromEnum(code));
}
pub fn onTakeChallengeReward(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.TakeChallengeCumulativeRewardCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.TakeChallengeCumulativeRewardScRsp.init(allocator);
    var reward = protocol.TakenChallengeRewardInfo.init(allocator);
    if (req.group_id > 2000) reward.star_count = 12 else reward.star_count = 36;
    try rsp.taken_reward_list.append(reward);
    rsp.retcode = 0;
    rsp.group_id = req.group_id;
    try session.send(CmdID.CmdTakeChallengeCumulativeRewardScRsp, rsp);
}

// Sends GetChallengePeakDataScRsp unasked, as March7thHoney's /peak does (the handler never reads its packet), then
// the chosen season as a group update.
pub fn pushPeakData(session: *Session, allocator: Allocator) !void {
    try onGetChallengePeakData(session, undefined, allocator);
    const group = peakGroupById(currentPeakGroupId()) orelse return;
    try sendPeakGroupUpdate(session, group, allocator);
}
pub fn onGetCurChallengePeak(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetCurChallengePeakScRsp.init(allocator);
    rsp.retcode = 0;
    try session.send(CmdID.CmdGetCurChallengePeakScRsp, rsp);
}
pub fn onGetChallengePeakData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChallengePeakDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (peak_group.challenge_peak_group.items) |*group| {
        const boss = findPeakBossConfig(group.boss_level_id) orelse continue;
        try rsp.challenge_peak_groups.append(try buildPeakGroup(allocator, group, boss));
    }
    rsp.current_peak_group_id = currentPeakGroupId();
    try session.send(CmdID.CmdGetChallengePeakDataScRsp, rsp);
}

// One AA season as its menu shows it. A knight or boss difficulty with a record shows it; the rest stay fully
// cleared (every star reward taken, 3 stars a knight, the hard boss passed), as before records were kept.
fn buildPeakGroup(
    allocator: Allocator,
    group: *const ChallengeConfig.ChallengePeakGroup,
    boss: *const ChallengeConfig.ChallengePeakBoss,
) !protocol.ChallengePeakGroup {
    var data = protocol.ChallengePeakGroup.init(allocator);
    data.peak_group_id = group.id;
    for (1..13) |i| try data.taken_star_rewards.append(@intCast(i));
    data.count_of_peaks = 3;
    // The knights' stars, but never fewer than 3 a knight (M7H: max(stars, knights * 3)): every knight counts as
    // passed, by a record or as before records, so nothing the season unlocks locks again.
    var stars: u32 = 0;
    var recorded = false;
    for (group.pre_level_id_list.items) |level_id| {
        const record = RecordManager.findPeak(level_id) orelse {
            stars += 3;
            continue;
        };
        const knight_stars: u32 = @intCast(@min(record.targets.len, 3));
        stars += knight_stars;
        recorded = true;
    }
    const knights: u32 = @intCast(group.pre_level_id_list.items.len);
    data.obtained_stars = @max(stars, 3 * knights);
    // The knights are listed once one has a record, the others as cleared, so none of them locks again.
    if (recorded) {
        // M7H's best_record_list.
        var best = protocol.JFBFFIAOPCC.init(allocator);
        for (group.pre_level_id_list.items) |level_id| {
            var peak = protocol.ChallengePeak.init(allocator);
            peak.peak_id = level_id;
            peak.has_passed = true;
            if (RecordManager.findPeak(level_id)) |record| {
                peak.cycles_used = record.cycles;
                try peak.finished_target_list.appendSlice(record.targets.constSlice());
                try peak.peak_avatar_id_list.appendSlice(record.team.slice());
                var entry = protocol.MEKPDDBLCGK.init(allocator);
                entry.peak_id = level_id;
                entry.cycles_used = record.cycles;
                try entry.finished_target_list.appendSlice(record.targets.constSlice());
                for (record.team.slice()) |id| try entry.avatar_list.append(.{ .avatar_id = id });
                try best.peaks.append(entry);
            } else if (findPeakConfig(level_id)) |conf| {
                try peak.finished_target_list.appendSlice(conf.normal_target_list.items);
            }
            try data.peaks.append(peak);
        }
        data.PAPDCCKPEPK = best;
    }
    data.peak_boss = try buildPeakBoss(allocator, boss);
    return data;
}
// A difficulty without a record stays as before: easy left out, hard passed with a placeholder team.
fn buildPeakBoss(allocator: Allocator, boss: *const ChallengeConfig.ChallengePeakBoss) !protocol.ChallengePeakBoss {
    var data = protocol.ChallengePeakBoss.init(allocator);
    data.hard_mode_has_passed = true;
    if (RecordManager.findPeakBoss(boss.id, false)) |record| {
        try data.finished_target_list.appendSlice(record.targets.constSlice());
        data.easy_mode = try bossClearance(allocator, record);
    } else {
        try data.finished_target_list.appendSlice(&[_]u32{ 3003, 3004, 3005 });
    }
    if (RecordManager.findPeakBoss(boss.id, true)) |record| {
        data.hard_mode = try bossClearance(allocator, record);
    } else {
        var hard = protocol.ChallengePeakBossClearance.init(allocator);
        hard.has_passed = true;
        hard.buff_id = if (boss.buff_list.items.len > 0) boss.buff_list.items[0] else 0;
        try hard.peak_avatar_id_list.append(1508);
        try hard.LAMPCACOCHP.append(1508);
        data.hard_mode = hard;
    }
    return data;
}
fn bossClearance(allocator: Allocator, record: *const RecordManager.Peak) !protocol.ChallengePeakBossClearance {
    var clearance = protocol.ChallengePeakBossClearance.init(allocator);
    clearance.has_passed = true;
    clearance.best_cycle_count = record.cycles;
    clearance.buff_id = record.buff_id;
    try clearance.peak_avatar_id_list.appendSlice(record.team.slice());
    try clearance.LAMPCACOCHP.appendSlice(record.team.slice());
    // M7H's best_record_avatar_list.
    for (record.team.slice()) |id| try clearance.EBNNJAEPBGD.append(.{ .avatar_id = id });
    return clearance;
}
fn findPeakConfig(peak_id: u32) ?*const ChallengeConfig.ChallengePeak {
    for (peak_config.challenge_peak.items) |*peak| {
        if (peak.id == peak_id) return peak;
    }
    return null;
}
fn findPeakBossConfig(boss_id: u32) ?*const ChallengeConfig.ChallengePeakBoss {
    for (peak_boss.challenge_peak_boss_config.items) |*boss| {
        if (boss.id == boss_id) return boss;
    }
    return null;
}
fn peakGroupById(group_id: u32) ?*const ChallengeConfig.ChallengePeakGroup {
    for (peak_group.challenge_peak_group.items) |*group| {
        if (group.id == group_id) return group;
    }
    return null;
}
// The season a knight or boss belongs to.
fn peakGroupOf(peak_id: u32) ?*const ChallengeConfig.ChallengePeakGroup {
    for (peak_group.challenge_peak_group.items) |*group| {
        if (group.boss_level_id == peak_id or Logic.contains(&group.pre_level_id_list, peak_id)) return group;
    }
    return null;
}
// A season once more, so its menu shows a new record or a new /peak pick without logging in again.
fn sendPeakGroupUpdate(session: *Session, group: *const ChallengeConfig.ChallengePeakGroup, allocator: Allocator) !void {
    const boss = findPeakBossConfig(group.boss_level_id) orelse return;
    try session.send(CmdID.CmdChallengePeakGroupDataUpdateScNotify, protocol.ChallengePeakGroupDataUpdateScNotify{
        .challenge_peak_group = try buildPeakGroup(allocator, group, boss),
    });
}

// The Anomaly Arbitration season the client shows (banner and boss): the one /peak chose, else the one SRTools'
// AA picker points at (it saves the picked node's stage, or the boss's hard-mode stage, as battle_config.stage_id),
// else the newest. The client asks only at login; /peak pushes the data again (pushPeakData).
pub fn currentPeakGroupId() u32 {
    const groups = peak_group.challenge_peak_group.items;
    if (groups.len == 0) return 0;
    const chosen = ProfileStore.get().peak_group;
    for (groups) |*group| {
        if (chosen != 0 and group.id == chosen) return chosen;
    }
    const stage_id = ConfigManager.global_game_config_cache.game_config.battle_config.stage_id;
    for (groups) |*group| {
        if (peakGroupHasStage(group, stage_id)) return group.id;
    }
    return groups[groups.len - 1].id;
}

fn peakGroupHasStage(group: *const @TypeOf(peak_group.challenge_peak_group.items[0]), stage_id: u32) bool {
    for (peak_config.challenge_peak.items) |*peak| {
        if (peak.id != group.boss_level_id and !Logic.contains(&group.pre_level_id_list, peak.id)) continue;
        if (Logic.contains(&peak.event_id_list, stage_id)) return true;
    }
    for (peak_boss.challenge_peak_boss_config.items) |*boss| {
        if (boss.id == group.boss_level_id and Logic.contains(&boss.hard_event_id_list, stage_id)) return true;
    }
    return false;
}
pub fn onGetChallengeTierceController(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChallengeTierceControllerScRsp.init(allocator);
    rsp.retcode = 0;
    try session.send(CmdID.CmdGetChallengeTierceControllerScRsp, rsp);
}
// The Starward floors as played: each node's saved team, and for a passed floor its record run and the stars it
// earned. A floor never passed shows as unplayed, so the floor list offers the full three-node run.
pub fn onGetChallengeTierceData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChallengeTierceDataScRsp.init(allocator);
    rsp.retcode = 0;

    for (challenge_tierce.challenge_tierce.items) |*info| {
        var data = protocol.ChallengeTierceData.init(allocator);
        data.challenge_id = info.id;
        const floor = TierceManager.find(info.id);
        const passed = if (floor) |f| f.passed else false;
        data.is_passed = passed;
        for (0..TierceManager.nodes) |index| {
            var stage_info = protocol.ChallengeTierceStageInfo.init(allocator);
            stage_info.stage_index = @intCast(index);
            if (floor) |f| {
                stage_info.buff_id = f.nodes[index].buff_id;
                for (f.nodes[index].avatars()) |id| {
                    var lineup = protocol.AvatarLineup.init(allocator);
                    lineup.id = id;
                    lineup.avatar_type = .AVATAR_FORMAL_TYPE;
                    try stage_info.lineup.append(lineup);
                }
            }
            try data.stage_info_list.append(stage_info);
        }
        if (passed) {
            const f = floor.?;
            const totals = TierceManager.floorTotals(f);
            try data.finished_target_list.appendSlice(TierceManager.metTargets(info, totals).constSlice());
            for (&f.nodes, 0..) |*node, index| {
                var result = protocol.ChallengeTierceStageData.init(allocator);
                result.stage_index = @intCast(index);
                result.end_status = .BATTLE_END_WIN;
                result.score_id = node.score;
                result.INLLMKEDGLC = node.cycles;
                result.IBECKONIICF = node.deaths;
                try data.result_list.append(result);
            }
            data.record = .{ .DJEIMGGHMGM = totals.score, .EJEDODFFABI = totals.cycles };
        }
        try rsp.challenge_info_list.append(data);
    }
    try session.send(CmdID.CmdGetChallengeTierceDataScRsp, rsp);
}

pub fn onReStartChallengePeak(session: *Session, _: *const Packet, allocator: Allocator) !void {
    // The result screen's retry: the same node, team and boss buff again, from the arena's spawn point.
    const run = peak_run;
    if (run.peak_id == 0) {
        return session.send(CmdID.CmdReStartChallengePeakScRsp, protocol.ReStartChallengePeakScRsp{
            .retcode = retcodeOf(.RET_CHALLENGE_NOT_DOING),
        });
    }
    const started = try startPeak(session, run.peak_id, run.buff_id, run.team[0..run.team_len], allocator);
    try session.send(CmdID.CmdReStartChallengePeakScRsp, protocol.ReStartChallengePeakScRsp{ .retcode = started.retcode });
    try sendPeakSpawn(session, started);
}
pub fn onSetChallengePeakMobLineupAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetChallengePeakMobLineupAvatarCsReq, allocator);
    defer req.deinit();
    var update = protocol.ChallengePeakGroup.init(allocator);
    update.peak_group_id = req.peak_group_id;
    update.count_of_peaks = 3;
    update.obtained_stars = 9;
    for (req.lineup_list.items) |list| {
        var build = protocol.ChallengePeak.init(allocator);
        build.peak_id = list.peak_id;
        build.peak_avatar_id_list = list.peak_avatar_id_list;
        try Logic.Challenge().SavePeakLineup(list.peak_id, list.peak_avatar_id_list.items);
        try update.peaks.append(build);
    }
    var rsp = protocol.SetChallengePeakMobLineupAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    try session.send(CmdID.CmdChallengePeakGroupDataUpdateScNotify, protocol.ChallengePeakGroupDataUpdateScNotify{
        .challenge_peak_group = update,
    });
    try session.send(CmdID.CmdSetChallengePeakMobLineupAvatarScRsp, rsp);
}
// The Anomaly Arbitration fight in progress, kept for its result screen and the retry from it. `team` is the
// team the start sent: the boss's, or empty for a knight, whose team was saved with SetChallengePeakMobLineupAvatar.
const PeakRun = struct {
    peak_id: u32 = 0,
    buff_id: u32 = 0,
    team: [4]u32 = .{ 0, 0, 0, 0 },
    team_len: usize = 0,
};
var peak_run: PeakRun = .{};

const PeakStart = struct {
    retcode: u32,
    scene: ?protocol.SceneInfo = null,
    spawn: ?protocol.MotionInfo = null,
};

pub fn onStartChallengePeak(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartChallengePeakCsReq, allocator);
    defer req.deinit();
    const started = try startPeak(session, req.peak_id, req.boss_buff_id, req.peak_avatar_id_list.items, allocator);
    try session.send(CmdID.CmdStartChallengePeakScRsp, protocol.StartChallengePeakScRsp{ .retcode = started.retcode });
    try sendPeakSpawn(session, started);
}

// Sends the arena of `peak_id` (EnterSceneByServerScNotify) with the party already at its spawn point; the caller
// answers the request, then calls sendPeakSpawn.
fn startPeak(session: *Session, peak_id: u32, boss_buff_id: u32, team: []const u32, allocator: Allocator) !PeakStart {
    const C = Logic.Challenge();
    // Team and blessings are appended below, so a second start or a retry without LeaveChallengePeak would add
    // to the last run's. The saved peak teams, MoC node teams and the hard mode setting are kept.
    C.resetChallengeState();
    C.SetKind(.peak);
    C.SetCurNode(1);
    if (team.len != 0) {
        C.SetPeakBoss(true);
        try C.AddAvatar(team);
    } else {
        C.SetPeakBoss(false);
        try C.LoadPeakLineup(peak_id);
    }
    // Mob teams live only in memory, so a server restart loses them: fall back to the team of the knight's record,
    // which the AA menu shows (the avatars config.json still has), else the current team preset.
    if (C.GetAvatarIDs().items.len == 0) {
        if (RecordManager.findPeak(peak_id)) |record| {
            var kept: [4]u32 = undefined;
            var len: usize = 0;
            for (record.team.slice()) |id| {
                if (!OverrideManager.inConfig(id) or len == kept.len) continue;
                kept[len] = id;
                len += 1;
            }
            try C.AddAvatar(kept[0..len]);
        }
    }
    if (C.GetAvatarIDs().items.len == 0) try C.AddAvatar(PresetManager.curTeam().slice());
    if (C.GetAvatarIDs().items.len == 0) {
        std.log.err("challenge peak {} has no team", .{peak_id});
        C.resetChallengeState();
        return .{ .retcode = retcodeOf(.RET_CHALLENGE_LINEUP_EMPTY) };
    }
    var lineup_manager = LineupManager.ChallengeLineupManager.init(allocator);
    const lineup_info = try lineup_manager.createPeakLineup(C.GetAvatarIDs());

    var challenge_manager = ChallengeManager.ChallengeManager.init(allocator);
    try challenge_manager.createChallengePeak(peak_id, boss_buff_id);

    const ids = C.GetPeakSceneIDs();
    if (ids[0] == 0) {
        std.log.err("challenge peak {} is not in ChallengePeakConfig", .{peak_id});
        C.resetChallengeState();
        return .{ .retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST) };
    }
    var scene_challenge_manager = SceneManager.ChallengeSceneManager.init(allocator);
    var scene_info = try scene_challenge_manager.createPeakScene(
        C.GetAvatarIDs(),
        ids[0],
        ids[1],
        ids[2],
        ids[3],
        ids[4],
        ids[5],
    );
    // The spawn point has to be inside the scene: without it the party stands at the origin, under the arena.
    const spawn = SceneManager.ChallengeSceneManager.peakSpawnMotion(&scene_info, ids[5]);
    if (spawn) |motion| SceneManager.ChallengeSceneManager.placeActorsAt(&scene_info, motion);
    try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
        .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
        .lineup = lineup_info,
        .scene = scene_info,
    });
    C.SetChallenge();
    C.GetCurSceneStatus();

    peak_run = .{ .peak_id = peak_id, .buff_id = boss_buff_id };
    peak_run.team_len = @min(team.len, peak_run.team.len);
    @memcpy(peak_run.team[0..peak_run.team_len], team[0..peak_run.team_len]);
    std.log.info("CHALLENGE PEAK {} STARTED IN ENTRY {} GROUP {}", .{ peak_id, ids[2], ids[5] });
    return .{ .retcode = 0, .scene = scene_info, .spawn = spawn };
}

fn sendPeakSpawn(session: *Session, started: PeakStart) !void {
    const motion = started.spawn orelse return;
    const scene_info = started.scene orelse return;
    try sendActorMoves(session, &scene_info, motion);
}

fn isPeakBoss(peak_id: u32) bool {
    for (peak_boss.challenge_peak_boss_config.items) |boss| {
        if (boss.id == peak_id) return true;
    }
    return false;
}

// Most cycles a boss clear can take and still earn a star (target 3003).
const peak_boss_turn_budget: u32 = 6;

// The result screen of an Anomaly Arbitration fight; from it the client goes on to the next knight, retries or
// leaves. A clear's targets are judged from its cycles and downed characters; it may become the knight's or boss
// difficulty's record, and its season is sent again so the menu shows it.
fn onPeakBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (!C.ChallengeMode() or peak_run.peak_id == 0) return;
    // Backing out of the fight is not losing it: the party stays in the arena.
    if (req.end_status == .BATTLE_END_QUIT) return;

    var notify = protocol.ChallengePeakSettleScNotify.init(allocator);
    notify.peak_id = peak_run.peak_id;
    notify.is_win = req.end_status == .BATTLE_END_WIN;
    if (notify.is_win) {
        const cycles = if (req.stt) |stt| stt.round_cnt else 0;
        const boss = isPeakBoss(peak_run.peak_id);
        const hard = boss and C.ChallengePeakHard();
        const met = metPeakTargets(peak_run.peak_id, hard, .{
            .cycles = cycles,
            .downed = if (req.stt) |stt| downedAvatars(&stt) else 0,
        });
        notify.cycles_used = cycles;
        if (hard) {
            // A hard clear has a result screen of its own, with no targets on it.
            notify.hard_mode_has_passed = true;
        } else {
            try notify.finished_target_list.appendSlice(met.constSlice());
            if (boss) notify.turn_left = peak_boss_turn_budget -| cycles;
        }
        RecordManager.recordPeak(.{
            .level_id = peak_run.peak_id,
            .boss = boss,
            .hard = hard,
            .cycles = cycles,
            .targets = met,
            .buff_id = peak_run.buff_id,
            .team = C.GetAvatarIDs().items,
        });
    }
    std.log.info("CHALLENGE PEAK {} {s}", .{ peak_run.peak_id, if (notify.is_win) "CLEARED" else "FAILED" });
    try session.send(CmdID.CmdChallengePeakSettleScNotify, notify);
    if (notify.is_win) {
        if (peakGroupOf(peak_run.peak_id)) |group| try sendPeakGroupUpdate(session, group, allocator);
    }
}
// The star targets a won fight met: a knight's or the easy boss's normal targets, the hard boss's own.
fn metPeakTargets(peak_id: u32, hard: bool, fight: RecordManager.Fight) RecordManager.Targets {
    if (hard) {
        const boss = findPeakBossConfig(peak_id) orelse return .{};
        if (boss.hard_target == 0) return .{};
        return RecordManager.peakTargetsMet(&[_]u32{boss.hard_target}, fight);
    }
    const peak = findPeakConfig(peak_id) orelse return .{};
    return RecordManager.peakTargetsMet(peak.normal_target_list.items, fight);
}
pub fn onSetChallengePeakBossHardMode(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetChallengePeakBossHardModeCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.SetChallengePeakBossHardModeScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.is_hard_mode = req.is_hard_mode;
    rsp.peak_group_id = req.peak_group_id;
    Logic.Challenge().SetChallengePeakHard(req.is_hard_mode);
    try session.send(CmdID.CmdSetChallengePeakBossHardModeScRsp, rsp);
}
// The season's reward buttons. GetChallengePeakData reports every star reward taken, so the client should not ask;
// if it does, the asked ids come back without items so the window does not hang.
pub fn onTakeChallengePeakReward(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.TakeChallengePeakRewardCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.TakeChallengePeakRewardScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.peak_group_id = req.peak_group_id;
    for (req.normal_reward_id_list.items) |id| {
        try rsp.peak_reward_group_list.append(.{ .reward_id = id, .reward = protocol.ItemList.init(allocator) });
    }
    try session.send(CmdID.CmdTakeChallengePeakRewardScRsp, rsp);
}
pub fn onGetFriendBattleRecordDetail(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetFriendBattleRecordDetailCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.GetFriendBattleRecordDetailScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.uid = req.uid;
    var record_list = ArrayList(protocol.ChallengeAvatarInfo).init(allocator);
    try record_list.appendSlice(&[_]protocol.ChallengeAvatarInfo{
        .{ .level = 80, .index = 0, .id = 1508, .avatar_type = protocol.AvatarType.AVATAR_UPGRADE_AVAILABLE_TYPE },
    });

    const BossType = @TypeOf(peak_boss.challenge_peak_boss_config.items[0]);
    var boss_map = std.AutoHashMap(u32, *const BossType).init(allocator);
    defer boss_map.deinit();
    for (peak_boss.challenge_peak_boss_config.items) |*boss| {
        try boss_map.put(boss.id, boss);
    }

    for (peak_group.challenge_peak_group.items) |group| {
        if (boss_map.get(group.boss_level_id)) |boss| {
            var peak_record = protocol.DBFHOCOBPMK.init(allocator);
            peak_record.group_id = group.id;
            peak_record.CDFFIGJLGMM = .{
                .buff_id = boss.buff_list.items[0],
                .peak_id = group.boss_level_id,
                .HAMDKIHGKGO = true,
                .CFLDOMPACKI = true,
                .MCJNLLBBDHN = std.ArrayList(u32).init(allocator),
                .lineup = .{ .avatar_list = record_list },
            };
            try rsp.LGIBJLFBFCG.append(peak_record);
        }
    }
    try session.send(CmdID.CmdGetFriendBattleRecordDetailScRsp, rsp);
}
//CHALLENGE TIERCE WIP
// Starward Mode (Challenge Tierce): how the 4.5 client plays MoC/PF/AS floors, as three nodes. Its other packets
// have no names in the generated protocol; the 4.6.51 ids (4.5.54 in brackets) are 8978 [8974]
// StartNextChallengeTierceCsReq (MHJNOBBOFOC) and 8977 [8980] its ScRsp (LHAKNKHBLBI), 8985 [8990]
// RestartChallengeTierceCsReq (PKKFNODINEM) and 9000 [8977] its ScRsp (JMPJCAPKNGI), 8982 [8987]
// ConfirmChallengeTierceStageSettleCsReq (MENLHHCJNCE) and 8994 [8986] its ScRsp (OKEDFNJJGHB), and 8975 [8976]
// ChallengeTierceSyncNotify (DOPHNDHILPA, the struct ChallengeTierceScNotify). CapySR's 4.6.51 cmdids.txt agrees.
const tierce_nodes = 3;

fn tierceLineupType(stage: u32) protocol.ExtraLineupType {
    return switch (stage) {
        0 => .LINEUP_CHALLENGE,
        1 => .LINEUP_CHALLENGE_2,
        else => .LINEUP_CHALLENGE_3,
    };
}

const TierceStage = struct { scene: protocol.SceneInfo, info: protocol.ChallengeTierceChallengeInfo };

// Makes `stage` the node in progress and builds its arena. The client takes the node's team from lineup_list by
// the stage index, so all three teams are sent; with only the current one, node 2 crashed the client's loading.
fn enterTierceStage(session: *Session, allocator: Allocator, stage: u32) !TierceStage {
    const C = Logic.Challenge();
    const challenge_id = C.GetChallengeID();
    C.SetTierceStage(stage);
    // PF's battle target seed reads the 1-based node.
    C.SetCurNode(stage + 1);
    C.SetLeaderSlot(0);
    try C.SetAvatars(TierceManager.stageLineup(challenge_id, stage));
    C.SetChallengeBuffID(TierceManager.stageBuff(challenge_id, stage));
    std.log.debug("CHALLENGE TIERCE {} STAGE {}: LINEUP {any} BUFF {}", .{ challenge_id, stage, C.GetAvatarIDs().items, C.GetChallengeBuffID() });

    var lineups = ArrayList(protocol.LineupInfo).init(allocator);
    for (0..tierce_nodes) |i| {
        const node_stage: u32 = @intCast(i);
        try lineups.append(try LineupManager.buildLineup(allocator, TierceManager.stageLineup(challenge_id, i), tierceLineupType(node_stage)));
    }
    var challenge_manager = ChallengeManager.ChallengeManager.init(allocator);
    const info = try challenge_manager.createChallengeTierce(challenge_id, C.TierceSingle(), stage, C.GetChallengeBuffID(), lineups.items);

    const ids = C.GetSceneIDs();
    var scene_challenge_manager = SceneManager.ChallengeSceneManager.init(allocator);
    var scene_info = try scene_challenge_manager.createScene(
        C.GetAvatarIDs(),
        ids[0],
        ids[1],
        ids[2],
        ids[3],
        ids[4],
        ids[5],
        ids[6],
    );
    // The spawn point has to be inside the scene: a SceneEntityMoveScNotify sent before the client holds the
    // scene is dropped, and the party would stand at the origin, out of the monster's reach.
    SceneManager.ChallengeSceneManager.placeActorsAtAnchor(&scene_info);

    // The client switches to the node's team before the arena arrives.
    try session.send(CmdID.CmdChallengeLineupNotify, protocol.ChallengeLineupNotify{ .extra_lineup_type = tierceLineupType(stage) });
    var sync = protocol.SyncLineupNotify.init(allocator);
    sync.lineup = lineups.items[stage];
    try session.send(CmdID.CmdSyncLineupNotify, sync);
    return .{ .scene = scene_info, .info = info };
}

// Each node's team and buff as the client set them. AS nodes pick from their own list (4.6 log, 30205: 3111092 /
// 3111058 / 3111079), PF nodes from one shared list (20285: 3031354 / 3031366 / 3031354), MoC none. Recommended
// teams have to carry a buff the same way, or the window's "Replace" does nothing.
fn logTierceLineups(challenge_id: u32, stages: []const protocol.LineupTierce) void {
    for (stages, 1..) |info, node| {
        var ids: [4]u32 = .{ 0, 0, 0, 0 };
        for (info.lineup.items, 0..) |avatar, i| {
            if (i < ids.len) ids[i] = avatar.id;
        }
        std.log.info("STARWARD LINEUP {} node {}: buff {} avatars {any}", .{ challenge_id, node, info.buff_id, ids });
    }
}

pub fn onStartChallengeTierce(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartChallengeTierceCsReq, allocator);
    defer req.deinit();
    std.log.debug("REQ CHALLENGE ID: {}, IS SINGLE STAGE: {}, STAGE INDEX: {}", .{ req.challenge_id, req.is_single_stage, req.stage_index });

    const C = Logic.Challenge();
    C.resetChallengeState();
    C.SetChallengeID(req.challenge_id);
    C.SetKind(.tierce);
    // A full run starts at the first node. A single-node start (all the floor list offers once a floor is cleared,
    // as MoC shows it) is played on from the chosen node too, so its settle screen offers the next node.
    C.SetTierceRun(if (req.is_single_stage) req.stage_index else 0, false);
    TierceManager.seedEarlierNodes(req.challenge_id, C.TierceStage(), C.TierceResults());
    if (req.is_single_stage == false) {
        logTierceLineups(req.challenge_id, req.stage_info_list.items);
        try TierceManager.setLineups(req.challenge_id, req.stage_info_list.items);
    }

    var rsp = protocol.StartChallengeTierceScRsp.init(allocator);
    const entered = enterTierceStage(session, allocator, C.TierceStage()) catch |err| {
        std.log.err("failed to start tierce challenge {} stage {}: {}", .{ req.challenge_id, req.stage_index, err });
        C.resetChallengeState();
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdStartChallengeTierceScRsp, rsp);
    };
    rsp.retcode = 0;
    rsp.scene = entered.scene;
    rsp.cur_tierce_challenge = entered.info;
    C.SetChallenge();
    try session.send(CmdID.CmdStartChallengeTierceScRsp, rsp);
    try sendAnchorMoves(session, &entered.scene);
}

// Asked by the client after the single-node sync of a cleared node.
pub fn onStartNextChallengeTierce(session: *Session, _: *const Packet, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var rsp = protocol.StartNextChallengeTierceScRsp{ .retcode = 0 };
    const stage = C.TierceStage();
    // A failed floor (a lost node, or the shared cycles spent) has no next node.
    if (C.GetKind() != .tierce or C.GetStatus() != .doing or C.TierceSingle() or stage + 1 >= tierce_nodes) {
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdLHAKNKHBLBI, rsp);
    }
    const entered = enterTierceStage(session, allocator, stage + 1) catch |err| {
        std.log.err("failed to enter tierce challenge {} stage {}: {}", .{ C.GetChallengeID(), stage + 1, err });
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdLHAKNKHBLBI, rsp);
    };
    C.SetStatus(.doing);
    rsp.scene = entered.scene;
    rsp.cur_tierce_challenge = entered.info;
    try session.send(CmdID.CmdLHAKNKHBLBI, rsp);
    try sendAnchorMoves(session, &entered.scene);
}

// Fights the node in progress again; what it had banked is dropped.
pub fn onReStartChallengeTierce(session: *Session, _: *const Packet, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var rsp = protocol.ReStartChallengeTierceScRsp{ .retcode = 0 };
    if (C.GetKind() != .tierce) {
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdJMPJCAPKNGI, rsp);
    }
    const stage = C.TierceStage();
    C.TierceResults()[stage] = .{};
    const entered = enterTierceStage(session, allocator, stage) catch |err| {
        std.log.err("failed to restart tierce challenge {} stage {}: {}", .{ C.GetChallengeID(), stage, err });
        rsp.retcode = retcodeOf(.RET_CHALLENGE_NOT_EXIST);
        return session.send(CmdID.CmdJMPJCAPKNGI, rsp);
    };
    C.SetStatus(.doing);
    rsp.scene = entered.scene;
    try session.send(CmdID.CmdJMPJCAPKNGI, rsp);
    try sendAnchorMoves(session, &entered.scene);
}

// The node settle screen closing; nothing to hand over.
pub fn onConfirmChallengeTierceStageSettle(session: *Session, _: *const Packet, _: Allocator) !void {
    try session.send(CmdID.CmdOKEDFNJJGHB, protocol.ConfirmChallengeTierceStageSettleScRsp{ .retcode = 0 });
}

fn tierceStageData(allocator: Allocator, stage: u32) protocol.ChallengeTierceStageData {
    const result = Logic.Challenge().TierceResults()[stage];
    var data = protocol.ChallengeTierceStageData.init(allocator);
    data.stage_index = stage;
    data.end_status = @enumFromInt(@as(i32, @intCast(result.end_status)));
    data.score_id = result.score;
    // Unnamed in our 4.6.51 protocol; CapySR's 4.6.51 proto: 3 cycles, 5 downed characters.
    data.INLLMKEDGLC = result.cycles;
    data.IBECKONIICF = result.deaths;
    return data;
}

// The stars the run in progress holds so far (all of its nodes, the record's earlier ones on a later-node start).
// Mid-run only the floor's own targets: its Starward target is judged on the passed floor, as CapySR leaves it out.
fn appendRunTargets(list: *ArrayList(u32), floor_passed: bool) !void {
    const C = Logic.Challenge();
    const conf = TierceManager.configOf(C.GetChallengeID()) orelse return;
    for (TierceManager.metTargets(conf, TierceManager.runTotals(C.TierceResults())).constSlice()) |id| {
        if (!floor_passed and id == conf.tierce_target_id) continue;
        try list.append(id);
    }
}

// A cleared node that is not the last one; the client then asks for the next node itself.
fn sendTierceStageSync(session: *Session, stage: u32, allocator: Allocator) !void {
    var single = protocol.JCKGBFJJFFC.init(allocator);
    single.PAIAEPJIDPE = tierceStageData(allocator, stage);
    try appendRunTargets(&single.finished_target_list, false);
    try session.send(CmdID.CmdDOPHNDHILPA, protocol.ChallengeTierceScNotify{ .MMCGBGDJIPN = .{ .IANBCDJPDJF = single } });
}

// The end of a run: every node's result and the floor's totals.
fn sendTierceFloorSync(session: *Session, passed: bool, allocator: Allocator) !void {
    const C = Logic.Challenge();
    const challenge_id = C.GetChallengeID();
    var all = protocol.GEKNAKDAMJF.init(allocator);
    all.challenge_id = challenge_id;
    all.is_passed = passed;
    var record = protocol.ChallengeTierceRecord{};
    for (C.TierceResults(), 0..) |result, i| {
        try all.GBMBAHHDONN.append(tierceStageData(allocator, @intCast(i)));
        // Unnamed in our 4.6.51 protocol; ppSR's and CapySR's 4.6.51 protos: 15 used_cycle_count, 7 total_score.
        record.EJEDODFFABI +|= result.cycles;
        record.DJEIMGGHMGM +|= result.score;
    }
    all.EGEHLOPFELK = record;
    // A failed floor earns no stars.
    if (passed) try appendRunTargets(&all.finished_target_list, true);
    try session.send(CmdID.CmdDOPHNDHILPA, protocol.ChallengeTierceScNotify{ .MMCGBGDJIPN = .{ .DFNNKENBOEN = all } });
    if (passed) {
        if (ChallengeManager.findChallengeConfig(challenge_id - 1)) |conf| {
            try session.send(CmdID.CmdDOPHNDHILPA, protocol.ChallengeTierceScNotify{ .MMCGBGDJIPN = .{ .HNHCFJJNJCE = .{ .MGLLKBNFKFG = conf.group_id } } });
        }
    }
}

// A fight in a Starward run has ended: a cleared node that is not the last is synced on its own, and the last node
// or a loss ends the run with the whole floor.
fn onTierceBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (!C.ChallengeMode() or C.GetStatus() != .doing) return;
    if (req.stage_id != 0 and req.stage_id != C.GetChallengeStageID()) return;
    // Backing out of the fight is not losing the node; the client stays in the arena.
    if (req.end_status != .BATTLE_END_WIN and req.end_status != .BATTLE_END_LOSE) return;

    const stage = @min(C.TierceStage(), tierce_nodes - 1);
    const mode = ChallengeManager.challengeModeOf(C.GetChallengeID());
    const turn_limit = if (req.stt) |stt| stt.end_reason == .BATTLE_END_REASON_TURN_LIMIT else false;
    // PF/AS nodes end when the cycles run out; that finishes the node rather than failing it.
    const cleared = req.end_status == .BATTLE_END_WIN or (mode != 0 and turn_limit);
    const end_status: protocol.BattleEndStatus = if (cleared) .BATTLE_END_WIN else .BATTLE_END_LOSE;
    C.TierceResults()[stage] = .{
        .end_status = @intCast(@intFromEnum(end_status)),
        .score = if (mode != 0) nodeScore(req, mode, stage + 1) else 0,
        .cycles = if (req.stt) |stt| stt.round_cnt else 0,
        .deaths = if (req.stt) |stt| downedAvatars(&stt) else 0,
    };
    const last = C.TierceSingle() or stage + 1 >= tierce_nodes;
    const result = C.TierceResults()[stage];
    std.log.info("CHALLENGE TIERCE {} NODE {}/3 {s} (cycles {}, score {}, downed {})", .{
        C.GetChallengeID(),
        stage + 1,
        if (cleared) "CLEARED" else "FAILED",
        result.cycles,
        result.score,
        result.deaths,
    });

    // A MoC floor whose shared cycles are spent ends here: there are none left to fight the next node with.
    const out_of_cycles = cleared and !last and (TierceManager.cyclesLeft(C.GetChallengeID(), C.TierceResults()) orelse 1) == 0;
    if (cleared and !last and !out_of_cycles) return sendTierceStageSync(session, stage, allocator);
    C.SetStatus(if (cleared and !out_of_cycles) .finish else .failed);
    const passed = cleared and stage + 1 >= tierce_nodes;
    if (passed) {
        const totals = TierceManager.runTotals(C.TierceResults());
        std.log.info("CHALLENGE TIERCE {} PASSED: cycles {}, score {}, downed {}", .{ C.GetChallengeID(), totals.cycles, totals.score, totals.deaths });
        TierceManager.recordPassedRun(C.GetChallengeID(), C.TierceResults());
    }
    try sendTierceFloorSync(session, passed, allocator);
}

// Characters the fight knocked down, revived or not.
fn downedAvatars(stt: *const protocol.BattleStatistics) u32 {
    var count: u32 = 0;
    for (stt.battle_avatar_list.items) |avatar| {
        const down = avatar.die_times > 0 or if (avatar.avatar_status) |status| status.left_hp <= 0 else false;
        if (down) count += 1;
    }
    return count;
}

pub fn onSetChallengeTierceLineup(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetChallengeTierceLineupCsReq, allocator);
    defer req.deinit();
    logTierceLineups(req.challenge_id, req.stage_info_list.items);
    try TierceManager.setLineups(req.challenge_id, req.stage_info_list.items);
    try session.send(CmdID.CmdSetChallengeTierceLineupScRsp, protocol.SetChallengeTierceLineupScRsp{
        .retcode = 0,
    });
}
