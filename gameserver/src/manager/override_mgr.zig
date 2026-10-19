const std = @import("std");
const ConfigManager = @import("config_mgr.zig");
const PresetManager = @import("preset_mgr.zig");
const ProfileStore = @import("profile_store.zig");
const StageConfig = @import("../data/stage_config.zig");

// What /calyx and /debug change about ordinary battles (Calyx, overworld monsters). Kept in memory only, so a
// restart clears it, except the Calyx mode, which profile.json keeps. Challenge battles never read any of it.

const config = &ConfigManager.global_game_config_cache.game_config;
const stages = &ConfigManager.global_game_config_cache.stage_config;

pub const max_team = 4;
pub const max_wave_monsters = 5;
pub const max_hp_overrides = 32;

pub const Error = error{ EmptyTeam, TooManyAvatars, UnknownAvatar, DuplicateAvatar, BadWave, BadIndex, BadHp, TooManyOverrides, UnknownMonster, TooManyMonsters };

pub const HpOverride = struct { wave: u32, index: u32, monster_id: u32, hp: u32 };

pub const NextBattle = union(enum) {
    none,
    stage: u32,
    monsters: struct { ids: [max_wave_monsters]u32 = undefined, len: usize = 0 },
};

var team_ids: [max_team]u32 = undefined;
var team_len: usize = 0;
var hp_list: [max_hp_overrides]HpOverride = undefined;
var hp_len: usize = 0;
var next_battle: NextBattle = .none;

pub fn inConfig(id: u32) bool {
    for (config.avatar_config.items) |avatar| {
        if (avatar.id == id) return true;
    }
    return false;
}

// The config.json avatar a typed id means: 8001 and 1001 follow the Trailblazer's and March 7th's selected path.
pub fn resolveAvatar(id: u32) ?u32 {
    const want = if (id == 8001 or id == 1001) PresetManager.pathId(id) else id;
    return if (inConfig(want)) want else null;
}

// --- /calyx on|off ---------------------------------------------------------------------------------------------
// Sync: every Calyx, Cavern of Corrosion, Echo of War, Stagnant Shadow and overworld monster fights config.json's
// battle. Original: each fights its own stages.
pub fn calyxSync() bool {
    return ProfileStore.get().calyx_sync;
}
pub fn setCalyxSync(on: bool) void {
    ProfileStore.set("calyx_sync", on);
}

// --- /calyx lineup ---------------------------------------------------------------------------------------------
pub fn setLineup(ids: []const u32) Error!void {
    if (ids.len == 0) return error.EmptyTeam;
    if (ids.len > max_team) return error.TooManyAvatars;
    var resolved: [max_team]u32 = undefined;
    for (ids, 0..) |id, i| {
        const avatar = resolveAvatar(id) orelse return error.UnknownAvatar;
        for (resolved[0..i]) |prev| {
            if (PresetManager.baseId(prev) == PresetManager.baseId(avatar)) return error.DuplicateAvatar;
        }
        resolved[i] = avatar;
    }
    team_ids = resolved;
    team_len = ids.len;
}
pub fn lineup() ?[]const u32 {
    return if (team_len == 0) null else team_ids[0..team_len];
}
pub fn clearLineup() void {
    team_len = 0;
}

// --- /calyx modify ---------------------------------------------------------------------------------------------
// `wave` and `index` count from 1 over config.json's battle_config.monster_wave; returns the monster's id.
pub fn setMonsterHp(wave: u32, index: u32, hp: u32) Error!u32 {
    const waves = config.battle_config.monster_wave.items;
    if (wave == 0 or wave > waves.len) return error.BadWave;
    const monsters = waves[wave - 1].items;
    if (index == 0 or index > monsters.len) return error.BadIndex;
    if (hp == 0 or hp > std.math.maxInt(i32)) return error.BadHp;
    const monster_id = monsters[index - 1];
    for (hp_list[0..hp_len]) |*o| {
        if (o.wave == wave and o.index == index) {
            o.* = .{ .wave = wave, .index = index, .monster_id = monster_id, .hp = hp };
            return monster_id;
        }
    }
    if (hp_len == max_hp_overrides) return error.TooManyOverrides;
    hp_list[hp_len] = .{ .wave = wave, .index = index, .monster_id = monster_id, .hp = hp };
    hp_len += 1;
    return monster_id;
}
pub fn hpOverrides() []const HpOverride {
    return hp_list[0..hp_len];
}
pub fn clearHp() void {
    hp_len = 0;
}

// --- /debug ----------------------------------------------------------------------------------------------------
pub fn findStage(stage_id: u32) ?*const StageConfig.Stage {
    for (stages.stage_config.items) |*stage| {
        if (stage.stage_id == stage_id) return stage;
    }
    return null;
}
// Monster ids some stage uses; any other id may not exist on the client, which then never loads the battle.
pub fn knownMonster(monster_id: u32) bool {
    for (stages.stage_config.items) |stage| {
        for (stage.monster_list.items) |wave| {
            if (std.mem.indexOfScalar(u32, wave.items, monster_id) != null) return true;
        }
    }
    return false;
}
pub fn setNextStage(stage_id: u32) error{UnknownStage}!void {
    if (findStage(stage_id) == null) return error.UnknownStage;
    next_battle = .{ .stage = stage_id };
}
pub fn setNextMonsters(ids: []const u32) Error!void {
    if (ids.len == 0) return error.UnknownMonster;
    if (ids.len > max_wave_monsters) return error.TooManyMonsters;
    var next: NextBattle = .{ .monsters = .{} };
    for (ids) |id| {
        if (!knownMonster(id)) return error.UnknownMonster;
        next.monsters.ids[next.monsters.len] = id;
        next.monsters.len += 1;
    }
    next_battle = next;
}
pub fn nextBattle() NextBattle {
    return next_battle;
}
// Called where an ordinary battle actually starts, so building one that is never fought keeps the choice.
pub fn clearNextBattle() void {
    next_battle = .none;
}

// --- lifetimes -------------------------------------------------------------------------------------------------
pub fn clearAll() void {
    clearLineup();
    clearHp();
    clearNextBattle();
}
// A /calyx team lasts until the next login, as in March7thHoney.
pub fn clearOnLogin() void {
    clearLineup();
}
// HP overrides name a wave and slot of config.json's battle, which a reload may have changed; a /calyx team
// keeps only the avatars the new config.json still has (none left = the current team again).
pub fn onConfigReloaded() void {
    clearHp();
    var kept: usize = 0;
    for (team_ids[0..team_len]) |id| {
        if (!inConfig(id)) continue;
        team_ids[kept] = id;
        kept += 1;
    }
    team_len = kept;
}
