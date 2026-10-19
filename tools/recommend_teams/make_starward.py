"""Builds frag_starward.json: the Starward mode teams (IGDNEOELFKC, format "team_list_buff") for all 16 stages of the
4.7 beta resources/ChallengeMazeTierceConfig.json. make_recommend.py merges it into recommend_teams.json.

    python make_starward.py           # fetches the Prydwen phases it needs into cache/starward/ (once), then writes
    python make_recommend.py merge

One entry = Node 1 / Node 2 / Node 3 teams, no character in two nodes (all Trailblazers count as one). Node 1 and 2
are the two halves of the stage before the Starward stage (PreChallengeMazeID, ChallengeMazeConfig ...1/...2),
Node 3 is the Starward stage itself. AS and PF nodes get a buff_id, since the client's "Replace" does nothing with
buff 0 there: each AS node has its own buff list (Node 1-3 = ChallengeBossGroupExtra BuffList1-3), and every PF node
picks from the same ChallengeStoryGroupExtra BuffList (see starward_buffs.json). No source records the buff players
picked, so every team gets its node's first buff. MoC has no buff, so its buff_id stays 0.

Stage -> rotation (ChallengeMazeConfig GroupID; names from nanoka.cc 4.6.51 data, dates of the live server):
  MoC  5213 1033 Academy Ghost Story      Prydwen phase 48       weak N1 Ice/Thunder, N2 Fire, N3 Fire/Imaginary
       5313 1034 Stormcleanse             Prydwen phase 60       N1 Thunder/Quantum, N2 Fire/Imaginary, N3 Physical/Fire
       5413 1035 Crossing the Afterlife   game8 (live to 11-02)  N1 Fire/Quantum, N2 Physical/Ice, N3 Fire
       5513 1036 Survival of the Fittest  theorycraft (11-02)    N1 Fire/Wind, N2 Quantum/Imaginary, N3 Physical
       5613 1037 Echo of Darkness         theorycraft (4.7)      N1 Physical/Fire, N2 Ice/Thunder, N3 Fire/Imaginary
  PF  20245 2024 Falsehood to Fact        Prydwen phase 45       N1 Ice/Wind, N2 Fire/Thunder, N3 Physical/Imaginary
      20255 2025 Fabricated Business      Prydwen phase 57       N1 Physical/Imaginary, N2 Fire/Thunder, N3 Fire/Quantum
      20265 2026 Domain Genesis           Prydwen phase 61       N1 Quantum/Imaginary, N2 Physical/Imaginary, N3 Fire/Wind
      20275 2027 (DoT / debuff buffs)     theorycraft (10-19)    N1 Ice/Thunder, N2 Fire/Imaginary, N3 Physical/Ice
      20285 2028 Fiction Made Truth       theorycraft (4.7)      N1 Physical/Thunder, N2 Fire/Quantum, N3 Physical/Imaginary
  AS  30185 3018 Gale of Forgetting       Prydwen phase 42
      30195 3019 Vanguard Knight          Prydwen phase 54
      30205 3020 Celestial Lupine         Prydwen phase 62
      30215 3021 Dominance of Oblivion    theorycraft (10-05)    Soulhook Sovereign / Arbiter of the Lost Abyss / Wolflord
      30225 3022 Navigator's Netherveil   theorycraft (4.7)      King Pom-Pom / Pollux / Argenti
      30235 3023 Navigator's Netherveil   same stage data as 30225
Prydwen phase = the last update of that rotation in /api/star-rail/analytics?phaseId=N (team groups 1-3 = Node 1-3).
20265 / 30205 come out the same as the 4.6 RecommendTeams.json (built from the PF/AS pages, top 10 per node).
"""
import json
import os
import re
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
CACHE = os.path.join(HERE, 'cache', 'starward')
OUT = os.path.join(HERE, 'frag_starward.json')
AVATAR_CONFIG = os.path.join(ROOT, 'resources', 'AvatarConfig.json')
BASE = 'https://www.prydwen.gg'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'

