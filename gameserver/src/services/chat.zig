const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const commandhandler = @import("../command.zig");
const Login = @import("login.zig");

const bot_uid = commandhandler.bot_uid;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const B64Decoder = std.base64.standard.Decoder;

const EmojiList = [_]u32{};

pub fn onGetFriendListInfo(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetFriendListInfoScRsp.init(allocator);
    rsp.retcode = 0;

    const assist_list = ArrayList(protocol.AssistSimpleInfo).init(allocator);
    //try assist_list.appendSlice(&[_]protocol.AssistSimpleInfo{
    //    .{ .pos = 0, .level = 80, .avatar_id = 1510, .dressed_skin_id = 0 },
    //    .{ .pos = 1, .level = 80, .avatar_id = 1508, .dressed_skin_id = 0 },
    //    .{ .pos = 2, .level = 80, .avatar_id = 1505, .dressed_skin_id = 0 },
    //});

    var friend = protocol.FriendSimpleInfo.init(allocator);
    friend.playing_state = .PLAYING_CHALLENGE_PEAK;
    friend.create_time = 0; //timestamp
    friend.remark_name = .{ .Const = "ReversedRooms" }; //friend_custom_nickname
    friend.is_marked = true;
    friend.player_info = protocol.PlayerSimpleInfo{
        //.personal_card = 253001,
        .signature = .{ .Const = "https://discord.gg/reversedrooms" },
        .nickname = .{ .Const = "MushiSR" },
        .level = 70,
        .uid = bot_uid,
        .head_icon = 200140,
        //.head_frame_info = .{
        //    .head_frame_expire_time = 4294967295,
        //    .head_frame_item_id = 226004,
        //},
        //.chat_bubble = 220008,
        .assist_info_list = assist_list,
        //.platform = protocol.PlatformType.PC,
        //.online_status = protocol.FriendOnlineStatus.FRIEND_ONLINE_STATUS_ONLINE,
    };
    try rsp.friend_list.append(friend);
    try session.send(CmdID.CmdGetFriendListInfoScRsp, rsp);
}
pub fn onChatEmojiList(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChatEmojiListScRsp.init(allocator);

    rsp.retcode = 0;
    try rsp.chat_emoji_list.appendSlice(&EmojiList);

    try session.send(CmdID.CmdGetChatEmojiListScRsp, rsp);
}
pub fn onPrivateChatHistory(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetPrivateChatHistoryCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.GetPrivateChatHistoryScRsp.init(allocator);

    rsp.retcode = 0;
    rsp.target_side = req.target_side;
    rsp.contact_side = bot_uid;
    try rsp.chat_message_list.appendSlice(&[_]protocol.ChatMessageData{
        try makeTextChat(allocator, bot_uid, "Use https://relic-builder.vercel.app/ to setup config"),
        try makeTextChat(allocator, bot_uid, "/help for command list"),
        try makeTextChat(allocator, bot_uid, "to use command, use '/' first"),
    });

    try session.send(CmdID.CmdGetPrivateChatHistoryScRsp, rsp);
}

pub fn onGetAiPamChatHistory(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetAiPamChatHistoryScRsp.init(allocator);

    rsp.retcode = 0;
    rsp.target_side = 1;
    try rsp.JPCMGNGNONJ.appendSlice(&[_]protocol.ChatMessageData{
        try makeTextChat(allocator, bot_uid, "Kill all nantong :Đ"),
    });

    try session.send(CmdID.CmdGetAiPamChatHistoryScRsp, rsp);
}

// A history line from `uid` to the player, in the same shape as the live command replies.
fn makeTextChat(
    allocator: Allocator,
    uid: u32,
    text: []const u8,
) !protocol.ChatMessageData {
    return commandhandler.chatMessage(allocator, uid, Login.player_uid, text);
}

// The typed text of a decoded SendMsgCsReq: "" for stickers and other non-text messages, null without chat data.
fn decodedText(req: *const protocol.SendMsgCsReq) ?[]const u8 {
    const message = req.message_datas orelse return null;
    const chat_data = message.chat_data orelse return null;
    const extend = chat_data.extend_type orelse return null;
    return switch (extend) {
        .message_text => |text| text.getSlice(),
        else => "",
    };
}

fn readVarint(buf: []const u8, i: *usize) ?u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    while (i.* < buf.len) {
        const b = buf[i.*];
        i.* += 1;
        result |= @as(u64, b & 0x7f) << shift;
        if (b & 0x80 == 0) return result;
        if (shift >= 63) return null;
        shift += 7;
    }
    return null;
}

// Fallback for a body the proto does not decode: the first length-delimited field, at any depth, that
// starts with '/' and is valid UTF-8. Stops at the first malformed field instead of reading past the end.
fn findSlashString(buf: []const u8, depth: u8) ?[]const u8 {
    if (depth > 4) return null;
    var i: usize = 0;
    while (i < buf.len) {
        const key = readVarint(buf, &i) orelse return null;
        switch (@as(u3, @truncate(key))) {
            0 => _ = readVarint(buf, &i) orelse return null,
            1 => {
                if (buf.len - i < 8) return null;
                i += 8;
            },
            5 => {
                if (buf.len - i < 4) return null;
                i += 4;
            },
            2 => {
                const len = readVarint(buf, &i) orelse return null;
                if (len > buf.len - i) return null;
                const payload = buf[i .. i + @as(usize, @intCast(len))];
                i += payload.len;
                if (payload.len > 0 and payload[0] == '/' and std.unicode.utf8ValidateSlice(payload)) return payload;
                if (findSlashString(payload, depth + 1)) |s| return s;
            },
            else => return null,
        }
    }
    return null;
}

pub fn onSendMsg(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    // The decoded text belongs to `req`, so it is kept until the command has run.
    const req: ?protocol.SendMsgCsReq = packet.getProto(protocol.SendMsgCsReq, allocator) catch |err| blk: {
        std.log.warn("SendMsgCsReq did not decode ({s}); scanning the raw body", .{@errorName(err)});
        break :blk null;
    };
    defer if (req) |r| r.deinit();
    const decoded = if (req) |*r| decodedText(r) else null;
    const text = std.mem.trim(u8, decoded orelse findSlashString(packet.body, 0) orelse "", commandhandler.whitespace);
    std.log.debug("SendMsgCsReq body: {any}, text: '{s}'", .{ packet.body, text });

    if (text.len > 0 and text[0] == '/') {
        // A failing command (bad arguments, a scene it cannot build) must not disconnect the player.
        commandhandler.handleCommand(session, text, allocator) catch |err| {
            std.log.err("command '{s}' failed: {s}", .{ text, @errorName(err) });
            commandhandler.sendMessage(session, "Command failed, see the gameserver window", allocator) catch {};
        };
    }

    var rsp = protocol.SendMsgScRsp.init(allocator);
    rsp.retcode = 0;
    try session.send(CmdID.CmdSendMsgScRsp, rsp);
}

pub fn onTriggerAiPamSpeak(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.TriggerAiPamSpeakCsReq, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdTriggerAiPamSpeakScRsp, protocol.TriggerAiPamSpeakScRsp{
        .JMPPMNAONHM = req.JMPPMNAONHM,
        .BDPIMPJOJBK = req.BDPIMPJOJBK,
        .retcode = 0,
    });
}
