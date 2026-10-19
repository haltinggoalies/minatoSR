"""Team presets: 50 of them, the game's own 9 plus 41 more, each editable, switchable, nameable and saved."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402

COUNT = 50
LAST = COUNT - 1


def presets(c):
    rsp, _ = c.call("GetAllLineupDataCsReq", {}, "GetAllLineupDataScRsp")
    return rsp, {l.get("index", 0): l for l in rsp.get("lineup_list", [])}


def ids(lineup):
    return [a["id"] for a in lineup.get("avatar_list", [])]


def replace(c, index, team):
    body = {"index": index, "lineup_slot_list": [{"id": i, "slot": s} for s, i in enumerate(team)]}
    rsp, _ = c.call("ReplaceLineupCsReq", body, "ReplaceLineupScRsp")
    return rsp.get("retcode", 0)


with Server() as srv:
    c = srv.login()
    rsp, by_index = presets(c)
    check(f"{COUNT} presets", sorted(by_index) == list(range(COUNT)), sorted(by_index))
    check("the game names teams 1-9 itself", all(not by_index[i].get("name") for i in range(9)),
          [by_index[i].get("name") for i in range(9)])
    check("teams 10+ get a name", by_index[9].get("name") == "Team 10" and by_index[LAST].get("name") == f"Team {COUNT}",
          (by_index[9].get("name"), by_index[LAST].get("name")))

    check(f"team {COUNT} takes members", replace(c, LAST, [1415, 1501]) == 0)
    check(f"past team {COUNT} is refused", replace(c, COUNT, [1415]) != 0)
    rsp, _ = c.call("SwitchLineupIndexCsReq", {"index": LAST}, "SwitchLineupIndexScRsp")
    check(f"switch to team {COUNT}", rsp.get("retcode", 0) == 0, rsp)
    rsp, _ = c.call("GetCurLineupDataCsReq", {}, "GetCurLineupDataScRsp")
    check(f"team {COUNT} is the current team", rsp.get("lineup", {}).get("index") == LAST and ids(rsp["lineup"]) == [1415, 1501], rsp)
    rsp, _ = c.call("SetLineupNameCsReq", {"index": LAST, "name": "Last"}, "SetLineupNameScRsp")
    check(f"rename team {COUNT}", rsp.get("retcode", 0) == 0 and rsp.get("name") == "Last", rsp)
    rsp, _ = c.call("SwitchLineupIndexCsReq", {"index": COUNT}, "SwitchLineupIndexScRsp")
    check(f"switch past team {COUNT} is refused", rsp.get("retcode", 0) != 0, rsp)

    srv.restart()
    c = srv.login()
    rsp, by_index = presets(c)
    check(f"still team {COUNT} after a restart", rsp.get("cur_index") == LAST, rsp.get("cur_index"))
    check(f"team {COUNT} kept its members and name", ids(by_index[LAST]) == [1415, 1501] and by_index[LAST].get("name") == "Last",
          by_index[LAST])
    saved = srv.read_json("lineups.json")
    check(f"lineups.json holds {COUNT} teams", len(saved.get("lineups", [])) == COUNT, len(saved.get("lineups", [])))

# A lineups.json from before, with the game's 9 teams, loads as they were plus 41 empty ones.
old = {"cur_index": 8, "lineups": [{"name": "", "leader": 0, "favourite": False, "avatars": []}] * 8
       + [{"name": "Nine", "leader": 1501, "favourite": True, "avatars": [1310, 1501]}]}
with Server(files={"lineups.json": json.dumps(old)}) as srv:
    c = srv.login()
    rsp, by_index = presets(c)
    check("a 9-team file loads", rsp.get("cur_index") == 8 and ids(by_index[8]) == [1310, 1501]
          and by_index[8].get("name") == "Nine", by_index.get(8))
    check("with 41 empty teams after it", len(by_index) == COUNT and all(not ids(by_index[i]) for i in range(9, COUNT)))

done()
