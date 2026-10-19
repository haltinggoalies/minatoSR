"""/calyx on|off: Sync (default) fights config.json's battle in every Calyx, Cavern of Corrosion, Echo of War,
Stagnant Shadow and overworld monster; Original fights their own stages (resources/CocoonConfig.json,
FarmElementConfig.json, PlaneEvent.json)."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import FIXTURE_BATTLE, Server, check, done  # noqa: E402
import pb  # noqa: E402


def resource(name):
    with open(os.path.join(pb.repo_root(), "resources", name), encoding="utf-8") as f:
        return json.load(f)


COCOONS = {(r["id"], r["world_level"]): r["stage_ids"] for r in resource("CocoonConfig.json")}
SHADOWS = {(r["id"], r["world_level"]): r["stage_id"] for r in resource("FarmElementConfig.json")}
PLANE_EVENTS = {r["event_id"]: r["stage_id"] for r in resource("PlaneEvent.json")}
STAGES = {s["StageID"]: s for s in resource("StageConfig.json")["stage_config"]}
CONFIG_STAGE = FIXTURE_BATTLE["stage_id"]


def finish(c):
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")


def cocoon(c, cocoon_id=1001, world_level=6, wave=1, quick=False):
    name = "QuickStartCocoonStage" if quick else "StartCocoonStage"
    rsp, _ = c.call(name + "CsReq", {"cocoon_id": cocoon_id, "wave": wave, "world_level": world_level}, name + "ScRsp")
    finish(c)
    return rsp.get("battle_info", {})


def shadow(c, id_or_stage, world_level=6):
    rsp, _ = c.call("QuickStartFarmElementCsReq", {"PAOFHFLFFHD": id_or_stage, "world_level": world_level},
                    "QuickStartFarmElementScRsp")
    finish(c)
    return rsp


def map_monsters(c):
    """(leader entity id, [(entity id, event id)] of the overworld monsters in the current scene)."""
    scene = c.call("GetCurSceneInfoCsReq", {}, "GetCurSceneInfoScRsp")[0]["scene"]
    monsters = [(e["entity_id"], e["npc_monster"].get("event_id", 0)) for g in scene.get("entity_group_list", [])
                for e in g.get("entity_list", []) if "npc_monster" in e]
    return scene.get("leader_entity_id"), monsters


def hit(c, attacker, entity_ids):
    rsp, _ = c.call("SceneCastSkillCsReq", {"attacked_by_entity_id": attacker, "cast_entity_id": 42, "skill_index": 0,
                                            "assist_monster_entity_id_list": entity_ids}, "SceneCastSkillScRsp")
    finish(c)
    return rsp.get("battle_info", {})


def stages_of(battle):
    return [w.get("battle_stage_id", 0) for w in battle.get("monster_wave_list", [])]


def is_stage_battle(battle, stage_ids):
    """Every wave is a wave of one of `stage_ids`, with that stage's monsters and level, numbered from 1."""
    waves = battle.get("monster_wave_list", [])
    if not stage_ids or any(sid not in STAGES for sid in stage_ids):
        return False
    expected = [(sid, w) for sid in stage_ids for w in STAGES[sid]["MonsterList"]]
    if len(waves) != len(expected) or battle.get("stage_id") != stage_ids[0]:
        return False
    for n, (wave, (sid, monsters)) in enumerate(zip(waves, expected), 1):
        if wave.get("battle_stage_id") != sid or wave.get("battle_wave_id") != n:
            return False
        if [m.get("monster_id") for m in wave.get("monster_list", [])] != monsters:
            return False
        if wave.get("monster_param", {}).get("level") != STAGES[sid]["Level"]:
            return False
    return True


def drawn_from(battle, pool, runs):
    """The battle is `runs` stages, each one of `pool`."""
    picked = []
    for sid in stages_of(battle):
        if sid not in STAGES:
            return False
        if not picked or picked[-1] != sid or len(STAGES[sid]["MonsterList"]) == 1:
            picked.append(sid)
    return len(picked) == runs and all(s in pool for s in picked) and is_stage_battle(battle, picked)


