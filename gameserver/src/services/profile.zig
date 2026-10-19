const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const GameConfig = @import("../data/game_config.zig");
const commandhandler = @import("../command.zig");
const Login = @import("login.zig");
const Clock = @import("../utils/clock.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const config = &ConfigManager.global_game_config_cache.game_config;

// can change these id here for initial display
const SupportAvatar = [_]u32{
    1510, 1508, 1505,
};
const ListAvatar = [_]u32{
    1415, 1001, 1310, 1303, 1501,
};
const max_display = 5;
const max_assist = 3;
const max_signature = 256;
const max_nickname = 32;

// Pom-Pom's outfits (PamSkinConfig). The empty reply this used to get left the outfit at 0, which has no model:
// the client could not build the Pom-Pom NPC on the Express (group 227, NormalPam) or the Party Train (group 103,
// Pam_NPC) and never left the loading screen of either.
const pam_skins = [_]u32{ 252000, 252001, 252002, 252003, 252004 };

// The outfit survives restarts in profile.json; a saved one that is not in the list (a hand edit) shows the first.
fn curPamSkin() u32 {
    const saved = ProfileStore.get().pam_skin;
    return if (std.mem.indexOfScalar(u32, &pam_skins, saved) != null) saved else pam_skins[0];
}

pub fn onGetPamSkinData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPamSkinDataScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_skin = curPamSkin();
    try rsp.unlock_skin_list.appendSlice(&pam_skins);
    try session.send(CmdID.CmdGetPamSkinDataScRsp, rsp);
}

pub fn onSelectPamSkin(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPamSkinCsReq, allocator);
    defer req.deinit();
    if (req.pam_skin != curPamSkin() and std.mem.indexOfScalar(u32, &pam_skins, req.pam_skin) != null) {
        ProfileStore.set("pam_skin", req.pam_skin);
    }
    try session.send(CmdID.CmdSelectPamSkinScRsp, protocol.SelectPamSkinScRsp{
        .retcode = 0,
        .cur_skin = curPamSkin(),
        .set_skin = curPamSkin(),
    });
}

// The phone's bubble, theme and case are kept in profile.json. An id outside the owned lists of data.zig keeps the
// current choice; a saved one outside them (a hand edit) shows the default.
fn owns(list: []const u32, id: u32) bool {
    return std.mem.indexOfScalar(u32, list, id) != null;
}
fn ownedOr(list: []const u32, saved: u32, default: u32) u32 {
    return if (owns(list, saved)) saved else default;
}
fn curChatBubble() u32 {
    return ownedOr(&Data.OwnedChatBubbles, ProfileStore.get().chat_bubble, 0);
}
fn curPhoneTheme() u32 {
    return ownedOr(&Data.OwnedPhoneThemes, ProfileStore.get().phone_theme, 0);
}
fn curPhoneCase() u32 {
    return ownedOr(&Data.OwnedPhoneCases, ProfileStore.get().phone_case, 254001);
}

pub fn onGetPhoneData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPhoneDataScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_chat_bubble = curChatBubble();
    rsp.cur_phone_theme = curPhoneTheme();
    rsp.cur_phone_case = curPhoneCase();
    try rsp.owned_phone_cases.appendSlice(&Data.OwnedPhoneCases);
    try rsp.owned_phone_themes.appendSlice(&Data.OwnedPhoneThemes);
    try rsp.owned_chat_bubbles.appendSlice(&Data.OwnedChatBubbles);
    try session.send(CmdID.CmdGetPhoneDataScRsp, rsp);
}
pub fn onSelectPhoneTheme(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPhoneThemeCsReq, allocator);
    defer req.deinit();
    if (req.theme_id != curPhoneTheme() and owns(&Data.OwnedPhoneThemes, req.theme_id)) {
        ProfileStore.set("phone_theme", req.theme_id);
    }

    var rsp = protocol.SelectPhoneThemeScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_phone_theme = curPhoneTheme();
    try session.send(CmdID.CmdSelectPhoneThemeScRsp, rsp);
}
pub fn onSelectChatBubble(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectChatBubbleCsReq, allocator);
    defer req.deinit();
    if (req.bubble_id != curChatBubble() and owns(&Data.OwnedChatBubbles, req.bubble_id)) {
        ProfileStore.set("chat_bubble", req.bubble_id);
    }

    var rsp = protocol.SelectChatBubbleScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_chat_bubble = curChatBubble();
    try session.send(CmdID.CmdSelectChatBubbleScRsp, rsp);
}
// The player board (card) is kept in profile.json. Its avatars are stored as base ids (8001, 1001), which follow
// the Trailblazer's and March 7th's selected path.

