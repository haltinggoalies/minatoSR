const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

// Every pet is unlocked: the normal ones (Data.Pets) by id, the blind-box ones (Data.BlindBoxPets) as instances whose
// unique id is the pet id. The one that is out is kept in profile.json (0 = none).

// How the client tagged its last summon (LLGIIPALELD, meaning unknown), sent back as it came. Memory only.
var summon_kind: protocol.EOGNOEJHAGN = @enumFromInt(0);

fn isBlindBox(pet_id: u32) bool {
    return std.mem.indexOfScalar(u32, &Data.BlindBoxPets, pet_id) != null;
}
fn known(pet_id: u32) bool {
    for (Data.Pets) |pet| {
        if (pet.id == pet_id) return true;
    }
    return isBlindBox(pet_id);
}
fn curPet() u32 {
    const saved = ProfileStore.get().pet;
    return if (known(saved)) saved else 0;
}
fn petState(pet_id: u32) protocol.EHDNPMEKPCA {
    if (isBlindBox(pet_id)) return .{ .LLGIIPALELD = summon_kind, .HGEOKHHJAIE = .{ .EBAAFDHEPLO = pet_id } };
    return .{ .LLGIIPALELD = summon_kind, .HGEOKHHJAIE = .{ .ODNGMIJLKKA = pet_id } };
}
fn curState() ?protocol.EHDNPMEKPCA {
    const pet_id = curPet();
    return if (pet_id == 0) null else petState(pet_id);
}

pub fn onGetPetData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPetDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (Data.Pets) |pet| try rsp.HCAKDJMKDJP.append(pet.id);
    for (Data.BlindBoxPets) |pet_id| try rsp.MPJNPINHCJL.append(.{ .summoned_pet_id = pet_id, .EBAAFDHEPLO = pet_id });
    rsp.PLKBLNMOOPH = curState();
    try session.send(CmdID.CmdGetPetDataScRsp, rsp);
}

pub fn onSummonPet(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SummonPetCsReq, allocator);
    defer req.deinit();
    // Normal pets come by id, blind-box pets by their instance's unique id (which is the pet id here).
    const pet_id: u32 = if (req.HGEOKHHJAIE) |target| switch (target) {
        .ODNGMIJLKKA => |id| id,
        .EBAAFDHEPLO => |uid| if (uid <= std.math.maxInt(u32) and isBlindBox(@intCast(uid))) @intCast(uid) else 0,
    } else 0;
    if (known(pet_id)) {
        summon_kind = req.LLGIIPALELD;
        if (pet_id != curPet()) {
            ProfileStore.set("pet", pet_id);
            var change = protocol.PetDataChangeScNotify.init(allocator);
            try change.DGNGMJMPFGK.append(.{ .MMCGBGDJIPN = .{ .GJALNEHICDE = petState(pet_id) } });
            try session.send(CmdID.CmdPetDataChangeScNotify, change);
        }
    }
    try session.send(CmdID.CmdSummonPetScRsp, protocol.SummonPetScRsp{
        .retcode = 0,
        .PLKBLNMOOPH = curState(),
    });
}

pub fn onRecallPet(session: *Session, _: *const Packet, _: Allocator) !void {
    if (ProfileStore.get().pet != 0) ProfileStore.set("pet", @as(u32, 0));
    try session.send(CmdID.CmdRecallPetScRsp, protocol.RecallPetScRsp{
        .retcode = 0,
        .PLKBLNMOOPH = null,
    });
}

test "no pet item is in the bag" {
    for (Data.Pets) |pet| {
        try std.testing.expect(std.mem.indexOfScalar(u32, &Data.ItemList, pet.item_id) == null);
    }
    for (Data.BlindBoxPets) |pet_id| {
        try std.testing.expect(std.mem.indexOfScalar(u32, &Data.ItemList, pet_id) == null);
    }
}
