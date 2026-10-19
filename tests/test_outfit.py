"""The Trailblazer's outfit (SetPlayerOutfit) is kept in profile.json and sent back in GetAvatarData after a restart.
The client sends PlayerOutfitBase outfit ids (1001 = the hat of item 227001), not item ids."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

OUTFIT = [1016, 2000, 3001, 4001]  # items 227016, 229001, 227015 are in the bag; 2000 is a default (no item)


def worn(c):
    rsp, _ = c.call("GetAvatarDataCsReq", {"is_get_all": True}, "GetAvatarDataScRsp")
    return rsp.get("player_outfit_data", {}).get("EAKOLIJOEPA", [])


def put_on(c, ids):
    body = {"player_outfit_data": {"EAKOLIJOEPA": ids}} if ids is not None else {}
    _, pkts = c.call("SetPlayerOutfitCsReq", body, "SetPlayerOutfitScRsp")
    sync = packets_named(pkts, "PlayerSyncScNotify")
    return sync[0].msg().get("player_outfit_data", {}).get("EAKOLIJOEPA", []) if sync else None


with Server() as srv:
    c = srv.login()
    check("no outfit before one is picked", worn(c) == [])
    check("the pick is synced", put_on(c, OUTFIT) == OUTFIT)
    check("and saved", srv.read_json("profile.json").get("outfit") == OUTFIT, srv.read_json("profile.json").get("outfit"))
    srv.restart()
    c = srv.login()
    check("the outfit survives a restart", worn(c) == OUTFIT, worn(c))
    check("an outfit nobody owns is left out", put_on(c, [999, 1017, 1016]) == [1016])  # 1017 is item 227017, not in the bag
    check("taking it off saves nothing worn", put_on(c, None) == [] and srv.read_json("profile.json").get("outfit") == [])

with Server(files={"profile.json": '{"outfit": [227015, 4001]}'}) as srv:
    check("a hand-edited unknown outfit id is not sent", worn(srv.login()) == [4001])

done()