// The config.json avatar a board entry stands for; null once config.json no longer has the character.
fn configAvatar(base_id: u32) ?*const GameConfig.Avatar {
    const selected = PresetManager.pathId(base_id);
    var first: ?*const GameConfig.Avatar = null;
    for (config.avatar_config.items) |*avatar| {
        if (avatar.id == selected) return avatar;
        if (first == null and PresetManager.baseId(avatar.id) == base_id) first = avatar;
    }
    return first;
}

// The saved board avatars config.json still has; the defaults above when none are left.
fn boardDisplay(allocator: Allocator) ![]const ProfileStore.DisplayAvatar {
    var out = ArrayList(ProfileStore.DisplayAvatar).init(allocator);
    for (ProfileStore.get().display_avatars) |entry| {
        if (configAvatar(entry.avatar_id) != null) try out.append(entry);
    }
    if (out.items.len == 0) {
        for (ListAvatar, 1..) |id, pos| try out.append(.{ .avatar_id = id, .pos = @intCast(pos) });
    }
    return out.items;
}
fn boardAssist(allocator: Allocator) ![]const u32 {
    var out = ArrayList(u32).init(allocator);
    for (ProfileStore.get().assist_avatars) |id| {
        if (configAvatar(id) != null) try out.append(id);
    }
    if (out.items.len == 0) try out.appendSlice(&SupportAvatar);
    return out.items;
}

// A board request's avatars as base ids; null if one is not in config.json, one repeats, or there are too many.
// Empty slots (avatar 0) are skipped.
fn pickDisplay(allocator: Allocator, entries: []const protocol.DisplayAvatarData) !?[]ProfileStore.DisplayAvatar {
    var picked = ArrayList(ProfileStore.DisplayAvatar).init(allocator);
    for (entries) |entry| {
        if (entry.avatar_id == 0) continue;
        const base = PresetManager.baseId(entry.avatar_id);
        if (configAvatar(base) == null or picked.items.len == max_display) return null;
        for (picked.items) |p| {
            if (p.avatar_id == base) return null;
        }
        try picked.append(.{ .avatar_id = base, .pos = entry.pos });
    }
    return picked.items;
}
fn pickAssist(allocator: Allocator, ids: []const u32) !?[]u32 {
    var picked = ArrayList(u32).init(allocator);
    for (ids) |id| {
        if (id == 0) continue;
        const base = PresetManager.baseId(id);
        if (configAvatar(base) == null or picked.items.len == max_assist) return null;
        if (std.mem.indexOfScalar(u32, picked.items, base) != null) return null;
        try picked.append(base);
    }
    return picked.items;
}

fn unlockedHeadIcon(id: u32) bool {
    for (ConfigManager.global_game_config_cache.player_icon_config.player_icon_config.items) |icon| {
        if (icon.id == id) return true;
    }
    return false;
}
// A saved icon or card the player does not have (a hand edit) shows the default.
fn curHeadIcon() u32 {
    const saved = ProfileStore.get().head_icon;
    return if (unlockedHeadIcon(saved)) saved else 0;
}
fn curPersonalCard() u32 {
    return ownedOr(&Data.OwnedPersonalCardSkin, ProfileStore.get().personal_card, 253001);
}

