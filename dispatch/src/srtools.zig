//! SRTools (https://srtools.neonteam.dev) "Connect PS" support.
//!
//! Provider "Other" POSTs to the Server URL exactly as typed, provider "RobinSR" appends /srtools:
//!   {"username", "password"}          Connect button: any 2xx means connected.
//!   {"data", "username", "password"}  Sync button: `data` is freesr-data.json.
//! Errors must be JSON with a `message`, which the site shows as a toast.
//!
//! A sync is converted into this server's config.json (the file /sync and the gameserver read),
//! written atomically; the gameserver notices the new file and pushes it to the player in-game.

const std = @import("std");
const httpz = @import("httpz");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Value = std.json.Value;
const log = std.log.scoped(.srtools);

const CONFIG_FILE = "config.json";
const FREESR_FILE = "freesr-data.json";
const BACKUP_DIR = "config-backups";
const ORIGINAL_BACKUP = "config-before-first-sync.json";
const BACKUP_KEEP = 20;

const MAX_MONSTERS_PER_WAVE = 5;
// Lightcone for a built character with none equipped; the same one SRTools' own config.json export uses.
const FALLBACK_LIGHTCONE = Lightcone{ .id = 23021, .rank = 1, .level = 80, .promotion = 6 };

// Browsers may send several requests at once; config.json is rewritten one sync at a time.
var write_lock = std.Thread.Mutex{};

pub fn onPreflight(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 204;
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.header("Access-Control-Allow-Headers", "Content-Type");
    res.header("Access-Control-Allow-Private-Network", "true");
    res.header("Access-Control-Max-Age", "86400");
}

pub fn onPost(req: *httpz.Request, res: *httpz.Response) !void {
    res.header("Access-Control-Allow-Origin", "*");
    const body = req.body() orelse return reply(res, 200, "OK");
    const root = std.json.parseFromSliceLeaky(Value, res.arena, body, .{}) catch {
        return reply(res, 400, "Request body is not valid JSON");
    };
    if (root != .object) return reply(res, 400, "Request body is not a JSON object");

    const data = root.object.get("data") orelse {
        log.info("SRTools connected", .{});
        return reply(res, 200, "OK");
    };
    if (data != .object) return reply(res, 400, "`data` is not a freesr-data object");

    write_lock.lock();
    defer write_lock.unlock();
    const summary = sync(res.arena, data) catch |err| {
        log.err("SRTools sync failed: {}", .{err});
        if (err == error.NoBuiltAvatars) {
            return reply(res, 400, "No character has a light cone or relic equipped, so there is nothing to sync");
        }
        return reply(res, 500, try std.fmt.allocPrint(res.arena, "The server could not save config.json ({s}); is it open in another program?", .{@errorName(err)}));
    };
    log.info("SRTools sync saved {d} characters and the battle setup to config.json", .{summary.avatars});
    return reply(res, 200, "OK");
}

fn reply(res: *httpz.Response, status: u16, message: []const u8) !void {
    res.status = status;
    try res.json(.{ .message = message, .status = status }, .{});
}

// ---------------------------------------------------------------- config.json

const Lightcone = struct {
    id: u32,
    rank: u32,
    level: u32,
    promotion: u32,
};
const Avatar = struct {
    name: []const u8,
    id: u32,
    hp: u32,
    sp: u32,
    level: u32,
    promotion: u32,
    rank: u32,
    lightcone: Lightcone,
    relics: []const []const u8,
    use_technique: bool,
};
const BattleConfig = struct {
    battle_id: u32,
    stage_id: u32,
    cycle_count: u32,
    monster_wave: []const []const u32,
    monster_level: u32,
    blessings: []const u32,
};
const Config = struct {
    avatar_config: []const Avatar,
    battle_config: BattleConfig,
};

const Summary = struct { avatars: usize };

fn sync(arena: Allocator, data: Value) !Summary {
    const old = readOldConfig(arena);
    const config = Config{
        .avatar_config = try convertAvatars(arena, data, old),
        .battle_config = try convertBattle(arena, data, old),
    };
    if (config.avatar_config.len == 0) return error.NoBuiltAvatars;

    var out = ArrayList(u8).init(arena);
    try std.json.stringify(config, .{ .whitespace = .indent_2 }, out.writer());
    var raw = ArrayList(u8).init(arena);
    try std.json.stringify(data, .{ .whitespace = .indent_2 }, raw.writer());

    try backupConfig(arena);
    try writeAtomic(FREESR_FILE, raw.items);
    try writeAtomic(CONFIG_FILE, out.items);
    return .{ .avatars = config.avatar_config.len };
}

