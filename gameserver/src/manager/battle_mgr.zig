const std = @import("std");
const protocol = @import("protocol");
const Config = @import("../data/game_config.zig");
const Data = @import("../data.zig");
const ConfigManager = @import("config_mgr.zig");
const PresetManager = @import("preset_mgr.zig");
const Logic = @import("../utils/logic.zig");
const AvatarConfig = @import("../data/avatar_config.zig");
const AvatarManager = @import("avatar_mgr.zig");
const TierceManager = @import("tierce_mgr.zig");
const OverrideManager = @import("override_mgr.zig");
const StageConfig = @import("../data/stage_config.zig");
const SceneManager = @import("scene_mgr.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const skill_config = &ConfigManager.global_game_config_cache.avatar_skill_config;
const config = &ConfigManager.global_game_config_cache.game_config;
const stage_invasion_config = &ConfigManager.global_game_config_cache.stage_invasion_config;
const cocoon_config = &ConfigManager.global_game_config_cache.cocoon_config;
const farm_element_config = &ConfigManager.global_game_config_cache.farm_element_config;
const plane_event_config = &ConfigManager.global_game_config_cache.plane_event_config;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub var funmodeAvatarID = std.ArrayList(u32).init(gpa.allocator());

fn getAvatarElement(avatar_id: u32) AvatarConfig.Element {
    const avatars = &ConfigManager.global_game_config_cache.avatar_config;
    for (avatars.avatar_config.items) |avatar| {
        if (avatar.avatar_id == avatar_id) {
            return avatar.damage_type;
        }
    }
    return .None;
}

// Opening-attack element of the leader in `team`, the team the battle is built from.
fn getAttackerBuffId(team: []const u32, leader_slot: u32) u32 {
    const avatar_id = if (leader_slot < team.len) team[leader_slot] else 0;
    const element = getAvatarElement(avatar_id);
    return switch (element) {
        .Physical => 1000111,
        .Fire => 1000112,
        .Ice => 1000113,
        .Thunder => 1000114,
        .Wind => 1000115,
        .Quantum => 1000116,
        .Imaginary => 1000117,
        .None => 0,
    };
}

fn createBattleRelic(allocator: Allocator, id: u32, level: u32, main_affix_id: u32, stat1: u32, cnt1: u32, step1: u32, stat2: u32, cnt2: u32, step2: u32, stat3: u32, cnt3: u32, step3: u32, stat4: u32, cnt4: u32, step4: u32) !protocol.BattleRelic {
    var relic = protocol.BattleRelic{ .id = id, .main_affix_id = main_affix_id, .level = level, .sub_affix_list = ArrayList(protocol.RelicAffix).init(allocator) };
    if (stat1 != 0) try relic.sub_affix_list.append(protocol.RelicAffix{ .affix_id = stat1, .cnt = cnt1, .step = step1 });
    if (stat2 != 0) try relic.sub_affix_list.append(protocol.RelicAffix{ .affix_id = stat2, .cnt = cnt2, .step = step2 });
    if (stat3 != 0) try relic.sub_affix_list.append(protocol.RelicAffix{ .affix_id = stat3, .cnt = cnt3, .step = step3 });
    if (stat4 != 0) try relic.sub_affix_list.append(protocol.RelicAffix{ .affix_id = stat4, .cnt = cnt4, .step = step4 });
    return relic;
}

fn createBattleAvatar(allocator: Allocator, avatarConf: Config.Avatar) !protocol.BattleAvatar {
    var avatar = protocol.BattleAvatar.init(allocator);
    avatar.id = avatarConf.id;
    avatar.hp = avatarConf.hp * 100;
    avatar.sp_bar = .{ .cur_sp = avatarConf.sp * 100, .max_sp = 10000 };
    avatar.level = avatarConf.level;
    avatar.rank = avatarConf.rank;
    avatar.promotion = avatarConf.promotion;
    avatar.avatar_type = .AVATAR_FORMAL_TYPE;
    try AvatarManager.appendExRanks(&avatar.IGDEHGIKFJA, avatar.id);
    if (Logic.inlist(avatar.id, &Data.EnhanceAvatarID)) avatar.enhanced_id = 1;

    for (avatarConf.relics.items) |relic| {
        const r = try createBattleRelic(allocator, relic.id, relic.level, relic.main_affix_id, relic.stat1, relic.cnt1, relic.step1, relic.stat2, relic.cnt2, relic.step2, relic.stat3, relic.cnt3, relic.step3, relic.stat4, relic.cnt4, relic.step4);
        try avatar.relic_list.append(r);
    }

    const lc = protocol.BattleEquipment{
        .id = avatarConf.lightcone.id,
        .rank = avatarConf.lightcone.rank,
        .level = avatarConf.lightcone.level,
        .promotion = avatarConf.lightcone.promotion,
    };
    try avatar.equipment_list.append(lc);

    for (skill_config.avatar_skill_tree_config.items) |skill| {
        if (skill.avatar_id == avatar.id) {
            if (skill.level == skill.max_level) {
                try avatar.skilltree_list.append(.{
                    .point_id = skill.point_id,
                    .level = skill.max_level,
                });
            }
        }
    }
    return avatar;
}

const BuffRule = struct {
    avatar_id: u32,
    buffs: []const struct {
        id: u32,
        owner_is_avatar: bool = true,
        dynamic_values: []const protocol.BattleBuff.DynamicValuesEntry = &.{},
    },
};

const technique_buffs = [_]BuffRule{
    .{
        .avatar_id = 1208,
        .buffs = &.{
            .{ .id = 120801, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 120802, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
        },
    },
    .{
        .avatar_id = 1224,
        .buffs = &.{
            .{ .id = 122402, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 122403, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 122401, .dynamic_values = &.{
                .{ .key = .{ .Const = "#ADF_1" }, .value = 3 },
                .{ .key = .{ .Const = "#ADF_2" }, .value = 3 },
            } },
        },
    },
    .{
        .avatar_id = 1304,
        .buffs = &.{.{ .id = 130403, .dynamic_values = &.{
            .{ .key = .{ .Const = "SkillIndex" }, .value = 3 },
        } }},
    },
    .{
        .avatar_id = 1306,
        .buffs = &.{
            .{ .id = 130601, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 130602, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
        },
    },
    .{
        .avatar_id = 1308,
        .buffs = &.{
            .{ .id = 130803, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
        },
    },
    .{
        .avatar_id = 1309,
        .buffs = &.{
            .{ .id = 130901, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 130902, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
        },
    },
    .{
        .avatar_id = 1310,
        .buffs = &.{
            .{ .id = 131001, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 131002, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 1000112, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
        },
    },
    .{
        .avatar_id = 1412,
        .buffs = &.{
            .{ .id = 141201, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{
                .id = 1000121,
                .owner_is_avatar = false,
                .dynamic_values = &.{
                    .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
                },
            },
        },
    },
    .{
        .avatar_id = 1414,
        .buffs = &.{
            .{ .id = 141401, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{
                .id = 1000121,
                .owner_is_avatar = false,
                .dynamic_values = &.{
                    .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
                },
            },
        },
    },
    .{
        .avatar_id = 1510,
        .buffs = &.{
            .{ .id = 151001, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{ .id = 151002, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
        },
    },
    .{
        .avatar_id = 1503,
        .buffs = &.{
            .{ .id = 150301, .dynamic_values = &.{
                .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
            } },
            .{
                .id = 1000121,
                .owner_is_avatar = false,
                .dynamic_values = &.{
                    .{ .key = .{ .Const = "SkillIndex" }, .value = 0 },
                },
            },
        },
    },
};

fn addTechniqueBuffs(allocator: Allocator, battle: *protocol.SceneBattleInfo, avatar: protocol.BattleAvatar, avatarConf: Config.Avatar, avatar_index: u32, leader_slot: u32) !void {
    if (!avatarConf.use_technique) return;

    var targetIndexList = ArrayList(u32).init(allocator);
    errdefer targetIndexList.deinit();
    try targetIndexList.append(0);

    const buffedAvatarId = switch (avatar.id) {
        8004 => 8003,
        8006 => 8005,
        8008 => 8007,
        8010 => 8009,
        else => avatar.id,
    };

    if (Logic.inlist(buffedAvatarId, &Data.IgnoreToughness)) {
        var buff = protocol.BattleBuff{
            .id = 1000119,
            .level = 1,
            .owner_index = @intCast(avatar_index),
            .wave_flag = 0xFFFFFFFF,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try buff.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 0 });
        try battle.buff_list.append(buff);
    }

    var found_custom_buff = false;
    for (technique_buffs) |rule| {
        if (rule.avatar_id == buffedAvatarId) {
            found_custom_buff = true;
            for (rule.buffs) |buff_def| {
                var buff = protocol.BattleBuff{
                    .id = buff_def.id,
                    .level = 1,
                    .owner_index = if (buff_def.owner_is_avatar) @intCast(avatar_index) else leader_slot,
                    .wave_flag = 0xFFFFFFFF,
                    .target_index_list = try targetIndexList.clone(),
                    .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
                };
                try buff.dynamic_values.appendSlice(buff_def.dynamic_values);
                try battle.buff_list.append(buff);
            }
            break;
        }
    }
    if (!found_custom_buff) {
        var buff = protocol.BattleBuff{
            .id = buffedAvatarId * 100 + 1,
            .level = 1,
            .owner_index = @intCast(avatar_index),
            .wave_flag = 0xFFFFFFFF,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try buff.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 0 });
        try battle.buff_list.append(buff);
    }
    targetIndexList.deinit();
}

fn addGlobalPassive(allocator: Allocator, battle: *protocol.SceneBattleInfo) !void {
    if (Logic.inlist(1407, &Data.AvatarGlobalBuff)) {
        var targetIndexList = ArrayList(u32).init(allocator);
        errdefer targetIndexList.deinit();
        try targetIndexList.append(0);
        var mazebuff_data = protocol.BattleBuff{
            .id = 140703,
            .level = 1,
            .owner_index = 1,
            .wave_flag = 0xFFFFFFFF,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try mazebuff_data.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 0 });
        try battle.buff_list.append(mazebuff_data);
        targetIndexList.deinit();
    }
    if (Logic.inlist(1506, &Data.AvatarGlobalBuff)) {
        var targetIndexList = ArrayList(u32).init(allocator);
        errdefer targetIndexList.deinit();
        try targetIndexList.append(0);
        var mazebuff_data = protocol.BattleBuff{
            .id = 150602,
            .level = 1,
            .owner_index = 1,
            .wave_flag = 0xFFFFFFFF,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try mazebuff_data.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 0 });
        try battle.buff_list.append(mazebuff_data);
        targetIndexList.deinit();
    }
    if (Logic.inlist(1511, &Data.AvatarGlobalBuff)) {
        var targetIndexList = ArrayList(u32).init(allocator);
        errdefer targetIndexList.deinit();
        try targetIndexList.append(0);
        var mazebuff_data = protocol.BattleBuff{
            .id = 151104,
            .level = 1,
            .owner_index = 1,
            .wave_flag = 0xFFFFFFFF,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try mazebuff_data.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 0 });
        try battle.buff_list.append(mazebuff_data);
        targetIndexList.deinit();
    }
}

fn addTriggerAttack(allocator: Allocator, battle: *protocol.SceneBattleInfo, team: []const u32, leader_slot: u32) !void {
    var targetIndexList = ArrayList(u32).init(allocator);
    errdefer targetIndexList.deinit();
    try targetIndexList.append(0);
    var attack = protocol.BattleBuff{
        .id = getAttackerBuffId(team, leader_slot),
        .level = 1,
        .owner_index = leader_slot,
        .wave_flag = 0xFFFFFFFF,
        .target_index_list = try targetIndexList.clone(),
        .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
    };
    try attack.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 1 });
    try battle.buff_list.append(attack);
    targetIndexList.deinit();
}

fn addStageInvasion(allocator: Allocator, battle: *protocol.SceneBattleInfo, leader_slot: u32) !void {
    var targetIndexList = ArrayList(u32).init(allocator);
    errdefer targetIndexList.deinit();
    try targetIndexList.append(0);
    var id: u32 = 0;
    for (stage_invasion_config.stage_invasion_config.items) |stage| {
        if (Logic.Challenge().GetChallengeStageID() == stage.stage_id) id = stage.invasion_id;
    }
    if (id == 0) return;
    var attack = protocol.BattleBuff{
        .id = 3034000 + id,
        .level = 1,
        .owner_index = leader_slot,
        .wave_flag = 0xFFFFFFFF,
        .target_index_list = try targetIndexList.clone(),
        .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
    };
    try attack.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 1 });
    try battle.buff_list.append(attack);
    if (Logic.CustomMode().AhaBuff()) {
        var support = protocol.BattleBuff{
            .id = 3034013,
            .level = 1,
            .owner_index = leader_slot,
            .wave_flag = 0xFFFFFFFF,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try support.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 1 });
        try battle.buff_list.append(support);
    }
    targetIndexList.deinit();
}

