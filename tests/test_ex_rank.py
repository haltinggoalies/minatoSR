import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "fakeclient"))
from client import Server, check, done, fixture_config  # noqa: E402

# Ex Eidolon rank ids are <avatar id>01 (gameserver Data.ExRankAvatarID). The client opens the Ex Eidolon page for any
# avatar with an id in its list, so an avatar without its own Ex Eidolon got an empty Eidolon page (Lua error
# "attempt to index nil with 'ExtraEffectIDList'") while every avatar got all three.
EX_RANKS = {1204: [120401], 1213: [121301], 1308: [130801]}
AVATARS = [1204, 1309, 1308, 1310] + list(range(8001, 8011))

with Server(config=fixture_config(avatars=AVATARS)) as srv:
    c = srv.login()
    rsp, _ = c.call("GetAvatarDataCsReq", {"is_get_all": True}, "GetAvatarDataScRsp")
    paths = rsp.get("avatar_path_data_info_list", [])
    check("avatar path data sent", len(paths) > len(AVATARS), len(paths))
    wrong = [(p.get("avatar_id"), p.get("IGDEHGIKFJA", [])) for p in paths
             if p.get("IGDEHGIKFJA", []) != EX_RANKS.get(p.get("avatar_id"), [])]
    check("each avatar lists only its own Ex Eidolon", not wrong, wrong[:5])
    check("Jing Yuan keeps his", [p.get("IGDEHGIKFJA") for p in paths if p.get("avatar_id") == 1204][-1] == [120401])

    rsp, _ = c.call("StartCocoonStageCsReq", {"cocoon_id": 1001, "wave": 1, "world_level": 6}, "StartCocoonStageScRsp")
    fighters = rsp.get("battle_info", {}).get("battle_avatar_list", [])
    check("battle has the lineup", len(fighters) == 4, len(fighters))
    wrong = [(a.get("id"), a.get("IGDEHGIKFJA", [])) for a in fighters
             if a.get("IGDEHGIKFJA", []) != EX_RANKS.get(a.get("id"), [])]
    check("battle avatars list only their own Ex Eidolon", not wrong, wrong)
    c.call("PVEBattleResultCsReq", {"end_status": 1}, "PVEBattleResultScRsp")

done()
