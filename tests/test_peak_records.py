"""Anomaly Arbitration records: targets judged from the cycles and downed characters, the best clear of each knight and
boss difficulty kept in challenge.json and shown by GetChallengePeakData, the group update after each clear and /peak;
anything without a record still shows fully cleared. Also the reward button (TakeChallengePeakReward)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

WIN, LOSE = 1, 2
GROUP, KNIGHT, BOSS = 11, 1101, 1104
KNIGHT_TEAM, BOSS_TEAM, BOSS_BUFF = [1310, 1415, 1501, 1303], [1224, 8005, 1001], 3033074


def fight(c, rounds, status=WIN, downed=0):
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    stt = {"round_cnt": rounds}
    if downed:
        stt["battle_avatar_list"] = [{"id": KNIGHT_TEAM[i], "die_times": 1} for i in range(downed)]
    body = {"end_status": status, "stage_id": info.get("battle_info", {}).get("stage_id", 0), "stt": stt}
    _, pkts = c.call("PVEBattleResultCsReq", body, "PVEBattleResultScRsp")
    return pkts


def knight(c, rounds, status=WIN, downed=0):
    """A knight fight with the team set in the menu; returns (settle notify, group update or None, packet names)."""
    c.call("SetChallengePeakMobLineupAvatarCsReq",
           {"peak_group_id": GROUP, "lineup_list": [{"peak_id": KNIGHT, "peak_avatar_id_list": KNIGHT_TEAM}]},
           "SetChallengePeakMobLineupAvatarScRsp")
    rsp, _ = c.call("StartChallengePeakCsReq", {"peak_id": KNIGHT}, "StartChallengePeakScRsp")
    check("knight starts", rsp.get("retcode", 0) == 0, rsp)
    return result(c, fight(c, rounds, status, downed))


def boss(c, rounds, hard):
    c.call("SetChallengePeakBossHardModeCsReq", {"peak_group_id": GROUP, "is_hard_mode": hard}, "SetChallengePeakBossHardModeScRsp")
    rsp, _ = c.call("StartChallengePeakCsReq", {"peak_id": BOSS, "boss_buff_id": BOSS_BUFF, "peak_avatar_id_list": BOSS_TEAM},
                    "StartChallengePeakScRsp")
    check("boss starts", rsp.get("retcode", 0) == 0, rsp)
    return result(c, fight(c, rounds))


def result(c, pkts):
    c.call("LeaveChallengePeakCsReq", {}, "LeaveChallengePeakScRsp")
    settle = packets_named(pkts, "ChallengePeakSettleScNotify")
    update = packets_named(pkts, "ChallengePeakGroupDataUpdateScNotify")
    return (settle[0].msg() if settle else {}, update[0].msg().get("challenge_peak_group") if update else None,
            [p.name for p in pkts])


def groups(c):
    rsp, _ = c.call("GetChallengePeakDataCsReq", {}, "GetChallengePeakDataScRsp")
    return {g["peak_group_id"]: g for g in rsp.get("challenge_peak_groups", [])}


def peak(group, peak_id):
    return next((p for p in group.get("peaks", []) if p["peak_id"] == peak_id), None)


def knight_view(group):
    p = peak(group or {}, KNIGHT) or {}
    return p.get("has_passed"), p.get("cycles_used", 0), p.get("finished_target_list", []), p.get("peak_avatar_id_list", [])


def clearance(mode):
    mode = mode or {}
    return mode.get("has_passed"), mode.get("best_cycle_count", 0), mode.get("buff_id", 0), mode.get("peak_avatar_id_list", [])


def is_fake(group):
    b = group.get("peak_boss", {})
    return (group.get("obtained_stars") == 9 and "peaks" not in group and "easy_mode" not in b
            and b.get("finished_target_list") == [3003, 3004, 3005] and b.get("hard_mode_has_passed") is True
            and clearance(b.get("hard_mode"))[0] is True and b["hard_mode"].get("peak_avatar_id_list") == [1508])


with Server() as srv:
    c = srv.login()

    print("no records yet")
    g = groups(c)
    check("every season shows as fully cleared", all(is_fake(x) for x in g.values()), g.get(GROUP))

    print(f"knight {KNIGHT} (targets 3001 <= 4 cycles, 3002 <= 2 cycles, 3000 nobody downed)")
    settle, update, names = knight(c, 3, downed=1)
    check("3 cycles with one downed meets 3001 only",
          (settle.get("is_win"), settle.get("finished_target_list", []), settle.get("cycles_used")) == (True, [3001], 3), settle)
    check("the group update follows the settle", update is not None and names.index("ChallengePeakGroupDataUpdateScNotify")
          > names.index("ChallengePeakSettleScNotify"), names)
    check("update: the knight's record, still 9 stars", update and update.get("obtained_stars") == 9
          and knight_view(update) == (True, 3, [3001], KNIGHT_TEAM), update)
    x = groups(c)[GROUP]
    check("GetChallengePeakData shows the record", knight_view(x) == (True, 3, [3001], KNIGHT_TEAM), knight_view(x))
    check("obtained stars never drop below 3 a knight", x.get("obtained_stars") == 9, x.get("obtained_stars"))
    best = next((p for p in x.get("PAPDCCKPEPK", {}).get("peaks", []) if p["peak_id"] == KNIGHT), {})
    check("and the best-record list", (best.get("cycles_used"), best.get("finished_target_list"),
                                       [a["avatar_id"] for a in best.get("avatar_list", [])]) == (3, [3001], KNIGHT_TEAM), best)
    other = peak(x, 1102) or {}
    check("an unplayed knight of the group shows fully cleared",
          (other.get("has_passed"), other.get("finished_target_list")) == (True, [3001, 3002, 3000]), other)
    check("a season without records is unchanged", is_fake(groups(c)[10]))

    settle, _, _ = knight(c, 5)
    check("a clean 5-cycle clear meets 3000 only", settle.get("finished_target_list", []) == [3000], settle)
    check("as many targets in more cycles keeps the record", knight_view(groups(c)[GROUP])[1:3] == (3, [3001]))
    settle, _, names = knight(c, 1, LOSE)
    check("a lost fight sends no group update", settle.get("is_win") is not True
          and "ChallengePeakGroupDataUpdateScNotify" not in names, names)
    settle, _, _ = knight(c, 2, downed=1)
    check("2 cycles with one downed meets 3001 + 3002", settle.get("finished_target_list", []) == [3001, 3002], settle)
    check("more targets replace the record", knight_view(groups(c)[GROUP])[1:3] == (2, [3001, 3002]))
    settle, _, _ = knight(c, 2)
    check("the same clear with nobody downed also meets 3000", settle.get("finished_target_list", []) == [3001, 3002, 3000], settle)
    knight(c, 1)
    x = groups(c)[GROUP]
    check("as many targets in fewer cycles replace it", knight_view(x)[1:3] == (1, [3001, 3002, 3000]), knight_view(x))

    print("/peak sends the season with its records")
    c.command("/peak 11")
    pushed = packets_named(c.last_packets, "ChallengePeakGroupDataUpdateScNotify")
    group = pushed[0].msg().get("challenge_peak_group") if pushed else None
    check("the pushed group update is the whole season", group and group.get("peak_group_id") == GROUP
          and knight_view(group)[1:3] == (1, [3001, 3002, 3000]) and "peak_boss" in group, group)
    c.command("/peak 0")

    print(f"boss {BOSS}: easy (3003 <= 6, 3004 <= 4, 3005 <= 2 cycles), hard (3007 <= 2 cycles)")
    settle, update, _ = boss(c, 3, False)
    check("easy boss in 3 cycles meets 3003 + 3004", (settle.get("finished_target_list"), settle.get("turn_left"))
          == ([3003, 3004], 3), settle)
    b = groups(c)[GROUP]["peak_boss"]
    check("easy record shown", clearance(b.get("easy_mode")) == (True, 3, BOSS_BUFF, BOSS_TEAM), b.get("easy_mode"))
    check("boss targets are the easy record's", b.get("finished_target_list") == [3003, 3004], b)
    check("hard mode without a record stays fake", b["hard_mode"].get("peak_avatar_id_list") == [1508], b["hard_mode"])
    settle, _, _ = boss(c, 2, True)
    check("hard clear keeps its own result screen", settle.get("hard_mode_has_passed") is True
          and "finished_target_list" not in settle, settle)
    boss(c, 4, True)
    b = groups(c)[GROUP]["peak_boss"]
    check("hard record: 2 cycles, not the worse 4", clearance(b.get("hard_mode")) == (True, 2, BOSS_BUFF, BOSS_TEAM), b.get("hard_mode"))
    check("easy record untouched by hard clears", clearance(b.get("easy_mode"))[1] == 3, b.get("easy_mode"))

    print("after a restart")
    saved = srv.read_json("challenge.json") if os.path.exists(srv.path("challenge.json")) else {}
    check("challenge.json holds the knight", [(p["level_id"], p["cycles"], p["targets"]) for p in saved.get("peak", [])]
          == [(KNIGHT, 1, [3001, 3002, 3000])], saved.get("peak"))
    check("and both boss difficulties", sorted((p["level_id"], p["hard"], p["cycles"]) for p in saved.get("peak_boss", []))
          == [(BOSS, False, 3), (BOSS, True, 2)], saved.get("peak_boss"))
    srv.restart()
    c = srv.login()
    x = groups(c)[GROUP]
    check("knight record survives", knight_view(x) == (True, 1, [3001, 3002, 3000], KNIGHT_TEAM), knight_view(x))
    check("boss records survive", (clearance(x["peak_boss"].get("easy_mode"))[1], clearance(x["peak_boss"].get("hard_mode"))[1])
          == (3, 2), x["peak_boss"])
    check("other seasons still fake", is_fake(groups(c)[1]))

    print("reward button")
    try:
        rsp, _ = c.call("TakeChallengePeakRewardCsReq", {"peak_group_id": GROUP, "normal_reward_id_list": [1, 2, 3]},
                        "TakeChallengePeakRewardScRsp")
    except AssertionError as e:
        rsp = None
        print(f"  ({e})")
    check("TakeChallengePeakReward answers the asked ids without items",
          rsp is not None and rsp.get("retcode", 0) == 0 and rsp.get("peak_group_id") == GROUP
          and [r["reward_id"] for r in rsp.get("peak_reward_group_list", [])] == [1, 2, 3]
          and all(not r.get("reward", {}).get("item_list") for r in rsp.get("peak_reward_group_list", [])), rsp)

done()