fn createBattleInfo(allocator: Allocator, game_config: *const Config.GameConfig, stage_monster_wave_len: u32, stage_id: u32, rounds_limit: u32) protocol.SceneBattleInfo {
    var battle = protocol.SceneBattleInfo.init(allocator);
    battle.battle_id = game_config.battle_config.battle_id;
    battle.stage_id = stage_id;
    battle.logic_random_seed = @intCast(@mod(std.time.timestamp(), 0xFFFFFFFF));
    battle.rounds_limit = rounds_limit;
    battle.monster_wave_length = @intCast(stage_monster_wave_len);
    battle.world_level = 6;
    return battle;
}

fn addMonsterWaves(allocator: Allocator, battle: *protocol.SceneBattleInfo, monster_wave_configs: std.ArrayList(std.ArrayList(u32)), monster_level: u32) !void {
    for (monster_wave_configs.items) |wave| {
        var monster_wave = protocol.SceneMonsterWave.init(allocator);
        monster_wave.monster_param = protocol.SceneMonsterWaveParam{ .level = monster_level };
        for (wave.items) |mob_id| {
            try monster_wave.monster_list.append(.{ .monster_id = mob_id, .max_hp = Logic.FunMode().GetHp() });
        }
        try battle.monster_wave_list.append(monster_wave);
    }
}

