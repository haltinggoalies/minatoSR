const std = @import("std");
const Allocator = std.mem.Allocator;

// resources/PlaneEvent.json: the stage each overworld monster's event fights at world level 6 (the server's; an event
// without a world level 6 row has its highest one below), trimmed from the 4.6.51 PlaneEvent excel to
// [{"event_id", "stage_id"}].
pub const PlaneEventConfig = struct {
    stages: std.AutoHashMap(u32, u32),

    pub fn deinit(self: *PlaneEventConfig) void {
        self.stages.deinit();
    }
    pub fn stageFor(self: *const PlaneEventConfig, event_id: u32) ?u32 {
        return self.stages.get(event_id);
    }
};

pub fn parsePlaneEventConfig(root: std.json.Value, allocator: Allocator) anyerror!PlaneEventConfig {
    if (root != .array) return error.InvalidPlaneEvent;
    var stages = std.AutoHashMap(u32, u32).init(allocator);
    errdefer stages.deinit();
    for (root.array.items) |row| {
        try stages.put(try intField(row, "event_id"), try intField(row, "stage_id"));
    }
    return .{ .stages = stages };
}

fn intField(row: std.json.Value, key: []const u8) !u32 {
    if (row != .object) return error.InvalidPlaneEvent;
    const value = row.object.get(key) orelse return error.InvalidPlaneEvent;
    if (value != .integer) return error.InvalidPlaneEvent;
    return std.math.cast(u32, value.integer) orelse error.InvalidPlaneEvent;
}

test "PlaneEvent.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"event_id\": 20503001, \"stage_id\": 1012286}]", .{});
    defer parsed.deinit();
    var config = try parsePlaneEventConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqual(@as(?u32, 1012286), config.stageFor(20503001));
    try std.testing.expectEqual(@as(?u32, null), config.stageFor(20503002));

    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"event_id\": 20503001}]", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidPlaneEvent, parsePlaneEventConfig(bad.value, allocator));
}
