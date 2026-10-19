const std = @import("std");
const builtin = @import("builtin");
const network = @import("network.zig");
const ConfigManager = @import("../src/manager/config_mgr.zig");
const PresetManager = @import("../src/manager/preset_mgr.zig");
const ProfileStore = @import("../src/manager/profile_store.zig");
const TierceManager = @import("../src/manager/tierce_mgr.zig");
const PrefsManager = @import("../src/manager/prefs_mgr.zig");
const RecordManager = @import("../src/manager/record_mgr.zig");

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    try ConfigManager.initGameGlobals(allocator);
    defer ConfigManager.deinitGameGlobals();
    PresetManager.load(allocator);
    ProfileStore.load();
    TierceManager.load(allocator);
    PrefsManager.load();
    RecordManager.load(allocator);
    try network.listen();
    std.log.info("Server listening for connections.", .{});
}
