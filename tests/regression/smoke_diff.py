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