// A real stage's waves after those already there, as the game numbers them: each names its stage and wave.
fn addStageWaves(allocator: Allocator, battle: *protocol.SceneBattleInfo, stage: *const StageConfig.Stage) !void {
    for (stage.monster_list.items) |wave| {
        var monster_wave = protocol.SceneMonsterWave.init(allocator);
        monster_wave.battle_stage_id = stage.stage_id;
        monster_wave.battle_wave_id = @intCast(battle.monster_wave_list.items.len + 1);
        monster_wave.monster_param = protocol.SceneMonsterWaveParam{ .level = stage.level };
        for (wave.items) |mob_id| {
            try monster_wave.monster_list.append(.{ .monster_id = mob_id, .max_hp = Logic.FunMode().GetHp() });
        }
        try battle.monster_wave_list.append(monster_wave);
    }
    battle.monster_wave_length = @intCast(battle.monster_wave_list.items.len);
}

fn addStageBlessings(allocator: Allocator, battle: *protocol.SceneBattleInfo, blessings: []const u32) !void {
    for (blessings) |blessing| {
        var targetIndexList = ArrayList(u32).init(allocator);
        errdefer targetIndexList.deinit();
        try targetIndexList.append(0);
        var buff = protocol.BattleBuff{
            .id = blessing,
            .level = 1,
            .owner_index = 0xffffffff,
            .wave_flag = 0xffffffff,
            .target_index_list = try targetIndexList.clone(),
            .dynamic_values = ArrayList(protocol.BattleBuff.DynamicValuesEntry).init(allocator),
        };
        try buff.dynamic_values.append(.{ .key = .{ .Const = "SkillIndex" }, .value = 0 });
        try battle.buff_list.append(buff);
        targetIndexList.deinit();
    }
}