MAX_STARWARD = 300
PRYDWEN_TOP = 10      # teams per node, as the 4.6 PF/AS pages show
THEORY_MAX = 30       # entries per theorycraft stage
GAME8_MAX = 100       # 5413: 12 game8 teams + support swaps; the 4.6 file had 97 sets from the same teams

NODE_BUFFS = json.load(open(os.path.join(HERE, 'starward_buffs.json'), encoding='utf-8'))['stages']
PRYDWEN_IDS = json.load(open(os.path.join(HERE, 'prydwen_characters.json'), encoding='utf-8'))
PRYDWEN_STAGES = {  # stage -> (phase ID, Prydwen page)
    5213: (48, 'memory-of-chaos'), 5313: (60, 'memory-of-chaos'),
    20245: (45, 'pure-fiction'), 20255: (57, 'pure-fiction'), 20265: (61, 'pure-fiction'),
    30185: (42, 'apocalyptic-shadow'), 30195: (54, 'apocalyptic-shadow'), 30205: (62, 'apocalyptic-shadow'),
}

# Avatar IDs (4.7 beta AvatarConfig). Trailblazers as the female ID.
ARCHER, RIN, SABER, GIL = 1015, 1508, 1014, 1509
KAFKA, WELT, ACHERON, BSWAN, HYSILENS = 1005, 1004, 1308, 1307, 1410
SW999, SPARXIE, YG, PEARL, EVAN, AHA, WAVE = 1506, 1501, 1502, 1503, 1505, 1511, 1513
ASHVEIL, MBLADE, NOVA, SUMM = 1504, 1507, 1510, 1512
CASTORICE, EVERNIGHT, CYRENE, HYACINE, TRIBBIE = 1407, 1413, 1415, 1409, 1403
PHAINON, CERYDRA, SUNDAY, SPARKLE, ROBIN, RUANMEI = 1408, 1412, 1313, 1306, 1309, 1303
FIREFLY, FUGUE, DAHLIA, LINGSHA, GALLAGHER = 1310, 1225, 1321, 1222, 1301
DHPT, HUOHUO, AVENTURINE, FUXUAN, ASTA, LYNX = 1414, 1217, 1304, 1208, 1009, 1110
TB_ELATION, TB_HARMONY, TB_ICE = 8010, 8006, 8008


def same_char(a, b):
    return a == b or (8001 <= a <= 8010 and 8001 <= b <= 8010)


def no_repeats(ids):
    return not any(same_char(x, y) for i, x in enumerate(ids) for y in ids[i + 1:])


def best_sets(combos, limit, note):
    """combos: (sort key, lead key, [3 teams], note args), best first. Every lead team (node 1) heads one set before
    any set repeats a lead, so the top of the list shows different teams. Same as make_recommend.py."""
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


# --- Prydwen analytics (past rotations) ---
def prydwen_phase(phase_id):
    path = os.path.join(CACHE, f'phase{phase_id}.json')
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        req = urllib.request.Request(f'{BASE}/api/star-rail/analytics?phaseId={phase_id}', headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=60) as rsp:
            open(path, 'wb').write(rsp.read())
        time.sleep(1)
    return json.load(open(path, encoding='utf-8'))


def prydwen_starward(phase_id, page):
    d = prydwen_phase(phase_id)
    ph = d['phase']
    nodes = []
    for group in ('1', '2', '3'):
        teams = []
        for t in d['teams'][group][:PRYDWEN_TOP]:
            ids = [PRYDWEN_IDS.get(t.get(k)) for k in ('char_one', 'char_two', 'char_three', 'char_four')]
            teams.append({'rank': t['rank'], 'rate': float(t['app_rate']), 'ids': ids})  # 13.0 as the 4.6 page data
        nodes.append(teams)
    combos = []
    for a in nodes[0]:
        for b in nodes[1]:
            for c in nodes[2]:
                ids = a['ids'] + b['ids'] + c['ids']
                if None not in ids and no_repeats(ids):
                    combos.append((a['rank'] + b['rank'] + c['rank'], a['rank'], [a['ids'], b['ids'], c['ids']],
                                   (a, b, c)))
    src = f"{ph['displayVersion']} — {ph['displayName']}"
    return best_sets(combos, MAX_STARWARD, lambda a, b, c: f"Prydwen {src}: node 1 #{a['rank']} ({a['rate']}%), "
                     f"node 2 #{b['rank']} ({b['rate']}%), node 3 #{c['rank']} ({c['rate']}%) (prydwen.gg/star-rail/{page})")


