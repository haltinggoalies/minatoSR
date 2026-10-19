"""Findings of the whole-branch review (GPT-6 Astra and a fresh reviewer): each check failed before its fix."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Dropped, Server, check, done, fixture_config, packets_named  # noqa: E402

MOC_LINEUP = [{"id": i, "avatar_type": 3} for i in (1310, 1415, 1501, 1303)]


def safe_command(c, text):
    try:
        return c.command(text)
    except Dropped as e:
        return [f"dropped: {e}"]


def cocoon_win(c):
    c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")


def colleges_passed(c):
    rsp, _ = c.call("GetBattleCollegeDataCsReq", {}, "GetBattleCollegeDataScRsp")
    return rsp.get("finished_college_id_list", [])


with Server() as srv:
    print("/hero after the path handler stored id 0")
    c = srv.login()
    c.call("SetAvatarPathCsReq", {}, "SetAvatarPathScRsp")
    lines = safe_command(c, "/hero gender 1")
    check("/hero does not take the server down", any("Trailblazer is now" in l for l in lines), lines)
    srv.restart()  # in case it did

    print("commands that would change the team mid-challenge")
    c = srv.login()
    c.command("/json export cfg")
    c.call("StartChallengeCsReq", {"challenge_id": 5612, "avatar_lineup_first": MOC_LINEUP, "avatar_lineup_second": MOC_LINEUP},
           "StartChallengeScRsp")
    lines = c.command("/hero gender 1")
    check("/hero waits for the challenge to end", "Leave the challenge first" in " ".join(lines)
          and not packets_named(c.last_packets, "SyncLineupNotify"), lines)
    lines = c.command("/json load cfg")
    check("/json load waits for the challenge to end", "Leave the challenge first" in " ".join(lines), lines)
    c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")

    print("/scene change to an entry with nowhere to stand")
    lines = c.command("/scene change 1000201")
    check("an entry without a spawn point is refused", "spawn point" in " ".join(lines)
          and not packets_named(c.last_packets, "EnterSceneByServerScNotify"), lines)

    print("a Battle College room left unfinished")
    c.call("StartBattleCollegeCsReq", {"id": 1}, "StartBattleCollegeScRsp")
    c = srv.login()
    cocoon_win(c)
    check("a Calyx won after relogging does not pass the room", 1 not in colleges_passed(c), colleges_passed(c))
    c.call("StartBattleCollegeCsReq", {"id": 2}, "StartBattleCollegeScRsp")
    cocoon_win(c)
    check("nor a Calyx started instead of the room", 2 not in colleges_passed(c), colleges_passed(c))

    print("/json load backups")
    srv.write_json("configs/small.json", fixture_config(avatars=[1310, 1415, 8010]))
    for name in ("small", "cfg", "small", "cfg"):
        c.command(f"/json load {name}", settle=0.1)
    backups = [n for n in os.listdir(srv.path("config-backups")) if n.endswith("-before-json-load.json")]
    check("four quick loads keep four backups", len(backups) == 4, backups)

with Server() as srv:
    print("an AA knight started after a restart without picking its team")
    c = srv.login()
    team = [1501, 1303, 1224]
    c.call("SetChallengePeakMobLineupAvatarCsReq", {"peak_group_id": 11, "lineup_list": [{"peak_id": 1101, "peak_avatar_id_list": team}]},
           "SetChallengePeakMobLineupAvatarScRsp")
    c.call("StartChallengePeakCsReq", {"peak_id": 1101}, "StartChallengePeakScRsp")
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1, "stage_id": info["battle_info"]["stage_id"], "stt": {"round_cnt": 3}},
           "PVEBattleResultScRsp")
    c.call("LeaveChallengePeakCsReq", {}, "LeaveChallengePeakScRsp")
    srv.restart()
    c = srv.login()
    c.call("StartChallengePeakCsReq", {"peak_id": 1101}, "StartChallengePeakScRsp")
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    used = [a["id"] for a in info["battle_info"].get("battle_avatar_list", [])]
    check("the knight fights with its record's team, the one the menu shows", used == team, used)

done()
