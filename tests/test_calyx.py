import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import FIXTURE_AVATARS, Server, check, done, fixture_config  # noqa: E402


def cocoon(c):
    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")
    return rsp["battle_info"]


def team(battle):
    return [a["id"] for a in battle.get("battle_avatar_list", [])]


def hps(battle):
    return [[m.get("max_hp", 0) for m in w.get("monster_list", [])] for w in battle.get("monster_wave_list", [])]


def reload_config(srv, c, cfg):
    srv.write_json("config.json", cfg)
    time.sleep(1.2)  # the server looks at config.json at most once a second, on the next packet
    c.call("GetCurSceneInfoCsReq", {}, "GetCurSceneInfoScRsp")


with Server() as srv:
    c = srv.login()
    default_team = team(cocoon(c))
    check("a battle starts with the preset team", len(default_team) > 0, default_team)

    print("/calyx lineup")
    check("bad id is refused", "config.json" in " ".join(c.command("/calyx lineup 99999")))
    check("five avatars are refused", "at most 4" in " ".join(c.command("/calyx lineup 1310 1415 1501 1303 1001")))
    check("a duplicate base id is refused", "twice" in " ".join(c.command("/calyx lineup 1001 1224")))
    check("mixed case, double spaces and a trailing NUL are fine", "Calyx team set" in " ".join(c.command("/CALYX  LineUp  1310\x00")))
    lines = c.command("/calyx lineup 1501 8001")
    check("lineup accepted", "Calyx team set" in " ".join(lines), lines)
    b = cocoon(c)
    check("battle uses the Calyx team, 8001 = current Trailblazer path", team(b)[0] == 1501 and 8001 <= team(b)[1] <= 8010, team(b))

    print("/calyx modify")
    check("wave out of range", "no monster" in " ".join(c.command("/calyx modify 3 1 100")))
    check("hp 0 refused", "between 1" in " ".join(c.command("/calyx modify 1 1 0")))
    lines = c.command("/calyx modify 1 2 123456")
    check("hp set", "123456" in " ".join(lines), lines)
    b = cocoon(c)
    check("monster 2 of wave 1 has the HP", hps(b)[0][1] == 123456 and hps(b)[0][0] == 0, hps(b))
    status = " ".join(c.command("/calyx"))
    check("status lists team and HP", "1501" in status and "123456" in status, status)

    print("lifetimes")
    c = srv.login()
    b = cocoon(c)
    check("a new login drops the Calyx team", team(b) == default_team, team(b))
    check("but keeps HP changes", hps(b)[0][1] == 123456, hps(b))
    c.command("/calyx lineup 1310 1415")
    cfg = fixture_config(avatars=[a for a in FIXTURE_AVATARS if a != 1415])
    cfg["battle_config"]["monster_wave"] = [[801201025, 801201025, 801201025]]
    reload_config(srv, c, cfg)
    b = cocoon(c)
    check("a config.json reload clears HP changes", 123456 not in sum(hps(b), []), hps(b))
    check("and drops Calyx avatars config.json no longer has", team(b) == [1310], team(b))
    c.command("/calyx reset")
    check("/calyx reset clears the team", team(cocoon(c)) != [1310])

done()
