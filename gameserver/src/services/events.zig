const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const PrefsManager = @import("../manager/prefs_mgr.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.events);

const activity_config = &ConfigManager.global_game_config_cache.activity_config;

pub fn onGetActivity(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetActivityScheduleConfigScRsp.init(allocator);
    var activ_list = protocol.ActivityScheduleData.init(allocator);
    //challenge mode pannel : 2100101
    for (activity_config.activity_config.items) |activityConf| {
        if (activityConf.panel_id != 30002) {
            activ_list.panel_id = activityConf.activity_id;
            for (activityConf.activity_module_list.items) |id| {
                activ_list.begin_time = 1664308800;
                activ_list.end_time = 4294967295;
                activ_list.activity_id = id;
                try rsp.schedule_data.append(activ_list);
            }
        }
    }
    rsp.retcode = 0;
    try session.send(CmdID.CmdGetActivityScheduleConfigScRsp, rsp);
}

pub fn onGetAllServerPrefsData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetAllServerPrefsDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (PrefsManager.all()) |entry| {
        try rsp.server_prefs_list.append(.{ .server_prefs_id = entry.id, .data = .{ .Const = entry.data } });
    }
    try session.send(CmdID.CmdGetAllServerPrefsDataScRsp, rsp);
}

pub fn onGetServerPrefsData(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetServerPrefsDataCsReq, allocator);
    defer req.deinit();
    // An id with nothing saved gets an entry with only the id.
    try session.send(CmdID.CmdGetServerPrefsDataScRsp, protocol.GetServerPrefsDataScRsp{
        .retcode = 0,
        .server_prefs = .{
            .server_prefs_id = req.server_prefs_id,
            .data = if (PrefsManager.find(req.server_prefs_id)) |data| .{ .Const = data } else .Empty,
        },
    });
}

pub fn onUpdateServerPrefs(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.UpdateServerPrefsCsReq, allocator);
    defer req.deinit();
    const prefs = req.server_prefs orelse {
        try session.send(CmdID.CmdUpdateServerPrefsScRsp, protocol.UpdateServerPrefsScRsp{ .retcode = 0 });
        return;
    };
    var retcode: u32 = 0;
    PrefsManager.put(prefs.server_prefs_id, prefs.data.getSlice()) catch |err| {
        log.warn("server prefs {} not saved: {s}", .{ prefs.server_prefs_id, @errorName(err) });
        retcode = @intCast(@intFromEnum(protocol.Retcode.RET_REQ_PARA_INVALID));
    };
    try session.send(CmdID.CmdUpdateServerPrefsScRsp, protocol.UpdateServerPrefsScRsp{
        .retcode = retcode,
        .server_prefs_id = prefs.server_prefs_id,
    });
}
