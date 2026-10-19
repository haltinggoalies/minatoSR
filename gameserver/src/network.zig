const std = @import("std");
const Session = @import("Session.zig");
const ConfigManager = @import("../src/manager/config_mgr.zig");
const Login = @import("services/login.zig");
const SceneManager = @import("manager/scene_mgr.zig");
const Allocator = std.mem.Allocator;

// 23301, where dispatch sends the client. PEARL_GAMESERVER_PORT moves a second server (the fake-client tests') off
// it: with reuse_address Windows lets two servers listen on one port, and clients then reach the first one.
fn listenPort() u16 {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "PEARL_GAMESERVER_PORT") catch return 23301;
    defer std.heap.page_allocator.free(value);
    return std.fmt.parseInt(u16, value, 10) catch 23301;
}

pub fn listen() !void {
    const addr = std.net.Address.parseIp4("0.0.0.0", listenPort()) catch unreachable;
    var listener = try addr.listen(.{
        .kernel_backlog = 100,
        .reuse_address = true,
    });

    std.log.info("server is listening at {}", .{listener.listen_address});

    while (true) {
        const conn = listener.accept() catch continue;

        runSession(
            conn.address,
            conn.stream,
            ConfigManager.global_main_allocator,
            &ConfigManager.global_game_config_cache,
        ) catch |err| {
            std.log.err("session error: {}", .{err});
        };
    }
}

fn runSession(
    address: std.net.Address,
    stream: std.net.Stream,
    main_allocator: Allocator,
    game_config_cache: *ConfigManager.GameConfigCache,
) !void {
    std.log.info("new connection from {}", .{address});
    // Nothing is pushed to a new connection until it has logged in.
    Login.logged_in = false;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) std.log.err("memory leaks were detected for session at {}", .{address});

    const session_allocator = gpa.allocator();

    const session = try session_allocator.create(Session);
    session.* = Session.init(address, stream, session_allocator, main_allocator, game_config_cache);
    defer session_allocator.destroy(session);

    if (session.*.run()) |_| {
        std.log.info("client from {} disconnected", .{address});
    } else |err| {
        std.log.err("session disconnected with an error: {}", .{err});
    }
    // The last steps walked since the throttled save.
    SceneManager.saveLocation();
}
