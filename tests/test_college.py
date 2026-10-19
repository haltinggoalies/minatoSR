import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def finished(c):
    rsp, _ = c.call("GetBattleCollegeDataCsReq", {}, "GetBattleCollegeDataScRsp")
    return rsp.get("finished_college_id_list", [])


def start(c, room):
    rsp, _ = c.call("StartBattleCollegeCsReq", {"id": room}, "StartBattleCollegeScRsp")
    return rsp


def result(c, end_status, stage_id):
    _, pkts = c.call("PVEBattleResultCsReq", {"end_status": end_status, "stage_id": stage_id}, "PVEBattleResultScRsp")
    return pkts


def notified(pkts):
    return bool(packets_named(pkts, "SyncBattleCollegeDataChangeScNotify"))


with Server() as srv:
    c = srv.login()
    check("nothing passed yet", finished(c) == [])

    rsp = start(c, 3)
    info = rsp.get("battle_info", {})
    waves = [[m.get("monster_id") for m in w.get("monster_list", [])] for w in info.get("monster_wave_list", [])]
    check("room 3 fights stage 400103", rsp.get("retcode", 0) == 0 and rsp.get("id") == 3 and info.get("stage_id") == 400103, rsp)
    check("with that stage's waves", waves == [[102202017], [102202015, 102202015, 102202015]], waves)
    check("and the current team", len(info.get("battle_avatar_list", [])) > 0, info.get("battle_avatar_list"))

    pkts = result(c, 1, 400103)
    names = [p.name for p in pkts]
    check("win: change notify before the battle result", notified(pkts)
          and names.index("SyncBattleCollegeDataChangeScNotify") < names.index("PVEBattleResultScRsp"), names)
    if notified(pkts):
        note = packets_named(pkts, "SyncBattleCollegeDataChangeScNotify")[0].msg()
        check("notify lists room 3", note.get("finished_college_id_list") == [3], note)
    check("saved in profile.json", saved(srv).get("college_finished") == [3])

    start(c, 3)
    check("second win of the same room: no notify", not notified(result(c, 1, 400103)))
    start(c, 5)
    check("a loss: no notify", not notified(result(c, 2, 400114)) and finished(c) == [3])
    start(c, 1)
    check("a result for another stage: not the room's", not notified(result(c, 1, 999)) and finished(c) == [3])

    # Room 1 fights 400101, the fixture's own stage: a later cocoon win must not pass it.
    start(c, 1)
    result(c, 2, 400101)
    c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    check("an ordinary battle after a room is not the room", not notified(result(c, 1, 400101)) and finished(c) == [3])

    rsp = start(c, 4)
    check("unknown room: refused, no battle", rsp.get("retcode", 0) != 0 and "battle_info" not in rsp, rsp)

    c.command("/calyx lineup 1310")
    rsp = start(c, 2)
    ids = [a.get("id") for a in rsp.get("battle_info", {}).get("battle_avatar_list", [])]
    check("/calyx lineup is the team", ids == [1310], ids)
    result(c, 2, 400102)
    c.command("/calyx off")

    srv.restart()
    c = srv.login()
    check("passed rooms survive a restart", finished(c) == [3])
done()
