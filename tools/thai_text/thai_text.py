"""Thai text for the 4.7 beta client (CN client, e.g. StarRail_4.6.53_CN_ReversedRooms).

The beta only ships English, Chinese, Japanese and Korean text, but its language table still has the Thai row
(Thai fonts and Thai line breaking). This script builds a Thai TextMap for the beta from the live client's Thai
TextMap, turns Thai on in the beta client and has the dispatch serve it:

    python thai_text.py [build]  # (re)build and switch the beta's text language to Thai
    python thai_text.py restore  # back to the text language the client had before the first build

Paths default to the ones below; pass --beta / --live to use others.

Which text a row gets: every row of the beta's English TextMap is kept, in the beta's order. A row takes the live
Thai text when the live client has Thai for that key and the beta's English is the same as the live English (the
text did not change), differs only in case, punctuation, line breaks, an added or removed a/an/the/to/is/and/of/s
or a doubled word (e.g. the beta fixed "when the the"), or is "..." (the beta blanks most old story text that way).
Anything else stays English: text the beta added or reworded has no Thai yet, and so has text where only a number,
a sign (+ - < > = ≤ ≥ ? /) or a label letter ("Route A") changed.

What build does:
- reads the beta's design data index from the CDN URL the dispatch has in hotfix.json, adds the two Thai TextMap
  files (the full one, lang "th", and the small one the client loads at start) with the same table hashes the live
  client uses, and writes index + files to <repo>/design_override/<version>/<cdn folder>/client/Windows/. The client
  starts its update by asking for M_Design_ArchiveV.bytes and loads the DesignV named in its "M_DesignV" line, so
  that file is written too (pointing at the new index), with M_DesignV.bytes and the Design_PatchV file it names.
  The dispatch hands the client that folder instead of the CDN and redirects every other file to the CDN. The client
  re-reads the index on every start and deletes design files its index does not list, so editing the client's own
  copy does not last.
- copies index and Thai files into the beta's Persistent/DesignData so the next start does not download them.
- adds the small Thai TextMap to the beta's StreamingAssets index too (new DesignV, M_DesignV and
  M_Design_ArchiveV): before it reaches the server the client loads the start TextMap of its text language
  ("TextmapMain_th") from the StreamingAssets index only, and without it the start throws and the screen stays black.
- sets the text language list in the beta's start config (StreamingAssets, the table hsrlingo patches) to Thai.
  The voice language is left alone.
Everything is read and checked before the first write. The StreamingAssets files as they were are kept in
design_override/<version>/boot_backup/ (added.txt lists the files build added there) for restore, which puts back
the text language and keeps the voice language the client has then. Without that backup, build and restore work
the originals out from the client's files (the index without the Thai start TextMap; text language English).

Formats (big-endian index, varint tables), worked out from the 4.6.53 beta and 4.6 live clients:
- M_Design_ArchiveV.bytes: JSON lines; "M_DesignV" = DesignV md5 (ContentHash) and size (FileSize),
  "M_Design_PatchV" = Design_PatchV_<md5>.bytes, the hpatch list from the previous version.
- M_DesignV.bytes (66 bytes): "SRMI", ..., u32le patch version at 0x18, DesignV md5 as 4 u32le words at 0x1c,
  u64le DesignV size at 0x2c, u32le time at 0x34.
- DesignV_<md5>.bytes: u32 0xff, u32 4, i32 file count, i32 table count, then per file: u64 hash, md5[16],
  i64 size, i32 n, n * (u64 table hash, u32 size, u32 offset), u16 + language ("" for most files), u8 0x80.
  Files are stored as <md5>.bytes, or <language>/<md5>.bytes when the language is set.
- TextMap table: zigzag varint row count, rows of varint field mask; bit 0 = key (zigzag varint hash32 + varint
  hash64), bit 1 = text (varint length + UTF-8), bit 2 = HasParam (u8). Its index table: zigzag count, rows of mask
  0x0f, hash64, zigzag offset and zigzag length of the row inside the TextMap table, 0.
- Region language table: 0x00, zigzag count, rows of mask; bit 0 = region ("cn"/"os"), bit 1 = kind (absent =
  text, 1 = voice), bit 2 = zigzag count + language codes, bit 3 = default language.
"""
import argparse
import difflib
import hashlib
import http.client
import json
import os
import re
import shutil
import struct
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))  # pearl-sr repo root, the dispatch's cwd
HOTFIX = os.path.join(ROOT, 'hotfix.json')
OVERRIDE = os.path.join(ROOT, 'design_override')

