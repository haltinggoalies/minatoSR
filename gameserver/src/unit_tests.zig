// Every file with `test` blocks, so `zig build test` (run in gameserver/) finds them.
test {
    _ = @import("manager/profile_store.zig");
    _ = @import("utils/clock.zig");
    _ = @import("commands/windy.zig");
    _ = @import("commands/json.zig");
    _ = @import("services/profile.zig");
    _ = @import("manager/prefs_mgr.zig");
    _ = @import("services/mail.zig");
    _ = @import("services/pet.zig");
    _ = @import("services/avatar.zig");
    _ = @import("data/jukebox_config.zig");
    _ = @import("services/jukebox.zig");
    _ = @import("data/college_config.zig");
    _ = @import("services/college.zig");
    _ = @import("manager/record_mgr.zig");
    _ = @import("data/cocoon_config.zig");
    _ = @import("data/plane_event_config.zig");
}
