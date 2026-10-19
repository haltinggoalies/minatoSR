import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402


def heartbeat_data(c):
    rsp, _ = c.call("PlayerHeartBeatCsReq", {"client_time_ms": 1}, "PlayerHeartBeatScRsp")
    return rsp["download_data"]["data"]


with Server() as srv:
    c = srv.login()
    check("no lua folder", "Create a lua folder" in " ".join(c.command("/windy")))

files = {"lua/b.lua": "print('b')", "lua/a.lua": "print('a')", "lua/notes.txt": "x", "lua/big.lua": "--" + "x" * 70000}
with Server(files=files) as srv:
    c = srv.login()
    lines = c.command("/windy")
    check("lists .lua files sorted", lines and lines[0].splitlines() == ["1. a.lua", "2. b.lua", "3. big.lua"], lines)
    check("a path outside lua/ is refused", "No script" in " ".join(c.command("/windy ../config.json")))
    check("a number past the list is refused", "No script" in " ".join(c.command("/windy 9")))
    check("over 64 KB refused", "64 KB" in " ".join(c.command("/windy big")))
    check("by name without .lua", "Sending b.lua" in " ".join(c.command("/windy b")))
    check("by number", "Sending a.lua" in " ".join(c.command("/windy load 1")))
    check("heartbeat 1 carries b.lua", heartbeat_data(c) == b"print('b')")
    check("heartbeat 2 carries a.lua", heartbeat_data(c) == b"print('a')")
    check("then the watermark again", b"setTextComponent" in heartbeat_data(c))
    check("loaded lists both", "b.lua, a.lua" in " ".join(c.command("/windy loaded")))
    c = srv.login()
    check("a new login starts a new list", "No script sent" in " ".join(c.command("/windy loaded")))

done()