DEFAULT_BETA = r'D:\Games\StarRail_4.6.53_CN_ReversedRooms'
DEFAULT_LIVE = r'H:\Games\Star Rail Games'

# Table hashes. They are hashes of the table names and the same in every client version.
EN_MAIN, EN_MAIN_INDEX = 0x12676d4ed6e604f2, 0x8cb9a9c1c48a185f  # full English TextMap, file lang "en"
EN_START, EN_START_INDEX = 0xf90c090cbf12fd1f, 0xd726e9f28dfd8ac7  # small English TextMap used at start
TH_MAIN, TH_MAIN_INDEX = 0xf7a4de4a0a526a66, 0xf4bd7ab48af1b6da  # full Thai TextMap, file lang "th"
TH_START, TH_START_INDEX = 0x1573487e8c3d61ca, 0xafb36ae446fcc629  # small Thai TextMap used at start
START_CONFIG = 0x058690e656a0f775  # StreamingAssets-only config file (language and font tables)
REGION_TABLE = 0xb804dbc76d81fb75  # its text/voice language list per region

PLACEHOLDER = '...'


# ---------------------------------------------------------------- varints

def read_varint(d, p):
    result = shift = 0
    while True:
        b = d[p]
        p += 1
        result |= (b & 0x7f) << shift
        shift += 7
        if b < 0x80:
            return result, p


def unzigzag(n):
    return (n >> 1) ^ -(n & 1)


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7f
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def zigzag(n):
    return varint((n << 1) ^ (n >> 63) if n < 0 else n << 1)


def read_string(d, p):
    n, p = read_varint(d, p)
    return d[p:p + n].decode('utf-8'), p + n


def string(s):
    b = s.encode('utf-8')
    return varint(len(b)) + b


# ---------------------------------------------------------------- design data index

def md5_hex(data):
    return hashlib.md5(data).hexdigest()


def parse_m_designv(d):
    assert len(d) == 66 and d[:4] == b'SRMI', 'not an M_DesignV.bytes'
    words = struct.unpack_from('<4I', d, 0x1c)
    md5 = b''.join(struct.pack('>I', w) for w in words).hex()
    size, = struct.unpack_from('<Q', d, 0x2c)
    return md5, size


def make_m_designv(template, md5, size):
    d = bytearray(template)
    raw = bytes.fromhex(md5)
    struct.pack_into('<4I', d, 0x1c, *struct.unpack('>4I', raw))
    struct.pack_into('<Q', d, 0x2c, size)
    return bytes(d)


def parse_archive(data):
    """M_Design_ArchiveV.bytes: one JSON object per line (CRLF), e.g. FileName "M_DesignV" with the DesignV md5."""
    lines = data.split(b'\r\n')
    assert lines[-1] == b'', 'M_Design_ArchiveV.bytes does not end with a line break'
    entries = [json.loads(line) for line in lines[:-1]]
    assert make_archive(entries) == data, 'M_Design_ArchiveV.bytes round trip failed'
    return entries


def make_archive(entries):
    return b''.join(json.dumps(e, separators=(',', ':'), ensure_ascii=False).encode() + b'\r\n' for e in entries)


def archive_entry(entries, file_name):
    for e in entries:
        if e['FileName'] == file_name:
            return e
    raise SystemExit(f'M_Design_ArchiveV.bytes has no {file_name}')


def parse_designv(d):
    head = d[:8]
    count, = struct.unpack_from('>i', d, 8)
    p = 16
    files = []
    for _ in range(count):
        file_hash, = struct.unpack_from('>Q', d, p)
        md5 = d[p + 8:p + 24].hex()
        size, n = struct.unpack_from('>qi', d, p + 24)
        p += 36
        tables = []
        for _ in range(n):
            tables.append(struct.unpack_from('>QII', d, p))
            p += 16
        lang_len, = struct.unpack_from('>H', d, p)
        lang = d[p + 2:p + 2 + lang_len].decode()
        p += 2 + lang_len
        flag = d[p]
        p += 1
        files.append({'hash': file_hash, 'md5': md5, 'size': size, 'tables': tables, 'lang': lang, 'flag': flag})
    assert p == len(d), 'DesignV has trailing bytes'
    return head, files


