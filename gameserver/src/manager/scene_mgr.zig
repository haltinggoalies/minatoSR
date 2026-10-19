const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Config = @import("../data/game_config.zig");
const Res_config = @import("../data/res_config.zig");
const ChallengeAnchors = @import("../data/challenge_anchors.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Uid = @import("../utils/uid.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const Logic = @import("../utils/logic.zig");
const Data = @import("../data.zig");
const ProfileStore = @import("profile_store.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const config = &ConfigManager.global_game_config_cache.game_config;
const res_config = &ConfigManager.global_game_config_cache.res_config;
const mission_config = &ConfigManager.global_game_config_cache.main_mission_config;
const saved_values_config = &ConfigManager.global_game_config_cache.saved_values_config;
const map_entrance_config = &ConfigManager.global_game_config_cache.map_entrance_config;
const anchors = &ConfigManager.global_game_config_cache.anchor_config;

// Floor of the last scene sent and where the party last stood, so party members can be swapped in place.
var party_floor_id: u32 = 0;
var party_plane_id: u32 = 0;
var party_entry_id: u32 = 0;
var party_pos: protocol.Vector = .{};
var party_rot: protocol.Vector = .{};
// Unknown after a scene the resources have no spawn point for, until the client reports a move. A swap waits
// for it rather than adding members at the origin; the pending team is the one the scene still shows.
var party_motion_known = false;
var pending_old_team: ?PresetManager.Team = null;
// Event of each overworld monster in the last scene sent, by entity id: which stage a /calyx off fight is.
var monster_events = std.AutoHashMap(u32, u32).init(std.heap.page_allocator);

pub fn monsterEvent(entity_id: u32) ?u32 {
    return monster_events.get(entity_id);
}

pub fn trackPartyMotion(motion: protocol.MotionInfo) void {
    if (motion.pos) |pos| {
        party_pos = pos;
        party_motion_known = true;
    }
    if (motion.rot) |rot| party_rot = rot;
    rememberLocation(false);
}

// The party's last overworld spot, so a login starts there (profile.json). Written when a scene is entered, at
// most every 10 s while walking, and when the client disconnects; never inside a challenge.
var unsaved_location: ?ProfileStore.Location = null;
var location_saved_ms: i64 = 0;

fn rememberLocation(now: bool) void {
    if (party_entry_id == 0 or !party_motion_known or Logic.Challenge().ChallengeMode()) return;
    unsaved_location = .{
        .plane_id = if (party_plane_id != 0) party_plane_id else entryPlaneId(party_entry_id),
        .floor_id = party_floor_id,
        .entry_id = party_entry_id,
        .x = party_pos.x,
        .y = party_pos.y,
        .z = party_pos.z,
        .rot_y = party_rot.y,
    };
    if (now or std.time.milliTimestamp() - location_saved_ms >= 10 * std.time.ms_per_s) saveLocation();
}
pub fn saveLocation() void {
    const spot = unsaved_location orelse return;
    unsaved_location = null;
    location_saved_ms = std.time.milliTimestamp();
    ProfileStore.set("location", spot);
}
// The saved spot, if MapEntrance still has its entry on that plane and floor.
pub fn savedLocation() ?ProfileStore.Location {
    const spot = ProfileStore.get().location orelse return null;
    if (spot.entry_id == 0 or entryPlaneId(spot.entry_id) != spot.plane_id) return null;
    if (entryFloorId(spot.entry_id) != spot.floor_id) return null;
    return spot;
}
// Set by createSceneAt for one createScene call.
var spawn_override: ?protocol.MotionInfo = null;
// Whether a scene entered without a teleport (/scene) has somewhere to put the party; without it the client never
// finishes loading.
pub fn hasSpawn(entry_id: u32) bool {
    return entrySpawnMotion(entry_id) != null;
}
// Where the party spawns in a scene entered without a matching teleport (/tp, the AA lobby, some challenge
// exits): the entry's first anchor, else its first teleport.
fn entrySpawnMotion(entry_id: u32) ?protocol.MotionInfo {
    if (ChallengeSceneManager.getAnchorMotion(entry_id)) |motion| return motion;
    for (res_config.scene_config.items) |sceneConf| {
        if (sceneConf.entryID != entry_id or sceneConf.teleports.items.len == 0) continue;
        const tele = sceneConf.teleports.items[0];
        return .{ .pos = toVector(tele.pos), .rot = toVector(tele.rot) };
    }
    return null;
}
pub fn entryFloorId(entry_id: u32) u32 {
    for (map_entrance_config.map_entrance_config.items) |entrConf| {
        if (entrConf.id == entry_id) return entrConf.floor_id;
    }
    return 0;
}
pub fn entryPlaneId(entry_id: u32) u32 {
    for (map_entrance_config.map_entrance_config.items) |entrConf| {
        if (entrConf.id == entry_id) return entrConf.plane_id;
    }
    return 0;
}

// Where the party is, for /scene.
pub const Location = struct { plane_id: u32, floor_id: u32, entry_id: u32, pos: protocol.Vector, pos_known: bool };
pub fn location() Location {
    return .{ .plane_id = party_plane_id, .floor_id = party_floor_id, .entry_id = party_entry_id, .pos = party_pos, .pos_known = party_motion_known };
}

// A res.json group of the current entry, with the distance from the party to its nearest prop, monster or teleport.
pub const GroupSummary = struct { group_id: u32, props: u32 = 0, monsters: u32 = 0, nearest_m: f64 = std.math.inf(f64) };
pub fn nearbyGroups(allocator: Allocator) ![]GroupSummary {
    var map = std.AutoArrayHashMap(u32, GroupSummary).init(allocator);
    for (res_config.scene_config.items) |sceneConf| {
        if (sceneConf.entryID != party_entry_id) continue;
        for (sceneConf.props.items) |p| (try groupEntry(&map, p.groupId, p.pos)).props += 1;
        for (sceneConf.monsters.items) |m| (try groupEntry(&map, m.groupId, m.pos)).monsters += 1;
        for (sceneConf.teleports.items) |t| _ = try groupEntry(&map, t.groupId, t.pos);
    }
    const groups = map.values();
    std.mem.sort(GroupSummary, groups, {}, struct {
        fn lessThan(_: void, a: GroupSummary, b: GroupSummary) bool {
            return a.nearest_m < b.nearest_m;
        }
    }.lessThan);
    return groups;
}
fn groupEntry(map: *std.AutoArrayHashMap(u32, GroupSummary), group_id: u32, pos: anytype) !*GroupSummary {
    const slot = try map.getOrPut(group_id);
    if (!slot.found_existing) slot.value_ptr.* = .{ .group_id = group_id };
    const dx: f64 = @floatFromInt(@as(i64, pos.x) - party_pos.x);
    const dy: f64 = @floatFromInt(@as(i64, pos.y) - party_pos.y);
    const dz: f64 = @floatFromInt(@as(i64, pos.z) - party_pos.z);
    slot.value_ptr.nearest_m = @min(slot.value_ptr.nearest_m, @sqrt(dx * dx + dy * dy + dz * dz) / 1000);
    return slot.value_ptr;
}

fn getBaseAvatarId(id: u32) u32 {
    return switch (id) {
        8001...8010 => 8001,
        1224 => 1001,
        else => id,
    };
}
fn hasBaseAvatar(ids: []const u32, base_id: u32) bool {
    for (ids) |id| {
        if (getBaseAvatarId(id) == base_id) return true;
    }
    return false;
}
inline fn toVector(v: anytype) protocol.Vector {
    return .{ .x = v.x, .y = v.y, .z = v.z };
}

// Swaps the overworld party from `old_team` to `new_team` at its last position; members in both keep
// their entity. Null when nobody joined or left, or while the position is unknown (see pendingPartyRefresh).
pub fn createPartyRefresh(allocator: Allocator, old_team: PresetManager.Team, new_team: PresetManager.Team) !?protocol.SceneGroupRefreshScNotify {
    if (!party_motion_known) {
        if (pending_old_team == null) pending_old_team = old_team;
        return null;
    }
    const shown = pending_old_team orelse old_team;
    pending_old_team = null;
    var group = protocol.GroupRefreshInfo.init(allocator);
    group.group_id = 0;
    var removed = false;
    for (shown.slice()) |id| {
        const base_id = getBaseAvatarId(id);
        if (hasBaseAvatar(new_team.slice(), base_id)) continue;
        removed = true;
        try group.refresh_entity.append(.{ .refresh_type = .{ .delete_entity = base_id + 100000 } });
    }
    for (new_team.slice()) |id| {
        const base_id = getBaseAvatarId(id);
        if (hasBaseAvatar(shown.slice(), base_id)) continue;
        try group.refresh_entity.append(.{ .refresh_type = .{ .add_entity = .{
            .inst_id = 1,
            .entity_id = base_id + 100000,
            .entity = .{
                .actor = .{
                    .base_avatar_id = base_id,
                    .avatar_type = .AVATAR_FORMAL_TYPE,
                    .uid = 0,
                    .map_layer = 0,
                },
            },
            .motion = .{ .pos = party_pos, .rot = party_rot },
        } } });
    }
    if (group.refresh_entity.items.len == 0) return null;
    group.refresh_type = if (removed) .SCENE_GROUP_REFRESH_TYPE_AFIBFMAFNCC else .SCENE_GROUP_REFRESH_TYPE_LOADED;
    var notify = protocol.SceneGroupRefreshScNotify.init(allocator);
    notify.floor_id = party_floor_id;
    notify.dimension_id = 0;
    try notify.group_refresh_list.append(group);
    return notify;
}
// The swap held back while the party's position was unknown, once the client has reported it.
pub fn pendingPartyRefresh(allocator: Allocator) !?protocol.SceneGroupRefreshScNotify {
    const old_team = pending_old_team orelse return null;
    if (!party_motion_known) return null;
    return createPartyRefresh(allocator, old_team, PresetManager.curTeam());
}
fn getOrCreateGroup(
    group_map: *std.AutoHashMap(u32, protocol.SceneEntityGroupInfo),
    group_id: u32,
    allocator: Allocator,
) !*protocol.SceneEntityGroupInfo {
    if (group_map.getPtr(group_id)) |g| return g;
    var new_group = protocol.SceneEntityGroupInfo.init(allocator);
    new_group.state = 1;
    new_group.group_id = group_id;
    new_group.property_map = ArrayList(protocol.SceneEntityGroupInfo.PropertyMapEntry).init(allocator);
    try group_map.put(group_id, new_group);
    return group_map.getPtr(group_id).?;
}
pub const SceneManager = struct {
    allocator: Allocator,
    pub fn init(allocator: Allocator) SceneManager {
        return .{ .allocator = allocator };
    }
    fn addAvatarEntities(
        scene_group: *protocol.SceneEntityGroupInfo,
        avatar_ids: []const u32,
        tele_pos: protocol.Vector,
        tele_rot: protocol.Vector,
        uid: u32,
    ) !void {
        for (avatar_ids) |avatar_id| {
            const base_id = getBaseAvatarId(avatar_id);
            try scene_group.entity_list.append(.{
                .inst_id = 1,
                .entity_id = @intCast(base_id + 100000),
                .entity = .{
                    .actor = .{
                        .base_avatar_id = base_id,
                        .avatar_type = .AVATAR_FORMAL_TYPE,
                        .uid = uid,
                        .map_layer = 0,
                    },
                },
                .motion = .{ .pos = tele_pos, .rot = tele_rot },
            });
        }
    }
    fn addPropEntities(
        allocator: Allocator,
        group_map: *std.AutoHashMap(u32, protocol.SceneEntityGroupInfo),
        prop_configs: []const Res_config.Props,
        generator: *Uid.BaseUidGen(),
    ) !void {
        for (prop_configs) |propConf| {
            var scene_group = try getOrCreateGroup(group_map, propConf.groupId, allocator);
            var prop_info = protocol.ScenePropInfo.init(allocator);
            prop_info.prop_id = propConf.propId;
            prop_info.prop_state = propConf.propState;
            try scene_group.entity_list.append(.{
                .entity = .{ .prop = prop_info },
                .group_id = scene_group.group_id,
                .inst_id = propConf.instId,
                .entity_id = 1000 + generator.nextId(),
                .motion = .{ .pos = toVector(propConf.pos), .rot = toVector(propConf.rot) },
            });
        }
    }
    fn addMonsterEntities(
        allocator: Allocator,
        group_map: *std.AutoHashMap(u32, protocol.SceneEntityGroupInfo),
        monster_configs: []const Res_config.Monsters,
        generator: *Uid.BaseUidGen(),
    ) !void {
        for (monster_configs) |monsConf| {
            var scene_group = try getOrCreateGroup(group_map, monsConf.groupId, allocator);
            var monster_info = protocol.SceneNpcMonsterInfo.init(allocator);
            monster_info.monster_id = monsConf.monsterId;
            monster_info.event_id = monsConf.eventId;
            monster_info.world_level = 6;
            const entity_id = if ((monsConf.monsterId / 1000) % 10 == 3) monster_info.monster_id else generator.nextId();
            try scene_group.entity_list.append(.{
                .entity = .{ .npc_monster = monster_info },
                .group_id = scene_group.group_id,
                .inst_id = monsConf.instId,
                .entity_id = entity_id,
                .motion = .{ .pos = toVector(monsConf.pos), .rot = toVector(monsConf.rot) },
            });
            try monster_events.put(entity_id, monsConf.eventId);
        }
    }
    pub fn createScene(
        self: *SceneManager,
        plane_id: u32,
        floor_id: u32,
        entry_id: u32,
        teleport_id: u32,
    ) !protocol.SceneInfo {
        var generator = Uid.BaseUidGen().init();
        var scene_info = protocol.SceneInfo.init(self.allocator);
        scene_info.game_mode_type = 1;
        scene_info.plane_id = plane_id;
        scene_info.floor_id = floor_id;
        scene_info.entry_id = entry_id;
        scene_info.scene_identifier = .{ .floor_id = floor_id };
        // /tp without a floor sends floor 0; the party still stands on the entry's floor.
        party_floor_id = if (floor_id != 0) floor_id else entryFloorId(entry_id);
        party_plane_id = plane_id;
        party_entry_id = entry_id;
        party_pos = .{};
        party_rot = .{};
        party_motion_known = false;
        pending_old_team = null;
        monster_events.clearRetainingCapacity();

        // Upstream withheld every saved value on the train (b2f7a69). Floor 10000003 is the Party Train
        // (Anomaly Arbitration's lobby, entry 100000352): its Build_*/Progress_*/Onboarded values decide which
        // rooms and passengers exist, so it gets its keys, all off except Onboarded.
        for (saved_values_config.floor_saved_values.items) |saved| {
            if (saved.floor_id != floor_id or (plane_id == 10000 and floor_id != 10000003)) continue;
            for (saved.saved_values.items) |values| {
                const name = values.name orelse "";
                // On the Party Train only "Onboarded" is set: with every room reported built, the OSBETA client
                // tried to create a passenger NPC (1608, group 103) it has no data for and never finished loading.
                const on = plane_id != 10000 or std.mem.eql(u8, name, "Onboarded");
                try scene_info.floor_saved_data.append(.{
                    .key = .{ .Const = name },
                    .value = if (on) (values.max_value orelse 0) else 0,
                });
            }
        }

        // Only the current team preset is spawned; config.json can list many more characters.
        const party = PresetManager.curTeam();
        const team_ids = party.slice();
        if (team_ids.len > 0) scene_info.leader_entity_id = getBaseAvatarId(team_ids[party.leader_slot]) + 100000;
        scene_info.world_id = Data.WorldId;
        scene_info.client_pos_version = 1;
        var group_map = std.AutoHashMap(u32, protocol.SceneEntityGroupInfo).init(self.allocator);
        defer group_map.deinit();
        for (res_config.scene_config.items) |sceneConf| {
            for (sceneConf.teleports.items) |teleConf| {
                if (teleConf.teleportId != teleport_id) continue;
                var scene_group = protocol.SceneEntityGroupInfo.init(self.allocator);
                scene_group.state = 1;
                party_pos = toVector(teleConf.pos);
                party_rot = toVector(teleConf.rot);
                party_motion_known = true;
                try addAvatarEntities(&scene_group, team_ids, party_pos, party_rot, 0);
                try scene_info.entity_group_list.append(scene_group);
                break;
            }
            if (sceneConf.planeID == plane_id and sceneConf.entryID == entry_id) {
                try addPropEntities(self.allocator, &group_map, sceneConf.props.items, &generator);
                try addMonsterEntities(self.allocator, &group_map, sceneConf.monsters.items, &generator);
            }
        }
        // No teleport matched (teleport_id 0: Anomaly Arbitration's Express lobby 100000352, /tp, challenge
        // exits, a login at the last spot). The client never leaves the loading screen of a scene without its
        // party, so spawn it at the given spot or the entry's spawn point.
        if (!party_motion_known) {
            if (spawn_override orelse entrySpawnMotion(entry_id)) |motion| {
                trackPartyMotion(motion);
                var scene_group = protocol.SceneEntityGroupInfo.init(self.allocator);
                scene_group.state = 1;
                try addAvatarEntities(&scene_group, team_ids, party_pos, party_rot, 0);
                try scene_info.entity_group_list.append(scene_group);
            } else {
                std.log.warn("entry {}: no teleport {}, anchor or entry teleport to spawn the party at; the scene has no party", .{ entry_id, teleport_id });
            }
        }
        var iter = group_map.iterator();
        while (iter.next()) |entry| {
            const g = entry.value_ptr.*;
            try scene_info.entity_group_list.append(g);
            try scene_info.entity_list.appendSlice(g.entity_list.items);
            try scene_info.opened_chest_id_list.append(g.group_id);
            try scene_info.custom_data_list.append(.{ .group_id = g.group_id });
        }
        const ranges = [_][2]usize{ .{ 0, 101 }, .{ 10000, 10051 }, .{ 20000, 20001 }, .{ 30000, 30020 } };
        for (ranges) |range| {
            for (range[0]..range[1]) |i| try scene_info.lighten_section_list.append(@intCast(i));
        }
        rememberLocation(true);
        return scene_info;
    }
    // createScene with the party at `motion` (a login at the last saved spot).
    pub fn createSceneAt(self: *SceneManager, plane_id: u32, floor_id: u32, entry_id: u32, motion: protocol.MotionInfo) !protocol.SceneInfo {
        spawn_override = motion;
        defer spawn_override = null;
        return self.createScene(plane_id, floor_id, entry_id, 0);
    }
};
pub const ChallengeSceneManager = struct {
    allocator: Allocator,
    pub fn init(allocator: Allocator) ChallengeSceneManager {
        return .{ .allocator = allocator };
    }
    pub fn getAnchorMotion(entry_id: u32) ?protocol.MotionInfo {
        for (anchors.anchor_config.items) |anchorConf| {
            if (anchorConf.entryID != entry_id) continue;
            if (anchorConf.anchor.items.len == 0) break;
            const a = anchorConf.anchor.items[0];
            return protocol.MotionInfo{ .pos = toVector(a.pos), .rot = toVector(a.rot) };
        }
        return null;
    }
    // The game's own start point of the node's maze group (the group holding the node's monster).
    fn groupAnchorMotion(scene_info: *const protocol.SceneInfo) ?protocol.MotionInfo {
        for (scene_info.entity_group_list.items) |group| {
            for (group.entity_list.items) |entity| {
                if (entity.entity) |ent| if (ent == .npc_monster) {
                    for (ChallengeAnchors.list) |a| {
                        if (a.entry_id == scene_info.entry_id and a.group_id == group.group_id) {
                            return .{ .pos = .{ .x = a.x, .y = a.y, .z = a.z }, .rot = .{ .y = a.rot_y } };
                        }
                    }
                    return null;
                };
            }
        }
        return null;
    }
    // Challenge maps missing from the table: 20 m in front of the node's monster, at its height, facing it. Only
    // right on flat maps: on stairs or a raised stage (AS 3012201, 3012402) it left the party above the floor,
    // unable to walk.
    fn monsterFrontMotion(scene_info: *const protocol.SceneInfo) ?protocol.MotionInfo {
        for (scene_info.entity_group_list.items) |group| {
            for (group.entity_list.items) |entity| {
                if (entity.entity) |ent| if (ent == .npc_monster) {
                    const motion = entity.motion orelse return null;
                    const pos = motion.pos orelse return null;
                    const rot = motion.rot orelse protocol.Vector{};
                    const yaw = @as(f64, @floatFromInt(rot.y)) / 1000.0 * std.math.pi / 180.0;
                    const dx: i32 = @intFromFloat(@round(20000.0 * @sin(yaw)));
                    const dz: i32 = @intFromFloat(@round(20000.0 * @cos(yaw)));
                    return .{
                        .pos = .{ .x = pos.x + dx, .y = pos.y, .z = pos.z + dz },
                        .rot = .{ .x = 0, .y = @mod(rot.y + 180000, 360000), .z = 0 },
                    };
                };
            }
        }
        return null;
    }
    // Where the party stands in a challenge map: the node group's start anchor, else the entry's first anchor,
    // else in front of the monster.
    pub fn spawnMotion(scene_info: *const protocol.SceneInfo) ?protocol.MotionInfo {
        return groupAnchorMotion(scene_info) orelse getAnchorMotion(scene_info.entry_id) orelse monsterFrontMotion(scene_info);
    }
    // Where the party stands in an Anomaly Arbitration arena: Anchor1 of the arena's monster group in the game's
    // level data (DimbreathBot/TurnBasedGameData, Config/LevelOutput/SharedRuntimeGroup), in res.json units.
    // Anchor.json has none of these but 3012302's, which is group 72's spot, not group 5's.
    const PeakArenaAnchor = struct { entry_id: u32, group_id: u32, pos: protocol.Vector, rot_y: i32 };
    const peak_arena_anchors = [_]PeakArenaAnchor{
        .{ .entry_id = 3013501, .group_id = 8, .pos = .{ .x = 110, .y = 1244, .z = -20250 }, .rot_y = 0 },
        .{ .entry_id = 3013701, .group_id = 10, .pos = .{ .x = 6900, .y = 657847, .z = 10250 }, .rot_y = 215000 },
        .{ .entry_id = 3012302, .group_id = 5, .pos = .{ .x = -34, .y = 4615, .z = 261712 }, .rot_y = 0 },
        .{ .entry_id = 3012302, .group_id = 72, .pos = .{ .x = -34, .y = 4615, .z = 272712 }, .rot_y = 0 },
        .{ .entry_id = 3014001, .group_id = 7, .pos = .{ .x = -321540, .y = 49596, .z = 37620 }, .rot_y = 180000 },
        .{ .entry_id = 3014101, .group_id = 5, .pos = .{ .x = -31509, .y = -14827, .z = -48 }, .rot_y = 90000 },
        .{ .entry_id = 3014101, .group_id = 6, .pos = .{ .x = -31509, .y = -14827, .z = -48 }, .rot_y = 90000 },
        .{ .entry_id = 3014101, .group_id = 7, .pos = .{ .x = -31509, .y = -14827, .z = -48 }, .rot_y = 90000 },
        .{ .entry_id = 3014101, .group_id = 8, .pos = .{ .x = -31509, .y = -14827, .z = -48 }, .rot_y = 90000 },
        .{ .entry_id = 3014201, .group_id = 7, .pos = .{ .x = 11487, .y = 310285, .z = -11212 }, .rot_y = 315000 },
        .{ .entry_id = 3014201, .group_id = 8, .pos = .{ .x = 11487, .y = 310285, .z = -11212 }, .rot_y = 315000 },
        .{ .entry_id = 3000204, .group_id = 4, .pos = .{ .x = 18722, .y = 144064, .z = -14086 }, .rot_y = 270000 },
        .{ .entry_id = 3014401, .group_id = 5, .pos = .{ .x = 102680, .y = 240533, .z = 120500 }, .rot_y = 12000 },
        .{ .entry_id = 3014501, .group_id = 7, .pos = .{ .x = 43420, .y = -651030, .z = 506340 }, .rot_y = 0 },
        .{ .entry_id = 3014501, .group_id = 8, .pos = .{ .x = 43420, .y = -651030, .z = 506340 }, .rot_y = 0 },
        // Season 10's arena has no public level data: like every Anchor1 above, 18 m in front of the group's
        // res.json monster (-204790, -163012, -3470, facing 70°), at its height, facing it.
        .{ .entry_id = 3014601, .group_id = 6, .pos = .{ .x = -187876, .y = -163012, .z = 2686 }, .rot_y = 250000 },
        .{ .entry_id = 3014601, .group_id = 7, .pos = .{ .x = -187876, .y = -163012, .z = 2686 }, .rot_y = 250000 },
    };
    pub fn peakSpawnMotion(scene_info: *const protocol.SceneInfo, group_id: u32) ?protocol.MotionInfo {
        for (peak_arena_anchors) |a| {
            if (a.entry_id == scene_info.entry_id and a.group_id == group_id) {
                return .{ .pos = a.pos, .rot = .{ .y = a.rot_y } };
            }
        }
        return monsterFrontMotion(scene_info);
    }
    // Spawns the team at the spawn point, for scenes sent without a follow-up SceneEntityMoveScNotify.
    pub fn placeActorsAtAnchor(scene_info: *protocol.SceneInfo) void {
        const motion = spawnMotion(scene_info) orelse return;
        placeActorsAt(scene_info, motion);
    }
    pub fn placeActorsAt(scene_info: *protocol.SceneInfo, motion: protocol.MotionInfo) void {
        for (scene_info.entity_group_list.items) |*group| {
            for (group.entity_list.items) |*entity| {
                if (entity.entity) |ent| if (ent == .actor) {
                    entity.motion = motion;
                };
            }
        }
    }
    fn createBaseScene(
        self: *ChallengeSceneManager,
        game_mode_type: u32,
        avatar_list: ArrayList(u32),
        plane_id: u32,
        floor_id: u32,
        entry_id: u32,
        world_id: ?u32,
    ) !protocol.SceneInfo {
        var scene_info = protocol.SceneInfo.init(self.allocator);
        scene_info.game_mode_type = game_mode_type;
        scene_info.plane_id = plane_id;
        scene_info.floor_id = floor_id;
        scene_info.entry_id = entry_id;
        scene_info.scene_identifier = .{ .floor_id = floor_id };
        party_floor_id = floor_id;
        // A challenge scene shows the challenge team, so no preset swap is owed to it.
        party_motion_known = false;
        pending_old_team = null;

        // The leader must be one of the actor entities below (base id + 100000), not a raw avatar id.
        if (avatar_list.items.len > 0) {
            const slot = Logic.Challenge().LeaderSlot();
            const leader = if (slot < avatar_list.items.len) avatar_list.items[slot] else avatar_list.items[0];
            scene_info.leader_entity_id = getBaseAvatarId(leader) + 100000;
        }
        if (world_id) |wid| scene_info.world_id = wid;

        var scene_group = protocol.SceneEntityGroupInfo.init(self.allocator);
        scene_group.state = 1;
        scene_group.group_id = 0;

        for (saved_values_config.floor_saved_values.items) |saved| {
            if (saved.floor_id == floor_id) {
                for (saved.saved_values.items) |values| {
                    try scene_info.floor_saved_data.append(.{
                        .key = .{ .Const = values.name orelse "" },
                        .value = values.max_value orelse 0,
                    });
                }
            }
        }

        for (avatar_list.items) |avatar_base_id| {
            const base_id = getBaseAvatarId(avatar_base_id);
            try scene_group.entity_list.append(.{
                .inst_id = 1,
                .entity_id = @intCast(base_id + 100000),
                .entity = .{
                    .actor = .{
                        .base_avatar_id = base_id,
                        .avatar_type = .AVATAR_FORMAL_TYPE,
                        .uid = 1,
                        .map_layer = 0,
                    },
                },
                .motion = .{ .pos = .{}, .rot = .{} },
            });
        }
        try scene_info.entity_group_list.append(scene_group);
        return scene_info;
    }
    fn addChallengeEntities(
        self: *ChallengeSceneManager,
        scene_info: *protocol.SceneInfo,
        group_id: u32,
        monster_id: u32,
        event_id: u32,
        generator: *Uid.BaseUidGen(),
    ) !void {
        // A plane's res.json entries are its floors, and they reuse group ids: take the scene's own entry first
        // so another floor's monster does not end up in the map, and fall back to the whole plane.
        for ([_]bool{ true, false }) |own_entry_only| {
            var added = false;
            for (res_config.scene_config.items) |sceneConf| {
                if (sceneConf.planeID != scene_info.plane_id) continue;
                if (own_entry_only and sceneConf.entryID != scene_info.entry_id) continue;
                added = try self.addChallengeGroup(scene_info, sceneConf, group_id, monster_id, event_id, generator) or added;
            }
            if (added) break;
        }
    }
    fn addChallengeGroup(
        self: *ChallengeSceneManager,
        scene_info: *protocol.SceneInfo,
        sceneConf: Res_config.ResConfig,
        group_id: u32,
        monster_id: u32,
        event_id: u32,
        generator: *Uid.BaseUidGen(),
    ) !bool {
        var added = false;
        {
            for (sceneConf.monsters.items) |monsConf| {
                if (monsConf.groupId != group_id) continue;
                var scene_group = protocol.SceneEntityGroupInfo.init(self.allocator);
                scene_group.state = 1;
                scene_group.group_id = group_id;
                var monster_info = protocol.SceneNpcMonsterInfo.init(self.allocator);
                monster_info.monster_id = monster_id;
                monster_info.event_id = event_id;
                monster_info.world_level = 6;
                try scene_group.entity_list.append(.{
                    .entity = .{ .npc_monster = monster_info },
                    .group_id = group_id,
                    .inst_id = monsConf.instId,
                    .entity_id = generator.nextId(),
                    .motion = .{ .pos = toVector(monsConf.pos), .rot = toVector(monsConf.rot) },
                });
                try scene_info.entity_group_list.append(scene_group);
                added = true;
                break;
            }
            for (sceneConf.props.items) |propConf| {
                if (propConf.groupId != group_id) continue;
                var scene_group = protocol.SceneEntityGroupInfo.init(self.allocator);
                scene_group.state = 1;
                scene_group.group_id = group_id;
                var prop_info = protocol.ScenePropInfo.init(self.allocator);
                prop_info.prop_id = propConf.propId;
                prop_info.prop_state = propConf.propState;
                try scene_group.entity_list.append(.{
                    .entity = .{ .prop = prop_info },
                    .group_id = group_id,
                    .inst_id = propConf.instId,
                    .entity_id = generator.nextId(),
                    .motion = .{ .pos = toVector(propConf.pos), .rot = toVector(propConf.rot) },
                });
                try scene_info.entity_group_list.append(scene_group);
                added = true;
            }
        }
        return added;
    }
    pub fn createScene(
        self: *ChallengeSceneManager,
        avatar_list: ArrayList(u32),
        plane_id: u32,
        floor_id: u32,
        entry_id: u32,
        world_id: u32,
        monster_id: u32,
        event_id: u32,
        group_id: u32,
    ) !protocol.SceneInfo {
        var scene_info = try self.createBaseScene(4, avatar_list, plane_id, floor_id, entry_id, world_id);
        var generator = Uid.BaseUidGen().init();
        try self.addChallengeEntities(&scene_info, group_id, monster_id, event_id, &generator);
        return scene_info;
    }
    pub fn createPeakScene(
        self: *ChallengeSceneManager,
        avatar_list: ArrayList(u32),
        plane_id: u32,
        floor_id: u32,
        entry_id: u32,
        monster_id: u32,
        event_id: u32,
        group_id: u32,
    ) !protocol.SceneInfo {
        var scene_info = try self.createBaseScene(4, avatar_list, plane_id, floor_id, entry_id, null);
        var generator = Uid.BaseUidGen().init();
        try self.addChallengeEntities(&scene_info, group_id, monster_id, event_id, &generator);
        return scene_info;
    }
};
pub const MazeMapManager = struct {
    allocator: Allocator,
    pub fn init(allocator: Allocator) MazeMapManager {
        return .{ .allocator = allocator };
    }
    pub fn setMazeMapData(
        self: *MazeMapManager,
        map_info: *protocol.SceneMapInfo,
        floor_id: u32,
    ) !void {
        var plane_ids_map = std.AutoHashMap(u32, void).init(self.allocator);
        defer plane_ids_map.deinit();
        for (map_entrance_config.map_entrance_config.items) |entrConf| {
            if (entrConf.floor_id == floor_id) {
                try plane_ids_map.put(entrConf.plane_id, {});
            }
        }
        map_info.maze_group_list = ArrayList(protocol.MazeGroup).init(self.allocator);
        map_info.maze_prop_list = ArrayList(protocol.MazePropState).init(self.allocator);
        for (res_config.scene_config.items) |sceneConf| {
            if (!plane_ids_map.contains(sceneConf.planeID)) continue;
            for (sceneConf.props.items) |propConf| {
                try map_info.maze_group_list.append(protocol.MazeGroup{
                    .destory_monster_config_id_list = ArrayList(u32).init(self.allocator),
                    .group_id = propConf.groupId,
                });
                try map_info.maze_prop_list.append(protocol.MazePropState{
                    .group_id = propConf.groupId,
                    .config_id = propConf.instId,
                    .state = propConf.propState,
                });
            }
        }
    }
};
