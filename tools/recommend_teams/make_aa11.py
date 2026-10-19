"""AA season 11 (4.7 beta, OSBETAWin4.6.51) recommended teams: theorycraft, no community data yet.

Stage data: resources/ChallengePeakConfig.json 1101-1104, ChallengePeakBossConfig.json 1104, nanoka.cc
static.nanoka.cc/hsr/4.6.51/en/peak/11.json (traits + boss buff texts).
  K1 1101  Quantum/Imaginary  Hemovore (lose 500 HP each turn)       Joy Ascendant, Depth Crawler Protoplasm / Yabuli
  K2 1102  Fire/Lightning     Scales (20 stacks, -1 per hit taken)   God-Devourer Offspring, Beyond Overcooked / Murata Graphia
  K3 1103  Fire/Ice           Unwavering (no Toughness DMG), Vanquishment (healing -70%)
                                                                     Winged Serpent, Cyclonic Swarm Mother / Banacademic Office Staff
  Boss 1104 Fire/Wind/Imaginary  Stability, Tainted Remains (-50% HP at start), Interference   Asat Pramad
  Boss buffs: 3033095 Supreme Joy (Elation CRIT DMG +60%), 3033074 Finale's Kiss (Skill/Ult DMG +40%, 25% Energy once),
              3033008 Hammer and Anvil (after an ally's shield/heal: DMG taken -25%, All-Type RES PEN +20%).
Archetypes and order follow Prydwen usage of AA seasons 8-9 and PF/AS 4.5 (the 4.6 data file) plus game8 4.6.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'frag_aa11.json')
AVATARS = os.path.join(HERE, '..', '..', 'resources', 'AvatarConfig.json')
MAX_MOB = 40

ID = {
    "Aha": 1511, "Silver Wolf Lv.999": 1506, "Sparxie": 1501, "Yao Guang": 1502, "Pearl": 1503, "Ashveil": 1504,
    "Evanescia": 1505, "Mortenax Blade": 1507, "Rin Tohsaka": 1508, "Gilgamesh": 1509, "Nova": 1510,
    "Summeretto": 1512, "Waveflair": 1513, "Archer": 1015, "Saber": 1014, "Castorice": 1407, "Evernight": 1413,
    "Cyrene": 1415, "Hyacine": 1409, "Permansor Terrae": 1414, "Sparkle": 1306, "Sunday": 1313, "Huohuo": 1217,
    "Welt": 1004, "Tribbie": 1403, "Firefly": 1310, "Fugue": 1225, "The Dahlia": 1321, "Lingsha": 1222,
    "Ruan Mei": 1303, "Hysilens": 1410, "Black Swan": 1307, "Kafka": 1005, "Phainon": 1408, "Cerydra": 1412,
    "Acheron": 1308, "The Herta": 1401, "Anaxa": 1405, "Aventurine": 1304,
    "Trailblazer (Elation)": 8010, "Trailblazer (Remembrance)": 8008,
}
TC = "theorycraft, 4.7 beta"
SUPREME_JOY, FINALES_KISS, HAMMER_AND_ANVIL = 3033095, 3033074, 3033008  # ChallengePeakBossConfig 1104

# Per knight, best first: (label, team, why).
knight1 = [  # Quantum/Imaginary, Hemovore -> keep a healer
    ("Aha DPS", ["Aha", "Silver Wolf Lv.999", "Yao Guang", "Pearl"], "Quantum + Imaginary Elation, new 4.7"),
    ("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Sparxie", "Yao Guang", "Pearl"], "Imaginary Elation"),
    ("Castorice DPS", ["Castorice", "Evernight", "Cyrene", "Hyacine"], "Quantum, HP loss feeds Castorice"),
    ("Archer DPS", ["Archer", "Rin Tohsaka", "Sparkle", "Permansor Terrae"], "Quantum"),
    ("Aventurine - Waveflair DPS", ["Waveflair", "Trailblazer (Elation)", "Yao Guang", "Pearl"], "Quantum Elation"),
    ("Aha DPS", ["Aha", "Sparxie", "Yao Guang", "Pearl"], "Quantum Elation, new 4.7"),
    ("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Trailblazer (Elation)", "Yao Guang", "Huohuo"], "Imaginary Elation"),
    ("Castorice DPS", ["Castorice", "Evernight", "Summeretto", "Hyacine"], "Quantum"),
    ("Aventurine - Waveflair DPS", ["Waveflair", "Ashveil", "Mortenax Blade", "Hyacine"], "Quantum"),
    ("Archer DPS", ["Archer", "Rin Tohsaka", "Sparkle", "Huohuo"], "Quantum"),
    ("Aha DPS", ["Aha", "Trailblazer (Elation)", "Yao Guang", "Huohuo"], "Quantum Elation, new 4.7"),
    ("Castorice DPS", ["Castorice", "Evernight", "Tribbie", "Hyacine"], "Quantum"),
]
knight2 = [  # Fire/Lightning, Scales -> many hits
    ("Sparxie DPS", ["Sparxie", "Sparkle", "Yao Guang", "Permansor Terrae"], "Fire Elation, many hits"),
    ("Himeko - Nova DPS", ["Nova", "Sparkle", "Sunday", "Permansor Terrae"], "Fire"),
    ("Ashveil DPS", ["Ashveil", "Mortenax Blade", "Tribbie", "Hyacine"], "Lightning + Fire"),
    ("Evanescia DPS", ["Evanescia", "Trailblazer (Elation)", "Yao Guang", "Pearl"], "Elation, Lightning sub-DPS"),
    ("Firefly DPS", ["Firefly", "Fugue", "The Dahlia", "Lingsha"], "Fire Break"),
    ("Saber DPS", ["Saber", "Gilgamesh", "Summeretto", "Huohuo"], "Lightning sub-DPS"),
    ("Himeko - Nova DPS", ["Nova", "Summeretto", "Welt", "Huohuo"], "Fire"),
    ("Acheron DPS", ["Acheron", "Mortenax Blade", "Tribbie", "Hyacine"], "Lightning + Fire"),
    ("Hysilens DoT", ["Hysilens", "Black Swan", "Kafka", "Permansor Terrae"], "DoT ticks strip Scales, Kafka Lightning"),
    ("Aha DPS", ["Aha", "Sparxie", "Yao Guang", "Pearl"], "Elation, Sparxie Fire, new 4.7"),
    ("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Sparxie", "Yao Guang", "Huohuo"], "Elation, Sparxie Fire"),
    ("Firefly DPS", ["Firefly", "Fugue", "Ruan Mei", "The Dahlia"], "Fire Break"),
]
knight3 = [  # Fire/Ice, Unwavering (Break useless), healing -70% -> shields
    ("Evernight DPS", ["Evernight", "Cyrene", "Summeretto", "Permansor Terrae"], "Ice, shield sustain"),
    ("Himeko - Nova DPS", ["Nova", "Sparkle", "Sunday", "Permansor Terrae"], "Fire, shield sustain"),
    ("Sparxie DPS", ["Sparxie", "Sparkle", "Yao Guang", "Permansor Terrae"], "Fire Elation, shield sustain"),
    ("Himeko - Nova DPS", ["Nova", "Summeretto", "Welt", "Aventurine"], "Fire, shield sustain"),
    ("The Herta DPS", ["The Herta", "Anaxa", "Tribbie", "Permansor Terrae"], "Ice"),
    ("Sparxie DPS", ["Sparxie", "Trailblazer (Elation)", "Yao Guang", "Pearl"], "Fire Elation, Pearl Ice"),
    ("Evernight DPS", ["Evernight", "Cyrene", "Trailblazer (Remembrance)", "Aventurine"], "Ice, shield sustain"),
    ("Phainon DPS", ["Phainon", "Cerydra", "Sunday", "Permansor Terrae"], "no Break needed"),
    ("Saber DPS", ["Saber", "Gilgamesh", "Summeretto", "Aventurine"], "no Break needed"),
    ("Archer DPS", ["Archer", "Rin Tohsaka", "Sparkle", "Aventurine"], "no Break needed"),
]
boss = [  # Fire/Wind/Imaginary
    ("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Sparxie", "Yao Guang", "Pearl"], SUPREME_JOY, "Imaginary + Fire Elation"),
    ("Aha DPS", ["Aha", "Silver Wolf Lv.999", "Yao Guang", "Pearl"], SUPREME_JOY, "Elation, new 4.7"),
    ("Himeko - Nova DPS", ["Nova", "Sparkle", "Sunday", "Permansor Terrae"], FINALES_KISS, "Fire, Skill/Ult DMG"),
    ("Castorice DPS", ["Castorice", "Evernight", "Cyrene", "Hyacine"], HAMMER_AND_ANVIL, "Tainted Remains HP loss feeds Castorice, Hyacine heals"),
    ("Himeko - Nova DPS", ["Nova", "Summeretto", "Welt", "Huohuo"], FINALES_KISS, "Fire + Imaginary"),
    ("Sparxie DPS", ["Sparxie", "Sparkle", "Yao Guang", "Permansor Terrae"], SUPREME_JOY, "Fire Elation"),
    ("Evanescia DPS", ["Evanescia", "Trailblazer (Elation)", "Yao Guang", "Pearl"], SUPREME_JOY, "Elation"),
    ("Aha DPS", ["Aha", "Sparxie", "Yao Guang", "Pearl"], SUPREME_JOY, "Elation, new 4.7"),
    ("Saber DPS", ["Saber", "Gilgamesh", "Summeretto", "Huohuo"], FINALES_KISS, "Wind, Ult DMG"),
    ("Firefly DPS", ["Firefly", "Fugue", "The Dahlia", "Lingsha"], HAMMER_AND_ANVIL, "Fire Break, Lingsha heals"),
    ("Archer DPS", ["Archer", "Rin Tohsaka", "Sparkle", "Permansor Terrae"], FINALES_KISS, "Skill DMG"),
    ("Aventurine - Waveflair DPS", ["Waveflair", "Trailblazer (Elation)", "Yao Guang", "Pearl"], SUPREME_JOY, "Elation"),
    ("Ashveil DPS", ["Ashveil", "Mortenax Blade", "Tribbie", "Hyacine"], HAMMER_AND_ANVIL, "Mortenax Fire, Hyacine heals"),
    ("Phainon DPS", ["Phainon", "Cerydra", "Sunday", "Permansor Terrae"], FINALES_KISS, "Skill/Ult DMG"),
    ("Castorice DPS", ["Castorice", "Evernight", "Summeretto", "Hyacine"], HAMMER_AND_ANVIL, "HP loss feeds Castorice"),
    ("Silver Wolf Lv.999 DPS", ["Silver Wolf Lv.999", "Trailblazer (Elation)", "Yao Guang", "Huohuo"], SUPREME_JOY, "Imaginary Elation"),
    ("Hysilens DoT", ["Hysilens", "Black Swan", "Kafka", "Permansor Terrae"], HAMMER_AND_ANVIL, "Black Swan Wind, shields"),
    ("Evernight DPS", ["Evernight", "Cyrene", "Summeretto", "Hyacine"], HAMMER_AND_ANVIL, "Hyacine heals"),
    ("Anaxa DPS", ["Anaxa", "The Herta", "Tribbie", "Permansor Terrae"], FINALES_KISS, "Wind, Skill DMG"),
]


def same_char(a, b):
    return a == b or (8001 <= a <= 8010 and 8001 <= b <= 8010)


def no_repeats(ids):
    return not any(same_char(x, y) for i, x in enumerate(ids) for y in ids[i + 1:])


def knights():
    combos = []
    for ia, a in enumerate(knight1):
        for ib, b in enumerate(knight2):
            for ic, c in enumerate(knight3):
                teams = [[ID[n] for n in t[1]] for t in (a, b, c)]
                if no_repeats(sum(teams, [])):
                    combos.append((ia + ib + ic, ia, teams, (a[0], b[0], c[0])))
    combos.sort(key=lambda c: (c[0], c[1]))
    out, leads = [], set()
    for first_pass in (True, False):  # every knight 1 team leads one set before any lead repeats
        for _, lead, teams, names in combos:
            if first_pass and lead in leads:
                continue
            lineups = [{"avatars": t} for t in teams]
            if any(o["lineups"] == lineups for o in out):
                continue
            leads.add(lead)
            out.append({"note": f"K1 {names[0]} / K2 {names[1]} / K3 {names[2]} ({TC}: stage weakness + "
                                f"Prydwen AA 8-9 + PF/AS 4.5 and game8 4.6 archetypes)", "lineups": lineups})
            if len(out) >= MAX_MOB:
                return out
    return out


def main():
    valid = {a["AvatarID"] for a in json.load(open(AVATARS, encoding="utf-8"))["avatar_config"]}
    mob = knights()
    boss_teams = [{"note": f"{label} ({TC}: {why})", "avatars": [ID[n] for n in t], "buff_id": buff}
                  for label, t, buff, why in boss]
    for lineup in [l["avatars"] for e in mob for l in e["lineups"]] + [t["avatars"] for t in boss_teams]:
        assert len(lineup) == 4 and no_repeats(lineup) and set(lineup) <= valid, lineup
    for e in mob:
        assert no_repeats(sum((l["avatars"] for l in e["lineups"]), [])), e
    assert len(boss_teams) == len({tuple(t["avatars"]) for t in boss_teams})
    config = {
        "CHALLENGE_PEAK_MOB": {"format": "team_list", "teams": {"11": mob}},
        "CHALLENGE_PEAK_BOSS": {"format": "avatars_buff", "teams": {"11": boss_teams}},
    }
    text = json.dumps(config, indent=2, ensure_ascii=False)
    text = re.sub(r'\[\s+([\d,\s]+?)\s+\]', lambda m: '[' + ', '.join(m.group(1).split()).replace(',,', ',') + ']', text)
    json.loads(text)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8", newline="\n").write(text + "\n")
    from collections import Counter
    print("mob", len(mob), "boss", len(boss_teams), Counter(t["buff_id"] for t in boss_teams))
    print("distinct K1 leads in first", len({json.dumps(e['lineups'][0]) for e in mob}))


if __name__ == "__main__":
    main()