# --- Teams written by hand: (label, [4 IDs]) per node, best first ---
def hand_sets(nodes, limit, note):
    """Every Node 1/2/3 pick without a shared character, ranked by the sum of the teams' places."""
    combos = []
    for i, a in enumerate(nodes[0]):
        for j, b in enumerate(nodes[1]):
            for k, c in enumerate(nodes[2]):
                if no_repeats(a[1] + b[1] + c[1]):
                    combos.append(((i + j + k, i, j), a[0], [a[1], b[1], c[1]], (a[0], b[0], c[0])))
    return best_sets(combos, limit, note)


# MoC 1035 "Crossing the Afterlife" (4.6, live 09-28 to 11-02): game8's Stage 12 page lists its teams in tabs
# First Half / Second Half / Starward Mode, i.e. Node 1 / 2 / 3 (checked 2026-10-01).
G8_5413 = [
    [("Archer DPS", [ARCHER, RIN, SPARKLE, HYACINE]),
     ("Aventurine - Waveflair DPS", [WAVE, ASHVEIL, MBLADE, HYACINE]),
     ("Castorice DPS", [CASTORICE, EVERNIGHT, CYRENE, HYACINE]),
     ("F2P Team", [ARCHER, RIN, ASTA, LYNX])],
    [("Saber DPS", [SABER, GIL, SUMM, HUOHUO]),
     ("Phainon DPS", [PHAINON, SUNDAY, CERYDRA, SUMM]),
     ("Evanescia DPS", [EVAN, TB_ELATION, YG, PEARL]),
     ("F2P Team (Evanescia)", [EVAN, TB_ELATION, ASTA, HUOHUO])],
    [("Silver Wolf Lv.999 DPS", [SW999, SPARXIE, YG, PEARL]),
     ("Himeko - Nova DPS", [NOVA, SUMM, WELT, HUOHUO]),
     ("Firefly DPS", [FIREFLY, DAHLIA, FUGUE, LINGSHA]),
     ("F2P Team (Nova)", [NOVA, TB_ICE, WELT, DHPT])],
]
# game8's "Other Recommended Characters" per half, used to swap out a support another node already took.
G8_5413_SWAPS = [
    {HYACINE: [HUOHUO, DHPT, PEARL], SPARKLE: [SUNDAY, ROBIN]},
    {SUMM: [TRIBBIE, WELT], HUOHUO: [DHPT], YG: [TRIBBIE], PEARL: [DHPT], SUNDAY: [TRIBBIE]},
    {YG: [], PEARL: [HUOHUO, LINGSHA, GALLAGHER], SUMM: [TRIBBIE], HUOHUO: [GALLAGHER, LINGSHA], DHPT: [GALLAGHER]},
]


def with_swaps(nodes, swaps):
    """Each team, then each team with one support swapped (place after the originals of its node)."""
    out = []
    for n, teams in enumerate(nodes):
        extra = []
        for label, ids in teams:
            for i, x in enumerate(ids):
                for y in swaps[n].get(x, []):
                    if y not in ids:
                        extra.append((label, ids[:i] + [y] + ids[i + 1:]))
        out.append(list(teams) + extra)
    return out


def game8_5413():
    nodes = with_swaps(G8_5413, G8_5413_SWAPS)
    src = "game8 Crossing the Afterlife, game8.co/games/Honkai-Star-Rail/archives/438117"
    return hand_sets(nodes, GAME8_MAX, lambda a, b, c: f"N1 {a} / N2 {b} / N3 {c} ({src})")


