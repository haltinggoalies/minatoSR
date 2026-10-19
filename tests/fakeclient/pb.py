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
