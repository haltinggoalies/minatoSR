"""AS Dominance of Oblivion (group 3021): node 1 of every floor, and of its Starward floor 30215 (nodes 1-2 come from
30214), loads node 1's own arena (entry 3000205, group 6), not node 2's (3013601, group 7)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402

NODE1, NODE2 = 3000205, 3013601
TEAM1, TEAM2 = [1310, 1415, 1501, 1303], [1224, 8005]
BUFFS = (3111092, 3111058)


def lineup(ids):
    return [{"id": i, "avatar_type": 3} for i in ids]


def win(c):
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    body = {"end_status": 1, "stage_id": info.get("battle_info", {}).get("stage_id", 0), "stt": {"round_cnt": 1}}
    c.call("PVEBattleResultCsReq", body, "PVEBattleResultScRsp")


def next_entry(c):
    rsp, _ = c.call("EnterChallengeNextPhaseCsReq", {}, "EnterChallengeNextPhaseScRsp")
    return (rsp or {}).get("scene", {}).get("entry_id")


with Server() as srv:
    c = srv.login()
    for cid in (30211, 30214):
        body = {"challenge_id": cid, "avatar_lineup_first": lineup(TEAM1), "avatar_lineup_second": lineup(TEAM2),
                "stage_info": {"boss_info": {"buff_one": BUFFS[0], "buff_two": BUFFS[1]}}}
        rsp, _ = c.call("StartChallengeCsReq", body, "StartChallengeScRsp")
        check(f"{cid} starts", rsp.get("retcode", 0) == 0, rsp)
        entry = rsp.get("scene", {}).get("entry_id")
        check(f"{cid} node 1 is node 1's arena", entry == NODE1, entry)
        win(c)
        entry = next_entry(c)
        check(f"{cid} node 2 is node 2's arena", entry == NODE2, entry)
        c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")

    rsp, _ = c.call("StartChallengeTierceCsReq", {"challenge_id": 30215}, "StartChallengeTierceScRsp")
    check("Starward 30215 starts", rsp.get("retcode", 0) == 0, rsp)
    entry = rsp.get("scene", {}).get("entry_id")
    check("Starward 30215 node 1 is node 1's arena", entry == NODE1, entry)
    c.call("LeaveChallengeTierceCsReq", {}, "LeaveChallengeTierceScRsp")

done()
