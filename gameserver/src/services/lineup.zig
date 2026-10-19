const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const SceneManager = @import("../manager/scene_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const config = &ConfigManager.global_game_config_cache.game_config;

fn retcodeOf(code: protocol.Retcode) u32 {
    return @intCast(@intFromEnum(code));
}
fn presetRetcode(err: PresetManager.Error) u32 {
    return retcodeOf(switch (err) {
        error.InvalidIndex => .RET_LINEUP_INVALID_INDEX,
        error.EmptyLineup => .RET_LINEUP_IS_EMPTY,
        error.InvalidName => .RET_LINEUP_NAME_FORMAT_ERROR,
        error.InvalidSlot => .RET_LINEUP_NOT_VALID_LEADER,
    });
}

// SyncLineupNotify for one preset; its index tells the client which team it is.
fn sendPresetLineup(session: *Session, index: u32, allocator: Allocator) !void {
    var sync = protocol.SyncLineupNotify.init(allocator);
    sync.lineup = try LineupManager.buildPresetLineup(allocator, index);
    try session.send(CmdID.CmdSyncLineupNotify, sync);
}

// Set when config.json is applied during a challenge, which sends no presets; they go out once it is left.
var presets_unsent = false;

pub fn sendAllPresets(session: *Session, allocator: Allocator) !void {
    presets_unsent = false;
    var sync = protocol.SyncAllPresetLineupNotify.init(allocator);
    sync.cur_index = PresetManager.curIndex();
    try LineupManager.buildAllPresets(allocator, &sync.lineup_list);
    try session.send(CmdID.CmdSyncAllPresetLineupNotify, sync);
}
pub fn markPresetsUnsent() void {
    presets_unsent = true;
}
pub fn sendUnsentPresets(session: *Session, allocator: Allocator) !void {
    if (presets_unsent) try sendAllPresets(session, allocator);
}

// Swaps the overworld party entities if the current team's members are no longer those of `old_team`.
pub fn sendPartyRefresh(session: *Session, old_team: PresetManager.Team, allocator: Allocator) !void {
    const notify = (try SceneManager.createPartyRefresh(allocator, old_team, PresetManager.curTeam())) orelse return;
    try session.send(CmdID.CmdSceneGroupRefreshScNotify, notify);
}
// A swap made before the client had reported where the party stands goes out with its first move.
pub fn sendPendingPartyRefresh(session: *Session, allocator: Allocator) !void {
    const notify = (try SceneManager.pendingPartyRefresh(allocator)) orelse return;
    try session.send(CmdID.CmdSceneGroupRefreshScNotify, notify);
}

pub fn onGetCurLineupData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    const lineup = try lineup_mgr.createLineup();
    try session.send(CmdID.CmdGetCurLineupDataScRsp, protocol.GetCurLineupDataScRsp{
        .retcode = 0,
        .lineup = lineup,
    });
}

pub fn onGetAllLineupData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetAllLineupDataScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_index = PresetManager.curIndex();
    try LineupManager.buildAllPresets(allocator, &rsp.lineup_list);
    presets_unsent = false;
    try session.send(CmdID.CmdGetAllLineupDataScRsp, rsp);
}

pub fn onSwitchLineupIndex(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SwitchLineupIndexCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SwitchLineupIndexScRsp{ .index = req.index, .retcode = 0 };
    // A challenge scene holds the challenge team, not a preset.
    if (Logic.Challenge().ChallengeMode()) {
        rsp.retcode = retcodeOf(.RET_LINEUP_NOT_ALLOW_EDIT);
        return session.send(CmdID.CmdSwitchLineupIndexScRsp, rsp);
    }
    const old_index = PresetManager.curIndex();
    const old_team = PresetManager.curTeam();
    // Only the current preset gets the stand-in team, so the one being left may now show nobody.
    const left_stand_in = PresetManager.curIsStandIn() and req.index != old_index;
    PresetManager.switchTo(req.index) catch |err| {
        rsp.retcode = presetRetcode(err);
        return session.send(CmdID.CmdSwitchLineupIndexScRsp, rsp);
    };
    PresetManager.save();
    try sendPartyRefresh(session, old_team, allocator);
    if (left_stand_in) try sendAllPresets(session, allocator);
    try sendPresetLineup(session, req.index, allocator);
    try session.send(CmdID.CmdSwitchLineupIndexScRsp, rsp);
}

pub fn onChangeLineupLeader(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.ChangeLineupLeaderCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.ChangeLineupLeaderScRsp{ .slot = req.slot, .retcode = 0 };
    if (Logic.Challenge().ChallengeMode()) {
        Logic.Challenge().SetLeaderSlot(req.slot);
    } else if (PresetManager.setLeader(req.slot)) |_| {
        PresetManager.save();
    } else |err| {
        rsp.retcode = presetRetcode(err);
    }
    try session.send(CmdID.CmdChangeLineupLeaderScRsp, rsp);
}

