"""The party's last overworld spot (entry, floor, position) is kept in profile.json; logging in again starts there
instead of the fixed login scene. Challenge arenas are never kept."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402

LOGIN_ENTRY = 2050301
EXPRESS = 1000001
SPOT = {"x": 1500, "y": 120, "z": -2500}
MOC_LINEUP = [{"id": i, "avatar_type": 3} for i in (1310, 1415, 1501, 1303)]


def login_scene(c):
    rsp, _ = c.call("GetCurSceneInfoCsReq", {}, "GetCurSceneInfoScRsp")
    return rsp["scene"]


def party_pos(scene):
    for group in scene.get("entity_group_list", []):
        for entity in group.get("entity_list", []):
            if "actor" in entity:
                return entity.get("motion", {}).get("pos", {})
    return None


def walk(c, pos):
    c.call("SceneEntityMoveCsReq", {"entity_motion_list": [{"entity_id": 101310, "motion": {"pos": pos}}]}, "SceneEntityMoveScRsp")


with Server() as srv:
    c = srv.login()
    check("first login: the usual scene", login_scene(c).get("entry_id") == LOGIN_ENTRY)
    c.command("/scene change 1000001")
    walk(c, SPOT)
    c = srv.login()  # the old connection closes: the spot is written then
    scene = login_scene(c)
    check("relog starts on the Express", scene.get("entry_id") == EXPRESS and scene.get("plane_id") == 10000, scene.get("entry_id"))
    check("where the party last stood", party_pos(scene) == SPOT, party_pos(scene))
    saved = srv.read_json("profile.json").get("location") or {}
    check("saved in profile.json", saved.get("entry_id") == EXPRESS and saved.get("x") == 1500, saved)
    srv.restart()
    c = srv.login()
    scene = login_scene(c)
    check("and after a restart", scene.get("entry_id") == EXPRESS and party_pos(scene) == SPOT, (scene.get("entry_id"), party_pos(scene)))

    print("challenges")
    c.call("StartChallengeCsReq", {"challenge_id": 5612, "avatar_lineup_first": MOC_LINEUP, "avatar_lineup_second": MOC_LINEUP},
           "StartChallengeScRsp")
    walk(c, {"x": 9000, "y": 0, "z": 9000})
    c = srv.login()
    scene = login_scene(c)
    check("a MoC arena is never the saved spot", scene.get("entry_id") == EXPRESS and party_pos(scene) == SPOT,
          (scene.get("entry_id"), party_pos(scene)))

broken = '{"location": {"plane_id": 1, "floor_id": 2, "entry_id": 42, "x": 0, "y": 0, "z": 0, "rot_y": 0}}'
with Server(files={"profile.json": broken}) as srv:
    check("a spot that is not in MapEntrance falls back to the usual scene", login_scene(srv.login()).get("entry_id") == LOGIN_ENTRY)

done()
