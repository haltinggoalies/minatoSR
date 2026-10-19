const std = @import("std");
const protocol = @import("protocol");
const AvatarManager = @import("avatar_mgr.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.recommend);

// The teams shown in the in-game "Recommended Lineup" window. Same schema as the 4.6 server's
// Config/Custom/RecommendTeams.json, so one file serves both: keyed by the BigDataRecommendType the client
// asks for, without its "BIG_DATA_RECOMMEND_TYPE_" prefix (e.g. "CHALLENGE_PEAK_BOSS"), then by the ID it
// sends with it (e.g. the Anomaly Arbitration season). Parsed again when its size or mtime changes, so edits
// apply without a restart. A repeated key keeps the last one, as the 4.6 server's Newtonsoft load does.
const file_path = "recommend_teams.json";
const max_file_size = 64 << 20;

// The parsed file (or the error it gave), kept between requests: a Debug build takes ~65 ms to parse the 2 MB file.
// Not tied to a session's allocator; network.listen runs one session at a time, so no lock.
var cache: ?struct {
    arena: std.heap.ArenaAllocator,
    size: u64,
    mtime: i128,
    root: anyerror!std.json.Value,
} = null;

// BigDataRecommendType names by number (protocol.pb.zig only has obfuscated ones). Other numbers are looked
// up by their decimal value, as the 4.6 server does for values its proto does not name.
const type_names = [_][]const u8{
    "NONE",
    "EQUIPMENT",
    "RELIC_SUIT",
    "RELIC_AVATAR",
    "AVATAR_RELIC",
    "LOCAL_LEGEND",
    "CHALLENGE_PEAK_MOB", // Anomaly Arbitration knights, ID = season
    "CHALLENGE_PEAK_BOSS", // Anomaly Arbitration boss, ID = season
    "CHALLENGE",
    "HMFFBIANKBF",
    "IGDNEOELFKC", // Starward mode, ID = ChallengeMazeTierce stage
};

// How a team is written into the reply. Seen in the 4.6.0 client:
//   avatars_buff    one team and a buff                CHALLENGE_PEAK_BOSS (Anomaly Arbitration boss)
//   team_list       several teams ("lineups")          CHALLENGE_PEAK_MOB (Knight 1-3)
//   team_list_buff  several teams, each with a buff    IGDNEOELFKC (Starward mode)
//   two_halves      first and second half teams        CHALLENGE (not confirmed yet)
//   avatars         one team
const Format = enum { avatars, team_list, avatars_buff, two_halves, team_list_buff };

const Lineup = struct {
    avatars: []const u32 = &.{},
    buff_id: u32 = 0,
};

// "note" is not sent and not parsed; it says what the team is and where it came from.
const Team = struct {
    avatars: []const u32 = &.{},
    second_half: []const u32 = &.{},
    buff_id: u32 = 0,
    second_buff_id: u32 = 0,
    // For the list formats; when empty, avatars and buff_id make the only lineup.
    lineups: []const Lineup = &.{},

    fn getLineups(self: *const Team, one: *[1]Lineup) []const Lineup {
        if (self.lineups.len > 0) return self.lineups;
        one.* = .{.{ .avatars = self.avatars, .buff_id = self.buff_id }};
        return one;
    }
};

const Found = struct {
    format: Format = .avatars,
    teams: []const Team = &.{},
};

// The lineup list for GetBigDataRecommendScRsp, or null when the file has no teams for this type and ID.
// A missing or broken file is logged and answered with no teams; it never drops the player.
// Everything is allocated with `allocator` (the packet arena) and freed with it.
pub fn lineupList(allocator: Allocator, kind: protocol.BigDataRecommendType, id: u32) ?protocol.GNBBDMBNNDJ {
    var name_buf: [16]u8 = undefined;
    const name = typeName(kind, &name_buf);
    const found = find(allocator, name, id) catch |err| {
        switch (err) {
            error.FileNotFound => log.warn("{s} not found; no recommended teams for {s} {}", .{ file_path, name, id }),
            else => log.warn("{s} could not be read ({s}); no recommended teams for {s} {}", .{ file_path, @errorName(err), name, id }),
        }
        return null;
    };
    log.info("RECOMMENDED TEAMS {s} {}: {} ({s})", .{ name, id, found.teams.len, @tagName(found.format) });
    if (found.teams.len == 0) return null;

    var list = protocol.GNBBDMBNNDJ.init(allocator);
    for (found.teams) |*team| {
        const lineup = toLineup(allocator, team, found.format) catch |err| {
            log.warn("recommended teams for {s} {} could not be built: {s}", .{ name, id, @errorName(err) });
            return null;
        };
        list.lineup_list.append(lineup) catch |err| {
            log.warn("recommended teams for {s} {} could not be built: {s}", .{ name, id, @errorName(err) });
            return null;
        };
    }
    return list;
}

fn typeName(kind: protocol.BigDataRecommendType, buf: []u8) []const u8 {
    const value = @intFromEnum(kind);
    if (value >= 0 and value < type_names.len) return type_names[@intCast(value)];
    return std.fmt.bufPrint(buf, "{}", .{value}) catch "";
}

// The file's JSON tree, from the cache unless the file changed. `allocator` only holds the file's bytes while they
// are parsed (std.json.Value copies every string into the cache arena).
fn load(allocator: Allocator) !std.json.Value {
    const stat = std.fs.cwd().statFile(file_path) catch |err| {
        drop();
        return err;
    };
    if (cache) |c| {
        if (c.size == stat.size and c.mtime == stat.mtime) return c.root;
    }
    drop();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const root = parse(allocator, arena.allocator());
    if (std.meta.isError(root)) _ = arena.reset(.free_all);
    cache = .{ .arena = arena, .size = stat.size, .mtime = stat.mtime, .root = root };
    return root;
}

fn drop() void {
    if (cache) |*c| c.arena.deinit();
    cache = null;
}

fn parse(allocator: Allocator, tree_allocator: Allocator) !std.json.Value {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, file_path, max_file_size);
    defer allocator.free(bytes);
    // Windows editors may save a BOM, which std.json rejects.
    const text = if (std.mem.startsWith(u8, bytes, "\xEF\xBB\xBF")) bytes[3..] else bytes;
    return std.json.parseFromSliceLeaky(std.json.Value, tree_allocator, text, .{ .duplicate_field_behavior = .use_last });
}

