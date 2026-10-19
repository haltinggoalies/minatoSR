"""Builds recommend_teams.json (repo root), the teams of the in-game "Recommended Lineup" window, for the Beta 4.7
(PearlSR) server. Adapted from the 4.6 server's scripts/recommend_teams/make_recommend.py; the JSON schema is the
same as its Config/Custom/RecommendTeams.json, so the file works on both servers.

    python fetch_prydwen.py           # Prydwen data into cache/
    python make_recommend.py          # rebuild frag_aa_4_10.json from cache/, then merge
    python make_recommend.py merge    # merge only (after editing or adding a frag_*.json)

The final file is put together from fragments next to this script, frag_*.json, each written in the final schema
for a part of the data (e.g. frag_aa_4_10.json = Anomaly Arbitration seasons 4-10). This script rebuilds
frag_aa_4_10.json; other fragments are written by hand or by their own scripts. The merge checks every team, swaps
male Trailblazers to the female ID, cuts each list to the client's cap and writes the type keys sorted and the IDs
(as strings) in numeric order. Two fragments giving the same type + ID is an error.

What the client asks for (GetBigDataRecommendCsReq type + ID) and the reply format each needs:
- CHALLENGE_PEAK_MOB, ID = Anomaly Arbitration season: "team_list", one entry = Knight 1-3 teams.
- CHALLENGE_PEAK_BOSS, ID = season: "avatars_buff", one team and its boss buff.
- IGDNEOELFKC (Starward mode), ID = the Starward stage (ChallengeMazeTierceConfig): "team_list_buff", nodes 1-3.
The client shows at most 300 knight sets and 100 boss teams (ConstValueClient
ChallengePeak_Mob/Boss_BigData_Max_Lineup_Num). Lists are ordered by popularity, most used first.

AA sources: Prydwen (seasons 4-9) and game8 (season 10, written below by hand; game8 pages last updated
2026-09-28). When Prydwen has season 10, add its phase ID in fetch_prydwen.py and the game8 teams are no longer used.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))  # pearl-sr repo root, the servers' cwd
CACHE = os.path.join(HERE, 'cache')
FRAG_AA = os.path.join(HERE, 'frag_aa_4_10.json')
OUT = os.path.join(ROOT, 'recommend_teams.json')
AVATAR_CONFIG = os.path.join(ROOT, 'resources', 'AvatarConfig.json')

MAX_MOB, MAX_BOSS, MAX_STARWARD = 300, 100, 300  # Starward has no cap in the data; same as the knights
CAPS = {"CHALLENGE_PEAK_MOB": MAX_MOB, "CHALLENGE_PEAK_BOSS": MAX_BOSS, "IGDNEOELFKC": MAX_STARWARD}
FORMATS = {"avatars", "team_list", "avatars_buff", "two_halves", "team_list_buff"}
TYPE_FORMATS = {"CHALLENGE_PEAK_MOB": "team_list", "CHALLENGE_PEAK_BOSS": "avatars_buff", "IGDNEOELFKC": "team_list_buff"}

# Character name (as game8 writes it) -> avatar ID (Beta 4.7 resources/AvatarConfig.json).
# Trailblazers are written as the female ID; the server swaps to the player's gender.
ID = {
    "Silver Wolf Lv.999": 1506, "Sparxie": 1501, "Yao Guang": 1502, "Pearl": 1503, "Nova": 1510,
    "Summeretto": 1512, "Welt": 1004, "Huohuo": 1217, "Sparkle": 1306, "Permansor Terrae": 1414,
    "Castorice": 1407, "Evernight": 1413, "Hyacine": 1409, "Trailblazer (Lightning)": 8010,
    "Trailblazer (Ice)": 8008, "Waveflair": 1513, "Archer": 1015, "Rin Tohsaka": 1508, "Saber": 1014,
    "Gilgamesh": 1509, "Evanescia": 1505, "Ashveil": 1504, "Mortenax Blade": 1507, "Cyrene": 1415,
    "Phainon": 1408, "Sunday": 1313, "Cerydra": 1412, "Asta": 1009, "Lynx": 1110, "Firefly": 1310,
    "The Dahlia": 1321, "Fugue": 1225, "Lingsha": 1222,
}
# Prydwen character slug -> avatar ID.
PRYDWEN_IDS = json.load(open(os.path.join(HERE, 'prydwen_characters.json'), encoding='utf-8'))

ECSTASY_NIGHT, NAVIGATORS_OATH = 3033082, 3033083  # season 10 boss buffs (ChallengePeakBossConfig 1004)
G8 = "game8.co/games/Honkai-Star-Rail/archives/"


def same_char(a, b):
    # All Trailblazer paths are one character.
    return a == b or (8001 <= a <= 8010 and 8001 <= b <= 8010)


def no_repeats(ids):
    return not any(same_char(x, y) for i, x in enumerate(ids) for y in ids[i + 1:])


def team(label, names, source, buff=0):
    t = {"note": f"{label} ({G8}{source})", "avatars": [ID[n] for n in names]}
    if buff:
        t["buff_id"] = buff
    return t


def best_sets(combos, limit, note):
    """combos: (sort key, lead key, [3 teams], note args), best first. Every lead team (node/knight 1) heads one
    set before any set repeats a lead, so the top of the list shows different teams."""
    combos.sort(key=lambda c: c[0])
    out, leads = [], set()
    for first_pass in (True, False):
        for _, lead_key, teams, args in combos:
            if first_pass and lead_key in leads:
                continue
            lineups = [{"avatars": t} for t in teams]
            if any(o["lineups"] == lineups for o in out):
                continue
            leads.add(lead_key)
            out.append({"note": note(*args), "lineups": lineups})
            if len(out) >= limit:
                return out
    return out


# --- Anomaly Arbitration season 10 "Return to Roots" (4.6), game8 (Prydwen has no data for it yet) ---
knight1 = [team("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Sparxie", "Yao Guang", "Pearl"], "553079"),
           team("Himeko - Nova DPS", ["Nova", "Summeretto", "Welt", "Huohuo"], "553079"),
           team("Sparxie DPS", ["Sparxie", "Sparkle", "Yao Guang", "Permansor Terrae"], "553079")]
knight2 = [team("Castorice DPS", ["Castorice", "Evernight", "Summeretto", "Hyacine"], "553120"),
           team("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Trailblazer (Lightning)", "Yao Guang", "Pearl"], "553120"),
           team("Aventurine - Waveflair DPS", ["Waveflair", "Trailblazer (Lightning)", "Yao Guang", "Pearl"], "553120"),
           team("Archer DPS", ["Archer", "Rin Tohsaka", "Sparkle", "Huohuo"], "553120")]
knight3 = [team("Himeko - Nova DPS", ["Nova", "Welt", "Summeretto", "Huohuo"], "553103"),
           team("Saber DPS", ["Saber", "Gilgamesh", "Summeretto", "Huohuo"], "553103"),
           team("Evanescia DPS", ["Evanescia", "Trailblazer (Lightning)", "Yao Guang", "Pearl"], "553103"),
           team("Sparxie DPS", ["Sparxie", "Sparkle", "Yao Guang", "Permansor Terrae"], "553103")]
king = [team("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Sparxie", "Yao Guang", "Pearl"], "553128", ECSTASY_NIGHT),
        team("Himeko - Nova DPS", ["Nova", "Summeretto", "Welt", "Huohuo"], "553128", NAVIGATORS_OATH),
        team("Evanescia DPS", ["Evanescia", "Trailblazer (Lightning)", "Yao Guang", "Pearl"], "553128", ECSTASY_NIGHT),
        team("Aventurine - Waveflair DPS", ["Waveflair", "Trailblazer (Lightning)", "Yao Guang", "Pearl"], "553128", ECSTASY_NIGHT)]


def season10_knights():
    """game8's per-knight teams share supports (Yao Guang, Huohuo...), so no set is free of repeats. Only sets with
    1 shared character are kept (16 of 48): more means the same team or the same DPS in two knights."""
    name = lambda t: t["note"].split(" (")[0]
    combos = []
    for ia, a in enumerate(knight1):
        for ib, b in enumerate(knight2):
            for ic, c in enumerate(knight3):
                ids = a["avatars"] + b["avatars"] + c["avatars"]
                shared = sum(1 for i, x in enumerate(ids) for y in ids[i + 1:] if same_char(x, y))
                if shared > 1:
                    continue
                combos.append(((shared, ia + ib + ic), name(a), [a["avatars"], b["avatars"], c["avatars"]],
                               (name(a), name(b), name(c), shared)))
    return best_sets(combos, MAX_MOB, lambda a, b, c, shared: f"K1 {a} / K2 {b} / K3 {c}, {shared} shared "
                                                             f"({G8}553079, 553120, 553103)")


# --- Anomaly Arbitration seasons from Prydwen (cache/aa/season<N>.json). Team groups 1-3 are Knight 1-3
# (nodes x01-x03) and 4 is the boss (x04), checked against the stage enemies of seasons 4-9. ---
def prydwen_aa(path):
    d = json.load(open(path, encoding='utf-8'))
    src = f"prydwen.gg/star-rail/anomaly-arbitration {d['phase']['phase']} {d['phase']['displayName']}"

    def teams(group, top):
        out = []
        for t in d['teams'][group]:
            slugs = [t.get(k) for k in ('char_one', 'char_two', 'char_three', 'char_four')]
            ids = [PRYDWEN_IDS.get(s) for s in slugs]
            if None not in ids and no_repeats(ids):
                out.append((t['rank'], t['app_rate'], ids))
            if len(out) >= top:
                break
        return out

    k1, k2, k3 = teams('1', 30), teams('2', 30), teams('3', 30)
    combos = [(a[0] + b[0] + c[0], a[0], [a[2], b[2], c[2]], (a, b, c))
              for a in k1 for b in k2 for c in k3 if no_repeats(a[2] + b[2] + c[2])]
    knights = best_sets(combos, MAX_MOB, lambda a, b, c: f"K1 #{a[0]} ({a[1]}%) / K2 #{b[0]} ({b[1]}%) / "
                                                         f"K3 #{c[0]} ({c[1]}%) ({src})")
    boss = [{"note": f"Boss #{r} ({rate}%) ({src})", "avatars": ids} for r, rate, ids in teams('4', MAX_BOSS)]
    return knights, boss


def dump(config):
    """JSON text with each avatar list on one line."""
    text = json.dumps(config, indent=2, ensure_ascii=False)
    text = re.sub(r'\[\s+([\d,\s]+?)\s+\]', lambda m: '[' + ', '.join(m.group(1).split()).replace(',,', ',') + ']', text)
    json.loads(text)
    return text + '\n'


def make_aa_fragment():
    """frag_aa_4_10.json: CHALLENGE_PEAK_MOB / CHALLENGE_PEAK_BOSS for seasons 4-10."""
    aa_mob, aa_boss = {}, {}
    aa_dir = os.path.join(CACHE, 'aa')
    if not os.path.isdir(aa_dir):
        print('no cache/aa (run fetch_prydwen.py first), keeping', os.path.basename(FRAG_AA))
        return
    for f in sorted(os.listdir(aa_dir), key=lambda f: int(re.sub(r'\D', '', f) or 0)):
        m = re.fullmatch(r'season(\d+)\.json', f)
        if m:
            aa_mob[m.group(1)], aa_boss[m.group(1)] = prydwen_aa(os.path.join(aa_dir, f))
    aa_mob.setdefault("10", season10_knights())
    aa_boss.setdefault("10", king)

    frag = {
        "CHALLENGE_PEAK_MOB": {"format": "team_list", "teams": aa_mob},
        "CHALLENGE_PEAK_BOSS": {"format": "avatars_buff", "teams": aa_boss},
    }
    open(FRAG_AA, 'w', encoding='utf-8', newline='\n').write(dump(frag))
    for key, entry in frag.items():
        print(os.path.basename(FRAG_AA), key, {tid: len(t) for tid, t in entry['teams'].items()})


# --- Merge ---
def female(avatar_id):
    return avatar_id + 1 if 8001 <= avatar_id <= 8010 and avatar_id % 2 == 1 else avatar_id


def check_team(t, fmt, roster, where):
    """Fixes Trailblazer IDs in place; stops on a broken team. Returns warnings that the client copes with
    (not 4 avatars, a character in two lineups of one entry: game8's season 10 sets share one support)."""
    if fmt in ("team_list", "team_list_buff") and t.get("lineups"):
        lists = [("lineups", l) for l in t["lineups"]]
    else:
        lists = [("avatars", t)]
        if fmt == "two_halves":
            lists.append(("second_half", t))
    warn, every = [], []
    for field, holder in lists:
        key = "avatars" if field == "lineups" else field
        ids = holder[key] = [female(int(i)) for i in holder.get(key, [])]
        if not 1 <= len(ids) <= 4 or not no_repeats(ids):
            sys.exit(f'{where}: bad team {ids} ({t.get("note", "")})')
        missing = [i for i in ids if i not in roster]
        if missing:
            sys.exit(f'{where}: avatar {missing} not in resources/AvatarConfig.json ({t.get("note", "")})')
        if len(ids) != 4:
            warn.append('not 4 avatars')
        every += ids
    if len(lists) > 1 and not no_repeats(every):
        warn.append('character in two lineups')
    return warn


NODE_BUFFS = json.load(open(os.path.join(HERE, 'starward_buffs.json'), encoding='utf-8'))['stages']


def check_buffs(t, key, tid, boss_buffs, where):
    """Boss buffs must be one of the season's (ChallengePeakBossConfig BuffList). AS and PF Starward lineups must
    carry one of their node's buffs (starward_buffs.json), since the client's "Replace" ignores a team with buff 0
    there. Knight entries and MoC Starward stages carry none."""
    if key == "IGDNEOELFKC" and tid in NODE_BUFFS:
        bad = []
        for node, lineup in enumerate(t.get("lineups", [])):
            valid = {b["id"] for b in NODE_BUFFS[tid]["nodes"][node]} - {0}
            if lineup.get("buff_id", 0) not in valid:
                bad.append(lineup.get("buff_id", 0))
        if bad:
            sys.exit(f'{where}: Starward node buff {bad} not valid here ({t.get("note", "")})')
        return
    ids = [t.get("buff_id", 0), t.get("second_buff_id", 0)] + [l.get("buff_id", 0) for l in t.get("lineups", [])]
    ids = [int(i) for i in ids if i]
    if key == "CHALLENGE_PEAK_BOSS":
        bad = [i for i in ids if i not in boss_buffs.get(tid, ())]
    else:
        bad = ids
    if bad:
        sys.exit(f'{where}: buff {bad} not valid here ({t.get("note", "")})')


def load_ids():
    """Valid IDs per type: AA season -> its boss buffs, Starward stages."""
    res = os.path.join(ROOT, 'resources')
    load = lambda f, k: json.load(open(os.path.join(res, f), encoding='utf-8'))[k]
    boss = {b['ID']: b['BuffList'] for b in load('ChallengePeakBossConfig.json', 'challenge_peak_boss_config')}
    seasons = {str(g['ID']): boss.get(g['BossLevelID'], [])
               for g in load('ChallengePeakGroupConfig.json', 'challenge_peak_group_config')}
    stages = {str(s['ID']) for s in load('ChallengeMazeTierceConfig.json', 'challenge_tierce_config')}
    return seasons, {"CHALLENGE_PEAK_MOB": set(seasons), "CHALLENGE_PEAK_BOSS": set(seasons), "IGDNEOELFKC": stages}


def merge():
    roster = {a['AvatarID'] for a in json.load(open(AVATAR_CONFIG, encoding='utf-8'))['avatar_config']}
    boss_buffs, valid_ids = load_ids()
    config, origin = {}, {}
    frags = sorted(glob.glob(os.path.join(HERE, 'frag_*.json')))
    if not frags:
        sys.exit('no frag_*.json')
    for path in frags:
        name = os.path.basename(path)
        for key, entry in json.load(open(path, encoding='utf-8')).items():
            key = key.removeprefix("BIG_DATA_RECOMMEND_TYPE_")
            fmt = entry.get("format", "avatars")
            if fmt not in FORMATS or TYPE_FORMATS.get(key, fmt) != fmt:
                sys.exit(f'{name} {key}: format {fmt} (expected {TYPE_FORMATS.get(key, sorted(FORMATS))})')
            out = config.setdefault(key, {"format": fmt, "teams": {}})
            if out["format"] != fmt:
                sys.exit(f'{name} {key}: format {fmt}, {origin[key]} has {out["format"]}')
            origin.setdefault(key, name)
            for tid, teams in entry.get("teams", {}).items():
                tid = str(int(tid))
                where = f'{name} {key} {tid}'
                if tid in out["teams"]:
                    sys.exit(f'{where}: already in {origin[(key, tid)]}')
                if key in valid_ids and tid not in valid_ids[key]:
                    sys.exit(f'{where}: no such season/stage in resources/')
                if not teams:
                    sys.exit(f'{where}: no teams')
                kept, seen, warns = [], set(), {}
                for t in teams:
                    for w in check_team(t, fmt, roster, where):
                        warns[w] = warns.get(w, 0) + 1
                    check_buffs(t, key, tid, boss_buffs, where)
                    same = json.dumps({k: v for k, v in t.items() if k != "note"}, sort_keys=True)
                    if same in seen:
                        warns['duplicate dropped'] = warns.get('duplicate dropped', 0) + 1
                        continue
                    seen.add(same)
                    kept.append(t)
                teams = kept
                cap = CAPS.get(key)
                if cap and len(teams) > cap:
                    warns[f'cut to {cap} from'] = len(teams)
                    teams = teams[:cap]
                if warns:
                    print(f'{where}:', ', '.join(f'{w} {n}' for w, n in warns.items()))
                out["teams"][tid] = teams
                origin[(key, tid)] = name

    config = {k: {"format": config[k]["format"],
                  "teams": dict(sorted(config[k]["teams"].items(), key=lambda i: int(i[0])))}
              for k in sorted(config)}
    open(OUT, 'w', encoding='utf-8', newline='\n').write(dump(config))
    print('wrote', OUT, 'from', ', '.join(os.path.basename(f) for f in frags))
    for key, entry in config.items():
        print(' ', key, entry['format'], {tid: len(t) for tid, t in entry['teams'].items()})


def main():
    if sys.argv[1:] != ['merge']:
        make_aa_fragment()
    merge()


if __name__ == '__main__':
    main()
