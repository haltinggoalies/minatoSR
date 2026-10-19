const commandhandler = @import("../command.zig");
const std = @import("std");
const Session = @import("../Session.zig");

const Allocator = std.mem.Allocator;

pub fn handle(session: *Session, _: []const u8, allocator: Allocator) !void {
    try commandhandler.sendMessage(session, "/tp to teleport, /sync to sync data from config\n", allocator);
    try commandhandler.sendMessage(session, "/refill to refill technique point after battle\n", allocator);
    try commandhandler.sendMessage(session, "/set to set gacha banner\n", allocator);
    try commandhandler.sendMessage(session, "MoC, PF, AS go from node 1 to node 2 automatically; the game's single-node option plays one node\n", allocator);
    try commandhandler.sendMessage(session, "/id to turn ON custom mode for challenge mode. /id info to check current challenge id. /id off to turn OFF\n", allocator);
    try commandhandler.sendMessage(session, "/funmode to Sillyism\n", allocator);
    try commandhandler.sendMessage(session, "/aha on or /aha off to toggle Aha helping buff in Voracity Corrosion stages.\n", allocator);
    try commandhandler.sendMessage(session, "/calyx on|off|lineup|modify|reset: Calyx and overworld fights use config.json's battle (on) or their own (off); team and monster HP\n", allocator);
    try commandhandler.sendMessage(session, "/debug specific <stage> or /debug monster <id...>: pick the next battle\n", allocator);
    try commandhandler.sendMessage(session, "/peak <season>: Anomaly Arbitration season (0 = automatic)\n", allocator);
    try commandhandler.sendMessage(session, "/faketime <YYYYMMDD>|off: server date, for challenges that show Locked\n", allocator);
    try commandhandler.sendMessage(session, "/hero gender <1|2> or /hero type <8001..8009>: Trailblazer\n", allocator);
    try commandhandler.sendMessage(session, "/scene cur|group|reload|change <entry>\n", allocator);
    try commandhandler.sendMessage(session, "/windy: send a script from the lua folder. /json: save and load configs\n", allocator);
    try commandhandler.sendMessage(session, "You can enter MoC, PF, AS via F4 menu\n", allocator);
    try commandhandler.sendMessage(session, "(If your Castorice technique enabled, you must enter battle by using Castorice's technique)\n", allocator);
}
