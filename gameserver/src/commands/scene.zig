const std = @import("std");
const protocol = @import("protocol");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const SceneManager = @import("../manager/scene_mgr.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const usage =
    \\/scene cur - plane, floor, entry and position
    \\/scene group - the 10 res.json groups nearest to the party
    \\/scene reload - enter the current scene again, at its spawn point
    \\/scene change <entry id> - go to an entry (MapEntrance)
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
    const here = SceneManager.location();
    if (std.ascii.eqlIgnoreCase(mode, "cur")) {
        if (here.entry_id == 0) return commandhandler.sendMessage(session, "No scene entered yet.", allocator);
        var text = std.ArrayList(u8).init(allocator);
        try text.writer().print("Plane {d}, floor {d}, entry {d}.", .{ here.plane_id, here.floor_id, here.entry_id });
        if (here.pos_known) {
            try text.writer().print(" Position {d:.1} {d:.1} {d:.1} m.", .{ metres(here.pos.x), metres(here.pos.y), metres(here.pos.z) });
        } else {
            try text.writer().writeAll(" Position unknown until you move.");
        }
        return commandhandler.sendMessage(session, text.items, allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "group")) {
        const groups = try SceneManager.nearbyGroups(allocator);
        if (groups.len == 0) return commandhandler.sendMessage(session, "res.json has no groups for this scene.", allocator);
        var text = std.ArrayList(u8).init(allocator);
        for (groups[0..@min(groups.len, 10)], 0..) |g, i| {
            if (i > 0) try text.append('\n');
            try text.writer().print("Group {d}: {d} props, {d} monsters, {d:.0} m", .{ g.group_id, g.props, g.monsters, g.nearest_m });
        }
        return commandhandler.sendMessage(session, text.items, allocator);
    }
    if (Logic.Challenge().ChallengeMode()) return commandhandler.sendMessage(session, "Leave the challenge first.", allocator);
    if (std.ascii.eqlIgnoreCase(mode, "reload")) {
        if (here.entry_id == 0) return commandhandler.sendMessage(session, "No scene entered yet.", allocator);
        if (!SceneManager.hasSpawn(here.entry_id)) return noSpawn(session, here.entry_id, allocator);
        try enter(session, here.entry_id, allocator);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entry {d} reloaded.", .{here.entry_id}), allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "change")) {
        const tok = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        const entry_id = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
        if (SceneManager.entryPlaneId(entry_id) == 0) {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entry {d} is not in MapEntrance.", .{entry_id}), allocator);
        }
        if (!SceneManager.hasSpawn(entry_id)) return noSpawn(session, entry_id, allocator);
        try enter(session, entry_id, allocator);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entering entry {d}.", .{entry_id}), allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn noSpawn(session: *Session, entry_id: u32, allocator: Allocator) !void {
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entry {d} has no spawn point in the resources; the game would never finish loading it.", .{entry_id}), allocator);
}

fn metres(mm: i32) f64 {
    return @as(f64, @floatFromInt(mm)) / 1000;
}

// Like /tp, but with the entry's own plane and floor, so the scene gets its props and monsters.
fn enter(session: *Session, entry_id: u32, allocator: Allocator) !void {
    var scene_manager = SceneManager.SceneManager.init(allocator);
    const scene_info = try scene_manager.createScene(SceneManager.entryPlaneId(entry_id), SceneManager.entryFloorId(entry_id), entry_id, 0);
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    const lineup = try lineup_mgr.createLineup();
    try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
        .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
        .lineup = lineup,
        .scene = scene_info,
    });
}