fn slotLessThan(_: void, a: protocol.LineupSlotData, b: protocol.LineupSlotData) bool {
    return a.slot < b.slot;
}

pub fn onReplaceLineup(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.ReplaceLineupCsReq, allocator);
    defer req.deinit();

    // Slot order; a stable sort keeps the list order when the client leaves the slots unset.
    std.sort.insertion(protocol.LineupSlotData, req.lineup_slot_list.items, {}, slotLessThan);
    var ids = std.ArrayList(u32).init(allocator);
    defer ids.deinit();
    for (req.lineup_slot_list.items) |ok| {
        try ids.append(ok.id);
    }
    var rsp = protocol.SyncLineupNotify.init(allocator);
    var retcode: u32 = 0;
    switch (req.extra_lineup_type) {
        // Challenge team edits are remembered for single-node challenge starts.
        .LINEUP_CHALLENGE, .LINEUP_CHALLENGE_2 => {
            const node: u32 = if (req.extra_lineup_type == .LINEUP_CHALLENGE) 1 else 2;
            Logic.Challenge().SaveLineup(node, Logic.Challenge().NodeLineup.fromSlice(ids.items));
            var lineup_manager = LineupManager.ChallengeLineupManager.init(allocator);
            rsp.lineup = try lineup_manager.createNodeLineup(ids.items, node);
        },
        // One of the team presets. Story and virtual lineups are only echoed.
        .LINEUP_NONE => if (!req.is_virtual and req.game_story_line_id == 0) {
            if (req.index >= PresetManager.max_presets) {
                return session.send(CmdID.CmdReplaceLineupScRsp, protocol.ReplaceLineupScRsp{
                    .retcode = retcodeOf(.RET_LINEUP_INVALID_INDEX),
                });
            }
            const old_team = PresetManager.curTeam();
            if (PresetManager.replace(req.index, ids.items, req.leader_slot)) |_| {
                PresetManager.save();
                if (req.index == PresetManager.curIndex() and !Logic.Challenge().ChallengeMode()) {
                    try sendPartyRefresh(session, old_team, allocator);
                }
            } else |err| {
                retcode = presetRetcode(err);
            }
            // Also sent when the edit is refused, so the client puts the team back.
            rsp.lineup = try LineupManager.buildPresetLineup(allocator, req.index);
        } else {
            rsp.lineup = try LineupManager.buildLineup(allocator, ids.items, null);
        },
        else => rsp.lineup = try LineupManager.buildLineup(allocator, ids.items, req.extra_lineup_type),
    }
    try session.send(CmdID.CmdSyncLineupNotify, rsp);
    try session.send(CmdID.CmdReplaceLineupScRsp, protocol.ReplaceLineupScRsp{
        .retcode = retcode,
    });
}

pub fn onSetLineupName(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetLineupNameCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SetLineupNameScRsp{ .index = req.index, .retcode = 0 };
    const new_name = req.name.getSlice();
    if (PresetManager.rename(req.index, new_name)) |_| {
        PresetManager.save();
        // The request's string dies with the packet; the stored copy does not.
        rsp.name = .{ .Const = PresetManager.presetName(req.index) };
    } else |err| {
        rsp.retcode = if (err == error.InvalidName and !std.unicode.utf8ValidateSlice(new_name))
            retcodeOf(.RET_LINEUP_NAME_UTF8_ERROR)
        else
            presetRetcode(err);
    }
    try session.send(CmdID.CmdSetLineupNameScRsp, rsp);
}

// Marks a preset as a favourite; MarkPresetLineupScRsp (4.5.54: SetTeamFavourite) is its reply.
pub fn onMarkPresetLineup(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.MarkPresetLineupCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.MarkPresetLineupScRsp{ .index = req.index, .IECKKCHJMLP = req.IECKKCHJMLP, .retcode = 0 };
    if (PresetManager.setFavourite(req.index, req.IECKKCHJMLP)) |_| {
        PresetManager.save();
    } else |err| {
        rsp.retcode = presetRetcode(err);
    }
    try session.send(CmdID.CmdMarkPresetLineupScRsp, rsp);
}

// Every character the team editor may pick from, once per base id.
pub fn onGetLineupAvatarData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetLineupAvatarDataScRsp.init(allocator);
    rsp.retcode = 0;
    outer: for (config.avatar_config.items) |avatarConf| {
        const base_id = PresetManager.baseId(avatarConf.id);
        for (rsp.avatar_data_list.items) |data| {
            if (data.id == base_id) continue :outer;
        }
        try rsp.avatar_data_list.append(.{ .id = base_id, .hp = 10000, .avatar_type = .AVATAR_FORMAL_TYPE });
    }
    try session.send(CmdID.CmdGetLineupAvatarDataScRsp, rsp);
}
