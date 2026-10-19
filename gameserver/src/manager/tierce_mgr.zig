const std = @import("std");
const protocol = @import("protocol");
const ConfigManager = @import("config_mgr.zig");
const ChallengeConfig = @import("../data/challenge_config.zig");
const ChallengeTargets = @import("../data/challenge_targets.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.tierce);

// Starward (Challenge Tierce) floor records: each node's team and buff as the player last set them, and the best
// passed run of the floor, which GetChallengeTierceData shows and the floor's stars are judged from. Kept in
// tierce.json next to config.json.
pub const nodes = 3;
const save_path = "tierce.json";
const bad_path = "tierce.json.bad";

const tierce_config = &ConfigManager.global_game_config_cache.challenge_tierce_config;
const TierceResult = Logic.Challenge().TierceResult;

pub const Node = struct {
    ids: [4]u32 = .{ 0, 0, 0, 0 },
    len: usize = 0,
    buff_id: u32 = 0,
    // The best passed run's result for this node; only set once the floor is passed.
    cycles: u32 = 0,
    score: u32 = 0,
    deaths: u32 = 0,

    pub fn avatars(self: *const Node) []const u32 {
        return self.ids[0..self.len];
    }
    fn setAvatars(self: *Node, src: []const u32) void {
        self.len = 0;
        for (src) |id| {
            if (id == 0 or self.len == self.ids.len) continue;
            self.ids[self.len] = id;
            self.len += 1;
        }
    }
};

pub const Floor = struct {
    passed: bool = false,
    nodes: [nodes]Node = .{ .{}, .{}, .{} },
};

// Every floor the player has set teams for or passed, by tierce id.
var floors = std.AutoArrayHashMap(u32, Floor).init(std.heap.page_allocator);

pub fn find(challenge_id: u32) ?*const Floor {
    return floors.getPtr(challenge_id);
}
pub fn configOf(challenge_id: u32) ?*const ChallengeConfig.ChallengeTierce {
    for (tierce_config.challenge_tierce.items) |*conf| {
        if (conf.id == challenge_id) return conf;
    }
    return null;
}

// The team the player set for `stage` of a floor; without one, a placeholder team so the node still loads.
pub fn stageLineup(challenge_id: u32, stage: usize) []const u32 {
    if (floors.getPtr(challenge_id)) |floor| {
        if (stage < nodes and floor.nodes[stage].len > 0) return floor.nodes[stage].avatars();
    }
    return switch (stage) {
        0 => &[_]u32{1508},
        1 => &[_]u32{1509},
        else => &[_]u32{1510},
    };
}
pub fn stageBuff(challenge_id: u32, stage: usize) u32 {
    const floor = floors.getPtr(challenge_id) orelse return 0;
    return if (stage < nodes) floor.nodes[stage].buff_id else 0;
}

// The teams and buffs of a start request or a team edit; nodes the request leaves out keep theirs.
pub fn setLineups(challenge_id: u32, stages: []const protocol.LineupTierce) !void {
    const floor = try getOrAdd(challenge_id);
    for (stages[0..@min(stages.len, nodes)], floor.nodes[0..@min(stages.len, nodes)]) |info, *node| {
        var ids: [4]u32 = .{ 0, 0, 0, 0 };
        for (info.lineup.items[0..@min(info.lineup.items.len, ids.len)], 0..) |avatar, i| ids[i] = avatar.id;
        node.setAvatars(&ids);
        node.buff_id = info.buff_id;
    }
    save();
}
fn getOrAdd(challenge_id: u32) !*Floor {
    const entry = try floors.getOrPut(challenge_id);
    if (!entry.found_existing) entry.value_ptr.* = .{};
    return entry.value_ptr;
}

pub const Totals = struct { cycles: u32 = 0, score: u32 = 0, deaths: u32 = 0 };

pub fn runTotals(results: []const TierceResult) Totals {
    var totals = Totals{};
    for (results) |r| {
        totals.cycles +|= r.cycles;
        totals.score +|= r.score;
        totals.deaths +|= r.deaths;
    }
    return totals;
}
pub fn floorTotals(floor: *const Floor) Totals {
    var totals = Totals{};
    for (&floor.nodes) |*n| {
        totals.cycles +|= n.cycles;
        totals.score +|= n.score;
        totals.deaths +|= n.deaths;
    }
    return totals;
}

// Cycles a MoC floor's shared pool (45) has left after `results`; null for floors without one (PF/AS).
pub fn cyclesLeft(challenge_id: u32, results: []const TierceResult) ?u32 {
    const conf = configOf(challenge_id) orelse return null;
    if (conf.round_limit == 0) return null;
    return conf.round_limit -| runTotals(results).cycles;
}

pub const Met = std.BoundedArray(u32, 8);

// The star targets a floor's run with these totals meets: the floor's own targets, and on top of all of them its
// Starward target (600 "gain 3 stars and win with 33 or more cycles remaining", 4000/5000 the highest score).
pub fn metTargets(conf: *const ChallengeConfig.ChallengeTierce, totals: Totals) Met {
    var met = Met{};
    var all = true;
    for (conf.target_id.items) |id| {
        if (!targetMet(conf, id, totals)) {
            all = false;
            continue;
        }
        met.append(id) catch break;
    }
    if (all and targetMet(conf, conf.tierce_target_id, totals)) met.append(conf.tierce_target_id) catch {};
    return met;
}
fn targetMet(conf: *const ChallengeConfig.ChallengeTierce, id: u32, totals: Totals) bool {
    const target = ChallengeTargets.find(id) orelse return false;
    return switch (target.kind) {
        // Only MoC floors have a shared cycle pool to have cycles left of.
        .rounds_left => conf.round_limit > 0 and conf.round_limit -| totals.cycles >= target.param,
        .dead_avatar => totals.deaths <= target.param,
        .total_score => totals.score >= target.param,
    };
}

// A run started at a later node takes the record's earlier nodes as played, so the floor's shared cycles and its
// stars count all three nodes.
pub fn seedEarlierNodes(challenge_id: u32, stage: u32, results: *[nodes]TierceResult) void {
    const floor = floors.getPtr(challenge_id) orelse return;
    if (!floor.passed) return;
    const n = @min(stage, nodes);
    for (results[0..n], floor.nodes[0..n]) |*r, node| {
        r.* = .{
            .end_status = @intCast(@intFromEnum(protocol.BattleEndStatus.BATTLE_END_WIN)),
            .score = node.score,
            .cycles = node.cycles,
            .deaths = node.deaths,
        };
    }
}

// A passed run becomes the floor's record when it meets more targets than the record, or as many with fewer
// cycles (MoC) or a higher score (PF/AS).
pub fn recordPassedRun(challenge_id: u32, results: *const [nodes]TierceResult) void {
    const conf = configOf(challenge_id) orelse return;
    const floor = getOrAdd(challenge_id) catch |err| {
        log.err("floor {} could not be recorded: {s}", .{ challenge_id, @errorName(err) });
        return;
    };
    const run = runTotals(results);
    if (floor.passed) {
        const old = floorTotals(floor);
        const run_met = metTargets(conf, run).len;
        const old_met = metTargets(conf, old).len;
        const better = run_met > old_met or (run_met == old_met and
            if (conf.round_limit > 0) run.cycles < old.cycles else run.score > old.score);
        if (!better) return;
    }
    floor.passed = true;
    for (&floor.nodes, results) |*node, r| {
        node.cycles = r.cycles;
        node.score = r.score;
        node.deaths = r.deaths;
    }
    save();
}

const SavedNode = struct {
    avatars: []const u32 = &.{},
    buff_id: u32 = 0,
    cycles: u32 = 0,
    score: u32 = 0,
    deaths: u32 = 0,
};
const SavedFloor = struct {
    id: u32 = 0,
    passed: bool = false,
    nodes: []const SavedNode = &.{},
};
const SaveFile = struct {
    floors: []const SavedFloor = &.{},
};

// Loaded once at startup. A missing file is normal; a broken one is kept as tierce.json.bad and every floor starts
// unplayed.
pub fn load(allocator: Allocator) void {
    loadFile(allocator) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); every Starward floor starts unplayed", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadFile(allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, 1 << 20);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(SaveFile, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    // Nothing is applied unless the whole file is valid.
    var loaded = std.AutoArrayHashMap(u32, Floor).init(std.heap.page_allocator);
    errdefer loaded.deinit();
    for (parsed.value.floors) |saved| {
        if (saved.nodes.len > nodes or (saved.passed and saved.nodes.len != nodes)) return error.InvalidRecords;
        var floor = Floor{ .passed = saved.passed };
        for (saved.nodes, floor.nodes[0..saved.nodes.len]) |s, *node| {
            if (s.avatars.len > node.ids.len) return error.InvalidRecords;
            node.setAvatars(s.avatars);
            node.buff_id = s.buff_id;
            node.cycles = s.cycles;
            node.score = s.score;
            node.deaths = s.deaths;
        }
        try loaded.put(saved.id, floor);
    }
    floors.deinit();
    floors = loaded;
}

// Written after every change; a failed write is logged and never drops the player.
pub fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    const allocator = std.heap.page_allocator;
    const saved_nodes = try allocator.alloc(SavedNode, floors.count() * nodes);
    defer allocator.free(saved_nodes);
    const saved = try allocator.alloc(SavedFloor, floors.count());
    defer allocator.free(saved);
    for (floors.keys(), floors.values(), saved, 0..) |id, *floor, *entry, i| {
        const floor_nodes = saved_nodes[i * nodes ..][0..nodes];
        for (floor_nodes, &floor.nodes) |*s, *node| {
            s.* = .{ .avatars = node.avatars(), .buff_id = node.buff_id, .cycles = node.cycles, .score = node.score, .deaths = node.deaths };
        }
        entry.* = .{ .id = id, .passed = floor.passed, .nodes = floor_nodes };
    }
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    try std.json.stringify(SaveFile{ .floors = saved }, .{ .whitespace = .indent_2 }, out.writer());
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(out.items);
    try file.finish();
}
