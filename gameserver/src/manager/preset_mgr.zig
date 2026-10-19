const std = @import("std");
const AvatarManager = @import("avatar_mgr.zig");
const ConfigManager = @import("config_mgr.zig");
const LineupManager = @import("lineup_mgr.zig");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.presets);

// The game itself has 9; teams 10 and up are ours.
pub const max_presets = 50;
pub const game_presets = 9;
const max_name_len = 64;
const save_path = "lineups.json";
const bad_path = "lineups.json.bad";

const config = &ConfigManager.global_game_config_cache.game_config;

// Avatars are kept by base id (8001 Trailblazer, 1001 March 7th), so a path switch or a config.json sync
// reaches every team without rewriting it. Fixed size: presets outlive every packet and session.
const Preset = struct {
    ids: [4]u32 = .{ 0, 0, 0, 0 },
    len: usize = 0,
    leader_id: u32 = 0,
    name_buf: [max_name_len]u8 = undefined,
    name_len: usize = 0,
    favourite: bool = false,

    fn avatars(self: *const Preset) []const u32 {
        return self.ids[0..self.len];
    }
    fn name(self: *const Preset) []const u8 {
        return self.name_buf[0..self.name_len];
    }
    fn has(self: *const Preset, base: u32) bool {
        return std.mem.indexOfScalar(u32, self.avatars(), base) != null;
    }
    // Zeros, a second Trailblazer or March 7th and a fifth avatar are dropped.
    fn add(self: *Preset, id: u32) void {
        const base = baseId(id);
        if (id == 0 or self.len == self.ids.len or self.has(base)) return;
        self.ids[self.len] = base;
        self.len += 1;
    }
};

var presets = [_]Preset{.{}} ** max_presets;
var cur_index: u32 = 0;
// Leader of the stand-in team, kept apart so a hidden preset keeps its own leader for when its members return.
var standin_leader: u32 = 0;

// A preset as the scene and battles use it: only characters config.json has, each on a path it has.
pub const Team = struct {
    ids: [4]u32 = .{ 0, 0, 0, 0 },
    len: usize = 0,
    leader_slot: u32 = 0,

    pub fn slice(self: *const Team) []const u32 {
        return self.ids[0..self.len];
    }
};

pub const Error = error{ InvalidIndex, EmptyLineup, InvalidName, InvalidSlot };

pub fn baseId(id: u32) u32 {
    return switch (id) {
        8001...8010 => 8001,
        1001, 1224 => 1001,
        else => id,
    };
}
pub fn pathId(base: u32) u32 {
    return switch (base) {
        8001 => AvatarManager.mc_id,
        1001 => AvatarManager.m7th,
        else => base,
    };
}
// The selected path if config.json has it, else the first path of that character it lists; null if it has
// none. A path switch then never changes who is in a team, and battles only get avatars config.json has.
fn configPath(base: u32) ?u32 {
    const selected = pathId(base);
    var found: ?u32 = null;
    for (config.avatar_config.items) |avatar| {
        if (avatar.id == selected) return selected;
        if (found == null and baseId(avatar.id) == base) found = avatar.id;
    }
    return found;
}

pub fn curIndex() u32 {
    return cur_index;
}
pub fn presetName(index: u32) []const u8 {
    if (index >= max_presets) return "";
    return presets[index].name();
}
pub fn isFavourite(index: u32) bool {
    if (index >= max_presets) return false;
    return presets[index].favourite;
}

// Characters config.json no longer has are hidden, not removed: a later sync that brings them back restores them.
pub fn teamOf(index: u32) Team {
    var t = Team{};
    if (index >= max_presets) return t;
    const p = &presets[index];
    for (p.avatars()) |base| {
        const id = configPath(base) orelse continue;
        if (base == p.leader_id) t.leader_slot = @intCast(t.len);
        t.ids[t.len] = id;
        t.len += 1;
    }
    // The current team is never empty: the scene needs a party and battles need avatars.
    if (t.len == 0 and index == cur_index) {
        t.len = LineupManager.overworldAvatarIds(&t.ids);
        for (t.ids[0..t.len], 0..) |*id, i| {
            const base = baseId(id.*);
            id.* = configPath(base) orelse id.*;
            if (base == standin_leader) t.leader_slot = @intCast(i);
        }
    }
    return t;
}
pub fn curTeam() Team {
    return teamOf(cur_index);
}
// The current preset has nobody config.json has, so curTeam() is the stand-in team.
pub fn curIsStandIn() bool {
    for (presets[cur_index].avatars()) |base| {
        if (configPath(base) != null) return false;
    }
    return true;
}

