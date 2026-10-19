import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config, packets_named  # noqa: E402


def changed(c):
    notes = packets_named(c.last_packets, "AvatarPathChangedNotify")
    return notes[0].msg().get("cur_multi_path_avatar_type") if notes else None


with Server() as srv:
    c = srv.login()
    check("bad gender refused", "/hero gender" in " ".join(c.command("/hero gender 3")))
    check("bad path refused", "/hero type" in " ".join(c.command("/hero type 9000")))
    c.command("/hero gender 1")
    check("gender 1 picks the male Trailblazer of the same path", changed(c) == 8009, changed(c))
    rsp, _ = c.call("GetBasicInfoCsReq", {}, "GetBasicInfoScRsp")
    check("basic info says male", rsp.get("gender") == 1, rsp)
    c.command("/hero type 8004")
    check("type keeps the gender", changed(c) == 8003, changed(c))
    check("lineup is resent", packets_named(c.last_packets, "SyncLineupNotify"))

no_8004 = [a for a in range(8001, 8011) if a != 8004] + [1310]
with Server(config=fixture_config(avatars=no_8004)) as srv:
    c = srv.login()
    c.command("/hero gender 1")
    c.command("/hero type 8003")
    check("now male Preservation", changed(c) == 8003, changed(c))
    lines = c.command("/hero gender 2")
    check("a Trailblazer config.json lacks is refused", "config.json has no 8004" in " ".join(lines), lines)

done()