// Starting progress of the PF score target for a node; the client reports challenge_score on top of it.
pub fn pfTargetSeed(node: u32) u32 {
    return if (node == 1) 0 else 40000;
}

fn addBattleTargets(allocator: Allocator, battle: *protocol.SceneBattleInfo) !void {
    battle.battle_target_info = ArrayList(protocol.SceneBattleInfo.BattleTargetInfoEntry).init(allocator);

    var pfTargetHead = protocol.BattleTargetList{ .battle_target_list = ArrayList(protocol.BattleTarget).init(allocator) };
    if (Logic.Challenge().ChallengeMode()) {
        const seed = pfTargetSeed(Logic.Challenge().CurNode());
        try pfTargetHead.battle_target_list.append(.{ .id = 10003, .progress = seed, .total_progress = 80000 });
    } else {
        try pfTargetHead.battle_target_list.append(.{ .id = 10002, .progress = 0, .total_progress = 80000 });
    }

    var pfTargetTail = protocol.BattleTargetList{ .battle_target_list = ArrayList(protocol.BattleTarget).init(allocator) };
    try pfTargetTail.battle_target_list.append(.{ .id = 2001, .progress = 0, .total_progress = 0 });
    try pfTargetTail.battle_target_list.append(.{ .id = 2002, .progress = 0, .total_progress = 0 });

    var asTargetHead = protocol.BattleTargetList{ .battle_target_list = ArrayList(protocol.BattleTarget).init(allocator) };
    try asTargetHead.battle_target_list.append(.{ .id = 90005, .progress = 2000, .total_progress = 0 });

    switch (battle.stage_id) {
        30019000...30019100, 30021000...30021100, 30301000...30399900 => { // PF
            try battle.battle_target_info.append(.{ .key = 1, .value = pfTargetHead });
            for (2..4) |i| {
                try battle.battle_target_info.append(.{ .key = @intCast(i), .value = protocol.BattleTargetList{ .battle_target_list = ArrayList(protocol.BattleTarget).init(allocator) } });
            }
            try battle.battle_target_info.append(.{ .key = 5, .value = pfTargetTail });
        },
        420100...420900 => { // AS
            try battle.battle_target_info.append(.{ .key = 1, .value = asTargetHead });
        },
        else => {},
    }
}
fn commonBattleSetup(
    allocator: Allocator,
    battle: *protocol.SceneBattleInfo,
    selected_avatar_ids: []const u32,
    leader_slot: u32,
    avatar_configs: []const Config.Avatar,
    monster_wave_configs: std.ArrayList(std.ArrayList(u32)),
    monster_level: u32,
    stage_blessings: []const u32,
) !void {
    var avatarIndex: u32 = 0;
    for (selected_avatar_ids) |selected_id| {
        for (avatar_configs) |avatarConf| {
            if (avatarConf.id == selected_id) {
                const avatar = try createBattleAvatar(allocator, avatarConf);
                try addTechniqueBuffs(allocator, battle, avatar, avatarConf, avatarIndex, leader_slot);
                try battle.battle_avatar_list.append(avatar);
                avatarIndex += 1;
            }
        }
    }

    try addMonsterWaves(allocator, battle, monster_wave_configs, monster_level);
    try addTriggerAttack(allocator, battle, selected_avatar_ids, leader_slot);
    try addStageBlessings(allocator, battle, stage_blessings);
    try addGlobalPassive(allocator, battle);
    try addStageInvasion(allocator, battle, leader_slot);
    try addBattleTargets(allocator, battle);
}
pub const BattleTeam = struct { ids: []const u32, leader_slot: u32 };
var preset_team: PresetManager.Team = .{};