fn writeAtomic(path: []const u8, bytes: []const u8) !void {
    var file = try std.fs.cwd().atomicFile(path, .{});
    defer file.deinit();
    try file.file.writeAll(bytes);
    try file.file.sync();
    try file.finish();
}

// A sync replaces every character, so the config.json it replaces is kept: the one from before the
// first sync for good, plus the last BACKUP_KEEP. Without a backup the sync does not go ahead.
fn backupConfig(arena: Allocator) !void {
    const cwd = std.fs.cwd();
    cwd.access(CONFIG_FILE, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    var dir = try cwd.makeOpenPath(BACKUP_DIR, .{ .iterate = true });
    defer dir.close();
    dir.access(ORIGINAL_BACKUP, .{}) catch |err| switch (err) {
        error.FileNotFound => try cwd.copyFile(CONFIG_FILE, dir, ORIGINAL_BACKUP, .{}),
        else => return err,
    };
    try cwd.copyFile(CONFIG_FILE, dir, try backupName(arena), .{});
    pruneBackups(arena, dir) catch |err| log.warn("could not remove old config backups: {}", .{err});
}

// config-YYYYMMDD-HHMMSS-mmm-UTC.json, which sorts oldest first.
fn backupName(arena: Allocator) ![]const u8 {
    const ms: u64 = @intCast(std.time.milliTimestamp());
    const secs = std.time.epoch.EpochSeconds{ .secs = ms / 1000 };
    const year_day = secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const time = secs.getDaySeconds();
    return std.fmt.allocPrint(arena, "config-{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}-{d:0>3}-UTC.json", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        time.getHoursIntoDay(),
        time.getMinutesIntoHour(),
        time.getSecondsIntoMinute(),
        ms % 1000,
    });
}

fn pruneBackups(arena: Allocator, dir: std.fs.Dir) !void {
    var names = ArrayList([]const u8).init(arena);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.startsWith(u8, entry.name, "config-2")) continue;
        try names.append(try arena.dupe(u8, entry.name));
    }
    if (names.items.len <= BACKUP_KEEP) return;
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    for (names.items[0 .. names.items.len - BACKUP_KEEP]) |name| try dir.deleteFile(name);
}

fn readOldConfig(arena: Allocator) ?Value {
    const text = std.fs.cwd().readFileAlloc(arena, CONFIG_FILE, 64 * 1024 * 1024) catch return null;
    const root = std.json.parseFromSliceLeaky(Value, arena, text, .{}) catch return null;
    return if (root == .object) root else null;
}

// Characters that have gear in SRTools. The site sends every character in the game, and each one in
// config.json becomes a party candidate, so untouched ones are left out. Characters already in
// config.json keep their order (the first 4 form the overworld team); new ones follow in SRTools order.
fn convertAvatars(arena: Allocator, data: Value, old: ?Value) ![]const Avatar {
    const avatars = objectField(data, "avatars") orelse return &.{};
    const lightcones = arrayField(data, "lightcones");
    const relics = arrayField(data, "relics");

    var built = std.AutoArrayHashMap(u32, Value).init(arena);
    var it = avatars.object.iterator();
    while (it.next()) |entry| {
        const avatar = entry.value_ptr.*;
        if (avatar != .object or boolField(avatar, "_hidden")) continue;
        const id = intField(avatar, "avatar_id") orelse (std.fmt.parseInt(u32, entry.key_ptr.*, 10) catch continue);
        if (id == 0 or !hasGear(id, lightcones, relics)) continue;
        try built.put(id, avatar);
    }

    var order = ArrayList(u32).init(arena);
    if (old) |o| if (arrayField(o, "avatar_config")) |list| for (list.items) |entry| {
        const id = intField(entry, "id") orelse continue;
        if (built.contains(id) and std.mem.indexOfScalar(u32, order.items, id) == null) try order.append(id);
    };
    for (built.keys()) |id| {
        if (std.mem.indexOfScalar(u32, order.items, id) == null) try order.append(id);
    }

    var result = ArrayList(Avatar).init(arena);
    for (order.items) |id| {
        const avatar = built.get(id).?;
        const old_entry = findOldAvatar(old, id);
        const sp_max = intField(avatar, "sp_max") orelse 0;
        const sp_value = intField(avatar, "sp_value") orelse 0;
        try result.append(.{
            .name = if (old_entry) |e| stringField(e, "name") orelse try idName(arena, id) else try idName(arena, id),
            .id = id,
            .hp = if (old_entry) |e| @min(intField(e, "hp") orelse 100, 100) else 100,
            .sp = if (sp_max > 0) @intCast(@min((@as(u64, sp_value) * 100 + sp_max / 2) / sp_max, 100)) else 50,
            .level = clamp(intField(avatar, "level") orelse 80, 1, 80),
            .promotion = clamp(intField(avatar, "promotion") orelse 6, 0, 6),
            .rank = clamp(if (objectField(avatar, "data")) |d| intField(d, "rank") orelse 0 else 0, 0, 6),
            .lightcone = equippedLightcone(id, lightcones),
            .relics = try equippedRelics(arena, id, relics),
            .use_technique = if (arrayField(avatar, "techniques")) |t| t.items.len > 0 else true,
        });
    }
    return result.toOwnedSlice();
}

