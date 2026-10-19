import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def mails(c):
    rsp, _ = c.call("GetMailCsReq", {}, "GetMailScRsp")
    return rsp


with Server() as srv:
    c = srv.login()
    m = mails(c)
    lst = m.get("mail_list", [])
    check("one unread mail with an attachment", len(lst) == 1 and lst[0].get("id") == 1 and not lst[0].get("is_read")
          and lst[0].get("attachment", {}).get("item_list") == [{"item_id": 1503, "num": 1}] and m.get("total_num") == 1, m)

    rsp, _ = c.call("MarkReadMailCsReq", {"id": 99}, "MarkReadMailScRsp")
    check("mark read, unknown id: RET_MAIL_MAIL_ID_INVALID", rsp.get("retcode") == 1702, rsp)
    rsp, _ = c.call("MarkReadMailCsReq", {"id": 1}, "MarkReadMailScRsp")
    check("mark read", rsp.get("retcode", 0) == 0 and rsp.get("id") == 1, rsp)
    check("mail now read", mails(c)["mail_list"][0].get("is_read") is True)

    rsp, _ = c.call("TakeMailAttachmentCsReq", {"mail_id_list": [5]}, "TakeMailAttachmentScRsp")
    check("take, unknown id: nothing taken", rsp.get("succ_mail_id_list", []) == [] and rsp.get("retcode", 0) == 0, rsp)
    rsp, _ = c.call("TakeMailAttachmentCsReq", {}, "TakeMailAttachmentScRsp")
    check("an empty list takes every attachment", rsp.get("succ_mail_id_list") == [1], rsp)
    check("attachment gone", "attachment" not in mails(c)["mail_list"][0])
    rsp, _ = c.call("TakeMailAttachmentCsReq", {}, "TakeMailAttachmentScRsp")
    check("nothing left to take", rsp.get("succ_mail_id_list", []) == [], rsp)

    rsp, _ = c.call("DelMailCsReq", {"id_list": [1, 77]}, "DelMailScRsp")
    check("delete with an unknown id: refused, nothing deleted", rsp.get("retcode") == 1702
          and len(mails(c).get("mail_list", [])) == 1, rsp)
    p = saved(srv).get("mail")
    check("profile.json mail state", p == {"read": [1], "deleted": [], "taken": [1]}, p)

    srv.restart()
    c = srv.login()
    lst = mails(c).get("mail_list", [])
    check("after a restart: still read, attachment still taken", len(lst) == 1 and lst[0].get("is_read") is True
          and "attachment" not in lst[0], lst)

    rsp, _ = c.call("DelMailCsReq", {"id_list": [1]}, "DelMailScRsp")
    check("delete", rsp.get("retcode", 0) == 0 and rsp.get("id_list") == [1], rsp)
    m = mails(c)
    check("mailbox empty", m.get("mail_list", []) == [] and m.get("total_num", 0) == 0, m)
    rsp, _ = c.call("MarkReadMailCsReq", {"id": 1}, "MarkReadMailScRsp")
    check("a deleted mail cannot be marked read", rsp.get("retcode") == 1702, rsp)
    srv.restart()
    c = srv.login()
    check("still deleted after a restart", mails(c).get("mail_list", []) == [])

with Server() as srv:
    c = srv.login()
    rsp, _ = c.call("TakeMailAttachmentCsReq", {"mail_id_list": [1]}, "TakeMailAttachmentScRsp")
    check("taking by id works", rsp.get("succ_mail_id_list") == [1], rsp)
    check("and marks the mail read", mails(c)["mail_list"][0].get("is_read") is True)
done()
