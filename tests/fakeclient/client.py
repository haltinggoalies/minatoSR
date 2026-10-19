"""Fake 4.6.51 client and a throwaway gameserver to run it against.

    with Server() as srv:                 # copies config.json, links resources/, starts zig-out/bin/gameserver.exe
        c = srv.login()                   # PlayerGetToken + PlayerLogin + PlayerLoginFinish
        rsp, pkts = c.call("GetPhoneDataCsReq", {}, "GetPhoneDataScRsp")
        print(c.command("/help"))         # chat command -> list of MushiSR's reply lines
        srv.restart()                     # same run dir, so saved files survive

Env: PEARL_ROOT (repo, default ../..), PEARL_EXE (gameserver.exe, default <repo>/zig-out/bin/gameserver.exe).
"""
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pb  # noqa: E402

# Failure details may hold Thai or emoji; the Windows console code page cannot print those.
sys.stdout.reconfigure(errors="backslashreplace")

# Never 23301: the player's own gameserver may be listening there, and a second server bound to it with
# reuse_address would not fail, so tests could talk to the player's server. The test server gets this port through
# PEARL_GAMESERVER_PORT.
HOST, PORT = "127.0.0.1", int(os.environ.get("PEARL_TEST_PORT", "23391"))
HEAD, TAIL = 0x9D74C714, 0xD7A152C8
BOT_UID = 2000

_cmd = None


def cmds():
    """({'GetPhoneDataCsReq': 5174, ...}, {5174: 'GetPhoneDataCsReq', ...}) from protocol/src/root.zig."""
    global _cmd
    if _cmd is None:
        text = open(os.path.join(pb.repo_root(), "protocol", "src", "root.zig"), encoding="utf-8").read()
        n2i = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\s*Cmd(\w+) = (\d+),", text, re.M)}
        _cmd = (n2i, {v: k for k, v in n2i.items()})
    return _cmd


def cmd_id(name):
    return name if isinstance(name, int) else cmds()[0][name]


def cmd_name(cid):
    return cmds()[1].get(cid, str(cid))


class Dropped(Exception):
    pass


class Packet:
    def __init__(self, cid, body):
        self.cid, self.body = cid, body
        self.name = cmd_name(cid)

    def msg(self, msg_name=None):
        """Decoded body; the message type defaults to the CmdID's name."""
        return pb.decode(msg_name or self.name, self.body)

    def __repr__(self):
        return f"<{self.name} {self.body.hex()}>"


class Client:
    def __init__(self):
        self.sock = socket.create_connection((HOST, PORT), timeout=5)
        self.buf = b""

    def close(self):
        self.sock.close()

    def send(self, name, body=b""):
        if isinstance(body, dict):
            body = pb.encode(name, body)
        self.sock.sendall(struct.pack(">IHHI", HEAD, cmd_id(name), 0, len(body)) + body + struct.pack(">I", TAIL))

    def recv(self, timeout):
        self.sock.settimeout(timeout)
        while True:
            if len(self.buf) >= 12:
                _, c, hl, bl = struct.unpack(">IHHI", self.buf[:12])
                total = 12 + hl + bl + 4
                if len(self.buf) >= total:
                    body = self.buf[12 + hl:12 + hl + bl]
                    self.buf = self.buf[total:]
                    return Packet(c, body)
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            except OSError as e:
                raise Dropped(str(e))
            if not chunk:
                raise Dropped("closed")
            self.buf += chunk

    def call(self, req, body=None, rsp=None, settle=0.3):
        """Sends `req`; returns (decoded `rsp` or None, every packet received) after `settle` s of quiet."""
        self.send(req, body if body is not None else b"")
        packets, found = [], None
        deadline = time.time() + 5
        while rsp and found is None and time.time() < deadline:
            p = self.recv(5)
            if p is None:
                break
            packets.append(p)
            if p.name == rsp:
                found = p
        while True:
            p = self.recv(settle)
            if p is None:
                break
            packets.append(p)
        if rsp and found is None:
            raise AssertionError(f"{req}: no {rsp} (got {[p.name for p in packets]})")
        return (found.msg() if found else None), packets

    def command(self, text, settle=0.5):
        """Types `text` to MushiSR; returns its reply lines."""
        body = {"target_list": [BOT_UID], "chat_type": 1,
                "message_datas": {"message_type": 1, "chat_data": {"message_text": text}}}
        _, packets = self.call("SendMsgCsReq", body, "SendMsgScRsp", settle=settle)
        self.last_packets = packets
        return chat_lines(packets)


def chat_lines(packets):
    out = []
    for p in packets:
        if p.name != "RevcMsgScNotify":
            continue
        data = p.msg().get("recv_message_data", {})
        for d in data.get("message_datas", []):
            text = d.get("chat_data", {}).get("message_text")
            if text is not None:
                out.append(text)
    return out


def packets_named(packets, name):
    return [p for p in packets if p.name == name]


