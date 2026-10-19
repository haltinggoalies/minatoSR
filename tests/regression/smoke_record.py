"""Plays every game mode against one gameserver build and records every packet it sends back.

Usage: python -I smoke_record.py <root.zig> <handlers.zig> <gameserver.exe> <run dir> <out.json>
The run dir needs config.json + a resources junction; lineups/profile/tierce files there are removed first so
both builds start from the same state.
"""
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time

# Not 23301, where the player's own gameserver may listen (see tests/fakeclient/client.py). Builds older than
# PEARL_GAMESERVER_PORT still listen on 23301: stop the player's server and set PEARL_TEST_PORT=23301 to record them.
HOST, PORT = "127.0.0.1", int(os.environ.get("PEARL_TEST_PORT", "23391"))
HEAD, TAIL = 0x9D74C714, 0xD7A152C8
WIN, LOSE = 1, 2

root_zig, handlers_zig, exe, run_dir, out_path = sys.argv[1:6]
NAME2ID, ID2NAME = {}, {}
for m in re.finditer(r"^\s*(Cmd\w+) = (\d+),", open(root_zig, encoding="utf-8").read(), re.M):
    NAME2ID[m.group(1)] = int(m.group(2))
    ID2NAME[int(m.group(2))] = m.group(1)


def cmd(name):
    return NAME2ID["Cmd" + name]


# --- protobuf ---------------------------------------------------------------------------------------------------
def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | 0x80 if n else b)
        if not n:
            return bytes(out)


def f_int(field, value):
    return varint(field << 3) + varint(value) if value else b""


def f_msg(field, body):
    return varint((field << 3) | 2) + varint(len(body)) + body


def f_packed(field, values):
    return f_msg(field, b"".join(varint(v) for v in values)) if values else b""


def read_varint(buf, i):
    n = shift = 0
    while True:
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return n, i


def parse(buf):
    out, i = {}, 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        field, wt = key >> 3, key & 7
        if wt == 0:
            val, i = read_varint(buf, i)
        elif wt == 2:
            ln, i = read_varint(buf, i)
            val, i = buf[i:i + ln], i + ln
        elif wt == 1:
            val, i = buf[i:i + 8], i + 8
        elif wt == 5:
            val, i = buf[i:i + 4], i + 4
        else:
            raise ValueError(f"wire type {wt}")
        out.setdefault(field, []).append(val)
    return out


def one(msg, field, default=0):
    return msg.get(field, [default])[0]


# --- connection -------------------------------------------------------------------------------------------------
class Dropped(Exception):
    pass


class Client:
    def __init__(self):
        self.sock = socket.create_connection((HOST, PORT), timeout=5)
        self.buf = b""

    def send(self, c, body=b""):
        self.sock.sendall(struct.pack(">IHHI", HEAD, c, 0, len(body)) + body + struct.pack(">I", TAIL))

    def recv_packet(self, timeout):
        self.sock.settimeout(timeout)
        while True:
            if len(self.buf) >= 12:
                head, c, hl, bl = struct.unpack(">IHHI", self.buf[:12])
                total = 12 + hl + bl + 4
                if len(self.buf) >= total:
                    body = self.buf[12 + hl:12 + hl + bl]
                    self.buf = self.buf[total:]
                    return c, body
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            except OSError as e:
                raise Dropped(str(e))
            if not chunk:
                raise Dropped("closed")
            self.buf += chunk


steps = []
client = None


def connect():
    global client
    for _ in range(100):
        try:
            client = Client()
            return
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("no server")


def step(label, req, body=b"", rsp=None, settle=0.3):
    """Sends `req`, collects packets until `rsp` (if given) and then until `settle` seconds of quiet."""
    packets, rsp_body, dropped = [], None, None
    try:
        client.send(cmd(req) if isinstance(req, str) else req, body)
        want = (cmd(rsp) if isinstance(rsp, str) else rsp) if rsp else None
        deadline = time.time() + 5
        while want is not None and time.time() < deadline:
            p = client.recv_packet(5)
            if p is None:
                break
            packets.append(p)
            if p[0] == want:
                rsp_body = p[1]
                break
        while True:
            p = client.recv_packet(settle)
            if p is None:
                break
            packets.append(p)
    except Dropped as e:
        dropped = str(e)
        connect()
    steps.append(dict(label=label, req=req if isinstance(req, str) else ID2NAME.get(req, str(req)), dropped=dropped,
                      got_rsp=rsp is None or rsp_body is not None,
                      packets=[[ID2NAME.get(c, str(c)), b.hex()] for c, b in packets]))
    return rsp_body or b""


