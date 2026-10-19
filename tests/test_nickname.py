import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def login_name(c):
    # PlayerLogin again on the same connection: its reply carries basic_info.
    rsp, _ = c.call("PlayerLoginCsReq", {}, "PlayerLoginScRsp")
    return rsp.get("basic_info", {}).get("nickname")


with Server() as srv:
    c = srv.login()
    check("default nickname", login_name(c) == "ReversedRooms")

    rsp, pkts = c.call("SetNicknameCsReq", {"is_modify": True, "nickname": "  Stelle  "}, "SetNicknameScRsp")
    names = [p.name for p in pkts]
    check("rename accepted", rsp.get("retcode", 0) == 0 and rsp.get("is_modify") is True
          and rsp.get("set_time", 0) > 1_700_000_000, rsp)
    check("PlayerSyncScNotify follows the reply", "PlayerSyncScNotify" in names
          and names.index("SetNicknameScRsp") < names.index("PlayerSyncScNotify"), names)
    if packets_named(pkts, "PlayerSyncScNotify"):
        info = packets_named(pkts, "PlayerSyncScNotify")[0].msg().get("basic_info", {})
        check("sync: trimmed name, login values", info.get("nickname") == "Stelle" and info.get("level") == 70
              and info.get("world_level") == 6 and info.get("stamina") == 300, info)

    for label, bad in (("blank", "   "), ("33 bytes", "a" * 33), ("11 Thai letters (33 bytes)", "ก" * 11),
                       ("not UTF-8", b"\xff\xfe")):
        rsp, pkts = c.call("SetNicknameCsReq", {"is_modify": True, "nickname": bad}, "SetNicknameScRsp")
        check(f"{label}: refused", rsp.get("retcode") == 2105 and not packets_named(pkts, "PlayerSyncScNotify"), rsp)
    check("refused names change nothing", login_name(c) == "Stelle")

    rsp, _ = c.call("SetNicknameCsReq", {"is_modify": True, "nickname": "ก" * 10}, "SetNicknameScRsp")
    check("10 Thai letters (30 bytes) fit", rsp.get("retcode", 0) == 0, rsp)
    check("saved in profile.json", saved(srv).get("nickname") == "ก" * 10)

    rsp, _ = c.call("GetBasicInfoCsReq", {}, "GetBasicInfoScRsp")
    gender = rsp.get("gender")
    rsp, _ = c.call("SetGenderCsReq", {"gender": 1}, "SetGenderScRsp")
    check("SetGender: retcode 0 and the current Trailblazer path", rsp.get("retcode", 0) == 0
          and rsp.get("cur_avatar_path") == 8010, rsp)
    rsp, _ = c.call("GetBasicInfoCsReq", {}, "GetBasicInfoScRsp")
    check("SetGender changes nothing", rsp.get("gender") == gender == 2, rsp)

    rsp, _ = c.call("SetPlayerInfoCsReq", {"is_modify": True, "nickname": "Caelus", "gender": 1}, "SetPlayerInfoScRsp")
    check("SetPlayerInfo answered", rsp.get("retcode", 0) == 0 and rsp.get("is_modify") is True
          and rsp.get("set_time", 0) > 1_700_000_000 and rsp.get("cur_avatar_path") == 8010, rsp)

    srv.restart()
    c = srv.login()
    check("name survives a restart; SetPlayerInfo did not rename", login_name(c) == "ก" * 10)
done()
