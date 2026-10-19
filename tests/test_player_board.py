import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config, FIXTURE_AVATARS
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


DEFAULT_DISPLAY = [(1415, 1), (1001, 2), (1310, 3), (1303, 4), (1501, 5)]
DEFAULT_ASSIST = [1510, 1508, 1505]
PICKED = [(1310, 0), (8001, 1), (1001, 2)]


def board(c):
    rsp, _ = c.call("GetPlayerBoardDataCsReq", {}, "GetPlayerBoardDataScRsp")
    return rsp


def pairs(entries):
    return [(e.get("avatar_id", 0), e.get("pos", 0)) for e in entries]


def board_display(b):
    return pairs(b.get("display_avatar_vec", {}).get("display_avatar_list", []))


with Server() as srv:
    c = srv.login()
    b = board(c)
    check("default display avatars", board_display(b) == DEFAULT_DISPLAY, b.get("display_avatar_vec"))
    check("default assist avatars", b.get("assist_avatar_id_list") == DEFAULT_ASSIST, b.get("assist_avatar_id_list"))
    check("default card, no icon, no signature", b.get("current_personal_card_id") == 253001
          and b.get("current_head_icon_id", 0) == 0 and b.get("signature", "") == "", b)
    icons = [h["id"] for h in b.get("unlocked_head_icon_list", [])]
    icon = icons[len(icons) // 2]

    # Signature: cut at 256 bytes on a character boundary; text that is not UTF-8 is refused.
    rsp, _ = c.call("SetSignatureCsReq", {"signature": "a" * 300}, "SetSignatureScRsp")
    check("signature cut at 256 bytes", rsp.get("signature") == "a" * 256, len(rsp.get("signature", "")))
    rsp, _ = c.call("SetSignatureCsReq", {"signature": "é" * 200}, "SetSignatureScRsp")
    check("signature cut between characters", rsp.get("signature") == "é" * 128, len(rsp.get("signature", "")))
    rsp, _ = c.call("SetSignatureCsReq", {"signature": b"\xff\xfe"}, "SetSignatureScRsp")
    check("signature that is not UTF-8 refused", rsp.get("signature") == "é" * 128, rsp)
    rsp, _ = c.call("SetSignatureCsReq", {"signature": "Remember me ✨"}, "SetSignatureScRsp")
    check("signature set", rsp.get("signature") == "Remember me ✨" and rsp.get("retcode", 0) == 0, rsp)

    rsp, _ = c.call("SetHeadIconCsReq", {"id": icon}, "SetHeadIconScRsp")
    check("head icon set", rsp.get("current_head_icon_id") == icon, rsp)
    rsp, _ = c.call("SetHeadIconCsReq", {"id": 1}, "SetHeadIconScRsp")
    check("locked head icon refused", rsp.get("current_head_icon_id") == icon, rsp)

    rsp, _ = c.call("SetPersonalCardCsReq", {"id": 253003}, "SetPersonalCardScRsp")
    check("personal card set", rsp.get("current_personal_card_id") == 253003, rsp)
    rsp, _ = c.call("SetPersonalCardCsReq", {"id": 1}, "SetPersonalCardScRsp")
    check("unknown personal card refused", rsp.get("current_personal_card_id") == 253003, rsp)

    # 8010 is the Trailblazer on a path: saved as its base id 8001.
    req = [{"avatar_id": 1310, "pos": 0}, {"avatar_id": 8010, "pos": 1}, {"avatar_id": 1001, "pos": 2}]
    rsp, _ = c.call("SetDisplayAvatarCsReq", {"display_avatar_list": req}, "SetDisplayAvatarScRsp")
    check("display avatars set as base ids", pairs(rsp.get("display_avatar_list", [])) == PICKED, rsp)
    for label, bad in (("unknown avatar", [{"avatar_id": 9999, "pos": 0}]),
                       ("repeated avatar", [{"avatar_id": 1310, "pos": 0}, {"avatar_id": 1310, "pos": 1}]),
                       ("six avatars", [{"avatar_id": a, "pos": i} for i, a in enumerate([1310, 1415, 1501, 1303, 1001, 8001])])):
        rsp, _ = c.call("SetDisplayAvatarCsReq", {"display_avatar_list": bad}, "SetDisplayAvatarScRsp")
        check(f"display: {label} refused", pairs(rsp.get("display_avatar_list", [])) == PICKED, rsp)

    rsp, _ = c.call("SetAssistAvatarCsReq", {"avatar_id_list": [1415, 1501]}, "SetAssistAvatarScRsp")
    check("assist avatars set", rsp.get("avatar_id_list") == [1415, 1501], rsp)
    for label, bad in (("unknown avatar", [9999]), ("repeated avatar", [1415, 1415]), ("four avatars", [1415, 1501, 1303, 1310])):
        rsp, _ = c.call("SetAssistAvatarCsReq", {"avatar_id_list": bad}, "SetAssistAvatarScRsp")
        check(f"assist: {label} refused", rsp.get("avatar_id_list") == [1415, 1501], rsp)

    rsp, _ = c.call("SetIsDisplayAvatarInfoCsReq", {"is_display": True}, "SetIsDisplayAvatarInfoScRsp")
    check("SetIsDisplayAvatarInfo echoed", rsp.get("is_display") is True and rsp.get("retcode", 0) == 0, rsp)

    def check_board(c, when):
        b = board(c)
        check(f"{when}: signature", b.get("signature") == "Remember me ✨", b.get("signature"))
        check(f"{when}: head icon", b.get("current_head_icon_id") == icon, b.get("current_head_icon_id"))
        check(f"{when}: personal card", b.get("current_personal_card_id") == 253003, b.get("current_personal_card_id"))
        check(f"{when}: display avatars", board_display(b) == PICKED, board_display(b))
        check(f"{when}: assist avatars", b.get("assist_avatar_id_list") == [1415, 1501], b.get("assist_avatar_id_list"))

    check_board(c, "same session")

    rsp, _ = c.call("GetPlayerDetailInfoCsReq", {"uid": 1}, "GetPlayerDetailInfoScRsp")
    d = rsp.get("detail_info", {})
    check("detail: nickname, signature, head icon", d.get("nickname") == "ReversedRooms"
          and d.get("signature") == "Remember me ✨" and d.get("head_icon") == icon, d)
    check("detail: display avatars", [a.get("avatar_id") for a in d.get("display_avatar_list", [])] == [1310, 8001, 1001],
          d.get("display_avatar_list"))
    check("detail: assist avatars", [a.get("avatar_id") for a in d.get("assist_avatar_list", [])] == [1415, 1501],
          d.get("assist_avatar_list"))
    check("detail: avatars carry their config.json level and Light Cone",
          all(a.get("level", 0) > 0 and a.get("equipment", {}).get("tid", 0) > 0 for a in d.get("display_avatar_list", [])),
          d.get("display_avatar_list"))
    check("detail: gender, level, world level", d.get("gender") == 2 and d.get("level") == 70 and d.get("world_level") == 6, d)
    rsp, _ = c.call("GetPlayerDetailInfoCsReq", {"uid": 2000}, "GetPlayerDetailInfoScRsp")
    check("MushiSR's card is not the player's", "nickname" not in rsp.get("detail_info", {}), rsp)

    p = saved(srv)
    check("profile.json", p.get("signature") == "Remember me ✨" and p.get("head_icon") == icon
          and p.get("personal_card") == 253003 and p.get("assist_avatars") == [1415, 1501]
          and p.get("display_avatars") == [{"avatar_id": a, "pos": pos} for a, pos in PICKED], p)

    srv.restart()
    c = srv.login()
    check_board(c, "after restart")

    # An avatar config.json no longer has drops off the board.
    srv.stop()
    srv.write_json("config.json", fixture_config(avatars=[a for a in FIXTURE_AVATARS if a != 1310]))
    srv.start()
    c = srv.login()
    check("avatar gone from config.json is left out", board_display(board(c)) == [(8001, 1), (1001, 2)], board_display(board(c)))

    # None left: the defaults.
    srv.stop()
    p = saved(srv)
    p["display_avatars"], p["assist_avatars"] = [{"avatar_id": 9999, "pos": 0}], [9998]
    srv.write_json("profile.json", p)
    srv.start()
    c = srv.login()
    b = board(c)
    check("no saved avatar left: the default board", board_display(b) == DEFAULT_DISPLAY
          and b.get("assist_avatar_id_list") == DEFAULT_ASSIST, b)

# A hand-edited profile.json with an icon and a card the player does not have shows the defaults.
with Server(files={"profile.json": '{"head_icon": 1, "personal_card": 1}'}) as srv:
    c = srv.login()
    b = board(c)
    rsp, _ = c.call("GetPlayerDetailInfoCsReq", {"uid": 1}, "GetPlayerDetailInfoScRsp")
    check("unowned saved icon and card: the defaults", b.get("current_head_icon_id", 0) == 0
          and b.get("current_personal_card_id") == 253001 and rsp.get("detail_info", {}).get("head_icon", 0) == 0, (b, rsp))
done()