def make_designv(head, files):
    out = bytearray(head)
    out += struct.pack('>ii', len(files), sum(len(f['tables']) for f in files))
    for f in files:
        out += struct.pack('>Q', f['hash']) + bytes.fromhex(f['md5']) + struct.pack('>qi', f['size'], len(f['tables']))
        for t in f['tables']:
            out += struct.pack('>QII', *t)
        lang = f['lang'].encode()
        out += struct.pack('>H', len(lang)) + lang + bytes([f['flag']])
    return bytes(out)


def file_by_hash(files, file_hash):
    for f in files:
        if f['hash'] == file_hash:
            return f
    raise SystemExit(f'design data index has no file {file_hash:016x}')


def table_bytes(data, f, table_hash):
    for h, size, offset in f['tables']:
        if h == table_hash:
            return data[offset:offset + size]
    raise SystemExit(f'file {f["md5"]} has no table {table_hash:016x}')


# ---------------------------------------------------------------- TextMap

def parse_textmap(t):
    """Rows of (mask, hash32, hash64, text, has_param) in file order."""
    n, p = read_varint(t, 0)
    rows = []
    for _ in range(unzigzag(n)):
        mask, p = read_varint(t, p)
        if mask & ~7 or not mask & 1:
            raise SystemExit(f'unexpected TextMap row mask {mask:#x}')
        h32, p = read_varint(t, p)
        h64, p = read_varint(t, p)
        text = has_param = None
        if mask & 2:
            text, p = read_string(t, p)
        if mask & 4:
            has_param = t[p]
            p += 1
        rows.append((mask, unzigzag(h32), h64, text, has_param))
    assert p == len(t), 'TextMap table has trailing bytes'
    return rows


def make_textmap(rows):
    """The TextMap table and its index table."""
    head = zigzag(len(rows))
    body = bytearray(head)
    index = bytearray(head)
    for mask, h32, h64, text, has_param in rows:
        start = len(body)
        body += varint(mask) + zigzag(h32) + varint(h64)
        if mask & 2:
            body += string(text)
        if mask & 4:
            body.append(has_param)
        index += b'\x0f' + varint(h64) + zigzag(start) + zigzag(len(body) - start) + b'\x00'
    return bytes(body), bytes(index)


def text_file(main_hash, index_hash, rows):
    body, index = make_textmap(rows)
    tables = [(main_hash, len(body), 0), (index_hash, len(index), len(body))]
    return body + index, tables


MINOR_WORDS = {'a', 'an', 'the', 'to', 'is', 'and', 'of', 's'}


def tokens(text):
    """Words, numbers and the signs that carry meaning (+ - < > = ≤ ≥ ± ≠ ≈ ? / ×). Other punctuation and line breaks
    are left out."""
    return re.findall(r"[^\W_]+|[#%+\-−<>=≤≥±≠≈?/×\[\]]", text.replace('\\n', ' '))


def minor_edit(old, new):
    """The new text only changes case, punctuation or line breaks, adds or removes a/an/the/to/is/and/of/'s, or drops
    a doubled word ("when the the"). A word, number or sign that changed, or one put in place of another, is not, and
    neither is a capital A or S on its own (a label such as "Route A" or "Rank S")."""
    raw_a, raw_b = tokens(old), tokens(new)
    a, b = [w.lower() for w in raw_a], [w.lower() for w in raw_b]
    if not a or not b:
        return False
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == 'equal':
            continue
        if op == 'replace':
            return False
        seq, raw, start, end = (a, raw_a, i1, i2) if op == 'delete' else (b, raw_b, j1, j2)
        for k in range(start, end):
            w = seq[k]
            minor = w in MINOR_WORDS and not (len(raw[k]) == 1 and raw[k].isupper())
            doubled = w.isalpha() and w in (seq[k - 1] if k else None, seq[k + 1] if k + 1 < len(seq) else None)
            if not minor and not doubled:
                return False
    return True


