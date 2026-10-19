const std = @import("std");
const ChallengeConfig = @import("../data/challenge_config.zig");
const ChallengeTargets = @import("../data/challenge_targets.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.records);

// The best runs of MoC/PF/AS floors and of Anomaly Arbitration knights and bosses, kept in challenge.json next to
// config.json. Anything without a record keeps showing as fully cleared, as before records were kept, so nothing the
// player had open locks again.
const save_path = "challenge.json";
const bad_path = "challenge.json.bad";

pub const NodeLineup = Logic.Challenge().NodeLineup;

pub const Classic = struct {
    // Bit i: the floor's i-th star target (ChallengeTargetID order) was met.
    stars_mask: u32 = 0,
    rounds: u32 = 0,
    scores: [2]u32 = .{ 0, 0 },
    buffs: [2]u32 = .{ 0, 0 },
    lineups: [2]NodeLineup = .{ .{}, .{} },

    pub fn stars(self: *const Classic) u32 {
        return @popCount(self.stars_mask);
    }
    pub fn score(self: *const Classic) u32 {
        return self.scores[0] +| self.scores[1];
    }
};

var classic = std.AutoArrayHashMap(u32, Classic).init(std.heap.page_allocator);

pub fn findClassic(challenge_id: u32) ?*const Classic {
    return classic.getPtr(challenge_id);
}

pub const Totals = struct { rounds: u32 = 0, score: u32 = 0, deaths: u32 = 0 };

// The star mask a run with these totals earns. MoC counts the cycles left of the floor's countdown; PF/AS rows have
// no countdown (0) and score targets instead.
pub fn classicStars(target_ids: []const u32, count_down: u32, totals: Totals) u32 {
    var mask: u32 = 0;
    for (target_ids[0..@min(target_ids.len, 3)], 0..) |id, i| {
        const target = ChallengeTargets.find(id) orelse continue;
        const met = switch (target.kind) {
            .rounds_left => count_down > 0 and count_down -| totals.rounds >= target.param,
            .dead_avatar => totals.deaths <= target.param,
            .total_score => totals.score >= target.param,
        };
        if (met) mask |= @as(u32, 1) << @intCast(i);
    }
    return mask;
}

// More stars wins; as many stars wins with fewer cycles (MoC) or a higher score (PF/AS).
pub fn betterClassic(is_moc: bool, new: *const Classic, old: *const Classic) bool {
    if (new.stars() != old.stars()) return new.stars() > old.stars();
    return if (is_moc) new.rounds < old.rounds else new.score() > old.score();
}

// The MoC/PF/AS run in progress. Only a run started at node 1 can become a record; a retried node's cycles and
// downed characters replace the failed try's.
const ClassicRun = struct {
    full: bool = false,
    rounds: [2]u32 = .{ 0, 0 },
    deaths: [2]u32 = .{ 0, 0 },
};
var classic_run: ClassicRun = .{};

pub fn startClassicRun(full: bool) void {
    classic_run = .{ .full = full };
}
pub fn endClassicNode(node: u32, rounds: u32, deaths: u32) void {
    if (node < 1 or node > 2) return;
    classic_run.rounds[node - 1] = rounds;
    classic_run.deaths[node - 1] = deaths;
}

pub const Finished = struct {
    is_moc: bool,
    scores: [2]u32,
    buffs: [2]u32,
    lineups: [2]NodeLineup,
};

// The last node of a run was won: returns the star mask for the settle screens. A full run gets its own, and becomes
// the floor's record when it beats the one kept; a single node shows every star, as before, and is not kept. A run
// without stars is not kept either: its floor would show as never cleared.
pub fn settleClassicRun(conf: ?*const ChallengeConfig.ChallengeConfig, done: Finished) u32 {
    const c = conf orelse return 7;
    if (!classic_run.full) return 7;
    const totals = Totals{
        .rounds = classic_run.rounds[0] +| classic_run.rounds[1],
        .score = done.scores[0] +| done.scores[1],
        .deaths = classic_run.deaths[0] +| classic_run.deaths[1],
    };
    const run = Classic{
        .stars_mask = classicStars(c.target_ids.items, c.count_down, totals),
        .rounds = totals.rounds,
        .scores = done.scores,
        .buffs = done.buffs,
        .lineups = done.lineups,
    };
    log.info("challenge {} run: stars {b:0>3}, cycles {}, score {}, downed {}", .{ c.id, run.stars_mask, totals.rounds, totals.score, totals.deaths });
    if (run.stars_mask == 0) return 0;
    const entry = classic.getOrPut(c.id) catch |err| {
        log.err("challenge {} could not be recorded: {s}", .{ c.id, @errorName(err) });
        return run.stars_mask;
    };
    if (entry.found_existing and !betterClassic(done.is_moc, &run, entry.value_ptr)) return run.stars_mask;
    entry.value_ptr.* = run;
    save();
    return run.stars_mask;
}

// Anomaly Arbitration star targets (resources/BattleTargetConfig.json, trimmed from the game's BattleTargetConfig):
// at most `param` cycles, or at most `param` characters downed. A table of its own: 3001 is an AS score target in
// challenge_targets.zig but a 4-cycle AA target here.
pub const TargetKind = enum { cycles, downed };
pub const BattleTarget = struct { id: u32, kind: TargetKind = .cycles, param: u32 = 0 };
const battle_target_path = "resources/BattleTargetConfig.json";
var battle_targets: []const BattleTarget = &.{};

pub const Targets = std.BoundedArray(u32, 8);
// What a won fight is judged by. We send the client no AA targets, so it reports no progress on them.
pub const Fight = struct { cycles: u32, downed: u32 };

// The targets of `ids` a won fight meets; one the table does not have is never met.
pub fn targetsMet(table: []const BattleTarget, ids: []const u32, fight: Fight) Targets {
    var met = Targets{};
    for (ids) |id| {
        const target = for (table) |t| {
            if (t.id == id) break t;
        } else continue;
        const value = switch (target.kind) {
            .cycles => fight.cycles,
            .downed => fight.downed,
        };
        if (value <= target.param) met.append(id) catch break;
    }
    return met;
}
pub fn peakTargetsMet(ids: []const u32, fight: Fight) Targets {
    return targetsMet(battle_targets, ids, fight);
}

// The best clear of a knight, or of one boss difficulty.
pub const Peak = struct {
    cycles: u32 = 0,
    targets: Targets = .{},
    // The boss buff it was cleared with; knights have none.
    buff_id: u32 = 0,
    team: NodeLineup = .{},
};
const PeakKey = struct { level_id: u32, boss: bool, hard: bool };
var peak_records = std.AutoArrayHashMap(PeakKey, Peak).init(std.heap.page_allocator);

pub fn findPeak(level_id: u32) ?*const Peak {
    return peak_records.getPtr(.{ .level_id = level_id, .boss = false, .hard = false });
}
pub fn findPeakBoss(level_id: u32, hard: bool) ?*const Peak {
    return peak_records.getPtr(.{ .level_id = level_id, .boss = true, .hard = hard });
}

// More targets wins; as many targets wins with fewer cycles.
pub fn betterPeak(new: *const Peak, old: *const Peak) bool {
    if (new.targets.len != old.targets.len) return new.targets.len > old.targets.len;
    return new.cycles < old.cycles;
}

pub const PeakClear = struct {
    level_id: u32,
    boss: bool,
    hard: bool,
    cycles: u32,
    targets: Targets,
    buff_id: u32,
    team: []const u32,
};

// A won AA fight: it becomes the record of its knight or boss difficulty when it beats the one kept.
pub fn recordPeak(clear: PeakClear) void {
    const run = Peak{
        .cycles = clear.cycles,
        .targets = clear.targets,
        .buff_id = if (clear.boss) clear.buff_id else 0,
        .team = NodeLineup.fromSlice(clear.team),
    };
    const key = PeakKey{ .level_id = clear.level_id, .boss = clear.boss, .hard = clear.boss and clear.hard };
    const entry = peak_records.getOrPut(key) catch |err| {
        log.err("AA level {} could not be recorded: {s}", .{ clear.level_id, @errorName(err) });
        return;
    };
    if (entry.found_existing and !betterPeak(&run, entry.value_ptr)) return;
    entry.value_ptr.* = run;
    save();
}

const SavedClassic = struct {
    id: u32 = 0,
    stars_mask: u32 = 0,
    rounds: u32 = 0,
    score1: u32 = 0,
    score2: u32 = 0,
    buff1: u32 = 0,
    buff2: u32 = 0,
    lineup1: []const u32 = &.{},
    lineup2: []const u32 = &.{},
};
const SavedPeak = struct {
    level_id: u32 = 0,
    cycles: u32 = 0,
    targets: []const u32 = &.{},
    team: []const u32 = &.{},
};
const SavedPeakBoss = struct {
    level_id: u32 = 0,
    hard: bool = false,
    cycles: u32 = 0,
    targets: []const u32 = &.{},
    buff_id: u32 = 0,
    team: []const u32 = &.{},
};
const SaveFile = struct {
    classic: []const SavedClassic = &.{},
    peak: []const SavedPeak = &.{},
    peak_boss: []const SavedPeakBoss = &.{},
};

// Loaded once at startup. A missing file is normal; a broken one is kept as challenge.json.bad and every challenge
// shows as fully cleared.
pub fn load(allocator: Allocator) void {
    loadBattleTargets(allocator) catch |err| {
        log.err("{s} could not be loaded ({s}); no AA star target counts as met", .{ battle_target_path, @errorName(err) });
    };
    loadFile(allocator) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); every challenge shows as fully cleared", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadBattleTargets(allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, battle_target_path, 1 << 20);
    defer allocator.free(bytes);
    // Kept for the server's lifetime.
    battle_targets = try std.json.parseFromSliceLeaky([]const BattleTarget, std.heap.page_allocator, bytes, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}
fn loadFile(allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, 1 << 20);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(SaveFile, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    // Nothing is applied unless the whole file is valid.
    var loaded_classic = std.AutoArrayHashMap(u32, Classic).init(std.heap.page_allocator);
    errdefer loaded_classic.deinit();
    for (parsed.value.classic) |saved| {
        if (saved.stars_mask == 0 or saved.stars_mask > 7 or saved.lineup1.len > 4 or saved.lineup2.len > 4) return error.InvalidRecords;
        try loaded_classic.put(saved.id, .{
            .stars_mask = saved.stars_mask,
            .rounds = saved.rounds,
            .scores = .{ saved.score1, saved.score2 },
            .buffs = .{ saved.buff1, saved.buff2 },
            .lineups = .{ NodeLineup.fromSlice(saved.lineup1), NodeLineup.fromSlice(saved.lineup2) },
        });
    }
    var loaded_peaks = std.AutoArrayHashMap(PeakKey, Peak).init(std.heap.page_allocator);
    errdefer loaded_peaks.deinit();
    for (parsed.value.peak) |saved| {
        const key = PeakKey{ .level_id = saved.level_id, .boss = false, .hard = false };
        try loaded_peaks.put(key, try loadedPeak(saved.cycles, saved.targets, 0, saved.team));
    }
    for (parsed.value.peak_boss) |saved| {
        const key = PeakKey{ .level_id = saved.level_id, .boss = true, .hard = saved.hard };
        try loaded_peaks.put(key, try loadedPeak(saved.cycles, saved.targets, saved.buff_id, saved.team));
    }
    classic.deinit();
    classic = loaded_classic;
    peak_records.deinit();
    peak_records = loaded_peaks;
}
fn loadedPeak(cycles: u32, targets: []const u32, buff_id: u32, team: []const u32) !Peak {
    if (team.len > 4) return error.InvalidRecords;
    return .{
        .cycles = cycles,
        .targets = Targets.fromSlice(targets) catch return error.InvalidRecords,
        .buff_id = buff_id,
        .team = NodeLineup.fromSlice(team),
    };
}

// Written after every change; a failed write is logged and never drops the player.
pub fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const saved_classic = try allocator.alloc(SavedClassic, classic.count());
    for (classic.keys(), classic.values(), saved_classic) |id, *record, *entry| {
        entry.* = .{
            .id = id,
            .stars_mask = record.stars_mask,
            .rounds = record.rounds,
            .score1 = record.scores[0],
            .score2 = record.scores[1],
            .buff1 = record.buffs[0],
            .buff2 = record.buffs[1],
            .lineup1 = record.lineups[0].slice(),
            .lineup2 = record.lineups[1].slice(),
        };
    }
    var saved_peaks = std.ArrayList(SavedPeak).init(allocator);
    var saved_bosses = std.ArrayList(SavedPeakBoss).init(allocator);
    for (peak_records.keys(), peak_records.values()) |key, *record| {
        if (key.boss) {
            try saved_bosses.append(.{
                .level_id = key.level_id,
                .hard = key.hard,
                .cycles = record.cycles,
                .targets = record.targets.constSlice(),
                .buff_id = record.buff_id,
                .team = record.team.slice(),
            });
        } else {
            try saved_peaks.append(.{
                .level_id = key.level_id,
                .cycles = record.cycles,
                .targets = record.targets.constSlice(),
                .team = record.team.slice(),
            });
        }
    }
    var out = std.ArrayList(u8).init(allocator);
    const file_data = SaveFile{ .classic = saved_classic, .peak = saved_peaks.items, .peak_boss = saved_bosses.items };
    try std.json.stringify(file_data, .{ .whitespace = .indent_2 }, out.writer());
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(out.items);
    try file.finish();
}

