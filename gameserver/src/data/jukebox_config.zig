const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// resources/BackGroundMusic.json: the jukebox tracks, trimmed from the game's BackGroundMusic excel to
// [{"id", "group_id"}].
pub const Track = struct { id: u32, group_id: u32 };

pub const BackGroundMusicConfig = struct {
    tracks: ArrayList(Track),

    pub fn deinit(self: *BackGroundMusicConfig) void {
        self.tracks.deinit();
    }
    pub fn find(self: *const BackGroundMusicConfig, id: u32) ?Track {
        for (self.tracks.items) |track| {
            if (track.id == id) return track;
        }
        return null;
    }
};

pub fn parseBackGroundMusicConfig(root: std.json.Value, allocator: Allocator) anyerror!BackGroundMusicConfig {
    if (root != .array) return error.InvalidBackGroundMusic;
    var tracks = ArrayList(Track).init(allocator);
    errdefer tracks.deinit();
    for (root.array.items) |row| {
        try tracks.append(.{ .id = try intField(row, "id"), .group_id = try intField(row, "group_id") });
    }
    return .{ .tracks = tracks };
}

fn intField(row: std.json.Value, key: []const u8) !u32 {
    if (row != .object) return error.InvalidBackGroundMusic;
    const value = row.object.get(key) orelse return error.InvalidBackGroundMusic;
    if (value != .integer) return error.InvalidBackGroundMusic;
    return std.math.cast(u32, value.integer) orelse error.InvalidBackGroundMusic;
}

test "BackGroundMusic.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 210000, \"group_id\": 1}, {\"id\": 210100, \"group_id\": 2}]", .{});
    defer parsed.deinit();
    var config = try parseBackGroundMusicConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 2), config.tracks.items.len);
    try std.testing.expectEqual(@as(u32, 2), config.find(210100).?.group_id);
    try std.testing.expect(config.find(1) == null);

    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 210000}]", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidBackGroundMusic, parseBackGroundMusicConfig(bad.value, allocator));
}
