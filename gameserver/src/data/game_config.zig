const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const BattleConfig = struct {
    battle_id: u32,
    stage_id: u32,
    cycle_count: u32,
    monster_wave: ArrayList(ArrayList(u32)),
    monster_level: u32,
    blessings: ArrayList(u32),
};

pub const Lightcone = struct {
    id: u32,
    rank: u32,
    level: u32,
    promotion: u32,
};

pub const Relic = struct {
    id: u32,
    level: u32,
    main_affix_id: u32,
    sub_count: u32,
    stat1: u32,
    cnt1: u32,
    step1: u32,
    stat2: u32,
    cnt2: u32,
    step2: u32,
    stat3: u32,
    cnt3: u32,
    step3: u32,
    stat4: u32,
    cnt4: u32,
    step4: u32,
};

pub const Avatar = struct {
    id: u32,
    hp: u32,
    sp: u32,
    level: u32,
    promotion: u32,
    rank: u32,
    lightcone: Lightcone,
    relics: ArrayList(Relic),
    use_technique: bool,
};

const StatCount = struct {
    stat: u32,
    count: u32,
    step: u32,
};

pub const GameConfig = struct {
    battle_config: BattleConfig,
    avatar_config: ArrayList(Avatar),

    pub fn deinit(self: *GameConfig) void {
        for (self.battle_config.monster_wave.items) |*wave| {
            wave.deinit();
        }
        self.battle_config.monster_wave.deinit();
        self.battle_config.blessings.deinit();

        for (self.avatar_config.items) |*avatar| {
            avatar.relics.deinit();
        }
        self.avatar_config.deinit();
    }
};

pub fn parseConfig(root: std.json.Value, allocator: Allocator) anyerror!GameConfig {
    const battle_json = try objectField(root, "battle_config");
    var config = GameConfig{
        .battle_config = .{
            .battle_id = try intField(battle_json, "battle_id"),
            .stage_id = try intField(battle_json, "stage_id"),
            .cycle_count = try intField(battle_json, "cycle_count"),
            .monster_wave = ArrayList(ArrayList(u32)).init(allocator),
            .monster_level = try intField(battle_json, "monster_level"),
            .blessings = ArrayList(u32).init(allocator),
        },
        .avatar_config = ArrayList(Avatar).init(allocator),
    };
    errdefer config.deinit();

    for ((try arrayField(battle_json, "monster_wave")).items) |wave| {
        if (wave != .array) return invalid("monster_wave");
        var wave_list = ArrayList(u32).init(allocator);
        errdefer wave_list.deinit();
        for (wave.array.items) |monster| try wave_list.append(try intValue(monster, "monster_wave"));
        try config.battle_config.monster_wave.append(wave_list);
    }
    for ((try arrayField(battle_json, "blessings")).items) |blessing| {
        try config.battle_config.blessings.append(try intValue(blessing, "blessings"));
    }

    for ((try arrayField(root, "avatar_config")).items) |avatar_json| {
        const lightcone_json = try objectField(avatar_json, "lightcone");
        var avatar = Avatar{
            .id = try intField(avatar_json, "id"),
            .hp = try intField(avatar_json, "hp"),
            .sp = try intField(avatar_json, "sp"),
            .level = try intField(avatar_json, "level"),
            .promotion = try intField(avatar_json, "promotion"),
            .rank = try intField(avatar_json, "rank"),
            .lightcone = .{
                .id = try intField(lightcone_json, "id"),
                .rank = try intField(lightcone_json, "rank"),
                .level = try intField(lightcone_json, "level"),
                .promotion = try intField(lightcone_json, "promotion"),
            },
            .relics = ArrayList(Relic).init(allocator),
            .use_technique = try boolField(avatar_json, "use_technique"),
        };
        errdefer avatar.relics.deinit();
        for ((try arrayField(avatar_json, "relics")).items) |relic_json| {
            if (relic_json != .string) return invalid("relics");
            try avatar.relics.append(try parseRelic(relic_json.string, allocator));
        }
        try config.avatar_config.append(avatar);
    }
    return config;
}

