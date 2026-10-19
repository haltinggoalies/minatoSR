const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const OverrideManager = @import("../manager/override_mgr.zig");

const Allocator = std.mem.Allocator;

const usage =
    \\/debug specific <stage id> - the next Calyx/overworld battle is that stage (resources/StageConfig.json)
    \\/debug monster <monster id> [monster id...] - the next battle is one wave of these (at most 5)
    \\/debug off - cancel
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return status(session, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "off")) {
        OverrideManager.clearNextBattle();
        return commandhandler.sendMessage(session, "Next battle is config.json's again.", allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "specific")) {
        const tok = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        const stage_id = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
        OverrideManager.setNextStage(stage_id) catch {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Stage {d} is not in resources/StageConfig.json.", .{stage_id}), allocator);
        };
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "The next battle is stage {d}.", .{stage_id}), allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "monster")) {
        var ids: [OverrideManager.max_wave_monsters + 1]u32 = undefined;
        var len: usize = 0;
        while (tokens.next()) |tok| {
            if (len == ids.len) break;
            ids[len] = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
            len += 1;
        }
        OverrideManager.setNextMonsters(ids[0..len]) catch |err| {
            const msg = switch (err) {
                error.TooManyMonsters => "At most 5 monsters.",
                else => "Every monster must appear in some stage of resources/StageConfig.json.",
            };
            return commandhandler.sendMessage(session, msg, allocator);
        };
        return commandhandler.sendMessage(session, "The next battle is one wave of those monsters.", allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn status(session: *Session, allocator: Allocator) !void {
    const text = switch (OverrideManager.nextBattle()) {
        .none => "Next battle: config.json's.",
        .stage => |id| try std.fmt.allocPrint(allocator, "Next battle: stage {d}.", .{id}),
        .monsters => |m| blk: {
            var list = std.ArrayList(u8).init(allocator);
            try list.writer().writeAll("Next battle: monsters");
            for (m.ids[0..m.len]) |id| try list.writer().print(" {d}", .{id});
            break :blk list.items;
        },
    };
    try commandhandler.sendMessage(session, text, allocator);
}