def merge(beta_en, live_en, live_th, stats):
    """Beta English rows with the live Thai text where it still fits."""
    en = {r[2]: r[3] for r in live_en}
    th = {r[2]: r for r in live_th}
    rows = []
    for row in beta_en:
        mask, h32, h64, text, has_param = row
        t = th.get(h64)
        old = en.get(h64)
        if t is not None and t[3] is not None and old is not None and text is not None and old != text \
                and text != PLACEHOLDER and minor_edit(old, text):
            # The beta only fixed case, punctuation or a doubled "the the": the Thai still says the same.
            stats['thai_minor_edit'] += 1
            rows.append(((mask & 1) | (t[0] & 6), h32, h64, t[3], t[4]))
        elif t is not None and t[3] is not None and (text == PLACEHOLDER or old == text):
            stats['thai_placeholder' if text == PLACEHOLDER and old != text else 'thai'] += 1
            rows.append(((mask & 1) | (t[0] & 6), h32, h64, t[3], t[4]))
        else:
            stats['english_new' if t is None else 'english_changed'] += 1
            rows.append(row)
    return rows


# ---------------------------------------------------------------- region language table

def parse_region_table(t):
    assert t[0] == 0, 'region table does not start with 0'
    n, p = read_varint(t, 1)
    rows = []
    for _ in range(unzigzag(n)):
        mask, p = read_varint(t, p)
        if mask & ~0xf:
            raise SystemExit(f'unexpected region table row mask {mask:#x}')
        row = {'mask': mask, 'region': None, 'kind': 0, 'langs': None, 'default': None}
        if mask & 1:
            row['region'], p = read_string(t, p)
        if mask & 2:
            row['kind'], p = read_varint(t, p)
        if mask & 4:
            k, p = read_varint(t, p)
            row['langs'] = []
            for _ in range(unzigzag(k)):
                s, p = read_string(t, p)
                row['langs'].append(s)
        if mask & 8:
            row['default'], p = read_string(t, p)
        rows.append(row)
    assert p == len(t), 'region table has trailing bytes'
    return rows


def make_region_table(rows):
    out = bytearray(b'\x00') + zigzag(len(rows))
    for row in rows:
        out += varint(row['mask'])
        if row['mask'] & 1:
            out += string(row['region'])
        if row['mask'] & 2:
            out += varint(row['kind'])
        if row['mask'] & 4:
            out += zigzag(len(row['langs'])) + b''.join(string(s) for s in row['langs'])
        if row['mask'] & 8:
            out += string(row['default'])
    return bytes(out)


def text_rows_to(rows, lang):
    """Every text row (kind 0) lists only `lang`. Keeps the list lengths, as hsrlingo does, so the table and with it
    the config file keep their size and the StreamingAssets index stays valid."""
    for row in rows:
        if row['kind'] == 0:
            if row['langs'] is not None:
                row['langs'] = [lang] * len(row['langs'])
            if row['default'] is not None:
                row['default'] = lang
    return rows


def text_langs(rows):
    return {lang for r in rows if r['kind'] == 0 for lang in (r['langs'] or []) + [r['default']] if lang}


def region_table(config, f):
    """Rows, offset and size of the region language table in the start config `config` (index entry `f`)."""
    for h, size, offset in f['tables']:
        if h == REGION_TABLE:
            old = config[offset:offset + size]
            rows = parse_region_table(old)
            if make_region_table(rows) != old:
                raise SystemExit('the region language table round trip failed: its format changed, '
                                 'thai_text.py needs fixing')
            return rows, offset, size
    raise SystemExit('start config has no region language table')


def with_region_table(config, offset, size, rows):
    """`config` with the region table replaced, or None if the new table has another size: the StreamingAssets index
    lists the config's size and the offsets of its tables."""
    new = make_region_table(rows)
    if len(new) != size:
        return None
    return config[:offset] + new + config[offset + size:]


# ---------------------------------------------------------------- client folders

def design_dir(client, where):
    return os.path.join(client, 'StarRail_Data', where, 'DesignData', 'Windows')


def client_version(beta):
    path = os.path.join(beta, 'StarRail_Data', 'StreamingAssets', 'BinaryVersion.bytes')
    if not os.path.exists(path):
        raise SystemExit(f'no beta client in {beta} ({path} is missing): is --beta the beta client folder?')
    with open(path, 'rb') as f:
        m = re.search(rb'(?:CN|OS)[A-Z]*(?:Win|Android)\d+\.\d+\.\d+', f.read())
    if not m:
        raise SystemExit('cannot read the client version from BinaryVersion.bytes')
    return m.group().decode()


def local_file(client, f):
    """The client's copy of an index file if it has one with the right content."""
    name = f['md5'] + '.bytes'
    for where in ('Persistent', 'StreamingAssets'):
        path = os.path.join(design_dir(client, where), f['lang'], name) if f['lang'] else \
            os.path.join(design_dir(client, where), name)
        if os.path.exists(path):
            with open(path, 'rb') as fh:
                data = fh.read()
            if md5_hex(data) == f['md5']:
                return data
    return None