fn hasGear(id: u32, lightcones: ?std.json.Array, relics: ?std.json.Array) bool {
    for ([_]?std.json.Array{ lightcones, relics }) |maybe_list| {
        const list = maybe_list orelse continue;
        for (list.items) |item| {
            if ((intField(item, "equip_avatar") orelse 0) == id) return true;
        }
    }
    return false;
}

fn equippedLightcone(id: u32, lightcones: ?std.json.Array) Lightcone {
    const list = lightcones orelse return FALLBACK_LIGHTCONE;
    for (list.items) |item| {
        if ((intField(item, "equip_avatar") orelse 0) != id) continue;
        const item_id = intField(item, "item_id") orelse continue;
        return .{
            .id = item_id,
            .rank = clamp(intField(item, "rank") orelse 1, 1, 5),
            .level = clamp(intField(item, "level") orelse 80, 1, 80),
            .promotion = clamp(intField(item, "promotion") orelse 6, 0, 6),
        };
    }
    return FALLBACK_LIGHTCONE;
}

// "relic_id,level,main_affix_id,sub_count,sub:count:step,..." with at most 4 subs, one relic per
// slot (the last digit of the relic id), sorted by slot. The gameserver needs at least one sub.
fn equippedRelics(arena: Allocator, id: u32, relics: ?std.json.Array) ![]const []const u8 {
    const list = relics orelse return &.{};
    var by_slot = [_]?[]const u8{null} ** 6;
    for (list.items) |item| {
        if ((intField(item, "equip_avatar") orelse 0) != id) continue;
        const relic_id = intField(item, "relic_id") orelse continue;
        const slot = relic_id % 10;
        if (slot < 1 or slot > 6) continue;

        var subs = ArrayList(u8).init(arena);
        var sub_count: u32 = 0;
        if (arrayField(item, "sub_affixes")) |sub_list| for (sub_list.items) |sub| {
            if (sub_count == 4) break;
            const sub_id = intField(sub, "sub_affix_id") orelse continue;
            if (sub_id == 0) continue;
            const count = clamp(intField(sub, "count") orelse 1, 1, 99);
            const step = @min(intField(sub, "step") orelse 0, count * 2);
            try subs.writer().print(",{d}:{d}:{d}", .{ sub_id, count, step });
            sub_count += 1;
        };
        if (sub_count == 0) continue;

        by_slot[slot - 1] = try std.fmt.allocPrint(arena, "{d},{d},{d},{d}{s}", .{
            relic_id,
            clamp(intField(item, "level") orelse 15, 0, 15),
            intField(item, "main_affix_id") orelse 1,
            sub_count,
            subs.items,
        });
    }
    var result = ArrayList([]const u8).init(arena);
    for (by_slot) |relic| if (relic) |r| try result.append(r);
    return result.toOwnedSlice();
}

