"""Classic MoC/PF/AS records: real stars on the settle screen, the best full run kept in challenge.json and shown by
GetChallenge / GetChallengeGroupStatistics; floors without a record still show fully cleared."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

WIN, LOSE = 1, 2
TEAM1, TEAM2 = [1310, 1415, 1501, 1303], [1224, 8005]
PF_BUFFS, AS_BUFFS = (3031354, 3031366), (3111092, 3111058)


def lineup(ids):
    return [{"id": i, "avatar_type": 3} for i in ids]


def fight(c, rounds, status=WIN, score=0, as_score=0, downed=0):
    """Ends the battle of the node in progress; returns every packet the server sent for it."""
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    stt = {"round_cnt": rounds}
    if score:
        stt["challenge_score"] = score
    if as_score:
        stt["battle_target_info"] = [{"key": 1, "value": {"battle_target_list": [{"id": 90005, "progress": as_score}]}}]
    if downed:
        stt["battle_avatar_list"] = [{"id": TEAM1[i], "die_times": 1} for i in range(downed)]
    body = {"end_status": status, "stage_id": info.get("battle_info", {}).get("stage_id", 0), "stt": stt}
    _, pkts = c.call("PVEBattleResultCsReq", body, "PVEBattleResultScRsp")
    return pkts


def run(c, cid, node1, node2, buffs=None):
    """A full run from node 1 (node1/node2 are fight() arguments); returns the packets of the last fight."""
    body = {"challenge_id": cid, "avatar_lineup_first": lineup(TEAM1), "avatar_lineup_second": lineup(TEAM2)}
    if buffs:
        body["stage_info"] = {"story_info" if cid < 30000 else "boss_info": {"buff_one": buffs[0], "buff_two": buffs[1]}}
    rsp, _ = c.call("StartChallengeCsReq", body, "StartChallengeScRsp")
    check(f"{cid} starts", rsp.get("retcode", 0) == 0, rsp)
    fight(c, **node1)
    if cid > 30000:
        c.call("EnterChallengeNextPhaseCsReq", {}, "EnterChallengeNextPhaseScRsp")
    pkts = fight(c, **node2)
    c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")
    return pkts


def partial(c, cid, rounds):
    rsp, _ = c.call("StartPartialChallengeCsReq", {"challenge_id": cid, "is_first_half": True}, "StartPartialChallengeScRsp")
    check(f"{cid} single node starts", rsp.get("retcode", 0) == 0, rsp)
    pkts = fight(c, rounds)
    c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")
    return pkts


def star(pkts, name="ChallengeSettleNotify"):
    found = packets_named(pkts, name)
    return found[-1].msg().get("star", 0) if found else None


def challenges(c):
    rsp, _ = c.call("GetChallengeCsReq", {}, "GetChallengeScRsp")
    return {ch["challenge_id"]: ch for ch in rsp.get("challenge_list", [])}


def stats(c, group_id, kind):
    rsp, _ = c.call("GetChallengeGroupStatisticsCsReq", {"group_id": group_id}, "GetChallengeGroupStatisticsScRsp")
    return rsp.get(kind, {}).get("PPBHLLOJNEK")


def teams(record):
    return [[a["id"] for a in lst.get("avatar_list", [])] for lst in record.get("lineup_list", [])] if record else None


def score(ch):
    return ch.get("star", 0), ch.get("score_id", 0), ch.get("score_two", 0)


def saved_ids(srv):
    if not os.path.exists(srv.path("challenge.json")):
        return []
    return sorted(r["id"] for r in srv.read_json("challenge.json").get("classic", []))


with Server() as srv:
    c = srv.login()

    print("no records yet")
    ch = challenges(c)
    check("unplayed MoC 5612 shows 3 stars", score(ch[5612]) == (7, 0, 0), ch[5612])
    check("unplayed PF 20284 shows the fake 40000 scores", score(ch[20284]) == (7, 40000, 40000), ch[20284])
    check("unplayed AS 30234 shows 3 stars", score(ch[30234]) == (7, 0, 0), ch[30234])
    rsp, _ = c.call("GetChallengeGroupStatisticsCsReq", {"group_id": 1037}, "GetChallengeGroupStatisticsScRsp")
    check("group without a record has no statistics",
          rsp.get("group_id") == 1037 and not {"challenge_default", "challenge_story", "challenge_boss"} & rsp.keys(), rsp)

    print("MoC 5612 (30-cycle countdown; targets 251 >=10 left, 252 >=20 left, 253 nobody downed)")
    pkts = run(c, 5612, {"rounds": 8}, {"rounds": 8})
    check("run A (16 cycles) settles with stars 251 + 253", star(pkts) == 0b101, star(pkts))
    check("run A is the record", challenges(c)[5612].get("star") == 0b101)
    rec = stats(c, 1037, "challenge_default")
    check("group statistics show run A", rec and (rec.get("level"), rec.get("EEJCPNAEKLJ"), rec.get("round_count")) == (12, 2, 16), rec)
    check("group statistics show both node teams", teams(rec) == [TEAM1, TEAM2], teams(rec))

    pkts = run(c, 5612, {"rounds": 10, "downed": 1}, {"rounds": 10})
    check("run B (20 cycles, one downed) settles with 251 only", star(pkts) == 0b001, star(pkts))
    check("worse run B does not replace the record", challenges(c)[5612].get("star") == 0b101)
    rec = stats(c, 1037, "challenge_default")
    check("record still 16 cycles", rec and rec.get("round_count") == 16, rec)

    pkts = run(c, 5612, {"rounds": 6}, {"rounds": 6})
    check("run C (12 cycles) settles with 251 + 253", star(pkts) == 0b101, star(pkts))
    rec = stats(c, 1037, "challenge_default")
    check("as many stars in fewer cycles replaces the record", rec and rec.get("round_count") == 12, rec)

    print("single node runs")
    pkts = partial(c, 5612, 1)
    check("a single node still settles with every star", star(pkts) == 7, star(pkts))
    rec = stats(c, 1037, "challenge_default")
    check("a 1-cycle single node is not recorded", rec and rec.get("round_count") == 12, rec)
    partial(c, 5611, 1)
    check("5611 played only as a single node keeps the fake stars", challenges(c)[5611].get("star") == 7)
    check("challenge.json holds only the full run", saved_ids(srv) == [5612], saved_ids(srv))

    print("PF 20284 (targets 2001-2003: 40000 / 50000 / 60000 total)")
    pkts = run(c, 20284, {"rounds": 4, "score": 30000}, {"rounds": 4, "score": 40000 + 25000}, PF_BUFFS)
    check("55000 points settles with 2001 + 2002", star(pkts) == 0b011, star(pkts))
    check("GetChallenge shows the record's stars and node scores", score(challenges(c)[20284]) == (0b011, 30000, 25000))
    rec = stats(c, 2028, "challenge_story")
    check("story statistics: floor, stars, total score, buffs",
          rec and (rec.get("level"), rec.get("EEJCPNAEKLJ"), rec.get("score_id"), rec.get("buff_one"), rec.get("buff_two"))
          == (4, 2, 55000, *PF_BUFFS), rec)
    run(c, 20284, {"rounds": 4, "score": 30000}, {"rounds": 4, "score": 40000 + 20001}, PF_BUFFS)
    check("as many stars with a lower score keeps the record", score(challenges(c)[20284]) == (0b011, 30000, 25000))
    pkts = run(c, 20283, {"rounds": 4, "score": 10000}, {"rounds": 4, "score": 40000 + 10000})
    check("a run without stars settles with none", star(pkts) == 0, star(pkts))
    check("and is not recorded: 20283 keeps the fake values", score(challenges(c)[20283]) == (7, 40000, 40000))

    print("AS 30234 (targets 3001-3003: 4000 / 5200 / 6600 total)")
    pkts = run(c, 30234, {"rounds": 3, "as_score": 3000}, {"rounds": 3, "as_score": 2500}, AS_BUFFS)
    check("boss phase settle shows the real stars", star(pkts, "ChallengeBossPhaseSettleNotify") == 0b011,
          star(pkts, "ChallengeBossPhaseSettleNotify"))
    check("challenge settle shows the real stars", star(pkts) == 0b011, star(pkts))
    check("GetChallenge shows the AS record", score(challenges(c)[30234]) == (0b011, 3000, 2500))
    rec = stats(c, 3023, "challenge_boss")
    check("boss statistics: floor, stars, total score, buffs",
          rec and (rec.get("level"), rec.get("EEJCPNAEKLJ"), rec.get("score_id"), rec.get("buff_one"), rec.get("buff_two"))
          == (4, 2, 5500, *AS_BUFFS), rec)

    print("after a restart")
    check("challenge.json holds the three records", saved_ids(srv) == [5612, 20284, 30234], saved_ids(srv))
    srv.restart()
    c = srv.login()
    ch = challenges(c)
    check("5612 record survives", ch[5612].get("star") == 0b101, ch[5612])
    check("20284 record survives", score(ch[20284]) == (0b011, 30000, 25000), ch[20284])
    check("30234 record survives", score(ch[30234]) == (0b011, 3000, 2500), ch[30234])
    check("unplayed 5601 still shows 3 stars", ch[5601].get("star") == 7, ch[5601])
    rec = stats(c, 1037, "challenge_default")
    check("group statistics survive", rec and rec.get("round_count") == 12 and teams(rec) == [TEAM1, TEAM2], rec)

    print("a broken challenge.json")
    srv.stop()
    with open(srv.path("challenge.json"), "w", encoding="utf-8") as f:
        f.write("{ broken")
    srv.start()
    c = srv.login()
    check("every floor shows 3 stars again", challenges(c)[5612].get("star") == 7)
    check("the broken file is kept as challenge.json.bad", os.path.exists(srv.path("challenge.json.bad")))

done()