test "classic stars: MoC counts the cycles left of the countdown and the downed characters" {
    // 5612: 251 at least 10 cycles left, 252 at least 20, 253 nobody downed.
    const moc = [_]u32{ 251, 252, 253 };
    try std.testing.expectEqual(@as(u32, 0b101), classicStars(&moc, 30, .{ .rounds = 16 }));
    try std.testing.expectEqual(@as(u32, 0b111), classicStars(&moc, 30, .{ .rounds = 10 }));
    try std.testing.expectEqual(@as(u32, 0b011), classicStars(&moc, 30, .{ .rounds = 10, .deaths = 1 }));
    try std.testing.expectEqual(@as(u32, 0), classicStars(&moc, 30, .{ .rounds = 21, .deaths = 2 }));
    // The countdown stops at zero; without one no cycle target is met.
    try std.testing.expectEqual(@as(u32, 0b100), classicStars(&moc, 30, .{ .rounds = 45 }));
    try std.testing.expectEqual(@as(u32, 0b100), classicStars(&moc, 0, .{ .rounds = 1 }));
}

test "classic stars: PF and AS add up both nodes' scores" {
    const pf = [_]u32{ 2001, 2002, 2003 }; // 40000 / 50000 / 60000
    try std.testing.expectEqual(@as(u32, 0b011), classicStars(&pf, 0, .{ .score = 55000 }));
    try std.testing.expectEqual(@as(u32, 0b111), classicStars(&pf, 0, .{ .score = 60000 }));
    try std.testing.expectEqual(@as(u32, 0), classicStars(&pf, 0, .{ .score = 39999 }));
    const as = [_]u32{ 3001, 3002, 3003 }; // 4000 / 5200 / 6600
    try std.testing.expectEqual(@as(u32, 0b011), classicStars(&as, 0, .{ .score = 5500 }));
}

