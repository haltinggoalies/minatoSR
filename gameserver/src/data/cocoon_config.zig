const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// resources/CocoonConfig.json: every Calyx, Cavern of Corrosion and Echo of War at each world level and the stages
// one run draws from, trimmed from the 4.6.51 CocoonConfig excel to [{"id", "world_level", "stage_ids"}].
// resources/FarmElementConfig.json: every Stagnant Shadow's stage at each world level, trimmed from the
// FarmElementConfig excel to [{"id", "world_level", "stage_id"}].
pub const Cocoon = struct { id: u32, world_level: u32, stage_ids: []const u32 };
pub const FarmElement = struct { id: u32, world_level: u32, stage_id: u32 };

pub const CocoonConfig = struct {
    allocator: Allocator,
    cocoons: ArrayList(Cocoon),

    pub fn deinit(self: *CocoonConfig) void {
        for (self.cocoons.items) |cocoon| self.allocator.free(cocoon.stage_ids);
        self.cocoons.deinit();
    }
    // The row for `world_level`, else the highest one below it (rows start at world level 0).
    pub fn find(self: *const CocoonConfig, id: u32, world_level: u32) ?Cocoon {
        var best: ?Cocoon = null;
        for (self.cocoons.items) |cocoon| {
            if (cocoon.id != id or cocoon.world_level > world_level) continue;
            if (best == null or cocoon.world_level > best.?.world_level) best = cocoon;
        }
        return best;
    }
};

pub const FarmElementConfig = struct {
    elements: ArrayList(FarmElement),

    pub fn deinit(self: *FarmElementConfig) void {
        self.elements.deinit();
    }
    // The client names a Stagnant Shadow either by its id (Survival Index) or by one of its stages (Challenge
    // Again); an id gets the row of `world_level`, else of the highest world level below it.
    pub fn find(self: *const FarmElementConfig, id_or_stage: u32, world_level: u32) ?FarmElement {
        var best: ?FarmElement = null;
        for (self.elements.items) |element| {
            if (element.stage_id == id_or_stage) return element;
            if (element.id != id_or_stage or element.world_level > world_level) continue;
            if (best == null or element.world_level > best.?.world_level) best = element;
        }
        return best;
    }
};

pub fn parseCocoonConfig(root: std.json.Value, allocator: Allocator) anyerror!CocoonConfig {
    if (root != .array) return error.InvalidCocoonConfig;
    var config = CocoonConfig{ .allocator = allocator, .cocoons = ArrayList(Cocoon).init(allocator) };
    errdefer config.deinit();
    for (root.array.items) |row| {
        const list = try field(row, "stage_ids", error.InvalidCocoonConfig);
        if (list != .array or list.array.items.len == 0) return error.InvalidCocoonConfig;
        const stage_ids = try allocator.alloc(u32, list.array.items.len);
        errdefer allocator.free(stage_ids);
        for (list.array.items, stage_ids) |value, *id| id.* = try int(value, error.InvalidCocoonConfig);
        try config.cocoons.append(.{
            .id = try int(try field(row, "id", error.InvalidCocoonConfig), error.InvalidCocoonConfig),
            .world_level = try int(try field(row, "world_level", error.InvalidCocoonConfig), error.InvalidCocoonConfig),
            .stage_ids = stage_ids,
        });
    }
    return config;
}

pub fn parseFarmElementConfig(root: std.json.Value, allocator: Allocator) anyerror!FarmElementConfig {
    if (root != .array) return error.InvalidFarmElementConfig;
    var elements = ArrayList(FarmElement).init(allocator);
    errdefer elements.deinit();
    for (root.array.items) |row| {
        try elements.append(.{
            .id = try int(try field(row, "id", error.InvalidFarmElementConfig), error.InvalidFarmElementConfig),
            .world_level = try int(try field(row, "world_level", error.InvalidFarmElementConfig), error.InvalidFarmElementConfig),
            .stage_id = try int(try field(row, "stage_id", error.InvalidFarmElementConfig), error.InvalidFarmElementConfig),
        });
    }
    return .{ .elements = elements };
}

fn field(row: std.json.Value, key: []const u8, err: anyerror) !std.json.Value {
    if (row != .object) return err;
    return row.object.get(key) orelse err;
}

fn int(value: std.json.Value, err: anyerror) !u32 {
    if (value != .integer) return err;
    return std.math.cast(u32, value.integer) orelse err;
}

test "CocoonConfig.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\[{"id": 1001, "world_level": 0, "stage_ids": [1022010, 1022020]},
        \\ {"id": 1001, "world_level": 6, "stage_ids": [1022016]},
        \\ {"id": 1201, "world_level": 0, "stage_ids": [1043010]}]
    , .{});
    defer parsed.deinit();
    var config = try parseCocoonConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqualSlices(u32, &.{1022016}, config.find(1001, 6).?.stage_ids);
    try std.testing.expectEqual(@as(u32, 6), config.find(1001, 9).?.world_level);
    try std.testing.expectEqual(@as(u32, 0), config.find(1001, 5).?.world_level);
    try std.testing.expect(config.find(1002, 6) == null);

    const empty = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 1, \"world_level\": 0, \"stage_ids\": []}]", .{});
    defer empty.deinit();
    try std.testing.expectError(error.InvalidCocoonConfig, parseCocoonConfig(empty.value, allocator));
    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 1, \"stage_ids\": [2, \"x\"]}]", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidCocoonConfig, parseCocoonConfig(bad.value, allocator));
}

test "FarmElementConfig.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\[{"id": 1101, "world_level": 0, "stage_id": 1012010},
        \\ {"id": 1101, "world_level": 6, "stage_id": 1012016}]
    , .{});
    defer parsed.deinit();
    var config = try parseFarmElementConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqual(@as(u32, 1012016), config.find(1101, 6).?.stage_id);
    try std.testing.expectEqual(@as(u32, 1012010), config.find(1101, 3).?.stage_id);
    const by_stage = config.find(1012016, 0).?;
    try std.testing.expectEqual(@as(u32, 1012016), by_stage.stage_id);
    try std.testing.expectEqual(@as(u32, 6), by_stage.world_level);
    try std.testing.expect(config.find(1102, 6) == null);

    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 1101, \"world_level\": 0}]", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidFarmElementConfig, parseFarmElementConfig(bad.value, allocator));
}