// Who fights an ordinary battle: a /calyx team, else /funmode's, else the current team preset.
pub fn currentTeam() BattleTeam {
    if (OverrideManager.lineup()) |ids| return .{ .ids = ids, .leader_slot = 0 };
    preset_team = PresetManager.curTeam();
    if (Logic.FunMode().FunMode()) return .{ .ids = funmodeAvatarID.items, .leader_slot = preset_team.leader_slot };
    return .{ .ids = preset_team.slice(), .leader_slot = preset_team.leader_slot };
}

pub const findStage = OverrideManager.findStage;

// The world level a Calyx-type request means: 0 is the player's own.
pub fn requestedWorldLevel(world_level: u32) u32 {
    return if (world_level == 0) 6 else world_level;
}
// Most runs one Calyx battle is built with; the client offers fewer.
const max_cocoon_runs = 10;

// /calyx modify: per-monster HP on top of /funmode hp, for config.json's own waves only.
fn applyHpOverrides(battle: *protocol.SceneBattleInfo) void {
    for (OverrideManager.hpOverrides()) |o| {
        if (o.wave > battle.monster_wave_list.items.len) continue;
        const wave = &battle.monster_wave_list.items[o.wave - 1];
        if (o.index > wave.monster_list.items.len) continue;
        wave.monster_list.items[o.index - 1].max_hp = o.hp;
        wave.monster_list.items[o.index - 1].cur_hp = o.hp;
    }
}

