# March7thHoney chat commands + profile/world features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the March7thHoney features the user picked to MushiSR (pearl-sr-4.6.51): eight chat commands and the profile/world systems that today reset or go unanswered, plus real classic MoC/PF/AS and Anomaly Arbitration records.

**Architecture:** New logic lives in new files (`manager/profile_store.zig`, `override_mgr.zig`, `prefs_mgr.zig`, `record_mgr.zig`, `services/{pet,jukebox,college}.zig`, one `commands/*.zig` per command); existing handlers change only where they must read or save the new state. Everything the player picks is saved in small JSON files next to config.json (`profile.json`, `server_prefs.json`, `challenge.json`); in-memory overrides (`/calyx`, `/debug`) never touch challenge battles.

**Tech Stack:** Zig 0.14.1 (`G:\Cluade Code\HRSLOPRail\tools\zig-x86_64-windows-0.14.1\zig.exe`, below written `<zig>`), the generated `protocol/src/protocol.pb.zig`, Python 3.14 fake-client tests (no third-party packages).

**Spec:** `docs/superpowers/specs/2026-10-15-m7h-commands-profile-design.md` (read it with this plan; it is the requirement).

## Global Constraints

- Work in `G:\Cluade Code\HRSLOPRail\pearl-sr-4.6.51`, branch `local-4.6.51`. Do not push; the user decides about pushing.
- Never stage `config.json` or `hotfix.json` (user data, intentionally uncommitted). New user-data files/folders are untracked and added to `.git/info/exclude`: `configs/`, `lua/`, `challenge.json`, `challenge.json.bad`, `server_prefs.json`, `server_prefs.json.bad`, `profile.json.bad` (profile.json is already there).
- Commit as `git -c user.name=YourName -c user.email=you@example.com commit`; every message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
  ```
- `<zig>` and `"$ZIG"` (Parts B/C, Git Bash: `ZIG="G:/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe"`) are the same compiler.
- Most tracked `.zig` files are CRLF in the working tree (core.autocrlf=true). Apply before→after edits with the Edit tool, which matches and keeps the line endings; a sed/Python replace must handle `\r\n`. New files may be written with LF. Each "before" snippet in this plan matches exactly once in the state left by the previous tasks; if one does not, stop and report instead of guessing.
- Broken state files are copied (not moved) to `<name>.bad`, as `tierce_mgr.zig` and `preset_mgr.zig` already do (the spec's "ย้าย" means this).
- Build: `<zig> build` from the repo root → `zig-out/bin/gameserver.exe`. The first build after pulling dependencies can sit ~4.5 min with no CPU use; it finishes by itself — do not kill it. Before building, make sure the user's own gameserver is not running from `zig-out` (`tasklist | findstr gameserver`); if it is, ask the user to close it.
- Unit tests: `cd gameserver && <zig> build test --summary all`. Fake-client tests: `python tests/test_<name>.py` (or `python tests/run_all.py`) from the repo root, after building. Tests start their own gameserver in a temp folder on TCP 23301 and never touch the user's files. (The user may run March7thHoney on TCP 21000 + UDP 23301; that does not conflict.)
- Branding stays: chat bot / watermark / mail text "MushiSR", bot remark "ReversedRooms"; the default player nickname stays "ReversedRooms".
- Field and message names come from `protocol/src/protocol.pb.zig` / `protocol/src/root.zig` only; never copy field numbers from `Re/1.2.3-Features` protos (several messages have swapped tags).
- Ordinary-battle overrides (`/calyx`, `/debug`) never apply to MoC/PF/AS/Starward/AA battles (`ChallegeStageManager`).
- Anything without a saved challenge record keeps today's fake "all cleared" values (user decision).
- Code style: match the surrounding Zig (4-space indent, short comments that say why, same comment density); one command per `commands/<name>.zig`.

## Review Focus

1. Commands typed with odd casing, double spaces or the trailing NUL the client sometimes adds (`/CALYX  LineUp  1310\0`) must behave like the clean form — tested in Task 3.
2. An SRTools sync that removes an avatar a `/calyx lineup` uses must not send a missing avatar into battle — the team drops it (Task 3 test).
3. A `/debug` choice must not leak into a MoC/PF/AS battle and must still apply to the next ordinary battle after the challenge (Task 4 test).
4. `/peak` typed during an Anomaly Arbitration fight must not push season data mid-fight (Task 5 test).
5. A hand-edited `profile.json` with ids the client does not own (phone theme, pet, head icon) must fall back to defaults instead of sending them (Tasks 11, 12, 16 validate on read; their tests cover one bad id each).

---

## Part A: foundations and chat commands (Tasks 1–10)

### Task 1: Fake-client harness and unit test step

**Files:**
- Create: `tests/fakeclient/pb.py`, `tests/fakeclient/client.py`, `tests/run_all.py`, `tests/test_harness.py`, `gameserver/src/unit_tests.zig`
- Modify: `gameserver/build.zig` (add the `test` step)

**Interfaces:**
- Produces: `tests/fakeclient/client.py` API — `Server(config=None|dict|path, files={rel_path: text})` context manager (temp run dir, its own config.json = `fixture_config()` unless given, resources/ junction), `srv.login()` → `Client` (closes older connections: the server serves one at a time), `srv.restart()`, `srv.path(name)`, `srv.read_json(name)`, `srv.write_json(name, value)`; `Client.call(req, fields_dict, rsp)` → `(decoded rsp dict, [Packet])`, `Client.command(text)` → MushiSR reply lines (packets of that call in `c.last_packets`), `Packet.name`, `Packet.msg()`; helpers `check(label, cond, detail="")`, `done()`, `packets_named(packets, name)`, `chat_lines(packets)`, `fixture_config(battle=None, avatars=FIXTURE_AVATARS)`, constants `FIXTURE_AVATARS = [1310, 1415, 1501, 1303, 1001, 1224, 8001..8010]`, `FIXTURE_BATTLE` (stage 400101, level 30, waves `[[801201025, 801201025], [801201025]]`, cycle_count 30, no blessings).
- Produces: `gameserver/src/unit_tests.zig` — every later file with Zig `test` blocks gets a line `_ = @import("<path>");` inside its `test { }` block.

- [ ] **Step 1: Write the harness**

`tests/fakeclient/pb.py` (protobuf codec driven by protocol.pb.zig):

```python
"""Protobuf codec driven by the generated protocol/src/protocol.pb.zig.

Messages and fields are addressed by the names the Zig code uses, so tests read like the server code:
    body = encode("SetSignatureCsReq", {"signature": "hi"})
    msg = decode("SetSignatureScRsp", body)   # {"retcode": 0, "signature": "hi"}
"""
import os
import re
import struct

_STRUCT = re.compile(r"^(\s*)pub const (\w+) = struct \{")
_UNION = re.compile(r"^(\s*)pub const (\w+)_union = union\(")
_ENUM = re.compile(r"^(\s*)pub const (\w+) = enum\(i32\) \{")
_FIELD = re.compile(r"^\s+(\w+): ([^=,]+?)(?: = .*)?,$")
_DESC = re.compile(r"^\s+\.(\w+) = fd\((\d+|null), (.+)\),$")
_CLOSE = re.compile(r"^(\s*)\};")


class Field:
    def __init__(self, name, num, kind, type_name):
        self.name, self.num, self.kind, self.type_name = name, num, kind, type_name

    @property
    def repeated(self):
        return self.kind.startswith(".{ .List") or self.kind.startswith(".{ .PackedList")

    @property
    def is_message(self):
        return ".SubMessage" in self.kind

    def __repr__(self):
        return f"Field({self.name}={self.num} {self.kind} {self.type_name})"


class Message:
    def __init__(self, name):
        self.name = name
        self.types = {}  # field name -> declared Zig type
        self.fields = {}  # field name -> Field (oneof members included)
        self.by_num = {}


def _elem_type(t):
    t = t.strip().lstrip("?")
    m = re.match(r"ArrayList\((.+)\)$", t)
    if m:
        t = m.group(1)
    return t.strip()


class Schema:
    def __init__(self, path):
        self.messages = {}
        self.enums = set()
        stack = []  # (indent, kind, name)
        union_types = {}
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            m = _STRUCT.match(line)
            if m:
                parent = next((n for _, k, n in reversed(stack) if k == "struct"), None)
                name = f"{parent}.{m.group(2)}" if parent else m.group(2)
                self.messages[name] = Message(name)
                stack.append((len(m.group(1)), "struct", name))
                continue
            m = _UNION.match(line)
            if m:
                stack.append((len(m.group(1)), "union", m.group(2)))
                union_types[m.group(2)] = {}
                continue
            m = _ENUM.match(line)
            if m:
                self.enums.add(m.group(2))
                stack.append((len(m.group(1)), "enum", m.group(2)))
                continue
            m = _CLOSE.match(line)
            if m and stack and len(m.group(1)) == stack[-1][0]:
                stack.pop()
                continue
            if not stack:
                continue
            indent, kind, name = stack[-1]
            if kind == "enum":
                continue
            d = _DESC.match(line)
            if d:
                fname, num, fkind = d.group(1), d.group(2), d.group(3)
                if num == "null":
                    continue  # the oneof itself; its members come from the union's _union_desc
                if kind == "union":
                    owner = next(n for _, k, n in reversed(stack) if k == "struct")
                    t = union_types[name].get(fname, "")
                else:
                    owner = name
                    t = self.messages[owner].types.get(fname, "")
                msg = self.messages[owner]
                f = Field(fname, int(num), fkind, _elem_type(t))
                msg.fields[fname] = f
                msg.by_num[f.num] = f
                continue
            f = _FIELD.match(line)
            if f and not line.strip().startswith("pub "):
                if kind == "union":
                    union_types[name][f.group(1)] = f.group(2)
                elif kind == "struct" and len(line) - len(line.lstrip()) == indent + 4:
                    self.messages[name].types[f.group(1)] = f.group(2)

    def resolve(self, owner, type_name):
        """The message a field of `owner` refers to (nested names are looked up inside `owner` first)."""
        parts = owner.split(".")
        while parts:
            cand = ".".join(parts + [type_name])
            if cand in self.messages:
                return cand
            parts.pop()
        if type_name in self.messages:
            return type_name
        raise KeyError(f"{owner}: unknown message type {type_name}")


_schema = None


def repo_root():
    """pearl-sr-4.6.51; PEARL_ROOT overrides it (tests run from a copy of this folder)."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.environ.get("PEARL_ROOT") or os.path.join(here, "..", ".."))


def schema():
    global _schema
    if _schema is None:
        _schema = Schema(os.path.join(repo_root(), "protocol", "src", "protocol.pb.zig"))
    return _schema


# --- wire format ------------------------------------------------------------------------------------------------
def varint(n):
    if n < 0:
        n += 1 << 64
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | 0x80 if n else b)
        if not n:
            return bytes(out)


def read_varint(buf, i):
    n = shift = 0
    while True:
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return n, i


def _key(num, wt):
    return varint((num << 3) | wt)


def _scalar(f, v):
    """Encodes one non-message value of field `f` (without the key)."""
    k = f.kind
    if ".String" in k or ".Bytes" in k:
        data = v.encode("utf-8") if isinstance(v, str) else bytes(v)
        return 2, varint(len(data)) + data
    if ".FixedInt = .I32" in k:
        return 5, struct.pack("<f", v) if f.type_name == "f32" else struct.pack("<i", v)
    if ".FixedInt = .I64" in k:
        return 1, struct.pack("<d", v) if f.type_name == "f64" else struct.pack("<q", v)
    if ".ZigZagOptimized" in k:
        return 0, varint((v << 1) ^ (v >> 63))
    return 0, varint(int(v))


def encode(msg_name, values):
    s = schema()
    msg = s.messages[msg_name]
    out = bytearray()
    for name, v in values.items():
        f = msg.fields[name]
        items = v if f.repeated else [v]
        if f.is_message:
            sub = s.resolve(msg_name, f.type_name)
            for item in items:
                body = encode(sub, item)
                out += _key(f.num, 2) + varint(len(body)) + body
        elif f.kind.startswith(".{ .PackedList"):
            body = b"".join(_scalar(f, x)[1] for x in items)
            out += _key(f.num, 2) + varint(len(body)) + body
        else:
            for item in items:
                wt, data = _scalar(f, item)
                out += _key(f.num, wt) + data
    return bytes(out)


def _raw_fields(buf):
    i = 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        num, wt = key >> 3, key & 7
        if wt == 0:
            val, i = read_varint(buf, i)
        elif wt == 2:
            ln, i = read_varint(buf, i)
            val, i = bytes(buf[i:i + ln]), i + ln
        elif wt == 1:
            val, i = bytes(buf[i:i + 8]), i + 8
        elif wt == 5:
            val, i = bytes(buf[i:i + 4]), i + 4
        else:
            raise ValueError(f"wire type {wt}")
        yield num, wt, val


def _decode_scalar(f, wt, val):
    k = f.kind
    if ".String" in k:
        return val.decode("utf-8", "replace")
    if ".Bytes" in k:
        return val
    if wt == 5:
        return struct.unpack("<f" if f.type_name == "f32" else "<i", val)[0]
    if wt == 1:
        return struct.unpack("<d" if f.type_name == "f64" else "<q", val)[0]
    if ".ZigZagOptimized" in k:
        return (val >> 1) ^ -(val & 1)
    if f.type_name == "bool":
        return bool(val)
    return val


def decode(msg_name, buf):
    s = schema()
    msg = s.messages[msg_name]
    out = {}
    for num, wt, val in _raw_fields(buf):
        f = msg.by_num.get(num)
        if f is None:
            out.setdefault(f"_{num}", []).append(val)
            continue
        if f.is_message:
            v = decode(s.resolve(msg_name, f.type_name), val)
            vals = [v]
        elif wt == 2 and f.kind.startswith(".{ .PackedList"):
            vals, j = [], 0
            while j < len(val):
                x, j = read_varint(val, j)
                vals.append(_decode_scalar(f, 0, x))
        else:
            vals = [_decode_scalar(f, wt, val)]
        if f.repeated:
            out.setdefault(f.name, []).extend(vals)
        else:
            out[f.name] = vals[0]
    return out


def field_numbers(msg_name):
    """{field name: number}, handy when a test needs to hand-craft bytes."""
    return {n: f.num for n, f in schema().messages[msg_name].fields.items()}
```

`tests/fakeclient/client.py`:

```python
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

HOST, PORT = "127.0.0.1", 23301
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


# The gameserver always listens on 23301, so only one test may run at a time on this machine; Server holds this
# lock from `with` to the end of the block (a lock older than 15 minutes is taken to be left over from a crash).
_LOCK = os.path.join(tempfile.gettempdir(), "pearl-test-23301.lock")


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
    raise RuntimeError("gameserver did not start listening on 23301")


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
        self.log = open(self.path("gameserver.log"), "ab")
        self.proc = subprocess.Popen([self.exe], cwd=self.dir, stdout=self.log, stderr=subprocess.STDOUT)
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
```

`tests/run_all.py`:

```python
"""Runs every tests/test_*.py against zig-out/bin/gameserver.exe (build first). Exits 1 if any fails."""
import glob
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
failed = []
for path in sorted(glob.glob(os.path.join(here, "test_*.py"))):
    name = os.path.basename(path)
    print(f"=== {name}", flush=True)
    if subprocess.run([sys.executable, path]).returncode != 0:
        failed.append(name)
print("failed:", ", ".join(failed) if failed else "none")
sys.exit(1 if failed else 0)
```

- [ ] **Step 2: Write the harness's own test**

`tests/test_harness.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402
import pb  # noqa: E402

check("schema parsed", len(pb.schema().messages) > 4000)
body = pb.encode("SetSignatureCsReq", {"signature": "hi"})
check("round trip", pb.decode("SetSignatureCsReq", body) == {"signature": "hi"})

with Server() as srv:
    c = srv.login()
    check("/help answers", len(c.command("/help")) > 3)
    rsp, _ = c.call("GetPhoneDataCsReq", {}, "GetPhoneDataScRsp")
    check("nested lists decode", 220000 in rsp.get("owned_chat_bubbles", []), rsp)
    rsp, _ = c.call("GetPlayerBoardDataCsReq", {}, "GetPlayerBoardDataScRsp")
    check("sub-messages decode", rsp["display_avatar_vec"]["display_avatar_list"][0]["avatar_id"] > 0, rsp)
    srv.restart()
    c = srv.login()
    check("restart + login again", len(c.command("/help")) > 3)

done()
```

- [ ] **Step 3: Run it against the current build, expect PASS**

Run: `<zig> build` then `python tests/test_harness.py`
Expected: `6 passed, 0 failed` (it only exercises existing behaviour).

- [ ] **Step 4: Add the unit test step**

`gameserver/src/unit_tests.zig`:

```zig
// Every file with `test` blocks, so `zig build test` (run in gameserver/) finds them.
test {}
```

In `gameserver/build.zig`, replace

```zig
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

with

```zig
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` in gameserver/: the `test` blocks of the files listed in src/unit_tests.zig.
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/unit_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("protocol", protocol.module("protocol"));
    const test_step = b.step("test", "Run the unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}
```

- [ ] **Step 5: Run the unit test step, expect PASS**

Run: `cd gameserver && <zig> build test --summary all`
Expected: `Build Summary: 3/3 steps succeeded` (0 tests yet).

- [ ] **Step 6: Commit**

```bash
git add tests/fakeclient/pb.py tests/fakeclient/client.py tests/run_all.py tests/test_harness.py gameserver/src/unit_tests.zig gameserver/build.zig
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Add a fake-client test harness and a unit test step

tests/fakeclient drives a throwaway gameserver with messages encoded from
protocol.pb.zig by field name; `zig build test` in gameserver/ runs the
test blocks listed in src/unit_tests.zig.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 2: One profile.json store for every saved choice

**Files:**
- Create: `gameserver/src/manager/profile_store.zig`, `tests/test_profile_store.py`
- Modify: `gameserver/src/services/profile.zig` (Pom-Pom outfit reads/writes the store; its own load/save go away), `gameserver/src/main.zig`, `gameserver/src/unit_tests.zig`, `.git/info/exclude`

**Interfaces:**
- Produces (`manager/profile_store.zig`): `DisplayAvatar{avatar_id, pos}`, `MailState{read, deleted, taken: []const u32}`, `Profile` (fields `pam_skin, nickname, chat_bubble, phone_theme, phone_case, head_icon, personal_card, signature, display_avatars, assist_avatars, mail, pet, jukebox_track, peak_group, fake_date, college_finished` with the defaults shown in the file), `load()`, `get() *const Profile`, `set(comptime field, value)` (deep copy + atomic save), `save()`.

- [ ] **Step 1: Write the failing test**

`tests/test_profile_store.py`:

```python
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
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `<zig> build` then `python tests/test_profile_store.py`
Expected: FAIL on `profile.json holds every field` (today's file only has `pam_skin`) and on `and is kept as profile.json.bad`.

- [ ] **Step 3: Implement the store**

`gameserver/src/manager/profile_store.zig`:

```zig
const std = @import("std");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.profile);

const save_path = "profile.json";
const bad_path = "profile.json.bad";

pub const DisplayAvatar = struct { avatar_id: u32, pos: u32 };
pub const MailState = struct {
    read: []const u32 = &.{},
    deleted: []const u32 = &.{},
    taken: []const u32 = &.{},
};

// Everything the player picks in menus that should survive a restart. Each field defaults to what the server
// reported before it was saved, so an old profile.json (only pam_skin) or none at all changes nothing.
pub const Profile = struct {
    pam_skin: u32 = 252000,
    nickname: []const u8 = "ReversedRooms",
    chat_bubble: u32 = 0,
    phone_theme: u32 = 0,
    phone_case: u32 = 254001,
    head_icon: u32 = 0,
    personal_card: u32 = 253001,
    signature: []const u8 = "",
    display_avatars: []const DisplayAvatar = &.{},
    assist_avatars: []const u32 = &.{},
    mail: MailState = .{},
    pet: u32 = 0,
    jukebox_track: u32 = 0,
    peak_group: u32 = 0,
    fake_date: u32 = 0,
    college_finished: []const u32 = &.{},
};

// `current` and every slice in it live in `arena`; set() builds the next value in a fresh arena first.
var arena: ?std.heap.ArenaAllocator = null;
var current: Profile = .{};

pub fn get() *const Profile {
    return &current;
}

// Replaces one field and saves. The value is copied, so it may point into a request that is freed afterwards.
pub fn set(comptime field: []const u8, value: anytype) void {
    var next = current;
    @field(next, field) = value;
    adopt(next) catch |err| {
        log.err("{s} could not be changed: {s}", .{ field, @errorName(err) });
        return;
    };
    save();
}

fn adopt(value: Profile) !void {
    var next_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer next_arena.deinit();
    const copy = try dupe(next_arena.allocator(), value);
    if (arena) |*old| old.deinit();
    arena = next_arena;
    current = copy;
}

fn dupe(allocator: Allocator, value: anytype) !@TypeOf(value) {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size != .slice) @compileError("only slices are copied");
            const out = try allocator.alloc(p.child, value.len);
            for (value, out) |v, *o| o.* = try dupe(allocator, v);
            return out;
        },
        .@"struct" => |s| {
            var out: T = undefined;
            inline for (s.fields) |f| @field(out, f.name) = try dupe(allocator, @field(value, f.name));
            return out;
        },
        else => return value,
    }
}

// Loaded once at startup. A missing file is normal; a broken one is kept as profile.json.bad and the
// defaults are used.
pub fn load() void {
    loadFile() catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); using the defaults", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadFile() !void {
    const allocator = std.heap.page_allocator;
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, 1 << 20);
    defer allocator.free(bytes);
    const parsed = try parse(allocator, bytes);
    defer parsed.deinit();
    try adopt(parsed.value);
}
fn parse(allocator: Allocator, bytes: []const u8) !std.json.Parsed(Profile) {
    const parsed = try std.json.parseFromSlice(Profile, allocator, bytes, .{ .ignore_unknown_fields = true });
    errdefer parsed.deinit();
    if (!std.unicode.utf8ValidateSlice(parsed.value.nickname) or !std.unicode.utf8ValidateSlice(parsed.value.signature)) {
        return error.InvalidProfile;
    }
    return parsed;
}

// Written after every change; a failed write is logged and never drops the player.
pub fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    defer out.deinit();
    try std.json.stringify(current, .{ .whitespace = .indent_2 }, out.writer());
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(out.items);
    try file.finish();
}

test "an old profile.json with only the outfit keeps every other default" {
    const parsed = try parse(std.testing.allocator, "{\"pam_skin\": 252003}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 252003), parsed.value.pam_skin);
    try std.testing.expectEqualStrings("ReversedRooms", parsed.value.nickname);
    try std.testing.expectEqual(@as(u32, 254001), parsed.value.phone_case);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.display_avatars.len);
}

test "unknown fields are ignored and broken JSON is an error" {
    const parsed = try parse(std.testing.allocator, "{\"pet\": 1003, \"future_field\": [1, 2]}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1003), parsed.value.pet);
    try std.testing.expectError(error.UnexpectedEndOfInput, parse(std.testing.allocator, "{\"pet\": "));
}

test "dupe copies nested slices" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    var ids = [_]u32{ 1, 2 };
    const src = Profile{ .assist_avatars = &ids, .mail = .{ .read = &ids }, .signature = "hi" };
    const copy = try dupe(a.allocator(), src);
    ids[0] = 9;
    try std.testing.expectEqual(@as(u32, 1), copy.assist_avatars[0]);
    try std.testing.expectEqual(@as(u32, 1), copy.mail.read[0]);
    try std.testing.expectEqualStrings("hi", copy.signature);
}
```

In `gameserver/src/services/profile.zig`: add the import after `const Uid = @import("../utils/uid.zig");`

```zig
const ProfileStore = @import("../manager/profile_store.zig");
```

replace everything from `const pam_skins = [_]u32{ 252000, 252001, 252002, 252003, 252004 };` up to (not including) `pub fn onGetPamSkinData` (the `cur_pam_skin` var, `profile_path`, `SavedProfile`, `load`, `save`, `saveFile`) with

```zig
const pam_skins = [_]u32{ 252000, 252001, 252002, 252003, 252004 };

// The outfit survives restarts in profile.json; a saved one that is not in the list (a hand edit) shows the first.
fn curPamSkin() u32 {
    const saved = ProfileStore.get().pam_skin;
    return if (std.mem.indexOfScalar(u32, &pam_skins, saved) != null) saved else pam_skins[0];
}

```

then in `onGetPamSkinData` replace `rsp.cur_skin = cur_pam_skin;` with `rsp.cur_skin = curPamSkin();`, and in `onSelectPamSkin` replace

```zig
    if (req.pam_skin != cur_pam_skin and std.mem.indexOfScalar(u32, &pam_skins, req.pam_skin) != null) {
        cur_pam_skin = req.pam_skin;
        save();
    }
```

with

```zig
    if (req.pam_skin != curPamSkin() and std.mem.indexOfScalar(u32, &pam_skins, req.pam_skin) != null) {
        ProfileStore.set("pam_skin", req.pam_skin);
    }
```

and `.cur_skin = cur_pam_skin,` / `.set_skin = cur_pam_skin,` with `.cur_skin = curPamSkin(),` / `.set_skin = curPamSkin(),`. (`grep -n cur_pam_skin gameserver/src/services/profile.zig` must print nothing afterwards.)

In `gameserver/src/main.zig` replace `const Profile = @import("../src/services/profile.zig");` with `const ProfileStore = @import("../src/manager/profile_store.zig");` and `    Profile.load(allocator);` with `    ProfileStore.load();`.

In `gameserver/src/unit_tests.zig` replace `test {}` with

```zig
test {
    _ = @import("manager/profile_store.zig");
}
```

Append to `.git/info/exclude`:

```
profile.json.bad
```

- [ ] **Step 4: Build and test, expect PASS**

Run: `cd gameserver && <zig> build test --summary all` → `3/3 tests passed`; then from the repo root `<zig> build` and `python tests/test_profile_store.py` → `8 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/manager/profile_store.zig gameserver/src/services/profile.zig gameserver/src/main.zig gameserver/src/unit_tests.zig tests/test_profile_store.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Keep every saved profile choice in one profile.json store

The Pom-Pom outfit moves into manager/profile_store.zig, which holds all
the menu choices later commits save (phone, board, mail, pet, music, AA
season, server date). An old profile.json still loads; a broken one is
kept as profile.json.bad.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 3: `/calyx` — battle team and monster HP for ordinary battles

**Files:**
- Create: `gameserver/src/manager/override_mgr.zig` (lineup + HP part), `gameserver/src/commands/calyx.zig`, `tests/test_calyx.py`
- Modify: `gameserver/src/manager/battle_mgr.zig` (`currentTeam`, `applyHpOverrides`), `gameserver/src/manager/config_mgr.zig` (reload hook), `gameserver/src/services/login.zig` (login hook), `gameserver/src/command.zig`, `gameserver/src/commands/help.zig`

**Interfaces:**
- Produces (`override_mgr.zig`): `max_team = 4`, `Error`, `HpOverride{wave, index, monster_id, hp}`, `inConfig(id) bool`, `resolveAvatar(id) ?u32`, `setLineup(ids) Error!void`, `lineup() ?[]const u32`, `clearLineup()`, `setMonsterHp(wave, index, hp) Error!u32`, `hpOverrides() []const HpOverride`, `clearHp()`, `clearAll()`, `clearOnLogin()`, `onConfigReloaded()`.
- Produces (`battle_mgr.zig`): `pub const BattleTeam = struct { ids: []const u32, leader_slot: u32 }`, `pub fn currentTeam() BattleTeam` (/calyx team > /funmode > current preset).
- Command registration pattern used by Tasks 4–10: an import line inserted directly above `const CommandFn = *const fn` in `command.zig`, a `.{ .name = "...", .action = "", .func = ... },` line inserted directly above the `};` that closes `commandList` (the line before `\n\npub fn handleCommand`), and a help line inserted directly above `    try commandhandler.sendMessage(session, "You can enter MoC, PF, AS via F4 menu\n", allocator);` in `commands/help.zig`.

- [ ] **Step 1: Write the failing test**

`tests/test_calyx.py`:

```python
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import FIXTURE_AVATARS, Server, check, done, fixture_config  # noqa: E402


def cocoon(c):
    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")
    return rsp["battle_info"]


def team(battle):
    return [a["id"] for a in battle.get("battle_avatar_list", [])]


def hps(battle):
    return [[m.get("max_hp", 0) for m in w.get("monster_list", [])] for w in battle.get("monster_wave_list", [])]


def reload_config(srv, c, cfg):
    srv.write_json("config.json", cfg)
    time.sleep(1.2)  # the server looks at config.json at most once a second, on the next packet
    c.call("GetCurSceneInfoCsReq", {}, "GetCurSceneInfoScRsp")


with Server() as srv:
    c = srv.login()
    default_team = team(cocoon(c))
    check("a battle starts with the preset team", len(default_team) > 0, default_team)

    print("/calyx lineup")
    check("bad id is refused", "config.json" in " ".join(c.command("/calyx lineup 99999")))
    check("five avatars are refused", "at most 4" in " ".join(c.command("/calyx lineup 1310 1415 1501 1303 1001")))
    check("a duplicate base id is refused", "twice" in " ".join(c.command("/calyx lineup 1001 1224")))
    check("mixed case, double spaces and a trailing NUL are fine", "Calyx team set" in " ".join(c.command("/CALYX  LineUp  1310\x00")))
    lines = c.command("/calyx lineup 1501 8001")
    check("lineup accepted", "Calyx team set" in " ".join(lines), lines)
    b = cocoon(c)
    check("battle uses the Calyx team, 8001 = current Trailblazer path", team(b)[0] == 1501 and 8001 <= team(b)[1] <= 8010, team(b))

    print("/calyx modify")
    check("wave out of range", "no monster" in " ".join(c.command("/calyx modify 3 1 100")))
    check("hp 0 refused", "between 1" in " ".join(c.command("/calyx modify 1 1 0")))
    lines = c.command("/calyx modify 1 2 123456")
    check("hp set", "123456" in " ".join(lines), lines)
    b = cocoon(c)
    check("monster 2 of wave 1 has the HP", hps(b)[0][1] == 123456 and hps(b)[0][0] == 0, hps(b))
    status = " ".join(c.command("/calyx"))
    check("status lists team and HP", "1501" in status and "123456" in status, status)

    print("lifetimes")
    c = srv.login()
    b = cocoon(c)
    check("a new login drops the Calyx team", team(b) == default_team, team(b))
    check("but keeps HP changes", hps(b)[0][1] == 123456, hps(b))
    c.command("/calyx lineup 1310 1415")
    cfg = fixture_config(avatars=[a for a in FIXTURE_AVATARS if a != 1415])
    cfg["battle_config"]["monster_wave"] = [[801201025, 801201025, 801201025]]
    reload_config(srv, c, cfg)
    b = cocoon(c)
    check("a config.json reload clears HP changes", 123456 not in sum(hps(b), []), hps(b))
    check("and drops Calyx avatars config.json no longer has", team(b) == [1310], team(b))
    c.command("/calyx off")
    check("/calyx off clears the team", team(cocoon(c)) != [1310])

done()
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `python tests/test_calyx.py` → FAIL from `bad id is refused` on (`/calyx` is an "Invalid command").

- [ ] **Step 3: Implement**

`gameserver/src/manager/override_mgr.zig` (Task 4 appends the `/debug` part to this file):

```zig
const std = @import("std");
const ConfigManager = @import("config_mgr.zig");
const PresetManager = @import("preset_mgr.zig");

// What /calyx and /debug change about ordinary battles (Calyx, overworld monsters). Kept in memory only:
// a restart clears it. Challenge battles never read it.

const config = &ConfigManager.global_game_config_cache.game_config;

pub const max_team = 4;
pub const max_hp_overrides = 32;

pub const Error = error{ EmptyTeam, TooManyAvatars, UnknownAvatar, DuplicateAvatar, BadWave, BadIndex, BadHp, TooManyOverrides };

pub const HpOverride = struct { wave: u32, index: u32, monster_id: u32, hp: u32 };

var team_ids: [max_team]u32 = undefined;
var team_len: usize = 0;
var hp_list: [max_hp_overrides]HpOverride = undefined;
var hp_len: usize = 0;

pub fn inConfig(id: u32) bool {
    for (config.avatar_config.items) |avatar| {
        if (avatar.id == id) return true;
    }
    return false;
}

// The config.json avatar a typed id means: 8001 and 1001 follow the Trailblazer's and March 7th's selected path.
pub fn resolveAvatar(id: u32) ?u32 {
    const want = if (id == 8001 or id == 1001) PresetManager.pathId(id) else id;
    return if (inConfig(want)) want else null;
}

// --- /calyx lineup ---------------------------------------------------------------------------------------------
pub fn setLineup(ids: []const u32) Error!void {
    if (ids.len == 0) return error.EmptyTeam;
    if (ids.len > max_team) return error.TooManyAvatars;
    var resolved: [max_team]u32 = undefined;
    for (ids, 0..) |id, i| {
        const avatar = resolveAvatar(id) orelse return error.UnknownAvatar;
        for (resolved[0..i]) |prev| {
            if (PresetManager.baseId(prev) == PresetManager.baseId(avatar)) return error.DuplicateAvatar;
        }
        resolved[i] = avatar;
    }
    team_ids = resolved;
    team_len = ids.len;
}
pub fn lineup() ?[]const u32 {
    return if (team_len == 0) null else team_ids[0..team_len];
}
pub fn clearLineup() void {
    team_len = 0;
}

// --- /calyx modify ---------------------------------------------------------------------------------------------
// `wave` and `index` count from 1 over config.json's battle_config.monster_wave; returns the monster's id.
pub fn setMonsterHp(wave: u32, index: u32, hp: u32) Error!u32 {
    const waves = config.battle_config.monster_wave.items;
    if (wave == 0 or wave > waves.len) return error.BadWave;
    const monsters = waves[wave - 1].items;
    if (index == 0 or index > monsters.len) return error.BadIndex;
    if (hp == 0 or hp > std.math.maxInt(i32)) return error.BadHp;
    const monster_id = monsters[index - 1];
    for (hp_list[0..hp_len]) |*o| {
        if (o.wave == wave and o.index == index) {
            o.* = .{ .wave = wave, .index = index, .monster_id = monster_id, .hp = hp };
            return monster_id;
        }
    }
    if (hp_len == max_hp_overrides) return error.TooManyOverrides;
    hp_list[hp_len] = .{ .wave = wave, .index = index, .monster_id = monster_id, .hp = hp };
    hp_len += 1;
    return monster_id;
}
pub fn hpOverrides() []const HpOverride {
    return hp_list[0..hp_len];
}
pub fn clearHp() void {
    hp_len = 0;
}

// --- lifetimes -------------------------------------------------------------------------------------------------
pub fn clearAll() void {
    clearLineup();
    clearHp();
}
// A /calyx team lasts until the next login, as in March7thHoney.
pub fn clearOnLogin() void {
    clearLineup();
}
// HP overrides name a wave and slot of config.json's battle, which a reload may have changed; a /calyx team
// keeps only the avatars the new config.json still has (none left = the current team again).
pub fn onConfigReloaded() void {
    clearHp();
    var kept: usize = 0;
    for (team_ids[0..team_len]) |id| {
        if (!inConfig(id)) continue;
        team_ids[kept] = id;
        kept += 1;
    }
    team_len = kept;
}
```

`gameserver/src/commands/calyx.zig`:

```zig
const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const OverrideManager = @import("../manager/override_mgr.zig");

const Allocator = std.mem.Allocator;

const usage =
    \\/calyx lineup <avatar id> [avatar id...] - battle team for Calyx and overworld fights (8001/1001 = current path)
    \\/calyx lineup reset - back to the current team
    \\/calyx modify <wave> <monster> <hp> - HP of one config.json monster (wave and monster count from 1)
    \\/calyx off - clear the team and every HP change
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return status(session, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "lineup")) return lineup(session, &tokens, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "modify")) return modify(session, &tokens, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "off")) {
        OverrideManager.clearLineup();
        OverrideManager.clearHp();
        return commandhandler.sendMessage(session, "Calyx team and HP changes cleared.", allocator);
    }
    // March7thHoney switches to a cached freesr battle here; ours always fights config.json's battle.
    if (std.ascii.eqlIgnoreCase(mode, "on")) {
        return commandhandler.sendMessage(session, "Not needed here: Calyx always fights the config.json battle. Use /calyx lineup or /calyx modify.", allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn status(session: *Session, allocator: Allocator) !void {
    var text = std.ArrayList(u8).init(allocator);
    const w = text.writer();
    if (OverrideManager.lineup()) |ids| {
        try w.writeAll("Calyx team:");
        for (ids) |id| try w.print(" {d}", .{id});
    } else {
        try w.writeAll("Calyx team: current team");
    }
    const hps = OverrideManager.hpOverrides();
    if (hps.len == 0) try w.writeAll("\nHP changes: none");
    for (hps) |o| try w.print("\nWave {d} monster {d} ({d}): {d} HP", .{ o.wave, o.index, o.monster_id, o.hp });
    try commandhandler.sendMessage(session, text.items, allocator);
}

fn lineup(session: *Session, tokens: *std.mem.TokenIterator(u8, .any), allocator: Allocator) !void {
    const first = tokens.peek() orelse return commandhandler.sendMessage(session, usage, allocator);
    if (std.ascii.eqlIgnoreCase(first, "reset")) {
        OverrideManager.clearLineup();
        return commandhandler.sendMessage(session, "Calyx team cleared; battles use the current team.", allocator);
    }
    var ids: [OverrideManager.max_team + 1]u32 = undefined;
    var len: usize = 0;
    while (tokens.next()) |tok| {
        if (len == ids.len) break;
        ids[len] = std.fmt.parseInt(u32, tok, 10) catch {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "'{s}' is not an avatar id.", .{tok}), allocator);
        };
        len += 1;
    }
    OverrideManager.setLineup(ids[0..len]) catch |err| {
        const msg = switch (err) {
            error.TooManyAvatars => "A team has at most 4 avatars.",
            error.UnknownAvatar => "Every avatar must be in config.json (add it in SRTools first).",
            error.DuplicateAvatar => "An avatar is listed twice.",
            else => usage,
        };
        return commandhandler.sendMessage(session, msg, allocator);
    };
    var text = std.ArrayList(u8).init(allocator);
    try text.writer().writeAll("Calyx team set:");
    for (OverrideManager.lineup().?) |id| try text.writer().print(" {d}", .{id});
    try text.writer().writeAll(". It lasts until /calyx lineup reset or the next login.");
    try commandhandler.sendMessage(session, text.items, allocator);
}

fn modify(session: *Session, tokens: *std.mem.TokenIterator(u8, .any), allocator: Allocator) !void {
    var nums: [3]u32 = undefined;
    for (&nums) |*n| {
        const tok = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        n.* = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
    }
    const monster_id = OverrideManager.setMonsterHp(nums[0], nums[1], nums[2]) catch |err| {
        const msg = switch (err) {
            error.BadWave, error.BadIndex => try std.fmt.allocPrint(allocator, "config.json's battle has no monster {d} in wave {d}.", .{ nums[1], nums[0] }),
            error.BadHp => "HP must be between 1 and 2147483647.",
            error.TooManyOverrides => "Too many HP changes; use /calyx off first.",
            else => usage,
        };
        return commandhandler.sendMessage(session, msg, allocator);
    };
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Wave {d} monster {d} ({d}) now has {d} HP.", .{ nums[0], nums[1], monster_id, nums[2] }), allocator);
}
```

In `gameserver/src/manager/battle_mgr.zig` add after `const TierceManager = @import("tierce_mgr.zig");`

```zig
const OverrideManager = @import("override_mgr.zig");
```

and replace the whole `pub const BattleManager = struct { ... };` (from `pub const BattleManager = struct {` to the `};` before `// Cycles a challenge battle may last.`) with

```zig
pub const BattleTeam = struct { ids: []const u32, leader_slot: u32 };
var preset_team: PresetManager.Team = .{};

// Who fights an ordinary battle: a /calyx team, else /funmode's, else the current team preset.
pub fn currentTeam() BattleTeam {
    if (OverrideManager.lineup()) |ids| return .{ .ids = ids, .leader_slot = 0 };
    preset_team = PresetManager.curTeam();
    if (Logic.FunMode().FunMode()) return .{ .ids = funmodeAvatarID.items, .leader_slot = preset_team.leader_slot };
    return .{ .ids = preset_team.slice(), .leader_slot = preset_team.leader_slot };
}

// /calyx modify: per-monster HP on top of /funmode hp, for config.json's own waves only.
fn applyHpOverrides(battle: *protocol.SceneBattleInfo) void {
    for (OverrideManager.hpOverrides()) |o| {
        if (o.wave > battle.monster_wave_list.items.len) continue;
        const wave = &battle.monster_wave_list.items[o.wave - 1];
        if (o.index > wave.monster_list.items.len) continue;
        wave.monster_list.items[o.index - 1].max_hp = o.hp;
        wave.monster_list.items[o.index - 1].cur_hp = o.hp;
    }
}

pub const BattleManager = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) BattleManager {
        return BattleManager{ .allocator = allocator };
    }

    pub fn createBattle(self: *BattleManager) !protocol.SceneBattleInfo {
        var battle = createBattleInfo(
            self.allocator,
            config,
            @intCast(config.battle_config.monster_wave.items.len),
            config.battle_config.stage_id,
            config.battle_config.cycle_count,
        );

        // The team is read when the battle starts.
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            config.battle_config.monster_wave,
            config.battle_config.monster_level,
            config.battle_config.blessings.items,
        );
        applyHpOverrides(&battle);

        return battle;
    }
};
```

In `gameserver/src/manager/config_mgr.zig` add after `const AvatarManager = @import("../manager/avatar_mgr.zig");`

```zig
const OverrideManager = @import("override_mgr.zig");
```

and in `UpdateGameConfig` replace

```zig
    global_game_config_cache.game_config = fresh;
    selectConfiguredPaths();
}
```

with

```zig
    global_game_config_cache.game_config = fresh;
    selectConfiguredPaths();
    OverrideManager.onConfigReloaded();
}
```

In `gameserver/src/services/login.zig` add after `const ConfigManager = @import("../manager/config_mgr.zig");`

```zig
const OverrideManager = @import("../manager/override_mgr.zig");
```

and in `onPlayerLogin` replace `    Logic.Challenge().resetChallengeState();` with

```zig
    Logic.Challenge().resetChallengeState();
    OverrideManager.clearOnLogin();
```

Register (pattern above): import `const calyx_command = @import("./commands/calyx.zig");`, entry `    .{ .name = "calyx", .action = "", .func = calyx_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/calyx lineup|modify|off: battle team and monster HP for Calyx and overworld fights\n", allocator);
```

- [ ] **Step 4: Build and test, expect PASS**

Run: `<zig> build` then `python tests/test_calyx.py` → `17 passed, 0 failed`; `python tests/test_harness.py` still passes.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/manager/override_mgr.zig gameserver/src/commands/calyx.zig gameserver/src/manager/battle_mgr.zig gameserver/src/manager/config_mgr.zig gameserver/src/services/login.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_calyx.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Pick a Calyx battle team and monster HP from chat (/calyx)

/calyx lineup sets the team for Calyx and overworld battles until the
next login, /calyx modify sets one config.json monster's HP until
config.json is reloaded, /calyx off clears both. Challenge battles keep
their own teams.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 4: `/debug` — choose the next ordinary battle

**Files:**
- Create: `gameserver/src/commands/debug.zig`, `tests/test_debug.py`
- Modify: `gameserver/src/manager/override_mgr.zig` (append the next-battle part), `gameserver/src/manager/battle_mgr.zig` (`findStage`, `createStageBattle`, `createMonsterBattle`, `createBattle` honours the choice), `gameserver/src/services/battle.zig` (clear the choice where an ordinary battle starts), `command.zig`, `commands/help.zig`

**Interfaces:**
- Consumes: Task 3's `currentTeam()`, `override_mgr.zig`.
- Produces (`override_mgr.zig`): `max_wave_monsters = 5`, `NextBattle` union (`none | stage: u32 | monsters`), `findStage(stage_id) ?*const StageConfig.Stage`, `knownMonster(id) bool`, `setNextStage(stage_id) error{UnknownStage}!void`, `setNextMonsters(ids) Error!void`, `nextBattle() NextBattle`, `clearNextBattle()`.
- Produces (`battle_mgr.zig`): `pub const findStage = OverrideManager.findStage;`, `BattleManager.createStageBattle(self, stage: *const StageConfig.Stage) !protocol.SceneBattleInfo` (stage's waves/level/id, team from `currentTeam()`, no config.json blessings — Task 18's Battle College reuses it).

- [ ] **Step 1: Write the failing test**

`tests/test_debug.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402


def cocoon(c):
    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")
    return rsp["battle_info"]


def wave_sizes(battle):
    return [len(w.get("monster_list", [])) for w in battle.get("monster_wave_list", [])]


with Server() as srv:
    c = srv.login()
    check("status when nothing is picked", "config.json's" in " ".join(c.command("/debug")))
    check("unknown stage refused", "not in" in " ".join(c.command("/debug specific 1")))
    check("unknown monster refused", "Every monster" in " ".join(c.command("/debug monster 42")))
    check("six monsters refused", "At most 5" in " ".join(c.command("/debug monster 801201025 801201025 801201025 801201025 801201025 801201025")))

    c.command("/debug specific 400102")
    c.call("SceneCastSkillCsReq", {"attacked_by_entity_id": 1, "cast_entity_id": 1, "skill_index": 0}, "SceneCastSkillScRsp")
    check("a skill cast that hits nothing keeps the choice", "400102" in " ".join(c.command("/debug")))
    b = cocoon(c)
    check("next battle is stage 400102", b.get("stage_id") == 400102, b.get("stage_id"))
    check("with that stage's waves", wave_sizes(b) == [4], wave_sizes(b))
    check("only once: then config.json's stage", cocoon(c).get("stage_id") == 400101)

    c.command("/debug monster 801201025 801201025 801201025")
    b = cocoon(c)
    check("one wave of the picked monsters on config.json's stage", wave_sizes(b) == [3] and b.get("stage_id") == 400101, wave_sizes(b))

    c.command("/debug specific 400102")
    c.command("/debug off")
    check("/debug off cancels", cocoon(c).get("stage_id") == 400101)

    print("challenges ignore /debug")
    c.command("/debug specific 400102")
    lineup = [{"id": i, "avatar_type": 3} for i in (1310, 1415, 1501, 1303)]
    c.call("StartChallengeCsReq", {"challenge_id": 5612, "avatar_lineup_first": lineup, "avatar_lineup_second": lineup}, "StartChallengeScRsp")
    rsp, _ = c.call("SceneCastSkillCsReq", {"attacked_by_entity_id": 1, "cast_entity_id": 1, "skill_index": 1,
                                            "assist_monster_entity_id_list": [2000001]}, "SceneCastSkillScRsp")
    stage = rsp.get("battle_info", {}).get("stage_id")
    check("the MoC battle is MoC's stage", stage and stage != 400102, stage)
    c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")
    check("and the /debug choice waits for the next ordinary battle", cocoon(c).get("stage_id") == 400102)

done()
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `python tests/test_debug.py` → FAIL from `status when nothing is picked` on.

- [ ] **Step 3: Implement**

Append to `gameserver/src/manager/override_mgr.zig` the `/debug` section; first add `const StageConfig = @import("../data/stage_config.zig");` after `const PresetManager = @import("preset_mgr.zig");`, `const stages = &ConfigManager.global_game_config_cache.stage_config;` after `const config = &ConfigManager.global_game_config_cache.game_config;`, `pub const max_wave_monsters = 5;` after `pub const max_team = 4;`, extend `Error` with `, UnknownMonster, TooManyMonsters`, and add after `pub const HpOverride = ...;`

```zig
pub const NextBattle = union(enum) {
    none,
    stage: u32,
    monsters: struct { ids: [max_wave_monsters]u32 = undefined, len: usize = 0 },
};
```

and after `var hp_len: usize = 0;`

```zig
var next_battle: NextBattle = .none;
```

then insert before the `// --- lifetimes` section:

```zig
// --- /debug ----------------------------------------------------------------------------------------------------
pub fn findStage(stage_id: u32) ?*const StageConfig.Stage {
    for (stages.stage_config.items) |*stage| {
        if (stage.stage_id == stage_id) return stage;
    }
    return null;
}
// Monster ids some stage uses; any other id may not exist on the client, which then never loads the battle.
pub fn knownMonster(monster_id: u32) bool {
    for (stages.stage_config.items) |stage| {
        for (stage.monster_list.items) |wave| {
            if (std.mem.indexOfScalar(u32, wave.items, monster_id) != null) return true;
        }
    }
    return false;
}
pub fn setNextStage(stage_id: u32) error{UnknownStage}!void {
    if (findStage(stage_id) == null) return error.UnknownStage;
    next_battle = .{ .stage = stage_id };
}
pub fn setNextMonsters(ids: []const u32) Error!void {
    if (ids.len == 0) return error.UnknownMonster;
    if (ids.len > max_wave_monsters) return error.TooManyMonsters;
    var next: NextBattle = .{ .monsters = .{} };
    for (ids) |id| {
        if (!knownMonster(id)) return error.UnknownMonster;
        next.monsters.ids[next.monsters.len] = id;
        next.monsters.len += 1;
    }
    next_battle = next;
}
pub fn nextBattle() NextBattle {
    return next_battle;
}
// Called where an ordinary battle actually starts, so building one that is never fought keeps the choice.
pub fn clearNextBattle() void {
    next_battle = .none;
}
```

and make `clearAll` also call `clearNextBattle();`. The finished file must equal:

```zig
const std = @import("std");
const ConfigManager = @import("config_mgr.zig");
const PresetManager = @import("preset_mgr.zig");
const StageConfig = @import("../data/stage_config.zig");

// What /calyx and /debug change about ordinary battles (Calyx, overworld monsters). Kept in memory only:
// a restart clears it. Challenge battles never read it.

const config = &ConfigManager.global_game_config_cache.game_config;
const stages = &ConfigManager.global_game_config_cache.stage_config;

pub const max_team = 4;
pub const max_wave_monsters = 5;
pub const max_hp_overrides = 32;

pub const Error = error{ EmptyTeam, TooManyAvatars, UnknownAvatar, DuplicateAvatar, BadWave, BadIndex, BadHp, TooManyOverrides, UnknownMonster, TooManyMonsters };

pub const HpOverride = struct { wave: u32, index: u32, monster_id: u32, hp: u32 };

pub const NextBattle = union(enum) {
    none,
    stage: u32,
    monsters: struct { ids: [max_wave_monsters]u32 = undefined, len: usize = 0 },
};

var team_ids: [max_team]u32 = undefined;
var team_len: usize = 0;
var hp_list: [max_hp_overrides]HpOverride = undefined;
var hp_len: usize = 0;
var next_battle: NextBattle = .none;

pub fn inConfig(id: u32) bool {
    for (config.avatar_config.items) |avatar| {
        if (avatar.id == id) return true;
    }
    return false;
}

// The config.json avatar a typed id means: 8001 and 1001 follow the Trailblazer's and March 7th's selected path.
pub fn resolveAvatar(id: u32) ?u32 {
    const want = if (id == 8001 or id == 1001) PresetManager.pathId(id) else id;
    return if (inConfig(want)) want else null;
}

// --- /calyx lineup ---------------------------------------------------------------------------------------------
pub fn setLineup(ids: []const u32) Error!void {
    if (ids.len == 0) return error.EmptyTeam;
    if (ids.len > max_team) return error.TooManyAvatars;
    var resolved: [max_team]u32 = undefined;
    for (ids, 0..) |id, i| {
        const avatar = resolveAvatar(id) orelse return error.UnknownAvatar;
        for (resolved[0..i]) |prev| {
            if (PresetManager.baseId(prev) == PresetManager.baseId(avatar)) return error.DuplicateAvatar;
        }
        resolved[i] = avatar;
    }
    team_ids = resolved;
    team_len = ids.len;
}
pub fn lineup() ?[]const u32 {
    return if (team_len == 0) null else team_ids[0..team_len];
}
pub fn clearLineup() void {
    team_len = 0;
}

// --- /calyx modify ---------------------------------------------------------------------------------------------
// `wave` and `index` count from 1 over config.json's battle_config.monster_wave; returns the monster's id.
pub fn setMonsterHp(wave: u32, index: u32, hp: u32) Error!u32 {
    const waves = config.battle_config.monster_wave.items;
    if (wave == 0 or wave > waves.len) return error.BadWave;
    const monsters = waves[wave - 1].items;
    if (index == 0 or index > monsters.len) return error.BadIndex;
    if (hp == 0 or hp > std.math.maxInt(i32)) return error.BadHp;
    const monster_id = monsters[index - 1];
    for (hp_list[0..hp_len]) |*o| {
        if (o.wave == wave and o.index == index) {
            o.* = .{ .wave = wave, .index = index, .monster_id = monster_id, .hp = hp };
            return monster_id;
        }
    }
    if (hp_len == max_hp_overrides) return error.TooManyOverrides;
    hp_list[hp_len] = .{ .wave = wave, .index = index, .monster_id = monster_id, .hp = hp };
    hp_len += 1;
    return monster_id;
}
pub fn hpOverrides() []const HpOverride {
    return hp_list[0..hp_len];
}
pub fn clearHp() void {
    hp_len = 0;
}

// --- /debug ----------------------------------------------------------------------------------------------------
pub fn findStage(stage_id: u32) ?*const StageConfig.Stage {
    for (stages.stage_config.items) |*stage| {
        if (stage.stage_id == stage_id) return stage;
    }
    return null;
}
// Monster ids some stage uses; any other id may not exist on the client, which then never loads the battle.
pub fn knownMonster(monster_id: u32) bool {
    for (stages.stage_config.items) |stage| {
        for (stage.monster_list.items) |wave| {
            if (std.mem.indexOfScalar(u32, wave.items, monster_id) != null) return true;
        }
    }
    return false;
}
pub fn setNextStage(stage_id: u32) error{UnknownStage}!void {
    if (findStage(stage_id) == null) return error.UnknownStage;
    next_battle = .{ .stage = stage_id };
}
pub fn setNextMonsters(ids: []const u32) Error!void {
    if (ids.len == 0) return error.UnknownMonster;
    if (ids.len > max_wave_monsters) return error.TooManyMonsters;
    var next: NextBattle = .{ .monsters = .{} };
    for (ids) |id| {
        if (!knownMonster(id)) return error.UnknownMonster;
        next.monsters.ids[next.monsters.len] = id;
        next.monsters.len += 1;
    }
    next_battle = next;
}
pub fn nextBattle() NextBattle {
    return next_battle;
}
// Called where an ordinary battle actually starts, so building one that is never fought keeps the choice.
pub fn clearNextBattle() void {
    next_battle = .none;
}

// --- lifetimes -------------------------------------------------------------------------------------------------
pub fn clearAll() void {
    clearLineup();
    clearHp();
    clearNextBattle();
}
// A /calyx team lasts until the next login, as in March7thHoney.
pub fn clearOnLogin() void {
    clearLineup();
}
// HP overrides name a wave and slot of config.json's battle, which a reload may have changed; a /calyx team
// keeps only the avatars the new config.json still has (none left = the current team again).
pub fn onConfigReloaded() void {
    clearHp();
    var kept: usize = 0;
    for (team_ids[0..team_len]) |id| {
        if (!inConfig(id)) continue;
        team_ids[kept] = id;
        kept += 1;
    }
    team_len = kept;
}
```

`gameserver/src/commands/debug.zig`:

```zig
const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const OverrideManager = @import("../manager/override_mgr.zig");

const Allocator = std.mem.Allocator;

const usage =
    \\/debug specific <stage id> - the next Calyx/overworld battle is that stage (resources/StageConfig.json)
    \\/debug monster <monster id> [monster id...] - the next battle is one wave of these (at most 5)
    \\/debug off - cancel
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return status(session, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "off")) {
        OverrideManager.clearNextBattle();
        return commandhandler.sendMessage(session, "Next battle is config.json's again.", allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "specific")) {
        const tok = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        const stage_id = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
        OverrideManager.setNextStage(stage_id) catch {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Stage {d} is not in resources/StageConfig.json.", .{stage_id}), allocator);
        };
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "The next battle is stage {d}.", .{stage_id}), allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "monster")) {
        var ids: [OverrideManager.max_wave_monsters + 1]u32 = undefined;
        var len: usize = 0;
        while (tokens.next()) |tok| {
            if (len == ids.len) break;
            ids[len] = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
            len += 1;
        }
        OverrideManager.setNextMonsters(ids[0..len]) catch |err| {
            const msg = switch (err) {
                error.TooManyMonsters => "At most 5 monsters.",
                else => "Every monster must appear in some stage of resources/StageConfig.json.",
            };
            return commandhandler.sendMessage(session, msg, allocator);
        };
        return commandhandler.sendMessage(session, "The next battle is one wave of those monsters.", allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn status(session: *Session, allocator: Allocator) !void {
    const text = switch (OverrideManager.nextBattle()) {
        .none => "Next battle: config.json's.",
        .stage => |id| try std.fmt.allocPrint(allocator, "Next battle: stage {d}.", .{id}),
        .monsters => |m| blk: {
            var list = std.ArrayList(u8).init(allocator);
            try list.writer().writeAll("Next battle: monsters");
            for (m.ids[0..m.len]) |id| try list.writer().print(" {d}", .{id});
            break :blk list.items;
        },
    };
    try commandhandler.sendMessage(session, text, allocator);
}
```

In `gameserver/src/manager/battle_mgr.zig` add `const StageConfig = @import("../data/stage_config.zig");` after the `OverrideManager` import; add `pub const findStage = OverrideManager.findStage;` after `currentTeam`; in `createBattle` insert at the top of the function body

```zig
        switch (OverrideManager.nextBattle()) {
            .stage => |stage_id| if (findStage(stage_id)) |stage| return self.createStageBattle(stage),
            .monsters => |m| return self.createMonsterBattle(m.ids[0..m.len]),
            .none => {},
        }
```

(and change its comment to `// An ordinary battle: config.json's, unless /debug picked the next one.`), and add after `createBattle` inside `BattleManager`:

```zig
    // A stage from resources/StageConfig.json as it is: its waves and level, none of config.json's blessings.
    pub fn createStageBattle(self: *BattleManager, stage: *const StageConfig.Stage) !protocol.SceneBattleInfo {
        var battle = createBattleInfo(
            self.allocator,
            config,
            @intCast(stage.monster_list.items.len),
            stage.stage_id,
            config.battle_config.cycle_count,
        );
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            stage.monster_list,
            stage.level,
            &.{},
        );
        return battle;
    }

    // config.json's stage, level and blessings with one wave of the given monsters (/debug monster).
    fn createMonsterBattle(self: *BattleManager, monster_ids: []const u32) !protocol.SceneBattleInfo {
        var wave = std.ArrayList(u32).init(self.allocator);
        try wave.appendSlice(monster_ids);
        var waves = std.ArrayList(std.ArrayList(u32)).init(self.allocator);
        try waves.append(wave);
        var battle = createBattleInfo(self.allocator, config, 1, config.battle_config.stage_id, config.battle_config.cycle_count);
        const team = currentTeam();
        try commonBattleSetup(
            self.allocator,
            &battle,
            team.ids,
            team.leader_slot,
            config.avatar_config.items,
            waves,
            config.battle_config.monster_level,
            config.battle_config.blessings.items,
        );
        return battle;
    }
```

In `gameserver/src/services/battle.zig` add `const OverrideManager = @import("../manager/override_mgr.zig");` after `const ChallengeService = @import("challenge.zig");`, and add the line `OverrideManager.clearNextBattle();` directly after `on_battle = true;` in `onStartCocoonStage`, `onQuickStartCocoonStage`, `onQuickStartFarmElement` and in `onSceneCastSkill`'s non-challenge branch (after `battle_info = battle;\n                    on_battle = true;`). Not in `onStartBattleCollege` (it does not use the choice).

Register: import `const debug_command = @import("./commands/debug.zig");`, entry `    .{ .name = "debug", .action = "", .func = debug_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/debug specific <stage> or /debug monster <id...>: pick the next battle\n", allocator);
```

- [ ] **Step 4: Build and test, expect PASS**

Run: `<zig> build`, `python tests/test_debug.py` → `12 passed, 0 failed`; `python tests/test_calyx.py` still `17 passed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/manager/override_mgr.zig gameserver/src/commands/debug.zig gameserver/src/manager/battle_mgr.zig gameserver/src/services/battle.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_debug.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Pick the next ordinary battle from chat (/debug)

/debug specific <stage> fights a StageConfig.json stage next, /debug
monster <ids> one wave of known monsters; the choice is used once, by the
next Calyx or overworld battle, and never by a challenge.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 5: `/peak` — Anomaly Arbitration season from chat

**Files:**
- Create: `gameserver/src/commands/peak.zig`, `tests/test_peak.py`
- Modify: `gameserver/src/services/challenge.zig` (`currentPeakGroupId` honours the saved season and becomes `pub`; new `pushPeakData`), `command.zig`, `commands/help.zig`

**Interfaces:**
- Consumes: `ProfileStore.get().peak_group`, `ProfileStore.set("peak_group", id)`.
- Produces (`services/challenge.zig`): `pub fn currentPeakGroupId() u32`, `pub fn pushPeakData(session, allocator) !void` (sends GetChallengePeakDataScRsp + a ChallengePeakGroupDataUpdateScNotify unasked). Task 20 keeps both names and keeps `onGetChallengePeakData` not reading its packet.

- [ ] **Step 1: Write the failing test**

`tests/test_peak.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402


def peak_group(c):
    return c.call("GetChallengePeakDataCsReq", {}, "GetChallengePeakDataScRsp")[0].get("current_peak_group_id")


with Server() as srv:
    c = srv.login()
    auto = peak_group(c)
    check("automatic season is the newest", auto == 11, auto)
    lines = c.command("/peak")
    check("status lists the seasons", "Seasons: 1 2 3" in " ".join(lines), lines)
    check("unknown season refused", "No season 99" in " ".join(c.command("/peak 99")))
    lines = c.command("/peak 3")
    pushed = packets_named(c.last_packets, "GetChallengePeakDataScRsp")
    check("the data is pushed with the new season", pushed and pushed[0].msg().get("current_peak_group_id") == 3, lines)
    check("and a group update", packets_named(c.last_packets, "ChallengePeakGroupDataUpdateScNotify"))
    check("query answers season 3", peak_group(c) == 3)
    srv.restart()
    c = srv.login()
    check("season survives a restart", peak_group(c) == 3)
    c.command("/peak 0")
    check("/peak 0 is automatic again", peak_group(c) == auto)

    print("during a fight")
    c.call("StartChallengePeakCsReq", {"peak_id": 1101, "peak_avatar_id_list": [1310, 1415, 1501, 1303]}, "StartChallengePeakScRsp")
    lines = c.command("/peak 2")
    check("the season changes after the fight", "after this challenge" in " ".join(lines), lines)
    check("nothing is pushed mid-fight", not packets_named(c.last_packets, "GetChallengePeakDataScRsp"))
    c.call("LeaveChallengePeakCsReq", {}, "LeaveChallengePeakScRsp")
    check("after leaving the query answers season 2", peak_group(c) == 2)

done()
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `python tests/test_peak.py` → FAIL from `status lists the seasons` on.

- [ ] **Step 3: Implement**

In `gameserver/src/services/challenge.zig` add `const ProfileStore = @import("../manager/profile_store.zig");` after `const TierceManager = @import("../manager/tierce_mgr.zig");`, replace

```zig
// The Anomaly Arbitration season the client shows (banner and boss). SRTools' AA picker saves the picked node's
// stage, or the boss's hard-mode stage, as battle_config.stage_id; any other pick gets the newest season.
// The client asks only at login, so a new pick shows after logging in again.
fn currentPeakGroupId() u32 {
    const groups = peak_group.challenge_peak_group.items;
    if (groups.len == 0) return 0;
```

with

```zig
// The Anomaly Arbitration season the client shows (banner and boss): the one /peak chose, else the one SRTools'
// AA picker points at (it saves the picked node's stage, or the boss's hard-mode stage, as battle_config.stage_id),
// else the newest. The client asks only at login; /peak pushes the data again (pushPeakData).
pub fn currentPeakGroupId() u32 {
    const groups = peak_group.challenge_peak_group.items;
    if (groups.len == 0) return 0;
    const chosen = ProfileStore.get().peak_group;
    for (groups) |*group| {
        if (chosen != 0 and group.id == chosen) return chosen;
    }
```

and insert directly above `pub fn onGetCurChallengePeak(`:

```zig
// Sends GetChallengePeakDataScRsp unasked, as March7thHoney's /peak does; the handler never reads its packet.
pub fn pushPeakData(session: *Session, allocator: Allocator) !void {
    try onGetChallengePeakData(session, undefined, allocator);
    var update = protocol.ChallengePeakGroup.init(allocator);
    update.peak_group_id = currentPeakGroupId();
    update.count_of_peaks = 3;
    update.obtained_stars = 9;
    try session.send(CmdID.CmdChallengePeakGroupDataUpdateScNotify, protocol.ChallengePeakGroupDataUpdateScNotify{
        .challenge_peak_group = update,
    });
}
```

`gameserver/src/commands/peak.zig`:

```zig
const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const ChallengeService = @import("../services/challenge.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;

const groups = &ConfigManager.global_game_config_cache.challenge_peak_group_config.challenge_peak_group;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    const arg = std.mem.trim(u8, args, commandhandler.whitespace);
    if (arg.len == 0) {
        const how = if (ProfileStore.get().peak_group != 0) "chosen with /peak" else "from SRTools or the newest";
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Anomaly Arbitration season {d} ({s}). Seasons: {s}. /peak 0 = automatic.", .{ ChallengeService.currentPeakGroupId(), how, try seasonList(allocator) }), allocator);
    }
    const group_id = std.fmt.parseInt(u32, arg, 10) catch return commandhandler.sendMessage(session, "Usage: /peak <season>, /peak 0 = automatic", allocator);
    if (group_id != 0 and !hasGroup(group_id)) {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "No season {d}. Seasons: {s}.", .{ group_id, try seasonList(allocator) }), allocator);
    }
    ProfileStore.set("peak_group", group_id);
    const now = ChallengeService.currentPeakGroupId();
    // A fight in progress keeps its season; the menus pick up the new one after it.
    if (Logic.Challenge().ChallengeMode()) {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Season {d} after this challenge.", .{now}), allocator);
    }
    try ChallengeService.pushPeakData(session, allocator);
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Anomaly Arbitration season {d}. If the banner did not change, log in again.", .{now}), allocator);
}

fn hasGroup(id: u32) bool {
    for (groups.items) |group| {
        if (group.id == id) return true;
    }
    return false;
}

fn seasonList(allocator: Allocator) ![]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    for (groups.items, 0..) |group, i| {
        if (i > 0) try text.appendSlice(" ");
        try text.writer().print("{d}", .{group.id});
    }
    return text.items;
}
```

Register: import `const peak_command = @import("./commands/peak.zig");`, entry `    .{ .name = "peak", .action = "", .func = peak_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/peak <season>: Anomaly Arbitration season (0 = automatic)\n", allocator);
```

- [ ] **Step 4: Build and test, expect PASS**

Run: `<zig> build`, `python tests/test_peak.py` → `11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/commands/peak.zig gameserver/src/services/challenge.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_peak.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Pick the Anomaly Arbitration season from chat (/peak)

The season is saved in profile.json and wins over the SRTools pick; the
season data is pushed again right away, except during an AA fight.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 6: `/faketime` — server date from chat

**Files:**
- Create: `gameserver/src/commands/faketime.zig`, `tests/test_faketime.py`
- Modify: `gameserver/src/utils/clock.zig` (whole file below), `gameserver/src/unit_tests.zig`, `command.zig`, `commands/help.zig`

**Interfaces:**
- Consumes: `ProfileStore.get().fake_date`, `ProfileStore.set("fake_date", yyyymmdd)`.
- Produces (`utils/clock.zig`): `parseDate(text) ?u32`, `dateStartMs(yyyymmdd) ?i64` (noon UTC+8), `resetAtLogin()` now also applies the saved date; `nowMs`/`nowSec` unchanged.

- [ ] **Step 1: Write the failing tests**

`tests/test_faketime.py`:

```python
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402

NOON_20260920 = 1789876800000  # 2026-09-20 12:00 UTC+8


def server_ms(c):
    rsp, _ = c.call("PlayerHeartBeatCsReq", {"client_time_ms": 1}, "PlayerHeartBeatScRsp")
    return rsp["server_time_ms"]


with Server() as srv:
    c = srv.login()
    check("real time by default", abs(server_ms(c) - time.time() * 1000) < 60000)
    check("bad date refused", "Usage" in " ".join(c.command("/faketime 2026-02-30")))
    lines = c.command("/faketime 20260920")
    check("date set", "2026-09-20 12:00" in " ".join(lines), lines)
    check("heartbeat reports that day from noon UTC+8", 0 <= server_ms(c) - NOON_20260920 < 60000, server_ms(c))
    srv.restart()
    c = srv.login()
    check("still set after a restart", 0 <= server_ms(c) - NOON_20260920 < 60000)
    rsp, _ = c.call("PlayerLoginCsReq", {}, "PlayerLoginScRsp")
    check("login reports it too", 0 <= rsp["server_timestamp_ms"] - NOON_20260920 < 60000, rsp.get("server_timestamp_ms"))
    c.command("/faketime off")
    check("off = real time", abs(server_ms(c) - time.time() * 1000) < 60000)

done()
```

The Zig unit tests are at the end of the new `clock.zig` below (`dates parse in both forms...`, `a date starts at noon UTC+8`).

- [ ] **Step 2: Run, expect FAIL**

Run: `python tests/test_faketime.py` → FAIL from `bad date refused` on.

- [ ] **Step 3: Implement**

`gameserver/src/utils/clock.zig` becomes:

```zig
const std = @import("std");
const ProfileStore = @import("../manager/profile_store.zig");

// The time the server reports to the client. The client checks the MoC/PF/AS schedules in its own design data
// against it, so once the schedules of the client version in use have closed, those modes show "Locked".
// /faketime fixes that from the game: each login restarts the reported clock at noon UTC+8 of the chosen day.
// A window (start, end) does the same at build time: once the real clock is past `end`, each login restarts the
// reported clock at `start` and lets it run from there; before it, the real time is used.
// 4.5.54 needed 2026-09-20 00:00 UTC .. 2026-09-24 20:00 UTC (its MoC 1035/1036, PF 2026/2027 and AS 3020/3021
// closed at 2026-09-25 04:00 UTC+8). 4.6.51 came out on 2026-09-29 and runs on the real time (as CapySR does);
// its closing dates are not known here. If MoC/PF/AS show "Locked" later, use /faketime or set a window.
const Window = struct { start_ms: i64, end_ms: i64 };
const window: ?Window = null;

var offset_ms: i64 = 0;

pub fn resetAtLogin() void {
    const now = std.time.milliTimestamp();
    if (dateStartMs(ProfileStore.get().fake_date)) |start| {
        offset_ms = now - start;
        return;
    }
    offset_ms = 0;
    const w = window orelse return;
    if (now >= w.end_ms) offset_ms = now - w.start_ms;
}

// Unix milliseconds as the client should see them.
pub fn nowMs() u64 {
    return @intCast(@max(0, std.time.milliTimestamp() - offset_ms));
}
// Unix seconds, for protocol fields in seconds.
pub fn nowSec() u64 {
    return nowMs() / std.time.ms_per_s;
}

// "20260920" or "2026-09-20" as 20260920, if it is a real day in 2023..2099.
pub fn parseDate(text: []const u8) ?u32 {
    var digits: [8]u8 = undefined;
    switch (text.len) {
        8 => @memcpy(&digits, text),
        10 => {
            if (text[4] != '-' or text[7] != '-') return null;
            @memcpy(digits[0..4], text[0..4]);
            @memcpy(digits[4..6], text[5..7]);
            @memcpy(digits[6..8], text[8..10]);
        },
        else => return null,
    }
    const date = std.fmt.parseInt(u32, &digits, 10) catch return null;
    return if (dateStartMs(date) != null) date else null;
}

// Noon UTC+8 of yyyymmdd in Unix milliseconds. The schedules open at 04:00 UTC+8, so midnight would still be
// before the first day of one.
pub fn dateStartMs(date: u32) ?i64 {
    const year = date / 10000;
    const month = date / 100 % 100;
    const day = date % 100;
    if (year < 2023 or year > 2099 or month < 1 or month > 12 or day < 1) return null;
    if (day > daysInMonth(year, month)) return null;
    var days: i64 = 0;
    var y: u32 = 1970;
    while (y < year) : (y += 1) days += std.time.epoch.getDaysInYear(@intCast(y));
    var m: u32 = 1;
    while (m < month) : (m += 1) days += daysInMonth(year, m);
    days += day - 1;
    return (days * std.time.s_per_day + 4 * std.time.s_per_hour) * std.time.ms_per_s;
}

fn daysInMonth(year: u32, month: u32) u32 {
    const leap: std.time.epoch.YearLeapKind = if (std.time.epoch.isLeapYear(@intCast(year))) .leap else .not_leap;
    return std.time.epoch.getDaysInMonth(leap, @enumFromInt(month));
}

test "dates parse in both forms and only when they exist" {
    try std.testing.expectEqual(@as(?u32, 20260920), parseDate("20260920"));
    try std.testing.expectEqual(@as(?u32, 20260920), parseDate("2026-09-20"));
    try std.testing.expectEqual(@as(?u32, 20240229), parseDate("2024-02-29"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("2026-02-29"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("2026-13-01"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("1999-01-01"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("2026/09/20"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("today"));
}

test "a date starts at noon UTC+8" {
    try std.testing.expectEqual(@as(?i64, 1789876800000), dateStartMs(20260920));
    try std.testing.expectEqual(@as(?i64, 1709179200000), dateStartMs(20240229));
    try std.testing.expectEqual(@as(?i64, null), dateStartMs(0));
}
```

`gameserver/src/commands/faketime.zig`:

```zig
const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const Clock = @import("../utils/clock.zig");

const Allocator = std.mem.Allocator;

const usage = "Usage: /faketime <YYYYMMDD or YYYY-MM-DD>, /faketime off";

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    const arg = std.mem.trim(u8, args, commandhandler.whitespace);
    if (arg.len == 0) {
        const date = ProfileStore.get().fake_date;
        if (date == 0) return commandhandler.sendMessage(session, "Server time: real time. " ++ usage, allocator);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Server time starts at {d:0>4}-{d:0>2}-{d:0>2} 12:00 (UTC+8) at every login.", .{ date / 10000, date / 100 % 100, date % 100 }), allocator);
    }
    if (std.ascii.eqlIgnoreCase(arg, "off")) {
        ProfileStore.set("fake_date", 0);
        Clock.resetAtLogin();
        return commandhandler.sendMessage(session, "Server time is the real time again. Log in again so the challenge menus read it.", allocator);
    }
    const date = Clock.parseDate(arg) orelse return commandhandler.sendMessage(session, usage ++ " (a real day in 2023-2099)", allocator);
    ProfileStore.set("fake_date", date);
    Clock.resetAtLogin();
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Server time now starts at {d:0>4}-{d:0>2}-{d:0>2} 12:00 (UTC+8) at every login. Log in again so the challenge menus read it.", .{ date / 10000, date / 100 % 100, date % 100 }), allocator);
}
```

Add `    _ = @import("utils/clock.zig");` to `gameserver/src/unit_tests.zig`. Register: import `const faketime_command = @import("./commands/faketime.zig");`, entry `    .{ .name = "faketime", .action = "", .func = faketime_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/faketime <YYYYMMDD>|off: server date, for challenges that show Locked\n", allocator);
```

- [ ] **Step 4: Build and test, expect PASS**

Run: `cd gameserver && <zig> build test --summary all` (5 tests), then `<zig> build` and `python tests/test_faketime.py` → `7 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/utils/clock.zig gameserver/src/commands/faketime.zig gameserver/src/unit_tests.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_faketime.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Set the server date from chat (/faketime)

/faketime <date> makes every login start the reported clock at noon
UTC+8 of that day (MoC/PF/AS schedules open at 04:00), saved in
profile.json; /faketime off returns to the real time.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 7: `/hero` — Trailblazer gender and path

**Files:**
- Create: `gameserver/src/commands/hero.zig`, `tests/test_hero.py`
- Modify: `command.zig`, `commands/help.zig`

**Interfaces:**
- Consumes: `OverrideManager.inConfig(id)`, `AvatarManager.mc_id`, `AvatarManager.gender`, `AvatarManager.syncAvatarData`, `LineupManager.LineupManager.createLineup`.

- [ ] **Step 1: Write the failing test**

`tests/test_hero.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config, packets_named  # noqa: E402


def changed(c):
    notes = packets_named(c.last_packets, "AvatarPathChangedNotify")
    return notes[0].msg().get("cur_multi_path_avatar_type") if notes else None


with Server() as srv:
    c = srv.login()
    check("bad gender refused", "/hero gender" in " ".join(c.command("/hero gender 3")))
    check("bad path refused", "/hero type" in " ".join(c.command("/hero type 9000")))
    c.command("/hero gender 1")
    check("gender 1 picks the male Trailblazer of the same path", changed(c) == 8009, changed(c))
    rsp, _ = c.call("GetBasicInfoCsReq", {}, "GetBasicInfoScRsp")
    check("basic info says male", rsp.get("gender") == 1, rsp)
    c.command("/hero type 8004")
    check("type keeps the gender", changed(c) == 8003, changed(c))
    check("lineup is resent", packets_named(c.last_packets, "SyncLineupNotify"))

no_8004 = [a for a in range(8001, 8011) if a != 8004] + [1310]
with Server(config=fixture_config(avatars=no_8004)) as srv:
    c = srv.login()
    c.command("/hero gender 1")
    c.command("/hero type 8003")
    check("now male Preservation", changed(c) == 8003, changed(c))
    lines = c.command("/hero gender 2")
    check("a Trailblazer config.json lacks is refused", "config.json has no 8004" in " ".join(lines), lines)

done()
```

- [ ] **Step 2: Run, expect FAIL** — `python tests/test_hero.py` fails from `bad gender refused` on.

- [ ] **Step 3: Implement**

`gameserver/src/commands/hero.zig`:

```zig
const std = @import("std");
const protocol = @import("protocol");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const OverrideManager = @import("../manager/override_mgr.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const usage =
    \\/hero gender <1 male | 2 female> - same path, other Trailblazer
    \\/hero type <8001 Destruction | 8003 Preservation | 8005 Harmony | 8007 Remembrance | 8009 Elation> - same gender
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
    const value = std.fmt.parseInt(u32, tokens.next() orelse "", 10) catch return commandhandler.sendMessage(session, usage, allocator);
    // Trailblazer ids come in pairs per path: odd male, even female.
    const target: u32 = if (std.ascii.eqlIgnoreCase(mode, "gender")) blk: {
        if (value != 1 and value != 2) return commandhandler.sendMessage(session, usage, allocator);
        break :blk pathBase(AvatarManager.mc_id) + value - 1;
    } else if (std.ascii.eqlIgnoreCase(mode, "type")) blk: {
        if (value < 8001 or value > 8010) return commandhandler.sendMessage(session, usage, allocator);
        break :blk pathBase(value) + AvatarManager.gender - 1;
    } else return commandhandler.sendMessage(session, usage, allocator);

    if (!OverrideManager.inConfig(target)) {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "config.json has no {d}; add that Trailblazer in SRTools first.", .{target}), allocator);
    }
    AvatarManager.mc_id = target;
    AvatarManager.gender = if (target % 2 == 0) 2 else 1;

    // What the in-game path switch (services/avatar.zig onSetAvatarPath) sends.
    var change = protocol.AvatarPathChangedNotify.init(allocator);
    change.base_avatar_id = 8001;
    change.cur_multi_path_avatar_type = @enumFromInt(target);
    try session.send(CmdID.CmdAvatarPathChangedNotify, change);
    try AvatarManager.syncAvatarData(session, allocator);
    var lineup = protocol.SyncLineupNotify.init(allocator);
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    lineup.lineup = try lineup_mgr.createLineup();
    try session.send(CmdID.CmdSyncLineupNotify, lineup);
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Trailblazer is now {d}. If the model did not change, log in again.", .{target}), allocator);
}

fn pathBase(id: u32) u32 {
    return id - (id - 8001) % 2;
}
```

Register: import `const hero_command = @import("./commands/hero.zig");`, entry `    .{ .name = "hero", .action = "", .func = hero_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/hero gender <1|2> or /hero type <8001..8009>: Trailblazer\n", allocator);
```

- [ ] **Step 4: Build and test** — `<zig> build`, `python tests/test_hero.py` → `8 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/commands/hero.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_hero.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Switch the Trailblazer's gender and path from chat (/hero)

Sends what the in-game path switch sends; the Trailblazer picked must be
in config.json.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 8: `/scene` — where the party is, reload and change scenes

**Files:**
- Create: `gameserver/src/commands/scene.zig`, `tests/test_scene.py`
- Modify: `gameserver/src/manager/scene_mgr.zig` (track plane/entry; `entryFloorId` becomes pub; new `entryPlaneId`, `location`, `nearbyGroups`), `command.zig`, `commands/help.zig`

**Interfaces:**
- Produces (`scene_mgr.zig`): `pub fn entryFloorId(entry_id) u32`, `pub fn entryPlaneId(entry_id) u32`, `pub const Location = struct { plane_id, floor_id, entry_id: u32, pos: protocol.Vector, pos_known: bool }`, `pub fn location() Location`, `pub const GroupSummary = struct { group_id: u32, props: u32, monsters: u32, nearest_m: f64 }`, `pub fn nearbyGroups(allocator) ![]GroupSummary` (nearest first).

- [ ] **Step 1: Write the failing test**

`tests/test_scene.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

with Server() as srv:
    c = srv.login()
    check("before any scene", "No scene" in " ".join(c.command("/scene cur")))
    c.call("GetCurSceneInfoCsReq", {}, "GetCurSceneInfoScRsp")
    lines = c.command("/scene cur")
    check("cur shows the login scene", "entry 2050301" in " ".join(lines), lines)
    c.call("SceneEntityMoveCsReq", {"entity_motion_list": [{"entity_id": 101310, "motion": {"pos": {"x": 1500, "y": 0, "z": -2500}}}]},
           "SceneEntityMoveScRsp")
    lines = c.command("/scene cur")
    check("cur shows the last position in metres", "1.5 0.0 -2.5" in " ".join(lines), lines)
    lines = c.command("/scene group")
    check("group lists groups with distances", lines and lines[0].startswith("Group ") and " m" in lines[0], lines)
    check("unknown entry refused", "not in MapEntrance" in " ".join(c.command("/scene change 42")))
    c.command("/scene change 1000001")
    enter = packets_named(c.last_packets, "EnterSceneByServerScNotify")
    scene = enter[0].msg()["scene"] if enter else {}
    check("change enters the entry on its own plane", scene.get("entry_id") == 1000001 and scene.get("plane_id") == 10000, scene.get("plane_id"))
    check("with the entry's props", sum(len(g.get("entity_list", [])) for g in scene.get("entity_group_list", [])) > 5)
    c.command("/scene reload")
    enter = packets_named(c.last_packets, "EnterSceneByServerScNotify")
    check("reload enters the same entry", enter and enter[0].msg()["scene"].get("entry_id") == 1000001)
    check("cur follows", "entry 1000001" in " ".join(c.command("/scene cur")))

done()
```

- [ ] **Step 2: Run, expect FAIL** — `python tests/test_scene.py` fails from `before any scene` on.

- [ ] **Step 3: Implement**

In `gameserver/src/manager/scene_mgr.zig` replace

```zig
var party_floor_id: u32 = 0;
var party_pos: protocol.Vector = .{};
```

with

```zig
var party_floor_id: u32 = 0;
var party_plane_id: u32 = 0;
var party_entry_id: u32 = 0;
var party_pos: protocol.Vector = .{};
```

replace the `fn entryFloorId` function with

```zig
pub fn entryFloorId(entry_id: u32) u32 {
    for (map_entrance_config.map_entrance_config.items) |entrConf| {
        if (entrConf.id == entry_id) return entrConf.floor_id;
    }
    return 0;
}
pub fn entryPlaneId(entry_id: u32) u32 {
    for (map_entrance_config.map_entrance_config.items) |entrConf| {
        if (entrConf.id == entry_id) return entrConf.plane_id;
    }
    return 0;
}

// Where the party is, for /scene.
pub const Location = struct { plane_id: u32, floor_id: u32, entry_id: u32, pos: protocol.Vector, pos_known: bool };
pub fn location() Location {
    return .{ .plane_id = party_plane_id, .floor_id = party_floor_id, .entry_id = party_entry_id, .pos = party_pos, .pos_known = party_motion_known };
}

// A res.json group of the current entry, with the distance from the party to its nearest prop, monster or teleport.
pub const GroupSummary = struct { group_id: u32, props: u32 = 0, monsters: u32 = 0, nearest_m: f64 = std.math.inf(f64) };
pub fn nearbyGroups(allocator: Allocator) ![]GroupSummary {
    var map = std.AutoArrayHashMap(u32, GroupSummary).init(allocator);
    for (res_config.scene_config.items) |sceneConf| {
        if (sceneConf.entryID != party_entry_id) continue;
        for (sceneConf.props.items) |p| (try groupEntry(&map, p.groupId, p.pos)).props += 1;
        for (sceneConf.monsters.items) |m| (try groupEntry(&map, m.groupId, m.pos)).monsters += 1;
        for (sceneConf.teleports.items) |t| _ = try groupEntry(&map, t.groupId, t.pos);
    }
    const groups = map.values();
    std.mem.sort(GroupSummary, groups, {}, struct {
        fn lessThan(_: void, a: GroupSummary, b: GroupSummary) bool {
            return a.nearest_m < b.nearest_m;
        }
    }.lessThan);
    return groups;
}
fn groupEntry(map: *std.AutoArrayHashMap(u32, GroupSummary), group_id: u32, pos: anytype) !*GroupSummary {
    const slot = try map.getOrPut(group_id);
    if (!slot.found_existing) slot.value_ptr.* = .{ .group_id = group_id };
    const dx: f64 = @floatFromInt(@as(i64, pos.x) - party_pos.x);
    const dy: f64 = @floatFromInt(@as(i64, pos.y) - party_pos.y);
    const dz: f64 = @floatFromInt(@as(i64, pos.z) - party_pos.z);
    slot.value_ptr.nearest_m = @min(slot.value_ptr.nearest_m, @sqrt(dx * dx + dy * dy + dz * dz) / 1000);
    return slot.value_ptr;
}
```

and in `SceneManager.createScene` replace

```zig
        party_floor_id = if (floor_id != 0) floor_id else entryFloorId(entry_id);
        party_pos = .{};
```

with

```zig
        party_floor_id = if (floor_id != 0) floor_id else entryFloorId(entry_id);
        party_plane_id = plane_id;
        party_entry_id = entry_id;
        party_pos = .{};
```

`gameserver/src/commands/scene.zig`:

```zig
const std = @import("std");
const protocol = @import("protocol");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const SceneManager = @import("../manager/scene_mgr.zig");
const LineupManager = @import("../manager/lineup_mgr.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const usage =
    \\/scene cur - plane, floor, entry and position
    \\/scene group - the 10 res.json groups nearest to the party
    \\/scene reload - enter the current scene again, at its spawn point
    \\/scene change <entry id> - go to an entry (MapEntrance)
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
    const here = SceneManager.location();
    if (std.ascii.eqlIgnoreCase(mode, "cur")) {
        if (here.entry_id == 0) return commandhandler.sendMessage(session, "No scene entered yet.", allocator);
        var text = std.ArrayList(u8).init(allocator);
        try text.writer().print("Plane {d}, floor {d}, entry {d}.", .{ here.plane_id, here.floor_id, here.entry_id });
        if (here.pos_known) {
            try text.writer().print(" Position {d:.1} {d:.1} {d:.1} m.", .{ metres(here.pos.x), metres(here.pos.y), metres(here.pos.z) });
        } else {
            try text.writer().writeAll(" Position unknown until you move.");
        }
        return commandhandler.sendMessage(session, text.items, allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "group")) {
        const groups = try SceneManager.nearbyGroups(allocator);
        if (groups.len == 0) return commandhandler.sendMessage(session, "res.json has no groups for this scene.", allocator);
        var text = std.ArrayList(u8).init(allocator);
        for (groups[0..@min(groups.len, 10)], 0..) |g, i| {
            if (i > 0) try text.append('\n');
            try text.writer().print("Group {d}: {d} props, {d} monsters, {d:.0} m", .{ g.group_id, g.props, g.monsters, g.nearest_m });
        }
        return commandhandler.sendMessage(session, text.items, allocator);
    }
    if (Logic.Challenge().ChallengeMode()) return commandhandler.sendMessage(session, "Leave the challenge first.", allocator);
    if (std.ascii.eqlIgnoreCase(mode, "reload")) {
        if (here.entry_id == 0) return commandhandler.sendMessage(session, "No scene entered yet.", allocator);
        try enter(session, here.entry_id, allocator);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entry {d} reloaded.", .{here.entry_id}), allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "change")) {
        const tok = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        const entry_id = std.fmt.parseInt(u32, tok, 10) catch return commandhandler.sendMessage(session, usage, allocator);
        if (SceneManager.entryPlaneId(entry_id) == 0) {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entry {d} is not in MapEntrance.", .{entry_id}), allocator);
        }
        try enter(session, entry_id, allocator);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Entering entry {d}.", .{entry_id}), allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn metres(mm: i32) f64 {
    return @as(f64, @floatFromInt(mm)) / 1000;
}

// Like /tp, but with the entry's own plane and floor, so the scene gets its props and monsters.
fn enter(session: *Session, entry_id: u32, allocator: Allocator) !void {
    var scene_manager = SceneManager.SceneManager.init(allocator);
    const scene_info = try scene_manager.createScene(SceneManager.entryPlaneId(entry_id), SceneManager.entryFloorId(entry_id), entry_id, 0);
    var lineup_mgr = LineupManager.LineupManager.init(allocator);
    const lineup = try lineup_mgr.createLineup();
    try session.send(CmdID.CmdEnterSceneByServerScNotify, protocol.EnterSceneByServerScNotify{
        .reason = protocol.EnterSceneReason.ENTER_SCENE_REASON_NONE,
        .lineup = lineup,
        .scene = scene_info,
    });
}
```

Register: import `const scene_command = @import("./commands/scene.zig");`, entry `    .{ .name = "scene", .action = "", .func = scene_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/scene cur|group|reload|change <entry>\n", allocator);
```

- [ ] **Step 4: Build and test** — `<zig> build`, `python tests/test_scene.py` → `9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/manager/scene_mgr.zig gameserver/src/commands/scene.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_scene.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Show where the party is and change scenes from chat (/scene)

/scene cur and /scene group report the entry, position and the nearest
res.json groups; /scene reload and /scene change enter an entry on its
own plane and floor, so its props and monsters come along.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 9: `/windy` — send Lua from the lua folder

**Files:**
- Create: `gameserver/src/commands/windy.zig`, `tests/test_windy.py`
- Modify: `gameserver/src/services/misc.zig` (script queue on the heartbeat), `gameserver/src/services/login.zig` (clear at login), `gameserver/src/unit_tests.zig`, `command.zig`, `commands/help.zig`, `.git/info/exclude`

**Interfaces:**
- Produces (`services/misc.zig`): `max_lua_queue = 8`, `queueLua(name, text) !void` (error.QueueFull), `sentLua() []const []const u8`, `clearLua()`.

- [ ] **Step 1: Write the failing test**

`tests/test_windy.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done  # noqa: E402


def heartbeat_data(c):
    rsp, _ = c.call("PlayerHeartBeatCsReq", {"client_time_ms": 1}, "PlayerHeartBeatScRsp")
    return rsp["download_data"]["data"]


with Server() as srv:
    c = srv.login()
    check("no lua folder", "Create a lua folder" in " ".join(c.command("/windy")))

files = {"lua/b.lua": "print('b')", "lua/a.lua": "print('a')", "lua/notes.txt": "x", "lua/big.lua": "--" + "x" * 70000}
with Server(files=files) as srv:
    c = srv.login()
    lines = c.command("/windy")
    check("lists .lua files sorted", lines and lines[0].splitlines() == ["1. a.lua", "2. b.lua", "3. big.lua"], lines)
    check("a path outside lua/ is refused", "No script" in " ".join(c.command("/windy ../config.json")))
    check("a number past the list is refused", "No script" in " ".join(c.command("/windy 9")))
    check("over 64 KB refused", "64 KB" in " ".join(c.command("/windy big")))
    check("by name without .lua", "Sending b.lua" in " ".join(c.command("/windy b")))
    check("by number", "Sending a.lua" in " ".join(c.command("/windy load 1")))
    check("heartbeat 1 carries b.lua", heartbeat_data(c) == b"print('b')")
    check("heartbeat 2 carries a.lua", heartbeat_data(c) == b"print('a')")
    check("then the watermark again", b"setTextComponent" in heartbeat_data(c))
    check("loaded lists both", "b.lua, a.lua" in " ".join(c.command("/windy loaded")))
    c = srv.login()
    check("a new login starts a new list", "No script sent" in " ".join(c.command("/windy loaded")))

done()
```

(The Zig unit test `only listed scripts can be picked` is at the end of `windy.zig` below.)

- [ ] **Step 2: Run, expect FAIL** — `python tests/test_windy.py` fails from `no lua folder` on.

- [ ] **Step 3: Implement**

In `gameserver/src/services/misc.zig` replace

```zig
pub fn onPlayerHeartBeat(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.PlayerHeartBeatCsReq, allocator);
    defer req.deinit();
    const dest_buf = try allocator.dupe(u8, script);
```

with

```zig
// Scripts /windy queued, each sent on one heartbeat instead of the watermark (which the next heartbeat restores),
// and the names of those sent since the last login.
pub const max_lua_queue = 8;
var lua_queue = std.ArrayList([]u8).init(std.heap.page_allocator);
var lua_sent = std.ArrayList([]u8).init(std.heap.page_allocator);

pub fn queueLua(name: []const u8, text: []const u8) !void {
    if (lua_queue.items.len >= max_lua_queue) return error.QueueFull;
    const owned = try std.heap.page_allocator.dupe(u8, text);
    errdefer std.heap.page_allocator.free(owned);
    const owned_name = try std.heap.page_allocator.dupe(u8, name);
    errdefer std.heap.page_allocator.free(owned_name);
    try lua_queue.append(owned);
    try lua_sent.append(owned_name);
}
pub fn sentLua() []const []const u8 {
    return lua_sent.items;
}
pub fn clearLua() void {
    for (lua_queue.items) |s| std.heap.page_allocator.free(s);
    for (lua_sent.items) |s| std.heap.page_allocator.free(s);
    lua_queue.clearRetainingCapacity();
    lua_sent.clearRetainingCapacity();
}

pub fn onPlayerHeartBeat(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.PlayerHeartBeatCsReq, allocator);
    defer req.deinit();
    const queued: ?[]u8 = if (lua_queue.items.len > 0) lua_queue.orderedRemove(0) else null;
    defer if (queued) |q| std.heap.page_allocator.free(q);
    const dest_buf = try allocator.dupe(u8, queued orelse script);
```

In `gameserver/src/services/login.zig` add `const Misc = @import("misc.zig");` after the `OverrideManager` import and `    Misc.clearLua();` after `    OverrideManager.clearOnLogin();`.

`gameserver/src/commands/windy.zig`:

```zig
const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const Misc = @import("../services/misc.zig");

const Allocator = std.mem.Allocator;

const lua_dir = "lua";
const max_script_size = 64 * 1024;

const usage =
    \\/windy - list the .lua files in the lua folder
    \\/windy <number or name> - send that script to the game (with the next heartbeat)
    \\/windy loaded - scripts sent since this login
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    var arg = tokens.next() orelse "list";
    if (std.ascii.eqlIgnoreCase(arg, "load")) arg = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
    if (std.ascii.eqlIgnoreCase(arg, "loaded")) {
        const sent = Misc.sentLua();
        if (sent.len == 0) return commandhandler.sendMessage(session, "No script sent since this login.", allocator);
        const text = try std.mem.join(allocator, ", ", sent);
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Sent since this login: {s}", .{text}), allocator);
    }
    const files = listScripts(allocator) catch |err| switch (err) {
        error.FileNotFound => return commandhandler.sendMessage(session, "Create a lua folder next to config.json and put .lua files in it.", allocator),
        else => return err,
    };
    if (std.ascii.eqlIgnoreCase(arg, "list")) {
        if (files.len == 0) return commandhandler.sendMessage(session, "The lua folder has no .lua files.", allocator);
        var text = std.ArrayList(u8).init(allocator);
        for (files, 1..) |name, i| {
            if (i > 1) try text.append('\n');
            try text.writer().print("{d}. {s}", .{ i, name });
        }
        return commandhandler.sendMessage(session, text.items, allocator);
    }
    const name = pick(files, arg, allocator) catch {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "No script '{s}' in the lua folder (see /windy).", .{arg}), allocator);
    };
    var dir = try std.fs.cwd().openDir(lua_dir, .{});
    defer dir.close();
    const text = dir.readFileAlloc(allocator, name, max_script_size) catch |err| switch (err) {
        error.FileTooBig => return commandhandler.sendMessage(session, "Scripts may be at most 64 KB.", allocator),
        else => return err,
    };
    Misc.queueLua(name, text) catch {
        return commandhandler.sendMessage(session, "Too many scripts waiting; try again in a few seconds.", allocator);
    };
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Sending {s} with the next heartbeat.", .{name}), allocator);
}

// The .lua files directly in lua/, sorted by name.
fn listScripts(allocator: Allocator) ![]const []const u8 {
    var dir = try std.fs.cwd().openDir(lua_dir, .{ .iterate = true });
    defer dir.close();
    var names = std.ArrayList([]const u8).init(allocator);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.ascii.endsWithIgnoreCase(entry.name, ".lua")) continue;
        try names.append(try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.lessThan);
    return names.items;
}

// A number from the list, or a listed file name (".lua" may be left out). Only listed names are accepted, so a
// path such as ../config.json can never be read.
fn pick(files: []const []const u8, arg: []const u8, allocator: Allocator) ![]const u8 {
    if (std.fmt.parseInt(usize, arg, 10)) |n| {
        if (n >= 1 and n <= files.len) return files[n - 1];
        return error.NotFound;
    } else |_| {}
    const want = if (std.ascii.endsWithIgnoreCase(arg, ".lua")) arg else try std.fmt.allocPrint(allocator, "{s}.lua", .{arg});
    for (files) |name| {
        if (std.ascii.eqlIgnoreCase(name, want)) return name;
    }
    return error.NotFound;
}

test "only listed scripts can be picked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_][]const u8{ "a.lua", "Watermark.lua" };
    try std.testing.expectEqualStrings("a.lua", try pick(&files, "1", a));
    try std.testing.expectEqualStrings("Watermark.lua", try pick(&files, "watermark", a));
    try std.testing.expectError(error.NotFound, pick(&files, "3", a));
    try std.testing.expectError(error.NotFound, pick(&files, "../config.json", a));
    try std.testing.expectError(error.NotFound, pick(&files, "0", a));
}
```

Add `    _ = @import("commands/windy.zig");` to `unit_tests.zig`; append `lua/` to `.git/info/exclude`. Register: import `const windy_command = @import("./commands/windy.zig");`, entry `    .{ .name = "windy", .action = "", .func = windy_command.handle },`, help line

```zig
    try commandhandler.sendMessage(session, "/windy: send a script from the lua folder. /json: save and load configs\n", allocator);
```

- [ ] **Step 4: Build and test** — `cd gameserver && <zig> build test --summary all` (6 tests), `<zig> build`, `python tests/test_windy.py` → `12 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/commands/windy.zig gameserver/src/services/misc.zig gameserver/src/services/login.zig gameserver/src/unit_tests.zig gameserver/src/command.zig gameserver/src/commands/help.zig tests/test_windy.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Send Lua scripts from the lua folder to the game (/windy)

A picked script goes out on the next heartbeat in place of the watermark,
the same way the watermark reaches the client; only .lua files listed in
lua/ can be picked, at most 64 KB each.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 10: `/json` — save and switch config.json setups

**Files:**
- Create: `gameserver/src/commands/json.zig`, `tests/test_json.py`
- Modify: `gameserver/src/unit_tests.zig`, `command.zig`, `.git/info/exclude` (help line already added in Task 9)

**Interfaces:**
- Consumes: `ConfigManager.loadConfig`, `GameConfig.parseConfig`, `sync_command.applyConfig(session, allocator)`, `Battle.on_battle`.

- [ ] **Step 1: Write the failing test**

`tests/test_json.py`:

```python
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config, packets_named  # noqa: E402


def battle_team(c):
    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")
    return [a["id"] for a in rsp["battle_info"]["battle_avatar_list"]]


with Server() as srv:
    c = srv.login()
    check("nothing saved yet", "No saved configs" in " ".join(c.command("/json")))
    check("bad name refused", "Names are" in " ".join(c.command("/json export ../x")))
    check("export", "configs/full.json" in " ".join(c.command("/json export full")))
    check("no overwrite without force", "exists" in " ".join(c.command("/json export full")))
    check("force overwrites", "saved as" in " ".join(c.command("/json export full force")))
    small = fixture_config(avatars=[1310, 1415, 8010])
    srv.write_json("configs/small.json", small)
    with open(srv.path("configs/broken.json"), "w") as f:
        f.write("{")
    lines = c.command("/json list")
    check("list is sorted", lines and lines[0].splitlines() == ["1. broken", "2. full", "3. small"], lines)
    with open(srv.path("config.json"), encoding="utf-8") as f:
        before = f.read()
    check("a broken config is refused", "not a valid config" in " ".join(c.command("/json load broken")))
    with open(srv.path("config.json"), encoding="utf-8") as f:
        check("and config.json is untouched", f.read() == before)
    lines = c.command("/json load 3")
    check("load by number", "Loaded configs/small.json" in " ".join(lines), lines)
    check("config.json is now small.json", srv.read_json("config.json") == small)
    check("the old one is backed up", any(n.endswith("-before-json-load.json") for n in os.listdir(srv.path("config-backups"))))
    check("avatars are resynced", packets_named(c.last_packets, "PlayerSyncScNotify"))
    team = battle_team(c)
    check("battles use the loaded config", team and set(team) <= {1310, 1415, 8010}, team)
    c.command("/json load full")
    check("load by name", len(srv.read_json("config.json")["avatar_config"]) == len(fixture_config()["avatar_config"]))

done()
```

- [ ] **Step 2: Run, expect FAIL** — `python tests/test_json.py` fails from `nothing saved yet` on.

- [ ] **Step 3: Implement**

`gameserver/src/commands/json.zig`:

```zig
const std = @import("std");
const commandhandler = @import("../command.zig");
const Session = @import("../Session.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const GameConfig = @import("../data/game_config.zig");
const Battle = @import("../services/battle.zig");
const sync_command = @import("sync.zig");

const Allocator = std.mem.Allocator;

// Named copies of config.json, so several SRTools setups can be kept and switched in game.
const configs_dir = "configs";
const backups_dir = "config-backups";
const max_config_size = 16 << 20;

const usage =
    \\/json - list the saved configs (configs folder)
    \\/json export <name> [force] - save config.json as configs/<name>.json
    \\/json load <number or name> - make that saved config the config.json and apply it
;

pub fn handle(session: *Session, args: []const u8, allocator: Allocator) !void {
    var tokens = std.mem.tokenizeAny(u8, args, commandhandler.whitespace);
    const mode = tokens.next() orelse "list";
    if (std.ascii.eqlIgnoreCase(mode, "list")) return list(session, allocator);
    if (std.ascii.eqlIgnoreCase(mode, "export")) {
        const name = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        const force = if (tokens.next()) |t| std.ascii.eqlIgnoreCase(t, "force") else false;
        return exportConfig(session, name, force, allocator);
    }
    if (std.ascii.eqlIgnoreCase(mode, "load")) {
        const arg = tokens.next() orelse return commandhandler.sendMessage(session, usage, allocator);
        return load(session, arg, allocator);
    }
    return commandhandler.sendMessage(session, usage, allocator);
}

fn list(session: *Session, allocator: Allocator) !void {
    const names = try savedConfigs(allocator);
    if (names.len == 0) return commandhandler.sendMessage(session, "No saved configs; /json export <name> saves config.json.", allocator);
    var text = std.ArrayList(u8).init(allocator);
    for (names, 1..) |name, i| {
        if (i > 1) try text.append('\n');
        try text.writer().print("{d}. {s}", .{ i, name[0 .. name.len - ".json".len] });
    }
    try commandhandler.sendMessage(session, text.items, allocator);
}

fn exportConfig(session: *Session, name: []const u8, force: bool, allocator: Allocator) !void {
    if (!validName(name)) return commandhandler.sendMessage(session, "Names are 1-40 letters, digits, '-' or '_'.", allocator);
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ configs_dir, name });
    try std.fs.cwd().makePath(configs_dir);
    if (!force) {
        if (std.fs.cwd().access(path, .{})) {
            return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "{s} exists; add force to overwrite it.", .{path}), allocator);
        } else |_| {}
    }
    try std.fs.cwd().copyFile("config.json", std.fs.cwd(), path, .{});
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "config.json saved as {s}.", .{path}), allocator);
}

fn load(session: *Session, arg: []const u8, allocator: Allocator) !void {
    if (Battle.on_battle) return commandhandler.sendMessage(session, "Finish the battle first.", allocator);
    const names = try savedConfigs(allocator);
    const name = pick(names, arg) orelse {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "No saved config '{s}' (see /json).", .{arg}), allocator);
    };
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ configs_dir, name });
    // Checked with the same parser as config.json before anything is touched.
    var parsed = ConfigManager.loadConfig(GameConfig.GameConfig, GameConfig.parseConfig, allocator, path) catch |err| {
        return commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "{s} is not a valid config ({s}); nothing changed.", .{ path, @errorName(err) }), allocator);
    };
    const avatars = parsed.avatar_config.items.len;
    parsed.deinit();
    if (avatars == 0) return commandhandler.sendMessage(session, "That config has no avatars; nothing changed.", allocator);

    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, max_config_size);
    try std.fs.cwd().makePath(backups_dir);
    const backup = try std.fmt.allocPrint(allocator, "{s}/config-{s}-before-json-load.json", .{ backups_dir, try timestamp(allocator) });
    try std.fs.cwd().copyFile("config.json", std.fs.cwd(), backup, .{});
    var file = try std.fs.cwd().atomicFile("config.json", .{});
    defer file.deinit();
    try file.file.writeAll(bytes);
    try file.finish();

    try sync_command.applyConfig(session, allocator);
    try commandhandler.sendMessage(session, try std.fmt.allocPrint(allocator, "Loaded {s}; the old config.json is in {s}.", .{ path, backup }), allocator);
}

// The *.json files directly in configs/, sorted by name; none if the folder does not exist.
fn savedConfigs(allocator: Allocator) ![]const []const u8 {
    var dir = std.fs.cwd().openDir(configs_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer dir.close();
    var names = std.ArrayList([]const u8).init(allocator);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.ascii.endsWithIgnoreCase(entry.name, ".json")) continue;
        try names.append(try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.lessThan);
    return names.items;
}

// A number from the list or a listed name (".json" may be left out); nothing outside configs/ can be named.
fn pick(names: []const []const u8, arg: []const u8) ?[]const u8 {
    if (std.fmt.parseInt(usize, arg, 10)) |n| {
        return if (n >= 1 and n <= names.len) names[n - 1] else null;
    } else |_| {}
    const stem = if (std.ascii.endsWithIgnoreCase(arg, ".json")) arg[0 .. arg.len - ".json".len] else arg;
    for (names) |name| {
        if (std.ascii.eqlIgnoreCase(name[0 .. name.len - ".json".len], stem)) return name;
    }
    return null;
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 40) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') return false;
    }
    return true;
}

fn timestamp(allocator: Allocator) ![]const u8 {
    const secs = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
    const day = secs.getEpochDay().calculateYearDay();
    const md = day.calculateMonthDay();
    const t = secs.getDaySeconds();
    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}-UTC", .{
        day.year, md.month.numeric(), md.day_index + 1, t.getHoursIntoDay(), t.getMinutesIntoHour(), t.getSecondsIntoMinute(),
    });
}

test "config names" {
    try std.testing.expect(validName("team-A_2"));
    try std.testing.expect(!validName(""));
    try std.testing.expect(!validName("../config"));
    try std.testing.expect(!validName("a b"));
    const names = [_][]const u8{ "boss.json", "farm.json" };
    try std.testing.expectEqualStrings("farm.json", pick(&names, "2").?);
    try std.testing.expectEqualStrings("boss.json", pick(&names, "BOSS").?);
    try std.testing.expectEqualStrings("boss.json", pick(&names, "boss.json").?);
    try std.testing.expect(pick(&names, "3") == null);
    try std.testing.expect(pick(&names, "../config") == null);
}
```

Add `    _ = @import("commands/json.zig");` to `unit_tests.zig`; append `configs/` to `.git/info/exclude`. Register: import `const json_command = @import("./commands/json.zig");`, entry `    .{ .name = "json", .action = "", .func = json_command.handle },`.

- [ ] **Step 4: Build and test** — `cd gameserver && <zig> build test --summary all` (7+ tests), `<zig> build`, `python tests/test_json.py` → `14 passed, 0 failed`; `python tests/run_all.py` → `failed: none`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/commands/json.zig gameserver/src/unit_tests.zig gameserver/src/command.zig tests/test_json.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Save and switch between config.json setups from chat (/json)

/json export <name> copies config.json into configs/, /json load checks a
saved one with the config.json parser, backs the current file up in
config-backups/ and applies it like an SRTools sync.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

## Part B: profile / world features (Tasks 11–18)

Every command below runs in Git Bash from the repo root:

```bash
cd "G:/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
ZIG="G:/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe"
```

Notes that hold for all of Part B:
- `ProfileStore.get()` returns a pointer into the store's arena, and `ProfileStore.set()` frees that arena after it
  copies the new value. Handlers therefore build every new slice (in the per-packet `allocator`) **before** calling
  `set()`, and read `get()` again afterwards instead of reusing an older pointer.
- Strings saved in `profile.json` must be valid UTF-8: `ProfileStore.load()` rejects the whole file otherwise
  (Task 2's `parse`). Signature and nickname are checked before they are saved.
- Protobuf leaves zero/false/empty fields off the wire, so tests read them with `.get(name, 0)` and friends.
- Broken state files are copied to `<name>.bad` (the same thing `tierce_mgr.zig` and Task 2's `profile_store.zig` do).
- Edits to `handlers.zig` and `config_mgr.zig` are anchored on lines that exist after Tasks 1–10; if another task has
  added lines right after the same anchor, put these lines after them.
- Each test sets `sys.stdout.reconfigure(errors="backslashreplace")`: a FAIL detail holding "é", "✨", "ก" or the mail's
  "Đ" otherwise crashes `print` on the cp1252 console with UnicodeEncodeError.
- Values read back from profile.json are checked again when sent (phone picks, head icon, personal card, pet,
  jukebox track, board avatars, college rooms): a hand-edited id the player does not have shows the default.
- Checked on 2026-10-15 on a copy of the repo with Tasks 1–10 applied: every "before" snippet below matched exactly once; for each task in turn (11…18) its test
  failed as quoted in Step 2 before the task, and after it the build succeeded, `zig build test` passed and the test
  passed with the count quoted in Step 4. With all eight applied, the Tasks 1–10 tests (calyx, debug, faketime, hero,
  json, peak, profile_store, scene, windy) still pass.

---

### Task 11: Phone choices persist

**Files:**
- Modify: `gameserver/src/services/profile.zig` (GetPhoneData sends the saved choices; SelectChatBubble/SelectPhoneTheme/SelectPhoneCase check the owned lists and save)
- Test: `tests/test_phone.py`

**Interfaces:**
- Consumes: `ProfileStore.get()`, `ProfileStore.set("chat_bubble" | "phone_theme" | "phone_case", u32)` (Task 2); `Data.OwnedChatBubbles`, `Data.OwnedPhoneThemes`, `Data.OwnedPhoneCases`
- Produces: `fn owns(list: []const u32, id: u32) bool` and `fn ownedOr(list, saved, default) u32` in `services/profile.zig` (used again by Task 12)

- [ ] **Step 1: Write the failing test** — create `tests/test_phone.py`:

```python
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
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_phone.py
```

Expected: `FAIL unknown bubble keeps 220003 {'cur_chat_bubble': 229999}` (the old handlers echo the request),
`FAIL unknown theme keeps 221005`, `FAIL case 0 keeps 254000`, `FAIL profile.json has the choices and the old outfit {'pam_skin': 252001}`,
`FAIL choices survive a restart`, last line `6 passed, 5 failed`, exit code 1 (`unowned saved ids: the defaults` already
passes: today's handler always sends the defaults).

- [ ] **Step 3: Implement** — in `gameserver/src/services/profile.zig`:

Replace

```zig
pub fn onGetPhoneData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPhoneDataScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_chat_bubble = 0;
    rsp.cur_phone_theme = 0;
    rsp.cur_phone_case = 254001;
    try rsp.owned_phone_cases.appendSlice(&Data.OwnedPhoneCases);
    try rsp.owned_phone_themes.appendSlice(&Data.OwnedPhoneThemes);
    try rsp.owned_chat_bubbles.appendSlice(&Data.OwnedChatBubbles);
    try session.send(CmdID.CmdGetPhoneDataScRsp, rsp);
}
pub fn onSelectPhoneTheme(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPhoneThemeCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SelectPhoneThemeScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_phone_theme = req.theme_id;
    try session.send(CmdID.CmdSelectPhoneThemeScRsp, rsp);
}
pub fn onSelectChatBubble(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectChatBubbleCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SelectChatBubbleScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_chat_bubble = req.bubble_id;
    try session.send(CmdID.CmdSelectChatBubbleScRsp, rsp);
}
```

with

```zig
// The phone's bubble, theme and case are kept in profile.json. An id outside the owned lists of data.zig keeps the
// current choice; a saved one outside them (a hand edit) shows the default.
fn owns(list: []const u32, id: u32) bool {
    return std.mem.indexOfScalar(u32, list, id) != null;
}
fn ownedOr(list: []const u32, saved: u32, default: u32) u32 {
    return if (owns(list, saved)) saved else default;
}
fn curChatBubble() u32 {
    return ownedOr(&Data.OwnedChatBubbles, ProfileStore.get().chat_bubble, 0);
}
fn curPhoneTheme() u32 {
    return ownedOr(&Data.OwnedPhoneThemes, ProfileStore.get().phone_theme, 0);
}
fn curPhoneCase() u32 {
    return ownedOr(&Data.OwnedPhoneCases, ProfileStore.get().phone_case, 254001);
}

pub fn onGetPhoneData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPhoneDataScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_chat_bubble = curChatBubble();
    rsp.cur_phone_theme = curPhoneTheme();
    rsp.cur_phone_case = curPhoneCase();
    try rsp.owned_phone_cases.appendSlice(&Data.OwnedPhoneCases);
    try rsp.owned_phone_themes.appendSlice(&Data.OwnedPhoneThemes);
    try rsp.owned_chat_bubbles.appendSlice(&Data.OwnedChatBubbles);
    try session.send(CmdID.CmdGetPhoneDataScRsp, rsp);
}
pub fn onSelectPhoneTheme(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPhoneThemeCsReq, allocator);
    defer req.deinit();
    if (req.theme_id != curPhoneTheme() and owns(&Data.OwnedPhoneThemes, req.theme_id)) {
        ProfileStore.set("phone_theme", req.theme_id);
    }

    var rsp = protocol.SelectPhoneThemeScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_phone_theme = curPhoneTheme();
    try session.send(CmdID.CmdSelectPhoneThemeScRsp, rsp);
}
pub fn onSelectChatBubble(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectChatBubbleCsReq, allocator);
    defer req.deinit();
    if (req.bubble_id != curChatBubble() and owns(&Data.OwnedChatBubbles, req.bubble_id)) {
        ProfileStore.set("chat_bubble", req.bubble_id);
    }

    var rsp = protocol.SelectChatBubbleScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_chat_bubble = curChatBubble();
    try session.send(CmdID.CmdSelectChatBubbleScRsp, rsp);
}
```

Replace

```zig
pub fn onSelectPhoneCase(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPhoneCaseCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SelectPhoneCaseScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_phone_case = req.phone_case_id;
    std.debug.print("SET PHONE CASE ID: {}\n", .{req.phone_case_id});
    try session.send(CmdID.CmdSelectPhoneCaseScRsp, rsp);
}
```

with

```zig
pub fn onSelectPhoneCase(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SelectPhoneCaseCsReq, allocator);
    defer req.deinit();
    if (req.phone_case_id != curPhoneCase() and owns(&Data.OwnedPhoneCases, req.phone_case_id)) {
        ProfileStore.set("phone_case", req.phone_case_id);
    }

    var rsp = protocol.SelectPhoneCaseScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.cur_phone_case = curPhoneCase();
    try session.send(CmdID.CmdSelectPhoneCaseScRsp, rsp);
}
```

(`ProfileStore` is already imported at the top of this file by Task 2.)

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_phone.py
```

Expected: unit tests all pass; `test_phone.py` ends with `11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/services/profile.zig tests/test_phone.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Remember the phone's chat bubble, theme and case

The phone menu forgot every pick on relog: GetPhoneData always sent
bubble 0, theme 0 and case 254001, and the Select* handlers only echoed
the request. Picks are now kept in profile.json. An id outside the owned
lists in data.zig keeps the current pick, and a saved one outside them
(a hand edit) shows the default.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 12: Player board + detail info persist

**Files:**
- Modify: `gameserver/src/services/profile.zig` (board getters/setters read and save profile.json; GetPlayerDetailInfo filled; new `onSetIsDisplayAvatarInfo`; `clipUtf8` helper + Zig test)
- Modify: `gameserver/src/handlers.zig` (register SetIsDisplayAvatarInfo 2859→2818; remove the dead `GetPlayerBoardData` DummyCmdList entry)
- Modify: `gameserver/src/unit_tests.zig` (add `services/profile.zig`)
- Test: `tests/test_player_board.py`

**Interfaces:**
- Consumes: `ProfileStore.get()`, `ProfileStore.set("signature" | "head_icon" | "personal_card" | "display_avatars" | "assist_avatars", ...)`, `ProfileStore.DisplayAvatar` (Task 2); `owns` (Task 11); `PresetManager.baseId`, `PresetManager.pathId`; `commandhandler.bot_uid`
- Produces: `pub fn clipUtf8(text: []const u8, max: usize) ?[]const u8`, `fn boardDisplay`, `fn boardAssist`, `fn configAvatar` in `services/profile.zig`

Decisions: board entries are stored as base ids (8001, 1001), like M7H. A Set request with an avatar that config.json
does not have, a repeated avatar, or more than 5 (display) / 3 (assist) is refused as a whole: the reply carries the
current list. Positions are stored as the client sends them. The defaults keep today's packet (positions 1..5).
A saved head icon outside the unlocked list shows 0, a saved card outside `OwnedPersonalCardSkin` shows 253001 (hand edits).
GetPlayerDetailInfo fills the player's own card for every uid except MushiSR's (`bot_uid` 2000), which keeps today's bare card.

- [ ] **Step 1: Write the failing test** — create `tests/test_player_board.py`:

```python
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
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_player_board.py
```

Expected: the default checks pass, then `FAIL signature cut at 256 bytes`, `FAIL locked head icon refused`, … and finally
`AssertionError: SetIsDisplayAvatarInfoCsReq: no SetIsDisplayAvatarInfoScRsp (got [])` (the request is not handled yet), exit code 1.

- [ ] **Step 3: Implement**

**3a.** `gameserver/src/services/profile.zig`, imports and constants. Replace

```zig
const ConfigManager = @import("../manager/config_mgr.zig");
const Uid = @import("../utils/uid.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

// can change these id here for initial display
const SupportAvatar = [_]u32{
    1510, 1508, 1505,
};
const ListAvatar = [_]u32{
    1415, 1001, 1310, 1303, 1501,
};
```

with

```zig
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const PresetManager = @import("../manager/preset_mgr.zig");
const AvatarManager = @import("../manager/avatar_mgr.zig");
const GameConfig = @import("../data/game_config.zig");
const commandhandler = @import("../command.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const config = &ConfigManager.global_game_config_cache.game_config;

// can change these id here for initial display
const SupportAvatar = [_]u32{
    1510, 1508, 1505,
};
const ListAvatar = [_]u32{
    1415, 1001, 1310, 1303, 1501,
};
const max_display = 5;
const max_assist = 3;
const max_signature = 256;
```

**3b.** Replace the whole `onGetPlayerBoardData`, `onSetAssistAvatar`, `onSetDisplayAvatar` and `onSetSignature` (they
sit together, from `pub fn onGetPlayerBoardData(` down to the end of `onSetSignature`):

```zig
pub fn onGetPlayerBoardData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPlayerBoardDataScRsp.init(allocator);
    var generator = Uid.BaseUidGen().init();
    var display_list = protocol.DisplayAvatarVec.init(allocator);
    const player_icon_config = &ConfigManager.global_game_config_cache.player_icon_config;
    display_list.is_display = true;
    rsp.retcode = 0;
    try rsp.unlocked_personal_card_list.appendSlice(&Data.OwnedPersonalCardSkin);
    rsp.current_personal_card_id = 253001;
    rsp.head_frame_info = .{
        .head_frame_expire_time = 4294967295,
        .head_frame_item_id = 226004,
    };
    rsp.signature = .{ .Const = "" };
    try rsp.assist_avatar_id_list.appendSlice(&SupportAvatar);
    for (ListAvatar) |id| {
        var A_list = protocol.DisplayAvatarData.init(allocator);
        A_list.avatar_id = id;
        A_list.pos = generator.nextId();
        try display_list.display_avatar_list.append(A_list);
    }
    rsp.display_avatar_vec = display_list;
    for (player_icon_config.player_icon_config.items) |head_id| {
        const head_icon = protocol.HeadIconData{
            .id = head_id.id,
        };
        try rsp.unlocked_head_icon_list.append(head_icon);
    }
    try session.send(CmdID.CmdGetPlayerBoardDataScRsp, rsp);
}
pub fn onSetAssistAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetAssistAvatarCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SetAssistAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.avatar_id = req.avatar_id;
    rsp.avatar_id_list = req.avatar_id_list;
    try session.send(CmdID.CmdSetAssistAvatarScRsp, rsp);
}
pub fn onSetDisplayAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetDisplayAvatarCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SetDisplayAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.display_avatar_list = req.display_avatar_list;

    try session.send(CmdID.CmdSetDisplayAvatarScRsp, rsp);
}

pub fn onSetSignature(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetSignatureCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SetSignatureScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.signature = req.signature;
    try session.send(CmdID.CmdSetSignatureScRsp, rsp);
}
```

with

```zig
// The player board (card) is kept in profile.json. Its avatars are stored as base ids (8001, 1001), which follow
// the Trailblazer's and March 7th's selected path.

// The config.json avatar a board entry stands for; null once config.json no longer has the character.
fn configAvatar(base_id: u32) ?*const GameConfig.Avatar {
    const selected = PresetManager.pathId(base_id);
    var first: ?*const GameConfig.Avatar = null;
    for (config.avatar_config.items) |*avatar| {
        if (avatar.id == selected) return avatar;
        if (first == null and PresetManager.baseId(avatar.id) == base_id) first = avatar;
    }
    return first;
}

// The saved board avatars config.json still has; the defaults above when none are left.
fn boardDisplay(allocator: Allocator) ![]const ProfileStore.DisplayAvatar {
    var out = ArrayList(ProfileStore.DisplayAvatar).init(allocator);
    for (ProfileStore.get().display_avatars) |entry| {
        if (configAvatar(entry.avatar_id) != null) try out.append(entry);
    }
    if (out.items.len == 0) {
        for (ListAvatar, 1..) |id, pos| try out.append(.{ .avatar_id = id, .pos = @intCast(pos) });
    }
    return out.items;
}
fn boardAssist(allocator: Allocator) ![]const u32 {
    var out = ArrayList(u32).init(allocator);
    for (ProfileStore.get().assist_avatars) |id| {
        if (configAvatar(id) != null) try out.append(id);
    }
    if (out.items.len == 0) try out.appendSlice(&SupportAvatar);
    return out.items;
}

// A board request's avatars as base ids; null if one is not in config.json, one repeats, or there are too many.
// Empty slots (avatar 0) are skipped.
fn pickDisplay(allocator: Allocator, entries: []const protocol.DisplayAvatarData) !?[]ProfileStore.DisplayAvatar {
    var picked = ArrayList(ProfileStore.DisplayAvatar).init(allocator);
    for (entries) |entry| {
        if (entry.avatar_id == 0) continue;
        const base = PresetManager.baseId(entry.avatar_id);
        if (configAvatar(base) == null or picked.items.len == max_display) return null;
        for (picked.items) |p| {
            if (p.avatar_id == base) return null;
        }
        try picked.append(.{ .avatar_id = base, .pos = entry.pos });
    }
    return picked.items;
}
fn pickAssist(allocator: Allocator, ids: []const u32) !?[]u32 {
    var picked = ArrayList(u32).init(allocator);
    for (ids) |id| {
        if (id == 0) continue;
        const base = PresetManager.baseId(id);
        if (configAvatar(base) == null or picked.items.len == max_assist) return null;
        if (std.mem.indexOfScalar(u32, picked.items, base) != null) return null;
        try picked.append(base);
    }
    return picked.items;
}

fn unlockedHeadIcon(id: u32) bool {
    for (ConfigManager.global_game_config_cache.player_icon_config.player_icon_config.items) |icon| {
        if (icon.id == id) return true;
    }
    return false;
}
// A saved icon or card the player does not have (a hand edit) shows the default.
fn curHeadIcon() u32 {
    const saved = ProfileStore.get().head_icon;
    return if (unlockedHeadIcon(saved)) saved else 0;
}
fn curPersonalCard() u32 {
    return ownedOr(&Data.OwnedPersonalCardSkin, ProfileStore.get().personal_card, 253001);
}

// The longest start of `text` that fits in `max` bytes without splitting a character; null if `text` is not UTF-8
// (profile.json would not load again).
pub fn clipUtf8(text: []const u8, max: usize) ?[]const u8 {
    if (!std.unicode.utf8ValidateSlice(text)) return null;
    if (text.len <= max) return text;
    var end = max;
    // Back up over continuation bytes (0b10xxxxxx) to the first byte of the character that crosses `max`.
    while (end > 0 and text[end] & 0xC0 == 0x80) end -= 1;
    return text[0..end];
}

pub fn onGetPlayerBoardData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    const saved = ProfileStore.get();
    var rsp = protocol.GetPlayerBoardDataScRsp.init(allocator);
    var display_list = protocol.DisplayAvatarVec.init(allocator);
    const player_icon_config = &ConfigManager.global_game_config_cache.player_icon_config;
    display_list.is_display = true;
    rsp.retcode = 0;
    try rsp.unlocked_personal_card_list.appendSlice(&Data.OwnedPersonalCardSkin);
    rsp.current_personal_card_id = curPersonalCard();
    rsp.current_head_icon_id = curHeadIcon();
    rsp.head_frame_info = .{
        .head_frame_expire_time = 4294967295,
        .head_frame_item_id = 226004,
    };
    rsp.signature = .{ .Const = saved.signature };
    try rsp.assist_avatar_id_list.appendSlice(try boardAssist(allocator));
    for (try boardDisplay(allocator)) |entry| {
        try display_list.display_avatar_list.append(.{ .avatar_id = entry.avatar_id, .pos = entry.pos });
    }
    rsp.display_avatar_vec = display_list;
    for (player_icon_config.player_icon_config.items) |head_id| {
        const head_icon = protocol.HeadIconData{
            .id = head_id.id,
        };
        try rsp.unlocked_head_icon_list.append(head_icon);
    }
    try session.send(CmdID.CmdGetPlayerBoardDataScRsp, rsp);
}
pub fn onSetAssistAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetAssistAvatarCsReq, allocator);
    defer req.deinit();
    // A request naming one avatar in avatar_id instead of the list.
    const single = [1]u32{req.avatar_id};
    const ids: []const u32 = if (req.avatar_id_list.items.len == 0 and req.avatar_id != 0) &single else req.avatar_id_list.items;
    if (try pickAssist(allocator, ids)) |picked| ProfileStore.set("assist_avatars", picked);

    var rsp = protocol.SetAssistAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    try rsp.avatar_id_list.appendSlice(try boardAssist(allocator));
    try session.send(CmdID.CmdSetAssistAvatarScRsp, rsp);
}
pub fn onSetDisplayAvatar(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetDisplayAvatarCsReq, allocator);
    defer req.deinit();
    if (try pickDisplay(allocator, req.display_avatar_list.items)) |picked| ProfileStore.set("display_avatars", picked);

    var rsp = protocol.SetDisplayAvatarScRsp.init(allocator);
    rsp.retcode = 0;
    for (try boardDisplay(allocator)) |entry| {
        try rsp.display_avatar_list.append(.{ .avatar_id = entry.avatar_id, .pos = entry.pos });
    }
    try session.send(CmdID.CmdSetDisplayAvatarScRsp, rsp);
}
// Echoed only: the board always shows its avatars.
pub fn onSetIsDisplayAvatarInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetIsDisplayAvatarInfoCsReq, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdSetIsDisplayAvatarInfoScRsp, protocol.SetIsDisplayAvatarInfoScRsp{
        .retcode = 0,
        .is_display = req.is_display,
    });
}

pub fn onSetSignature(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetSignatureCsReq, allocator);
    defer req.deinit();
    if (clipUtf8(req.signature.getSlice(), max_signature)) |text| {
        if (!std.mem.eql(u8, text, ProfileStore.get().signature)) ProfileStore.set("signature", text);
    }

    var rsp = protocol.SetSignatureScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.signature = .{ .Const = ProfileStore.get().signature };
    try session.send(CmdID.CmdSetSignatureScRsp, rsp);
}
```

**3c.** Replace

```zig
pub fn onSetHeadIcon(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetHeadIconCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.SetHeadIconScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.current_head_icon_id = req.id;
    std.debug.print("SET HEAD ICON ID: {}\n", .{req.id});
    try session.send(CmdID.CmdSetHeadIconScRsp, rsp);
}
```

with

```zig
pub fn onSetHeadIcon(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetHeadIconCsReq, allocator);
    defer req.deinit();
    // Only icons GetPlayerBoardData lists as unlocked.
    if (req.id != curHeadIcon() and unlockedHeadIcon(req.id)) ProfileStore.set("head_icon", req.id);

    var rsp = protocol.SetHeadIconScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.current_head_icon_id = curHeadIcon();
    try session.send(CmdID.CmdSetHeadIconScRsp, rsp);
}
```

**3d.** Replace

```zig
pub fn onGetPlayerDetailInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetPlayerDetailInfoCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.GetPlayerDetailInfoScRsp.init(allocator);
    rsp.retcode = 0;
    var detail = protocol.PlayerDetailInfo.init(allocator);
    detail.head_frame_info = .{
        .head_frame_expire_time = 4294967295,
        .head_frame_item_id = 226004,
    };
    detail.uid = req.uid;
    detail.world_level = 6;
    detail.level = 70;
    rsp.detail_info = detail;
    try session.send(CmdID.CmdGetPlayerDetailInfoScRsp, rsp);
}
pub fn onSetPersonalCard(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetPersonalCardCsReq, allocator);
    defer req.deinit();

    try session.send(CmdID.CmdSetPersonalCardScRsp, protocol.SetPersonalCardScRsp{
        .current_personal_card_id = req.id,
        .retcode = 0,
    });
}
```

with

```zig
// A card avatar with its config.json level, eidolons and Light Cone; the fixed defaults show at level 80.
fn detailAvatar(allocator: Allocator, base_id: u32, pos: u32) protocol.DisplayAvatarDetailInfo {
    var info = protocol.DisplayAvatarDetailInfo.init(allocator);
    info.avatar_id = base_id;
    info.pos = pos;
    if (configAvatar(base_id)) |avatar| {
        info.level = avatar.level;
        info.promotion = avatar.promotion;
        info.rank = avatar.rank;
        info.equipment = .{
            .tid = avatar.lightcone.id,
            .level = avatar.lightcone.level,
            .rank = avatar.lightcone.rank,
            .promotion = avatar.lightcone.promotion,
        };
    } else {
        info.level = 80;
        info.promotion = 6;
    }
    return info;
}

pub fn onGetPlayerDetailInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetPlayerDetailInfoCsReq, allocator);
    defer req.deinit();

    var rsp = protocol.GetPlayerDetailInfoScRsp.init(allocator);
    rsp.retcode = 0;
    var detail = protocol.PlayerDetailInfo.init(allocator);
    detail.head_frame_info = .{
        .head_frame_expire_time = 4294967295,
        .head_frame_item_id = 226004,
    };
    detail.uid = req.uid;
    detail.world_level = 6;
    detail.level = 70;
    // MushiSR's card stays bare; every other uid is the player.
    if (req.uid != commandhandler.bot_uid) {
        const saved = ProfileStore.get();
        detail.nickname = .{ .Const = saved.nickname };
        detail.signature = .{ .Const = saved.signature };
        detail.head_icon = curHeadIcon();
        detail.chat_bubble = curChatBubble();
        detail.gender = AvatarManager.gender;
        for (try boardDisplay(allocator)) |entry| {
            try detail.display_avatar_list.append(detailAvatar(allocator, entry.avatar_id, entry.pos));
        }
        for (try boardAssist(allocator), 0..) |id, pos| {
            try detail.assist_avatar_list.append(detailAvatar(allocator, id, @intCast(pos)));
        }
    }
    rsp.detail_info = detail;
    try session.send(CmdID.CmdGetPlayerDetailInfoScRsp, rsp);
}
pub fn onSetPersonalCard(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetPersonalCardCsReq, allocator);
    defer req.deinit();
    if (req.id != curPersonalCard() and owns(&Data.OwnedPersonalCardSkin, req.id)) {
        ProfileStore.set("personal_card", req.id);
    }

    try session.send(CmdID.CmdSetPersonalCardScRsp, protocol.SetPersonalCardScRsp{
        .current_personal_card_id = curPersonalCard(),
        .retcode = 0,
    });
}
```

**3e.** Append the Zig test at the end of `gameserver/src/services/profile.zig`:

```zig
test "a signature is cut on a character boundary" {
    try std.testing.expectEqualStrings("abc", clipUtf8("abc", 256).?);
    try std.testing.expectEqualStrings("ab", clipUtf8("abcd", 2).?);
    // "aéé" is 5 bytes; 4 would split the second "é", so the cut keeps "aé" (3 bytes).
    try std.testing.expectEqualStrings("aé", clipUtf8("aéé", 4).?);
    try std.testing.expectEqualStrings("", clipUtf8("é", 1).?);
    try std.testing.expect(clipUtf8("\xff\xfe", 256) == null);
}
```

**3f.** `gameserver/src/handlers.zig`: register the new handler. Replace

```zig
    .{ CmdID.CmdSelectPamSkinCsReq, profile.onSelectPamSkin },
```

with

```zig
    .{ CmdID.CmdSelectPamSkinCsReq, profile.onSelectPamSkin },
    .{ CmdID.CmdSetIsDisplayAvatarInfoCsReq, profile.onSetIsDisplayAvatarInfo },
```

and delete this DummyCmdList line (dead: the HandlerList entry for the same request matches first):

```zig
    .{ CmdID.CmdGetPlayerBoardDataCsReq, CmdID.CmdGetPlayerBoardDataScRsp },
```

**3g.** `gameserver/src/unit_tests.zig`: inside the `test { ... }` block add

```zig
    _ = @import("services/profile.zig");
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_player_board.py && python tests/test_phone.py
```

Expected: unit tests pass (including `a signature is cut on a character boundary`); `test_player_board.py` ends with
`40 passed, 0 failed`; `test_phone.py` still `11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/services/profile.zig gameserver/src/handlers.zig gameserver/src/unit_tests.zig tests/test_player_board.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Remember the player card across restarts

Signature, head icon, personal card, showcase and support avatars were
echoed but never kept, so the card went back to the defaults on relog
and the head icon vanished. They are now saved in profile.json and
GetPlayerBoardData sends them. Ids are checked first: head icons
against the unlocked list, cards against the owned list, avatars
against config.json (at most 5 shown, 3 support, no repeats). A
signature is cut at 256 bytes on a character boundary. Avatars that
config.json no longer has drop off the card; with none left the old
defaults show. A saved icon or card the player does not have (a hand
edit of profile.json) shows the default.

GetPlayerDetailInfo now fills the card (name, signature, icon, bubble,
gender, avatars with their config.json level and Light Cone).
SetIsDisplayAvatarInfo is answered. The dead GetPlayerBoardData dummy
entry is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 13: ServerPrefs

**Files:**
- Create: `gameserver/src/manager/prefs_mgr.zig`
- Modify: `gameserver/src/services/events.zig` (delete the dead `onUpdateServerPrefsData`; add the three real handlers)
- Modify: `gameserver/src/handlers.zig` (register GetAllServerPrefsData 6174→6119, GetServerPrefsData 6131→6187, UpdateServerPrefs 6105→6171; drop the GetAllServerPrefsData dummy entry and the commented-out wrong line)
- Modify: `gameserver/src/main.zig` (`PrefsManager.load()`)
- Modify: `gameserver/src/unit_tests.zig`
- Modify (not committed): `.git/info/exclude` (`server_prefs.json`, `server_prefs.json.bad`)
- Test: `tests/test_server_prefs.py` (+ Zig tests in `prefs_mgr.zig`)

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `PrefsManager.load()`, `PrefsManager.all() []const PrefsManager.Entry`, `PrefsManager.find(id) ?[]const u8`,
  `PrefsManager.put(id, data) !void`, `PrefsManager.max_entries = 256`, `PrefsManager.max_data_len = 64 * 1024`

Decisions: an update over the limits is answered with `RET_REQ_PARA_INVALID` (5) and nothing is saved. A
request without `server_prefs` gets retcode 0 and `server_prefs_id` 0.

- [ ] **Step 1: Write the failing test** — create `tests/test_server_prefs.py`:

```python
import base64, json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def prefs_all(c):
    rsp, _ = c.call("GetAllServerPrefsDataCsReq", {}, "GetAllServerPrefsDataScRsp")
    return {p.get("server_prefs_id", 0): p.get("data", b"") for p in rsp.get("server_prefs_list", [])}


def update(c, prefs_id, data):
    rsp, _ = c.call("UpdateServerPrefsCsReq", {"server_prefs": {"server_prefs_id": prefs_id, "data": data}}, "UpdateServerPrefsScRsp")
    return rsp


with Server() as srv:
    c = srv.login()
    check("nothing saved yet", prefs_all(c) == {})
    rsp = update(c, 7, b"\x00\x01layout")
    check("update answers with the id", rsp.get("server_prefs_id") == 7 and rsp.get("retcode", 0) == 0, rsp)
    update(c, 9, b"x" * 1000)
    update(c, 7, b"new")
    check("all prefs; a second update of 7 replaces it", prefs_all(c) == {7: b"new", 9: b"x" * 1000}, prefs_all(c))

    rsp, _ = c.call("GetServerPrefsDataCsReq", {"server_prefs_id": 9}, "GetServerPrefsDataScRsp")
    check("one pref", rsp.get("server_prefs") == {"server_prefs_id": 9, "data": b"x" * 1000}, rsp)
    rsp, _ = c.call("GetServerPrefsDataCsReq", {"server_prefs_id": 42}, "GetServerPrefsDataScRsp")
    check("unknown id: an entry with only the id", rsp.get("server_prefs") == {"server_prefs_id": 42}, rsp)

    rsp, _ = c.call("UpdateServerPrefsCsReq", {}, "UpdateServerPrefsScRsp")
    check("update without server_prefs: retcode 0, nothing saved", rsp.get("retcode", 0) == 0 and len(prefs_all(c)) == 2, rsp)
    rsp = update(c, 9, b"y" * (64 * 1024 + 1))
    check("over 64 KB refused, old data kept", rsp.get("retcode", 0) != 0 and prefs_all(c)[9] == b"x" * 1000, rsp)
    rsp = update(c, 11, b"z" * (64 * 1024))
    check("exactly 64 KB accepted", rsp.get("retcode", 0) == 0 and prefs_all(c)[11] == b"z" * (64 * 1024), rsp)

    expected = {7: b"new", 9: b"x" * 1000, 11: b"z" * (64 * 1024)}
    saved = {e["id"]: base64.b64decode(e["data"]) for e in srv.read_json("server_prefs.json")["prefs"]}
    check("server_prefs.json holds base64", saved == expected, sorted(saved))

    srv.restart()
    c = srv.login()
    check("prefs survive a restart", prefs_all(c) == expected, sorted(prefs_all(c)))

    srv.stop()
    with open(srv.path("server_prefs.json"), "w") as f:
        f.write('{"prefs": [{"id": 1, "data": "!!"}]}')
    srv.start()
    c = srv.login()
    check("broken file: no prefs", prefs_all(c) == {}, prefs_all(c))
    check("broken file kept as server_prefs.json.bad", os.path.exists(srv.path("server_prefs.json.bad")))

full = {"prefs": [{"id": i, "data": base64.b64encode(b"p").decode()} for i in range(1, 257)]}
with Server(files={"server_prefs.json": json.dumps(full)}) as srv:
    c = srv.login()
    check("256 prefs load", len(prefs_all(c)) == 256)
    rsp = update(c, 1000, b"q")
    check("a 257th id is refused", rsp.get("retcode", 0) != 0 and 1000 not in prefs_all(c), rsp)
    rsp = update(c, 5, b"q")
    check("an existing id still updates", rsp.get("retcode", 0) == 0 and prefs_all(c)[5] == b"q", rsp)

too_many = {"prefs": [{"id": i, "data": ""} for i in range(1, 258)]}
with Server(files={"server_prefs.json": json.dumps(too_many)}) as srv:
    c = srv.login()
    check("a file with 257 prefs is refused", prefs_all(c) == {} and os.path.exists(srv.path("server_prefs.json.bad")))
done()
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_server_prefs.py
```

Expected: `ok nothing saved yet` (the dummy reply is empty), then
`AssertionError: UpdateServerPrefsCsReq: no UpdateServerPrefsScRsp (got [])`, exit code 1.

- [ ] **Step 3: Implement**

**3a.** Create `gameserver/src/manager/prefs_mgr.zig`:

```zig
const std = @import("std");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.prefs);

// ServerPrefs: settings the client stores on the server as opaque blobs, by id. Kept in server_prefs.json next to
// config.json as {"prefs":[{"id":N,"data":"<base64>"}]}.
const save_path = "server_prefs.json";
const bad_path = "server_prefs.json.bad";
pub const max_entries = 256;
pub const max_data_len = 64 * 1024;
// 256 entries of 64 KB in base64, with room for the JSON around them.
const max_file_len = 32 << 20;

pub const Error = error{ TooManyPrefs, PrefsTooLarge };

pub const Entry = struct { id: u32, data: []const u8 };

// Every entry's data is owned by page_allocator.
var entries = std.ArrayList(Entry).init(std.heap.page_allocator);

pub fn all() []const Entry {
    return entries.items;
}
pub fn find(id: u32) ?[]const u8 {
    for (entries.items) |entry| {
        if (entry.id == id) return entry.data;
    }
    return null;
}

// Stores a copy of `data` under `id`, replacing what was there, and saves.
pub fn put(id: u32, data: []const u8) !void {
    try putIn(&entries, std.heap.page_allocator, id, data);
    save();
}
fn putIn(list: *std.ArrayList(Entry), allocator: Allocator, id: u32, data: []const u8) !void {
    if (data.len > max_data_len) return error.PrefsTooLarge;
    const index = for (list.items, 0..) |entry, i| {
        if (entry.id == id) break i;
    } else null;
    if (index == null and list.items.len >= max_entries) return error.TooManyPrefs;
    const copy = try allocator.dupe(u8, data);
    if (index) |i| {
        allocator.free(list.items[i].data);
        list.items[i].data = copy;
    } else {
        list.append(.{ .id = id, .data = copy }) catch |err| {
            allocator.free(copy);
            return err;
        };
    }
}
fn freeAll(list: *std.ArrayList(Entry), allocator: Allocator) void {
    for (list.items) |entry| allocator.free(entry.data);
    list.deinit();
}

const SavedEntry = struct { id: u32, data: []const u8 };
const SaveFile = struct { prefs: []const SavedEntry = &.{} };

// Loaded once at startup. A missing file is normal; a broken one is kept as server_prefs.json.bad and the game
// starts with no saved settings.
pub fn load() void {
    loadFile() catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); starting without saved settings", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadFile() !void {
    const allocator = std.heap.page_allocator;
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, max_file_len);
    defer allocator.free(bytes);
    const loaded = try parse(allocator, bytes);
    freeAll(&entries, allocator);
    entries = loaded;
}
// Nothing is used unless the whole file is valid.
fn parse(allocator: Allocator, bytes: []const u8) !std.ArrayList(Entry) {
    const parsed = try std.json.parseFromSlice(SaveFile, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.prefs.len > max_entries) return error.TooManyPrefs;
    var list = std.ArrayList(Entry).init(allocator);
    errdefer freeAll(&list, allocator);
    const decoder = std.base64.standard.Decoder;
    for (parsed.value.prefs) |saved| {
        for (list.items) |entry| {
            if (entry.id == saved.id) return error.DuplicatePrefs;
        }
        const len = try decoder.calcSizeForSlice(saved.data);
        if (len > max_data_len) return error.PrefsTooLarge;
        const data = try allocator.alloc(u8, len);
        errdefer allocator.free(data);
        try decoder.decode(data, saved.data);
        try list.append(.{ .id = saved.id, .data = data });
    }
    return list;
}

fn render(allocator: Allocator, list: []const Entry) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const encoder = std.base64.standard.Encoder;
    const saved = try arena.allocator().alloc(SavedEntry, list.len);
    for (list, saved) |entry, *s| {
        const text = try arena.allocator().alloc(u8, encoder.calcSize(entry.data.len));
        s.* = .{ .id = entry.id, .data = encoder.encode(text, entry.data) };
    }
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try std.json.stringify(SaveFile{ .prefs = saved }, .{ .whitespace = .indent_2 }, out.writer());
    return out.toOwnedSlice();
}

// Written after every change; a failed write is logged and never drops the player.
fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    const text = try render(std.heap.page_allocator, entries.items);
    defer std.heap.page_allocator.free(text);
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(text);
    try file.finish();
}

test "prefs survive a save and a load, as base64 in the file" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(Entry).init(allocator);
    defer freeAll(&list, allocator);
    try putIn(&list, allocator, 7, &[_]u8{ 0, 1, 2, 255 });
    try putIn(&list, allocator, 9, "hello");
    try putIn(&list, allocator, 7, "new");
    const text = try render(allocator, list.items);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"aGVsbG8=\"") != null);
    var loaded = try parse(allocator, text);
    defer freeAll(&loaded, allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded.items.len);
    try std.testing.expectEqual(@as(u32, 7), loaded.items[0].id);
    try std.testing.expectEqualStrings("new", loaded.items[0].data);
    try std.testing.expectEqualStrings("hello", loaded.items[1].data);
}

test "at most 256 ids of at most 64 KB each" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(Entry).init(allocator);
    defer freeAll(&list, allocator);
    for (0..max_entries) |i| try putIn(&list, allocator, @intCast(i), "p");
    try std.testing.expectError(error.TooManyPrefs, putIn(&list, allocator, 1000, "q"));
    try putIn(&list, allocator, 5, "q");
    const big = try allocator.alloc(u8, max_data_len + 1);
    defer allocator.free(big);
    @memset(big, 'x');
    try std.testing.expectError(error.PrefsTooLarge, putIn(&list, allocator, 5, big));
    try putIn(&list, allocator, 5, big[0..max_data_len]);
}

test "a broken file is refused" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicatePrefs, parse(allocator, "{\"prefs\":[{\"id\":1,\"data\":\"\"},{\"id\":1,\"data\":\"\"}]}"));
    if (parse(allocator, "{\"prefs\":[{\"id\":1,\"data\":\"!!!!\"}]}")) |list| {
        var l = list;
        freeAll(&l, allocator);
        return error.TestUnexpectedResult;
    } else |_| {}
    if (parse(allocator, "{\"prefs\":")) |list| {
        var l = list;
        freeAll(&l, allocator);
        return error.TestUnexpectedResult;
    } else |_| {}
}
```

**3b.** Replace the whole of `gameserver/src/services/events.zig` with:

```zig
const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const PrefsManager = @import("../manager/prefs_mgr.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.events);

const activity_config = &ConfigManager.global_game_config_cache.activity_config;

pub fn onGetActivity(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetActivityScheduleConfigScRsp.init(allocator);
    var activ_list = protocol.ActivityScheduleData.init(allocator);
    //challenge mode pannel : 2100101
    for (activity_config.activity_config.items) |activityConf| {
        if (activityConf.panel_id != 30002) {
            activ_list.panel_id = activityConf.activity_id;
            for (activityConf.activity_module_list.items) |id| {
                activ_list.begin_time = 1664308800;
                activ_list.end_time = 4294967295;
                activ_list.activity_id = id;
                try rsp.schedule_data.append(activ_list);
            }
        }
    }
    rsp.retcode = 0;
    try session.send(CmdID.CmdGetActivityScheduleConfigScRsp, rsp);
}

pub fn onGetAllServerPrefsData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetAllServerPrefsDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (PrefsManager.all()) |entry| {
        try rsp.server_prefs_list.append(.{ .server_prefs_id = entry.id, .data = .{ .Const = entry.data } });
    }
    try session.send(CmdID.CmdGetAllServerPrefsDataScRsp, rsp);
}

pub fn onGetServerPrefsData(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetServerPrefsDataCsReq, allocator);
    defer req.deinit();
    // An id with nothing saved gets an entry with only the id.
    try session.send(CmdID.CmdGetServerPrefsDataScRsp, protocol.GetServerPrefsDataScRsp{
        .retcode = 0,
        .server_prefs = .{
            .server_prefs_id = req.server_prefs_id,
            .data = if (PrefsManager.find(req.server_prefs_id)) |data| .{ .Const = data } else .Empty,
        },
    });
}

pub fn onUpdateServerPrefs(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.UpdateServerPrefsCsReq, allocator);
    defer req.deinit();
    const prefs = req.server_prefs orelse {
        try session.send(CmdID.CmdUpdateServerPrefsScRsp, protocol.UpdateServerPrefsScRsp{ .retcode = 0 });
        return;
    };
    var retcode: u32 = 0;
    PrefsManager.put(prefs.server_prefs_id, prefs.data.getSlice()) catch |err| {
        log.warn("server prefs {} not saved: {s}", .{ prefs.server_prefs_id, @errorName(err) });
        retcode = @intCast(@intFromEnum(protocol.Retcode.RET_REQ_PARA_INVALID));
    };
    try session.send(CmdID.CmdUpdateServerPrefsScRsp, protocol.UpdateServerPrefsScRsp{
        .retcode = retcode,
        .server_prefs_id = prefs.server_prefs_id,
    });
}
```

(The old `onUpdateServerPrefsData` used message names that do not exist — `UpdateServerPrefsDataCsReq`,
`CmdUpdateServerPrefsDataScRsp` — and only compiled because nothing referenced it.)

**3c.** `gameserver/src/handlers.zig`. Replace

```zig
    //events
    //.{ CmdID.CmdGetActivityScheduleConfigCsReq, events.onGetActivity },
    //.{ CmdID.CmdUpdateServerPrefsDataCsReq, events.onUpdateServerPrefsData },
```

with

```zig
    //events
    //.{ CmdID.CmdGetActivityScheduleConfigCsReq, events.onGetActivity },
    .{ CmdID.CmdGetAllServerPrefsDataCsReq, events.onGetAllServerPrefsData },
    .{ CmdID.CmdGetServerPrefsDataCsReq, events.onGetServerPrefsData },
    .{ CmdID.CmdUpdateServerPrefsCsReq, events.onUpdateServerPrefs },
```

and delete this DummyCmdList line:

```zig
    .{ CmdID.CmdGetAllServerPrefsDataCsReq, CmdID.CmdGetAllServerPrefsDataScRsp },
```

**3d.** `gameserver/src/main.zig`. Replace

```zig
const TierceManager = @import("../src/manager/tierce_mgr.zig");
```

with

```zig
const TierceManager = @import("../src/manager/tierce_mgr.zig");
const PrefsManager = @import("../src/manager/prefs_mgr.zig");
```

and replace

```zig
    TierceManager.load(allocator);
```

with

```zig
    TierceManager.load(allocator);
    PrefsManager.load();
```

**3e.** `gameserver/src/unit_tests.zig`: inside the `test { ... }` block add

```zig
    _ = @import("manager/prefs_mgr.zig");
```

**3f.** Keep the new state files out of git (local only, not committed):

```bash
grep -qx 'server_prefs.json' .git/info/exclude || printf 'server_prefs.json\nserver_prefs.json.bad\n' >> .git/info/exclude
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_server_prefs.py
```

Expected: the three `prefs_mgr` unit tests pass; `test_server_prefs.py` ends with `16 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/manager/prefs_mgr.zig gameserver/src/services/events.zig gameserver/src/handlers.zig gameserver/src/main.zig gameserver/src/unit_tests.zig tests/test_server_prefs.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Keep the game's server-side settings across restarts

The client stores some settings on the server (ServerPrefs). They got
an empty GetAllServerPrefsData reply and no answer to UpdateServerPrefs
or GetServerPrefsData, so they never stuck. They are now kept in
server_prefs.json as base64, at most 256 ids of 64 KB each; an update
past that is refused with RET_REQ_PARA_INVALID. An update without a
server_prefs entry is answered and saves nothing. A broken file is kept
as server_prefs.json.bad.

The unused onUpdateServerPrefsData in events.zig, which named messages
that do not exist, is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 14: Nickname / gender / SetPlayerInfo

**Files:**
- Modify: `gameserver/src/services/login.zig` (`pub fn basicInfo`; PlayerLogin uses the saved nickname)
- Modify: `gameserver/src/services/profile.zig` (`cleanNickname` + Zig test; `onSetNickname`, `onSetGender`, `onSetPlayerInfo`)
- Modify: `gameserver/src/handlers.zig` (register SetNickname 4→94, SetGender 22→49, SetPlayerInfo 66→90)
- Test: `tests/test_nickname.py`

**Interfaces:**
- Consumes: `ProfileStore.get().nickname`, `ProfileStore.set("nickname", []const u8)` (Task 2); `AvatarManager.mc_id`; `Clock.nowSec()`
- Produces: `pub fn basicInfo(allocator: Allocator) protocol.PlayerBasicInfo` in `services/login.zig`;
  `pub fn cleanNickname(raw: []const u8) ?[]const u8` in `services/profile.zig`

Decisions: a refused name is answered with `RET_NICKNAME_FORMAT_ERROR` (2105) and no PlayerSyncScNotify.
SetPlayerInfo does not save its nickname (the opening it belongs to never runs here).

- [ ] **Step 1: Write the failing test** — create `tests/test_nickname.py`:

```python
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
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_nickname.py
```

Expected: `ok default nickname`, then `AssertionError: SetNicknameCsReq: no SetNicknameScRsp (got [])`, exit code 1.

- [ ] **Step 3: Implement**

**3a.** `gameserver/src/services/login.zig`. Replace

```zig
const ConfigManager = @import("../manager/config_mgr.zig");
```

with

```zig
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
```

Replace

```zig
pub fn onPlayerLogin(session: *Session, packet: *const Packet, allocator: Allocator) !void {
```

with

```zig
// The player's basic info, the same at login and after a rename.
pub fn basicInfo(allocator: Allocator) protocol.PlayerBasicInfo {
    var basic_info = protocol.PlayerBasicInfo.init(allocator);
    basic_info.stamina = 300;
    basic_info.level = 70;
    basic_info.nickname = .{ .Const = ProfileStore.get().nickname };
    basic_info.world_level = 6;
    basic_info.mcoin = 99999990;
    basic_info.hcoin = 99999990; //Jade
    basic_info.scoin = 99999990; //Money
    return basic_info;
}

pub fn onPlayerLogin(session: *Session, packet: *const Packet, allocator: Allocator) !void {
```

and replace

```zig
    var basic_info = protocol.PlayerBasicInfo.init(allocator);
    basic_info.stamina = 300;
    basic_info.level = 70;
    basic_info.nickname = .{ .Const = "ReversedRooms" };
    basic_info.world_level = 6;
    basic_info.mcoin = 99999990;
    basic_info.hcoin = 99999990; //Jade
    basic_info.scoin = 99999990; //Money

    var rsp = protocol.PlayerLoginScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.login_random = req.login_random;
    rsp.stamina = 300;
    rsp.server_timestamp_ms = Clock.nowMs();
    rsp.basic_info = basic_info;
```

with

```zig
    var rsp = protocol.PlayerLoginScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.login_random = req.login_random;
    rsp.stamina = 300;
    rsp.server_timestamp_ms = Clock.nowMs();
    rsp.basic_info = basicInfo(allocator);
```

**3b.** `gameserver/src/services/profile.zig`. Replace

```zig
const commandhandler = @import("../command.zig");
```

with

```zig
const commandhandler = @import("../command.zig");
const Login = @import("login.zig");
const Clock = @import("../utils/clock.zig");
```

and replace

```zig
const max_signature = 256;
```

with

```zig
const max_signature = 256;
const max_nickname = 32;
```

Then add, right before `test "a signature is cut on a character boundary"`:

```zig
// The name as typed without the spaces around it; null if that is empty, longer than 32 bytes or not UTF-8.
pub fn cleanNickname(raw: []const u8) ?[]const u8 {
    if (!std.unicode.utf8ValidateSlice(raw)) return null;
    const name = std.mem.trim(u8, raw, " \t\r\n");
    if (name.len == 0 or name.len > max_nickname) return null;
    return name;
}

pub fn onSetNickname(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetNicknameCsReq, allocator);
    defer req.deinit();
    const name = cleanNickname(req.nickname.getSlice()) orelse {
        try session.send(CmdID.CmdSetNicknameScRsp, protocol.SetNicknameScRsp{
            .retcode = @intCast(@intFromEnum(protocol.Retcode.RET_NICKNAME_FORMAT_ERROR)),
            .is_modify = req.is_modify,
        });
        return;
    };
    if (!std.mem.eql(u8, name, ProfileStore.get().nickname)) ProfileStore.set("nickname", name);
    try session.send(CmdID.CmdSetNicknameScRsp, protocol.SetNicknameScRsp{
        .retcode = 0,
        .is_modify = req.is_modify,
        .set_time = @intCast(Clock.nowSec()),
    });
    // The new name shows at once, with the rest of the basic info as at login.
    var sync = protocol.PlayerSyncScNotify.init(allocator);
    sync.basic_info = Login.basicInfo(allocator);
    try session.send(CmdID.CmdPlayerSyncScNotify, sync);
}

// The Trailblazer's path as the client names it.
fn curAvatarPath() protocol.MultiPathAvatarType {
    return @enumFromInt(@as(i32, @intCast(AvatarManager.mc_id)));
}

// Gender follows the Trailblazer in config.json (/hero gender changes it), so this only reports the current path.
pub fn onSetGender(session: *Session, _: *const Packet, _: Allocator) !void {
    try session.send(CmdID.CmdSetGenderScRsp, protocol.SetGenderScRsp{
        .retcode = 0,
        .cur_avatar_path = curAvatarPath(),
    });
}

// The opening's name-and-gender step. The opening never runs here, so it is only answered.
pub fn onSetPlayerInfo(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SetPlayerInfoCsReq, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdSetPlayerInfoScRsp, protocol.SetPlayerInfoScRsp{
        .retcode = 0,
        .is_modify = req.is_modify,
        .set_time = @intCast(Clock.nowSec()),
        .cur_avatar_path = curAvatarPath(),
    });
}

test "a nickname is trimmed and must be 1 to 32 bytes of UTF-8" {
    try std.testing.expectEqualStrings("Stelle", cleanNickname("  Stelle \t").?);
    try std.testing.expect(cleanNickname("   ") == null);
    try std.testing.expect(cleanNickname("") == null);
    try std.testing.expectEqualStrings("a" ** 32, cleanNickname("a" ** 32).?);
    try std.testing.expect(cleanNickname("a" ** 33) == null);
    try std.testing.expect(cleanNickname("\xff\xfe") == null);
    // Thai letters are 3 bytes: ten fit, eleven do not.
    try std.testing.expect(cleanNickname("ก" ** 10) != null);
    try std.testing.expect(cleanNickname("ก" ** 11) == null);
}
```

**3c.** `gameserver/src/handlers.zig`. Replace

```zig
    .{ CmdID.CmdSetIsDisplayAvatarInfoCsReq, profile.onSetIsDisplayAvatarInfo },
```

with

```zig
    .{ CmdID.CmdSetIsDisplayAvatarInfoCsReq, profile.onSetIsDisplayAvatarInfo },
    .{ CmdID.CmdSetNicknameCsReq, profile.onSetNickname },
    .{ CmdID.CmdSetGenderCsReq, profile.onSetGender },
    .{ CmdID.CmdSetPlayerInfoCsReq, profile.onSetPlayerInfo },
```

(`services/profile.zig` is already in `unit_tests.zig` from Task 12.)

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_nickname.py && python tests/test_player_board.py
```

Expected: unit tests pass (including `a nickname is trimmed ...`); `test_nickname.py` ends with `15 passed, 0 failed`;
`test_player_board.py` still `40 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/services/login.zig gameserver/src/services/profile.zig gameserver/src/handlers.zig tests/test_nickname.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Let the player rename themselves

SetNickname, SetGender and SetPlayerInfo had no handler, so renaming
hung waiting for a reply and the name was always "ReversedRooms". A new
name (1 to 32 bytes of UTF-8 once the spaces around it are trimmed) is
saved in profile.json, answered, and pushed with a PlayerSyncScNotify
carrying the same basic info as login; PlayerLogin uses it too. Other
names get RET_NICKNAME_FORMAT_ERROR. MushiSR's own name does not change.

SetGender only answers with the current Trailblazer path: gender comes
from the Trailblazer in config.json. SetPlayerInfo, from the opening the
server skips, is only answered.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 15: Mail read/delete/take persist

**Files:**
- Modify: `gameserver/src/services/mail.zig` (whole file replaced)
- Modify: `gameserver/src/handlers.zig` (register MarkReadMail 831→887, DelMail 805→871)
- Modify: `gameserver/src/unit_tests.zig`
- Test: `tests/test_mail.py` (+ Zig test `withIds`)

**Interfaces:**
- Consumes: `ProfileStore.get().mail`, `ProfileStore.set("mail", ProfileStore.MailState{...})` (Task 2)
- Produces: nothing used later

Decisions: DelMail is all or nothing (one unknown id → `RET_MAIL_MAIL_ID_INVALID` 1702, nothing deleted). A deleted
mail counts as unknown. TakeMailAttachment skips unknown, deleted and already-taken ids (they are not in
`succ_mail_id_list`) and grants no items.

- [ ] **Step 1: Write the failing test** — create `tests/test_mail.py`:

```python
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
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_mail.py
```

Expected: `ok one unread mail with an attachment`, then
`AssertionError: MarkReadMailCsReq: no MarkReadMailScRsp (got [])`, exit code 1.

- [ ] **Step 3: Implement**

**3a.** Replace the whole of `gameserver/src/services/mail.zig` with:

```zig
const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const mail_id_invalid: u32 = @intCast(@intFromEnum(protocol.Retcode.RET_MAIL_MAIL_ID_INVALID));

// The server's only mail. What the player did with it (read, deleted, attachment taken) is kept in profile.json;
// taking the attachment grants nothing, items are not tracked.
const readme_id: u32 = 1;
const mail_ids = [_]u32{readme_id};

fn has(list: []const u32, id: u32) bool {
    return std.mem.indexOfScalar(u32, list, id) != null;
}
// A mail the player still has: one of ours, not deleted.
fn exists(id: u32) bool {
    return has(&mail_ids, id) and !has(ProfileStore.get().mail.deleted, id);
}

// `list` plus each id of `add` it does not have yet, in a new slice.
fn withIds(allocator: Allocator, list: []const u32, add: []const u32) ![]u32 {
    var out = try ArrayList(u32).initCapacity(allocator, list.len + add.len);
    out.appendSliceAssumeCapacity(list);
    for (add) |id| {
        if (!has(out.items, id)) out.appendAssumeCapacity(id);
    }
    return out.toOwnedSlice();
}

fn readme(allocator: Allocator) !protocol.ClientMail {
    const state = ProfileStore.get().mail;
    var mail = protocol.ClientMail.init(allocator);
    mail.sender = .{ .Const = "March 7th" };
    mail.title = .{ .Const = "Readme" };
    mail.is_read = has(state.read, readme_id);
    mail.id = readme_id;
    mail.content = .{ .Const = "MushiSR is a free and open-source software\nJoin our discord: https://discord.gg/reversedrooms\nUse https://relic-builder.vercel.app to setup relic :Đ" };
    mail.time = 1723334400;
    mail.expire_time = 17186330890;
    mail.mail_type = protocol.MailType.MAIL_TYPE_STAR;
    if (!has(state.taken, readme_id)) {
        var item_attachment = ArrayList(protocol.Item).init(allocator);
        try item_attachment.append(.{ .item_id = 1503, .num = 1 });
        mail.attachment = .{ .item_list = item_attachment };
    }
    return mail;
}

pub fn onGetMail(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetMailScRsp.init(allocator);
    if (exists(readme_id)) try rsp.mail_list.append(try readme(allocator));
    rsp.total_num = @intCast(rsp.mail_list.items.len);
    rsp.is_end = true;
    rsp.start = 0;
    rsp.retcode = 0;
    try session.send(CmdID.CmdGetMailScRsp, rsp);
}

pub fn onMarkReadMail(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.MarkReadMailCsReq, allocator);
    defer req.deinit();
    if (!exists(req.id)) {
        try session.send(CmdID.CmdMarkReadMailScRsp, protocol.MarkReadMailScRsp{ .retcode = mail_id_invalid, .id = req.id });
        return;
    }
    const state = ProfileStore.get().mail;
    if (!has(state.read, req.id)) {
        ProfileStore.set("mail", ProfileStore.MailState{
            .read = try withIds(allocator, state.read, &[_]u32{req.id}),
            .deleted = state.deleted,
            .taken = state.taken,
        });
    }
    try session.send(CmdID.CmdMarkReadMailScRsp, protocol.MarkReadMailScRsp{ .retcode = 0, .id = req.id });
}

pub fn onDelMail(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.DelMailCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.DelMailScRsp.init(allocator);
    // All or nothing: one unknown id refuses the whole request.
    for (req.id_list.items) |id| {
        if (!exists(id)) {
            rsp.retcode = mail_id_invalid;
            try session.send(CmdID.CmdDelMailScRsp, rsp);
            return;
        }
    }
    if (req.id_list.items.len > 0) {
        const state = ProfileStore.get().mail;
        ProfileStore.set("mail", ProfileStore.MailState{
            .read = state.read,
            .deleted = try withIds(allocator, state.deleted, req.id_list.items),
            .taken = state.taken,
        });
    }
    rsp.retcode = 0;
    try rsp.id_list.appendSlice(req.id_list.items);
    try session.send(CmdID.CmdDelMailScRsp, rsp);
}

pub fn onTakeMailAttachment(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.TakeMailAttachmentCsReq, allocator);
    defer req.deinit();
    const state = ProfileStore.get().mail;
    // An empty list takes every attachment still there.
    const wanted: []const u32 = if (req.mail_id_list.items.len > 0) req.mail_id_list.items else &mail_ids;
    var rsp = protocol.TakeMailAttachmentScRsp.init(allocator);
    rsp.retcode = 0;
    for (wanted) |id| {
        if (exists(id) and !has(state.taken, id) and !has(rsp.succ_mail_id_list.items, id)) {
            try rsp.succ_mail_id_list.append(id);
        }
    }
    const taken = rsp.succ_mail_id_list.items;
    if (taken.len > 0) {
        ProfileStore.set("mail", ProfileStore.MailState{
            .read = try withIds(allocator, state.read, taken),
            .deleted = state.deleted,
            .taken = try withIds(allocator, state.taken, taken),
        });
    }
    try session.send(CmdID.CmdTakeMailAttachmentScRsp, rsp);
}

test "mail id sets only grow by ids they do not have" {
    const allocator = std.testing.allocator;
    const ids = try withIds(allocator, &[_]u32{ 1, 2 }, &[_]u32{ 2, 3, 3 });
    defer allocator.free(ids);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 2, 3 }, ids);
}
```

**3b.** `gameserver/src/handlers.zig`. Replace

```zig
    .{ CmdID.CmdTakeMailAttachmentCsReq, mail.onTakeMailAttachment },
```

with

```zig
    .{ CmdID.CmdTakeMailAttachmentCsReq, mail.onTakeMailAttachment },
    .{ CmdID.CmdMarkReadMailCsReq, mail.onMarkReadMail },
    .{ CmdID.CmdDelMailCsReq, mail.onDelMail },
```

**3c.** `gameserver/src/unit_tests.zig`: inside the `test { ... }` block add

```zig
    _ = @import("services/mail.zig");
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_mail.py
```

Expected: unit tests pass; `test_mail.py` ends with `17 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/services/mail.zig gameserver/src/handlers.zig gameserver/src/unit_tests.zig tests/test_mail.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Remember which mail was read, deleted or emptied

The Readme mail came back unread with its attachment on every login,
and reading or deleting it got no reply. MarkReadMail and DelMail are
now answered, and the mail's state (read, deleted, attachment taken) is
kept in profile.json. Unknown or deleted ids get
RET_MAIL_MAIL_ID_INVALID, as in March7thHoney; a DelMail with one of
them deletes nothing. TakeMailAttachment with an empty list takes every
attachment and marks those mails read. No item reaches the bag: items
are not tracked.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 16: Pet

**Files:**
- Modify: `gameserver/src/data.zig` (`Pet`, `Pets`; 251005 in `ItemList`)
- Create: `gameserver/src/services/pet.zig`
- Modify: `gameserver/src/handlers.zig` (GetPetData 7612→7604, SummonPet 7611→7615, RecallPet 7616→7607; BlindBoxGetData 10052→10039 and PetMarbleGetData 10195→10188 into DummyCmdList)
- Modify: `gameserver/src/unit_tests.zig`
- Test: `tests/test_pet.py`

**Interfaces:**
- Consumes: `ProfileStore.get().pet`, `ProfileStore.set("pet", u32)` (Task 2)
- Produces: `Data.Pet`, `Data.Pets`

Decisions (not checked with the real client yet): `LLGIIPALELD` (enum `EOGNOEJHAGN`) is echoed from the last summon
and kept in memory only, so after a restart GetPetData sends the default 0. `NHCAOLGBGIF` is left false. Summoning
the pet that is already out sends no PetDataChangeScNotify (as M7H). RecallPet sends no notify and an empty
`PLKBLNMOOPH`. An unknown pet or a blind-box uid (`EBAAFDHEPLO`) keeps the current pet. A saved pet that is not in
`Data.Pets` (a hand edit) counts as no pet (`curPet()`).

- [ ] **Step 1: Write the failing test** — create `tests/test_pet.py`:

```python
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def pet_data(c):
    rsp, _ = c.call("GetPetDataCsReq", {}, "GetPetDataScRsp")
    return rsp


with Server() as srv:
    c = srv.login()
    rsp = pet_data(c)
    check("all five pets unlocked", rsp.get("HCAKDJMKDJP") == [1001, 1002, 1003, 1004, 1005], rsp)
    check("no pet out", "PLKBLNMOOPH" not in rsp, rsp)

    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 1003}, "SummonPetScRsp")
    names = [p.name for p in pkts]
    check("change notify before the reply", "PetDataChangeScNotify" in names
          and names.index("PetDataChangeScNotify") < names.index("SummonPetScRsp"), names)
    if packets_named(pkts, "PetDataChangeScNotify"):
        note = packets_named(pkts, "PetDataChangeScNotify")[0].msg()
        change = note.get("DGNGMJMPFGK", [{}])[0].get("GJALNEHICDE", {})
        check("notify names pet 1003", change.get("ODNGMIJLKKA") == 1003 and change.get("LLGIIPALELD") == 1, note)
    cur = rsp.get("PLKBLNMOOPH", {})
    check("reply: pet 1003, kind echoed", cur.get("ODNGMIJLKKA") == 1003 and cur.get("LLGIIPALELD") == 1
          and rsp.get("retcode", 0) == 0, rsp)

    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 9999}, "SummonPetScRsp")
    check("unknown pet: current one kept, no notify", rsp.get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1003
          and not packets_named(pkts, "PetDataChangeScNotify"), rsp)
    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 3, "EBAAFDHEPLO": 123456789}, "SummonPetScRsp")
    check("blind-box pet: current one kept", rsp.get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1003
          and not packets_named(pkts, "PetDataChangeScNotify"), rsp)
    rsp, pkts = c.call("SummonPetCsReq", {"LLGIIPALELD": 1, "ODNGMIJLKKA": 1003}, "SummonPetScRsp")
    check("same pet again: no notify", not packets_named(pkts, "PetDataChangeScNotify"), [p.name for p in pkts])
    check("saved in profile.json", saved(srv).get("pet") == 1003)

    srv.restart()
    c = srv.login()
    check("pet survives a restart", pet_data(c).get("PLKBLNMOOPH", {}).get("ODNGMIJLKKA") == 1003)

    rsp, _ = c.call("RecallPetCsReq", {}, "RecallPetScRsp")
    check("recall", rsp.get("retcode", 0) == 0 and "PLKBLNMOOPH" not in rsp, rsp)
    check("no pet out after recall", "PLKBLNMOOPH" not in pet_data(c) and saved(srv).get("pet") == 0)

    for req, rsp_name in (("BlindBoxGetDataCsReq", "BlindBoxGetDataScRsp"), ("PetMarbleGetDataCsReq", "PetMarbleGetDataScRsp")):
        _, pkts = c.call(req, {}, rsp_name)
        check(f"{req} answered", bool(packets_named(pkts, rsp_name)))
    rsp, _ = c.call("GetBagCsReq", {}, "GetBagScRsp")
    check("pet item 251005 in the bag", 251005 in [m.get("tid") for m in rsp.get("material_list", [])])

# A hand-edited profile.json with a pet that does not exist means no pet out.
with Server(files={"profile.json": '{"pet": 9999}'}) as srv:
    c = srv.login()
    rsp = pet_data(c)
    check("unknown saved pet: no pet out", "PLKBLNMOOPH" not in rsp and rsp.get("retcode", 0) == 0, rsp)
done()
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_pet.py
```

Expected: `AssertionError: GetPetDataCsReq: no GetPetDataScRsp (got [])`, exit code 1.

- [ ] **Step 3: Implement**

**3a.** `gameserver/src/data.zig`. Replace

```zig
pub const ItemList = [_]u32{ 251001, 251002, 251003, 251004, 101, 238, 239 };
```

with

```zig
pub const ItemList = [_]u32{ 251001, 251002, 251003, 251004, 251005, 101, 238, 239 };

// Pets (PetConfig): pet id, its item and its summon unit. The summon units are IsClient, so the client spawns a
// summoned pet itself and the server only remembers which one is out.
pub const Pet = struct { id: u32, item_id: u32, summon_unit_id: u32 };
pub const Pets = [_]Pet{
    .{ .id = 1001, .item_id = 251001, .summon_unit_id = 24001 },
    .{ .id = 1002, .item_id = 251002, .summon_unit_id = 32001 },
    .{ .id = 1003, .item_id = 251003, .summon_unit_id = 36001 },
    .{ .id = 1004, .item_id = 251004, .summon_unit_id = 42001 },
    .{ .id = 1005, .item_id = 251005, .summon_unit_id = 44001 },
};
```

**3b.** Create `gameserver/src/services/pet.zig`:

```zig
const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const Data = @import("../data.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

// Every pet of Data.Pets is unlocked; the one that is out is kept in profile.json (0 = none).

// How the client tagged its last summon (LLGIIPALELD, meaning unknown), sent back as it came. Memory only.
var summon_kind: protocol.EOGNOEJHAGN = @enumFromInt(0);

fn known(pet_id: u32) bool {
    for (Data.Pets) |pet| {
        if (pet.id == pet_id) return true;
    }
    return false;
}
fn curPet() u32 {
    const saved = ProfileStore.get().pet;
    return if (known(saved)) saved else 0;
}
fn petState(pet_id: u32) protocol.EHDNPMEKPCA {
    return .{ .LLGIIPALELD = summon_kind, .HGEOKHHJAIE = .{ .ODNGMIJLKKA = pet_id } };
}
fn curState() ?protocol.EHDNPMEKPCA {
    const pet_id = curPet();
    return if (pet_id == 0) null else petState(pet_id);
}

pub fn onGetPetData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetPetDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (Data.Pets) |pet| try rsp.HCAKDJMKDJP.append(pet.id);
    rsp.PLKBLNMOOPH = curState();
    try session.send(CmdID.CmdGetPetDataScRsp, rsp);
}

pub fn onSummonPet(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.SummonPetCsReq, allocator);
    defer req.deinit();
    // Pets by id only; blind-box pets (EBAAFDHEPLO) are not kept.
    const pet_id: u32 = if (req.HGEOKHHJAIE) |target| switch (target) {
        .ODNGMIJLKKA => |id| id,
        .EBAAFDHEPLO => 0,
    } else 0;
    if (known(pet_id)) {
        summon_kind = req.LLGIIPALELD;
        if (pet_id != curPet()) {
            ProfileStore.set("pet", pet_id);
            var change = protocol.PetDataChangeScNotify.init(allocator);
            try change.DGNGMJMPFGK.append(.{ .MMCGBGDJIPN = .{ .GJALNEHICDE = petState(pet_id) } });
            try session.send(CmdID.CmdPetDataChangeScNotify, change);
        }
    }
    try session.send(CmdID.CmdSummonPetScRsp, protocol.SummonPetScRsp{
        .retcode = 0,
        .PLKBLNMOOPH = curState(),
    });
}

pub fn onRecallPet(session: *Session, _: *const Packet, _: Allocator) !void {
    if (ProfileStore.get().pet != 0) ProfileStore.set("pet", @as(u32, 0));
    try session.send(CmdID.CmdRecallPetScRsp, protocol.RecallPetScRsp{
        .retcode = 0,
        .PLKBLNMOOPH = null,
    });
}

test "every pet's item is in the bag" {
    for (Data.Pets) |pet| {
        try std.testing.expect(std.mem.indexOfScalar(u32, &Data.ItemList, pet.item_id) != null);
    }
}
```

**3c.** `gameserver/src/handlers.zig`. Replace

```zig
const challenge = @import("services/challenge.zig");
```

with

```zig
const challenge = @import("services/challenge.zig");
const pet = @import("services/pet.zig");
```

Replace

```zig
    //mission
```

with

```zig
    //pet
    .{ CmdID.CmdGetPetDataCsReq, pet.onGetPetData },
    .{ CmdID.CmdSummonPetCsReq, pet.onSummonPet },
    .{ CmdID.CmdRecallPetCsReq, pet.onRecallPet },
    //mission
```

Replace (end of DummyCmdList)

```zig
    .{ CmdID.CmdB51RacingGetDataCsReq, CmdID.CmdB51RacingGetDataScRsp },
};
```

with

```zig
    .{ CmdID.CmdB51RacingGetDataCsReq, CmdID.CmdB51RacingGetDataScRsp },
    .{ CmdID.CmdBlindBoxGetDataCsReq, CmdID.CmdBlindBoxGetDataScRsp },
    .{ CmdID.CmdPetMarbleGetDataCsReq, CmdID.CmdPetMarbleGetDataScRsp },
};
```

**3d.** `gameserver/src/unit_tests.zig`: inside the `test { ... }` block add

```zig
    _ = @import("services/pet.zig");
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_pet.py
```

Expected: unit tests pass (including `every pet's item is in the bag`); `test_pet.py` ends with `16 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gameserver/src/data.zig gameserver/src/services/pet.zig gameserver/src/handlers.zig gameserver/src/unit_tests.zig tests/test_pet.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Let the player summon and recall pets

GetPetData, SummonPet and RecallPet went unanswered, as did the
BlindBoxGetData and PetMarbleGetData requests sent at login. All five
pets (PetConfig 1001-1005) are now unlocked; summoning one sends a
PetDataChangeScNotify and its reply, and the pet that is out is kept in
profile.json. The client spawns the pet itself (its summon unit is
IsClient). Pet item 251005 joins the bag. BlindBox and PetMarble get
empty replies.

The summon's LLGIIPALELD tag is echoed back unchanged; what its values
mean is not known yet.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 17: Jukebox

**Files:**
- Create: `resources/BackGroundMusic.json` (generated by the Python step below)
- Create: `gameserver/src/data/jukebox_config.zig`
- Modify: `gameserver/src/manager/config_mgr.zig` (load it into `background_music_config`)
- Create: `gameserver/src/services/jukebox.zig`
- Modify: `gameserver/src/handlers.zig` (GetJukeboxData 3174→3119, PlayBackGroundMusic 3131→3187, FKLMGEFILDI 3159→EGDFPDHNOKO 3118, UnlockBackGroundMusic 3105→3171; drop the GetJukeboxData dummy entry)
- Modify: `gameserver/src/unit_tests.zig`
- Test: `tests/test_jukebox.py` (+ Zig tests in `jukebox_config.zig` and `jukebox.zig`)

**Interfaces:**
- Consumes: `ProfileStore.get().jukebox_track`, `ProfileStore.set("jukebox_track", u32)` (Task 2)
- Produces: `ConfigManager.global_game_config_cache.background_music_config` (`JukeboxConfig.BackGroundMusicConfig`
  with `.tracks` and `.find(id) ?Track`); `jukebox.parsePlay`, `jukebox.encodePlayReply`

CmdIDs checked in `protocol/src/root.zig`: 3105 `CmdUnlockBackGroundMusicCsReq`, 3118 `CmdEGDFPDHNOKO`,
3119 `CmdGetJukeboxDataScRsp`, 3131 `CmdPlayBackGroundMusicCsReq`, 3159 `CmdFKLMGEFILDI`,
3171 `CmdUnlockBackGroundMusicScRsp`, 3174 `CmdGetJukeboxDataCsReq`, 3187 `CmdPlayBackGroundMusicScRsp`.

Decisions: track 0 is accepted on 3131 (the game's own music); unknown ids keep the current track. The 3187 reply is
hand-encoded as `field 8 = track id, field 14 = MNCBEDBDDHL`, so `EGDFPDHNOKO` (the layout M7H sends) and our
`PlayBackGroundMusicScRsp` both read it; the MNCBEDBDDHL is the client's own (re-encoded) when it sent one for the track
that is now playing, else one built from the id. The first 3131 body of each run is logged as hex.

- [ ] **Step 1: Write the failing test** — create `tests/test_jukebox.py`:

```python
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
    check("283 tracks, all unlocked", len(tracks) == 283 and all(t.get("BIMDKNLMICG") for t in tracks), len(tracks))
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
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_jukebox.py
```

Expected: `FAIL 283 tracks, all unlocked 0` (the dummy reply is empty), `FAIL 210000 is in group 1`, then
`AssertionError: PlayBackGroundMusicCsReq: no PlayBackGroundMusicScRsp (got [])`, exit code 1.

- [ ] **Step 3: Implement**

**3a.** Generate `resources/BackGroundMusic.json` from DimbreathBot (data only; the script reads the download straight
from the network and never runs anything from it):

```bash
python -I - resources/BackGroundMusic.json <<'EOF'
import collections, json, sys, urllib.request

URL = "https://raw.githubusercontent.com/DimbreathBot/TurnBasedGameData/main/ExcelOutput/BackGroundMusic.json"
with urllib.request.urlopen(URL, timeout=60) as f:
    rows = json.load(f)
tracks = [{"id": int(r["ID"]), "group_id": int(r["GroupID"])} for r in rows]
groups = dict(collections.Counter(t["group_id"] for t in tracks))
# The 4.6.51 data as checked on 2026-10-15: 283 tracks in these groups.
expected = {1: 12, 2: 16, 3: 38, 4: 66, 5: 52, 6: 85, 21: 14}
assert len({t["id"] for t in tracks}) == len(tracks) == 283 and groups == expected, (len(tracks), groups)
with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
    f.write("[\n" + ",\n".join("  " + json.dumps(t) for t in tracks) + "\n]\n")
print(len(tracks), "tracks written")
EOF
head -3 resources/BackGroundMusic.json
```

Expected output: `283 tracks written`, then `[` and `  {"id": 210000, "group_id": 1},` and `  {"id": 210001, "group_id": 1},`.
(If the assert fires, DimbreathBot has moved past 4.6.51: stop and ask the lead.)

**3b.** Create `gameserver/src/data/jukebox_config.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// resources/BackGroundMusic.json: the jukebox tracks, trimmed from the game's BackGroundMusic excel to
// [{"id", "group_id"}].
pub const Track = struct { id: u32, group_id: u32 };

pub const BackGroundMusicConfig = struct {
    tracks: ArrayList(Track),

    pub fn deinit(self: *BackGroundMusicConfig) void {
        self.tracks.deinit();
    }
    pub fn find(self: *const BackGroundMusicConfig, id: u32) ?Track {
        for (self.tracks.items) |track| {
            if (track.id == id) return track;
        }
        return null;
    }
};

pub fn parseBackGroundMusicConfig(root: std.json.Value, allocator: Allocator) anyerror!BackGroundMusicConfig {
    if (root != .array) return error.InvalidBackGroundMusic;
    var tracks = ArrayList(Track).init(allocator);
    errdefer tracks.deinit();
    for (root.array.items) |row| {
        try tracks.append(.{ .id = try intField(row, "id"), .group_id = try intField(row, "group_id") });
    }
    return .{ .tracks = tracks };
}

fn intField(row: std.json.Value, key: []const u8) !u32 {
    if (row != .object) return error.InvalidBackGroundMusic;
    const value = row.object.get(key) orelse return error.InvalidBackGroundMusic;
    if (value != .integer) return error.InvalidBackGroundMusic;
    return std.math.cast(u32, value.integer) orelse error.InvalidBackGroundMusic;
}

test "BackGroundMusic.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 210000, \"group_id\": 1}, {\"id\": 210100, \"group_id\": 2}]", .{});
    defer parsed.deinit();
    var config = try parseBackGroundMusicConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 2), config.tracks.items.len);
    try std.testing.expectEqual(@as(u32, 2), config.find(210100).?.group_id);
    try std.testing.expect(config.find(1) == null);

    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 210000}]", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidBackGroundMusic, parseBackGroundMusicConfig(bad.value, allocator));
}
```

**3c.** `gameserver/src/manager/config_mgr.zig`. Replace

```zig
pub const AvatarConfig = @import("../data/avatar_config.zig");
```

with

```zig
pub const AvatarConfig = @import("../data/avatar_config.zig");
pub const JukeboxConfig = @import("../data/jukebox_config.zig");
```

Replace

```zig
    buff_info_config: MiscConfig.TextMapConfig,
```

with

```zig
    buff_info_config: MiscConfig.TextMapConfig,
    background_music_config: JukeboxConfig.BackGroundMusicConfig,
```

Replace

```zig
        errdefer buff_info_cfg.deinit(allocator);
        return .{
```

with

```zig
        errdefer buff_info_cfg.deinit(allocator);

        var background_music_cfg = try loadConfig(JukeboxConfig.BackGroundMusicConfig, JukeboxConfig.parseBackGroundMusicConfig, allocator, "resources/BackGroundMusic.json");
        errdefer background_music_cfg.deinit();
        return .{
```

Replace

```zig
            .buff_info_config = buff_info_cfg,
```

with

```zig
            .buff_info_config = buff_info_cfg,
            .background_music_config = background_music_cfg,
```

Replace

```zig
        self.buff_info_config.deinit(global_main_allocator);
```

with

```zig
        self.buff_info_config.deinit(global_main_allocator);
        self.background_music_config.deinit();
```

**3d.** Create `gameserver/src/services/jukebox.zig`:

```zig
const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.jukebox);

// The jukebox: every track of resources/BackGroundMusic.json is unlocked, and the one last played is kept in
// profile.json (0 = the game's own music).
const music_config = &ConfigManager.global_game_config_cache.background_music_config;

fn curTrack() u32 {
    const saved = ProfileStore.get().jukebox_track;
    return if (music_config.find(saved) != null) saved else 0;
}

// The now-playing state for track `id`.
fn nowPlaying(allocator: Allocator, id: u32) protocol.MNCBEDBDDHL {
    var state = protocol.MNCBEDBDDHL.init(allocator);
    state.JKNLCEEDAHJ = .{ .id = id };
    return state;
}

pub fn onGetJukeboxData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetJukeboxDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (music_config.tracks.items) |track| {
        try rsp.IOKAJIBHLMP.append(.{ .id = track.id, .group_id = track.group_id, .BIMDKNLMICG = true });
    }
    rsp.GFFOBALDBPM = nowPlaying(allocator, curTrack());
    try session.send(CmdID.CmdGetJukeboxDataScRsp, rsp);
}

pub const PlayRequest = struct {
    id: u32,
    // The request's MNCBEDBDDHL, re-encoded, when it came in that layout.
    state: ?[]u8 = null,
};

// Which layout the 4.6.51 client sends for 3131 is not known yet, so the first byte decides: 0x58 is FKLMGEFILDI
// (field 11, the track id), 0x6A is PlayBackGroundMusicCsReq (field 13, an MNCBEDBDDHL whose JKNLCEEDAHJ.id is the
// track). Anything else is null.
pub fn parsePlay(allocator: Allocator, body: []const u8) !?PlayRequest {
    if (body.len == 0) return null;
    switch (body[0]) {
        0x58 => {
            const req = try protocol.FKLMGEFILDI.decode(body, allocator);
            defer req.deinit();
            return .{ .id = req.JKFCKJNHLHI };
        },
        0x6A => {
            const req = try protocol.PlayBackGroundMusicCsReq.decode(body, allocator);
            defer req.deinit();
            const state = req.IKJNIKIGFLF orelse return null;
            const track = state.JKNLCEEDAHJ orelse return null;
            return .{ .id = track.id, .state = try state.encode(allocator) };
        },
        else => return null,
    }
}

// The 3187 reply both decoders read: EGDFPDHNOKO takes field 8 (the track id), PlayBackGroundMusicScRsp field 14
// (the state), and each skips the other's field. retcode 0 is left out, as protobuf does.
pub fn encodePlayReply(allocator: Allocator, id: u32, state: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.append(8 << 3); // field 8, varint
    try appendVarint(&out, id);
    try out.append(14 << 3 | 2); // field 14, length-delimited
    try appendVarint(&out, state.len);
    try out.appendSlice(state);
    return out.toOwnedSlice();
}
fn appendVarint(out: *std.ArrayList(u8), value: u64) !void {
    var v = value;
    while (v >= 0x80) : (v >>= 7) try out.append(@as(u8, @truncate(v)) | 0x80);
    try out.append(@as(u8, @truncate(v)));
}

// Session.send encodes a message; this one is encoded already.
const RawBody = struct {
    bytes: []const u8,
    pub fn encode(self: RawBody, allocator: Allocator) ![]u8 {
        return allocator.dupe(u8, self.bytes);
    }
};

var logged_play_body = false;

pub fn onPlayBackGroundMusic(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    // Once per run, to see which layout the real client sends.
    if (!logged_play_body) {
        logged_play_body = true;
        log.info("first PlayBackGroundMusicCsReq body: {}", .{std.fmt.fmtSliceHexLower(packet.body)});
    }
    const request = parsePlay(allocator, packet.body) catch |err| blk: {
        log.warn("PlayBackGroundMusicCsReq could not be read: {s}", .{@errorName(err)});
        break :blk null;
    };
    if (request) |r| {
        const valid = r.id == 0 or music_config.find(r.id) != null;
        if (valid and r.id != ProfileStore.get().jukebox_track) ProfileStore.set("jukebox_track", r.id);
    }
    const id = curTrack();
    // The client's own state goes back when it asked for the track that is now playing.
    const echoed: ?[]const u8 = if (request) |r| (if (r.id == id) r.state else null) else null;
    const state = echoed orelse try nowPlaying(allocator, id).encode(allocator);
    try session.send(CmdID.CmdPlayBackGroundMusicScRsp, RawBody{ .bytes = try encodePlayReply(allocator, id, state) });
}

// 3159 (FKLMGEFILDI) -> 3118 (EGDFPDHNOKO): what the pair is for is not known; the track id is echoed.
pub fn onEchoTrack(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.FKLMGEFILDI, allocator);
    defer req.deinit();
    try session.send(CmdID.CmdEGDFPDHNOKO, protocol.EGDFPDHNOKO{
        .JKFCKJNHLHI = req.JKFCKJNHLHI,
        .retcode = 0,
    });
}

// Every track is unlocked already; the known ones asked for are echoed as unlocked.
pub fn onUnlockBackGroundMusic(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.UnlockBackGroundMusicCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.UnlockBackGroundMusicScRsp.init(allocator);
    rsp.retcode = 0;
    for (req.LIGKEOLPFBE.items) |id| {
        const track = music_config.find(id) orelse continue;
        try rsp.IOKAJIBHLMP.append(.{ .id = track.id, .group_id = track.group_id, .BIMDKNLMICG = true });
        try rsp.BPFGBEBPEDP.append(id);
    }
    try session.send(CmdID.CmdUnlockBackGroundMusicScRsp, rsp);
}

test "both 3131 layouts give the track" {
    const allocator = std.testing.allocator;
    // FKLMGEFILDI {JKFCKJNHLHI (11) = 210005}
    const flat = (try parsePlay(allocator, &[_]u8{ 0x58, 0xD5, 0xE8, 0x0C })).?;
    try std.testing.expectEqual(@as(u32, 210005), flat.id);
    try std.testing.expect(flat.state == null);
    // PlayBackGroundMusicCsReq {IKJNIKIGFLF (13) = {JKNLCEEDAHJ (1) = {id (1) = 210005}}}
    const nested = (try parsePlay(allocator, &[_]u8{ 0x6A, 0x06, 0x0A, 0x04, 0x08, 0xD5, 0xE8, 0x0C })).?;
    defer allocator.free(nested.state.?);
    try std.testing.expectEqual(@as(u32, 210005), nested.id);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x0A, 0x04, 0x08, 0xD5, 0xE8, 0x0C }, nested.state.?);

    try std.testing.expect((try parsePlay(allocator, &[_]u8{})) == null);
    try std.testing.expect((try parsePlay(allocator, &[_]u8{ 0x07, 0x01 })) == null);
    if (parsePlay(allocator, &[_]u8{0x58})) |_| return error.TestUnexpectedResult else |_| {}
}

test "the 3187 reply reads as both EGDFPDHNOKO and PlayBackGroundMusicScRsp" {
    const allocator = std.testing.allocator;
    const state = [_]u8{ 0x0A, 0x04, 0x08, 0xD5, 0xE8, 0x0C };
    const body = try encodePlayReply(allocator, 210005, &state);
    defer allocator.free(body);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x40, 0xD5, 0xE8, 0x0C, 0x72, 0x06 } ++ state, body);

    const as_id = try protocol.EGDFPDHNOKO.decode(body, allocator);
    defer as_id.deinit();
    try std.testing.expectEqual(@as(u32, 210005), as_id.JKFCKJNHLHI);
    try std.testing.expectEqual(@as(u32, 0), as_id.retcode);
    const as_state = try protocol.PlayBackGroundMusicScRsp.decode(body, allocator);
    defer as_state.deinit();
    try std.testing.expectEqual(@as(u32, 210005), as_state.GFFOBALDBPM.?.JKNLCEEDAHJ.?.id);
}
```

**3e.** `gameserver/src/handlers.zig`. Replace

```zig
const pet = @import("services/pet.zig");
```

with

```zig
const pet = @import("services/pet.zig");
const jukebox = @import("services/jukebox.zig");
```

Replace

```zig
    //mission
```

with

```zig
    //jukebox
    .{ CmdID.CmdGetJukeboxDataCsReq, jukebox.onGetJukeboxData },
    .{ CmdID.CmdPlayBackGroundMusicCsReq, jukebox.onPlayBackGroundMusic },
    .{ CmdID.CmdFKLMGEFILDI, jukebox.onEchoTrack }, // -> EGDFPDHNOKO
    .{ CmdID.CmdUnlockBackGroundMusicCsReq, jukebox.onUnlockBackGroundMusic },
    //mission
```

and delete this DummyCmdList line:

```zig
    .{ CmdID.CmdGetJukeboxDataCsReq, CmdID.CmdGetJukeboxDataScRsp },
```

**3f.** `gameserver/src/unit_tests.zig`: inside the `test { ... }` block add

```zig
    _ = @import("data/jukebox_config.zig");
    _ = @import("services/jukebox.zig");
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_jukebox.py
```

Expected: unit tests pass (3 new ones); `test_jukebox.py` ends with `18 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add resources/BackGroundMusic.json gameserver/src/data/jukebox_config.zig gameserver/src/manager/config_mgr.zig gameserver/src/services/jukebox.zig gameserver/src/handlers.zig gameserver/src/unit_tests.zig tests/test_jukebox.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Play any jukebox track and remember the last one

The jukebox showed no tracks (empty GetJukeboxData) and playing one got
no reply. All 283 tracks of BackGroundMusic (resources/
BackGroundMusic.json, trimmed from DimbreathBot's ExcelOutput to id and
group) are now unlocked, and the track picked is kept in profile.json.

Which layout the client sends for PlayBackGroundMusic is not known: our
proto has an MNCBEDBDDHL in field 13, March7thHoney and the 1.2.3 RE
read FKLMGEFILDI (the id in field 11). The first byte picks one, and
the reply carries the id in field 8 and the state in field 14 so either
decoder reads it. The first request body of each run is logged as hex
to settle this with the real client. 3159 and UnlockBackGroundMusic
echo what they are sent.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 18: Battle College

**Files:**
- Create: `resources/BattleCollegeConfig.json`
- Create: `gameserver/src/data/college_config.zig`
- Modify: `gameserver/src/manager/config_mgr.zig` (load it into `battle_college_config`)
- Create: `gameserver/src/services/college.zig`
- Modify: `gameserver/src/services/battle.zig` (remove `onStartBattleCollege`; `onPVEBattleResult` calls `CollegeService.onBattleEnd` before its reply)
- Modify: `gameserver/src/handlers.zig` (StartBattleCollege 5787→5705 and GetBattleCollegeData 5774→5719 to `college`; drop the dummy entry)
- Modify: `gameserver/src/unit_tests.zig`
- Test: `tests/test_college.py` (+ Zig tests in `college_config.zig` and `college.zig`)

**Interfaces:**
- Consumes: `BattleManager.findStage(stage_id) ?*const StageConfig.Stage`, `BattleManager.BattleManager.createStageBattle(self, stage) !protocol.SceneBattleInfo`
  (Tasks 3/4; the team comes from `currentTeam()`, so `/calyx lineup` applies); `BattleService.on_battle`;
  `ProfileStore.get().college_finished`, `ProfileStore.set("college_finished", []const u32)` (Task 2); the `/calyx lineup` command (Task 3)
- Produces: `ConfigManager.global_game_config_cache.battle_college_config` (`CollegeConfig.BattleCollegeConfig` with `.rooms`, `.find(id) ?Room`);
  `college.onBattleEnd(session, req, allocator)`

Decisions: the change notify (5731) goes out only when a room is passed for the first time (as M7H); later wins
send nothing extra. A result counts for the room only if its `stage_id` is 0 or the room's stage (the same guard
challenge.zig uses); every battle result clears the pending room. An unknown room is answered with `RET_FAIL` and no
battle. `/debug`'s next-battle pick is not used or cleared by college battles.

- [ ] **Step 1: Write the failing test** — create `tests/test_college.py`:

```python
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named
sys.stdout.reconfigure(errors="backslashreplace")  # FAIL details may hold text the console cannot print


def saved(srv):
    return srv.read_json("profile.json") if os.path.exists(srv.path("profile.json")) else {}


def finished(c):
    rsp, _ = c.call("GetBattleCollegeDataCsReq", {}, "GetBattleCollegeDataScRsp")
    return rsp.get("finished_college_id_list", [])


def start(c, room):
    rsp, _ = c.call("StartBattleCollegeCsReq", {"id": room}, "StartBattleCollegeScRsp")
    return rsp


def result(c, end_status, stage_id):
    _, pkts = c.call("PVEBattleResultCsReq", {"end_status": end_status, "stage_id": stage_id}, "PVEBattleResultScRsp")
    return pkts


def notified(pkts):
    return bool(packets_named(pkts, "SyncBattleCollegeDataChangeScNotify"))


with Server() as srv:
    c = srv.login()
    check("nothing passed yet", finished(c) == [])

    rsp = start(c, 3)
    info = rsp.get("battle_info", {})
    waves = [[m.get("monster_id") for m in w.get("monster_list", [])] for w in info.get("monster_wave_list", [])]
    check("room 3 fights stage 400103", rsp.get("retcode", 0) == 0 and rsp.get("id") == 3 and info.get("stage_id") == 400103, rsp)
    check("with that stage's waves", waves == [[102202017], [102202015, 102202015, 102202015]], waves)
    check("and the current team", len(info.get("battle_avatar_list", [])) > 0, info.get("battle_avatar_list"))

    pkts = result(c, 1, 400103)
    names = [p.name for p in pkts]
    check("win: change notify before the battle result", notified(pkts)
          and names.index("SyncBattleCollegeDataChangeScNotify") < names.index("PVEBattleResultScRsp"), names)
    if notified(pkts):
        note = packets_named(pkts, "SyncBattleCollegeDataChangeScNotify")[0].msg()
        check("notify lists room 3", note.get("finished_college_id_list") == [3], note)
    check("saved in profile.json", saved(srv).get("college_finished") == [3])

    start(c, 3)
    check("second win of the same room: no notify", not notified(result(c, 1, 400103)))
    start(c, 5)
    check("a loss: no notify", not notified(result(c, 2, 400114)) and finished(c) == [3])
    start(c, 1)
    check("a result for another stage: not the room's", not notified(result(c, 1, 999)) and finished(c) == [3])

    # Room 1 fights 400101, the fixture's own stage: a later cocoon win must not pass it.
    start(c, 1)
    result(c, 2, 400101)
    c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    check("an ordinary battle after a room is not the room", not notified(result(c, 1, 400101)) and finished(c) == [3])

    rsp = start(c, 4)
    check("unknown room: refused, no battle", rsp.get("retcode", 0) != 0 and "battle_info" not in rsp, rsp)

    c.command("/calyx lineup 1310")
    rsp = start(c, 2)
    ids = [a.get("id") for a in rsp.get("battle_info", {}).get("battle_avatar_list", [])]
    check("/calyx lineup is the team", ids == [1310], ids)
    result(c, 2, 400102)
    c.command("/calyx off")

    srv.restart()
    c = srv.login()
    check("passed rooms survive a restart", finished(c) == [3])
done()
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
"$ZIG" build && python tests/test_college.py
```

Expected: `ok nothing passed yet` (dummy reply), `FAIL room 3 fights stage 400103 ...` (today it fights config.json's
battle), `FAIL with that stage's waves [[801201025, 801201025], [801201025]]`,
`FAIL win: change notify before the battle result ['PVEBattleResultScRsp']`, `FAIL unknown room: refused, no battle`, …,
last line `4 passed, 9 failed`, exit code 1.

- [ ] **Step 3: Implement**

**3a.** Create `resources/BattleCollegeConfig.json` (DimbreathBot `ExcelOutput/BattleCollegeConfig.json` trimmed to
`ID`/`StageID`, checked on 2026-10-15; all 13 stages are in `resources/StageConfig.json`):

```json
[
  {"id": 1, "stage_id": 400101},
  {"id": 2, "stage_id": 400102},
  {"id": 3, "stage_id": 400103},
  {"id": 11, "stage_id": 400104},
  {"id": 15, "stage_id": 400105},
  {"id": 16, "stage_id": 400106},
  {"id": 5, "stage_id": 400114},
  {"id": 6, "stage_id": 400113},
  {"id": 7, "stage_id": 400115},
  {"id": 8, "stage_id": 400111},
  {"id": 9, "stage_id": 400112},
  {"id": 17, "stage_id": 400108},
  {"id": 18, "stage_id": 400109}
]
```

Check every stage exists:

```bash
python -I -c "import json; s={x['StageID'] for x in json.load(open('resources/StageConfig.json', encoding='utf-8'))['stage_config']}; r=json.load(open('resources/BattleCollegeConfig.json', encoding='utf-8')); print(len(r), [x for x in r if x['stage_id'] not in s])"
```

Expected: `13 []`.

**3b.** Create `gameserver/src/data/college_config.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// resources/BattleCollegeConfig.json: each Battle College room and the stage it fights, trimmed from the game's
// BattleCollegeConfig excel to [{"id", "stage_id"}].
pub const Room = struct { id: u32, stage_id: u32 };

pub const BattleCollegeConfig = struct {
    rooms: ArrayList(Room),

    pub fn deinit(self: *BattleCollegeConfig) void {
        self.rooms.deinit();
    }
    pub fn find(self: *const BattleCollegeConfig, id: u32) ?Room {
        for (self.rooms.items) |room| {
            if (room.id == id) return room;
        }
        return null;
    }
};

pub fn parseBattleCollegeConfig(root: std.json.Value, allocator: Allocator) anyerror!BattleCollegeConfig {
    if (root != .array) return error.InvalidBattleCollegeConfig;
    var rooms = ArrayList(Room).init(allocator);
    errdefer rooms.deinit();
    for (root.array.items) |row| {
        try rooms.append(.{ .id = try intField(row, "id"), .stage_id = try intField(row, "stage_id") });
    }
    return .{ .rooms = rooms };
}

fn intField(row: std.json.Value, key: []const u8) !u32 {
    if (row != .object) return error.InvalidBattleCollegeConfig;
    const value = row.object.get(key) orelse return error.InvalidBattleCollegeConfig;
    if (value != .integer) return error.InvalidBattleCollegeConfig;
    return std.math.cast(u32, value.integer) orelse error.InvalidBattleCollegeConfig;
}

test "BattleCollegeConfig.json rows" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "[{\"id\": 3, \"stage_id\": 400103}, {\"id\": 11, \"stage_id\": 400104}]", .{});
    defer parsed.deinit();
    var config = try parseBattleCollegeConfig(parsed.value, allocator);
    defer config.deinit();
    try std.testing.expectEqual(@as(u32, 400104), config.find(11).?.stage_id);
    try std.testing.expect(config.find(4) == null);

    const bad = try std.json.parseFromSlice(std.json.Value, allocator, "{\"id\": 3}", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidBattleCollegeConfig, parseBattleCollegeConfig(bad.value, allocator));
}
```

**3c.** `gameserver/src/manager/config_mgr.zig`. Replace

```zig
pub const JukeboxConfig = @import("../data/jukebox_config.zig");
```

with

```zig
pub const JukeboxConfig = @import("../data/jukebox_config.zig");
pub const CollegeConfig = @import("../data/college_config.zig");
```

Replace

```zig
    background_music_config: JukeboxConfig.BackGroundMusicConfig,
```

with

```zig
    background_music_config: JukeboxConfig.BackGroundMusicConfig,
    battle_college_config: CollegeConfig.BattleCollegeConfig,
```

Replace

```zig
        errdefer background_music_cfg.deinit();
        return .{
```

with

```zig
        errdefer background_music_cfg.deinit();

        var battle_college_cfg = try loadConfig(CollegeConfig.BattleCollegeConfig, CollegeConfig.parseBattleCollegeConfig, allocator, "resources/BattleCollegeConfig.json");
        errdefer battle_college_cfg.deinit();
        return .{
```

Replace

```zig
            .background_music_config = background_music_cfg,
```

with

```zig
            .background_music_config = background_music_cfg,
            .battle_college_config = battle_college_cfg,
```

Replace

```zig
        self.background_music_config.deinit();
```

with

```zig
        self.background_music_config.deinit();
        self.battle_college_config.deinit();
```

**3d.** Create `gameserver/src/services/college.zig`:

```zig
const std = @import("std");
const protocol = @import("protocol");
const Session = @import("../Session.zig");
const Packet = @import("../Packet.zig");
const ConfigManager = @import("../manager/config_mgr.zig");
const BattleManager = @import("../manager/battle_mgr.zig");
const ProfileStore = @import("../manager/profile_store.zig");
const BattleService = @import("battle.zig");

const Allocator = std.mem.Allocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.college);

// Battle College: a room fights its own stage from StageConfig.json with the current team (the room's trial
// avatars are not given). Rooms passed are kept in profile.json; passing one grants nothing.
const college_config = &ConfigManager.global_game_config_cache.battle_college_config;

// The room being fought, until a battle result comes in.
const Pending = struct { id: u32, stage_id: u32 };
var pending: ?Pending = null;

// `finished` plus `id`; null if it is there already.
fn addFinished(allocator: Allocator, finished: []const u32, id: u32) !?[]u32 {
    if (std.mem.indexOfScalar(u32, finished, id) != null) return null;
    return try std.mem.concat(allocator, u32, &[_][]const u32{ finished, &[_]u32{id} });
}

// The passed rooms the config still has.
fn appendFinished(list: *std.ArrayList(u32)) !void {
    for (ProfileStore.get().college_finished) |id| {
        if (college_config.find(id) != null) try list.append(id);
    }
}

pub fn onGetBattleCollegeData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetBattleCollegeDataScRsp.init(allocator);
    rsp.retcode = 0;
    try appendFinished(&rsp.finished_college_id_list);
    try session.send(CmdID.CmdGetBattleCollegeDataScRsp, rsp);
}

pub fn onStartBattleCollege(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartBattleCollegeCsReq, allocator);
    defer req.deinit();
    const stage = blk: {
        const room = college_config.find(req.id) orelse break :blk null;
        break :blk BattleManager.findStage(room.stage_id);
    } orelse {
        log.warn("Battle College room {} has no stage", .{req.id});
        try session.send(CmdID.CmdStartBattleCollegeScRsp, protocol.StartBattleCollegeScRsp{
            .retcode = @intCast(@intFromEnum(protocol.Retcode.RET_FAIL)),
            .id = req.id,
        });
        return;
    };
    var battle_manager = BattleManager.BattleManager.init(allocator);
    const battle = try battle_manager.createStageBattle(stage);
    pending = .{ .id = req.id, .stage_id = stage.stage_id };
    BattleService.on_battle = true;
    try session.send(CmdID.CmdStartBattleCollegeScRsp, protocol.StartBattleCollegeScRsp{
        .retcode = 0,
        .id = req.id,
        .battle_info = battle,
    });
}

// From onPVEBattleResult, before its reply: the first win of a room is saved and the client told.
pub fn onBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const room = pending orelse return;
    pending = null;
    if (req.stage_id != 0 and req.stage_id != room.stage_id) return;
    if (req.end_status != .BATTLE_END_WIN) return;
    const finished = (try addFinished(allocator, ProfileStore.get().college_finished, room.id)) orelse return;
    ProfileStore.set("college_finished", finished);
    var notify = protocol.SyncBattleCollegeDataChangeScNotify.init(allocator);
    try appendFinished(&notify.finished_college_id_list);
    try session.send(CmdID.CmdSyncBattleCollegeDataChangeScNotify, notify);
}

test "a room joins the finished list once" {
    const allocator = std.testing.allocator;
    try std.testing.expect((try addFinished(allocator, &[_]u32{ 1, 3 }, 3)) == null);
    const grown = (try addFinished(allocator, &[_]u32{ 1, 3 }, 5)).?;
    defer allocator.free(grown);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 3, 5 }, grown);
}
```

**3e.** `gameserver/src/services/battle.zig`. Replace

```zig
const ChallengeService = @import("challenge.zig");
```

with

```zig
const ChallengeService = @import("challenge.zig");
const CollegeService = @import("college.zig");
```

Delete (it moves to `college.zig`):

```zig
pub fn onStartBattleCollege(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.StartBattleCollegeCsReq, allocator);
    defer req.deinit();
    var battle_manager = BattleManager.BattleManager.init(allocator);
    var battle = try battle_manager.createBattle();
    _ = &battle;
    on_battle = true;
    try session.send(CmdID.CmdStartBattleCollegeScRsp, protocol.StartBattleCollegeScRsp{
        .retcode = 0,
        .id = req.id,
        .battle_info = battle,
    });
}
```

Replace

```zig
    ChallengeService.onChallengeBattleEnd(session, &req, allocator) catch |err| {
        log.err("challenge battle end failed: {}", .{err});
    };
    try session.send(CmdID.CmdPVEBattleResultScRsp, rsp);
```

with

```zig
    ChallengeService.onChallengeBattleEnd(session, &req, allocator) catch |err| {
        log.err("challenge battle end failed: {}", .{err});
    };
    // So does Battle College's "room passed".
    CollegeService.onBattleEnd(session, &req, allocator) catch |err| {
        log.err("battle college end failed: {}", .{err});
    };
    try session.send(CmdID.CmdPVEBattleResultScRsp, rsp);
```

**3f.** `gameserver/src/handlers.zig`. Replace

```zig
const jukebox = @import("services/jukebox.zig");
```

with

```zig
const jukebox = @import("services/jukebox.zig");
const college = @import("services/college.zig");
```

Replace

```zig
    .{ CmdID.CmdStartBattleCollegeCsReq, battle.onStartBattleCollege },
```

with

```zig
    .{ CmdID.CmdStartBattleCollegeCsReq, college.onStartBattleCollege },
    .{ CmdID.CmdGetBattleCollegeDataCsReq, college.onGetBattleCollegeData },
```

and delete this DummyCmdList line:

```zig
    .{ CmdID.CmdGetBattleCollegeDataCsReq, CmdID.CmdGetBattleCollegeDataScRsp },
```

**3g.** `gameserver/src/unit_tests.zig`: inside the `test { ... }` block add

```zig
    _ = @import("data/college_config.zig");
    _ = @import("services/college.zig");
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
"$ZIG" build && (cd gameserver && "$ZIG" build test --summary all) && python tests/test_college.py && python tests/test_jukebox.py
```

Expected: unit tests pass (2 new ones); `test_college.py` ends with `14 passed, 0 failed`; `test_jukebox.py` still `18 passed, 0 failed`
(config_mgr changed). Then run every fake-client test once to be sure the battle-result change broke nothing:

```bash
for t in tests/test_*.py; do echo "== $t"; python "$t" | tail -1; done
```

Expected: every line `N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add resources/BattleCollegeConfig.json gameserver/src/data/college_config.zig gameserver/src/manager/config_mgr.zig gameserver/src/services/college.zig gameserver/src/services/battle.zig gameserver/src/handlers.zig gameserver/src/unit_tests.zig tests/test_college.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Run Battle College rooms on their own stages and remember passed ones

Every Battle College room fought config.json's battle, and the room
list showed nothing passed. A room now fights its own stage (resources/
BattleCollegeConfig.json, the 13 rooms of DimbreathBot's
BattleCollegeConfig trimmed to id and stage; all 13 stages are in
StageConfig.json) with its waves and level and the current team, so
/calyx lineup applies. The rooms' trial avatars are not given.

The first win of a room is kept in profile.json and announced with
SyncBattleCollegeDataChangeScNotify before the battle result, as in
March7thHoney. A result only counts for the room whose battle it ends.
GetBattleCollegeData lists the passed rooms. An unknown room gets
RET_FAIL. Passing grants nothing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

## Part C: challenge records (Tasks 19–20)

Spec: "สถิติ challenge" + "การทดสอบ" in `docs/superpowers/specs/2026-10-15-m7h-commands-profile-design.md`.
Rule from the user: **anything without a record keeps today's fake "all cleared" values** (nothing locks again); with a
record, show the real best record.

Tasks 19–20 run after Task 18; every before-snippet below matches the Tasks 1–18 state. Verification (2026-10-15): on a copy of the repo with Tasks 1–18 applied from this plan, Task 19 then Task 20 were each
built with Zig 0.14.1 and tested with the final harness (`tests/fakeclient`, one test at a time under its lock):
- `zig build test` (gameserver/): 20 tests on Tasks 1–18, 23 after Task 19, 26 after Task 20, all passing.
- Failing first: `tests/test_challenge_records.py` 18 passed / 26 failed on Tasks 1–18; `tests/test_peak_records.py`
  17 passed / 22 failed on Tasks 1–18 + Task 19. After each task: 44/44 and 39/39.
- All 19 fake-client tests (Tasks 1–20) pass, run one at a time: calyx 17, challenge_records 44, college 14, debug 12,
  faketime 7, hero 8, json 14, jukebox 18, mail 17, nickname 15, peak 11, peak_records 39, pet 15, phone 10,
  player_board 39, profile_store 8, scene 9, server_prefs 16, windy 12 (325 checks, 0 failed).
- Without records, `GetChallengeScRsp`, `GetChallengePeakDataScRsp`, `GetChallengeGroupStatisticsScRsp` and a single-node
  `ChallengeSettleNotify` are byte-identical to the Tasks 1–18 build.
- The plan was then re-extracted from this file and applied to a fresh Tasks 1–18 copy: identical files.

Working-tree `.zig` files are CRLF (core.autocrlf=true): apply the before→after edits with the Edit tool (it keeps the
line endings); write new files with LF like `tierce_mgr.zig`.

---

### Task 19: Classic MoC/PF/AS records

**Files:**
- Create: `gameserver/src/manager/record_mgr.zig` (records + `challenge.json` load/save, star rules, run tracking)
- Modify: `gameserver/src/data/challenge_config.zig` (parse `ChallengeTargetID` and `ChallengeCountDown`)
- Modify: `gameserver/src/services/challenge.zig` (GetChallenge, GetChallengeGroupStatistics, run start/node end, real
  star masks in `ChallengeSettleNotify` / `ChallengeBossPhaseSettleNotify`)
- Modify: `gameserver/src/main.zig` (`RecordManager.load(allocator)` at startup)
- Modify: `gameserver/src/unit_tests.zig` (list record_mgr.zig)
- Modify (local, not committed): `.git/info/exclude` (`challenge.json`, `challenge.json.bad`)
- Test: `tests/test_challenge_records.py` + Zig `test` blocks in `record_mgr.zig` (`classicStars`, `betterClassic`)

**Interfaces:**
- Consumes: Task 1 harness (`Server`, `check`, `done`, `packets_named`; `srv.restart/stop/start/login/path/read_json`,
  always inside `with Server() as srv:`), Task 1 `gameserver/src/unit_tests.zig`; existing `Logic.Challenge().NodeLineup`,
  `ChallengeTargets.find`, `ChallengeManager.findChallengeConfig`, `ChallengeManager.challengeModeOf`, `downedAvatars`
  (challenge.zig).
- Produces (Task 20 builds on these):
  - `record_mgr.zig`: `pub fn load(allocator)`, `pub fn save()`, `pub const NodeLineup`, `pub const Classic`
    (`stars_mask, rounds, scores[2], buffs[2], lineups[2]`, `stars()`, `score()`), `pub fn findClassic(id) ?*const Classic`,
    `pub const Totals`, `pub fn classicStars(target_ids, count_down, totals) u32`, `pub fn betterClassic(is_moc, new, old) bool`,
    `pub fn startClassicRun(full: bool)`, `pub fn endClassicNode(node, rounds, deaths)`, `pub const Finished`,
    `pub fn settleClassicRun(conf, done) u32`; private `SaveFile { classic }`, `loadFile`, `saveFile`.
  - `ChallengeConfig.ChallengeConfig.target_ids: ArrayList(u32)`, `.count_down: u32`.
  - `services/challenge.zig` imports `RecordManager` and `ChallengeConfig`; `sendChallengeSettle(session, is_win, star, allocator)`,
    `sendBossPhaseSettle(session, req, node, is_win, star, allocator)`.
  - `challenge.json`: `{"classic": [{"id", "stars_mask", "rounds", "score1", "score2", "buff1", "buff2", "lineup1": [], "lineup2": []}]}`.

Rules implemented (from the spec):
- A run is recorded only if it was started by `StartChallengeCsReq` at node 1 (`start_node == 1`; a `/id` custom start at
  node 2 and every `StartPartialChallengeCsReq` are not) and its last node was won. Single-node runs keep settling with 7.
- Stars are computed at the settle point, after the last node's cycles are in: bit *i* = target *i* of `ChallengeTargetID`;
  MoC `rounds_left` = `ChallengeCountDown -| (node1 + node2 cycles) >= param`, `dead_avatar` = downed characters (summed
  over both nodes, counted by the existing `downedAvatars`) `<= param` (the `challenge_targets.zig`/Starward rule; every
  current MoC row has param 0 = nobody downed), PF/AS `total_score` = node1 + node2 score `>= param`. A retried node's
  cycles/downed replace the failed try's.
- Better run: more stars (popcount, never a numeric `max` of masks); same count → MoC fewer cycles, PF/AS higher total.
- A full run with **0 stars** is reported as 0 but not recorded (a 0 mask would show the floor as never cleared).
- `GetChallenge`: record → `star` = mask, PF/AS `score_id`/`score_two` = node scores; no record → today's 7 / PF 40000.
- `GetChallengeGroupStatistics`: the group's highest floor with a record fills the oneof by mode (`challenge_default` /
  `challenge_story` / `challenge_boss`) with floor, star count (`EEJCPNAEKLJ`), cycles or total score, buffs, both node
  teams and `record_id` = challenge id; no record → no oneof (as today).

- [ ] **Step 1: Write the failing test**

Create `tests/test_challenge_records.py`:
```python
"""Classic MoC/PF/AS records: real stars on the settle screen, the best full run kept in challenge.json and shown by
GetChallenge / GetChallengeGroupStatistics; floors without a record still show fully cleared."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

WIN, LOSE = 1, 2
TEAM1, TEAM2 = [1310, 1415, 1501, 1303], [1224, 8005]
PF_BUFFS, AS_BUFFS = (3031354, 3031366), (3111092, 3111058)


def lineup(ids):
    return [{"id": i, "avatar_type": 3} for i in ids]


def fight(c, rounds, status=WIN, score=0, as_score=0, downed=0):
    """Ends the battle of the node in progress; returns every packet the server sent for it."""
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    stt = {"round_cnt": rounds}
    if score:
        stt["challenge_score"] = score
    if as_score:
        stt["battle_target_info"] = [{"key": 1, "value": {"battle_target_list": [{"id": 90005, "progress": as_score}]}}]
    if downed:
        stt["battle_avatar_list"] = [{"id": TEAM1[i], "die_times": 1} for i in range(downed)]
    body = {"end_status": status, "stage_id": info.get("battle_info", {}).get("stage_id", 0), "stt": stt}
    _, pkts = c.call("PVEBattleResultCsReq", body, "PVEBattleResultScRsp")
    return pkts


def run(c, cid, node1, node2, buffs=None):
    """A full run from node 1 (node1/node2 are fight() arguments); returns the packets of the last fight."""
    body = {"challenge_id": cid, "avatar_lineup_first": lineup(TEAM1), "avatar_lineup_second": lineup(TEAM2)}
    if buffs:
        body["stage_info"] = {"story_info" if cid < 30000 else "boss_info": {"buff_one": buffs[0], "buff_two": buffs[1]}}
    rsp, _ = c.call("StartChallengeCsReq", body, "StartChallengeScRsp")
    check(f"{cid} starts", rsp.get("retcode", 0) == 0, rsp)
    fight(c, **node1)
    if cid > 30000:
        c.call("EnterChallengeNextPhaseCsReq", {}, "EnterChallengeNextPhaseScRsp")
    pkts = fight(c, **node2)
    c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")
    return pkts


def partial(c, cid, rounds):
    rsp, _ = c.call("StartPartialChallengeCsReq", {"challenge_id": cid, "is_first_half": True}, "StartPartialChallengeScRsp")
    check(f"{cid} single node starts", rsp.get("retcode", 0) == 0, rsp)
    pkts = fight(c, rounds)
    c.call("LeaveChallengeCsReq", {}, "LeaveChallengeScRsp")
    return pkts


def star(pkts, name="ChallengeSettleNotify"):
    found = packets_named(pkts, name)
    return found[-1].msg().get("star", 0) if found else None


def challenges(c):
    rsp, _ = c.call("GetChallengeCsReq", {}, "GetChallengeScRsp")
    return {ch["challenge_id"]: ch for ch in rsp.get("challenge_list", [])}


def stats(c, group_id, kind):
    rsp, _ = c.call("GetChallengeGroupStatisticsCsReq", {"group_id": group_id}, "GetChallengeGroupStatisticsScRsp")
    return rsp.get(kind, {}).get("PPBHLLOJNEK")


def teams(record):
    return [[a["id"] for a in lst.get("avatar_list", [])] for lst in record.get("lineup_list", [])] if record else None


def score(ch):
    return ch.get("star", 0), ch.get("score_id", 0), ch.get("score_two", 0)


def saved_ids(srv):
    if not os.path.exists(srv.path("challenge.json")):
        return []
    return sorted(r["id"] for r in srv.read_json("challenge.json").get("classic", []))


with Server() as srv:
    c = srv.login()

    print("no records yet")
    ch = challenges(c)
    check("unplayed MoC 5612 shows 3 stars", score(ch[5612]) == (7, 0, 0), ch[5612])
    check("unplayed PF 20284 shows the fake 40000 scores", score(ch[20284]) == (7, 40000, 40000), ch[20284])
    check("unplayed AS 30234 shows 3 stars", score(ch[30234]) == (7, 0, 0), ch[30234])
    rsp, _ = c.call("GetChallengeGroupStatisticsCsReq", {"group_id": 1037}, "GetChallengeGroupStatisticsScRsp")
    check("group without a record has no statistics",
          rsp.get("group_id") == 1037 and not {"challenge_default", "challenge_story", "challenge_boss"} & rsp.keys(), rsp)

    print("MoC 5612 (30-cycle countdown; targets 251 >=10 left, 252 >=20 left, 253 nobody downed)")
    pkts = run(c, 5612, {"rounds": 8}, {"rounds": 8})
    check("run A (16 cycles) settles with stars 251 + 253", star(pkts) == 0b101, star(pkts))
    check("run A is the record", challenges(c)[5612].get("star") == 0b101)
    rec = stats(c, 1037, "challenge_default")
    check("group statistics show run A", rec and (rec.get("level"), rec.get("EEJCPNAEKLJ"), rec.get("round_count")) == (12, 2, 16), rec)
    check("group statistics show both node teams", teams(rec) == [TEAM1, TEAM2], teams(rec))

    pkts = run(c, 5612, {"rounds": 10, "downed": 1}, {"rounds": 10})
    check("run B (20 cycles, one downed) settles with 251 only", star(pkts) == 0b001, star(pkts))
    check("worse run B does not replace the record", challenges(c)[5612].get("star") == 0b101)
    rec = stats(c, 1037, "challenge_default")
    check("record still 16 cycles", rec and rec.get("round_count") == 16, rec)

    pkts = run(c, 5612, {"rounds": 6}, {"rounds": 6})
    check("run C (12 cycles) settles with 251 + 253", star(pkts) == 0b101, star(pkts))
    rec = stats(c, 1037, "challenge_default")
    check("as many stars in fewer cycles replaces the record", rec and rec.get("round_count") == 12, rec)

    print("single node runs")
    pkts = partial(c, 5612, 1)
    check("a single node still settles with every star", star(pkts) == 7, star(pkts))
    rec = stats(c, 1037, "challenge_default")
    check("a 1-cycle single node is not recorded", rec and rec.get("round_count") == 12, rec)
    partial(c, 5611, 1)
    check("5611 played only as a single node keeps the fake stars", challenges(c)[5611].get("star") == 7)
    check("challenge.json holds only the full run", saved_ids(srv) == [5612], saved_ids(srv))

    print("PF 20284 (targets 2001-2003: 40000 / 50000 / 60000 total)")
    pkts = run(c, 20284, {"rounds": 4, "score": 30000}, {"rounds": 4, "score": 40000 + 25000}, PF_BUFFS)
    check("55000 points settles with 2001 + 2002", star(pkts) == 0b011, star(pkts))
    check("GetChallenge shows the record's stars and node scores", score(challenges(c)[20284]) == (0b011, 30000, 25000))
    rec = stats(c, 2028, "challenge_story")
    check("story statistics: floor, stars, total score, buffs",
          rec and (rec.get("level"), rec.get("EEJCPNAEKLJ"), rec.get("score_id"), rec.get("buff_one"), rec.get("buff_two"))
          == (4, 2, 55000, *PF_BUFFS), rec)
    run(c, 20284, {"rounds": 4, "score": 30000}, {"rounds": 4, "score": 40000 + 20001}, PF_BUFFS)
    check("as many stars with a lower score keeps the record", score(challenges(c)[20284]) == (0b011, 30000, 25000))
    pkts = run(c, 20283, {"rounds": 4, "score": 10000}, {"rounds": 4, "score": 40000 + 10000})
    check("a run without stars settles with none", star(pkts) == 0, star(pkts))
    check("and is not recorded: 20283 keeps the fake values", score(challenges(c)[20283]) == (7, 40000, 40000))

    print("AS 30234 (targets 3001-3003: 4000 / 5200 / 6600 total)")
    pkts = run(c, 30234, {"rounds": 3, "as_score": 3000}, {"rounds": 3, "as_score": 2500}, AS_BUFFS)
    check("boss phase settle shows the real stars", star(pkts, "ChallengeBossPhaseSettleNotify") == 0b011,
          star(pkts, "ChallengeBossPhaseSettleNotify"))
    check("challenge settle shows the real stars", star(pkts) == 0b011, star(pkts))
    check("GetChallenge shows the AS record", score(challenges(c)[30234]) == (0b011, 3000, 2500))
    rec = stats(c, 3023, "challenge_boss")
    check("boss statistics: floor, stars, total score, buffs",
          rec and (rec.get("level"), rec.get("EEJCPNAEKLJ"), rec.get("score_id"), rec.get("buff_one"), rec.get("buff_two"))
          == (4, 2, 5500, *AS_BUFFS), rec)

    print("after a restart")
    check("challenge.json holds the three records", saved_ids(srv) == [5612, 20284, 30234], saved_ids(srv))
    srv.restart()
    c = srv.login()
    ch = challenges(c)
    check("5612 record survives", ch[5612].get("star") == 0b101, ch[5612])
    check("20284 record survives", score(ch[20284]) == (0b011, 30000, 25000), ch[20284])
    check("30234 record survives", score(ch[30234]) == (0b011, 3000, 2500), ch[30234])
    check("unplayed 5601 still shows 3 stars", ch[5601].get("star") == 7, ch[5601])
    rec = stats(c, 1037, "challenge_default")
    check("group statistics survive", rec and rec.get("round_count") == 12 and teams(rec) == [TEAM1, TEAM2], rec)

    print("a broken challenge.json")
    srv.stop()
    with open(srv.path("challenge.json"), "w", encoding="utf-8") as f:
        f.write("{ broken")
    srv.start()
    c = srv.login()
    check("every floor shows 3 stars again", challenges(c)[5612].get("star") == 7)
    check("the broken file is kept as challenge.json.bad", os.path.exists(srv.path("challenge.json.bad")))

done()
```

- [ ] **Step 2: Run it, expect FAIL**

From the repo root (Git Bash):
```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
"/g/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe" build
python tests/test_challenge_records.py; echo "exit $?"
```
Expected: the "no records yet" checks pass, then FAIL lines starting with
`FAIL run A (16 cycles) settles with stars 251 + 253 7` (every settle still says 7, GetChallenge never changes, group
statistics stay empty, no `challenge.json`, no `.bad`), ending `18 passed, 26 failed` and `exit 1` (measured on
Tasks 1–18).

- [ ] **Step 3: Implement**

**3a.** Create `gameserver/src/manager/record_mgr.zig`:
```zig
const std = @import("std");
const ChallengeConfig = @import("../data/challenge_config.zig");
const ChallengeTargets = @import("../data/challenge_targets.zig");
const Logic = @import("../utils/logic.zig");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.records);

// The best runs of MoC/PF/AS floors, kept in challenge.json next to config.json. A floor without a record keeps
// showing as fully cleared, as before records were kept, so nothing the player had open locks again.
const save_path = "challenge.json";
const bad_path = "challenge.json.bad";

pub const NodeLineup = Logic.Challenge().NodeLineup;

pub const Classic = struct {
    // Bit i: the floor's i-th star target (ChallengeTargetID order) was met.
    stars_mask: u32 = 0,
    rounds: u32 = 0,
    scores: [2]u32 = .{ 0, 0 },
    buffs: [2]u32 = .{ 0, 0 },
    lineups: [2]NodeLineup = .{ .{}, .{} },

    pub fn stars(self: *const Classic) u32 {
        return @popCount(self.stars_mask);
    }
    pub fn score(self: *const Classic) u32 {
        return self.scores[0] +| self.scores[1];
    }
};

var classic = std.AutoArrayHashMap(u32, Classic).init(std.heap.page_allocator);

pub fn findClassic(challenge_id: u32) ?*const Classic {
    return classic.getPtr(challenge_id);
}

pub const Totals = struct { rounds: u32 = 0, score: u32 = 0, deaths: u32 = 0 };

// The star mask a run with these totals earns. MoC counts the cycles left of the floor's countdown; PF/AS rows have
// no countdown (0) and score targets instead.
pub fn classicStars(target_ids: []const u32, count_down: u32, totals: Totals) u32 {
    var mask: u32 = 0;
    for (target_ids[0..@min(target_ids.len, 3)], 0..) |id, i| {
        const target = ChallengeTargets.find(id) orelse continue;
        const met = switch (target.kind) {
            .rounds_left => count_down > 0 and count_down -| totals.rounds >= target.param,
            .dead_avatar => totals.deaths <= target.param,
            .total_score => totals.score >= target.param,
        };
        if (met) mask |= @as(u32, 1) << @intCast(i);
    }
    return mask;
}

// More stars wins; as many stars wins with fewer cycles (MoC) or a higher score (PF/AS).
pub fn betterClassic(is_moc: bool, new: *const Classic, old: *const Classic) bool {
    if (new.stars() != old.stars()) return new.stars() > old.stars();
    return if (is_moc) new.rounds < old.rounds else new.score() > old.score();
}

// The MoC/PF/AS run in progress. Only a run started at node 1 can become a record; a retried node's cycles and
// downed characters replace the failed try's.
const ClassicRun = struct {
    full: bool = false,
    rounds: [2]u32 = .{ 0, 0 },
    deaths: [2]u32 = .{ 0, 0 },
};
var classic_run: ClassicRun = .{};

pub fn startClassicRun(full: bool) void {
    classic_run = .{ .full = full };
}
pub fn endClassicNode(node: u32, rounds: u32, deaths: u32) void {
    if (node < 1 or node > 2) return;
    classic_run.rounds[node - 1] = rounds;
    classic_run.deaths[node - 1] = deaths;
}

pub const Finished = struct {
    is_moc: bool,
    scores: [2]u32,
    buffs: [2]u32,
    lineups: [2]NodeLineup,
};

// The last node of a run was won: returns the star mask for the settle screens. A full run gets its own, and becomes
// the floor's record when it beats the one kept; a single node shows every star, as before, and is not kept. A run
// without stars is not kept either: its floor would show as never cleared.
pub fn settleClassicRun(conf: ?*const ChallengeConfig.ChallengeConfig, done: Finished) u32 {
    const c = conf orelse return 7;
    if (!classic_run.full) return 7;
    const totals = Totals{
        .rounds = classic_run.rounds[0] +| classic_run.rounds[1],
        .score = done.scores[0] +| done.scores[1],
        .deaths = classic_run.deaths[0] +| classic_run.deaths[1],
    };
    const run = Classic{
        .stars_mask = classicStars(c.target_ids.items, c.count_down, totals),
        .rounds = totals.rounds,
        .scores = done.scores,
        .buffs = done.buffs,
        .lineups = done.lineups,
    };
    log.info("challenge {} run: stars {b:0>3}, cycles {}, score {}, downed {}", .{ c.id, run.stars_mask, totals.rounds, totals.score, totals.deaths });
    if (run.stars_mask == 0) return 0;
    const entry = classic.getOrPut(c.id) catch |err| {
        log.err("challenge {} could not be recorded: {s}", .{ c.id, @errorName(err) });
        return run.stars_mask;
    };
    if (entry.found_existing and !betterClassic(done.is_moc, &run, entry.value_ptr)) return run.stars_mask;
    entry.value_ptr.* = run;
    save();
    return run.stars_mask;
}

const SavedClassic = struct {
    id: u32 = 0,
    stars_mask: u32 = 0,
    rounds: u32 = 0,
    score1: u32 = 0,
    score2: u32 = 0,
    buff1: u32 = 0,
    buff2: u32 = 0,
    lineup1: []const u32 = &.{},
    lineup2: []const u32 = &.{},
};
const SaveFile = struct {
    classic: []const SavedClassic = &.{},
};

// Loaded once at startup. A missing file is normal; a broken one is kept as challenge.json.bad and every challenge
// shows as fully cleared.
pub fn load(allocator: Allocator) void {
    loadFile(allocator) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("{s} could not be loaded ({s}); every challenge shows as fully cleared", .{ save_path, @errorName(err) });
            std.fs.cwd().copyFile(save_path, std.fs.cwd(), bad_path, .{}) catch |copy_err| {
                log.err("could not keep a copy as {s}: {s}", .{ bad_path, @errorName(copy_err) });
            };
        },
    };
}
fn loadFile(allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, save_path, 1 << 20);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(SaveFile, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    // Nothing is applied unless the whole file is valid.
    var loaded_classic = std.AutoArrayHashMap(u32, Classic).init(std.heap.page_allocator);
    errdefer loaded_classic.deinit();
    for (parsed.value.classic) |saved| {
        if (saved.stars_mask == 0 or saved.stars_mask > 7 or saved.lineup1.len > 4 or saved.lineup2.len > 4) return error.InvalidRecords;
        try loaded_classic.put(saved.id, .{
            .stars_mask = saved.stars_mask,
            .rounds = saved.rounds,
            .scores = .{ saved.score1, saved.score2 },
            .buffs = .{ saved.buff1, saved.buff2 },
            .lineups = .{ NodeLineup.fromSlice(saved.lineup1), NodeLineup.fromSlice(saved.lineup2) },
        });
    }
    classic.deinit();
    classic = loaded_classic;
}

// Written after every change; a failed write is logged and never drops the player.
pub fn save() void {
    saveFile() catch |err| log.err("{s} could not be saved: {s}", .{ save_path, @errorName(err) });
}
fn saveFile() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const saved_classic = try allocator.alloc(SavedClassic, classic.count());
    for (classic.keys(), classic.values(), saved_classic) |id, *record, *entry| {
        entry.* = .{
            .id = id,
            .stars_mask = record.stars_mask,
            .rounds = record.rounds,
            .score1 = record.scores[0],
            .score2 = record.scores[1],
            .buff1 = record.buffs[0],
            .buff2 = record.buffs[1],
            .lineup1 = record.lineups[0].slice(),
            .lineup2 = record.lineups[1].slice(),
        };
    }
    var out = std.ArrayList(u8).init(allocator);
    try std.json.stringify(SaveFile{ .classic = saved_classic }, .{ .whitespace = .indent_2 }, out.writer());
    var file = try std.fs.cwd().atomicFile(save_path, .{});
    defer file.deinit();
    try file.file.writeAll(out.items);
    try file.finish();
}

test "classic stars: MoC counts the cycles left of the countdown and the downed characters" {
    // 5612: 251 at least 10 cycles left, 252 at least 20, 253 nobody downed.
    const moc = [_]u32{ 251, 252, 253 };
    try std.testing.expectEqual(@as(u32, 0b101), classicStars(&moc, 30, .{ .rounds = 16 }));
    try std.testing.expectEqual(@as(u32, 0b111), classicStars(&moc, 30, .{ .rounds = 10 }));
    try std.testing.expectEqual(@as(u32, 0b011), classicStars(&moc, 30, .{ .rounds = 10, .deaths = 1 }));
    try std.testing.expectEqual(@as(u32, 0), classicStars(&moc, 30, .{ .rounds = 21, .deaths = 2 }));
    // The countdown stops at zero; without one no cycle target is met.
    try std.testing.expectEqual(@as(u32, 0b100), classicStars(&moc, 30, .{ .rounds = 45 }));
    try std.testing.expectEqual(@as(u32, 0b100), classicStars(&moc, 0, .{ .rounds = 1 }));
}

test "classic stars: PF and AS add up both nodes' scores" {
    const pf = [_]u32{ 2001, 2002, 2003 }; // 40000 / 50000 / 60000
    try std.testing.expectEqual(@as(u32, 0b011), classicStars(&pf, 0, .{ .score = 55000 }));
    try std.testing.expectEqual(@as(u32, 0b111), classicStars(&pf, 0, .{ .score = 60000 }));
    try std.testing.expectEqual(@as(u32, 0), classicStars(&pf, 0, .{ .score = 39999 }));
    const as = [_]u32{ 3001, 3002, 3003 }; // 4000 / 5200 / 6600
    try std.testing.expectEqual(@as(u32, 0b011), classicStars(&as, 0, .{ .score = 5500 }));
}

test "better classic run: more stars, then fewer cycles (MoC) or a higher score (PF/AS)" {
    const old = Classic{ .stars_mask = 0b101, .rounds = 16, .scores = .{ 30000, 25000 } };
    try std.testing.expect(betterClassic(true, &Classic{ .stars_mask = 0b111, .rounds = 20 }, &old));
    try std.testing.expect(!betterClassic(true, &Classic{ .stars_mask = 0b001, .rounds = 2 }, &old));
    // Stars are counted, not compared as numbers: 0b011 is as good as 0b101.
    try std.testing.expect(betterClassic(true, &Classic{ .stars_mask = 0b011, .rounds = 12 }, &old));
    try std.testing.expect(!betterClassic(true, &Classic{ .stars_mask = 0b110, .rounds = 16 }, &old));
    try std.testing.expect(betterClassic(false, &Classic{ .stars_mask = 0b101, .scores = .{ 30000, 25001 } }, &old));
    try std.testing.expect(!betterClassic(false, &Classic{ .stars_mask = 0b101, .rounds = 1, .scores = .{ 20000, 20000 } }, &old));
}
```

**3b.** `gameserver/src/data/challenge_config.zig`:

*ChallengeConfig struct: two new fields*

Before:
```zig
    maze_group_id2: ?u32,
    maze_buff_id: u32,
};
```
After:
```zig
    maze_group_id2: ?u32,
    maze_buff_id: u32,
    // Star targets in star-bit order, and the cycles a MoC floor's stars count down from (PF/AS rows have none: 0).
    target_ids: ArrayList(u32),
    count_down: u32,
};
```

*ChallengeMazeConfig.deinit: free the new list*

Before:
```zig
            challenge.event_id_list2.deinit();
        }
        self.challenge_config.deinit();
```
After:
```zig
            challenge.event_id_list2.deinit();
            challenge.target_ids.deinit();
        }
        self.challenge_config.deinit();
```

*parseChallengeConfig: initialise the new fields*

Before:
```zig
            .maze_group_id2 = if (challenge_json.object.get("MazeGroupID2")) |val| @intCast(val.integer) else null,
        };
```
After:
```zig
            .maze_group_id2 = if (challenge_json.object.get("MazeGroupID2")) |val| @intCast(val.integer) else null,
            .target_ids = ArrayList(u32).init(allocator),
            .count_down = if (challenge_json.object.get("ChallengeCountDown")) |val| @intCast(val.integer) else 0,
        };
```

*parseChallengeConfig: read ChallengeTargetID (every row has 3)*

Before:
```zig
        for (challenge_json.object.get("EventIDList2").?.array.items) |event2| {
            try challenge.event_id_list2.append(@intCast(event2.integer));
        }
        try challenge_config.append(challenge);
```
After:
```zig
        for (challenge_json.object.get("EventIDList2").?.array.items) |event2| {
            try challenge.event_id_list2.append(@intCast(event2.integer));
        }
        for (challenge_json.object.get("ChallengeTargetID").?.array.items) |target| {
            try challenge.target_ids.append(@intCast(target.integer));
        }
        try challenge_config.append(challenge);
```


**3c.** `gameserver/src/services/challenge.zig`:

*Imports (anchored on the TierceManager line; Task 5's `ProfileStore` import below it stays)*

Before:
```zig
const TierceManager = @import("../manager/tierce_mgr.zig");
```
After:
```zig
const TierceManager = @import("../manager/tierce_mgr.zig");
const RecordManager = @import("../manager/record_mgr.zig");
const ChallengeConfig = @import("../data/challenge_config.zig");
```

*onGetChallenge shows records; onGetChallengeGroupStatistics fills the oneof (+ two helpers)*

Before:
```zig
        challenge.challenge_id = ids.id;
        challenge.star = 7;
        challenge.taken_reward = 42;


        if (ids.id > 20000) {
            if (ids.id < 30000) {
                challenge.score_id = 40000;
                challenge.score_two = 40000;
            }
        }

        try rsp.challenge_list.append(challenge);
    }

    try session.send(CmdID.CmdGetChallengeScRsp, rsp);
}
pub fn onGetChallengeGroupStatistics(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetChallengeGroupStatisticsCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.GetChallengeGroupStatisticsScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.group_id = req.group_id;
    try session.send(CmdID.CmdGetChallengeGroupStatisticsScRsp, rsp);
}
```
After:
```zig
        challenge.challenge_id = ids.id;
        challenge.taken_reward = 42;
        // A floor with a record shows it; any other shows fully cleared, as before records were kept.
        if (RecordManager.findClassic(ids.id)) |record| {
            challenge.star = record.stars_mask;
            if (ids.id > 20000) {
                challenge.score_id = record.scores[0];
                challenge.score_two = record.scores[1];
            }
        } else {
            challenge.star = 7;
            if (ids.id > 20000 and ids.id < 30000) {
                challenge.score_id = 40000;
                challenge.score_two = 40000;
            }
        }

        try rsp.challenge_list.append(challenge);
    }

    try session.send(CmdID.CmdGetChallengeScRsp, rsp);
}
// The record of a group's highest floor that has one; a group without a record shows none, as before.
pub fn onGetChallengeGroupStatistics(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.GetChallengeGroupStatisticsCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.GetChallengeGroupStatisticsScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.group_id = req.group_id;
    var best: ?*const ChallengeConfig.ChallengeConfig = null;
    for (challenge_config.challenge_config.items) |*conf| {
        if (conf.group_id != req.group_id or RecordManager.findClassic(conf.id) == null) continue;
        if (best) |b| {
            if ((b.floor orelse 0) >= (conf.floor orelse 0)) continue;
        }
        best = conf;
    }
    if (best) |conf| rsp.EDKOHAAMONH = try groupStatistics(allocator, conf, RecordManager.findClassic(conf.id).?);
    try session.send(CmdID.CmdGetChallengeGroupStatisticsScRsp, rsp);
}
fn groupStatistics(
    allocator: Allocator,
    conf: *const ChallengeConfig.ChallengeConfig,
    record: *const RecordManager.Classic,
) !protocol.GetChallengeGroupStatisticsScRsp.EDKOHAAMONH_union {
    const level = conf.floor orelse 0;
    var lineups = ArrayList(protocol.ChallengeLineupList).init(allocator);
    for (&record.lineups) |*team| {
        if (team.len == 0) continue;
        var list = protocol.ChallengeLineupList.init(allocator);
        for (team.slice(), 0..) |id, index| {
            try list.avatar_list.append(.{ .id = id, .level = avatarLevel(id), .index = @intCast(index), .avatar_type = .AVATAR_FORMAL_TYPE });
        }
        try lineups.append(list);
    }
    // EEJCPNAEKLJ is the star count here (M7H), not the mask GetChallenge sends.
    return switch (ChallengeManager.challengeModeOf(conf.id)) {
        0 => .{ .challenge_default = .{
            .record_id = conf.id,
            .PPBHLLOJNEK = .{ .level = level, .EEJCPNAEKLJ = record.stars(), .round_count = record.rounds, .lineup_list = lineups },
        } },
        1 => .{ .challenge_story = .{
            .record_id = conf.id,
            .PPBHLLOJNEK = .{
                .level = level,
                .EEJCPNAEKLJ = record.stars(),
                .score_id = record.score(),
                .buff_one = record.buffs[0],
                .buff_two = record.buffs[1],
                .lineup_list = lineups,
            },
        } },
        else => .{ .challenge_boss = .{
            .record_id = conf.id,
            .PPBHLLOJNEK = .{
                .level = level,
                .EEJCPNAEKLJ = record.stars(),
                .score_id = record.score(),
                .buff_one = record.buffs[0],
                .buff_two = record.buffs[1],
                .lineup_list = lineups,
            },
        } },
    };
}
// The level config.json gives a character; 80 for one it no longer has.
fn avatarLevel(id: u32) u32 {
    for (ConfigManager.global_game_config_cache.game_config.avatar_config.items) |avatar| {
        if (avatar.id == id) return avatar.level;
    }
    return 80;
}
```

*onStartChallenge: a run started at node 1 may become a record*

Before:
```zig
    if (ChallengeManager.challengeModeOf(challenge_id) == 2) rsp.stage_info = try bossStageInfo(allocator);

    C.SetChallenge();
    try session.send(CmdID.CmdStartChallengeScRsp, rsp);
```
After:
```zig
    if (ChallengeManager.challengeModeOf(challenge_id) == 2) rsp.stage_info = try bossStageInfo(allocator);

    C.SetChallenge();
    RecordManager.startClassicRun(start_node == 1);
    try session.send(CmdID.CmdStartChallengeScRsp, rsp);
```

*onStartPartialChallenge: a single node never does*

Before:
```zig
    rsp.cur_challenge = try challenge_manager.buildCurChallenge();

    C.SetChallenge();
    try session.send(CmdID.CmdChallengeLineupNotify, protocol.ChallengeLineupNotify{
```
After:
```zig
    rsp.cur_challenge = try challenge_manager.buildCurChallenge();

    C.SetChallenge();
    // A single node never becomes the floor's record.
    RecordManager.startClassicRun(false);
    try session.send(CmdID.CmdChallengeLineupNotify, protocol.ChallengeLineupNotify{
```

*onChallengeBattleEnd: keep each node's cycles and downed characters*

Before:
```zig
    if (req.stt) |stt| C.AddRounds(stt.round_cnt);
    if (mode != 0) C.SetNodeScore(node, nodeScore(req, mode, node));
```
After:
```zig
    if (req.stt) |stt| {
        C.AddRounds(stt.round_cnt);
        RecordManager.endClassicNode(node, stt.round_cnt, downedAvatars(&stt));
    }
    if (mode != 0) C.SetNodeScore(node, nodeScore(req, mode, node));
```

*onChallengeBattleEnd: failures and the AS node-1 page keep star 0*

Before:
```zig
    if (!cleared) {
        C.SetStatus(.failed);
        if (mode == 2) {
            try sendBossPhaseSettle(session, null, node, false, allocator);
        } else {
            try sendChallengeSettle(session, false, allocator);
        }
        return;
    }
    if (node < C.LastNode()) {
        if (mode == 2) {
            // AS shows the node-1 result page and waits for EnterChallengeNextPhaseCsReq.
            C.SetAwaitingNextPhase(true);
            try sendBossPhaseSettle(session, req, node, false, allocator);
            return;
        }
```
After:
```zig
    if (!cleared) {
        C.SetStatus(.failed);
        if (mode == 2) {
            try sendBossPhaseSettle(session, null, node, false, 0, allocator);
        } else {
            try sendChallengeSettle(session, false, 0, allocator);
        }
        return;
    }
    if (node < C.LastNode()) {
        if (mode == 2) {
            // AS shows the node-1 result page and waits for EnterChallengeNextPhaseCsReq.
            C.SetAwaitingNextPhase(true);
            try sendBossPhaseSettle(session, req, node, false, 0, allocator);
            return;
        }
```

*onChallengeBattleEnd: the settle point sends the run's real mask*

Before:
```zig
    C.SetStatus(.finish);
    if (mode == 2) try sendBossPhaseSettle(session, req, node, true, allocator);
    try sendChallengeSettle(session, true, allocator);
}
```
After:
```zig
    C.SetStatus(.finish);
    const star = RecordManager.settleClassicRun(ChallengeManager.findChallengeConfig(C.GetChallengeID()), .{
        .is_moc = mode == 0,
        .scores = .{ C.GetNodeScore(1), C.GetNodeScore(2) },
        .buffs = .{ C.GetNodeBuff(1), C.GetNodeBuff(2) },
        .lineups = .{ C.GetNodeLineup(1), C.GetNodeLineup(2) },
    });
    if (mode == 2) try sendBossPhaseSettle(session, req, node, true, star, allocator);
    try sendChallengeSettle(session, true, star, allocator);
}
```

*sendChallengeSettle takes the mask*

Before:
```zig
fn sendChallengeSettle(session: *Session, is_win: bool, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var notify = protocol.ChallengeSettleNotify.init(allocator);
    notify.challenge_id = C.GetChallengeID();
    notify.is_win = is_win;
    notify.star = if (is_win) 7 else 0;
```
After:
```zig
fn sendChallengeSettle(session: *Session, is_win: bool, star: u32, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var notify = protocol.ChallengeSettleNotify.init(allocator);
    notify.challenge_id = C.GetChallengeID();
    notify.is_win = is_win;
    notify.star = star;
```

*sendBossPhaseSettle takes the mask*

Before:
```zig
fn sendBossPhaseSettle(session: *Session, req: ?*const protocol.PVEBattleResultCsReq, node: u32, is_win: bool, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var notify = protocol.ChallengeBossPhaseSettleNotify.init(allocator);
    notify.challenge_id = C.GetChallengeID();
    notify.phase = node;
    notify.is_win = is_win;
    notify.star = if (is_win) 7 else 0;
```
After:
```zig
fn sendBossPhaseSettle(session: *Session, req: ?*const protocol.PVEBattleResultCsReq, node: u32, is_win: bool, star: u32, allocator: Allocator) !void {
    const C = Logic.Challenge();
    var notify = protocol.ChallengeBossPhaseSettleNotify.init(allocator);
    notify.challenge_id = C.GetChallengeID();
    notify.phase = node;
    notify.is_win = is_win;
    notify.star = star;
```


**3d.** `gameserver/src/main.zig` (after Task 13's `PrefsManager` lines; `ProfileStore.load();` from Task 2 stays):

*Import*

Before:
```zig
const TierceManager = @import("../src/manager/tierce_mgr.zig");
const PrefsManager = @import("../src/manager/prefs_mgr.zig");
```
After:
```zig
const TierceManager = @import("../src/manager/tierce_mgr.zig");
const PrefsManager = @import("../src/manager/prefs_mgr.zig");
const RecordManager = @import("../src/manager/record_mgr.zig");
```

*Load at startup, after TierceManager*

Before:
```zig
    TierceManager.load(allocator);
    PrefsManager.load();
```
After:
```zig
    TierceManager.load(allocator);
    PrefsManager.load();
    RecordManager.load(allocator);
```


**3e.** `gameserver/src/unit_tests.zig` (appended after Task 18's last entry):

*Add record_mgr.zig to the list*

Before:
```zig
    _ = @import("services/college.zig");
}
```
After:
```zig
    _ = @import("services/college.zig");
    _ = @import("manager/record_mgr.zig");
}
```


**3f.** Keep the player's records out of git (local only, idempotent):
```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
for f in challenge.json challenge.json.bad; do grep -qxF "$f" .git/info/exclude || echo "$f" >> .git/info/exclude; done
```

- [ ] **Step 4: Build + run tests, expect PASS**

```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
"/g/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe" build
(cd gameserver && "/g/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe" build test --summary all)
python tests/test_challenge_records.py; echo "exit $?"
for f in tests/test_*.py; do python "$f" > /dev/null || echo "FAILED $f"; done
```
Expected: `zig build test` passes with three more tests than before (20 → 23 on Tasks 1–18); the record test ends
`44 passed, 0 failed` / `exit 0`; the loop prints no `FAILED` line.

- [ ] **Step 5: Commit**

```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
git add gameserver/src/manager/record_mgr.zig gameserver/src/data/challenge_config.zig gameserver/src/services/challenge.zig \
        gameserver/src/main.zig gameserver/src/unit_tests.zig tests/test_challenge_records.py
git status --short   # config.json / hotfix.json must stay unstaged
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Show real MoC, PF and AS stars and keep each floor's best run

A full run (started at node 1, both nodes won) now settles with the stars it
earned: MoC from the cycles left of the floor's countdown and downed
characters, PF/AS from both nodes' total score. The best run of each floor is
kept in challenge.json and shown by the challenge menu and the group record
page. Floors without a record, and single-node runs, still show every star.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Task 20: Anomaly Arbitration records + TakeChallengePeakReward

**Files:**
- Create: `resources/BattleTargetConfig.json` (the AA targets as cycle or downed-character limits, from DimbreathBot)
- Modify: `gameserver/src/manager/record_mgr.zig` (AA records, target table, `peak` / `peak_boss` in `challenge.json`)
- Modify: `gameserver/src/data/challenge_config.zig` (parse `HardTarget` of ChallengePeakBossConfig)
- Modify: `gameserver/src/services/challenge.zig` (GetChallengePeakData from records, `pushPeakData` sends the real
  season, settle targets judged at a clear, record + group update after a clear, `onTakeChallengePeakReward`)
- Modify: `gameserver/src/handlers.zig` (register `CmdTakeChallengePeakRewardCsReq`)
- Test: `tests/test_peak_records.py` + Zig `test` blocks in `record_mgr.zig` (`targetsMet` for both kinds, the `kind`
  column, `betterPeak`)

**Interfaces:**
- Consumes: Task 19 `record_mgr.zig` (`NodeLineup`, `save`, `SaveFile`, `loadFile`, `saveFile`, `log`), Task 19 imports in
  challenge.zig (`RecordManager`, `ChallengeConfig`); Task 5 `pub fn currentPeakGroupId()` and `pub fn pushPeakData(session,
  allocator)` (body replaced, signature kept; `commands/peak.zig` unchanged); existing `peak_run`, `isPeakBoss`,
  `peak_boss_turn_budget`, `downedAvatars`, `Logic.Challenge().ChallengePeakHard()`, `Logic.contains`.
- Produces: `record_mgr.zig`: `pub const TargetKind = enum { cycles, downed }`, `pub const BattleTarget { id, kind, param }`,
  `pub const Targets = std.BoundedArray(u32, 8)`, `pub const Fight { cycles, downed }`,
  `pub fn targetsMet(table, ids, fight) Targets`, `pub fn peakTargetsMet(ids, fight) Targets`, `pub const Peak`
  (`cycles, targets, buff_id, team`), `pub fn findPeak(level_id)`, `pub fn findPeakBoss(level_id, hard)`,
  `pub fn betterPeak(new, old)`, `pub const PeakClear`, `pub fn recordPeak(clear)`;
  `ChallengeConfig.ChallengePeakBoss.hard_target: u32`;
  challenge.zig: `buildPeakGroup(allocator, group, boss) !protocol.ChallengePeakGroup`, `peakGroupById(id)`,
  `peakGroupOf(peak_id)`, `sendPeakGroupUpdate(session, group, allocator)`, `pub fn onTakeChallengePeakReward`;
  `resources/BattleTargetConfig.json` = `[{"id", "kind": "cycles"|"downed", "param"}]`;
  `challenge.json` gains `"peak": [{"level_id", "cycles", "targets": [], "team": []}]` and
  `"peak_boss": [{"level_id", "hard", "cycles", "targets": [], "buff_id", "team": []}]`.

Rules implemented (from the spec and the lead's decisions):
- A clear's targets are judged by the server (we send AA no battle targets, so the client reports none): a `cycles`
  target is met when `round_cnt <= param`, a `downed` target (3000, "nobody downed", no TargetParam → 0) when the
  fight's downed characters (`downedAvatars`: `die_times > 0` or `left_hp <= 0`, the rule Starward uses) `<= param`.
  The kind is data: the build script maps AbilityName `BattleTarget_DeathCount` → `downed`, `BattleTarget_TurnLimit*` →
  `cycles`, and stops on anything else. Knights and the easy boss use the peak's `NormalTargetList`; the hard boss its
  `HardTarget` (3007).
- `ChallengePeakSettleScNotify` lists the targets met (knights / easy boss); the hard clear screen is unchanged
  (`hard_mode_has_passed` only). Every win is recorded per knight `{level_id, cycles, targets, team}` and per boss
  difficulty `{level_id, hard, cycles, targets, buff_id, team}`; better = more targets, tie → fewer cycles. Then
  `ChallengePeakGroupDataUpdateScNotify` with the whole season follows the settle (wins only).
- `GetChallengePeakData` per season: knights with a record are listed for real (`peaks` + best-record list
  `PAPDCCKPEPK`); once a season has one knight record its other knights are listed as passed with all their targets; a
  season without knight records has no `peaks` (as today). `obtained_stars = max(Σ knight stars, 3 × knights)` with a
  knight's stars = min(record targets, 3), or 3 without a record (M7H's `max(starNum, peaks * 3)`; every knight counts as
  passed, so it stays 9 and nothing re-locks). Boss: easy record → `easy_mode` + `finished_target_list` = its targets,
  else today's `[3003, 3004, 3005]` and no `easy_mode`; hard record → real `hard_mode`, else today's fake
  (`buff_list[0]`, team `[1508]`); `hard_mode_has_passed` stays true.
- `/peak` (Task 5's `pushPeakData`) now follows `GetChallengePeakDataScRsp` with the chosen season built by
  `buildPeakGroup` instead of the minimal `{peak_group_id, 3, 9}` update.
- `TakeChallengePeakRewardCsReq` (8937) → `TakeChallengePeakRewardScRsp` (8911) `{retcode 0, peak_group_id, one
  ChallengePeakRewardGroup per requested id with an empty ItemList}` (the getter still reports rewards 1..12 taken).

- [ ] **Step 1: Write the failing test**

Create `tests/test_peak_records.py`:
```python
"""Anomaly Arbitration records: targets judged from the cycles and downed characters, the best clear of each knight and
boss difficulty kept in challenge.json and shown by GetChallengePeakData, the group update after each clear and /peak;
anything without a record still shows fully cleared. Also the reward button (TakeChallengePeakReward)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, packets_named  # noqa: E402

WIN, LOSE = 1, 2
GROUP, KNIGHT, BOSS = 11, 1101, 1104
KNIGHT_TEAM, BOSS_TEAM, BOSS_BUFF = [1310, 1415, 1501, 1303], [1224, 8005, 1001], 3033074


def fight(c, rounds, status=WIN, downed=0):
    info, _ = c.call("GetCurBattleInfoCsReq", {}, "GetCurBattleInfoScRsp")
    stt = {"round_cnt": rounds}
    if downed:
        stt["battle_avatar_list"] = [{"id": KNIGHT_TEAM[i], "die_times": 1} for i in range(downed)]
    body = {"end_status": status, "stage_id": info.get("battle_info", {}).get("stage_id", 0), "stt": stt}
    _, pkts = c.call("PVEBattleResultCsReq", body, "PVEBattleResultScRsp")
    return pkts


def knight(c, rounds, status=WIN, downed=0):
    """A knight fight with the team set in the menu; returns (settle notify, group update or None, packet names)."""
    c.call("SetChallengePeakMobLineupAvatarCsReq",
           {"peak_group_id": GROUP, "lineup_list": [{"peak_id": KNIGHT, "peak_avatar_id_list": KNIGHT_TEAM}]},
           "SetChallengePeakMobLineupAvatarScRsp")
    rsp, _ = c.call("StartChallengePeakCsReq", {"peak_id": KNIGHT}, "StartChallengePeakScRsp")
    check("knight starts", rsp.get("retcode", 0) == 0, rsp)
    return result(c, fight(c, rounds, status, downed))


def boss(c, rounds, hard):
    c.call("SetChallengePeakBossHardModeCsReq", {"peak_group_id": GROUP, "is_hard_mode": hard}, "SetChallengePeakBossHardModeScRsp")
    rsp, _ = c.call("StartChallengePeakCsReq", {"peak_id": BOSS, "boss_buff_id": BOSS_BUFF, "peak_avatar_id_list": BOSS_TEAM},
                    "StartChallengePeakScRsp")
    check("boss starts", rsp.get("retcode", 0) == 0, rsp)
    return result(c, fight(c, rounds))


def result(c, pkts):
    c.call("LeaveChallengePeakCsReq", {}, "LeaveChallengePeakScRsp")
    settle = packets_named(pkts, "ChallengePeakSettleScNotify")
    update = packets_named(pkts, "ChallengePeakGroupDataUpdateScNotify")
    return (settle[0].msg() if settle else {}, update[0].msg().get("challenge_peak_group") if update else None,
            [p.name for p in pkts])


def groups(c):
    rsp, _ = c.call("GetChallengePeakDataCsReq", {}, "GetChallengePeakDataScRsp")
    return {g["peak_group_id"]: g for g in rsp.get("challenge_peak_groups", [])}


def peak(group, peak_id):
    return next((p for p in group.get("peaks", []) if p["peak_id"] == peak_id), None)


def knight_view(group):
    p = peak(group or {}, KNIGHT) or {}
    return p.get("has_passed"), p.get("cycles_used", 0), p.get("finished_target_list", []), p.get("peak_avatar_id_list", [])


def clearance(mode):
    mode = mode or {}
    return mode.get("has_passed"), mode.get("best_cycle_count", 0), mode.get("buff_id", 0), mode.get("peak_avatar_id_list", [])


def is_fake(group):
    b = group.get("peak_boss", {})
    return (group.get("obtained_stars") == 9 and "peaks" not in group and "easy_mode" not in b
            and b.get("finished_target_list") == [3003, 3004, 3005] and b.get("hard_mode_has_passed") is True
            and clearance(b.get("hard_mode"))[0] is True and b["hard_mode"].get("peak_avatar_id_list") == [1508])


with Server() as srv:
    c = srv.login()

    print("no records yet")
    g = groups(c)
    check("every season shows as fully cleared", all(is_fake(x) for x in g.values()), g.get(GROUP))

    print(f"knight {KNIGHT} (targets 3001 <= 4 cycles, 3002 <= 2 cycles, 3000 nobody downed)")
    settle, update, names = knight(c, 3, downed=1)
    check("3 cycles with one downed meets 3001 only",
          (settle.get("is_win"), settle.get("finished_target_list", []), settle.get("cycles_used")) == (True, [3001], 3), settle)
    check("the group update follows the settle", update is not None and names.index("ChallengePeakGroupDataUpdateScNotify")
          > names.index("ChallengePeakSettleScNotify"), names)
    check("update: the knight's record, still 9 stars", update and update.get("obtained_stars") == 9
          and knight_view(update) == (True, 3, [3001], KNIGHT_TEAM), update)
    x = groups(c)[GROUP]
    check("GetChallengePeakData shows the record", knight_view(x) == (True, 3, [3001], KNIGHT_TEAM), knight_view(x))
    check("obtained stars never drop below 3 a knight", x.get("obtained_stars") == 9, x.get("obtained_stars"))
    best = next((p for p in x.get("PAPDCCKPEPK", {}).get("peaks", []) if p["peak_id"] == KNIGHT), {})
    check("and the best-record list", (best.get("cycles_used"), best.get("finished_target_list"),
                                       [a["avatar_id"] for a in best.get("avatar_list", [])]) == (3, [3001], KNIGHT_TEAM), best)
    other = peak(x, 1102) or {}
    check("an unplayed knight of the group shows fully cleared",
          (other.get("has_passed"), other.get("finished_target_list")) == (True, [3001, 3002, 3000]), other)
    check("a season without records is unchanged", is_fake(groups(c)[10]))

    settle, _, _ = knight(c, 5)
    check("a clean 5-cycle clear meets 3000 only", settle.get("finished_target_list", []) == [3000], settle)
    check("as many targets in more cycles keeps the record", knight_view(groups(c)[GROUP])[1:3] == (3, [3001]))
    settle, _, names = knight(c, 1, LOSE)
    check("a lost fight sends no group update", settle.get("is_win") is not True
          and "ChallengePeakGroupDataUpdateScNotify" not in names, names)
    settle, _, _ = knight(c, 2, downed=1)
    check("2 cycles with one downed meets 3001 + 3002", settle.get("finished_target_list", []) == [3001, 3002], settle)
    check("more targets replace the record", knight_view(groups(c)[GROUP])[1:3] == (2, [3001, 3002]))
    settle, _, _ = knight(c, 2)
    check("the same clear with nobody downed also meets 3000", settle.get("finished_target_list", []) == [3001, 3002, 3000], settle)
    knight(c, 1)
    x = groups(c)[GROUP]
    check("as many targets in fewer cycles replace it", knight_view(x)[1:3] == (1, [3001, 3002, 3000]), knight_view(x))

    print("/peak sends the season with its records")
    c.command("/peak 11")
    pushed = packets_named(c.last_packets, "ChallengePeakGroupDataUpdateScNotify")
    group = pushed[0].msg().get("challenge_peak_group") if pushed else None
    check("the pushed group update is the whole season", group and group.get("peak_group_id") == GROUP
          and knight_view(group)[1:3] == (1, [3001, 3002, 3000]) and "peak_boss" in group, group)
    c.command("/peak 0")

    print(f"boss {BOSS}: easy (3003 <= 6, 3004 <= 4, 3005 <= 2 cycles), hard (3007 <= 2 cycles)")
    settle, update, _ = boss(c, 3, False)
    check("easy boss in 3 cycles meets 3003 + 3004", (settle.get("finished_target_list"), settle.get("turn_left"))
          == ([3003, 3004], 3), settle)
    b = groups(c)[GROUP]["peak_boss"]
    check("easy record shown", clearance(b.get("easy_mode")) == (True, 3, BOSS_BUFF, BOSS_TEAM), b.get("easy_mode"))
    check("boss targets are the easy record's", b.get("finished_target_list") == [3003, 3004], b)
    check("hard mode without a record stays fake", b["hard_mode"].get("peak_avatar_id_list") == [1508], b["hard_mode"])
    settle, _, _ = boss(c, 2, True)
    check("hard clear keeps its own result screen", settle.get("hard_mode_has_passed") is True
          and "finished_target_list" not in settle, settle)
    boss(c, 4, True)
    b = groups(c)[GROUP]["peak_boss"]
    check("hard record: 2 cycles, not the worse 4", clearance(b.get("hard_mode")) == (True, 2, BOSS_BUFF, BOSS_TEAM), b.get("hard_mode"))
    check("easy record untouched by hard clears", clearance(b.get("easy_mode"))[1] == 3, b.get("easy_mode"))

    print("after a restart")
    saved = srv.read_json("challenge.json") if os.path.exists(srv.path("challenge.json")) else {}
    check("challenge.json holds the knight", [(p["level_id"], p["cycles"], p["targets"]) for p in saved.get("peak", [])]
          == [(KNIGHT, 1, [3001, 3002, 3000])], saved.get("peak"))
    check("and both boss difficulties", sorted((p["level_id"], p["hard"], p["cycles"]) for p in saved.get("peak_boss", []))
          == [(BOSS, False, 3), (BOSS, True, 2)], saved.get("peak_boss"))
    srv.restart()
    c = srv.login()
    x = groups(c)[GROUP]
    check("knight record survives", knight_view(x) == (True, 1, [3001, 3002, 3000], KNIGHT_TEAM), knight_view(x))
    check("boss records survive", (clearance(x["peak_boss"].get("easy_mode"))[1], clearance(x["peak_boss"].get("hard_mode"))[1])
          == (3, 2), x["peak_boss"])
    check("other seasons still fake", is_fake(groups(c)[1]))

    print("reward button")
    try:
        rsp, _ = c.call("TakeChallengePeakRewardCsReq", {"peak_group_id": GROUP, "normal_reward_id_list": [1, 2, 3]},
                        "TakeChallengePeakRewardScRsp")
    except AssertionError as e:
        rsp = None
        print(f"  ({e})")
    check("TakeChallengePeakReward answers the asked ids without items",
          rsp is not None and rsp.get("retcode", 0) == 0 and rsp.get("peak_group_id") == GROUP
          and [r["reward_id"] for r in rsp.get("peak_reward_group_list", [])] == [1, 2, 3]
          and all(not r.get("reward", {}).get("item_list") for r in rsp.get("peak_reward_group_list", [])), rsp)

done()
```

- [ ] **Step 2: Run it, expect FAIL**

```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
"/g/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe" build
python tests/test_peak_records.py; echo "exit $?"
```
Expected: `FAIL 3 cycles with one downed meets 3001 only {... 'finished_target_list': [3001, 3002, 3000] ...}` (every
target counts as met today), no group update after the settle, `FAIL the pushed group update is the whole season
{'peak_group_id': 11, 'obtained_stars': 9, 'count_of_peaks': 3}`, no records in GetChallengePeakData or `challenge.json`,
and `(TakeChallengePeakRewardCsReq: no TakeChallengePeakRewardScRsp (got []))` /
`FAIL TakeChallengePeakReward answers the asked ids without items None`; ends `17 passed, 22 failed`, `exit 1`
(measured on Tasks 1–18 + Task 19).

- [ ] **Step 3: Implement**

**3a.** `resources/BattleTargetConfig.json` — data only. Download the excel table into a new empty directory, keep the
script in a different directory, run with `python -I` from the repo root:
```bash
mkdir -p /c/Users/Pc/AppData/Local/Temp/claude/pearl-btc/src /c/Users/Pc/AppData/Local/Temp/claude/pearl-btc/tool
curl -sSL -o /c/Users/Pc/AppData/Local/Temp/claude/pearl-btc/src/BattleTargetConfig.json \
  https://raw.githubusercontent.com/DimbreathBot/TurnBasedGameData/main/ExcelOutput/BattleTargetConfig.json
```
Write `/c/Users/Pc/AppData/Local/Temp/claude/pearl-btc/tool/build_battle_targets.py` (not committed):
```python
"""Builds resources/BattleTargetConfig.json: every AA star target our challenge peak data uses, as a cycle limit or a
limit on downed characters.

Usage: python -I build_battle_targets.py <DimbreathBot BattleTargetConfig.json> <repo resources dir> <out json>
"""
import json
import os
import sys

src, resources, out_path = sys.argv[1:4]
with open(os.path.join(resources, "ChallengePeakConfig.json"), encoding="utf-8") as f:
    peaks = json.load(f)["challenge_peak_config"]
with open(os.path.join(resources, "ChallengePeakBossConfig.json"), encoding="utf-8") as f:
    bosses = json.load(f)["challenge_peak_boss_config"]
wanted = {t for p in peaks for t in p["NormalTargetList"]} | {b["HardTarget"] for b in bosses if b.get("HardTarget")}
with open(src, encoding="utf-8") as f:
    rows = {r["ID"]: r for r in json.load(f)}
missing = sorted(wanted - rows.keys())
if missing:
    sys.exit(f"not in BattleTargetConfig: {missing}")


def kind(row):
    """What the target limits; the server can only judge these two."""
    if row.get("ParamType") != "LessEqual":
        sys.exit(f"target {row['ID']}: ParamType {row.get('ParamType')}")
    name = row.get("AbilityName", "")
    if name == "BattleTarget_DeathCount":
        return "downed"
    if name.startswith("BattleTarget_TurnLimit"):
        return "cycles"
    sys.exit(f"target {row['ID']}: no rule for {name}")


# 3000 (nobody downed) has no TargetParam in the excel data: 0.
out = [{"id": i, "kind": kind(rows[i]), "param": rows[i].get("TargetParam") or 0} for i in sorted(wanted)]
with open(out_path, "w", encoding="utf-8", newline="\n") as f:
    f.write("[\n" + ",\n".join("  " + json.dumps(r) for r in out) + "\n]\n")
print(f"{len(out)} targets: {out}")
```
Run it:
```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
python -I /c/Users/Pc/AppData/Local/Temp/claude/pearl-btc/tool/build_battle_targets.py \
  /c/Users/Pc/AppData/Local/Temp/claude/pearl-btc/src/BattleTargetConfig.json resources resources/BattleTargetConfig.json
```
Expected output `7 targets: [...]` and this exact file (2026-10-15 data; if the download fails, write it by hand):
```json
[
  {"id": 3000, "kind": "downed", "param": 0},
  {"id": 3001, "kind": "cycles", "param": 4},
  {"id": 3002, "kind": "cycles", "param": 2},
  {"id": 3003, "kind": "cycles", "param": 6},
  {"id": 3004, "kind": "cycles", "param": 4},
  {"id": 3005, "kind": "cycles", "param": 2},
  {"id": 3007, "kind": "cycles", "param": 2}
]
```

**3b.** `gameserver/src/data/challenge_config.zig`:

*ChallengePeakBoss: new field*

Before:
```zig
pub const ChallengePeakBoss = struct {
    id: u32,
    hard_tag_list: ArrayList(u32),
```
After:
```zig
pub const ChallengePeakBoss = struct {
    id: u32,
    // The hard difficulty's star target (a BattleTargetConfig id); 0 if the row has none.
    hard_target: u32,
    hard_tag_list: ArrayList(u32),
```

*parseChallengePeakBossConfig*

Before:
```zig
            .id = @intCast(boss_json.object.get("ID").?.integer),
            .hard_tag_list = ArrayList(u32).init(allocator),
```
After:
```zig
            .id = @intCast(boss_json.object.get("ID").?.integer),
            .hard_target = if (boss_json.object.get("HardTarget")) |val| @intCast(val.integer) else 0,
            .hard_tag_list = ArrayList(u32).init(allocator),
```


**3c.** `gameserver/src/manager/record_mgr.zig` (on top of Task 19's file):

*Header comment*

Before:
```zig
// The best runs of MoC/PF/AS floors, kept in challenge.json next to config.json. A floor without a record keeps
// showing as fully cleared, as before records were kept, so nothing the player had open locks again.
```
After:
```zig
// The best runs of MoC/PF/AS floors and of Anomaly Arbitration knights and bosses, kept in challenge.json next to
// config.json. Anything without a record keeps showing as fully cleared, as before records were kept, so nothing the
// player had open locks again.
```

*AA target table, records and recordPeak (inserted before SavedClassic)*

Before:
```zig
const SavedClassic = struct {
```
After:
```zig
// Anomaly Arbitration star targets (resources/BattleTargetConfig.json, trimmed from the game's BattleTargetConfig):
// at most `param` cycles, or at most `param` characters downed. A table of its own: 3001 is an AS score target in
// challenge_targets.zig but a 4-cycle AA target here.
pub const TargetKind = enum { cycles, downed };
pub const BattleTarget = struct { id: u32, kind: TargetKind = .cycles, param: u32 = 0 };
const battle_target_path = "resources/BattleTargetConfig.json";
var battle_targets: []const BattleTarget = &.{};

pub const Targets = std.BoundedArray(u32, 8);
// What a won fight is judged by. We send the client no AA targets, so it reports no progress on them.
pub const Fight = struct { cycles: u32, downed: u32 };

// The targets of `ids` a won fight meets; one the table does not have is never met.
pub fn targetsMet(table: []const BattleTarget, ids: []const u32, fight: Fight) Targets {
    var met = Targets{};
    for (ids) |id| {
        const target = for (table) |t| {
            if (t.id == id) break t;
        } else continue;
        const value = switch (target.kind) {
            .cycles => fight.cycles,
            .downed => fight.downed,
        };
        if (value <= target.param) met.append(id) catch break;
    }
    return met;
}
pub fn peakTargetsMet(ids: []const u32, fight: Fight) Targets {
    return targetsMet(battle_targets, ids, fight);
}

// The best clear of a knight, or of one boss difficulty.
pub const Peak = struct {
    cycles: u32 = 0,
    targets: Targets = .{},
    // The boss buff it was cleared with; knights have none.
    buff_id: u32 = 0,
    team: NodeLineup = .{},
};
const PeakKey = struct { level_id: u32, boss: bool, hard: bool };
var peak_records = std.AutoArrayHashMap(PeakKey, Peak).init(std.heap.page_allocator);

pub fn findPeak(level_id: u32) ?*const Peak {
    return peak_records.getPtr(.{ .level_id = level_id, .boss = false, .hard = false });
}
pub fn findPeakBoss(level_id: u32, hard: bool) ?*const Peak {
    return peak_records.getPtr(.{ .level_id = level_id, .boss = true, .hard = hard });
}

// More targets wins; as many targets wins with fewer cycles.
pub fn betterPeak(new: *const Peak, old: *const Peak) bool {
    if (new.targets.len != old.targets.len) return new.targets.len > old.targets.len;
    return new.cycles < old.cycles;
}

pub const PeakClear = struct {
    level_id: u32,
    boss: bool,
    hard: bool,
    cycles: u32,
    targets: Targets,
    buff_id: u32,
    team: []const u32,
};

// A won AA fight: it becomes the record of its knight or boss difficulty when it beats the one kept.
pub fn recordPeak(clear: PeakClear) void {
    const run = Peak{
        .cycles = clear.cycles,
        .targets = clear.targets,
        .buff_id = if (clear.boss) clear.buff_id else 0,
        .team = NodeLineup.fromSlice(clear.team),
    };
    const key = PeakKey{ .level_id = clear.level_id, .boss = clear.boss, .hard = clear.boss and clear.hard };
    const entry = peak_records.getOrPut(key) catch |err| {
        log.err("AA level {} could not be recorded: {s}", .{ clear.level_id, @errorName(err) });
        return;
    };
    if (entry.found_existing and !betterPeak(&run, entry.value_ptr)) return;
    entry.value_ptr.* = run;
    save();
}

const SavedClassic = struct {
```

*Save file gains the AA lists*

Before:
```zig
const SaveFile = struct {
    classic: []const SavedClassic = &.{},
};
```
After:
```zig
const SavedPeak = struct {
    level_id: u32 = 0,
    cycles: u32 = 0,
    targets: []const u32 = &.{},
    team: []const u32 = &.{},
};
const SavedPeakBoss = struct {
    level_id: u32 = 0,
    hard: bool = false,
    cycles: u32 = 0,
    targets: []const u32 = &.{},
    buff_id: u32 = 0,
    team: []const u32 = &.{},
};
const SaveFile = struct {
    classic: []const SavedClassic = &.{},
    peak: []const SavedPeak = &.{},
    peak_boss: []const SavedPeakBoss = &.{},
};
```

*load() also reads the target table*

Before:
```zig
pub fn load(allocator: Allocator) void {
    loadFile(allocator) catch |err| switch (err) {
```
After:
```zig
pub fn load(allocator: Allocator) void {
    loadBattleTargets(allocator) catch |err| {
        log.err("{s} could not be loaded ({s}); no AA star target counts as met", .{ battle_target_path, @errorName(err) });
    };
    loadFile(allocator) catch |err| switch (err) {
```

*The target table loader (before loadFile)*

Before:
```zig
fn loadFile(allocator: Allocator) !void {
```
After:
```zig
fn loadBattleTargets(allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, battle_target_path, 1 << 20);
    defer allocator.free(bytes);
    // Kept for the server's lifetime.
    battle_targets = try std.json.parseFromSliceLeaky([]const BattleTarget, std.heap.page_allocator, bytes, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}
fn loadFile(allocator: Allocator) !void {
```

*loadFile: AA records, applied only if the whole file is valid*

Before:
```zig
            .lineups = .{ NodeLineup.fromSlice(saved.lineup1), NodeLineup.fromSlice(saved.lineup2) },
        });
    }
    classic.deinit();
    classic = loaded_classic;
}
```
After:
```zig
            .lineups = .{ NodeLineup.fromSlice(saved.lineup1), NodeLineup.fromSlice(saved.lineup2) },
        });
    }
    var loaded_peaks = std.AutoArrayHashMap(PeakKey, Peak).init(std.heap.page_allocator);
    errdefer loaded_peaks.deinit();
    for (parsed.value.peak) |saved| {
        const key = PeakKey{ .level_id = saved.level_id, .boss = false, .hard = false };
        try loaded_peaks.put(key, try loadedPeak(saved.cycles, saved.targets, 0, saved.team));
    }
    for (parsed.value.peak_boss) |saved| {
        const key = PeakKey{ .level_id = saved.level_id, .boss = true, .hard = saved.hard };
        try loaded_peaks.put(key, try loadedPeak(saved.cycles, saved.targets, saved.buff_id, saved.team));
    }
    classic.deinit();
    classic = loaded_classic;
    peak_records.deinit();
    peak_records = loaded_peaks;
}
fn loadedPeak(cycles: u32, targets: []const u32, buff_id: u32, team: []const u32) !Peak {
    if (team.len > 4) return error.InvalidRecords;
    return .{
        .cycles = cycles,
        .targets = Targets.fromSlice(targets) catch return error.InvalidRecords,
        .buff_id = buff_id,
        .team = NodeLineup.fromSlice(team),
    };
}
```

*saveFile: write the AA lists*

Before:
```zig
    var out = std.ArrayList(u8).init(allocator);
    try std.json.stringify(SaveFile{ .classic = saved_classic }, .{ .whitespace = .indent_2 }, out.writer());
```
After:
```zig
    var saved_peaks = std.ArrayList(SavedPeak).init(allocator);
    var saved_bosses = std.ArrayList(SavedPeakBoss).init(allocator);
    for (peak_records.keys(), peak_records.values()) |key, *record| {
        if (key.boss) {
            try saved_bosses.append(.{
                .level_id = key.level_id,
                .hard = key.hard,
                .cycles = record.cycles,
                .targets = record.targets.constSlice(),
                .buff_id = record.buff_id,
                .team = record.team.slice(),
            });
        } else {
            try saved_peaks.append(.{
                .level_id = key.level_id,
                .cycles = record.cycles,
                .targets = record.targets.constSlice(),
                .team = record.team.slice(),
            });
        }
    }
    var out = std.ArrayList(u8).init(allocator);
    const file_data = SaveFile{ .classic = saved_classic, .peak = saved_peaks.items, .peak_boss = saved_bosses.items };
    try std.json.stringify(file_data, .{ .whitespace = .indent_2 }, out.writer());
```

*Tests (appended after the classic tests)*

Before:
```zig
    try std.testing.expect(!betterClassic(false, &Classic{ .stars_mask = 0b101, .rounds = 1, .scores = .{ 20000, 20000 } }, &old));
}
```
After:
```zig
    try std.testing.expect(!betterClassic(false, &Classic{ .stars_mask = 0b101, .rounds = 1, .scores = .{ 20000, 20000 } }, &old));
}

test "AA targets: cycle limits and downed characters" {
    const table = [_]BattleTarget{
        .{ .id = 3000, .kind = .downed },
        .{ .id = 3001, .param = 4 },
        .{ .id = 3002, .param = 2 },
    };
    const knight = [_]u32{ 3001, 3002, 3000 };
    const clean = targetsMet(&table, &knight, .{ .cycles = 2, .downed = 0 });
    try std.testing.expectEqualSlices(u32, &.{ 3001, 3002, 3000 }, clean.constSlice());
    const downed = targetsMet(&table, &knight, .{ .cycles = 2, .downed = 1 });
    try std.testing.expectEqualSlices(u32, &.{ 3001, 3002 }, downed.constSlice());
    const slow = targetsMet(&table, &knight, .{ .cycles = 3, .downed = 0 });
    try std.testing.expectEqualSlices(u32, &.{ 3001, 3000 }, slow.constSlice());
    try std.testing.expectEqual(@as(usize, 0), targetsMet(&table, &knight, .{ .cycles = 5, .downed = 2 }).len);
    // A target the table does not have is never met.
    try std.testing.expectEqual(@as(usize, 0), targetsMet(&table, &.{3007}, .{ .cycles = 0, .downed = 0 }).len);
}

test "AA target table: the kind column parses" {
    const json = "[{\"id\": 3000, \"kind\": \"downed\", \"param\": 0}, {\"id\": 3001, \"kind\": \"cycles\", \"param\": 4}]";
    const parsed = try std.json.parseFromSlice([]const BattleTarget, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(TargetKind.downed, parsed.value[0].kind);
    try std.testing.expectEqual(BattleTarget{ .id = 3001, .kind = .cycles, .param = 4 }, parsed.value[1]);
}

test "better AA clear: more targets, then fewer cycles" {
    const old = Peak{ .cycles = 3, .targets = try Targets.fromSlice(&.{3001}) };
    try std.testing.expect(betterPeak(&Peak{ .cycles = 4, .targets = try Targets.fromSlice(&.{ 3001, 3002 }) }, &old));
    try std.testing.expect(!betterPeak(&Peak{ .cycles = 1 }, &old));
    try std.testing.expect(betterPeak(&Peak{ .cycles = 2, .targets = try Targets.fromSlice(&.{3001}) }, &old));
    try std.testing.expect(!betterPeak(&Peak{ .cycles = 3, .targets = try Targets.fromSlice(&.{3003}) }, &old));
}
```


**3d.** `gameserver/src/services/challenge.zig`:

*pushPeakData (Task 5's /peak push) sends the real season through the new helpers*

Before:
```zig
// Sends GetChallengePeakDataScRsp unasked, as March7thHoney's /peak does; the handler never reads its packet.
pub fn pushPeakData(session: *Session, allocator: Allocator) !void {
    try onGetChallengePeakData(session, undefined, allocator);
    var update = protocol.ChallengePeakGroup.init(allocator);
    update.peak_group_id = currentPeakGroupId();
    update.count_of_peaks = 3;
    update.obtained_stars = 9;
    try session.send(CmdID.CmdChallengePeakGroupDataUpdateScNotify, protocol.ChallengePeakGroupDataUpdateScNotify{
        .challenge_peak_group = update,
    });
}
```
After:
```zig
// Sends GetChallengePeakDataScRsp unasked, as March7thHoney's /peak does (the handler never reads its packet), then
// the chosen season as a group update.
pub fn pushPeakData(session: *Session, allocator: Allocator) !void {
    try onGetChallengePeakData(session, undefined, allocator);
    const group = peakGroupById(currentPeakGroupId()) orelse return;
    try sendPeakGroupUpdate(session, group, allocator);
}
```

*onGetChallengePeakData builds each season from the records (+ helpers); it still never reads its packet*

Before:
```zig
pub fn onGetChallengePeakData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChallengePeakDataScRsp.init(allocator);
    rsp.retcode = 0;
    const target_king = [_]u32{ 3003, 3004, 3005 };
    var reward = ArrayList(u32).init(allocator);
    for (1..13) |i| {
        try reward.append(@intCast(i));
    }
    var ava = ArrayList(u32).init(allocator);
    try ava.appendSlice(&[_]u32{1508});

    const BossType = @TypeOf(peak_boss.challenge_peak_boss_config.items[0]);
    var boss_map = std.AutoHashMap(u32, *const BossType).init(allocator);
    defer boss_map.deinit();
    for (peak_boss.challenge_peak_boss_config.items) |*boss| {
        try boss_map.put(boss.id, boss);
    }
    for (peak_group.challenge_peak_group.items) |id| {
        if (boss_map.get(id.boss_level_id)) |boss| {
            var data = protocol.ChallengePeakGroup.init(allocator);
            const unk = ArrayList(protocol.ABCHBKBKCDF).init(allocator);
            data.peak_group_id = id.id;
            data.taken_star_rewards = reward;
            data.count_of_peaks = 3;
            data.obtained_stars = 9;
            data.peak_boss = .{
                .finished_target_list = blk: {
                    var list = std.ArrayList(u32).init(allocator);
                    try list.appendSlice(&target_king);
                    break :blk list;
                },
                .hard_mode_has_passed = true,
                .hard_mode = .{
                    .has_passed = true,
                    .best_cycle_count = 0,
                    .buff_id = boss.buff_list.items[0],
                    .peak_avatar_id_list = ava,
                    .LAMPCACOCHP = ava,
                    .EBNNJAEPBGD = unk,
                },
            };
            try rsp.challenge_peak_groups.append(data);
        }
    }
    rsp.current_peak_group_id = currentPeakGroupId();
    try session.send(CmdID.CmdGetChallengePeakDataScRsp, rsp);
}
```
After:
```zig
pub fn onGetChallengePeakData(session: *Session, _: *const Packet, allocator: Allocator) !void {
    var rsp = protocol.GetChallengePeakDataScRsp.init(allocator);
    rsp.retcode = 0;
    for (peak_group.challenge_peak_group.items) |*group| {
        const boss = findPeakBossConfig(group.boss_level_id) orelse continue;
        try rsp.challenge_peak_groups.append(try buildPeakGroup(allocator, group, boss));
    }
    rsp.current_peak_group_id = currentPeakGroupId();
    try session.send(CmdID.CmdGetChallengePeakDataScRsp, rsp);
}

// One AA season as its menu shows it. A knight or boss difficulty with a record shows it; the rest stay fully
// cleared (every star reward taken, 3 stars a knight, the hard boss passed), as before records were kept.
fn buildPeakGroup(
    allocator: Allocator,
    group: *const ChallengeConfig.ChallengePeakGroup,
    boss: *const ChallengeConfig.ChallengePeakBoss,
) !protocol.ChallengePeakGroup {
    var data = protocol.ChallengePeakGroup.init(allocator);
    data.peak_group_id = group.id;
    for (1..13) |i| try data.taken_star_rewards.append(@intCast(i));
    data.count_of_peaks = 3;
    // The knights' stars, but never fewer than 3 a knight (M7H: max(stars, knights * 3)): every knight counts as
    // passed, by a record or as before records, so nothing the season unlocks locks again.
    var stars: u32 = 0;
    var recorded = false;
    for (group.pre_level_id_list.items) |level_id| {
        const record = RecordManager.findPeak(level_id) orelse {
            stars += 3;
            continue;
        };
        const knight_stars: u32 = @intCast(@min(record.targets.len, 3));
        stars += knight_stars;
        recorded = true;
    }
    const knights: u32 = @intCast(group.pre_level_id_list.items.len);
    data.obtained_stars = @max(stars, 3 * knights);
    // The knights are listed once one has a record, the others as cleared, so none of them locks again.
    if (recorded) {
        // M7H's best_record_list.
        var best = protocol.JFBFFIAOPCC.init(allocator);
        for (group.pre_level_id_list.items) |level_id| {
            var peak = protocol.ChallengePeak.init(allocator);
            peak.peak_id = level_id;
            peak.has_passed = true;
            if (RecordManager.findPeak(level_id)) |record| {
                peak.cycles_used = record.cycles;
                try peak.finished_target_list.appendSlice(record.targets.constSlice());
                try peak.peak_avatar_id_list.appendSlice(record.team.slice());
                var entry = protocol.MEKPDDBLCGK.init(allocator);
                entry.peak_id = level_id;
                entry.cycles_used = record.cycles;
                try entry.finished_target_list.appendSlice(record.targets.constSlice());
                for (record.team.slice()) |id| try entry.avatar_list.append(.{ .avatar_id = id });
                try best.peaks.append(entry);
            } else if (findPeakConfig(level_id)) |conf| {
                try peak.finished_target_list.appendSlice(conf.normal_target_list.items);
            }
            try data.peaks.append(peak);
        }
        data.PAPDCCKPEPK = best;
    }
    data.peak_boss = try buildPeakBoss(allocator, boss);
    return data;
}
// A difficulty without a record stays as before: easy left out, hard passed with a placeholder team.
fn buildPeakBoss(allocator: Allocator, boss: *const ChallengeConfig.ChallengePeakBoss) !protocol.ChallengePeakBoss {
    var data = protocol.ChallengePeakBoss.init(allocator);
    data.hard_mode_has_passed = true;
    if (RecordManager.findPeakBoss(boss.id, false)) |record| {
        try data.finished_target_list.appendSlice(record.targets.constSlice());
        data.easy_mode = try bossClearance(allocator, record);
    } else {
        try data.finished_target_list.appendSlice(&[_]u32{ 3003, 3004, 3005 });
    }
    if (RecordManager.findPeakBoss(boss.id, true)) |record| {
        data.hard_mode = try bossClearance(allocator, record);
    } else {
        var hard = protocol.ChallengePeakBossClearance.init(allocator);
        hard.has_passed = true;
        hard.buff_id = if (boss.buff_list.items.len > 0) boss.buff_list.items[0] else 0;
        try hard.peak_avatar_id_list.append(1508);
        try hard.LAMPCACOCHP.append(1508);
        data.hard_mode = hard;
    }
    return data;
}
fn bossClearance(allocator: Allocator, record: *const RecordManager.Peak) !protocol.ChallengePeakBossClearance {
    var clearance = protocol.ChallengePeakBossClearance.init(allocator);
    clearance.has_passed = true;
    clearance.best_cycle_count = record.cycles;
    clearance.buff_id = record.buff_id;
    try clearance.peak_avatar_id_list.appendSlice(record.team.slice());
    try clearance.LAMPCACOCHP.appendSlice(record.team.slice());
    // M7H's best_record_avatar_list.
    for (record.team.slice()) |id| try clearance.EBNNJAEPBGD.append(.{ .avatar_id = id });
    return clearance;
}
fn findPeakConfig(peak_id: u32) ?*const ChallengeConfig.ChallengePeak {
    for (peak_config.challenge_peak.items) |*peak| {
        if (peak.id == peak_id) return peak;
    }
    return null;
}
fn findPeakBossConfig(boss_id: u32) ?*const ChallengeConfig.ChallengePeakBoss {
    for (peak_boss.challenge_peak_boss_config.items) |*boss| {
        if (boss.id == boss_id) return boss;
    }
    return null;
}
fn peakGroupById(group_id: u32) ?*const ChallengeConfig.ChallengePeakGroup {
    for (peak_group.challenge_peak_group.items) |*group| {
        if (group.id == group_id) return group;
    }
    return null;
}
// The season a knight or boss belongs to.
fn peakGroupOf(peak_id: u32) ?*const ChallengeConfig.ChallengePeakGroup {
    for (peak_group.challenge_peak_group.items) |*group| {
        if (group.boss_level_id == peak_id or Logic.contains(&group.pre_level_id_list, peak_id)) return group;
    }
    return null;
}
// A season once more, so its menu shows a new record or a new /peak pick without logging in again.
fn sendPeakGroupUpdate(session: *Session, group: *const ChallengeConfig.ChallengePeakGroup, allocator: Allocator) !void {
    const boss = findPeakBossConfig(group.boss_level_id) orelse return;
    try session.send(CmdID.CmdChallengePeakGroupDataUpdateScNotify, protocol.ChallengePeakGroupDataUpdateScNotify{
        .challenge_peak_group = try buildPeakGroup(allocator, group, boss),
    });
}
```

*onPeakBattleEnd: judged targets, record, group update*

Before:
```zig
// The result screen of an Anomaly Arbitration fight; from it the client goes on to the next knight, retries or
// leaves. Every star target counts as met, as in MoC/PF/AS, and no record is kept.
fn onPeakBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (!C.ChallengeMode() or peak_run.peak_id == 0) return;
    // Backing out of the fight is not losing it: the party stays in the arena.
    if (req.end_status == .BATTLE_END_QUIT) return;

    var notify = protocol.ChallengePeakSettleScNotify.init(allocator);
    notify.peak_id = peak_run.peak_id;
    notify.is_win = req.end_status == .BATTLE_END_WIN;
    if (notify.is_win) {
        const cycles = if (req.stt) |stt| stt.round_cnt else 0;
        const boss = isPeakBoss(peak_run.peak_id);
        notify.cycles_used = cycles;
        if (boss and C.ChallengePeakHard()) {
            // A hard clear has a result screen of its own, with no targets on it.
            notify.hard_mode_has_passed = true;
        } else {
            for (peak_config.challenge_peak.items) |peak| {
                if (peak.id == peak_run.peak_id) try notify.finished_target_list.appendSlice(peak.normal_target_list.items);
            }
            if (boss) notify.turn_left = peak_boss_turn_budget -| cycles;
        }
    }
    std.log.info("CHALLENGE PEAK {} {s}", .{ peak_run.peak_id, if (notify.is_win) "CLEARED" else "FAILED" });
    try session.send(CmdID.CmdChallengePeakSettleScNotify, notify);
}
```
After:
```zig
// The result screen of an Anomaly Arbitration fight; from it the client goes on to the next knight, retries or
// leaves. A clear's targets are judged from its cycles and downed characters; it may become the knight's or boss
// difficulty's record, and its season is sent again so the menu shows it.
fn onPeakBattleEnd(session: *Session, req: *const protocol.PVEBattleResultCsReq, allocator: Allocator) !void {
    const C = Logic.Challenge();
    if (!C.ChallengeMode() or peak_run.peak_id == 0) return;
    // Backing out of the fight is not losing it: the party stays in the arena.
    if (req.end_status == .BATTLE_END_QUIT) return;

    var notify = protocol.ChallengePeakSettleScNotify.init(allocator);
    notify.peak_id = peak_run.peak_id;
    notify.is_win = req.end_status == .BATTLE_END_WIN;
    if (notify.is_win) {
        const cycles = if (req.stt) |stt| stt.round_cnt else 0;
        const boss = isPeakBoss(peak_run.peak_id);
        const hard = boss and C.ChallengePeakHard();
        const met = metPeakTargets(peak_run.peak_id, hard, .{
            .cycles = cycles,
            .downed = if (req.stt) |stt| downedAvatars(&stt) else 0,
        });
        notify.cycles_used = cycles;
        if (hard) {
            // A hard clear has a result screen of its own, with no targets on it.
            notify.hard_mode_has_passed = true;
        } else {
            try notify.finished_target_list.appendSlice(met.constSlice());
            if (boss) notify.turn_left = peak_boss_turn_budget -| cycles;
        }
        RecordManager.recordPeak(.{
            .level_id = peak_run.peak_id,
            .boss = boss,
            .hard = hard,
            .cycles = cycles,
            .targets = met,
            .buff_id = peak_run.buff_id,
            .team = C.GetAvatarIDs().items,
        });
    }
    std.log.info("CHALLENGE PEAK {} {s}", .{ peak_run.peak_id, if (notify.is_win) "CLEARED" else "FAILED" });
    try session.send(CmdID.CmdChallengePeakSettleScNotify, notify);
    if (notify.is_win) {
        if (peakGroupOf(peak_run.peak_id)) |group| try sendPeakGroupUpdate(session, group, allocator);
    }
}
// The star targets a won fight met: a knight's or the easy boss's normal targets, the hard boss's own.
fn metPeakTargets(peak_id: u32, hard: bool, fight: RecordManager.Fight) RecordManager.Targets {
    if (hard) {
        const boss = findPeakBossConfig(peak_id) orelse return .{};
        if (boss.hard_target == 0) return .{};
        return RecordManager.peakTargetsMet(&[_]u32{boss.hard_target}, fight);
    }
    const peak = findPeakConfig(peak_id) orelse return .{};
    return RecordManager.peakTargetsMet(peak.normal_target_list.items, fight);
}
```

*New handler after onSetChallengePeakBossHardMode*

Before:
```zig
    Logic.Challenge().SetChallengePeakHard(req.is_hard_mode);
    try session.send(CmdID.CmdSetChallengePeakBossHardModeScRsp, rsp);
}
```
After:
```zig
    Logic.Challenge().SetChallengePeakHard(req.is_hard_mode);
    try session.send(CmdID.CmdSetChallengePeakBossHardModeScRsp, rsp);
}
// The season's reward buttons. GetChallengePeakData reports every star reward taken, so the client should not ask;
// if it does, the asked ids come back without items so the window does not hang.
pub fn onTakeChallengePeakReward(session: *Session, packet: *const Packet, allocator: Allocator) !void {
    const req = try packet.getProto(protocol.TakeChallengePeakRewardCsReq, allocator);
    defer req.deinit();
    var rsp = protocol.TakeChallengePeakRewardScRsp.init(allocator);
    rsp.retcode = 0;
    rsp.peak_group_id = req.peak_group_id;
    for (req.normal_reward_id_list.items) |id| {
        try rsp.peak_reward_group_list.append(.{ .reward_id = id, .reward = protocol.ItemList.init(allocator) });
    }
    try session.send(CmdID.CmdTakeChallengePeakRewardScRsp, rsp);
}
```


**3e.** `gameserver/src/handlers.zig` (HandlerList, challenge section):

*Register the reward handler*

Before:
```zig
    .{ CmdID.CmdSetChallengePeakBossHardModeCsReq, challenge.onSetChallengePeakBossHardMode },
```
After:
```zig
    .{ CmdID.CmdSetChallengePeakBossHardModeCsReq, challenge.onSetChallengePeakBossHardMode },
    .{ CmdID.CmdTakeChallengePeakRewardCsReq, challenge.onTakeChallengePeakReward },
```


- [ ] **Step 4: Build + run tests, expect PASS**

```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
"/g/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe" build
(cd gameserver && "/g/Cluade Code/HRSLOPRail/tools/zig-x86_64-windows-0.14.1/zig.exe" build test --summary all)
python tests/test_peak_records.py; echo "exit $?"
python tests/test_challenge_records.py; echo "exit $?"
python tests/test_peak.py; echo "exit $?"
for f in tests/test_*.py; do python "$f" > /dev/null || echo "FAILED $f"; done
```
Expected: `zig build test` passes with three more tests (both target kinds, the kind column, better clear; 23 → 26);
`39 passed, 0 failed` / `exit 0`; the classic test still `44 passed, 0 failed`; Task 5's `/peak` test still passes; no
`FAILED` line.

- [ ] **Step 5: Commit**

```bash
cd "/g/Cluade Code/HRSLOPRail/pearl-sr-4.6.51"
git add resources/BattleTargetConfig.json gameserver/src/manager/record_mgr.zig gameserver/src/data/challenge_config.zig \
        gameserver/src/services/challenge.zig gameserver/src/handlers.zig tests/test_peak_records.py
git status --short   # config.json / hotfix.json must stay unstaged
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Keep Anomaly Arbitration records and answer its reward button

A cleared knight or boss now shows the star targets it met, judged from its
cycles and from whether anyone was knocked down, and the best clear of each
knight and of each boss difficulty is kept in challenge.json. The season's
menu shows those records right after the fight, after /peak and after logging
in; anything never cleared here still shows as cleared, and the season's star
count never drops. The reward button gets an answer (without items) instead
of hanging.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

---

### Notes on Tasks 19–20

Settled with the user's spec decisions: 0-star classic runs are not saved; the AA group update is sent on wins
only; `EEJCPNAEKLJ` = star count; `record_id` = challenge id; `NHOJDHPGBBO`/`DJFGDMIDEHJ` left empty; AS
`Challenge.stage_info.boss_info` not filled.

Still open:
1. `EBNNJAEPBGD` is filled as the best-record team (skin 0) and `LAMPCACOCHP` mirrors the team, as today's fake does;
   both meanings come from M7H, not verified on the client.
2. Unrecorded knights are listed (passed, all targets, cycles 0, no team) only in seasons that have a knight record;
   seasons without one send exactly today's bytes.
3. A failed node that is retried counts only the retry's cycles/downed for classic stars and records;
   `CurChallenge.round_count` still sums every try (unchanged code).
4. `SetChallengePeakMobLineupAvatar`'s own update still sends the minimal group (`obtained_stars = 9`, teams only), as
   before; it could use `sendPeakGroupUpdate` later.

---

## Part D: finish (Task 21)

### Task 21: Whole-branch regression, review and the real-client checklist

**Files:**
- Create: `tests/regression/smoke_record.py`, `tests/regression/smoke_diff.py` (the packet recorder/differ used for the Starward work, kept in the repo from now on)

**Interfaces:**
- Consumes: everything above; `tests/run_all.py`.

- [ ] **Step 1: Every test, one more time**

Run: `cd gameserver && <zig> build test --summary all` → all pass; from the repo root `<zig> build` and `python tests/run_all.py` → `failed: none`.

- [ ] **Step 2: Add the regression tools**

`tests/regression/smoke_record.py`:

```python
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

HOST, PORT = "127.0.0.1", 23301
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
    proc = subprocess.Popen([exe], cwd=run_dir, stdout=open(out_path + ".log", "wb"), stderr=subprocess.STDOUT)
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
```

`tests/regression/smoke_diff.py`:

```python
"""Compares two smoke_record.py outputs packet by packet; prints every step whose packets differ, with the
differing protobuf paths. Usage: python -I smoke_diff.py base.json new.json"""
import json
import struct
import sys


def read_varint(buf, i):
    n = shift = 0
    while True:
        if i >= len(buf):
            raise ValueError("truncated varint")
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return n, i


def decode(buf, depth=0):
    """bytes -> list of (field, value) where value is int, nested list, or bytes; raises on non-message bytes."""
    out, i = [], 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        field, wt = key >> 3, key & 7
        if field == 0:
            raise ValueError("field 0")
        if wt == 0:
            val, i = read_varint(buf, i)
        elif wt == 1:
            if i + 8 > len(buf):
                raise ValueError("truncated")
            val, i = ("f64", struct.unpack("<d", buf[i:i + 8])[0]), i + 8
        elif wt == 5:
            if i + 4 > len(buf):
                raise ValueError("truncated")
            val, i = ("f32", struct.unpack("<f", buf[i:i + 4])[0]), i + 4
        elif wt == 2:
            ln, i = read_varint(buf, i)
            if i + ln > len(buf):
                raise ValueError("truncated")
            raw, i = buf[i:i + ln], i + ln
            val = raw
            if depth < 12 and raw:
                try:
                    val = decode(raw, depth + 1)
                except ValueError:
                    val = raw
        else:
            raise ValueError(f"wire type {wt}")
        out.append((field, val))
    return out


def flatten(tree, prefix=""):
    counts = {}
    for field, val in tree:
        idx = counts.get(field, 0)
        counts[field] = idx + 1
        path = f"{prefix}.{field}[{idx}]"
        if isinstance(val, list):
            yield from flatten(val, path)
        else:
            yield path, val


def describe(v):
    if isinstance(v, (bytes, bytearray)):
        try:
            s = v.decode("utf-8")
            if s.isprintable():
                return repr(s[:60])
        except UnicodeDecodeError:
            pass
        return "0x" + v.hex()[:40]
    return repr(v)


def main():
    base, new = (json.load(open(p)) for p in sys.argv[1:3])
    assert len(base) == len(new), (len(base), len(new))
    differing = 0
    for b, n in zip(base, new):
        assert b["label"] == n["label"]
        lines = []
        if (b["dropped"], b["got_rsp"]) != (n["dropped"], n["got_rsp"]):
            lines.append(f"  dropped/got_rsp: {b['dropped']},{b['got_rsp']} -> {n['dropped']},{n['got_rsp']}")
        bc, nc = [p[0] for p in b["packets"]], [p[0] for p in n["packets"]]
        if bc != nc:
            lines.append(f"  packet list: {bc} -> {nc}")
        for (cb, hb), (cn, hn) in zip(b["packets"], n["packets"]):
            if cb != cn or hb == hn:
                continue
            fb = dict(flatten(decode(bytes.fromhex(hb))))
            fn = dict(flatten(decode(bytes.fromhex(hn))))
            keys = sorted(set(fb) | set(fn))
            diffs = [(k, fb.get(k), fn.get(k)) for k in keys if fb.get(k) != fn.get(k)]
            lines.append(f"  {cb}: {len(diffs)} field(s) differ")
            for k, vb, vn in diffs[:12]:
                lines.append(f"    {k}: {describe(vb) if vb is not None else '-'} -> {describe(vn) if vn is not None else '-'}")
            if len(diffs) > 12:
                lines.append(f"    ... {len(diffs) - 12} more")
        if lines:
            differing += 1
            print(f"[{b['label']}]")
            print("\n".join(lines))
    print(f"\n{differing} of {len(base)} steps differ")
    print("steps without a response:", [s["label"] for s in new if not s["got_rsp"]])
    print("dropped:", [s["label"] for s in new if s["dropped"]])


main()
```

- [ ] **Step 3: Packet diff against the commit before Task 1**

Baseline = the commit before Task 1 (`git log --oneline` — the spec commit `29603e7`). Build it outside the repo and record both builds (each run dir gets a copy of the user's config.json and a junction to resources):

```bash
B=$(mktemp -d)
git archive 29603e7 | tar -x -C "$B"
(cd "$B" && <zig> build)
for v in base new; do mkdir -p "$B/run-$v"; cp config.json "$B/run-$v/"; cmd //c mklink //J "$(cygpath -w "$B/run-$v/resources")" "$(cygpath -w "$PWD/resources")"; done
python -I tests/regression/smoke_record.py "$B/protocol/src/root.zig" "$B/gameserver/src/handlers.zig" "$B/zig-out/bin/gameserver.exe" "$B/run-base" "$B/base.json"
python -I tests/regression/smoke_record.py protocol/src/root.zig gameserver/src/handlers.zig zig-out/bin/gameserver.exe "$B/run-new" "$B/new.json"
python -I tests/regression/smoke_diff.py "$B/base.json" "$B/new.json" > "$B/diff.txt"; tail -5 "$B/diff.txt"
```

Expected: `0 dropped`, the same "without a response" list as the baseline (or shorter: newly answered requests such as GetPetData, BlindBoxGetData, PetMarbleGetData, SetNickname, MarkReadMail, DelMail, TakeChallengePeakReward are fine). Every differing field is either a timestamp/seed (values near the current Unix time) or one of the intended changes: GetPlayerBoardData (pos 0-based, head icon), GetPlayerDetailInfo (filled), GetMail, GetJukeboxData, GetBattleCollegeData / StartBattleCollege (college stage), GetAllServerPrefsData, GetPetData, GetChallenge / GetChallengeGroupStatistics / ChallengeSettleNotify / GetChallengePeakData / ChallengePeakSettleScNotify / ChallengePeakGroupDataUpdateScNotify (records of the runs the recorder plays). Anything else is a regression: find the task that caused it and fix it there before going on. Clean up: `cmd //c rmdir` each `run-*/resources` junction, then `rm -rf "$B"`.

- [ ] **Step 4: Independent review (GPT-6 Astra, ultra)**

Write the review prompt to a temp file and run Codex read-only on the branch (takes 10–20 min; run in the background):

```bash
cat > "$TEMP/m7h-review.md" <<'EOF'
Review the commits on branch local-4.6.51 after 29603e7 (git log 29603e7..HEAD) in this Zig 0.14.1 Honkai: Star Rail
private server against docs/superpowers/specs/2026-10-15-m7h-commands-profile-design.md and
docs/superpowers/plans/2026-10-15-m7h-commands-profile.md. Read-only. Report only confirmed defects with file:line,
a concrete failing scenario, and severity: crashes/panics reachable from client input or chat commands, client hangs
from bad packets (wrong field, missing reply, notify order), state that is not saved or not restored, files written
outside the server folder, regressions in existing flows (login, battles, MoC/PF/AS classic and Starward, AA).
EOF
powershell -Command "Get-Content \"$env:TEMP\m7h-review.md\" -Raw | & \"$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe\" exec --skip-git-repo-check -m gpt-6-astra -c model_reasoning_effort=\"ultra\" -s read-only -C (Get-Location) -o \"$env:TEMP\m7h-review-result.md\" -"
```

Fix every confirmed defect (each fix with a test that fails first), rerun Step 1, commit each fix separately with a message that says what the player would have seen.

- [ ] **Step 5: Commit the regression tools**

```bash
git add tests/regression/smoke_record.py tests/regression/smoke_diff.py
git -c user.name=YourName -c user.email=you@example.com commit -F - <<'EOF'
Keep the packet recorder and differ in tests/regression

smoke_record.py plays login, battles, MoC/PF/AS, AA and Starward and
sweeps every handler against one gameserver build; smoke_diff.py shows
which fields two recordings disagree on.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015Mtpih5bFQ2YGdKsams7q2
EOF
```

- [ ] **Step 6: Hand the real-client checklist to the user (in Thai, in the final message)**

Ask the user to rebuild with the normal script, start the server and check in game, reporting what fails (with `logs\gameserver*.log` if something hangs):
1. Login works; `/help` lists the new commands.
2. `/calyx lineup 1310 1415` then a Calyx: the battle uses those two; `/calyx modify 1 1 1` then a Calyx: the first monster has 1 HP.
3. `/debug specific 400101` then a Calyx: a different fight; the next one is normal again.
4. `/peak 3`: the AA banner changes (or after relogging).
5. `/faketime 20261001` + relog: dates in the challenge menus move; `/faketime off` + relog.
6. `/hero gender 1` / `/hero type 8005`: the Trailblazer changes (relog if not).
7. `/scene cur`, `/scene group`, `/scene change 1000001` (the Express).
8. `/windy` with a small test script in `lua\` (e.g. `CS.UnityEngine.Debug.Log("hi")`).
9. `/json export test`, change a character in SRTools, `/json load test`: the old character is back.
10. Phone: chat bubble / theme / case; profile: signature, avatar icon, card, showcase characters — all still there after a relog.
11. Rename in game; the new name shows after a relog.
12. Mail: open (read), delete; still gone after a relog.
13. Pet: summon one, recall it, summon again after a relog.
14. Jukebox on the Express: pick a track; send the `PlayBackGroundMusic` hex line from the gameserver log.
15. Battle College: one lesson fights its own stage and shows as done afterwards.
16. Classic MoC (the menu's normal mode): clear a floor with both nodes; its stars show the real result; an unplayed floor still shows cleared.
17. AA: clear one knight; its cycles and team show in the record; the boss is still open.