def battle_stage():
    rsp = step("GetCurBattleInfo", "GetCurBattleInfoCsReq", b"", "GetCurBattleInfoScRsp")
    info = parse(one(parse(rsp), 9, b""))
    return one(info, 15)


def pve(label, stage_id, status=WIN, rounds=3, score=0):
    stt = f_int(9, rounds) + f_int(14, score)
    step(label, "PVEBattleResultCsReq", f_int(6, status) + f_msg(8, stt) + f_int(10, stage_id), "PVEBattleResultScRsp")


def avatar_lineup(field, ids):
    return b"".join(f_msg(field, f_int(1, i) + f_int(4, 3)) for i in ids)


def main():
    for name in ("lineups.json", "lineups.json.bad", "profile.json", "tierce.json", "tierce.json.bad"):
        p = os.path.join(run_dir, name)
        if os.path.exists(p):
            os.remove(p)
    cfg = json.load(open(os.path.join(run_dir, "config.json"), encoding="utf-8"))
    ids = [a["id"] for a in cfg["avatar_config"]][:12]
    teams = [ids[0:4], ids[4:8], ids[8:12]]
    proc = subprocess.Popen([exe], cwd=run_dir, stdout=open(out_path + ".log", "wb"), stderr=subprocess.STDOUT,
                            env=dict(os.environ, PEARL_GAMESERVER_PORT=str(PORT)))
    try:
        connect()
        # Login and the data the client asks for at login.
        step("login token", "PlayerGetTokenCsReq", f_int(11, 1), "PlayerGetTokenScRsp")
        step("login", "PlayerLoginCsReq", b"", "PlayerLoginScRsp")
        for name in ("GetBasicInfo", "GetAvatarData", "GetBag", "GetAllLineupData", "GetCurLineupData", "GetCurSceneInfo",
                     "GetChallenge", "GetChallengePeakData", "GetChallengeTierceData", "GetCurChallenge", "GetCurChallengePeak",
                     "GetCurBattleInfo", "GetMissionStatus", "GetQuestData", "GetMail", "GetFriendListInfo", "GetPhoneData",
                     "GetPlayerBoardData", "GetLineupAvatarData", "GetPamSkinData", "GetGachaInfo", "PlayerLoginFinish"):
            step(name, name + "CsReq", b"", name + "ScRsp")

        # Overworld battles.
        step("cast skill on a monster", "SceneCastSkillCsReq", f_int(10, 1) + f_int(11, 1) + f_packed(15, [2000001]), "SceneCastSkillScRsp")
        pve("overworld battle win", battle_stage())
        step("cocoon", "StartCocoonStageCsReq", f_int(2, 1001) + f_int(3, 6) + f_int(7, 1), "StartCocoonStageScRsp")
        pve("cocoon win", 0)
        step("quick cocoon", "QuickStartCocoonStageCsReq", f_int(1, 1) + f_int(8, 6) + f_int(15, 1001), "QuickStartCocoonStageScRsp")
        step("battle college", "StartBattleCollegeCsReq", f_int(4, 1), "StartBattleCollegeScRsp")
        pve("battle college win", 0)

        # Classic MoC / PF / AS (two nodes, server-side node switching).
        start = lambda cid: f_int(14, cid) + avatar_lineup(4, teams[0]) + avatar_lineup(15, teams[1])
        for cid, label in ((5612, "MoC"), (20284, "PF"), (30234, "AS")):
            step(f"{label} start", "StartChallengeCsReq", start(cid), "StartChallengeScRsp")
            step(f"{label} cur challenge", "GetCurChallengeCsReq", b"", "GetCurChallengeScRsp")
            pve(f"{label} node 1 win", battle_stage(), rounds=5, score=30000 if label == "PF" else 0)
            if label == "AS":
                step("AS next phase", "EnterChallengeNextPhaseCsReq", b"", "EnterChallengeNextPhaseScRsp")
            pve(f"{label} node 2 win", battle_stage(), rounds=6, score=70000 if label == "PF" else 0)
            step(f"{label} cur challenge after", "GetCurChallengeCsReq", b"", "GetCurChallengeScRsp")
            step(f"{label} leave", "LeaveChallengeCsReq", b"", "LeaveChallengeScRsp")
        step("MoC start (loss)", "StartChallengeCsReq", start(5612), "StartChallengeScRsp")
        pve("MoC node 1 lose", battle_stage(), status=LOSE, rounds=30)
        step("MoC restart phase", "RestartChallengePhaseCsReq", b"", "RestartChallengePhaseScRsp")
        battle_stage()
        step("MoC leave", "LeaveChallengeCsReq", b"", "LeaveChallengeScRsp")
        step("MoC partial", "StartPartialChallengeCsReq", f_int(4, 1) + f_int(9, 5612), "StartPartialChallengeScRsp")
        pve("MoC partial win", battle_stage())
        step("MoC partial leave", "LeaveChallengeCsReq", b"", "LeaveChallengeScRsp")

        # Anomaly Arbitration (challenge peak): a knight, retry, the boss in hard mode.
        step("AA hard mode", "SetChallengePeakBossHardModeCsReq", f_int(1, 11) + f_int(2, 1), "SetChallengePeakBossHardModeScRsp")
        step("AA knight start", "StartChallengePeakCsReq", f_int(14, 1101) + f_packed(13, teams[0]), "StartChallengePeakScRsp")
        step("AA cur peak", "GetCurChallengePeakCsReq", b"", "GetCurChallengePeakScRsp")
        pve("AA knight win", battle_stage(), rounds=4)
        step("AA restart", "ReStartChallengePeakCsReq", b"", "ReStartChallengePeakScRsp")
        pve("AA knight lose", battle_stage(), status=LOSE)
        step("AA leave", "LeaveChallengePeakCsReq", b"", "LeaveChallengePeakScRsp")
        step("AA boss start", "StartChallengePeakCsReq", f_int(14, 1104) + f_packed(13, teams[1]), "StartChallengePeakScRsp")
        pve("AA boss win", battle_stage(), rounds=5)
        step("AA leave boss", "LeaveChallengePeakCsReq", b"", "LeaveChallengePeakScRsp")

        # Starward (challenge tierce) MoC / PF / AS, three nodes each.
        lineups = b"".join(f_msg(9, avatar_lineup(9, t)) for t in teams)
        for cid, label in ((5613, "Starward MoC"), (20285, "Starward PF"), (30235, "Starward AS")):
            step(f"{label} start", "StartChallengeTierceCsReq", f_int(3, cid) + lineups, "StartChallengeTierceScRsp")
            for node in range(3):
                if node:
                    step(f"{label} confirm settle", "MENLHHCJNCE", b"", "OKEDFNJJGHB")
                    step(f"{label} next node", "MHJNOBBOFOC", b"", "LHAKNKHBLBI")
                pve(f"{label} node {node + 1} win", battle_stage(), rounds=4, score=(35000 + 40000 * (node > 0)) if "PF" in label else 0)
            step(f"{label} data", "GetChallengeTierceDataCsReq", b"", "GetChallengeTierceDataScRsp")
            step(f"{label} leave", "LeaveChallengeTierceCsReq", b"", "LeaveChallengeTierceScRsp")

        # Every other handler, with an empty request.
        done = {s["req"] for s in steps}
        live = "\n".join(l for l in open(handlers_zig, encoding="utf-8").read().splitlines() if not l.strip().startswith("//"))
        handled = [n for n in re.findall(r"CmdID\.(Cmd\w+CsReq|Cmd[A-Z]{11})\b", live) if n in NAME2ID]
        for name in dict.fromkeys(handled):
            if name in done or name in ("CmdPlayerGetTokenCsReq", "CmdPlayerLoginCsReq"):
                continue
            rsp = name[:-5] + "ScRsp" if name.endswith("CsReq") and name[:-5] + "ScRsp" in NAME2ID else None
            step("sweep " + name[3:], name[3:], b"", rsp[3:] if rsp else None)
    finally:
        proc.kill()
        proc.wait()
    json.dump(steps, open(out_path, "w"), indent=1)
    print(f"{len(steps)} steps, {sum(1 for s in steps if s['dropped'])} dropped, "
          f"{sum(1 for s in steps if not s['got_rsp'])} without a response")


main()
