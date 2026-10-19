const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const mail_id_invalid: u32 = @intCast(@intFromEnum(protocol.Retcode.RET_MAIL_MAIL_ID_INVALID));

// The server's only mail. What the player did with it (read, deleted, attachment taken) is kept in profile.json;
// taking the attachment grants nothing, items are not tracked.
const readme_id: u32 = 1;
const mail_ids = [_]u32{readme_id};

fn has(list: []const u32, id: u32) bool {
    return std.mem.indexOfScalar(u32, list, id) != null;
}
// A mail the player still has: one of ours, not deleted.
fn exists(id: u32) bool {
    return has(&mail_ids, id) and !has(ProfileStore.get().mail.deleted, id);
}

// `list` plus each id of `add` it does not have yet, in a new slice.
fn withIds(allocator: Allocator, list: []const u32, add: []const u32) ![]u32 {
    var out = try ArrayList(u32).initCapacity(allocator, list.len + add.len);
    out.appendSliceAssumeCapacity(list);
    for (add) |id| {
        if (!has(out.items, id)) out.appendAssumeCapacity(id);
    }
    return out.toOwnedSlice();
}

fn readme(allocator: Allocator) !protocol.ClientMail {
    const state = ProfileStore.get().mail;
    var mail = protocol.ClientMail.init(allocator);
    mail.sender = .{ .Const = "March 7th" };
    mail.title = .{ .Const = "Readme" };
    mail.is_read = has(state.read, readme_id);
    mail.id = readme_id;
    mail.content = .{ .Const = "MushiSR is a free and open-source software\nJoin our discord: https://discord.gg/reversedrooms\nUse https://relic-builder.vercel.app to setup relic :Đ" };
    mail.time = 1723334400;
    mail.expire_time = 17186330890;
    mail.mail_type = protocol.MailType.MAIL_TYPE_STAR;
    if (!has(state.taken, readme_id)) {
        var item_attachment = ArrayList(protocol.Item).init(allocator);
        try item_attachment.append(.{ .item_id = 1503, .num = 1 });
        mail.attachment = .{ .item_list = item_attachment };
    }
    return mail;
}

pub fn onGetMail(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetMailScRsp.init(allocator);
    if (exists(readme_id)) try rsp.mail_list.append(try readme(allocator));
    rsp.total_num = @intCast(rsp.mail_list.items.len);
    rsp.is_end = true;
    rsp.start = 0;
    rsp.retcode = 0;
    try session.send(CmdID.CmdGetMailScRsp, rsp);
}

pub fn onMarkReadMail(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.MarkReadMailCsReq, allocator);
    defer req.deinit();
    if (!exists(req.id)) {
        try session.send(CmdID.CmdMarkReadMailScRsp, protocol.MarkReadMailScRsp{ .retcode = mail_id_invalid, .id = req.id });
        return;
    }
    const state = ProfileStore.get().mail;
    if (!has(state.read, req.id)) {
        ProfileStore.set("mail", ProfileStore.MailState{
            .read = try withIds(allocator, state.read, &[_]u32{req.id}),
            .deleted = state.deleted,
            .taken = state.taken,
        });
    }
    try session.send(CmdID.CmdMarkReadMailScRsp, protocol.MarkReadMailScRsp{ .retcode = 0, .id = req.id });
}

pub fn onDelMail(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.DelMailCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.DelMailScRsp.init(allocator);
    // All or nothing: one unknown id refuses the whole request.
    for (req.id_list.items) |id| {
        if (!exists(id)) {
            rsp.retcode = mail_id_invalid;
            try session.send(CmdID.CmdDelMailScRsp, rsp);
            return;
        }
    }
    if (req.id_list.items.len > 0) {
        const state = ProfileStore.get().mail;
        ProfileStore.set("mail", ProfileStore.MailState{
            .read = state.read,
            .deleted = try withIds(allocator, state.deleted, req.id_list.items),
            .taken = state.taken,
        });
    }
    rsp.retcode = 0;
    try rsp.id_list.appendSlice(req.id_list.items);
    try session.send(CmdID.CmdDelMailScRsp, rsp);
}

pub fn onTakeMailAttachment(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.TakeMailAttachmentCsReq, allocator);
    defer req.deinit();
    const state = ProfileStore.get().mail;
    // An empty list takes every attachment still there.
    const wanted: []const u32 = if (req.mail_id_list.items.len > 0) req.mail_id_list.items else &mail_ids;
    var rsp = protocol.TakeMailAttachmentScRsp.init(allocator);
    rsp.retcode = 0;
    for (wanted) |id| {
        if (exists(id) and !has(state.taken, id) and !has(rsp.succ_mail_id_list.items, id)) {
            try rsp.succ_mail_id_list.append(id);
        }
    }
    const taken = rsp.succ_mail_id_list.items;
    if (taken.len > 0) {
        ProfileStore.set("mail", ProfileStore.MailState{
            .read = try withIds(allocator, state.read, taken),
            .deleted = state.deleted,
            .taken = try withIds(allocator, state.taken, taken),
        });
    }
    try session.send(CmdID.CmdTakeMailAttachmentScRsp, rsp);
}

test "mail id sets only grow by ids they do not have" {
    const allocator = std.testing.allocator;
    const ids = try withIds(allocator, &[_]u32{ 1, 2 }, &[_]u32{ 2, 3, 3 });
    defer allocator.free(ids);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 2, 3 }, ids);
}
