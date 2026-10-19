const std = @import("std");
const builtin = @import("builtin");
const httpz = @import("httpz");
const protocol = @import("protocol");

const authentication = @import("authentication.zig");
const dispatch = @import("dispatch.zig");
const design_override = @import("design_override.zig");
const srtools = @import("srtools.zig");
const PORT = 21000;

pub const std_options = std.Options{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // SRTools syncs a whole freesr-data.json, which passes httpz's 1 MiB default with enough relics.
    // httpz preallocates one buffer per worker thread sized to max_body_size unless large_buffer_size is
    // set, so that stays at its 64 KiB default and bigger bodies are allocated only when they arrive.
    var server = try httpz.Server(void).init(allocator, .{
        .port = PORT,
        .request = .{ .max_body_size = 32 * 1024 * 1024 },
        .workers = .{ .large_buffer_size = 64 * 1024 },
    }, {});
    defer server.stop();
    defer server.deinit();
    var router = try server.router(.{});

    router.get("/query_dispatch", dispatch.onQueryDispatch, .{});
    router.get("/query_gateway", dispatch.onQueryGateway, .{});
    router.post("/account/risky/api/check", authentication.onRiskyApiCheck, .{});
    router.post("/:product_name/mdk/shield/api/login", authentication.onShieldLogin, .{});
    router.post("/:product_name/mdk/shield/api/verify", authentication.onVerifyLogin, .{});
    router.post("/:product_name/combo/granter/login/v2/login", authentication.onComboTokenReq, .{});
    router.post("/account/ma-cn-passport/app/loginByPassword", authentication.onappLoginByPassword, .{});
    router.post("/account/ma-cn-session/app/verify", authentication.onVerify, .{});
    router.get("/design_override/*", design_override.onGet, .{});
    router.head("/design_override/*", design_override.onGet, .{});
    // SRTools "Connect PS": provider Other posts to the URL as typed, provider RobinSR to /srtools.
    for ([_][]const u8{ "/", "/srtools", "/sr-tools" }) |path| {
        router.post(path, srtools.onPost, .{});
        router.options(path, srtools.onPreflight, .{});
    }

    std.log.info("Dispatch is listening at localhost:{?}", .{server.config.port});
    try server.listen();
}