# Test servers all use PORT, so only one test may run at a time on this machine; Server holds this lock from `with`
# to the end of the block (a lock older than 15 minutes is taken to be left over from a crash).
_LOCK = os.path.join(tempfile.gettempdir(), f"pearl-test-{PORT}.lock")


def _acquire_port():
    while True:
        try:
            fd = os.open(_LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(_LOCK) > 900:
                    os.remove(_LOCK)
                    continue
            except OSError:
                pass
            time.sleep(0.5)


def _release_port():
    try:
        os.remove(_LOCK)
    except OSError:
        pass


def _connect():
    for _ in range(300):
        try:
            return Client()
        except OSError:
            time.sleep(0.2)
    raise RuntimeError(f"gameserver did not start listening on {PORT}")


FIXTURE_AVATARS = [1310, 1415, 1501, 1303, 1001, 1224] + list(range(8001, 8011))
FIXTURE_BATTLE = {"battle_id": 1, "stage_id": 400101, "cycle_count": 30, "monster_wave": [[801201025, 801201025], [801201025]],
                  "monster_level": 30, "blessings": []}


def fixture_config(battle=None, avatars=FIXTURE_AVATARS):
    """A config.json with known avatars (every Trailblazer path) and battle; gear is copied from the repo's first avatar."""
    with open(os.path.join(pb.repo_root(), "config.json"), encoding="utf-8") as f:
        template = json.load(f)["avatar_config"][0]
    out = {"avatar_config": [], "battle_config": json.loads(json.dumps(battle or FIXTURE_BATTLE))}
    for avatar_id in avatars:
        a = json.loads(json.dumps(template))
        a["id"], a["name"] = avatar_id, str(avatar_id)
        out["avatar_config"].append(a)
    return out


class Server:
    """A gameserver in its own run dir: config.json (default fixture_config()), resources/ linked, state files from `files`."""

    def __init__(self, config=None, files=None, keep=False):
        self.dir = tempfile.mkdtemp(prefix="pearl-test-")
        root = pb.repo_root()
        if isinstance(config, str):
            shutil.copy(config, os.path.join(self.dir, "config.json"))
        else:
            self.write_json("config.json", config or fixture_config())
        subprocess.run(["cmd", "/c", "mklink", "/J", os.path.join(self.dir, "resources"),
                        os.path.join(root, "resources")], check=True, capture_output=True)
        for name, content in (files or {}).items():
            path = os.path.join(self.dir, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w" if isinstance(content, str) else "wb") as f:
                f.write(content)
        self.exe = os.environ.get("PEARL_EXE") or os.path.join(root, "zig-out", "bin", "gameserver.exe")
        self.keep = keep
        self.proc = None
        self.clients = []

    def path(self, name):
        return os.path.join(self.dir, name)

    def read_json(self, name):
        with open(self.path(name), encoding="utf-8") as f:
            return json.load(f)

    def write_json(self, name, value):
        with open(self.path(name), "w", encoding="utf-8") as f:
            json.dump(value, f, indent=2)

    def start(self):
        try:
            socket.create_connection((HOST, PORT), timeout=1).close()
            raise RuntimeError(f"something already listens on {PORT}; stop it or set PEARL_TEST_PORT")
        except OSError:
            pass
        self.log = open(self.path("gameserver.log"), "ab")
        env = dict(os.environ, PEARL_GAMESERVER_PORT=str(PORT))
        self.proc = subprocess.Popen([self.exe], cwd=self.dir, stdout=self.log, stderr=subprocess.STDOUT, env=env)
        return self

    def stop(self):
        for c in self.clients:
            try:
                c.close()
            except OSError:
                pass
        self.clients = []
        if self.proc:
            self.proc.kill()
            self.proc.wait()
            self.proc = None
            self.log.close()

    def restart(self):
        self.stop()
        return self.start()

    def connect(self):
        c = _connect()
        self.clients.append(c)
        return c

    def login(self):
        """Logs in again on a new connection; the server serves one connection at a time, so older ones are closed."""
        for old in self.clients:
            old.close()
        self.clients = []
        c = self.connect()
        c.call("PlayerGetTokenCsReq", {}, "PlayerGetTokenScRsp")
        c.call("PlayerLoginCsReq", {}, "PlayerLoginScRsp")
        c.call("PlayerLoginFinishCsReq", {}, "PlayerLoginFinishScRsp")
        return c

    def __enter__(self):
        _acquire_port()
        return self.start()

    def __exit__(self, *exc):
        self.stop()
        _release_port()
        if not self.keep:
            subprocess.run(["cmd", "/c", "rmdir", os.path.join(self.dir, "resources")], capture_output=True)
            shutil.rmtree(self.dir, ignore_errors=True)


# --- assertions -------------------------------------------------------------------------------------------------
_results = {"pass": 0, "fail": 0}


def check(label, cond, detail=""):
    if cond:
        _results["pass"] += 1
        print(f"  ok   {label}")
    else:
        _results["fail"] += 1
        print(f"  FAIL {label} {detail}")


def done():
    print(f"{_results['pass']} passed, {_results['fail']} failed")
    sys.exit(1 if _results["fail"] else 0)