// The longest start of `text` that fits in `max` bytes without splitting a character; null if `text` is not UTF-8
// (profile.json would not load again).
pub fn clipUtf8(text: []const u8, max: usize) ?[]const u8 {
    if (!std.unicode.utf8ValidateSlice(text)) return null;
    if (text.len <= max) return text;
    var end = max;
    // Back up over continuation bytes (0b10xxxxxx) to the first byte of the character that crosses `max`.
    while (end > 0 and text[end] & 0xC0 == 0x80) end -= 1;
    return text[0..end];
}

pub fn onGetPlayerBoardData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    const saved = ProfileStore.get();
    var rsp = protocol.GetPlayerBoardDataScRsp.init(allocator);
    var display_list = protocol.DisplayAvatarVec.init(allocator);
    const player_icon_config = &ConfigManager.global_game_config_cache.player_icon_config;
    display_list.is_display = true;
    rsp.retcode = 0;
    try rsp.unlocked_personal_card_list.appendSlice(&Data.OwnedPersonalCardSkin);
    rsp.current_personal_card_id = curPersonalCard();
    rsp.current_head_icon_id = curHeadIcon();
    rsp.head_frame_info = .{
        .head_frame_expire_time = 4294967295,
        .head_frame_item_id = 226004,
    };
    rsp.signature = .{ .Const = saved.signature };
    try rsp.assist_avatar_id_list.appendSlice(try boardAssist(allocator));
    for (try boardDisplay(allocator)) |entry| {
        try display_list.display_avatar_list.append(.{ .avatar_id = entry.avatar_id, .pos = entry.pos });
    }
    rsp.display_avatar_vec = display_list;
    for (player_icon_config.player_icon_config.items) |head_id| {
        const head_icon = protocol.HeadIconData{
            .id = head_id.id,
        };
        try rsp.unlocked_head_icon_list.append(head_icon);
    }
    try session.send(CmdID.CmdGetPlayerBoardDataScRsp, rsp);
}
pub fn onSetAssistAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetAssistAvatarCsReq, allocator);
    defer req.deinit();
    // A request naming one avatar in avatar_id instead of the list.
    const single = [1]u32{req.avatar_id};
    const ids: []const u32 = if (req.avatar_id_list.items.len == 0 and req.avatar_id != 0) &single else req.avatar_id_list.items;
    if (try pickAssist(allocator, ids)) |picked| ProfileStore.set("assist_avatars", picked);

    var rsp = protocol.SetAssistAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    try rsp.avatar_id_list.appendSlice(try boardAssist(allocator));
    try session.send(CmdID.CmdSetAssistAvatarScRsp, rsp);
}
pub fn onSetDisplayAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetDisplayAvatarCsReq, allocator);
    defer req.deinit();
    if (try pickDisplay(allocator, req.display_avatar_list.items)) |picked| ProfileStore.set("display_avatars", picked);

    var rsp = protocol.SetDisplayAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    for (try boardDisplay(allocator)) |entry| {
        try rsp.display_avatar_list.append(.{ .avatar_id = entry.avatar_id, .pos = entry.pos });
    }
    try session.send(CmdID.CmdSetDisplayAvatarScRsp, rsp);
}
// Echoed only: the board always shows its avatars.
pub fn onSetIsDisplayAvatarInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetIsDisplayAvatarInfoCsReq, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdSetIsDisplayAvatarInfoScRsp, protocol.SetIsDisplayAvatarInfoScRsp{
        .retcode = 0,
        .is_display = req.is_display,
    });
}