// config.json is edited by hand and written by SRTools sync, so bad input is reported, not a crash.
fn invalid(key: []const u8) error{InvalidConfig} {
    std.log.err("config.json: \"{s}\" is missing or has the wrong type", .{key});
    return error.InvalidConfig;
}
fn objectField(v: std.json.Value, key: []const u8) !std.json.Value {
    if (v != .object) return invalid(key);
    const field = v.object.get(key) orelse return invalid(key);
    return if (field == .object) field else invalid(key);
}
fn arrayField(v: std.json.Value, key: []const u8) !std.json.Array {
    if (v != .object) return invalid(key);
    const field = v.object.get(key) orelse return invalid(key);
    return if (field == .array) field.array else invalid(key);
}
fn boolField(v: std.json.Value, key: []const u8) !bool {
    if (v != .object) return invalid(key);
    const field = v.object.get(key) orelse return invalid(key);
    return if (field == .bool) field.bool else invalid(key);
}
fn intField(v: std.json.Value, key: []const u8) !u32 {
    if (v != .object) return invalid(key);
    return intValue(v.object.get(key) orelse return invalid(key), key);
}
fn intValue(v: std.json.Value, key: []const u8) !u32 {
    return switch (v) {
        .integer => |i| std.math.cast(u32, i) orelse invalid(key),
        .float => |f| if (f >= 0 and f <= std.math.maxInt(u32)) @intFromFloat(@round(f)) else invalid(key),
        else => invalid(key),
    };
}

fn parseRelic(relic_str: []const u8, allocator: Allocator) !Relic {
    var tokens = ArrayList([]const u8).init(allocator);
    defer tokens.deinit();

    var iterator = std.mem.tokenizeScalar(u8, relic_str, ',');

    while (iterator.next()) |token| {
        try tokens.append(token);
    }

    const tokens_slice = tokens.items;

    if (tokens_slice.len < 5) {
        std.debug.print("relic parsing critical error (too few fields): {s}\n", .{relic_str});
        return error.InsufficientTokens;
    }

    const stat1 = try parseStatCount(tokens_slice[4]);
    const stat2 = if (tokens_slice.len > 5) try parseStatCount(tokens_slice[5]) else StatCount{ .stat = 0, .count = 0, .step = 0 };
    const stat3 = if (tokens_slice.len > 6) try parseStatCount(tokens_slice[6]) else StatCount{ .stat = 0, .count = 0, .step = 0 };
    const stat4 = if (tokens_slice.len > 7) try parseStatCount(tokens_slice[7]) else StatCount{ .stat = 0, .count = 0, .step = 0 };

    const relic = Relic{
        .id = try std.fmt.parseInt(u32, tokens_slice[0], 10),
        .level = try std.fmt.parseInt(u32, tokens_slice[1], 10),
        .main_affix_id = try std.fmt.parseInt(u32, tokens_slice[2], 10),
        .sub_count = try std.fmt.parseInt(u32, tokens_slice[3], 10),
        .stat1 = stat1.stat,
        .cnt1 = stat1.count,
        .step1 = stat1.step,
        .stat2 = stat2.stat,
        .cnt2 = stat2.count,
        .step2 = stat2.step,
        .stat3 = stat3.stat,
        .cnt3 = stat3.count,
        .step3 = stat3.step,
        .stat4 = stat4.stat,
        .cnt4 = stat4.count,
        .step4 = stat4.step,
    };

    return relic;
}

// "stat:count:step"; SRTools' config.json leaves the step out unless "Use step on relic?" is ticked.
fn parseStatCount(token: []const u8) !StatCount {
    var parts = std.mem.splitScalar(u8, token, ':');
    const stat = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidFormat, 10);
    const count = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidFormat, 10);
    const step = if (parts.next()) |text| try std.fmt.parseInt(u32, text, 10) else 0;
    if (parts.next() != null) return error.InvalidFormat;
    return StatCount{ .stat = stat, .count = count, .step = step };
}
