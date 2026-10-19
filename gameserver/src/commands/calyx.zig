const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const OverrideManager = @import("../manager/override_mgr.zig");

const Allocator = std.mem.Allocator;

const usage =
    \\/calyx on - Sync: every Calyx, Cavern, Echo of War, Stagnant Shadow and overworld monster fights config.json's battle
    \\/calyx off - Original: each fights its own monsters
    \\/calyx lineup <avatar id> [avatar id...] - battle team for Calyx and overworld fights (8001/1001 = current path)
    \\/calyx lineup reset - back to the current team
    \\/calyx modify <wave> <monster> <hp> - HP of one config.json monster (wave and monster count from 1)
    \\/calyx reset - clear the team and every HP change
;
const sync_text = "Calyx mode: Sync. Every Calyx, Cavern of Corrosion, Echo of War, Stagnant Shadow and overworld monster fights config.json's battle.";
const original_text = "Calyx mode: Original. Every Calyx, Cavern of Corrosion, Echo of War, Stagnant Shadow and overworld monster fights its own stage (/calyx on for config.json's battle).";

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return status(session, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "lineup")) return lineup(session, &tokens, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "modify")) return modify(session, &tokens, allocator);
    // As in March7thHoney: on = the SRTools battle, off = the Calyx's own (and here the overworld monsters' own too).
    // Kept in profile.json.
    if (std.ascii.eqlIgnoreCase(mode, "on")) {
        OverrideManager.setCalyxSync(true);
        return commandhandler.sendMessage(session, sync_text, allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "off")) {
        OverrideManager.setCalyxSync(false);
        return commandhandler.sendMessage(session, original_text, allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "reset")) {
        OverrideManager.clearLineup();
        OverrideManager.clearHp();
        return commandhandler.sendMessage(session, "Calyx team and HP changes cleared.", allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn status(session: *Session, allocator: Allocator) !void {
    var text = std.ArrayList(u8).init(allocator);
    const w = text.writer();
    try w.writeAll(if (OverrideManager.calyxSync()) sync_text else original_text);
    if (OverrideManager.lineup()) |ids| {
        try w.writeAll("\nCalyx team:");
        for (ids) |id| try w.print(" {d}", .{id});
    } else {
        try w.writeAll("\nCalyx team: current team");
    }
    const hps = OverrideManager.hpOverrides();
    if (hps.len == 0) try w.writeAll("\nHP changes: none");
    for (hps) |o| try w.print("\nWave {d} monster {d} ({d}): {d} HP", .{ o.wave, o.index, o.monster_id, o.hp });
    try commandhandler.sendMessage(session, text.items, allocator);
}

fn lineup(session: *Session, tokens: *std.mem.TokenIterator(u8, .any), allocator: Allocator) !void {
    const first = tokens.peek() orelse return commandhandler.sendMessage(session, usage, allocator);
    if (std.ascii.eqlIgnoreCase(first, "reset")) {
        OverrideManager.clearLineup();
        return commandhandler.sendMessage(session, "Calyx team cleared; battles use the current team.", allocator);
    }
    var ids: [OverrideManager.max_team + 1]u32 = undefined;
    var len: usize = 0;
    while (tokens.next()) |tok| {
        if (len == ids.len) break;
        ids[len] = std.fmt.parseInt(u32, tok, 10) catch {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "'{s}' is not an avatar id.", .{tok}), allocator);
        };
        len += 1;
    }
    OverrideManager.setLineup(ids[0..len]) catch |err| {
        const msg = switch (err) {
            error.TooManyAvatars => "A team has at most 4 avatars.",
            error.UnknownAvatar => "Every avatar must be in config.json (add it in SRTools first).",
            error.DuplicateAvatar => "An avatar is listed twice.",
            else => usage,
        };
        return commandhandler.sendMessage(session, msg, allocator);
    };
    var text = std.ArrayList(u8).init(allocator);
    try text.writer().writeAll("Calyx team set:");
    for (OverrideManager.lineup().?) |id| try text.writer().print(" {d}", .{id});
    try text.writer().writeAll(". It lasts until /calyx lineup reset or the next login.");
    try commandhandler.sendMessage(session, text.items, allocator);
}

fn modify(session: *Session, tokens: *std.mem.TokenIterator(u8, .any), allocator: Allocator) !void {
    var nums: [3]u32 = undefined;
    for (&nums) |*n| {
        const tok = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        n.* = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
    }
    const monster_id = OverrideManager.setMonsterHp(nums[0], nums[1], nums[2]) catch |err| {
        const msg = switch (err) {
            error.BadWave, error.BadIndex => try std.fmt.allocPrint(allocator, "config.json's battle has no monster {d} in wave {d}.", .{ nums[1], nums[0] }),
            error.BadHp => "HP must be between 1 and 2147483647.",
            error.TooManyOverrides => "Too many HP changes; use /calyx off first.",
            else => usage,
        };
        return commandhandler.sendMessage(session, msg, allocator);
    };
    const note = if (OverrideManager.calyxSync()) "" else " It applies in Sync mode only (/calyx on).";
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Wave {d} monster {d} ({d}) now has {d} HP.{s}", .{ nums[0], nums[1], monster_id, nums[2], note }), allocator);
}