// A team edit from ReplaceLineupCsReq; `ids` are in slot order and `leader_slot` indexes them.
pub fn replace(index: u32, ids: []const u32, leader_slot: u32) Error!void {
    if (index >= max_presets) return error.InvalidIndex;
    const p = &presets[index];
    var next = p.*;
    next.len = 0;
    for (ids) |id| {
        if (configPath(baseId(id)) != null) next.add(id);
    }
    if (next.len == 0 and index == cur_index) return error.EmptyLineup;
    const picked = if (leader_slot < ids.len) baseId(ids[leader_slot]) else 0;
    next.leader_id = if (picked != 0 and next.has(picked))
        picked
    else if (next.has(p.leader_id))
        p.leader_id
    else if (next.len > 0) next.ids[0] else 0;
    p.* = next;
}

pub fn switchTo(index: u32) Error!void {
    if (index >= max_presets) return error.InvalidIndex;
    if (index != cur_index and teamOf(index).len == 0) return error.EmptyLineup;
    cur_index = index;
}

// ChangeLineupLeaderCsReq outside challenges; `slot` indexes the current team as the client sees it.
pub fn setLeader(slot: u32) Error!void {
    const t = curTeam();
    if (slot >= t.len) return error.InvalidSlot;
    const leader = baseId(t.ids[slot]);
    if (curIsStandIn()) standin_leader = leader else presets[cur_index].leader_id = leader;
}

pub fn rename(index: u32, new_name: []const u8) Error!void {
    if (index >= max_presets) return error.InvalidIndex;
    if (new_name.len > max_name_len or !std.unicode.utf8ValidateSlice(new_name)) return error.InvalidName;
    const p = &presets[index];
    @memcpy(p.name_buf[0..new_name.len], new_name);
    p.name_len = new_name.len;
}

pub fn setFavourite(index: u32, marked: bool) Error!void {
    if (index >= max_presets) return error.InvalidIndex;
    presets[index].favourite = marked;
}

const SavedPreset = struct {
    name: []const u8 = "",
    leader: u32 = 0,
    favourite: bool = false,
    avatars: []const u32 = &.{},
};
const SaveFile = struct {
    cur_index: u32 = 0,
    lineups: []const SavedPreset = &.{},
};

// Loaded once at startup. A missing file is normal; a broken one is kept as lineups.json.bad and the
// teams start over, team 1 being the config.json team.
pub fn load(allocator: Allocator) void {
    loadFile(allocator) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); starting from the config.json team", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
    if (presets[cur_index].len == 0) seedCurrent();
}
fn loadFile(allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, 1 << 20);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(SaveFile, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const file = parsed.value;
    if (file.cur_index >= max_presets or file.lineups.len > max_presets) return error.InvalidLineups;

    // Nothing is applied unless the whole file is valid.
    var loaded = [_]Preset{.{}} ** max_presets;
    for (file.lineups, 0..) |saved, i| {
        if (saved.avatars.len > 4 or saved.name.len > max_name_len or !std.unicode.utf8ValidateSlice(saved.name)) {
            return error.InvalidLineups;
        }
        const p = &loaded[i];
        for (saved.avatars) |id| p.add(id);
        const leader = baseId(saved.leader);
        p.leader_id = if (p.has(leader)) leader else if (p.len > 0) p.ids[0] else 0;
        p.favourite = saved.favourite;
        @memcpy(p.name_buf[0..saved.name.len], saved.name);
        p.name_len = saved.name.len;
    }
    presets = loaded;
    cur_index = file.cur_index;
}
// Before any lineups.json exists the current team is config.json's first 4, as it always was.
fn seedCurrent() void {
    var ids: [4]u32 = undefined;
    const len = LineupManager.overworldAvatarIds(&ids);
    const p = &presets[cur_index];
    p.len = 0;
    for (ids[0..len]) |id| p.add(id);
    p.leader_id = if (p.len > 0) p.ids[0] else 0;
}

// Written after every change; a failed write is logged and never drops the player.
pub fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    var saved: [max_presets]SavedPreset = undefined;
    for (&presets, &saved) |*p, *entry| {
        entry.* = .{ .name = p.name(), .leader = p.leader_id, .favourite = p.favourite, .avatars = p.avatars() };
    }
    // 50 teams with 64-byte names stay well under this even with every name byte escaped.
    var buf: [65536]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try std.json.stringify(SaveFile{ .cur_index = cur_index, .lineups = &saved }, .{ .whitespace = .indent_2 }, stream.writer());
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(stream.getWritten());
    try file.finish();
}
