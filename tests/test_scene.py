import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

with Server() as srv:
    c = srv.login()
    check("before any scene", "No scene" in " ".join(c.command("/scene cur")))
    c.call("GetCurSceneInfoCsReq", {}, "GetCurSceneInfoScRsp")
    lines = c.command("/scene cur")
    check("cur shows the login scene", "entry 2050301" in " ".join(lines), lines)
    c.call("SceneEntityMoveCsReq", {"entity_motion_list": [{"entity_id": 101310, "motion": {"pos": {"x": 1500, "y": 0, "z": -2500}}}]},
           "SceneEntityMoveScRsp")
    lines = c.command("/scene cur")
    check("cur shows the last position in metres", "1.5 0.0 -2.5" in " ".join(lines), lines)
    lines = c.command("/scene group")
    check("group lists groups with distances", lines and lines[0].startswith("Group ") and " m" in lines[0], lines)
    check("unknown entry refused", "not in MapEntrance" in " ".join(c.command("/scene change 42")))
    c.command("/scene change 1000001")
    enter = packets_named(c.last_packets, "EnterSceneByServerScNotify")
    scene = enter[0].msg()["scene"] if enter else {}
    check("change enters the entry on its own plane", scene.get("entry_id") == 1000001 and scene.get("plane_id") == 10000, scene.get("plane_id"))
    check("with the entry's props", sum(len(g.get("entity_list", [])) for g in scene.get("entity_group_list", [])) > 5)
    c.command("/scene reload")
    enter = packets_named(c.last_packets, "EnterSceneByServerScNotify")
    check("reload enters the same entry", enter and enter[0].msg()["scene"].get("entry_id") == 1000001)
    check("cur follows", "entry 1000001" in " ".join(c.command("/scene cur")))

done()
