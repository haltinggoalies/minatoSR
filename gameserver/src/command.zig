const std = @import("std");
const protocol = @import("protocol");
const Session = @import("Session.zig");
const Packet = @import("Packet.zig");
const Clock = @import("utils/clock.zig");
const Login = @import("services/login.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

// MushiSR, the friend commands are typed to (GetFriendListInfo in services/chat.zig).
pub const bot_uid: u32 = 2000;
// Stripped around a typed command; the client may add a trailing NUL or line break.
pub const whitespace = " \t\r\n\x00";

const value_command = @import("./commands/value.zig");
const help_command = @import("./commands/help.zig");
const tp_command = @import("./commands/tp.zig");
const unstuck_command = @import("./commands/unstuck.zig");
const sync_command = @import("./commands/sync.zig");
const refill_command = @import("./commands/refill.zig");
const calyx_command = @import("./commands/calyx.zig");
const debug_command = @import("./commands/debug.zig");
const peak_command = @import("./commands/peak.zig");
const faketime_command = @import("./commands/faketime.zig");
const hero_command = @import("./commands/hero.zig");
const scene_command = @import("./commands/scene.zig");
const windy_command = @import("./commands/windy.zig");
const json_command = @import("./commands/json.zig");

const CommandFn = *const fn (session: *Session, args: []const u8, allocator: Allocator) anyerror!void;

const Command = struct {
    name: []const u8,
    action: []const u8,
    func: CommandFn,
};

const commandList = [_]Command{
    .{ .name = "help", .action = "", .func = help_command.handle },
    .{ .name = "test", .action = "", .func = value_command.handle },
    .{ .name = "node", .action = "", .func = value_command.challengeNode },
    .{ .name = "set", .action = "", .func = value_command.setGachaCommand },
    .{ .name = "tp", .action = "", .func = tp_command.handle },
    .{ .name = "unstuck", .action = "", .func = unstuck_command.handle },
    .{ .name = "sync", .action = "", .func = sync_command.onGenerateAndSync },
    .{ .name = "refill", .action = "", .func = refill_command.onRefill },
    .{ .name = "id", .action = "", .func = value_command.onBuffId },
    .{ .name = "funmode", .action = "", .func = value_command.FunMode },
    .{ .name = "aha", .action = "", .func = value_command.AhaBuff },
    .{ .name = "calyx", .action = "", .func = calyx_command.handle },
    .{ .name = "debug", .action = "", .func = debug_command.handle },
    .{ .name = "peak", .action = "", .func = peak_command.handle },
    .{ .name = "faketime", .action = "", .func = faketime_command.handle },
    .{ .name = "hero", .action = "", .func = hero_command.handle },
    .{ .name = "scene", .action = "", .func = scene_command.handle },
    .{ .name = "windy", .action = "", .func = windy_command.handle },
    .{ .name = "json", .action = "", .func = json_command.handle },
};

pub fn handleCommand(session: *Session, msg: []const u8, allocator: Allocator) !void {
    const text = std.mem.trim(u8, msg, whitespace);
    if (text.len < 1 or text[0] != '/') {
        return sendMessage(session, "Commands must start with a '/'", allocator);
    }

    const input = text[1..]; // Remove leading '/'
    var tokenizer = std.mem.tokenizeAny(u8, input, whitespace);
    const command = tokenizer.next() orelse return sendMessage(session, "Invalid command", allocator);
    const args = tokenizer.rest();

    // Names only: /HELP runs /help. Arguments are matched by each command.
    for (commandList) |cmd| {
        if (std.ascii.eqlIgnoreCase(cmd.name, command)) {
            return try cmd.func(session, args, allocator);
        }
    }

    return sendMessage(session, "Invalid command", allocator);
}

// A private chat line from `from` to `to`, shaped like the March7thHoney server's, which current clients
// display: field 10 (CKHPFFENOBE) is the sender and field 11 (BKOALKHDLOB) the receiver, both of kind 1.
pub fn chatMessage(allocator: Allocator, from: u32, to: u32, text: []const u8) !protocol.ChatMessageData {
    var datas = std.ArrayList(protocol.MessageChatData).init(allocator);
    try datas.append(.{
        .message_type = .MSG_TYPE_CUSTOM_TEXT,
        .chat_data = .{
            .extend_type = .{
                .message_text = .{ .Const = text },
            },
        },
    });
    return .{
        .create_time = Clock.nowSec(),
        .message_datas = datas,
        .CKHPFFENOBE = .{
            .KPOBMNLKLOK = .HCMEILLLKBD_JDOAIPKBIPE,
            .role_id = from,
        },
        .BKOALKHDLOB = .{
            .KPOBMNLKLOK = .HCMEILLLKBD_JDOAIPKBIPE,
            .role_id = to,
        },
    };
}

// A reply from MushiSR. The notify's only uid is the sender's, as in March7thHoney; it used to be the
// player's own uid, and the client showed none of these replies.
pub fn sendMessage(session: *Session, msg: []const u8, allocator: Allocator) !void {
    const text = std.mem.trimRight(u8, msg, "\r\n");
    var chat = protocol.RevcMsgScNotify.init(allocator);
    chat.chat_type = protocol.ChatType.CHAT_TYPE_PRIVATE;
    chat.to_uid = bot_uid;
    chat.recv_message_data = try chatMessage(allocator, bot_uid, Login.player_uid, text);
    try session.send(CmdID.CmdRevcMsgScNotify, chat);
}
