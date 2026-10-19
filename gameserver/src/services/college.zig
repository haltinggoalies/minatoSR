const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const BattleManager = @import("../manager/battle_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const BattleService = @import("battle.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.college);

// Battle College: a room fights its own stage from StageConfig.json with the current team (the room's trial
// avatars are not given). Rooms passed are kept in profile.json; passing one grants nothing.
const college_config = &ConfigManager.global_game_config_cache.battle_college_config;

// The room being fought, until a battle result comes in.
const Pending = struct { id: u32, stage_id: u32 };
var pending: ?Pending = null;

// A room left without a result (a new login, or an ordinary battle started instead) must not be passed by the next
// battle's result.
pub fn clearPending() void {
    pending = null;
}

// `finished` plus `id`; null if it is there already.
fn addFinished(allocator: Allocator, finished: []const u32, id: u32) !?[]u32 {
    if (std.mem.indexOfScalar(u32, finished, id) != null) return null;
    return try std.mem.concat(allocator, u32, &[_][]const u32{ finished, &[_]u32{id} });
}

// The passed rooms the config still has.
fn appendFinished(list: *std.ArrayList(u32)) !void {
    for (ProfileStore.get().college_finished) |id| {
        if (college_config.find(id) != null) try list.append(id);
    }
}

pub fn onGetBattleCollegeData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetBattleCollegeDataScRsp.init(allocator);
    rsp.retcode = 0;
    try appendFinished(&rsp.finished_college_id_list);
    try session.send(CmdID.CmdGetBattleCollegeDataScRsp, rsp);
}

pub fn onStartBattleCollege(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartBattleCollegeCsReq, allocator);
    defer req.deinit();
    const stage = blk: {
        const room = college_config.find(req.id) orelse break :blk null;
        break :blk BattleManager.findStage(room.stage_id);
    } orelse {
        log.warn("Battle College room {} has no stage", .{req.id});
        try session.send(CmdID.CmdStartBattleCollegeScRsp, protocol.StartBattleCollegeScRsp{
            .retcode = @intCast(@intFromEnum(protocol.Retcode.RET_FAIL)),
            .id = req.id,
        });
        return;
    };
    var battle_manager = BattleManager.BattleManager.init(allocator);
    const battle = try battle_manager.createStageBattle(stage);
    pending = .{ .id = req.id, .stage_id = stage.stage_id };
    BattleService.on_battle = true;
    try session.send(CmdID.CmdStartBattleCollegeScRsp, protocol.StartBattleCollegeScRsp{
        .retcode = 0,
        .id = req.id,
        .battle_info = battle,
    });
}

// From onPVEBattleResult, before its reply: the first win of a room is saved and the client told.
pub fn onBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const room = pending orelse return;
    pending = null;
    if (req.stage_id != 0 and req.stage_id != room.stage_id) return;
    if (req.end_status != .BATTLE_END_WIN) return;
    const finished = (try addFinished(allocator, ProfileStore.get().college_finished, room.id)) orelse return;
    ProfileStore.set("college_finished", finished);
    var notify = protocol.SyncBattleCollegeDataChangeScNotify.init(allocator);
    try appendFinished(&notify.finished_college_id_list);
    try session.send(CmdID.CmdSyncBattleCollegeDataChangeScNotify, notify);
}

test "a room joins the finished list once" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try addFinished(allocator, &[_]u32{ 1, 3 }, 3)) == null);
    const grown = (try addFinished(allocator, &[_]u32{ 1, 3 }, 5)).?;
    defer allocator.free(grown);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 3, 5 }, grown);
}
