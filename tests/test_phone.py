import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def phone(c):
    rsp, _ = c.call("GetPhoneDataCsReq", {}, "GetPhoneDataScRsp")
    return rsp


# An old profile.json that only has the outfit must keep it when the phone is saved.
with Server(files={"profile.json": '{"pam_skin": 252001}'}) as srv:
    c = srv.login()
    rsp = phone(c)
    check("defaults: bubble 0, theme 0, case 254001",
          rsp.get("cur_chat_bubble", 0) == 0 and rsp.get("cur_phone_theme", 0) == 0 and rsp.get("cur_phone_case") == 254001, rsp)
    check("owned lists still sent", 220003 in rsp.get("owned_chat_bubbles", []) and 221005 in rsp.get("owned_phone_themes", [])
          and rsp.get("owned_phone_cases") == [254000, 254001], rsp)

    rsp, _ = c.call("SelectChatBubbleCsReq", {"bubble_id": 220003}, "SelectChatBubbleScRsp")
    check("bubble picked", rsp.get("cur_chat_bubble") == 220003 and rsp.get("retcode", 0) == 0, rsp)
    rsp, _ = c.call("SelectPhoneThemeCsReq", {"theme_id": 221005}, "SelectPhoneThemeScRsp")
    check("theme picked", rsp.get("cur_phone_theme") == 221005, rsp)
    rsp, _ = c.call("SelectPhoneCaseCsReq", {"phone_case_id": 254000}, "SelectPhoneCaseScRsp")
    check("case picked", rsp.get("cur_phone_case") == 254000, rsp)

    # Ids the player does not own keep the current choice.
    rsp, _ = c.call("SelectChatBubbleCsReq", {"bubble_id": 229999}, "SelectChatBubbleScRsp")
    check("unknown bubble keeps 220003", rsp.get("cur_chat_bubble") == 220003, rsp)
    rsp, _ = c.call("SelectPhoneThemeCsReq", {"theme_id": 1}, "SelectPhoneThemeScRsp")
    check("unknown theme keeps 221005", rsp.get("cur_phone_theme") == 221005, rsp)
    rsp, _ = c.call("SelectPhoneCaseCsReq", {"phone_case_id": 0}, "SelectPhoneCaseScRsp")
    check("case 0 keeps 254000", rsp.get("cur_phone_case") == 254000, rsp)

    p = saved(srv)
    check("profile.json has the choices and the old outfit",
          p.get("chat_bubble") == 220003 and p.get("phone_theme") == 221005 and p.get("phone_case") == 254000
          and p.get("pam_skin") == 252001, p)

    srv.restart()
    c = srv.login()
    rsp = phone(c)
    check("choices survive a restart",
          rsp.get("cur_chat_bubble") == 220003 and rsp.get("cur_phone_theme") == 221005 and rsp.get("cur_phone_case") == 254000, rsp)

# A hand-edited profile.json with ids the player does not own shows the defaults.
with Server(files={"profile.json": '{"chat_bubble": 229999, "phone_theme": 1, "phone_case": 999}'}) as srv:
    c = srv.login()
    rsp = phone(c)
    check("unowned saved ids: the defaults",
          rsp.get("cur_chat_bubble", 0) == 0 and rsp.get("cur_phone_theme", 0) == 0 and rsp.get("cur_phone_case") == 254001, rsp)
done()
