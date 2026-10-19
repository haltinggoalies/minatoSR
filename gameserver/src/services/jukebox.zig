const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.jukebox);

// The jukebox: every track of resources/BackGroundMusic.json is unlocked, and the one last played is kept in
// profile.json (0 = the game's own music).
const music_config = &ConfigManager.global_game_config_cache.background_music_config;

fn curTrack() u32 {
    const saved = ProfileStore.get().jukebox_track;
    return if (music_config.find(saved) != null) saved else 0;
}

// The now-playing state for track `id`.
fn nowPlaying(allocator: Allocator, id: u32) protocol.MNCBEDBDDHL {
    var state = protocol.MNCBEDBDDHL.init(allocator);
    state.JKNLCEEDAHJ = .{ .id = id };
    return state;
}

pub fn onGetJukeboxData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetJukeboxDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (music_config.tracks.items) |track| {
        try rsp.IOKAJIBHLMP.append(.{ .id = track.id, .group_id = track.group_id, .BIMDKNLMICG = true });
    }
    rsp.GFFOBALDBPM = nowPlaying(allocator, curTrack());
    try session.send(CmdID.CmdGetJukeboxDataScRsp, rsp);
}

pub const PlayRequest = struct {
    id: u32,
    // The request's MNCBEDBDDHL, re-encoded, when it came in that layout.
    state: ?[]u8 = null,
};

// Which layout the 4.6.51 client sends for 3131 is not known yet, so the first byte decides: 0x58 is FKLMGEFILDI
// (field 11, the track id), 0x6A is PlayBackGroundMusicCsReq (field 13, an MNCBEDBDDHL whose JKNLCEEDAHJ.id is the
// track). Anything else is null.
pub fn parsePlay(allocator: Allocator, body: []const u8) !?PlayRequest {
    if (body.len == 0) return null;
    switch (body[0]) {
        0x58 => {
            const req = try protocol.FKLMGEFILDI.decode(body, allocator);
            defer req.deinit();
            return .{ .id = req.JKFCKJNHLHI };
        },
        0x6A => {
            const req = try protocol.PlayBackGroundMusicCsReq.decode(body, allocator);
            defer req.deinit();
            const state = req.IKJNIKIGFLF orelse return null;
            const track = state.JKNLCEEDAHJ orelse return null;
            return .{ .id = track.id, .state = try state.encode(allocator) };
        },
        else => return null,
    }
}

// The 3187 reply both decoders read: EGDFPDHNOKO takes field 8 (the track id), PlayBackGroundMusicScRsp field 14
// (the state), and each skips the other's field. retcode 0 is left out, as protobuf does.
pub fn encodePlayReply(allocator: Allocator, id: u32, state: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.append(8 << 3); // field 8, varint
    try appendVarint(&out, id);
    try out.append(14 << 3 | 2); // field 14, length-delimited
    try appendVarint(&out, state.len);
    try out.appendSlice(state);
    return out.toOwnedSlice();
}
fn appendVarint(out: *std.ArrayList(u8), value: u64) !void {
    var v = value;
    while (v >= 0x80) : (v >>= 7) try out.append(@as(u8, @truncate(v)) | 0x80);
    try out.append(@as(u8, @truncate(v)));
}

// Session.send encodes a message; this one is encoded already.
const RawBody = struct {
    bytes: []const u8,
    pub fn encode(self: RawBody, allocator: Allocator) ![]u8 {
        return allocator.dupe(u8, self.bytes);
    }
};

var logged_play_body = false;