test "better classic run: more stars, then fewer cycles (MoC) or a higher score (PF/AS)" {
    const old = Classic{ .stars_mask = 0b101, .rounds = 16, .scores = .{ 30000, 25000 } };
    try std.testing.expect(betterClassic(true, &Classic{ .stars_mask = 0b111, .rounds = 20 }, &old));
    try std.testing.expect(!betterClassic(true, &Classic{ .stars_mask = 0b001, .rounds = 2 }, &old));
    // Stars are counted, not compared as numbers: 0b011 is as good as 0b101.
    try std.testing.expect(betterClassic(true, &Classic{ .stars_mask = 0b011, .rounds = 12 }, &old));
    try std.testing.expect(!betterClassic(true, &Classic{ .stars_mask = 0b110, .rounds = 16 }, &old));
    try std.testing.expect(betterClassic(false, &Classic{ .stars_mask = 0b101, .scores = .{ 30000, 25001 } }, &old));
    try std.testing.expect(!betterClassic(false, &Classic{ .stars_mask = 0b101, .rounds = 1, .scores = .{ 20000, 20000 } }, &old));
}

test "AA targets: cycle limits and downed characters" {
    const table = [_]BattleTarget{
        .{ .id = 3000, .kind = .downed },
        .{ .id = 3001, .param = 4 },
        .{ .id = 3002, .param = 2 },
    };
    const knight = [_]u32{ 3001, 3002, 3000 };
    const clean = targetsMet(&table, &knight, .{ .cycles = 2, .downed = 0 });
    try std.testing.expectEqualSlices(u32, &.{ 3001, 3002, 3000 }, clean.constSlice());
    const downed = targetsMet(&table, &knight, .{ .cycles = 2, .downed = 1 });
    try std.testing.expectEqualSlices(u32, &.{ 3001, 3002 }, downed.constSlice());
    const slow = targetsMet(&table, &knight, .{ .cycles = 3, .downed = 0 });
    try std.testing.expectEqualSlices(u32, &.{ 3001, 3000 }, slow.constSlice());
    try std.testing.expectEqual(@as(usize, 0), targetsMet(&table, &knight, .{ .cycles = 5, .downed = 2 }).len);
    // A target the table does not have is never met.
    try std.testing.expectEqual(@as(usize, 0), targetsMet(&table, &.{3007}, .{ .cycles = 0, .downed = 0 }).len);
}

test "AA target table: the kind column parses" {
    const json = "[{\"id\": 3000, \"kind\": \"downed\", \"param\": 0}, {\"id\": 3001, \"kind\": \"cycles\", \"param\": 4}]";
    const parsed = try std.json.parseFromSlice([]const BattleTarget, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(TargetKind.downed, parsed.value[0].kind);
    try std.testing.expectEqual(BattleTarget{ .id = 3001, .kind = .cycles, .param = 4 }, parsed.value[1]);
}

test "better AA clear: more targets, then fewer cycles" {
    const old = Peak{ .cycles = 3, .targets = try Targets.fromSlice(&.{3001}) };
    try std.testing.expect(betterPeak(&Peak{ .cycles = 4, .targets = try Targets.fromSlice(&.{ 3001, 3002 }) }, &old));
    try std.testing.expect(!betterPeak(&Peak{ .cycles = 1 }, &old));
    try std.testing.expect(betterPeak(&Peak{ .cycles = 2, .targets = try Targets.fromSlice(&.{3001}) }, &old));
    try std.testing.expect(!betterPeak(&Peak{ .cycles = 3, .targets = try Targets.fromSlice(&.{3003}) }, &old));
}
