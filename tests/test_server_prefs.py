import base64, json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def prefs_all(c):
    rsp, _ = c.call("GetAllServerPrefsDataCsReq", {}, "GetAllServerPrefsDataScRsp")
    return {p.get("server_prefs_id", 0): p.get("data", b"") for p in rsp.get("server_prefs_list", [])}


def update(c, prefs_id, data):
    rsp, _ = c.call("UpdateServerPrefsCsReq", {"server_prefs": {"server_prefs_id": prefs_id, "data": data}}, "UpdateServerPrefsScRsp")
    return rsp


with Server() as srv:
    c = srv.login()
    check("nothing saved yet", prefs_all(c) == {})
    rsp = update(c, 7, b"\x00\x01layout")
    check("update answers with the id", rsp.get("server_prefs_id") == 7 and rsp.get("retcode", 0) == 0, rsp)
    update(c, 9, b"x" * 1000)
    update(c, 7, b"new")
    check("all prefs; a second update of 7 replaces it", prefs_all(c) == {7: b"new", 9: b"x" * 1000}, prefs_all(c))

    rsp, _ = c.call("GetServerPrefsDataCsReq", {"server_prefs_id": 9}, "GetServerPrefsDataScRsp")
    check("one pref", rsp.get("server_prefs") == {"server_prefs_id": 9, "data": b"x" * 1000}, rsp)
    rsp, _ = c.call("GetServerPrefsDataCsReq", {"server_prefs_id": 42}, "GetServerPrefsDataScRsp")
    check("unknown id: an entry with only the id", rsp.get("server_prefs") == {"server_prefs_id": 42}, rsp)

    rsp, _ = c.call("UpdateServerPrefsCsReq", {}, "UpdateServerPrefsScRsp")
    check("update without server_prefs: retcode 0, nothing saved", rsp.get("retcode", 0) == 0 and len(prefs_all(c)) == 2, rsp)
    rsp = update(c, 9, b"y" * (64 * 1024 + 1))
    check("over 64 KB refused, old data kept", rsp.get("retcode", 0) != 0 and prefs_all(c)[9] == b"x" * 1000, rsp)
    rsp = update(c, 11, b"z" * (64 * 1024))
    check("exactly 64 KB accepted", rsp.get("retcode", 0) == 0 and prefs_all(c)[11] == b"z" * (64 * 1024), rsp)

    expected = {7: b"new", 9: b"x" * 1000, 11: b"z" * (64 * 1024)}
    saved = {e["id"]: base64.b64decode(e["data"]) for e in srv.read_json("server_prefs.json")["prefs"]}
    check("server_prefs.json holds base64", saved == expected, sorted(saved))

    srv.restart()
    c = srv.login()
    check("prefs survive a restart", prefs_all(c) == expected, sorted(prefs_all(c)))

    srv.stop()
    with open(srv.path("server_prefs.json"), "w") as f:
        f.write('{"prefs": [{"id": 1, "data": "!!"}]}')
    srv.start()
    c = srv.login()
    check("broken file: no prefs", prefs_all(c) == {}, prefs_all(c))
    check("broken file kept as server_prefs.json.bad", os.path.exists(srv.path("server_prefs.json.bad")))

full = {"prefs": [{"id": i, "data": base64.b64encode(b"p").decode()} for i in range(1, 257)]}
with Server(files={"server_prefs.json": json.dumps(full)}) as srv:
    c = srv.login()
    check("256 prefs load", len(prefs_all(c)) == 256)
    rsp = update(c, 1000, b"q")
    check("a 257th id is refused", rsp.get("retcode", 0) != 0 and 1000 not in prefs_all(c), rsp)
    rsp = update(c, 5, b"q")
    check("an existing id still updates", rsp.get("retcode", 0) == 0 and prefs_all(c)[5] == b"q", rsp)

too_many = {"prefs": [{"id": i, "data": ""} for i in range(1, 258)]}
with Server(files={"server_prefs.json": json.dumps(too_many)}) as srv:
    c = srv.login()
    check("a file with 257 prefs is refused", prefs_all(c) == {} and os.path.exists(srv.path("server_prefs.json.bad")))
done()
