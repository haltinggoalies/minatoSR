import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config, packets_named  # noqa: E402


def battle_team(c):
    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")
    return [a["id"] for a in rsp["battle_info"]["battle_avatar_list"]]


with Server() as srv:
    c = srv.login()
    check("nothing saved yet", "No saved configs" in " ".join(c.command("/json")))
    check("bad name refused", "Names are" in " ".join(c.command("/json export ../x")))
    check("export", "configs/full.json" in " ".join(c.command("/json export full")))
    check("no overwrite without force", "exists" in " ".join(c.command("/json export full")))
    check("force overwrites", "saved as" in " ".join(c.command("/json export full force")))
    small = fixture_config(avatars=[1310, 1415, 8010])
    srv.write_json("configs/small.json", small)
    with open(srv.path("configs/broken.json"), "w") as f:
        f.write("{")
    lines = c.command("/json list")
    check("list is sorted", lines and lines[0].splitlines() == ["1. broken", "2. full", "3. small"], lines)
    with open(srv.path("config.json"), encoding="utf-8") as f:
        before = f.read()
    check("a broken config is refused", "not a valid config" in " ".join(c.command("/json load broken")))
    with open(srv.path("config.json"), encoding="utf-8") as f:
        check("and config.json is untouched", f.read() == before)
    lines = c.command("/json load 3")
    check("load by number", "Loaded configs/small.json" in " ".join(lines), lines)
    check("config.json is now small.json", srv.read_json("config.json") == small)
    check("the old one is backed up", any(n.endswith("-before-json-load.json") for n in os.listdir(srv.path("config-backups"))))
    check("avatars are resynced", packets_named(c.last_packets, "PlayerSyncScNotify"))
    team = battle_team(c)
    check("battles use the loaded config", team and set(team) <= {1310, 1415, 8010}, team)
    c.command("/json load full")
    check("load by name", len(srv.read_json("config.json")["avatar_config"]) == len(fixture_config()["avatar_config"]))

done()