pub fn onSetSignature(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetSignatureCsReq, allocator);
    defer req.deinit();
    if (clipUtf8(req.signature.getSlice(), max_signature)) |text| {
        if (!std.mem.eql(u8, text, ProfileStore.get().signature)) ProfileStore.set("signature", text);
    }

    var rsp = protocol.SetSignatureScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.signature = .{ .Const = ProfileStore.get().signature };
    try session.send(CmdID.CmdSetSignatureScRsp, rsp);
}
pub fn onSetGameplayBirthday(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetGameplayBirthdayCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SetGameplayBirthdayScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.birthday = req.birthday;
    try session.send(CmdID.CmdSetGameplayBirthdayScRsp, rsp);
}
pub fn onSetHeadIcon(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetHeadIconCsReq, allocator);
    defer req.deinit();
    // Only icons GetPlayerBoardData lists as unlocked.
    if (req.id != curHeadIcon() and unlockedHeadIcon(req.id)) ProfileStore.set("head_icon", req.id);

    var rsp = protocol.SetHeadIconScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.current_head_icon_id = curHeadIcon();
    try session.send(CmdID.CmdSetHeadIconScRsp, rsp);
}
pub fn onSelectPhoneCase(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPhoneCaseCsReq, allocator);
    defer req.deinit();
    if (req.phone_case_id != curPhoneCase() and owns(&Data.OwnedPhoneCases, req.phone_case_id)) {
        ProfileStore.set("phone_case", req.phone_case_id);
    }

    var rsp = protocol.SelectPhoneCaseScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_phone_case = curPhoneCase();
    try session.send(CmdID.CmdSelectPhoneCaseScRsp, rsp);
}
pub fn onUpdatePlayerSetting(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.UpdatePlayerSettingCsReq, allocator);
    defer req.deinit();

    try session.send(CmdID.CmdUpdatePlayerSettingScRsp, protocol.UpdatePlayerSettingScRsp{
        .player_setting = req.player_setting,
        .retcode = 0,
    });
}
// A card avatar with its config.json level, eidolons and Light Cone; the fixed defaults show at level 80.
fn detailAvatar(allocator: Allocator, base_id: u32, pos: u32) protocol.DisplayAvatarDetailInfo {
    var info = protocol.DisplayAvatarDetailInfo.init(allocator);
    info.avatar_id = base_id;
    info.pos = pos;
    if (configAvatar(base_id)) |avatar| {
        info.level = avatar.level;
        info.promotion = avatar.promotion;
        info.rank = avatar.rank;
        info.equipment = .{
            .tid = avatar.lightcone.id,
            .level = avatar.lightcone.level,
            .rank = avatar.lightcone.rank,
            .promotion = avatar.lightcone.promotion,
        };
    } else {
        info.level = 80;
        info.promotion = 6;
    }
    return info;
}

pub fn onGetPlayerDetailInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetPlayerDetailInfoCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.GetPlayerDetailInfoScRsp.init(allocator);
    rsp.retcode = 0;
    var detail = protocol.PlayerDetailInfo.init(allocator);
    detail.head_frame_info = .{
        .head_frame_expire_time = 4294967295,
        .head_frame_item_id = 226004,
    };
    detail.uid = req.uid;
    detail.world_level = 6;
    detail.level = 70;
    // MushiSR's card stays bare; every other uid is the player.
    if (req.uid != commandhandler.bot_uid) {
        const saved = ProfileStore.get();
        detail.nickname = .{ .Const = saved.nickname };
        detail.signature = .{ .Const = saved.signature };
        detail.head_icon = curHeadIcon();
        detail.chat_bubble = curChatBubble();
        detail.gender = AvatarManager.gender;
        for (try boardDisplay(allocator)) |entry| {
            try detail.display_avatar_list.append(detailAvatar(allocator, entry.avatar_id, entry.pos));
        }
        for (try boardAssist(allocator), 0..) |id, pos| {
            try detail.assist_avatar_list.append(detailAvatar(allocator, id, @intCast(pos)));
        }
    }
    rsp.detail_info = detail;
    try session.send(CmdID.CmdGetPlayerDetailInfoScRsp, rsp);
}
pub fn onSetPersonalCard(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetPersonalCardCsReq, allocator);
    defer req.deinit();
    if (req.id != curPersonalCard() and owns(&Data.OwnedPersonalCardSkin, req.id)) {
        ProfileStore.set("personal_card", req.id);
    }

    try session.send(CmdID.CmdSetPersonalCardScRsp, protocol.SetPersonalCardScRsp{
        .current_personal_card_id = curPersonalCard(),
        .retcode = 0,
    });
}

