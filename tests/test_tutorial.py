"""Tutorial unlocks answer with what they unlocked: the client's handlers read the reply's tutorial (guide) id, and an
empty reply crashed TutorialModule._OnCmdUnlockTutorialGuideScRsp ("attempt to index nil with 'Id'"), leaving a broken
guide dialog that closed the next page opened (the Currency Wars entrance)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402

TUTORIAL_UNLOCK = 1

with Server() as srv:
    c = srv.login()
    rsp, _ = c.call("UnlockTutorialGuideCsReq", {"group_id": 7001, "type": 1}, "UnlockTutorialGuideScRsp")
    guide = rsp.get("tutorial_guide", {})
    check("a guide unlock answers with the guide", rsp.get("retcode", 0) == 0 and guide.get("id") == 7001
          and guide.get("status") == TUTORIAL_UNLOCK, rsp)
    rsp, _ = c.call("UnlockTutorialCsReq", {"tutorial_id": 10001}, "UnlockTutorialScRsp")
    tutorial = rsp.get("tutorial", {})
    check("a tutorial unlock answers with the tutorial", rsp.get("retcode", 0) == 0 and tutorial.get("id") == 10001
          and tutorial.get("status") == TUTORIAL_UNLOCK, rsp)

done()