def fetch(url):
    print('  download', url)
    try:
        with urllib.request.urlopen(url, timeout=120) as r:
            return r.read()
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError) as e:
        raise SystemExit(f'cannot download {url}: {e}\n(no internet, or the CDN folder in hotfix.json is gone: '
                         f'update the server)')


def design_file(base, client, f):
    data = local_file(client, f)
    if data is None:
        rel = f'{f["lang"]}/{f["md5"]}.bytes' if f['lang'] else f'{f["md5"]}.bytes'
        data = fetch(f'{base}/client/Windows/{rel}')
        if md5_hex(data) != f['md5']:
            raise SystemExit(f'{rel} from the CDN has the wrong md5')
    return data


def client_index(client):
    """The index the client itself last saved (its Persistent copy)."""
    folder = design_dir(client, 'Persistent')
    try:
        with open(os.path.join(folder, 'M_DesignV.bytes'), 'rb') as fh:
            md5, _ = parse_m_designv(fh.read())
        with open(os.path.join(folder, f'DesignV_{md5}.bytes'), 'rb') as fh:
            return parse_designv(fh.read())[1]
    except FileNotFoundError as e:
        raise SystemExit(f'no design data index in {folder} ({e.filename}): is --live the live client folder, '
                         f'and has that client been started once?')


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as fh:
        fh.write(data)


# ---------------------------------------------------------------- commands

