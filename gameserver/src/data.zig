const std = @import("std");
const ConfigManager = @import("./manager/config_mgr.zig");

// Avatar group
pub var EnhanceAvatarID = [_]u32{ 1005, 1006, 1205, 1212, 1306, 1307, 1306, 1102, 1217, 1310, 1004 };
pub const ExRankAvatarID = [_]u32{ 120401, 121301, 130801 };

pub var AllAvatars: []const u32 = &.{};
pub var AvatarGlobalBuff = [_]u32{ 1407, 1506, 1511 };

pub var AvatarSkinMap = [_]struct {
    avatar_id: u32,
    skin_id: u32,
}{
    .{ .avatar_id = 1001, .skin_id = 1100101 },
    .{ .avatar_id = 1303, .skin_id = 1130301 },
    .{ .avatar_id = 1310, .skin_id = 1131001 },
    .{ .avatar_id = 1415, .skin_id = 1141501 },
    .{ .avatar_id = 1407, .skin_id = 1140701 },
    .{ .avatar_id = 1501, .skin_id = 1150101 },
    .{ .avatar_id = 1505, .skin_id = 1150501 },
    .{ .avatar_id = 1409, .skin_id = 1140901 },
};

// Battle group
pub const IgnoreBattle = [_]u32{ 1509, 1504, 1501, 1414, 1405, 1404, 1225, 1321, 1314, 1312, 1305, 1302, 1217, 1108 };
pub const SkipBattle = [_]u32{ 1506, 1408, 1308, 1510 };

//TODO: update id for characters have ignore toughness in their technique in future
pub const IgnoreToughness = [_]u32{ 1006, 1308, 1317 };

// Profile group
pub const OwnedChatBubbles = [_]u32{ 220000, 220001, 220002, 220003, 220004, 220005, 220006, 220007, 220008, 220009, 220010, 220012 };
pub const OwnedPhoneThemes = [_]u32{ 221000, 221001, 221002, 221003, 221004, 221005, 221006, 221007, 221008, 221009, 221010, 221011, 221012, 221013 };
pub const OwnedPhoneCases = [_]u32{ 254000, 254001 };
pub const OwnedPersonalCardSkin = [_]u32{ 253000, 253001, 253002, 253003, 253004, 253005 };

// No pet items: the 4.6 pet tab takes every pet from PetModule (GetPetData) and cannot sort a pet item from the bag.
pub const ItemList = [_]u32{ 101, 238, 239 };

// Pets (PetConfig): pet id, its item and its summon unit. The summon units are IsClient, so the client spawns a
// summoned pet itself and the server only remembers which one is out.
pub const Pet = struct { id: u32, item_id: u32, summon_unit_id: u32 };
pub const Pets = [_]Pet{
    .{ .id = 1001, .item_id = 251001, .summon_unit_id = 24001 },
    .{ .id = 1002, .item_id = 251002, .summon_unit_id = 32001 },
    .{ .id = 1003, .item_id = 251003, .summon_unit_id = 36001 },
    .{ .id = 1004, .item_id = 251004, .summon_unit_id = 42001 },
    .{ .id = 1005, .item_id = 251005, .summon_unit_id = 44001 },
};
// Blind-box pets (BlindBoxPet), each sent as a pet instance whose unique id is the pet id. Live 4.6.0 data, as the
// 4.6.5x beta client's own table is not at hand: drop any id the client turns out not to have.
pub const BlindBoxPets = [_]u32{
    251501, 251502, 251503, 251504, 251505, 251506, 251507, 251508, 251509, 251510, 251511, 251512,
    251520, 251521, 251522, 251523, 251524,
};
pub const SkinList = [_]u32{ 1130301, 1100101, 1131001, 1141501, 1140701, 1150101, 1150501, 1140901 };
pub const PlayerOutfitList = [_]u32{ 227016, 227015, 229001, 227004, 227013, 227012, 227010, 227009, 227008, 227007, 227006, 227005, 227003, 227002, 227001 };
// The Trailblazer's outfits (PlayerOutfitBase) as the client dresses them: outfit id and the item that owns it, 0 for
// a slot's default (no item). Only outfits whose item is in PlayerOutfitList.
pub const PlayerOutfit = struct { id: u32, item_id: u32 };
pub const PlayerOutfits = [_]PlayerOutfit{
    .{ .id = 1000, .item_id = 0 },      .{ .id = 1001, .item_id = 227001 }, .{ .id = 1002, .item_id = 227002 },
    .{ .id = 1003, .item_id = 227003 }, .{ .id = 1004, .item_id = 227004 }, .{ .id = 1005, .item_id = 227005 },
    .{ .id = 1006, .item_id = 227006 }, .{ .id = 1007, .item_id = 227007 }, .{ .id = 1008, .item_id = 227008 },
    .{ .id = 1009, .item_id = 227009 }, .{ .id = 1010, .item_id = 227010 }, .{ .id = 1012, .item_id = 227012 },
    .{ .id = 1013, .item_id = 227013 }, .{ .id = 1016, .item_id = 227016 }, .{ .id = 2000, .item_id = 0 },
    .{ .id = 2100, .item_id = 0 },      .{ .id = 2200, .item_id = 0 },      .{ .id = 2300, .item_id = 0 },
    .{ .id = 2400, .item_id = 0 },      .{ .id = 3000, .item_id = 0 },      .{ .id = 3001, .item_id = 229001 },
    .{ .id = 4000, .item_id = 0 },      .{ .id = 4001, .item_id = 227015 },
};

pub const LightconeList_3 = [_]u32{
    20000, 20001, 20002, 20003, 20004, 20005, 20006, 20007, 20008, 20009, 20010, 20011, 20012, 20013, 20014, 20015, 20016, 20017, 20018, 20019, 20020, 20021, 20022,
};
pub const LightconeList_4 = [_]u32{
    21000, 21001, 21002, 21003, 21004, 21005, 21006, 21007, 21008, 21009, 21010, 21011, 21012, 21013, 21014, 21015, 21016, 21017, 21018, 21019, 21020, 21021, 21022,
    21023, 21024, 21025, 21026, 21027, 21028, 21029, 21030, 21031, 21032, 21033, 21034, 21035, 21036, 21037, 21038, 21039, 21040, 21041, 21042, 21043, 21044, 21045,
    21046, 21047, 21048, 21050, 21051, 21052, 22000, 22001, 22002, 22003, 22004,
};
pub var AvatarList: []const u32 = &.{};

pub var WorldId: u32 = 601;
