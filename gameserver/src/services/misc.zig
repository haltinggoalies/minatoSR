const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Clock = @import("../utils/clock.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

// Lua the client runs on every heartbeat; it writes the watermark in the bottom-left corner ("MushiSR", one
// rainbow colour per letter) and blanks the line under it.
const script =
    \\local function setTextComponent(path, newText)
    \\    local obj = CS.UnityEngine.GameObject.Find(path)
    \\    if obj then
    \\        local textComponent = obj:GetComponentInChildren(typeof(CS.RPG.Client.LocalizedText))
    \\        if textComponent then
    \\            textComponent.text = newText
    \\        end
    \\    end
    \\end
    \\
    \\setTextComponent("UIRoot/AboveDialog/BetaHintDialog(Clone)", "<color=#FF4D4D>M</color><color=#FFA64D>u</color><color=#FFE44D>s</color><color=#5CE65C>h</color><color=#4DB8FF>i</color><color=#7A6BFF>S</color><color=#D46BFF>R</color>")
    \\setTextComponent("VersionText", "")
    \\
;

// Scripts /windy queued, each sent on one heartbeat instead of the watermark (which the next heartbeat restores),
// and the names of those sent since the last login.
pub const max_lua_queue = 8;
var lua_queue = std.ArrayList([]u8).init(std.heap.page_allocator);
var lua_sent = std.ArrayList([]u8).init(std.heap.page_allocator);

pub fn queueLua(name: []const u8, text: []const u8) !void {
    if (lua_queue.items.len >= max_lua_queue) return error.QueueFull;
    const owned = try std.heap.page_allocator.dupe(u8, text);
    errdefer std.heap.page_allocator.free(owned);
    const owned_name = try std.heap.page_allocator.dupe(u8, name);
    errdefer std.heap.page_allocator.free(owned_name);
    try lua_queue.append(owned);
    try lua_sent.append(owned_name);
}
pub fn sentLua() []const []const u8 {
    return lua_sent.items;
}
pub fn clearLua() void {
    for (lua_queue.items) |s| std.heap.page_allocator.free(s);
    for (lua_sent.items) |s| std.heap.page_allocator.free(s);
    lua_queue.clearRetainingCapacity();
    lua_sent.clearRetainingCapacity();
}

pub fn onPlayerHeartBeat(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.PlayerHeartBeatCsReq, allocator);
    defer req.deinit();
    const queued: ?[]u8 = if (lua_queue.items.len > 0) lua_queue.orderedRemove(0) else null;
    defer if (queued) |q| std.heap.page_allocator.free(q);
    const dest_buf = try allocator.dupe(u8, queued orelse script);
    const managed_str = protocol.ManagedString.move(dest_buf, allocator);

    const now_ms = Clock.nowMs();
    const download_data = protocol.ClientDownloadData{
        .version = 51,
        .time = @intCast(now_ms),
        .data = managed_str,
    };
    try session.send(CmdID.CmdPlayerHeartBeatScRsp, protocol.PlayerHeartBeatScRsp{
        .retcode = 0,
        .client_time_ms = req.client_time_ms,
        .server_time_ms = now_ms,
        .download_data = download_data,
    });
}