def build(beta, live):
    version = client_version(beta)
    with open(HOTFIX, encoding='utf-8') as fh:
        hotfix = json.load(fh).get(version)
    if not hotfix:
        raise SystemExit(f'hotfix.json has no {version}: start the game once with the server first')
    base = hotfix['ex_resource_url'].rstrip('/')
    cdn_folder = base.rsplit('/', 1)[1]
    print(f'{version}, design data {base}')

    # The client asks for M_Design_ArchiveV.bytes and takes the DesignV md5 from its "M_DesignV" line.
    archive = parse_archive(fetch(f'{base}/client/Windows/M_Design_ArchiveV.bytes'))
    design_entry = archive_entry(archive, 'M_DesignV')
    index_md5 = design_entry['ContentHash']
    m_designv = fetch(f'{base}/client/Windows/M_DesignV.bytes')
    if parse_m_designv(m_designv)[0] != index_md5:
        raise SystemExit('the CDN\'s M_DesignV.bytes and M_Design_ArchiveV.bytes disagree: try again later')
    index = fetch(f'{base}/client/Windows/DesignV_{index_md5}.bytes')
    if md5_hex(index) != index_md5:
        raise SystemExit('DesignV from the CDN has the wrong md5')
    head, files = parse_designv(index)
    assert make_designv(head, files) == index, 'DesignV round trip failed'
    files = [f for f in files if f['hash'] not in (TH_MAIN, TH_START)]  # a CDN that ever ships Thai: use ours

    print('reading the TextMaps')
    en_main = file_by_hash(files, EN_MAIN)
    en_start = file_by_hash(files, EN_START)
    beta_en = parse_textmap(table_bytes(design_file(base, beta, en_main), en_main, EN_MAIN))
    beta_en_start = parse_textmap(table_bytes(design_file(base, beta, en_start), en_start, EN_START))

    live_files = client_index(live)
    live_text = {}
    for lang, file_hash, table_hash in (('en', EN_MAIN, EN_MAIN), ('th', TH_MAIN, TH_MAIN)):
        f = file_by_hash(live_files, file_hash)
        data = local_file(live, f)
        if data is None:
            raise SystemExit(f'the live client has no {lang} TextMap: set its text language to '
                             f'{"English" if lang == "en" else "Thai"} once and let it download')
        live_text[lang] = parse_textmap(table_bytes(data, f, table_hash))

    stats = {'thai': 0, 'thai_placeholder': 0, 'thai_minor_edit': 0, 'english_changed': 0, 'english_new': 0}
    th_rows = merge(beta_en, live_text['en'], live_text['th'], stats)
    start_stats = dict.fromkeys(stats, 0)
    th_start_rows = merge(beta_en_start, live_text['en'], live_text['th'], start_stats)
    total = len(th_rows)
    thai = stats['thai'] + stats['thai_placeholder'] + stats['thai_minor_edit']
    print(f'TextMap rows {total}: Thai {stats["thai"]} + Thai for "..." {stats["thai_placeholder"]} '
          f'+ Thai where the beta only fixed case/punctuation {stats["thai_minor_edit"]}, '
          f'English: changed in the beta {stats["english_changed"]}, new in the beta {stats["english_new"]} '
          f'({100 * thai / total:.1f}% Thai)')
    print(f'start TextMap rows {len(th_start_rows)}: Thai {sum(v for k, v in start_stats.items() if k.startswith("thai"))}')

    th_main_data, th_main_tables = text_file(TH_MAIN, TH_MAIN_INDEX, th_rows)
    th_start_data, th_start_tables = text_file(TH_START, TH_START_INDEX, th_start_rows)
    assert parse_textmap(th_main_data[:th_main_tables[0][1]]) == th_rows
    th_main = {'hash': TH_MAIN, 'md5': md5_hex(th_main_data), 'size': len(th_main_data),
               'tables': th_main_tables, 'lang': 'th', 'flag': 0x80}
    th_start = {'hash': TH_START, 'md5': md5_hex(th_start_data), 'size': len(th_start_data),
                'tables': th_start_tables, 'lang': '', 'flag': 0x80}
    new_index = make_designv(head, files + [th_main, th_start])
    new_index_md5 = md5_hex(new_index)
    new_m_designv = make_m_designv(m_designv, new_index_md5, len(new_index))
    design_entry['ContentHash'], design_entry['FileSize'] = new_index_md5, len(new_index)

    out = {
        'M_DesignV.bytes': new_m_designv,
        f'DesignV_{new_index_md5}.bytes': new_index,
        f'th/{th_main["md5"]}.bytes': th_main_data,
        f'{th_start["md5"]}.bytes': th_start_data,
    }
    served = dict(out)
    served['M_Design_ArchiveV.bytes'] = make_archive(archive)
    # The update step also fetches the patch list named here; keep it local instead of a redirect to the CDN.
    for e in archive:
        if e['FileName'] == 'M_Design_PatchV':
            name = f'Design_PatchV_{e["ContentHash"]}.bytes'
            served[name] = fetch(f'{base}/client/Windows/{name}')
            if md5_hex(served[name]) != e['ContentHash']:
                raise SystemExit(f'{name} from the CDN has the wrong md5')
    start = start_plan(beta, version, th_start, th_start_data)

    # Built next to the old build, which the dispatch keeps serving until this one is complete.
    version_dir = os.path.join(OVERRIDE, version)
    target = os.path.join(version_dir, cdn_folder)
    partial = target + '.partial'
    if os.path.isdir(partial):
        shutil.rmtree(partial)
    for rel, data in served.items():
        if rel != 'M_DesignV.bytes':
            write(os.path.join(partial, 'client', 'Windows', rel), data)
    write(os.path.join(partial, 'upstream.txt'), base.encode())
    for name in os.listdir(version_dir):  # older builds of this version, e.g. for a CDN folder that is gone
        path = os.path.join(version_dir, name)
        if name not in ('boot_backup', os.path.basename(partial)):
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
    os.rename(partial, target)
    # The dispatch takes a folder with M_DesignV.bytes for a finished build, so it comes last.
    write(os.path.join(target, 'client', 'Windows', 'M_DesignV.bytes'), served['M_DesignV.bytes'])
    print('dispatch files in', target)

    persistent = design_dir(beta, 'Persistent')
    for rel, data in sorted(out.items(), key=lambda item: item[0] == 'M_DesignV.bytes'):
        write(os.path.join(persistent, rel), data)
    print('copied into', persistent)

    apply_start(version, start)
    print('done: start the server with Start-PearlSR-4.6.51.bat, then the game.\n'
          'The beta now needs this server: run "Thai-Beta.bat restore" before you play it with another one.')


def boot_backup(version, name=''):
    return os.path.join(OVERRIDE, version, 'boot_backup', name)


def read(path):
    with open(path, 'rb') as fh:
        return fh.read()


