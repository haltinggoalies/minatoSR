import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named
import pb
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def jukebox(c):
    rsp, _ = c.call("GetJukeboxDataCsReq", {}, "GetJukeboxDataScRsp")
    return rsp


def now_playing(rsp):
    return rsp.get("GFFOBALDBPM", {}).get("JKNLCEEDAHJ", {}).get("id", 0)


def play(c, body):
    """Sends 3131 with a raw body; returns (PlayBackGroundMusicScRsp view, EGDFPDHNOKO view) of the one reply."""
    rsp, pkts = c.call("PlayBackGroundMusicCsReq", body, "PlayBackGroundMusicScRsp")
    raw = packets_named(pkts, "PlayBackGroundMusicScRsp")[0].body
    return rsp, pb.decode("EGDFPDHNOKO", raw)


with Server() as srv:
    c = srv.login()
    rsp = jukebox(c)
    tracks = rsp.get("IOKAJIBHLMP", [])
    check("276 tracks (the 4.6.51 client's table), all unlocked", len(tracks) == 276 and all(t.get("BIMDKNLMICG") for t in tracks), len(tracks))
    # Live tracks the 4.6.51 client has no row for: its jukebox page indexes the row's GroupID and the whole UI dies.
    newer = {210508, 210509, 210510, 210511, 210512, 210513, 215014}
    check("no track the 4.6.51 client lacks", not newer & {t["id"] for t in tracks}, sorted(newer & {t["id"] for t in tracks}))
    check("210000 is in group 1", {"id": 210000, "group_id": 1, "BIMDKNLMICG": True} in tracks)
    check("nothing picked yet", now_playing(rsp) == 0, rsp.get("GFFOBALDBPM"))

    # Layout 1: FKLMGEFILDI {JKFCKJNHLHI (11) = id}, first byte 0x58.
    body = pb.encode("FKLMGEFILDI", {"JKFCKJNHLHI": 210005})
    check("FKLMGEFILDI body starts with 0x58", body[0] == 0x58, body.hex())
    as_rsp, as_id = play(c, body)
    check("0x58: EGDFPDHNOKO reads the id", as_id.get("JKFCKJNHLHI") == 210005 and as_id.get("retcode", 0) == 0, as_id)
    check("0x58: PlayBackGroundMusicScRsp reads the state", now_playing(as_rsp) == 210005 and as_rsp.get("retcode", 0) == 0, as_rsp)

    # Layout 2: PlayBackGroundMusicCsReq {IKJNIKIGFLF (13) = MNCBEDBDDHL}, first byte 0x6A.
    state = {"JKNLCEEDAHJ": {"id": 210100, "KDHCICFNAOC": True}, "PGPNCNABHAM": True}
    body = pb.encode("PlayBackGroundMusicCsReq", {"IKJNIKIGFLF": state})
    check("PlayBackGroundMusicCsReq body starts with 0x6A", body[0] == 0x6A, body.hex())
    as_rsp, as_id = play(c, body)
    check("0x6A: the client's state comes back", as_rsp.get("GFFOBALDBPM") == state, as_rsp)
    check("0x6A: EGDFPDHNOKO reads the id", as_id.get("JKFCKJNHLHI") == 210100, as_id)

    # Bad input keeps 210100 and the server alive.
    for label, body in (("unknown track", pb.encode("FKLMGEFILDI", {"JKFCKJNHLHI": 999999})),
                        ("empty body", b""), ("unknown first byte", b"\x07\x01"), ("cut-off varint", b"\x58")):
        as_rsp, as_id = play(c, body)
        check(f"{label}: current track kept", as_id.get("JKFCKJNHLHI") == 210100 and now_playing(as_rsp) == 210100, (as_rsp, as_id))

    with open(srv.path("gameserver.log"), "rb") as f:
        log = f.read().decode("utf-8", "replace")
    check("first 3131 body logged as hex", "58d5e80c" in log)

    rsp, _ = c.call("FKLMGEFILDI", {"JKFCKJNHLHI": 210001}, "EGDFPDHNOKO")
    check("3159 -> 3118 echoes the id", rsp.get("JKFCKJNHLHI") == 210001 and rsp.get("retcode", 0) == 0, rsp)
    rsp, _ = c.call("UnlockBackGroundMusicCsReq", {"LIGKEOLPFBE": [210002, 999999]}, "UnlockBackGroundMusicScRsp")
    check("3105 -> 3171 echoes known tracks", rsp.get("BPFGBEBPEDP") == [210002]
          and rsp.get("IOKAJIBHLMP") == [{"id": 210002, "group_id": 1, "BIMDKNLMICG": True}], rsp)

    check("saved in profile.json", saved(srv).get("jukebox_track") == 210100)
    srv.restart()
    c = srv.login()
    check("track survives a restart", now_playing(jukebox(c)) == 210100)
done()
