const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// resources/BattleCollegeConfig.json: each Battle College room and the stage it fights, trimmed from the game's
// BattleCollegeConfig excel to [{"id", "stage_id"}].
pub const Room = struct { id: u32, stage_id: u32 };

pub const BattleCollegeConfig = struct {
    rooms: ArrayList(Room),

    pub fn deinit(self: *BattleCollegeConfig) void {
        self.rooms.deinit();
    }
    pub fn find(self: *const BattleCollegeConfig, id: u32) ?Room {
        for (self.rooms.items) |room| {
            if (room.id == id) return room;
        }
        return null;
    }
};

pub fn parseBattleCollegeConfig(root: std.json.Value, allocator: Allocator) anyerror!BattleCollegeConfig {
    if (root != .array) return error.InvalidBattleCollegeConfig;
    var rooms = ArrayList(Room).init(allocator);
    errdefer rooms.deinit();
    for (root.array.items) |row| {
        try rooms.append(.{ .id = try intField(row, "id"), .stage_id = try intField(row, "stage_id") });
    }
    return .{ .rooms = rooms };
}

fn intField(row: std.json.Value, key: []const u8) !u32 {
    if (row != .object) return error.InvalidBattleCollegeConfig;
    const value = row.object.get(key) orelse return error.InvalidBattleCollegeConfig;
    if (value != .integer) return error.InvalidBattleCollegeConfig;
    return std.math.cast(u32, value.integer) orelse error.InvalidBattleCollegeConfig;
}

test "BattleCollegeConfig.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 3, \"stage_id\": 400103}, {\"id\": 11, \"stage_id\": 400104}]", .{});
    defer parsed.deinit();
    var config = try parseBattleCollegeConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqual(@as(u32, 400104), config.find(11).?.stage_id);
    try std.testing.expect(config.find(4) == null);

    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "{\"id\": 3}", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidBattleCollegeConfig, parseBattleCollegeConfig(bad.value, allocator));
}
