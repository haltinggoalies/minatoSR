import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402


def peak_group(c):
    return c.call("GetChallengePeakDataCsReq", {}, "GetChallengePeakDataScRsp")[0].get("current_peak_group_id")


with Server() as srv:
    c = srv.login()
    auto = peak_group(c)
    check("automatic season is the newest", auto == 11, auto)
    lines = c.command("/peak")
    check("status lists the seasons", "Seasons: 1 2 3" in " ".join(lines), lines)
    check("unknown season refused", "No season 99" in " ".join(c.command("/peak 99")))
    lines = c.command("/peak 3")
    pushed = packets_named(c.last_packets, "GetChallengePeakDataScRsp")
    check("the data is pushed with the new season", pushed and pushed[0].msg().get("current_peak_group_id") == 3, lines)
    check("and a group update", packets_named(c.last_packets, "ChallengePeakGroupDataUpdateScNotify"))
    check("query answers season 3", peak_group(c) == 3)
    srv.restart()
    c = srv.login()
    check("season survives a restart", peak_group(c) == 3)
    c.command("/peak 0")
    check("/peak 0 is automatic again", peak_group(c) == auto)

    print("during a fight")
    c.call("StartChallengePeakCsReq", {"peak_id": 1101, "peak_avatar_id_list": [1310, 1415, 1501, 1303]}, "StartChallengePeakScRsp")
    lines = c.command("/peak 2")
    check("the season changes after the fight", "after this challenge" in " ".join(lines), lines)
    check("nothing is pushed mid-fight", not packets_named(c.last_packets, "GetChallengePeakDataScRsp"))
    c.call("LeaveChallengePeakCsReq", {}, "LeaveChallengePeakScRsp")
    check("after leaving the query answers season 2", peak_group(c) == 2)

done()
