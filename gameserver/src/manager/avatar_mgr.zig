const std = @import("std");
const protocol = @import("protocol");
const Config = @import("../data/game_config.zig");
const Session = @import("../Session.zig");
const Data = @import("../data.zig");
const Logic = @import("../utils/logic.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Uid = @import("../utils/uid.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const config = &ConfigManager.global_game_config_cache.game_config;
const skill_config = &ConfigManager.global_game_config_cache.avatar_skill_config;

pub var m7th: u32 = 1224;
pub var mc_id: u32 = 8010;
pub var gender: u32 = 2;

pub fn createAvatar(
    allocator: Allocator,
    avatarConf: Config.Avatar,
) !protocol.Avatar {
    var avatar = protocol.Avatar.init(allocator);
    avatar.base_avatar_id = switch (avatarConf.id) {
        8001...8010 => 8001,
        1224 => 1001,
        else => avatarConf.id,
    };
    avatar.level = avatarConf.level;
    avatar.promotion = avatarConf.promotion;
    avatar.has_taken_promotion_reward_list = ArrayList(u32).init(allocator);
    for (1..6) |i| {
        try avatar.has_taken_promotion_reward_list.append(@intCast(i));
    }
    avatar.cur_multi_path_avatar_type = switch (avatarConf.id) {
        8001...8010 => mc_id,
        1001, 1224 => m7th,
        else => avatarConf.id,
    };
    return avatar;
}
pub fn createAllAvatar(
    allocator: Allocator,
    Avatar_id: u32,
) !protocol.Avatar {
    var avatar = protocol.Avatar.init(allocator);
    avatar.base_avatar_id = Avatar_id;
    avatar.level = 80;
    avatar.promotion = 6;
    avatar.has_taken_promotion_reward_list = ArrayList(u32).init(allocator);
    for (1..6) |i| {
        try avatar.has_taken_promotion_reward_list.append(@intCast(i));
    }
    avatar.cur_multi_path_avatar_type = Avatar_id;
    return avatar;
}
pub fn createAvatarPathData(
    allocator: Allocator,
    avatarConf: Config.Avatar,
) !protocol.AvatarPathData {
    var avatar = protocol.AvatarPathData.init(allocator);
    avatar.avatar_id = avatarConf.id;
    avatar.rank = avatarConf.rank;
    avatar.dressed_skin_id = getSkinId(avatar.avatar_id);
    if (Logic.inlist(avatar.avatar_id, &Data.EnhanceAvatarID)) {
        avatar.unk_enhanced_id = 1;
    }
    try appendExRanks(&avatar.IGDEHGIKFJA, avatar.avatar_id);
    avatar.path_equipment_id = Uid.nextGlobalId();
    avatar.equip_relic_list = ArrayList(protocol.EquipRelic).init(allocator);
    // Unique ids are replayed in the order the bag creates items (light cone, then each relic), so this
    // takes one id per relic the avatar really has; SRTools builds often have fewer than 6.
    for (avatarConf.relics.items) |relicConf| {
        try avatar.equip_relic_list.append(.{
            .relic_unique_id = Uid.nextGlobalId(),
            .type = relicSlot(relicConf.id),
        });
    }
    try createSkillTree(avatar.avatar_id, &avatar.avatar_path_skill_tree);
    return avatar;
}
// Ex Eidolons (rank ids <avatar id>01) of this avatar only. The client opens the Ex Eidolon page for an avatar
// that has any in its list and shows an empty Eidolon page when the avatar has no Ex Eidolon of its own.
pub fn appendExRanks(list: *ArrayList(u32), avatar_id: u32) !void {
    for (Data.ExRankAvatarID) |rank_id| {
        if (rank_id / 100 == avatar_id) try list.append(rank_id);
    }
}
// Relic ids end in their slot number (1 head .. 6 rope); EquipRelic.type counts from 0.
fn relicSlot(relic_id: u32) u32 {
    const slot = relic_id % 10;
    return if (slot >= 1 and slot <= 6) slot - 1 else 0;
}
pub fn createAllAvatarPathData(
    allocator: Allocator,
    Avatar_id: u32,
) !protocol.AvatarPathData {
    var avatar = protocol.AvatarPathData.init(allocator);
    avatar.avatar_id = Avatar_id;
    avatar.rank = 6;
    avatar.dressed_skin_id = getSkinId(avatar.avatar_id);
    if (Logic.inlist(avatar.avatar_id, &Data.EnhanceAvatarID)) {
        avatar.unk_enhanced_id = 1;
    }
    try appendExRanks(&avatar.IGDEHGIKFJA, avatar.avatar_id);
    try createSkillTree(avatar.avatar_id, &avatar.avatar_path_skill_tree);
    return avatar;
}
fn createSkillTree(
    base_avatar_id: u32,
    skilltree_list: *std.ArrayList(protocol.AvatarPathSkillTree),
) !void {
    for (skill_config.avatar_skill_tree_config.items) |skill| {
        if (skill.avatar_id == base_avatar_id) {
            if (skill.level == skill.max_level) {
                try skilltree_list.append(.{
                    .point_id = skill.anchor_type,
                    .level = skill.max_level,
                });
            }
        }
    }
}

pub fn createEquipment(
    lightconeConf: Config.Lightcone,
    dress_avatar_id: u32,
) !protocol.Equipment {
    return protocol.Equipment{
        .unique_id = Uid.nextGlobalId(),
        .tid = lightconeConf.id,
        .is_protected = true,
        .level = lightconeConf.level,
        .rank = lightconeConf.rank,
        .promotion = lightconeConf.promotion,
        .dress_avatar_id = dress_avatar_id,
    };
}

pub fn createRelic(
    allocator: Allocator,
    relicConf: Config.Relic,
    dress_avatar_id: u32,
) !protocol.Relic {
    var r = protocol.Relic{
        .tid = relicConf.id,
        .main_affix_id = relicConf.main_affix_id,
        .unique_id = Uid.nextGlobalId(),
        .exp = 0,
        .dress_avatar_id = dress_avatar_id,
        .is_protected = true,
        .level = relicConf.level,
        .sub_affix_list = ArrayList(protocol.RelicAffix).init(allocator),
        .reforge_sub_affix_list = ArrayList(protocol.RelicAffix).init(allocator),
        .preview_sub_affix_list = ArrayList(protocol.RelicAffix).init(allocator),
    };
    const subs = [_]protocol.RelicAffix{
        .{ .affix_id = relicConf.stat1, .cnt = relicConf.cnt1, .step = relicConf.step1 },
        .{ .affix_id = relicConf.stat2, .cnt = relicConf.cnt2, .step = relicConf.step2 },
        .{ .affix_id = relicConf.stat3, .cnt = relicConf.cnt3, .step = relicConf.step3 },
        .{ .affix_id = relicConf.stat4, .cnt = relicConf.cnt4, .step = relicConf.step4 },
    };
    // Relics with fewer than 4 sub stats leave the rest as 0, which is not a real stat.
    for (subs) |sub| {
        if (sub.affix_id != 0) try r.sub_affix_list.append(sub);
    }
    return r;
}
pub fn getSkinId(avatar_id: u32) u32 {
    for (Data.AvatarSkinMap) |entry| {
        if (entry.avatar_id == avatar_id) return entry.skin_id;
    }
    return 0;
}
pub fn updateSkinId(avatar_id: u32, new_skin_id: u32) void {
    for (&Data.AvatarSkinMap) |*entry| {
        if (entry.avatar_id == avatar_id) {
            entry.skin_id = new_skin_id;
            return;
        }
    }
}
pub fn syncAvatarData(session: *Session, allocator: Allocator) !void {
    var sync = protocol.PlayerSyncScNotify.init(allocator);
    defer sync.deinit();
    Uid.resetGlobalUidGens();
    var char = protocol.AvatarSync.init(allocator);
    for (Data.AllAvatars) |id| {
        const avatar = try createAllAvatar(allocator, id);
        try char.avatar_list.append(avatar);
    }
    for (Data.AllAvatars) |id| {
        const avatar = try createAllAvatarPathData(allocator, id);
        try char.avatar_path_data_info_list.append(avatar);
    }
    for (config.avatar_config.items) |avatarConf| {
        const avatar = try createAvatar(allocator, avatarConf);
        try char.avatar_list.append(avatar);
    }
    for (config.avatar_config.items) |avatarConf| {
        const avatar = try createAvatarPathData(allocator, avatarConf);
        try char.avatar_path_data_info_list.append(avatar);
    }
    sync.avatar_sync = char;
    try session.send(CmdID.CmdPlayerSyncScNotify, sync);
}
