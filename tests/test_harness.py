import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config  # noqa: E402
import pb  # noqa: E402

check("schema parsed", len(pb.schema().messages) > 4000)
body = pb.encode("SetSignatureCsReq", {"signature": "hi"})
check("round trip", pb.decode("SetSignatureCsReq", body) == {"signature": "hi"})

with Server() as srv:
    c = srv.login()
    # The player's own gameserver may be listening on 23301 while tests run; this must be the test's server, whose
    # config.json is fixture_config() (stage 400101).
    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")
    stage = rsp.get("battle_info", {}).get("stage_id")
    check("talking to the test's own gameserver", stage == fixture_config()["battle_config"]["stage_id"], stage)
    check("/help answers", len(c.command("/help")) > 3)
    rsp, _ = c.call("GetPhoneDataCsReq", {}, "GetPhoneDataScRsp")
    check("nested lists decode", 220000 in rsp.get("owned_chat_bubbles", []), rsp)
    rsp, _ = c.call("GetPlayerBoardDataCsReq", {}, "GetPlayerBoardDataScRsp")
    check("sub-messages decode", rsp["display_avatar_vec"]["display_avatar_list"][0]["avatar_id"] > 0, rsp)
    srv.restart()
    c = srv.login()
    check("restart + login again", len(c.command("/help")) > 3)

done()
