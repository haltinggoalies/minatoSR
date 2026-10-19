import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402

NOON_20260920 = 1789876800000  # 2026-09-20 12:00 UTC+8


def server_ms(c):
    rsp, _ = c.call("PlayerHeartBeatCsReq", {"client_time_ms": 1}, "PlayerHeartBeatScRsp")
    return rsp["server_time_ms"]


with Server() as srv:
    c = srv.login()
    check("real time by default", abs(server_ms(c) - time.time() * 1000) < 60000)
    check("bad date refused", "Usage" in " ".join(c.command("/faketime 2026-02-30")))
    lines = c.command("/faketime 20260920")
    check("date set", "2026-09-20 12:00" in " ".join(lines), lines)
    check("heartbeat reports that day from noon UTC+8", 0 <= server_ms(c) - NOON_20260920 < 60000, server_ms(c))
    srv.restart()
    c = srv.login()
    check("still set after a restart", 0 <= server_ms(c) - NOON_20260920 < 60000)
    rsp, _ = c.call("PlayerLoginCsReq", {}, "PlayerLoginScRsp")
    check("login reports it too", 0 <= rsp["server_timestamp_ms"] - NOON_20260920 < 60000, rsp.get("server_timestamp_ms"))
    c.command("/faketime off")
    check("off = real time", abs(server_ms(c) - time.time() * 1000) < 60000)

done()