pub const BattleManager = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) BattleManager {
        return BattleManager{ .allocator = allocator };
    }

    // An ordinary battle: config.json's, unless /debug picked the next one.
    pub fn createBattle(self: *BattleManager) !protocol.SceneBattleInfo {
        switch (OverrideManager.nextBattle()) {
            .stage => |stage_id| if (findStage(stage_id)) |stage| return self.createStageBattle(stage),
            .monsters => |m| return self.createMonsterBattle(m.ids[0..m.len]),
            .none => {},
        }
        var battle = createBattleInfo(
            self.allocator,
            config,
            @intCast(config.battle_config.monster_wave.items.len),
            config.battle_config.stage_id,
            config.battle_config.cycle_count,
        );

        // The team is read when the battle starts.
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            config.battle_config.monster_wave,
            config.battle_config.monster_level,
            config.battle_config.blessings.items,
        );
        applyHpOverrides(&battle);

        return battle;
    }

    // A stage from resources/StageConfig.json as it is: its waves and level, none of config.json's blessings.
    pub fn createStageBattle(self: *BattleManager, stage: *const StageConfig.Stage) !protocol.SceneBattleInfo {
        var battle = createBattleInfo(
            self.allocator,
            config,
            @intCast(stage.monster_list.items.len),
            stage.stage_id,
            config.battle_config.cycle_count,
        );
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            stage.monster_list,
            stage.level,
            &.{},
        );
        return battle;
    }

    // A Calyx, Cavern of Corrosion or Echo of War: config.json's battle in Sync mode, else `wave` runs of the cocoon's
    // own stages at `world_level`, each drawn at random from its stage list as the real server does. A cocoon the
    // table does not have, or a /debug pick, still fights the ordinary battle.
    pub fn createCocoonBattle(self: *BattleManager, cocoon_id: u32, world_level: u32, wave: u32) !protocol.SceneBattleInfo {
        if (OverrideManager.calyxSync() or OverrideManager.nextBattle() != .none) return self.createBattle();
        const level = requestedWorldLevel(world_level);
        const cocoon = cocoon_config.find(cocoon_id, level) orelse {
            std.log.warn("Calyx {d} (world level {d}) is not in resources/CocoonConfig.json; it fights config.json's battle", .{ cocoon_id, level });
            return self.createBattle();
        };
        var picked: [max_cocoon_runs]u32 = undefined;
        const runs = std.math.clamp(wave, 1, max_cocoon_runs);
        for (picked[0..runs]) |*stage_id| {
            stage_id.* = cocoon.stage_ids[std.crypto.random.uintLessThan(usize, cocoon.stage_ids.len)];
        }
        return self.createRealStagesBattle(picked[0..runs], cocoon.world_level);
    }

    // A Stagnant Shadow, named by its id or one of its stages: config.json's battle in Sync mode, else its stage.
    pub fn createFarmElementBattle(self: *BattleManager, id_or_stage: u32, world_level: u32) !protocol.SceneBattleInfo {
        if (OverrideManager.calyxSync() or OverrideManager.nextBattle() != .none) return self.createBattle();
        const element = farm_element_config.find(id_or_stage, requestedWorldLevel(world_level)) orelse {
            std.log.warn("Stagnant Shadow {d} is not in resources/FarmElementConfig.json; it fights config.json's battle", .{id_or_stage});
            return self.createBattle();
        };
        return self.createRealStagesBattle(&.{element.stage_id}, element.world_level);
    }

    // Overworld monsters hit together, by entity id (the one that struck first leading): in Original mode each one's
    // event stage, one after another; null means the ordinary battle (Sync mode, a /debug pick, or no monster with a
    // known stage).
    pub fn createMapMonsterBattle(self: *BattleManager, entity_ids: []const u32) !?protocol.SceneBattleInfo {
        if (OverrideManager.calyxSync() or OverrideManager.nextBattle() != .none) return null;
        var stage_ids = ArrayList(u32).init(self.allocator);
        defer stage_ids.deinit();
        for (entity_ids) |entity_id| {
            const event_id = SceneManager.monsterEvent(entity_id) orelse continue;
            const stage_id = plane_event_config.stageFor(event_id) orelse {
                std.log.warn("monster event {d} is not in resources/PlaneEvent.json; left out of the fight", .{event_id});
                continue;
            };
            if (findStage(stage_id) == null) continue;
            try stage_ids.append(stage_id);
        }
        if (stage_ids.items.len == 0) return null;
        return try self.createRealStagesBattle(stage_ids.items, 6);
    }

    // Real stages of `world_level` fought one after another with the current team: their own monsters and levels,
    // no cycle limit and none of config.json's blessings.
    fn createRealStagesBattle(self: *BattleManager, stage_ids: []const u32, world_level: u32) !protocol.SceneBattleInfo {
        for (stage_ids) |stage_id| {
            if (findStage(stage_id) == null) return self.createBattle();
        }
        var battle = createBattleInfo(self.allocator, config, 0, stage_ids[0], 0);
        battle.world_level = world_level;
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            std.ArrayList(std.ArrayList(u32)).init(self.allocator),
            0,
            &.{},
        );
        for (stage_ids) |stage_id| try addStageWaves(self.allocator, &battle, findStage(stage_id).?);
        return battle;
    }

    // config.json's stage, level and blessings with one wave of the given monsters (/debug monster).
    fn createMonsterBattle(self: *BattleManager, monster_ids: []const u32) !protocol.SceneBattleInfo {
        var wave = std.ArrayList(u32).init(self.allocator);
        try wave.appendSlice(monster_ids);
        var waves = std.ArrayList(std.ArrayList(u32)).init(self.allocator);
        try waves.append(wave);
        var battle = createBattleInfo(self.allocator, config, 1, config.battle_config.stage_id, config.battle_config.cycle_count);
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            waves,
            config.battle_config.monster_level,
            config.battle_config.blessings.items,
        );
        return battle;
    }
};

