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