# --- Theorycraft for the rotations with no data yet (no usage data before they open; 4.7 roster incl. Aeon Aha). ---
# Archetypes, as Prydwen 4.5.2 shows them used; Elation variants with Pearl (4.6) and Aeon Aha (1511, 4.7: Quantum
# Elation, buffs the Emanator's Elation and the team's CRIT DMG).
T = {
    "Castorice": [CASTORICE, EVERNIGHT, CYRENE, HYACINE],
    "Castorice (Summeretto)": [CASTORICE, EVERNIGHT, SUMM, HYACINE],
    "Archer": [ARCHER, RIN, SPARKLE, DHPT],
    "Archer (Huohuo)": [ARCHER, RIN, SPARKLE, HUOHUO],
    "Silver Wolf LV.999": [SW999, SPARXIE, YG, HUOHUO],
    "Silver Wolf LV.999 (Pearl)": [SW999, SPARXIE, YG, PEARL],
    "Silver Wolf LV.999 + Aha": [SW999, AHA, YG, PEARL],
    "Evanescia": [EVAN, TB_ELATION, YG, HUOHUO],
    "Evanescia (Pearl)": [EVAN, TB_ELATION, YG, PEARL],
    "Evanescia + Aha": [EVAN, AHA, YG, PEARL],
    "Aha": [AHA, SPARXIE, YG, PEARL],
    "Waveflair + Aha": [WAVE, AHA, TB_ELATION, PEARL],
    "Waveflair": [WAVE, ASHVEIL, MBLADE, HYACINE],
    "Himeko Nova": [NOVA, SPARKLE, SUNDAY, DHPT],
    "Himeko Nova (Summeretto)": [NOVA, SUMM, WELT, DHPT],
    "Himeko Nova (Mortenax)": [NOVA, MBLADE, WELT, HUOHUO],
    "Firefly": [FIREFLY, FUGUE, DAHLIA, LINGSHA],
    "Firefly (Ruan Mei)": [FIREFLY, FUGUE, RUANMEI, DAHLIA],
    "Firefly (Harmony TB)": [FIREFLY, FUGUE, TB_HARMONY, DAHLIA],
    "DoT Hysilens": [HYSILENS, BSWAN, KAFKA, DHPT],
    "DoT Hysilens (Huohuo)": [HYSILENS, BSWAN, KAFKA, HUOHUO],
    "Saber": [SABER, GIL, SUMM, HUOHUO],
    "Saber (Mortenax)": [SABER, GIL, MBLADE, HUOHUO],
    "Phainon": [PHAINON, CERYDRA, SUNDAY, DHPT],
    "Phainon (Sparkle)": [PHAINON, CERYDRA, SPARKLE, SUNDAY],
    "Acheron": [ACHERON, MBLADE, TRIBBIE, HYACINE],
}
# Sustain swaps when another node took the healer / shielder (tried after the archetypes of that node).
SUSTAIN = [HUOHUO, HYACINE, DHPT, LINGSHA, GALLAGHER, AVENTURINE, FUXUAN]


def theory_nodes(labels):
    """Each node's archetypes, then the same archetypes with another sustain (Pearl counts as one)."""
    nodes = []
    for node in labels:
        teams = [(l, T[l]) for l in node]
        known = [t[1] for t in teams]
        for label, ids in list(teams):
            for i, x in enumerate(ids):
                if x not in SUSTAIN and x != PEARL:
                    continue
                for y in SUSTAIN:
                    swapped = ids[:i] + [y] + ids[i + 1:]
                    if y not in ids and swapped not in known:
                        known.append(swapped)
                        teams.append((label, swapped))
        nodes.append(teams)
    return nodes


def theory_sets(nodes, note):
    """Like hand_sets, but one entry per archetype triple (its best sustain choice), so the entries differ."""
    combos = []
    for i, a in enumerate(nodes[0]):
        for j, b in enumerate(nodes[1]):
            for k, c in enumerate(nodes[2]):
                if no_repeats(a[1] + b[1] + c[1]):
                    combos.append(((i + j + k, i, j), a[0], [a[1], b[1], c[1]], (a[0], b[0], c[0])))
    combos.sort(key=lambda c: c[0])
    seen, uniq = set(), []
    for c in combos:
        if c[3] not in seen:
            seen.add(c[3])
            uniq.append(c)
    return best_sets(uniq, THEORY_MAX, note)