// The SRTools battle setup, keeping values from the old config for anything it leaves empty.
fn convertBattle(arena: Allocator, data: Value, old: ?Value) !BattleConfig {
    const old_battle = if (old) |o| objectField(o, "battle_config") else null;
    const battle = objectField(data, "battle_config");

    var waves = ArrayList([]const u32).init(arena);
    var monster_level: u32 = 0;
    if (battle) |b| if (arrayField(b, "monsters")) |wave_list| for (wave_list.items) |wave| {
        if (wave != .array) continue;
        var ids = ArrayList(u32).init(arena);
        for (wave.array.items) |monster| {
            const monster_id = intField(monster, "monster_id") orelse continue;
            if (monster_id == 0) continue;
            monster_level = @max(monster_level, intField(monster, "level") orelse 0);
            var amount = @max(intField(monster, "amount") orelse 1, 1);
            while (amount > 0 and ids.items.len < MAX_MONSTERS_PER_WAVE) : (amount -= 1) try ids.append(monster_id);
        }
        if (ids.items.len > 0) try waves.append(try ids.toOwnedSlice());
    };
    if (waves.items.len == 0) {
        if (old_battle) |ob| if (arrayField(ob, "monster_wave")) |old_waves| for (old_waves.items) |wave| {
            if (wave != .array) continue;
            var ids = ArrayList(u32).init(arena);
            for (wave.array.items) |monster| if (intValue(monster)) |m| try ids.append(m);
            if (ids.items.len > 0) try waves.append(try ids.toOwnedSlice());
        };
    }
    if (waves.items.len == 0) try waves.append(&[_]u32{4035010});

    var blessings = ArrayList(u32).init(arena);
    if (battle) |b| if (arrayField(b, "blessings")) |list| for (list.items) |blessing| {
        if (intField(blessing, "id")) |bid| if (bid != 0) try blessings.append(bid);
    };

    const is_pf = if (battle) |b| std.mem.eql(u8, stringField(b, "battle_type") orelse "", "PF") else false;
    const cycles = if (battle) |b| intField(b, "cycle_count") orelse 0 else 0;
    const stage = if (battle) |b| intField(b, "stage_id") orelse 0 else 0;
    return .{
        .battle_id = if (old_battle) |ob| intField(ob, "battle_id") orelse 1 else 1,
        .stage_id = if (stage != 0) stage else if (old_battle) |ob| intField(ob, "stage_id") orelse 1052086 else 1052086,
        .cycle_count = if (cycles != 0) cycles else if (is_pf) 4 else 30,
        .monster_wave = try waves.toOwnedSlice(),
        .monster_level = if (monster_level != 0) monster_level else if (old_battle) |ob| intField(ob, "monster_level") orelse 95 else 95,
        .blessings = try blessings.toOwnedSlice(),
    };
}

// ---------------------------------------------------------------- JSON helpers

fn findOldAvatar(old: ?Value, id: u32) ?Value {
    const o = old orelse return null;
    const list = arrayField(o, "avatar_config") orelse return null;
    for (list.items) |entry| {
        if ((intField(entry, "id") orelse continue) == id) return entry;
    }
    return null;
}
fn idName(arena: Allocator, id: u32) ![]const u8 {
    return std.fmt.allocPrint(arena, "{d}", .{id});
}
fn clamp(value: u32, min: u32, max: u32) u32 {
    return std.math.clamp(value, min, max);
}
fn objectField(v: Value, key: []const u8) ?Value {
    if (v != .object) return null;
    const field = v.object.get(key) orelse return null;
    return if (field == .object) field else null;
}
fn arrayField(v: Value, key: []const u8) ?std.json.Array {
    if (v != .object) return null;
    const field = v.object.get(key) orelse return null;
    return if (field == .array) field.array else null;
}
fn stringField(v: Value, key: []const u8) ?[]const u8 {
    if (v != .object) return null;
    const field = v.object.get(key) orelse return null;
    return if (field == .string) field.string else null;
}
fn boolField(v: Value, key: []const u8) bool {
    if (v != .object) return false;
    const field = v.object.get(key) orelse return false;
    return field == .bool and field.bool;
}
fn intField(v: Value, key: []const u8) ?u32 {
    if (v != .object) return null;
    return intValue(v.object.get(key) orelse return null);
}
// Non-negative integer from a JSON number; edited values can arrive as floats or number strings.
fn intValue(v: Value) ?u32 {
    const n: f64 = switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        .number_string, .string => |s| std.fmt.parseFloat(f64, s) catch return null,
        else => return null,
    };
    if (!std.math.isFinite(n) or n < 0) return null;
    return @intFromFloat(@min(@round(n), @as(f64, std.math.maxInt(u32))));
}