pub fn onPlayBackGroundMusic(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    // Once per run, to see which layout the real client sends.
    if (!logged_play_body) {
        logged_play_body = true;
        log.info("first PlayBackGroundMusicCsReq body: {}", .{std.fmt.fmtSliceHexLower(packet.body)});
    }
    const request = parsePlay(allocator, packet.body) catch |err| blk: {
        log.warn("PlayBackGroundMusicCsReq could not be read: {s}", .{@errorName(err)});
        break :blk null;
    };
    if (request) |r| {
        const valid = r.id == 0 or music_config.find(r.id) != null;
        if (valid and r.id != ProfileStore.get().jukebox_track) ProfileStore.set("jukebox_track", r.id);
    }
    const id = curTrack();
    // The client's own state goes back when it asked for the track that is now playing.
    const echoed: ?[]const u8 = if (request) |r| (if (r.id == id) r.state else null) else null;
    const state = echoed orelse try nowPlaying(allocator, id).encode(allocator);
    try session.send(CmdID.CmdPlayBackGroundMusicScRsp, RawBody{ .bytes = try encodePlayReply(allocator, id, state) });
}

// 3159 (FKLMGEFILDI) -> 3118 (EGDFPDHNOKO): what the pair is for is not known; the track id is echoed.
pub fn onEchoTrack(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.FKLMGEFILDI, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdEGDFPDHNOKO, protocol.EGDFPDHNOKO{
        .JKFCKJNHLHI = req.JKFCKJNHLHI,
        .retcode = 0,
    });
}

// Every track is unlocked already; the known ones asked for are echoed as unlocked.
pub fn onUnlockBackGroundMusic(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.UnlockBackGroundMusicCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.UnlockBackGroundMusicScRsp.init(allocator);
    rsp.retcode = 0;
    for (req.LIGKEOLPFBE.items) |id| {
        const track = music_config.find(id) orelse continue;
        try rsp.IOKAJIBHLMP.append(.{ .id = track.id, .group_id = track.group_id, .BIMDKNLMICG = true });
        try rsp.BPFGBEBPEDP.append(id);
    }
    try session.send(CmdID.CmdUnlockBackGroundMusicScRsp, rsp);
}

test "both 3131 layouts give the track" {
    const allocator = std.testing.allocator;
    // FKLMGEFILDI {JKFCKJNHLHI (11) = 210005}
    const flat = (try parsePlay(allocator, &[_]u8{ 0x58, 0xD5, 0xE8, 0x0C })).?;
    try std.testing.expectEqual(@as(u32, 210005), flat.id);
    try std.testing.expect(flat.state == null);
    // PlayBackGroundMusicCsReq {IKJNIKIGFLF (13) = {JKNLCEEDAHJ (1) = {id (1) = 210005}}}
    const nested = (try parsePlay(allocator, &[_]u8{ 0x6A, 0x06, 0x0A, 0x04, 0x08, 0xD5, 0xE8, 0x0C })).?;
    defer allocator.free(nested.state.?);
    try std.testing.expectEqual(@as(u32, 210005), nested.id);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x04, 0x08, 0xD5, 0xE8, 0x0C }, nested.state.?);

    try std.testing.expect((try parsePlay(allocator, &[_]u8{})) == null);
    try std.testing.expect((try parsePlay(allocator, &[_]u8{ 0x07, 0x01 })) == null);
    if (parsePlay(allocator, &[_]u8{0x58})) |_| return error.TestUnexpectedResult else |_| {}
}

test "the 3187 reply reads as both EGDFPDHNOKO and PlayBackGroundMusicScRsp" {
    const allocator = std.testing.allocator;
    const state = [_]u8{ 0x0A, 0x04, 0x08, 0xD5, 0xE8, 0x0C };
    const body = try encodePlayReply(allocator, 210005, &state);
    defer allocator.free(body);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x40, 0xD5, 0xE8, 0x0C, 0x72, 0x06 } ++ state, body);

    const as_id = try protocol.EGDFPDHNOKO.decode(body, allocator);
    defer as_id.deinit();
    try std.testing.expectEqual(@as(u32, 210005), as_id.JKFCKJNHLHI);
    try std.testing.expectEqual(@as(u32, 0), as_id.retcode);
    const as_state = try protocol.PlayBackGroundMusicScRsp.decode(body, allocator);
    defer as_state.deinit();
    try std.testing.expectEqual(@as(u32, 210005), as_state.GFFOBALDBPM.?.JKNLCEEDAHJ.?.id);
}
