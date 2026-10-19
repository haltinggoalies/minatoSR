import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402


def pam(c):
    return c.call("GetPamSkinDataCsReq", {}, "GetPamSkinDataScRsp")[0].get("cur_skin")


with Server() as srv:
    c = srv.login()
    check("default outfit", pam(c) == 252000, pam(c))
    rsp, _ = c.call("SelectPamSkinCsReq", {"pam_skin": 252003}, "SelectPamSkinScRsp")
    check("outfit picked", rsp.get("cur_skin") == 252003, rsp)
    c.call("SelectPamSkinCsReq", {"pam_skin": 999}, "SelectPamSkinScRsp")
    check("unknown outfit ignored", pam(c) == 252003)
    srv.restart()
    c = srv.login()
    check("outfit survives a restart", pam(c) == 252003, pam(c))
    saved = srv.read_json("profile.json")
    check("profile.json holds every field", saved.get("pam_skin") == 252003 and saved.get("nickname") == "ReversedRooms", saved)

with Server(files={"profile.json": '{"pam_skin": 252004}'}) as srv:
    check("an old profile.json still loads", pam(srv.login()) == 252004)

with Server(files={"profile.json": '{"pam_skin": '}) as srv:
    c = srv.login()
    check("a broken profile.json falls back to the default", pam(c) == 252000)
    check("and is kept as profile.json.bad", os.path.exists(srv.path("profile.json.bad")))

done()
