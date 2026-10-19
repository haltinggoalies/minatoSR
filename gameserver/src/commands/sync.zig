const commandhandler = @import("../command.zig");
const std = @import("std");
const Session = @import("../Session.zig");
const protocol = @import("protocol");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const Uid = @import("../utils/uid.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const Logic = @import("../utils/logic.zig");
const Battle = @import("../services/battle.zig");
const Login = @import("../services/login.zig");
const Lineup = @import("../services/lineup.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.sync);

pub fn syncItems(session: *Session, allocator: Allocator, equip_avatar: bool) !void {
    Uid.resetGlobalUidGens();
    var sync = protocol.PlayerSyncScNotify.init(allocator);
    const config = &ConfigManager.global_game_config_cache.game_config;
    for (config.avatar_config.items) |avatarConf| {
        const dress_avatar_id: u32 = if (equip_avatar) avatarConf.id else 0;
        const lc = try AvatarManager.createEquipment(avatarConf.lightcone, dress_avatar_id);
        try sync.equipment_list.append(lc);
        for (avatarConf.relics.items) |input| {
            const r = try AvatarManager.createRelic(allocator, input, dress_avatar_id);
            try sync.relic_list.append(r);
        }
    }
    if (!equip_avatar) {
        try ConfigManager.UpdateGameConfig();
        Uid.updateInitialUid();
    }
    try session.send(CmdID.CmdPlayerSyncScNotify, sync);
}
pub fn onSyncAvatar(session: *Session, _: []const u8, allocator: Allocator) !void {
    Uid.resetGlobalUidGens();
    var sync = protocol.PlayerSyncScNotify.init(allocator);
    const config = &ConfigManager.global_game_config_cache.game_config;
    var char = protocol.AvatarSync.init(allocator);
    for (Data.AllAvatars) |id| {
        const avatar = try AvatarManager.createAllAvatar(allocator, id);
        try char.avatar_list.append(avatar);
    }
    for (Data.AllAvatars) |id| {
        const avatar = try AvatarManager.createAllAvatarPathData(allocator, id);
        try char.avatar_path_data_info_list.append(avatar);
    }
    for (config.avatar_config.items) |avatarConf| {
        const avatar = try AvatarManager.createAvatar(allocator, avatarConf);
        try char.avatar_list.append(avatar);
    }
    for (config.avatar_config.items) |avatarConf| {
        const avatar = try AvatarManager.createAvatarPathData(allocator, avatarConf);
        try char.avatar_path_data_info_list.append(avatar);
    }
    sync.avatar_sync = char;
    try session.send(CmdID.CmdPlayerSyncScNotify, sync);
}

pub fn onGenerateAndSync(session: *Session, _: []const u8, allocator: Allocator) !void {
    applyConfig(session, allocator) catch |err| {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "config.json could not be loaded ({s}); nothing changed\n", .{@errorName(err)}), allocator);
    };
    try commandhandler.sendMessage(session, "Sync items with config\n", allocator);
}

// Reloads config.json and replaces the player's light cones, relics and characters in-game.
pub fn applyConfig(session: *Session, allocator: Allocator) !void {
    // The client's current gear was numbered from the initial uid in config order, one id per item.
    Uid.resetGlobalUidGens();
    var removed = protocol.PlayerSyncScNotify.init(allocator);
    for (ConfigManager.global_game_config_cache.game_config.avatar_config.items) |avatarConf| {
        try removed.del_equipment_list.append(Uid.nextGlobalId());
        for (avatarConf.relics.items) |_| try removed.del_relic_list.append(Uid.nextGlobalId());
    }
    // Teams only show characters config.json has, so the new file can change who is in them.
    const old_team = PresetManager.curTeam();
    try ConfigManager.UpdateGameConfig();
    Uid.updateInitialUid();

    try session.send(CmdID.CmdPlayerSyncScNotify, removed);
    try syncItems(session, allocator, true);
    try onSyncAvatar(session, "", allocator);
    if (!Logic.Challenge().ChallengeMode()) {
        try Lineup.sendPartyRefresh(session, old_team, allocator);
        try Lineup.sendAllPresets(session, allocator);
        var lineup_mgr = LineupManager.LineupManager.init(allocator);
        var lineup = protocol.SyncLineupNotify.init(allocator);
        lineup.lineup = try lineup_mgr.createLineup();
        try session.send(CmdID.CmdSyncLineupNotify, lineup);
    } else {
        Lineup.markPresetsUnsent();
    }
}

// Applies config.json as soon as it changes on disk (an SRTools sync or a hand edit), checked at most once
// a second from the packet loop. Errors are logged, never passed on, so they cannot drop the player.
var last_check_ms: i64 = 0;
pub fn checkConfigFile(session: *Session, allocator: Allocator) void {
    const now = std.time.milliTimestamp();
    if (now - last_check_ms < 1000) return;
    last_check_ms = now;
    if (!ConfigManager.configFileChanged()) return;

    // A login loads the file itself when it starts (PlayerGetToken); a change during login is pushed once it
    // finishes, and a change mid-fight once the battle or challenge is over.
    if (!Login.logged_in or Battle.on_battle or Logic.Challenge().ChallengeMode()) return;

    applyConfig(session, allocator) catch |err| {
        log.err("config.json changed but could not be applied: {}", .{err});
        commandhandler.sendMessage(session, "config.json changed but could not be loaded; see the gameserver window\n", allocator) catch {};
        return;
    };
    log.info("applied the new config.json in-game", .{});
    commandhandler.sendMessage(session, "Characters updated from config.json (SRTools sync)\n", allocator) catch {};
}
