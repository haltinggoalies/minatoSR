//! Design data built by tools/thai_text, handed to the client in place of the CDN's.
//!
//! tools/thai_text writes design_override/<version>/<CDN folder>/client/Windows/... (the CDN's index with a Thai
//! TextMap added, and the Thai files) and upstream.txt, the CDN URL it was built from. The client re-reads the index
//! from ex_resource_url on every start, so the Thai text only stays while the dispatch keeps pointing it here.
//! Files that are not in the folder are redirected to the CDN.
const std = @import("std");
const httpz = @import("httpz");

const root = "design_override";
const route_prefix = "/" ++ root ++ "/";

/// The ex_resource_url to give the client: the build for `version` if there is one, else `ex_resource_url`.
pub fn exResourceUrl(allocator: std.mem.Allocator, version: []const u8, ex_resource_url: []const u8) ![]const u8 {
    if (!isName(version)) return ex_resource_url;
    const trimmed = std.mem.trimRight(u8, ex_resource_url, "/");
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse return ex_resource_url;
    const cdn_folder = trimmed[slash + 1 ..];
    const folder = (try buildFolder(allocator, version, cdn_folder)) orelse return ex_resource_url;
    if (!std.mem.eql(u8, folder, cdn_folder)) {
        // Still the build's index: it only lists files the client already has or the old CDN folder still serves,
        // where the CDN's new index would leave the client's Thai text language without a TextMap.
        std.log.warn("Thai design data for {s} is from CDN folder {s}, the CDN is now at {s}: run Thai-Beta.bat again", .{ version, folder, cdn_folder });
    }
    // Keeps the CDN's folder name as the last path segment, in case the client reads the version from it.
    return std.fmt.allocPrint(allocator, "http://127.0.0.1:21000/{s}/{s}/{s}", .{ root, version, folder });
}

/// `cdn_folder` if it was built, else another built folder of the version (tools/thai_text keeps one).
fn buildFolder(allocator: std.mem.Allocator, version: []const u8, cdn_folder: []const u8) !?[]const u8 {
    // A name with characters Windows rejects (e.g. a query string) would make the file check panic.
    if (isName(cdn_folder) and try hasBuild(allocator, version, cdn_folder)) return cdn_folder;
    const path = try std.fs.path.join(allocator, &.{ root, version });
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return null;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind == .directory and isName(entry.name) and try hasBuild(allocator, version, entry.name)) {
            return try allocator.dupe(u8, entry.name);
        }
    }
    return null;
}

/// tools/thai_text writes M_DesignV.bytes last, so a folder that has it is a finished build.
fn hasBuild(allocator: std.mem.Allocator, version: []const u8, folder: []const u8) !bool {
    const path = try std.fs.path.join(allocator, &.{ root, version, folder, "client", "Windows", "M_DesignV.bytes" });
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// GET/HEAD /design_override/<version>/<folder>/<file>: the file from the build, else a redirect to the CDN.
pub fn onGet(req: *httpz.Request, res: *httpz.Response) !void {
    const path = req.url.path;
    if (!std.mem.startsWith(u8, path, route_prefix)) return notFound(res);
    var parts = std.mem.splitScalar(u8, path[route_prefix.len..], '/');
    const version = parts.next() orelse "";
    const folder = parts.next() orelse "";
    const file = parts.rest();
    if (!isName(version) or !isName(folder) or file.len == 0) return notFound(res);
    var segments = std.mem.splitScalar(u8, file, '/');
    while (segments.next()) |segment| {
        if (!isName(segment)) return notFound(res);
    }

    const local = try std.fs.path.join(res.arena, &.{ root, version, folder, file });
    const handle = std.fs.cwd().openFile(local, .{}) catch |err| switch (err) {
        error.FileNotFound => return redirect(res, version, folder, file),
        else => {
            std.log.warn("Design data: cannot open {s}: {s}", .{ local, @errorName(err) });
            return notFound(res);
        },
    };
    defer handle.close();
    const size = (try handle.stat()).size;
    res.content_type = .BINARY;
    if (req.method == .HEAD) {
        res.header("Content-Length", try std.fmt.allocPrint(res.arena, "{d}", .{size}));
    } else {
        // One buffer of the file's size: reading to the end grows a list in the request arena, which keeps every
        // outgrown copy (3-4 times the 100 MB Thai TextMap) until the response is sent.
        const body = try res.arena.alloc(u8, @intCast(size));
        res.body = body[0..try handle.readAll(body)];
    }
    std.log.info("Design data: {s} {s} ({d} bytes)", .{ if (req.method == .HEAD) "HEAD" else "sent", local, size });
}

fn redirect(res: *httpz.Response, version: []const u8, folder: []const u8, file: []const u8) !void {
    const upstream_path = try std.fs.path.join(res.arena, &.{ root, version, folder, "upstream.txt" });
    const upstream = std.fs.cwd().readFileAlloc(res.arena, upstream_path, 4096) catch |err| {
        std.log.warn("Design data: cannot read {s} ({s}) to redirect {s} to the CDN: run Thai-Beta.bat again", .{ upstream_path, @errorName(err), file });
        return notFound(res);
    };
    const location = try std.fmt.allocPrint(res.arena, "{s}/{s}", .{ std.mem.trim(u8, upstream, " \r\n/"), file });
    res.setStatus(.found);
    res.header("Location", location);
    std.log.debug("Design data: {s} -> {s}", .{ file, location });
}

fn notFound(res: *httpz.Response) void {
    res.setStatus(.not_found);
}

/// A plain file or folder name: letters, digits, '.', '_' and '-', and not "." or "..".
fn isName(s: []const u8) bool {
    if (s.len == 0 or std.mem.eql(u8, s, ".") or std.mem.eql(u8, s, "..")) return false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '-') return false;
    }
    return true;
}
