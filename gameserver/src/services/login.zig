const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const Logic = @import("../utils/logic.zig");
const Uid = @import("../utils/uid.zig");
const Clock = @import("../utils/clock.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const OverrideManager = @import("../manager/override_mgr.zig");
const Misc = @import("misc.zig");
const College = @import("college.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const CmdID = protocol.CmdID;

const content = [_]u32{
    200001, 200002, 200003, 200004, 200005, 200006, 200007, 200008,
    200009, 200010, 200011, 200012, 200013, 200014, 150017, 150015,
    150021, 150018, 130011, 130012, 130013, 150025, 140006, 150026,
    130014, 150034, 150029, 150035, 150041, 150039, 150045, 150057,
    150042, 150067, 150064, 150063, 150024, 171002, 150068, 150070,
    150071, 150073, 150074, 150075, 150076, 150077, 150078, 150079,
    150132, 150134, 150135,
};

// The uid PlayerGetTokenScRsp gives the player.
pub const player_uid: u32 = 1;

// True once the client has finished logging in and holds its characters and bag; config.json changes
// are pushed to it only then.
pub var logged_in: bool = false;

pub fn onPlayerGetToken(session: *Session, _: *const Packet, allocator: Allocator) !void {
    logged_in = false;
    Uid.resetInitialUid();
    Clock.resetAtLogin();
    // config.json may have changed while nobody was online; load it before the client asks for its data.
    if (ConfigManager.configFileChanged()) {
        ConfigManager.UpdateGameConfig() catch |err| std.log.err("config.json could not be loaded: {}", .{err});
    }
    var rsp = protocol.PlayerGetTokenScRsp.init(allocator);

    rsp.retcode = 0;
    rsp.uid = player_uid;

    try session.send(CmdID.CmdPlayerGetTokenScRsp, rsp);
}

// The player's basic info, the same at login and after a rename.
pub fn basicInfo(allocator: Allocator) protocol.PlayerBasicInfo {
    var basic_info = protocol.PlayerBasicInfo.init(allocator);
    basic_info.stamina = 300;
    basic_info.level = 70;
    basic_info.nickname = .{ .Const = ProfileStore.get().nickname };
    basic_info.world_level = 6;
    basic_info.mcoin = 99999990;
    basic_info.hcoin = 99999990; //Jade
    basic_info.scoin = 99999990; //Money
    return basic_info;
}

pub fn onPlayerLogin(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.PlayerLoginCsReq, allocator);
    defer req.deinit();
    // Logins always land in the overworld, so a challenge left running by a disconnect cannot be resumed.
    Logic.Challenge().resetChallengeState();
    OverrideManager.clearOnLogin();
    Misc.clearLua();
    College.clearPending();

    var rsp = protocol.PlayerLoginScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.login_random = req.login_random;
    rsp.stamina = 300;
    rsp.server_timestamp_ms = Clock.nowMs();
    rsp.basic_info = basicInfo(allocator);

    try session.send(CmdID.CmdPlayerLoginScRsp, rsp);
}

pub fn onPlayerLoginFinish(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var package_data = protocol.ContentPackageData.init(allocator);
    package_data.cur_content_id = 0;
    for (content) |id| {
        try package_data.content_package_list.append(protocol.ContentPackageInfo{
            .content_id = id,
            .status = protocol.ContentPackageStatus.ContentPackageStatus_Finished,
        });
    }
    try session.send(CmdID.CmdContentPackageSyncDataScNotify, protocol.ContentPackageSyncDataScNotify{
        .data = package_data,
    });
    try session.send(CmdID.CmdPlayerLoginFinishScRsp, protocol.PlayerLoginFinishScRsp{
        .retcode = 0,
    });
    logged_in = true;
}

pub fn onContentPackageGetData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.ContentPackageGetDataScRsp.init(allocator);
    rsp.retcode = 0;
    var package_data = protocol.ContentPackageData.init(allocator);
    package_data.cur_content_id = 0;
    for (content) |id| {
        try package_data.content_package_list.append(protocol.ContentPackageInfo{
            .content_id = id,
            .status = protocol.ContentPackageStatus.ContentPackageStatus_Finished,
        });
    }
    try session.send(CmdID.CmdContentPackageGetDataScRsp, rsp);
}

pub fn onSetClientPaused(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetClientPausedCsReq, allocator);
    defer req.deinit();

    try session.send(CmdID.CmdSetClientPausedScRsp, protocol.SetClientPausedScRsp{
        .retcode = 0,
        .paused = req.paused,
    });
}

pub fn onGetArchiveData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var data = protocol.ArchiveData.init(allocator);
    try data.archive_avatar_id_list.append(1503);
    try data.archive_missing_equipment_id_list.append(23000);
    try session.send(CmdID.CmdGetArchiveDataScRsp, protocol.GetArchiveDataScRsp{
        .retcode = 0,
        .archive_data = data,
    });
}
pub fn onGetUpdatedArchiveData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var data = protocol.ArchiveData.init(allocator);
    try data.archive_avatar_id_list.append(1503);
    try data.archive_missing_equipment_id_list.append(23000);
    try session.send(CmdID.CmdGetUpdatedArchiveDataScRsp, protocol.GetUpdatedArchiveDataScRsp{
        .retcode = 0,
        .archive_data = data,
    });
}