// The name as typed without the spaces around it; null if that is empty, longer than 32 bytes or not UTF-8.
pub fn cleanNickname(raw: []const u8) ?[]const u8 {
    if (!std.unicode.utf8ValidateSlice(raw)) return null;
    const name = std.mem.trim(u8, raw, " \t\r\n");
    if (name.len == 0 or name.len > max_nickname) return null;
    return name;
}

pub fn onSetNickname(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetNicknameCsReq, allocator);
    defer req.deinit();
    const name = cleanNickname(req.nickname.getSlice()) orelse {
        try session.send(CmdID.CmdSetNicknameScRsp, protocol.SetNicknameScRsp{
            .retcode = @intCast(@intFromEnum(protocol.Retcode.RET_NICKNAME_FORMAT_ERROR)),
            .is_modify = req.is_modify,
        });
        return;
    };
    if (!std.mem.eql(u8, name, ProfileStore.get().nickname)) ProfileStore.set("nickname", name);
    try session.send(CmdID.CmdSetNicknameScRsp, protocol.SetNicknameScRsp{
        .retcode = 0,
        .is_modify = req.is_modify,
        .set_time = @intCast(Clock.nowSec()),
    });
    // The new name shows at once, with the rest of the basic info as at login.
    var sync = protocol.PlayerSyncScNotify.init(allocator);
    sync.basic_info = Login.basicInfo(allocator);
    try session.send(CmdID.CmdPlayerSyncScNotify, sync);
}

// The Trailblazer's path as the client names it.
fn curAvatarPath() protocol.MultiPathAvatarType {
    return @enumFromInt(@as(i32, @intCast(AvatarManager.mc_id)));
}

// Gender follows the Trailblazer in config.json (/hero gender changes it), so this only reports the current path.
pub fn onSetGender(session: *Session, _: *const Packet, _: Allocator) !void {
    try session.send(CmdID.CmdSetGenderScRsp, protocol.SetGenderScRsp{
        .retcode = 0,
        .cur_avatar_path = curAvatarPath(),
    });
}

// The opening's name-and-gender step. The opening never runs here, so it is only answered.
pub fn onSetPlayerInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetPlayerInfoCsReq, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdSetPlayerInfoScRsp, protocol.SetPlayerInfoScRsp{
        .retcode = 0,
        .is_modify = req.is_modify,
        .set_time = @intCast(Clock.nowSec()),
        .cur_avatar_path = curAvatarPath(),
    });
}

test "a nickname is trimmed and must be 1 to 32 bytes of UTF-8" {
    try std.testing.expectEqualStrings("Stelle", cleanNickname("  Stelle \t").?);
    try std.testing.expect(cleanNickname("   ") == null);
    try std.testing.expect(cleanNickname("") == null);
    try std.testing.expectEqualStrings("a" ** 32, cleanNickname("a" ** 32).?);
    try std.testing.expect(cleanNickname("a" ** 33) == null);
    try std.testing.expect(cleanNickname("\xff\xfe") == null);
    // Thai letters are 3 bytes: ten fit, eleven do not.
    try std.testing.expect(cleanNickname("ก" ** 10) != null);
    try std.testing.expect(cleanNickname("ก" ** 11) == null);
}

test "a signature is cut on a character boundary" {
    try std.testing.expectEqualStrings("abc", clipUtf8("abc", 256).?);
    try std.testing.expectEqualStrings("ab", clipUtf8("abcd", 2).?);
    // "aéé" is 5 bytes; 4 would split the second "é", so the cut keeps "aé" (3 bytes).
    try std.testing.expectEqualStrings("aé", clipUtf8("aéé", 4).?);
    try std.testing.expectEqualStrings("", clipUtf8("é", 1).?);
    try std.testing.expect(clipUtf8("\xff\xfe", 256) == null);
}