// Only the requested type's entry has to be valid; the rest of the file only has to be JSON.
fn find(allocator: Allocator, name: []const u8, id: u32) !Found {
    const root = try load(allocator);
    if (root != .object) return error.NotAnObject;

    const entry = root.object.get(name) orelse return .{};
    if (entry != .object) return error.InvalidType;

    var found = Found{};
    if (entry.object.get("format")) |value| {
        if (value != .string) return error.InvalidFormat;
        found.format = std.meta.stringToEnum(Format, value.string) orelse blk: {
            log.warn("{s}: unknown format \"{s}\"; sending {s} teams as \"avatars\"", .{ file_path, value.string, name });
            break :blk .avatars;
        };
    }

    const teams = entry.object.get("teams") orelse return found;
    if (teams != .object) return error.InvalidTeams;
    var id_buf: [10]u8 = undefined;
    const key = std.fmt.bufPrint(&id_buf, "{}", .{id}) catch unreachable;
    const list = teams.object.get(key) orelse return found;
    found.teams = try std.json.parseFromValueLeaky([]const Team, allocator, list, .{ .ignore_unknown_fields = true });
    return found;
}

const Kind = protocol.JOLHIMGJGBO.JBLDLHIGGKM_union;

fn toLineup(allocator: Allocator, team: *const Team, format: Format) !protocol.JOLHIMGJGBO {
    var one: [1]Lineup = undefined;
    const kind: Kind = switch (format) {
        .team_list => blk: {
            var msg = protocol.CIOAOEGEIKH.init(allocator);
            for (team.getLineups(&one)) |lineup| {
                var entry = protocol.PEGJIHHIFOP.init(allocator);
                try appendAvatars(&entry.AEJPCFLOPAL, lineup.avatars);
                try msg.DNIGKDKIPPJ.append(entry);
            }
            break :blk .{ .DKBBMJDNHNG = msg };
        },
        .team_list_buff => blk: {
            var msg = protocol.GFDJLBJPNMC.init(allocator);
            for (team.getLineups(&one)) |lineup| {
                var entry = protocol.JGPMBLAJJJG.init(allocator);
                try appendAvatars(&entry.AEJPCFLOPAL, lineup.avatars);
                entry.buff_id = lineup.buff_id;
                try msg.GBMBAHHDONN.append(entry);
            }
            break :blk .{ .MIEJNLBBIDB = msg };
        },
        .avatars_buff => blk: {
            var msg = protocol.JPKIDILKOAK.init(allocator);
            try appendAvatars(&msg.AEJPCFLOPAL, team.avatars);
            msg.buff_id = team.buff_id;
            break :blk .{ .BDNBIHLJNCK = msg };
        },
        .two_halves => blk: {
            var msg = protocol.DAMNNJKJOMM.init(allocator);
            try appendAvatars(&msg.first_lineup, team.avatars);
            try appendAvatars(&msg.second_lineup, team.second_half);
            msg.DHMEBODOJMI = team.buff_id;
            msg.DLCJLOIMKOJ = team.second_buff_id;
            break :blk .{ .HCAAHIGINOM = msg };
        },
        .avatars => blk: {
            var msg = protocol.OHLNNOMJPNH.init(allocator);
            try appendAvatars(&msg.AEJPCFLOPAL, team.avatars);
            break :blk .{ .FJONKDKACAB = msg };
        },
    };
    return .{ .JBLDLHIGGKM = kind };
}

fn appendAvatars(list: *ArrayList(u32), ids: []const u32) !void {
    for (ids) |id| try list.append(forGender(id));
}

// Trailblazer IDs come in pairs per path (8001 male / 8002 female, ...); the file has the female one.
// Shows the player's own (AvatarManager.gender: 1 male, 2 female).
fn forGender(id: u32) u32 {
    if (id < 8001 or id > 8010) return id;
    const male = if (id % 2 == 1) id else id - 1;
    return if (AvatarManager.gender == 1) male else male + 1;
}