// Cycles a challenge battle may last. A Starward MoC floor gives its three nodes one shared pool (45), so a node
// gets what the nodes before it left; classic MoC nodes get 30 each, PF nodes 4.
fn challengeRoundsLimit() u32 {
    const C = Logic.Challenge();
    if (C.GetChallengeMode() == 1) return 4;
    if (C.GetKind() == .tierce and C.GetChallengeMode() == 0) {
        const stage = @min(C.TierceStage(), TierceManager.nodes);
        // 0 would be read as no limit at all.
        if (TierceManager.cyclesLeft(C.GetChallengeID(), C.TierceResults()[0..stage])) |left| return @max(1, left);
    }
    return 30;
}

pub const ChallegeStageManager = struct {
    allocator: Allocator,
    game_config_cache: *ConfigManager.GameConfigCache,

    pub fn init(allocator: Allocator, cache: *ConfigManager.GameConfigCache) ChallegeStageManager {
        return ChallegeStageManager{
            .allocator = allocator,
            .game_config_cache = cache,
        };
    }

    pub fn createChallegeStage(self: *ChallegeStageManager) !protocol.SceneBattleInfo {
        if (!Logic.Challenge().FoundStage()) {
            std.log.info("Challenge stage ID is 0, skipping challenge battle creation and returning an empty battle info.", .{});
            return protocol.SceneBattleInfo.init(self.allocator);
        }

        const stage_config = &self.game_config_cache.stage_config;
        var battle: protocol.SceneBattleInfo = undefined;
        var found_stage = false;

        for (stage_config.stage_config.items) |stageConf| {
            if (stageConf.stage_id == Logic.Challenge().GetChallengeStageID()) {
                battle = createBattleInfo(
                    self.allocator,
                    config,
                    @intCast(stageConf.monster_list.items.len),
                    stageConf.stage_id,
                    challengeRoundsLimit(),
                );
                found_stage = true;
                // The current node's team, with the Trailblazer and March 7th on their selected paths.
                var node_avatars: [4]u32 = .{ 0, 0, 0, 0 };
                for (Logic.Challenge().GetAvatarIDs().items, 0..) |id, i| {
                    if (i >= node_avatars.len) break;
                    node_avatars[i] = switch (id) {
                        8001 => AvatarManager.mc_id,
                        1001 => AvatarManager.m7th,
                        else => id,
                    };
                }
                try commonBattleSetup(
                    self.allocator,
                    &battle,
                    if (!Logic.FunMode().FunMode()) &node_avatars else funmodeAvatarID.items,
                    Logic.Challenge().LeaderSlot(),
                    config.avatar_config.items,
                    stageConf.monster_list,
                    stageConf.level,
                    Logic.Challenge().GetChallengeBlessingID(),
                );
                break;
            }
        }
        if (!found_stage) {
            std.log.err("Challenge stage with ID {d} not found in config.", .{Logic.Challenge().GetChallengeStageID()});
            return error.StageNotFound;
        }
        return battle;
    }
};

pub fn deinitSceneBattleInfo(battle: *protocol.SceneBattleInfo) void {
    for (battle.battle_avatar_list.items) |*avatar| {
        for (avatar.relic_list.items) |*relic| {
            relic.sub_affix_list.deinit();
        }
        avatar.relic_list.deinit();
        avatar.equipment_list.deinit();
        avatar.skilltree_list.deinit();
    }
    battle.battle_avatar_list.deinit();

    for (battle.buff_list.items) |*buff| {
        buff.target_index_list.deinit();
        buff.dynamic_values.deinit();
    }
    battle.buff_list.deinit();

    for (battle.monster_wave_list.items) |*wave| {
        wave.monster_list.deinit();
    }
    battle.monster_wave_list.deinit();

    for (battle.battle_target_info.items) |*entry| {
        if (entry.value) |*v| {
            v.battle_target_list.deinit();
        }
    }
    battle.battle_target_info.deinit();
}