def start_state(beta, version):
    """The StreamingAssets files build changes (index, archive, start config), now and before the first build.

    An index without our start TextMap is as it was (an archive that names another index is put right). Otherwise,
    and for the text language whenever boot_backup has it, the originals come from boot_backup. A file missing there
    (design_override deleted, a new repo folder, a game update) is worked out from the client's files: the index
    without the Thai start TextMap is byte for byte the one build started from, and the text language goes back to
    English."""
    folder = design_dir(beta, 'StreamingAssets')
    m_designv = read(os.path.join(folder, 'M_DesignV.bytes'))
    md5, _ = parse_m_designv(m_designv)
    index_path = os.path.join(folder, f'DesignV_{md5}.bytes')
    if not os.path.exists(index_path):
        raise SystemExit(f'StreamingAssets M_DesignV.bytes names DesignV_{md5}.bytes, which is missing: '
                         f'repair the game files')
    head, files = parse_designv(read(index_path))
    config_f = file_by_hash(files, START_CONFIG)
    config_name = config_f['md5'] + '.bytes'
    current = {'M_DesignV.bytes': m_designv,
               'M_Design_ArchiveV.bytes': read(os.path.join(folder, 'M_Design_ArchiveV.bytes')),
               config_name: read(os.path.join(folder, config_name))}
    rows, offset, size = region_table(current[config_name], config_f)
    original_files = [f for f in files if f['hash'] != TH_START]
    s = {'folder': folder, 'head': head, 'files': files, 'config': (config_name, config_f), 'current': current,
         'ours': len(original_files) < len(files), 'originals': dict(current), 'added': set()}
    added_path = boot_backup(version, 'added.txt')
    if os.path.exists(added_path):
        with open(added_path, encoding='utf-8') as fh:
            s['added'] = set(fh.read().split())

    def original(name, worked_out):
        path = boot_backup(version, name)
        if os.path.exists(path):
            return read(path)
        print(f'no backup of {name}: worked out from the client\'s files')
        return worked_out

    if os.path.exists(boot_backup(version, config_name)) or text_langs(rows) == {'th'}:
        # Kept from the first build even when hsrlingo has set another text language since: restore goes back to it.
        english = with_region_table(current[config_name], offset, size, text_rows_to(rows, 'en'))
        s['originals'][config_name] = original(config_name, english or current[config_name])
    if not s['ours']:
        # A build stopped between the archive and M_DesignV.bytes leaves an archive that names our index.
        entries = parse_archive(current['M_Design_ArchiveV.bytes'])
        e = archive_entry(entries, 'M_DesignV')
        e['ContentHash'], e['FileSize'] = parse_m_designv(m_designv)
        s['originals']['M_Design_ArchiveV.bytes'] = make_archive(entries)
    else:
        index = make_designv(head, original_files)
        index_md5 = md5_hex(index)
        entries = parse_archive(current['M_Design_ArchiveV.bytes'])
        e = archive_entry(entries, 'M_DesignV')
        e['ContentHash'], e['FileSize'] = index_md5, len(index)
        s['originals']['M_DesignV.bytes'] = original('M_DesignV.bytes', make_m_designv(m_designv, index_md5, len(index)))
        s['originals']['M_Design_ArchiveV.bytes'] = original('M_Design_ArchiveV.bytes', make_archive(entries))
        if not os.path.exists(os.path.join(folder, f'DesignV_{index_md5}.bytes')):
            s['originals'][f'DesignV_{index_md5}.bytes'] = index
        if not os.path.exists(added_path):
            s['added'] = {f'DesignV_{md5}.bytes'} | {f['md5'] + '.bytes' for f in files if f['hash'] == TH_START}
    return s


def kept_files(s):
    """StreamingAssets files the client's own index needs: never deleted as files a build added."""
    return {f'DesignV_{parse_m_designv(s["originals"]["M_DesignV.bytes"])[0]}.bytes'} | \
        {f['md5'] + '.bytes' for f in s['files'] if f['hash'] != TH_START and not f['lang']}


def write_added(version, names):
    write(boot_backup(version, 'added.txt'), ''.join(name + '\n' for name in sorted(names)).encode())


def remove_added(s, keep):
    for name in s['added'] - keep - kept_files(s):
        path = os.path.join(s['folder'], name)
        if os.path.exists(path):
            os.remove(path)


def languages(config, f):
    rows = region_table(config, f)[0]
    return ', '.join(f'{r["region"]} {"text" if r["kind"] == 0 else "voice"} {r["default"]}' for r in rows)