print("resources")
check("every Calyx stage is in StageConfig.json", all(s in STAGES for ids in COCOONS.values() for s in ids))
check("every Stagnant Shadow stage is in StageConfig.json", all(s in STAGES for s in SHADOWS.values()))
check("every overworld event stage is in StageConfig.json", all(s in STAGES for s in PLANE_EVENTS.values()))

with Server() as srv:
    c = srv.login()
    print("Sync is the default")
    check("/calyx says Sync", "Sync" in " ".join(c.command("/calyx")))
    check("a Calyx fights config.json's battle", cocoon(c).get("stage_id") == CONFIG_STAGE)
    check("so does a Stagnant Shadow", shadow(c, 1101).get("battle_info", {}).get("stage_id") == CONFIG_STAGE)

    print("/calyx off = Original")
    lines = c.command("/calyx off")
    check("/calyx off switches to Original", "Original" in " ".join(lines), lines)
    check("/calyx says Original", "Original" in " ".join(c.command("/calyx")))
    b = cocoon(c, 1001, 6, 1)
    check("a Golden Calyx run is one of its own stages", drawn_from(b, COCOONS[(1001, 6)], 1), stages_of(b))
    check("at the requested world level", b.get("world_level") == 6, b.get("world_level"))
    check("with no cycle limit", b.get("rounds_limit", 0) == 0, b.get("rounds_limit"))
    check("and the current team", len(b.get("battle_avatar_list", [])) > 0)
    b = cocoon(c, 1001, 6, 3)
    check("three runs are three of its stages", drawn_from(b, COCOONS[(1001, 6)], 3), stages_of(b))
    b = cocoon(c, 1001, 3, 1)
    check("world level 3 draws from that level's stages", drawn_from(b, COCOONS[(1001, 3)], 1), stages_of(b))
    check("and says so", b.get("world_level") == 3, b.get("world_level"))
    b = cocoon(c, 1201, 6, 1, quick=True)
    check("Cavern of Corrosion from the guide fights its two-wave stage",
          is_stage_battle(b, COCOONS[(1201, 6)]), stages_of(b))
    b = cocoon(c, 1301, 6, 1)
    check("Echo of War fights its boss", is_stage_battle(b, COCOONS[(1301, 6)]), stages_of(b))
    b = cocoon(c, 1001, 9, 1)
    check("a world level past the table uses the highest one", drawn_from(b, COCOONS[(1001, 6)], 1), stages_of(b))
    b = cocoon(c, 1001, 0, 1)
    check("world level 0 in the request means the player's (6)", drawn_from(b, COCOONS[(1001, 6)], 1), stages_of(b))
    check("an unknown Calyx falls back to config.json's battle", cocoon(c, 99999).get("stage_id") == CONFIG_STAGE)

    rsp = shadow(c, 1101, 6)
    check("a Stagnant Shadow by id fights its stage", is_stage_battle(rsp.get("battle_info", {}), [SHADOWS[(1101, 6)]]),
          stages_of(rsp.get("battle_info", {})))
    check("the reply names the shadow and world level", rsp.get("PAOFHFLFFHD") == 1101 and rsp.get("world_level") == 6, rsp)
    rsp = shadow(c, SHADOWS[(1102, 4)], 6)
    check("a Stagnant Shadow by stage id fights that stage",
          is_stage_battle(rsp.get("battle_info", {}), [SHADOWS[(1102, 4)]]), stages_of(rsp.get("battle_info", {})))
    rsp, _ = c.call("ReEnterLastElementStageCsReq", {"stage_id": SHADOWS[(1101, 6)]}, "ReEnterLastElementStageScRsp")
    finish(c)
    check("Challenge Again replays the shadow's stage",
          rsp.get("retcode", 0) == 0 and rsp.get("stage_id") == SHADOWS[(1101, 6)]
          and is_stage_battle(rsp.get("battle_info", {}), [SHADOWS[(1101, 6)]]), rsp)

    print("what Original leaves alone")
    lines = c.command("/calyx modify 1 2 123456")
    check("/calyx modify still works but says it is for Sync", "123456" in " ".join(lines) and "/calyx on" in " ".join(lines), lines)
    b = cocoon(c, 1001, 6, 1)
    check("and does not touch the Calyx's own monsters", 123456 not in [m.get("max_hp") for w in b.get("monster_wave_list", [])
                                                                       for m in w.get("monster_list", [])])
    c.command("/debug specific 400102")
    check("/debug still picks the next battle", cocoon(c).get("stage_id") == 400102)

    print("overworld monsters")
    leader, monsters = map_monsters(c)
    mapped = [(e, PLANE_EVENTS[ev]) for e, ev in monsters if ev in PLANE_EVENTS]
    check("the scene has overworld monsters with known events", len(mapped) >= 2, monsters)
    (m1, s1), (m2, s2) = mapped[0], next(m for m in mapped[1:] if m[1] != mapped[0][1])
    b = hit(c, leader, [m1])
    check("hitting one fights its event's stage", is_stage_battle(b, [s1]), (stages_of(b), s1))
    check("at world level 6", b.get("world_level") == 6, b.get("world_level"))
    b = hit(c, leader, [m1, m2])
    check("hitting two fights both stages, one after the other", is_stage_battle(b, [s1, s2]), (stages_of(b), [s1, s2]))
    b = hit(c, m2, [m1])
    check("a monster that strikes first leads", is_stage_battle(b, [s2, s1]), (stages_of(b), [s2, s1]))
    b = hit(c, leader, [999])
    check("an unknown monster fights config.json's battle", b.get("stage_id") == CONFIG_STAGE, b.get("stage_id"))

    print("kept across a restart")
    check("profile.json has the mode", srv.read_json("profile.json").get("calyx_sync") is False)
    srv.restart()
    c = srv.login()
    check("/calyx still says Original", "Original" in " ".join(c.command("/calyx")))
    check("and a Calyx still fights its own stage", drawn_from(cocoon(c), COCOONS[(1001, 6)], 1))
    leader, monsters = map_monsters(c)
    b = hit(c, leader, [m1])
    check("the monster has the same entity id after a restart", PLANE_EVENTS.get(dict(monsters).get(m1)) == s1, monsters)
    check("and still fights its own stage", is_stage_battle(b, [s1]), stages_of(b))

    print("/calyx on = Sync again")
    check("/calyx on switches back", "Sync" in " ".join(c.command("/calyx on")))
    check("a Calyx fights config.json's battle again", cocoon(c).get("stage_id") == CONFIG_STAGE)
    check("so does an overworld monster", hit(c, leader, [m1]).get("stage_id") == CONFIG_STAGE)
    rsp, _ = c.call("ReEnterLastElementStageCsReq", {"stage_id": SHADOWS[(1101, 6)]}, "ReEnterLastElementStageScRsp")
    finish(c)
    check("and so does Challenge Again", rsp.get("battle_info", {}).get("stage_id") == CONFIG_STAGE, rsp)
    lines = c.command("/calyx modify 1 2 123456")  # HP changes live in memory only, so the restart dropped it
    check("in Sync /calyx modify does not mention the mode", "/calyx on" not in " ".join(lines), lines)
    hp = [m.get("max_hp") for w in cocoon(c).get("monster_wave_list", []) for m in w.get("monster_list", [])]
    check("where the /calyx modify HP applies", 123456 in hp, hp)

    print("/calyx reset")
    c.command("/calyx lineup 1310")
    lines = c.command("/calyx reset")
    check("/calyx reset answers", "cleared" in " ".join(lines), lines)
    b = cocoon(c)
    check("and clears the team", [a["id"] for a in b.get("battle_avatar_list", [])] != [1310])
    check("and the HP changes", 123456 not in [m.get("max_hp") for w in b.get("monster_wave_list", []) for m in w.get("monster_list", [])])
    check("but not the mode", "Sync" in " ".join(c.command("/calyx")))

done()