THEORY = {
    # MoC 1036 Survival of the Fittest: Ultimates give 5 Punchline, Aha acts every cycle -> Elation teams first.
    5513: ("MoC 1036 Survival of the Fittest", [
        ["Himeko Nova", "Firefly", "Himeko Nova (Summeretto)", "Saber", "DoT Hysilens", "Firefly (Ruan Mei)",
         "Himeko Nova (Mortenax)"],                                                       # Fire / Wind
        ["Silver Wolf LV.999", "Silver Wolf LV.999 + Aha", "Castorice", "Archer", "Waveflair + Aha",
         "Silver Wolf LV.999 (Pearl)", "Waveflair"],                                      # Quantum / Imaginary
        ["Evanescia", "Evanescia + Aha", "Phainon", "Evanescia (Pearl)", "DoT Hysilens", "Castorice",
         "Phainon (Sparkle)"],                                                            # Physical
    ]),
    # MoC 1037 Echo of Darkness: Basic ATK DMG +50%, Basic ATKs add Memory Turbulence hits.
    5613: ("MoC 1037 Echo of Darkness", [
        ["Himeko Nova", "Evanescia", "Firefly", "Phainon", "Evanescia + Aha", "Himeko Nova (Summeretto)",
         "DoT Hysilens"],                                                                 # Physical / Fire
        ["Castorice", "Saber", "Acheron", "DoT Hysilens", "Evanescia (Pearl)", "Waveflair", "Archer"],  # Ice / Thunder
        ["Silver Wolf LV.999", "Himeko Nova", "Silver Wolf LV.999 + Aha", "Firefly", "Himeko Nova (Summeretto)",
         "Firefly (Harmony TB)", "Silver Wolf LV.999 (Pearl)"],                           # Fire / Imaginary
    ]),
    # PF 2027: Fugato (DoT bursts), Toccata (Ult / FuA), Mirthful Cadence (Elation); debuffs fill Grit.
    20275: ("PF 2027, no name in nanoka.cc 4.6.51", [
        ["DoT Hysilens", "Castorice", "Evanescia (Pearl)", "Acheron", "Saber", "Archer", "DoT Hysilens (Huohuo)"],
        ["Silver Wolf LV.999", "Himeko Nova", "Silver Wolf LV.999 + Aha", "Firefly", "Himeko Nova (Summeretto)",
         "Himeko Nova (Mortenax)"],                                                       # Fire / Imaginary
        ["Castorice", "Evanescia", "DoT Hysilens", "Phainon", "Evanescia + Aha", "Castorice (Summeretto)"],  # Physical / Ice
    ]),
    # PF 2028 Fiction Made Truth: Euphoria (Elation DMG), Delirium, Riddle Fanatic (memosprites).
    20285: ("PF 2028 Fiction Made Truth", [
        ["Evanescia", "Evanescia + Aha", "DoT Hysilens", "Castorice", "Phainon", "Saber", "Acheron"],  # Physical / Thunder
        ["Castorice", "Waveflair + Aha", "Archer", "Himeko Nova", "Aha", "Firefly", "Waveflair"],  # Fire / Quantum
        ["Silver Wolf LV.999", "Silver Wolf LV.999 + Aha", "Evanescia", "Phainon", "Himeko Nova (Summeretto)",
         "Silver Wolf LV.999 (Pearl)"],                                                   # Physical / Imaginary
    ]),
    # AS 3021 Dominance of Oblivion: Weakness Break gives Aha a turn; Ult / Elation DMG taken up.
    # Node buffs: N1 Magic Time / Collapse on Sight / Moment of Opportunity, N2 Comic Relief / Exploit Opening /
    # Land of Fertility, N3 Unstoppable Force (memosprites) / Heroic Vanguard / Unto Apotheosis.
    30215: ("AS 3021 Dominance of Oblivion", [
        ["Silver Wolf LV.999", "Himeko Nova", "Firefly", "Evanescia", "Silver Wolf LV.999 + Aha", "Phainon",
         "Saber", "Himeko Nova (Summeretto)"],                                            # Soulhook Sovereign PFWI
        ["DoT Hysilens", "Evanescia", "Himeko Nova", "Acheron", "Silver Wolf LV.999", "Evanescia + Aha", "Saber"],  # Arbiter PFTI
        ["Castorice", "Archer", "Phainon", "Saber", "Waveflair + Aha", "Firefly", "Castorice (Summeretto)"],  # Wolflord PFWQ
    ]),
    # AS 3022 Navigator's Netherveil: Skill / Elation DMG taken up.
    # Node buffs: N1 Magic Time / Empire of Wealth / Demon City's Collapse (Elation), N2 Unstoppable Force /
    # Innervation / Unstoppable Momentum, N3 Land of Fertility / Literary Brilliance / Beaming Bliss.
    30225: ("AS 3022 Navigator's Netherveil", [
        ["Silver Wolf LV.999", "Silver Wolf LV.999 + Aha", "Evanescia", "Aha", "Evanescia + Aha", "Castorice",
         "Archer", "Himeko Nova"],                                                        # King Pom-Pom PFQI
        ["Castorice", "Archer", "Saber", "Castorice (Summeretto)", "Silver Wolf LV.999", "Waveflair",
         "DoT Hysilens"],                                                                 # Pollux IWQI
        ["Himeko Nova", "Silver Wolf LV.999", "Evanescia", "Phainon", "Firefly", "Himeko Nova (Summeretto)",
         "Castorice", "Saber"],                                                           # Argenti PFII
    ]),
}
THEORY[30235] = ("AS 3023 Navigator's Netherveil", THEORY[30225][1])  # same bosses, buffs and weaknesses


