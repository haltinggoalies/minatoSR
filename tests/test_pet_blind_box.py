"""Blind-box pets (4.6): each is a pet instance in GetPetData (PetModule._AddBlindBoxPet(JGDOHOFOFOF)), summoned by its
unique id; the one out is kept in profile.json like a normal pet."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

BLIND_BOX = list(range(251501, 251513)) + list(range(251520, 251525))  # BlindBoxPet.json, 17 rows


def pet_data(c):
    return c.call("GetPetDataCsReq", {}, "GetPetDataScRsp")[0]


with Server() as srv:
    c = srv.login()
    rsp = pet_data(c)
    check("normal pets stay unlocked by id", rsp.get("HCAKDJMKDJP") == [1001, 1002, 1003, 1004, 1005], rsp.get("HCAKDJMKDJP"))
    instances = rsp.get("MPJNPINHCJL", [])
    check("every blind-box pet has an instance", sorted(i.get("summoned_pet_id") for i in instances) == BLIND_BOX,
          [i.get("summoned_pet_id") for i in instances])
    uids = [i.get("EBAAFDHEPLO") for i in instances]
    check("instances have distinct unique ids", len(set(uids)) == len(BLIND_BOX) and 0 not in uids, uids)

    uid = instances[0]["EBAAFDHEPLO"] if instances else 251501
    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 2, "EBAAFDHEPLO": uid}, "SummonPetScRsp")
    check("a blind-box pet is summoned by its unique id", rsp.get("PLKBLNMOOPH", {}).get("EBAAFDHEPLO") == uid, rsp)
    check("with a change notify", bool(packets_named(pkts, "PetDataChangeScNotify")))
    srv.restart()
    c = srv.login()
    check("still out after a restart", pet_data(c).get("PLKBLNMOOPH", {}).get("EBAAFDHEPLO") == uid, pet_data(c))
    rsp, _ = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 1002}, "SummonPetScRsp")
    check("then a normal pet by id", rsp.get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1002, rsp)

done()
