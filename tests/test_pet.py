import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def pet_data(c):
    rsp, _ = c.call("GetPetDataCsReq", {}, "GetPetDataScRsp")
    return rsp


with Server() as srv:
    c = srv.login()
    rsp = pet_data(c)
    check("all five pets unlocked", rsp.get("HCAKDJMKDJP") == [1001, 1002, 1003, 1004, 1005], rsp)
    check("no pet out", "PLKBLNMOOPH" not in rsp, rsp)

    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 1003}, "SummonPetScRsp")
    names = [p.name for p in pkts]
    check("change notify before the reply", "PetDataChangeScNotify" in names
          and names.index("PetDataChangeScNotify") < names.index("SummonPetScRsp"), names)
    if packets_named(pkts, "PetDataChangeScNotify"):
        note = packets_named(pkts, "PetDataChangeScNotify")[0].msg()
        change = note.get("DGNGMJMPFGK", [{}])[0].get("GJALNEHICDE", {})
        check("notify names pet 1003", change.get("ODNGMIJLKKA") == 1003 and change.get("LLGIIPALELD") == 1, note)
    cur = rsp.get("PLKBLNMOOPH", {})
    check("reply: pet 1003, kind echoed", cur.get("ODNGMIJLKKA") == 1003 and cur.get("LLGIIPALELD") == 1
          and rsp.get("retcode", 0) == 0, rsp)

    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 9999}, "SummonPetScRsp")
    check("unknown pet: current one kept, no notify", rsp.get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1003
          and not packets_named(pkts, "PetDataChangeScNotify"), rsp)
    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 3, "EBAAFDHEPLO": 123456789}, "SummonPetScRsp")
    check("blind-box pet: current one kept", rsp.get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1003
          and not packets_named(pkts, "PetDataChangeScNotify"), rsp)
    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 1003}, "SummonPetScRsp")
    check("same pet again: no notify", not packets_named(pkts, "PetDataChangeScNotify"), [p.name for p in pkts])
    check("saved in profile.json", saved(srv).get("pet") == 1003)

    srv.restart()
    c = srv.login()
    check("pet survives a restart", pet_data(c).get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1003)

    rsp, _ = c.call("RecallPetCsReq", {}, "RecallPetScRsp")
    check("recall", rsp.get("retcode", 0) == 0 and "PLKBLNMOOPH" not in rsp, rsp)
    check("no pet out after recall", "PLKBLNMOOPH" not in pet_data(c) and saved(srv).get("pet") == 0)

    _, pkts = c.call("BlindBoxGetDataCsReq", {}, "BlindBoxGetDataScRsp")
    check("BlindBoxGetDataCsReq answered", bool(packets_named(pkts, "BlindBoxGetDataScRsp")))
    # CapySR's finding, seen in the 4.6.52 client's log too: an empty reply makes PetMarbleModule throw at login.
    _, pkts = c.call("PetMarbleGetDataCsReq", {})
    check("PetMarbleGetDataCsReq left unanswered", not packets_named(pkts, "PetMarbleGetDataScRsp"), [p.name for p in pkts])
    rsp, _ = c.call("GetBagCsReq", {}, "GetBagScRsp")
    # The pet tab takes every pet from PetModule; a pet item in the bag became a PetItemData it cannot sort.
    pet_items = sorted(m.get("tid") for m in rsp.get("material_list", []) if 251000 <= m.get("tid", 0) < 252000)
    check("no pet item in the bag", pet_items == [], pet_items)

# A hand-edited profile.json with a pet that does not exist means no pet out.
with Server(files={"profile.json": '{"pet": 9999}'}) as srv:
    c = srv.login()
    rsp = pet_data(c)
    check("unknown saved pet: no pet out", "PLKBLNMOOPH" not in rsp and rsp.get("retcode", 0) == 0, rsp)
done()