def start_plan(beta, version, th_start, th_start_data):
    """What build writes into StreamingAssets: the small Thai TextMap in the index, which the client reads before it
    reaches the server, and Thai as the text language. Worked out and checked before anything is written."""
    s = start_state(beta, version)
    config_name, config_f = s['config']
    index = make_designv(s['head'], [f for f in s['files'] if f['hash'] != TH_START] + [th_start])
    index_md5 = md5_hex(index)
    entries = parse_archive(s['current']['M_Design_ArchiveV.bytes'])
    e = archive_entry(entries, 'M_DesignV')
    e['ContentHash'], e['FileSize'] = index_md5, len(index)
    rows, offset, size = region_table(s['current'][config_name], config_f)
    config = with_region_table(s['current'][config_name], offset, size, text_rows_to(rows, 'th'))
    if config is None:
        raise SystemExit('the language codes in the beta\'s region language table are not all 2 letters long: '
                         'thai_text.py needs fixing')
    s['new_files'] = {f'DesignV_{index_md5}.bytes': index, f'{th_start["md5"]}.bytes': th_start_data}
    # The index files first and M_DesignV.bytes, which names the index, last.
    s['writes'] = {**s['new_files'], config_name: config, 'M_Design_ArchiveV.bytes': make_archive(entries),
                   'M_DesignV.bytes': make_m_designv(s['current']['M_DesignV.bytes'], index_md5, len(index))}
    return s


def apply_start(version, s):
    for name, data in s['originals'].items():
        write(boot_backup(version, name), data)
    write_added(version, s['added'] | set(s['new_files']))  # until the files an earlier build added are gone
    for name, data in s['writes'].items():
        write(os.path.join(s['folder'], name), data)
    remove_added(s, set(s['new_files']))
    write_added(version, s['new_files'])
    config_name, config_f = s['config']
    print('start TextMap added to the StreamingAssets index', next(iter(s['new_files'])))
    print(f'languages in {config_name}:', languages(s['writes'][config_name], config_f))


def restored_config(current, original, f):
    """The text language from before the first build with the voice language the client has now (e.g. one chosen with
    hsrlingo since). None when the text language is no longer Thai: a patcher has set it since build."""
    rows, offset, size = region_table(current, f)
    if text_langs(rows) != {'th'}:
        return None
    try:
        original_rows = region_table(original, f)[0]
    except SystemExit:
        return original
    if [(r['region'], r['kind']) for r in original_rows] != [(r['region'], r['kind']) for r in rows]:
        return original
    merged = [o if r['kind'] == 0 else r for o, r in zip(original_rows, rows)]
    return with_region_table(current, offset, size, merged) or original


def restore(beta):
    version = client_version(beta)
    s = start_state(beta, version)
    config_name, config_f = s['config']
    # The index files first and M_DesignV.bytes, which names the index, last.
    writes = {name: data for name, data in s['originals'].items() if name.startswith('DesignV_')}
    config = restored_config(s['current'][config_name], s['originals'][config_name], config_f)
    if config is None:
        if s['ours']:
            print('the text language was changed after build (e.g. with hsrlingo): left as it is')
    elif config != s['current'][config_name]:
        writes[config_name] = config
    for name in ('M_Design_ArchiveV.bytes', 'M_DesignV.bytes'):
        if s['originals'][name] != s['current'][name]:
            writes[name] = s['originals'][name]
    for name, data in writes.items():
        write(os.path.join(s['folder'], name), data)
        print('restored', name)
    if not writes:
        print('StreamingAssets has no Thai text: left as it is')
    print(f'languages in {config_name}:', languages(writes.get(config_name, s['current'][config_name]), config_f))
    remove_added(s, set())
    version_dir = os.path.join(OVERRIDE, version)
    if os.path.isdir(version_dir):
        shutil.rmtree(version_dir)
        print('removed', version_dir)
    # The client's index is ours: without it the client fetches the CDN's on the next start.
    m_designv = os.path.join(design_dir(beta, 'Persistent'), 'M_DesignV.bytes')
    if os.path.exists(m_designv):
        os.remove(m_designv)
    print('done: the next start downloads the CDN index again')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('command', nargs='?', default='build', choices=['build', 'restore'],
                    help='build (the default): Thai text on; restore: back to the text language before the first build')
    ap.add_argument('--beta', default=DEFAULT_BETA, help='the beta client folder (has StarRail.exe)')
    ap.add_argument('--live', default=DEFAULT_LIVE, help='the live client folder with Thai text downloaded')
    args = ap.parse_args()
    if args.command == 'build':
        build(args.beta, args.live)
    else:
        restore(args.beta)


if __name__ == '__main__':
    main()
