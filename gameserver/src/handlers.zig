const std = @import("std");
const protocol = @import("protocol");
const Session = @import("Session.zig");
const Packet = @import("Packet.zig");
const avatar = @import("services/avatar.zig");
const chat = @import("services/chat.zig");
const gacha = @import("services/gacha.zig");
const item = @import("services/item.zig");
const battle = @import("services/battle.zig");
const login = @import("services/login.zig");
const lineup = @import("services/lineup.zig");
const mail = @import("services/mail.zig");
const misc = @import("services/misc.zig");
const mission = @import("services/mission.zig");
const profile = @import("services/profile.zig");
const scene = @import("services/scene.zig");
const events = @import("services/events.zig");
const challenge = @import("services/challenge.zig");
const pet = @import("services/pet.zig");
const jukebox = @import("services/jukebox.zig");
const college = @import("services/college.zig");
const sync = @import("commands/sync.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const CmdID = protocol.CmdID;

const log = std.log.scoped(.handlers);

const Action = *const fn (*Session, *const Packet, Allocator) anyerror!void;
pub const HandlerList = [_]struct { CmdID, Action }{
    .{ CmdID.CmdPlayerGetTokenCsReq, login.onPlayerGetToken },
    .{ CmdID.CmdPlayerLoginCsReq, login.onPlayerLogin },
    .{ CmdID.CmdPlayerHeartBeatCsReq, misc.onPlayerHeartBeat },
    .{ CmdID.CmdPlayerLoginFinishCsReq, login.onPlayerLoginFinish },
    .{ CmdID.CmdContentPackageGetDataCsReq, login.onContentPackageGetData },
    .{ CmdID.CmdSetClientPausedCsReq, login.onSetClientPaused },
    .{ CmdID.CmdGetArchiveDataCsReq, login.onGetArchiveData },
    .{ CmdID.CmdGetUpdatedArchiveDataCsReq, login.onGetUpdatedArchiveData },
    //avatar
    .{ CmdID.CmdGetAvatarDataCsReq, avatar.onGetAvatarData },
    .{ CmdID.CmdSetAvatarPathCsReq, avatar.onSetAvatarPath },
    .{ CmdID.CmdGetBasicInfoCsReq, avatar.onGetBasicInfo },
    .{ CmdID.CmdTakeOffAvatarSkinCsReq, avatar.onTakeOffAvatarSkin },
    .{ CmdID.CmdDressAvatarSkinCsReq, avatar.onDressAvatarSkin },
    .{ CmdID.CmdGetBigDataAllRecommendCsReq, avatar.onGetBigDataAll },
    .{ CmdID.CmdGetBigDataRecommendCsReq, avatar.onGetBigData },
    .{ CmdID.CmdGetPreAvatarGrowthInfoCsReq, avatar.onGetPreAvatarGrowthInfo },
    .{ CmdID.CmdSetPlayerOutfitCsReq, avatar.onSetPlayerOutfit },
    .{ CmdID.CmdSetAvatarEnhancedIdCsReq, avatar.onSetAvatarEnhancedId },
    .{ CmdID.CmdToggleAvatarGlobalBuffCsReq, avatar.onToggleGlobalPassive },
    //bag
    .{ CmdID.CmdGetBagCsReq, item.onGetBag },
    .{ CmdID.CmdUseItemCsReq, item.onUseItem },
    //lineup
    .{ CmdID.CmdChangeLineupLeaderCsReq, lineup.onChangeLineupLeader },
    .{ CmdID.CmdReplaceLineupCsReq, lineup.onReplaceLineup },
    .{ CmdID.CmdGetCurLineupDataCsReq, lineup.onGetCurLineupData },
    .{ CmdID.CmdGetAllLineupDataCsReq, lineup.onGetAllLineupData },
    .{ CmdID.CmdSwitchLineupIndexCsReq, lineup.onSwitchLineupIndex },
    .{ CmdID.CmdSetLineupNameCsReq, lineup.onSetLineupName },
    .{ CmdID.CmdMarkPresetLineupCsReq, lineup.onMarkPresetLineup },
    .{ CmdID.CmdGetLineupAvatarDataCsReq, lineup.onGetLineupAvatarData },
    //battle
    .{ CmdID.CmdStartCocoonStageCsReq, battle.onStartCocoonStage },
    .{ CmdID.CmdPVEBattleResultCsReq, battle.onPVEBattleResult },
    .{ CmdID.CmdSceneCastSkillCsReq, battle.onSceneCastSkill },
    .{ CmdID.CmdSceneCastSkillCostMpCsReq, battle.onSceneCastSkillCostMp },
    .{ CmdID.CmdQuickStartCocoonStageCsReq, battle.onQuickStartCocoonStage },
    .{ CmdID.CmdQuickStartFarmElementCsReq, battle.onQuickStartFarmElement },
    .{ CmdID.CmdReEnterLastElementStageCsReq, battle.onReEnterLastElementStage },
    .{ CmdID.CmdStartBattleCollegeCsReq, college.onStartBattleCollege },
    .{ CmdID.CmdGetBattleCollegeDataCsReq, college.onGetBattleCollegeData },
    .{ CmdID.CmdGetCurBattleInfoCsReq, battle.onGetCurBattleInfo },
    .{ CmdID.CmdSyncClientResVersionCsReq, battle.onSyncClientResVersion },
    //gacha
    .{ CmdID.CmdGetGachaInfoCsReq, gacha.onGetGachaInfo },
    .{ CmdID.CmdBuyGoodsCsReq, gacha.onBuyGoods },
    .{ CmdID.CmdExchangeHcoinCsReq, gacha.onExchangeHcoin },
    .{ CmdID.CmdDoGachaCsReq, gacha.onDoGacha },
    //mail
    .{ CmdID.CmdGetMailCsReq, mail.onGetMail },
    .{ CmdID.CmdTakeMailAttachmentCsReq, mail.onTakeMailAttachment },
    .{ CmdID.CmdMarkReadMailCsReq, mail.onMarkReadMail },
    .{ CmdID.CmdDelMailCsReq, mail.onDelMail },
    //profile
    .{ CmdID.CmdGetPhoneDataCsReq, profile.onGetPhoneData },
    .{ CmdID.CmdSelectPhoneThemeCsReq, profile.onSelectPhoneTheme },
    .{ CmdID.CmdSelectChatBubbleCsReq, profile.onSelectChatBubble },
    .{ CmdID.CmdGetPlayerBoardDataCsReq, profile.onGetPlayerBoardData },
    .{ CmdID.CmdSetDisplayAvatarCsReq, profile.onSetDisplayAvatar },
    .{ CmdID.CmdSetAssistAvatarCsReq, profile.onSetAssistAvatar },
    .{ CmdID.CmdSetSignatureCsReq, profile.onSetSignature },
    .{ CmdID.CmdSetGameplayBirthdayCsReq, profile.onSetGameplayBirthday },
    .{ CmdID.CmdSetHeadIconCsReq, profile.onSetHeadIcon },
    .{ CmdID.CmdSelectPhoneCaseCsReq, profile.onSelectPhoneCase },
    .{ CmdID.CmdUpdatePlayerSettingCsReq, profile.onUpdatePlayerSetting },
    .{ CmdID.CmdGetPlayerDetailInfoCsReq, profile.onGetPlayerDetailInfo },
    .{ CmdID.CmdSetPersonalCardCsReq, profile.onSetPersonalCard },
    .{ CmdID.CmdGetPamSkinDataCsReq, profile.onGetPamSkinData },
    .{ CmdID.CmdSelectPamSkinCsReq, profile.onSelectPamSkin },
    .{ CmdID.CmdSetIsDisplayAvatarInfoCsReq, profile.onSetIsDisplayAvatarInfo },
    .{ CmdID.CmdSetNicknameCsReq, profile.onSetNickname },
    .{ CmdID.CmdSetGenderCsReq, profile.onSetGender },
    .{ CmdID.CmdSetPlayerInfoCsReq, profile.onSetPlayerInfo },
    //pet
    .{ CmdID.CmdGetPetDataCsReq, pet.onGetPetData },
    .{ CmdID.CmdSummonPetCsReq, pet.onSummonPet },
    .{ CmdID.CmdRecallPetCsReq, pet.onRecallPet },
    //jukebox
    .{ CmdID.CmdGetJukeboxDataCsReq, jukebox.onGetJukeboxData },
    .{ CmdID.CmdPlayBackGroundMusicCsReq, jukebox.onPlayBackGroundMusic },
    .{ CmdID.CmdFKLMGEFILDI, jukebox.onEchoTrack }, // -> EGDFPDHNOKO
    .{ CmdID.CmdUnlockBackGroundMusicCsReq, jukebox.onUnlockBackGroundMusic },
    //mission
    .{ CmdID.CmdGetTutorialGuideCsReq, mission.onGetTutorialGuideStatus },
    .{ CmdID.CmdGetMissionStatusCsReq, mission.onGetMissionStatus },
    .{ CmdID.CmdGetTutorialCsReq, mission.onGetTutorialStatus },
    .{ CmdID.CmdUnlockTutorialGuideCsReq, mission.onUnlockTutorialGuide },
    .{ CmdID.CmdUnlockTutorialCsReq, mission.onUnlockTutorial },
    .{ CmdID.CmdFinishTalkMissionCsReq, mission.onFinishTalkMission },
    .{ CmdID.CmdGetQuestDataCsReq, mission.onGetQuestData },
    //chat
    .{ CmdID.CmdGetFriendListInfoCsReq, chat.onGetFriendListInfo },
    .{ CmdID.CmdGetPrivateChatHistoryCsReq, chat.onPrivateChatHistory },
    .{ CmdID.CmdGetChatEmojiListCsReq, chat.onChatEmojiList },
    .{ CmdID.CmdSendMsgCsReq, chat.onSendMsg },
    .{ CmdID.CmdTriggerAiPamSpeakCsReq, chat.onTriggerAiPamSpeak },
    //.{ CmdID.CmdGetAiPamChatHistoryCsReq, chat.onGetAiPamChatHistory },
    //scene
    .{ CmdID.CmdGetCurSceneInfoCsReq, scene.onGetCurSceneInfo },
    .{ CmdID.CmdSceneEntityMoveCsReq, scene.onSceneEntityMove },
    .{ CmdID.CmdEnterSceneCsReq, scene.onEnterScene },
    .{ CmdID.CmdGetSceneMapInfoCsReq, scene.onGetSceneMapInfo },
    .{ CmdID.CmdGetUnlockTeleportCsReq, scene.onGetUnlockTeleport },
    .{ CmdID.CmdEnterSectionCsReq, scene.onEnterSection },
    .{ CmdID.CmdSceneEntityTeleportCsReq, scene.onSceneEntityTeleport },
    .{ CmdID.CmdGetFirstTalkNpcCsReq, scene.onGetFirstTalkNpc },
    .{ CmdID.CmdGetFirstTalkByPerformanceNpcCsReq, scene.onGetFirstTalkByPerformanceNp },
    .{ CmdID.CmdGetNpcTakenRewardCsReq, scene.onGetNpcTakenReward },
    .{ CmdID.CmdUpdateGroupPropertyCsReq, scene.onUpdateGroupProperty },
    .{ CmdID.CmdChangePropTimelineInfoCsReq, scene.onChangePropTimeline },
    .{ CmdID.CmdDeactivateFarmElementCsReq, scene.onDeactivateFarmElement },
    .{ CmdID.CmdGetEnteredSceneCsReq, scene.onGetEnteredScene },
    .{ CmdID.CmdInteractPropCsReq, scene.onInteractProp },
    .{ CmdID.CmdChangeEraFlipperDataCsReq, scene.onChangeEraFlipperData },
    .{ CmdID.CmdSetTrainWorldIdCsReq, scene.onSetTrainWorldId },
    //events
    //.{ CmdID.CmdGetActivityScheduleConfigCsReq, events.onGetActivity },
    .{ CmdID.CmdGetAllServerPrefsDataCsReq, events.onGetAllServerPrefsData },
    .{ CmdID.CmdGetServerPrefsDataCsReq, events.onGetServerPrefsData },
    .{ CmdID.CmdUpdateServerPrefsCsReq, events.onUpdateServerPrefs },
    //challenge
    .{ CmdID.CmdGetChallengeCsReq, challenge.onGetChallenge },
    .{ CmdID.CmdGetChallengeGroupStatisticsCsReq, challenge.onGetChallengeGroupStatistics },
    .{ CmdID.CmdStartChallengeCsReq, challenge.onStartChallenge },
    .{ CmdID.CmdStartPartialChallengeCsReq, challenge.onStartPartialChallenge },
    .{ CmdID.CmdEnterChallengeNextPhaseCsReq, challenge.onEnterChallengeNextPhase },
    .{ CmdID.CmdRestartChallengePhaseCsReq, challenge.onRestartChallengePhase },
    .{ CmdID.CmdLeaveChallengeCsReq, challenge.onLeaveChallenge },
    .{ CmdID.CmdLeaveChallengePeakCsReq, challenge.onLeaveChallengePeak },
    .{ CmdID.CmdLeaveChallengeTierceCsReq, challenge.onLeaveChallengeTierce },
    .{ CmdID.CmdMHJNOBBOFOC, challenge.onStartNextChallengeTierce }, // StartNextChallengeTierceCsReq
    .{ CmdID.CmdPKKFNODINEM, challenge.onReStartChallengeTierce }, // RestartChallengeTierceCsReq
    .{ CmdID.CmdMENLHHCJNCE, challenge.onConfirmChallengeTierceStageSettle }, // ConfirmChallengeTierceStageSettleCsReq
    .{ CmdID.CmdGetCurChallengeCsReq, challenge.onGetCurChallengeScRsp },
    .{ CmdID.CmdGetChallengePeakDataCsReq, challenge.onGetChallengePeakData },
    .{ CmdID.CmdGetChallengeTierceControllerCsReq, challenge.onGetChallengeTierceController },
    .{ CmdID.CmdGetCurChallengePeakCsReq, challenge.onGetCurChallengePeak },
    .{ CmdID.CmdTakeChallengeCumulativeRewardCsReq, challenge.onTakeChallengeReward },
    .{ CmdID.CmdStartChallengePeakCsReq, challenge.onStartChallengePeak },
    .{ CmdID.CmdReStartChallengePeakCsReq, challenge.onReStartChallengePeak },
    .{ CmdID.CmdSetChallengePeakMobLineupAvatarCsReq, challenge.onSetChallengePeakMobLineupAvatar },
    .{ CmdID.CmdSetChallengePeakBossHardModeCsReq, challenge.onSetChallengePeakBossHardMode },
    .{ CmdID.CmdTakeChallengePeakRewardCsReq, challenge.onTakeChallengePeakReward },
    .{ CmdID.CmdGetFriendBattleRecordDetailCsReq, challenge.onGetFriendBattleRecordDetail },
    .{ CmdID.CmdStartChallengeTierceCsReq, challenge.onStartChallengeTierce },
    .{ CmdID.CmdSetChallengeTierceLineupCsReq, challenge.onSetChallengeTierceLineup },
    .{ CmdID.CmdGetChallengeTierceDataCsReq, challenge.onGetChallengeTierceData },
};

const DummyCmdList = [_]struct { CmdID, CmdID }{
    .{ CmdID.CmdGetBagCsReq, CmdID.CmdGetBagScRsp },
    .{ CmdID.CmdGetMarkItemListCsReq, CmdID.CmdGetMarkItemListScRsp },
    .{ CmdID.CmdGetCurAssistCsReq, CmdID.CmdGetCurAssistScRsp },
    .{ CmdID.CmdGetMissionDataCsReq, CmdID.CmdGetMissionDataScRsp },
    //.{ CmdID.CmdGetRogueCommonDialogueDataCsReq, CmdID.CmdGetRogueCommonDialogueDataScRsp },
    .{ CmdID.CmdGetRogueInfoCsReq, CmdID.CmdGetRogueInfoScRsp },
    //.{ CmdID.CmdGetRogueHandbookDataCsReq, CmdID.CmdGetRogueHandbookDataScRsp },
    .{ CmdID.CmdGetRogueEndlessActivityDataCsReq, CmdID.CmdGetRogueEndlessActivityDataScRsp },
    .{ CmdID.CmdChessRogueQueryCsReq, CmdID.CmdChessRogueQueryScRsp },
    .{ CmdID.CmdRogueTournQueryCsReq, CmdID.CmdRogueTournQueryScRsp },
    .{ CmdID.CmdDailyFirstMeetPamCsReq, CmdID.CmdDailyFirstMeetPamScRsp },
    .{ CmdID.CmdGetNpcStatusCsReq, CmdID.CmdGetNpcStatusScRsp },
    .{ CmdID.CmdGetSecretKeyInfoCsReq, CmdID.CmdGetSecretKeyInfoScRsp },
    .{ CmdID.CmdGetHeartDialInfoCsReq, CmdID.CmdGetHeartDialInfoScRsp },
    .{ CmdID.CmdGetVideoVersionKeyCsReq, CmdID.CmdGetVideoVersionKeyScRsp },
    .{ CmdID.CmdHeliobusActivityDataCsReq, CmdID.CmdHeliobusActivityDataScRsp },
    .{ CmdID.CmdGetAetherDivideInfoCsReq, CmdID.CmdGetAetherDivideInfoScRsp },
    .{ CmdID.CmdGetMapRotationDataCsReq, CmdID.CmdGetMapRotationDataScRsp },
    .{ CmdID.CmdPlayerReturnInfoQueryCsReq, CmdID.CmdPlayerReturnInfoQueryScRsp },
    .{ CmdID.CmdGetLevelRewardTakenListCsReq, CmdID.CmdGetLevelRewardTakenListScRsp },
    .{ CmdID.CmdGetMainMissionCustomValueCsReq, CmdID.CmdGetMainMissionCustomValueScRsp },
    .{ CmdID.CmdGetMaterialSubmitActivityDataCsReq, CmdID.CmdGetMaterialSubmitActivityDataScRsp },
    .{ CmdID.CmdRogueTournGetCurRogueCocoonInfoCsReq, CmdID.CmdRogueTournGetCurRogueCocoonInfoScRsp },
    .{ CmdID.CmdRogueMagicQueryCsReq, CmdID.CmdRogueMagicQueryScRsp },
    .{ CmdID.CmdMusicRhythmDataCsReq, CmdID.CmdMusicRhythmDataScRsp },
    //friendlist
    .{ CmdID.CmdGetFriendApplyListInfoCsReq, CmdID.CmdGetFriendApplyListInfoScRsp },
    .{ CmdID.CmdGetChatFriendHistoryCsReq, CmdID.CmdGetChatFriendHistoryScRsp },
    .{ CmdID.CmdGetFriendLoginInfoCsReq, CmdID.CmdGetFriendLoginInfoScRsp },
    .{ CmdID.CmdGetFriendDevelopmentInfoCsReq, CmdID.CmdGetFriendDevelopmentInfoScRsp },
    .{ CmdID.CmdGetFriendRecommendListInfoCsReq, CmdID.CmdGetFriendRecommendListInfoScRsp },
    //add
    .{ CmdID.CmdGetSwitchHandDataCsReq, CmdID.CmdGetSwitchHandDataScRsp },
    .{ CmdID.CmdRogueArcadeGetInfoCsReq, CmdID.CmdRogueArcadeGetInfoScRsp },
    // TrainPartyGetData stays unanswered: an empty reply makes the client's TrainParty module throw at login.
    //.{ CmdID.CmdGetMissionMessageInfoCsReq, CmdID.CmdGetMissionMessageInfoScRsp },//
    .{ CmdID.CmdQueryProductInfoCsReq, CmdID.CmdQueryProductInfoScRsp },
    //.{ CmdID.CmdGetRogueScoreRewardInfoCsReq, CmdID.CmdGetRogueScoreRewardInfoScRsp },
    .{ CmdID.CmdGetQuestRecordCsReq, CmdID.CmdGetQuestRecordScRsp },
    .{ CmdID.CmdGetDailyActiveInfoCsReq, CmdID.CmdGetDailyActiveInfoScRsp },
    .{ CmdID.CmdGetChessRogueNousStoryInfoCsReq, CmdID.CmdGetChessRogueNousStoryInfoScRsp },
    //.{ CmdID.CmdCommonRogueQueryCsReq, CmdID.CmdCommonRogueQueryScRsp },
    .{ CmdID.CmdGetFightActivityDataCsReq, CmdID.CmdGetFightActivityDataScRsp },
    .{ CmdID.CmdGetStarFightDataCsReq, CmdID.CmdGetStarFightDataScRsp },
    .{ CmdID.CmdGetMultipleDropInfoCsReq, CmdID.CmdGetMultipleDropInfoScRsp },
    .{ CmdID.CmdGetPlayerReturnMultiDropInfoCsReq, CmdID.CmdGetPlayerReturnMultiDropInfoScRsp },
    .{ CmdID.CmdGetShareDataCsReq, CmdID.CmdGetShareDataScRsp },
    .{ CmdID.CmdGetTreasureDungeonActivityDataCsReq, CmdID.CmdGetTreasureDungeonActivityDataScRsp },
    .{ CmdID.CmdGetAetherDivideChallengeInfoCsReq, CmdID.CmdGetAetherDivideChallengeInfoScRsp },
    //.{ CmdID.CmdGetStrongChallengeActivityDataCsReq, CmdID.CmdGetStrongChallengeActivityDataScRsp },//
    .{ CmdID.CmdGetOfferingInfoCsReq, CmdID.CmdGetOfferingInfoScRsp },
    .{ CmdID.CmdClockParkGetInfoCsReq, CmdID.CmdClockParkGetInfoScRsp },
    //.{ CmdID.CmdGetGunPlayDataCsReq, CmdID.CmdGetGunPlayDataScRsp },//
    .{ CmdID.CmdGetTrackPhotoActivityDataCsReq, CmdID.CmdGetTrackPhotoActivityDataScRsp },
    .{ CmdID.CmdGetSwordTrainingDataCsReq, CmdID.CmdGetSwordTrainingDataScRsp },
    .{ CmdID.CmdGetFightFestDataCsReq, CmdID.CmdGetFightFestDataScRsp },
    .{ CmdID.CmdDifficultyAdjustmentGetDataCsReq, CmdID.CmdDifficultyAdjustmentGetDataScRsp },
    .{ CmdID.CmdSpaceZooDataCsReq, CmdID.CmdSpaceZooDataScRsp },
    .{ CmdID.CmdGetExpeditionDataCsReq, CmdID.CmdGetExpeditionDataScRsp },
    .{ CmdID.CmdTravelBrochureGetDataCsReq, CmdID.CmdTravelBrochureGetDataScRsp },
    .{ CmdID.CmdRaidCollectionDataCsReq, CmdID.CmdRaidCollectionDataScRsp },
    .{ CmdID.CmdGetRaidInfoCsReq, CmdID.CmdGetRaidInfoScRsp },
    .{ CmdID.CmdGetLoginActivityCsReq, CmdID.CmdGetLoginActivityScRsp },
    .{ CmdID.CmdGetTrialActivityDataCsReq, CmdID.CmdGetTrialActivityDataScRsp },
    .{ CmdID.CmdGetMuseumInfoCsReq, CmdID.CmdGetMuseumInfoScRsp },
    .{ CmdID.CmdGetTelevisionActivityDataCsReq, CmdID.CmdGetTelevisionActivityDataScRsp },
    .{ CmdID.CmdGetTrainVisitorRegisterCsReq, CmdID.CmdGetTrainVisitorRegisterScRsp },
    .{ CmdID.CmdGetBoxingClubInfoCsReq, CmdID.CmdGetBoxingClubInfoScRsp },
    .{ CmdID.CmdTextJoinQueryCsReq, CmdID.CmdTextJoinQueryScRsp },
    .{ CmdID.CmdGetLoginChatInfoCsReq, CmdID.CmdGetLoginChatInfoScRsp },
    .{ CmdID.CmdGetFeverTimeActivityDataCsReq, CmdID.CmdGetFeverTimeActivityDataScRsp },
    .{ CmdID.CmdGetSummonActivityDataCsReq, CmdID.CmdGetSummonActivityDataScRsp },
    .{ CmdID.CmdTarotBookGetDataCsReq, CmdID.CmdTarotBookGetDataScRsp },
    .{ CmdID.CmdGetMarkChestCsReq, CmdID.CmdGetMarkChestScRsp },
    //.{ CmdID.CmdMatchThreeGetDataCsReq, CmdID.CmdMatchThreeGetDataScRsp },//
    //.{ CmdID.CmdUpdateTrackMainMissionCsReq, CmdID.CmdUpdateTrackMainMissionScRsp },
    .{ CmdID.CmdGetNpcMessageGroupCsReq, CmdID.CmdGetNpcMessageGroupScRsp },
    .{ CmdID.CmdGetAllSaveRaidCsReq, CmdID.CmdGetAllSaveRaidScRsp },
    .{ CmdID.CmdGetAssistHistoryCsReq, CmdID.CmdGetAssistHistoryScRsp },
    //.{ CmdID.CmdGetEraFlipperDataCsReq, CmdID.CmdGetEraFlipperDataScRsp },//
    .{ CmdID.CmdGetRechargeGiftInfoCsReq, CmdID.CmdGetRechargeGiftInfoScRsp },
    .{ CmdID.CmdGetRechargeBenefitInfoCsReq, CmdID.CmdGetRechargeBenefitInfoScRsp },
    .{ CmdID.CmdRelicSmartWearGetPlanCsReq, CmdID.CmdRelicSmartWearGetPlanScRsp },
    .{ CmdID.CmdRelicSmartWearGetPinRelicCsReq, CmdID.CmdRelicSmartWearGetPinRelicScRsp },
    .{ CmdID.CmdSetGrowthTargetAvatarCsReq, CmdID.CmdSetGrowthTargetAvatarScRsp },
    .{ CmdID.CmdFateQueryCsReq, CmdID.CmdFateQueryScRsp },
    .{ CmdID.CmdGetPlanetFesDataCsReq, CmdID.CmdGetPlanetFesDataScRsp },
    .{ CmdID.CmdParkourGetDataCsReq, CmdID.CmdParkourGetDataScRsp },
    //.{ CmdID.CmdMatchThreeV2GetDataCsReq, CmdID.CmdMatchThreeV2GetDataScRsp },//
    .{ CmdID.CmdGetMonopolyInfoCsReq, CmdID.CmdGetMonopolyInfoScRsp },
    .{ CmdID.CmdMonopolyGetRegionProgressCsReq, CmdID.CmdMonopolyGetRegionProgressScRsp },
    .{ CmdID.CmdGetMbtiReportCsReq, CmdID.CmdGetMbtiReportScRsp },
    .{ CmdID.CmdGetDrinkMakerDataCsReq, CmdID.CmdGetDrinkMakerDataScRsp },
    .{ CmdID.CmdGetDataCsReq, CmdID.CmdGetDataScRsp },
    .{ CmdID.CmdMarbleGetDataCsReq, CmdID.CmdMarbleGetDataScRsp },
    .{ CmdID.CmdGetPreAvatarActivityListCsReq, CmdID.CmdGetPreAvatarActivityListScRsp },
    .{ CmdID.CmdGetUnreleasedBlockInfoCsReq, CmdID.CmdGetUnreleasedBlockInfoScRsp }, //
    .{ CmdID.CmdGetAssistListCsReq, CmdID.CmdGetAssistListScRsp },
    .{ CmdID.CmdGetFriendAssistListCsReq, CmdID.CmdGetFriendAssistListScRsp },
    .{ CmdID.CmdB51RacingGetDataCsReq, CmdID.CmdB51RacingGetDataScRsp },
    .{ CmdID.CmdBlindBoxGetDataCsReq, CmdID.CmdBlindBoxGetDataScRsp },
};

const SuppressLogList = [_]CmdID{CmdID.CmdSceneEntityMoveCsReq};

pub fn handle(session: *Session, packet: *const Packet) !void {
    var arena = ArenaAllocator.init(session.allocator);
    defer arena.deinit();

    sync.checkConfigFile(session, arena.allocator());

    const cmd_id: CmdID = @enumFromInt(packet.cmd_id);

    inline for (HandlerList) |handler| {
        if (handler[0] == cmd_id) {
            try handler[1](session, packet, arena.allocator());
            if (!std.mem.containsAtLeast(CmdID, &SuppressLogList, 1, &[_]CmdID{cmd_id})) {
                log.debug("packet {} was handled", .{cmd_id});
            }
            return;
        }
    }

    inline for (DummyCmdList) |pair| {
        if (pair[0] == cmd_id) {
            try session.send_empty(pair[1]);
            return;
        }
    }

    log.warn("packet {} was ignored", .{cmd_id});
}