def theorycraft(stage):
    name, labels = THEORY[stage]
    nodes = theory_nodes(labels)
    return theory_sets(nodes, lambda a, b, c: f"Theorycraft, no data yet ({name}): N1 {a} / N2 {b} / N3 {c} "
                                              f"(4.7 beta: node weakness from ChallengeMazeConfig, stage buffs from "
                                              f"nanoka.cc 4.6.51, archetypes as Prydwen 4.5.2 shows them used)")


def main():
    roster = {a['AvatarID'] for a in json.load(open(AVATAR_CONFIG, encoding='utf-8'))['avatar_config']}
    tierce = json.load(open(os.path.join(ROOT, 'resources', 'ChallengeMazeTierceConfig.json'), encoding='utf-8'))
    stages = [t['ID'] for t in tierce['challenge_tierce_config']]

    teams = {}
    for stage, (phase_id, page) in PRYDWEN_STAGES.items():
        teams[stage] = prydwen_starward(phase_id, page)
    teams[5413] = game8_5413()
    for stage in THEORY:
        teams[stage] = theorycraft(stage)

    assert sorted(teams) == sorted(stages), (sorted(teams), sorted(stages))
    for stage, entries in teams.items():
        assert entries, stage
        for e in entries:
            ids = [i for l in e['lineups'] for i in l['avatars']]
            assert len(e['lineups']) == 3 and all(len(l['avatars']) == 4 for l in e['lineups']), (stage, e)
            assert no_repeats(ids) and all(i in roster for i in ids), (stage, e)
            assert not any(8001 <= i <= 8010 and i % 2 for i in ids), (stage, e)

    # AS / PF: each node's first buff (starward_buffs.json).
    for stage, entries in teams.items():
        nodes = NODE_BUFFS.get(str(stage), {}).get('nodes')
        if not nodes:
            continue
        for e in entries:
            for lineup, buffs in zip(e['lineups'], nodes):
                lineup['buff_id'] = buffs[0]['id']

    frag = {"IGDNEOELFKC": {"format": "team_list_buff",
                            "teams": {str(s): teams[s] for s in sorted(teams)}}}
    text = json.dumps(frag, indent=2, ensure_ascii=False)

    text = re.sub(r'\[\s+([\d,\s]+?)\s+\]', lambda m: '[' + ', '.join(m.group(1).split()).replace(',,', ',') + ']', text)
    json.loads(text)
    open(OUT, 'w', encoding='utf-8', newline='\n').write(text + '\n')
    print({s: len(teams[s]) for s in sorted(teams)})


if __name__ == '__main__':
    main()
