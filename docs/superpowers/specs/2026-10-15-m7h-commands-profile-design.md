# คำสั่งแชท + โปรไฟล์/โลก จาก March7thHoney — Design

วันที่: 2026-10-15 · branch: `local-4.6.51` · client: 4.6.51 (4.7 Beta 1)

## เป้าหมาย

เอาฟีเจอร์ที่ March7thHoney (M7H) มีแต่ MushiSR ยังไม่มีมาใส่ เป็นโปรเจกต์ย่อยที่ 1+2 จากแผน 3 ชิ้น (ชิ้นที่ 3 คือ Currency Wars และ SU/DU ซึ่งทำแยกทีหลัง)

- **ชิ้นที่ 1, คำสั่งแชท:** `/calyx`, `/debug`, `/peak`, `/faketime`, `/hero`, `/scene`, `/windy`, `/json`
- **ชิ้นที่ 2, โปรไฟล์/โลก:** Phone, การ์ดผู้เล่น, ServerPrefs, ชื่อ/เพศ, เมล, Pet, Jukebox, Battle College, สถิติ challenge จริง (classic MoC/PF/AS + AA), ปุ่มรับรางวัล AA

**เกณฑ์ว่าเสร็จ:**
- ทุกอย่างในเอกสารนี้ผ่าน fake-client test
- packet ของ flow เดิม (login, ต่อสู้, MoC/PF/AS, Starward, AA) ไม่เปลี่ยน ยกเว้นส่วนที่ตั้งใจเปลี่ยนตามเอกสารนี้
- Codex ultra review แล้วไม่มี defect ที่ยืนยันได้
- ผู้ใช้ลองกับ client จริงตาม checklist ท้ายเอกสาร

## แหล่งอ้างอิง

| แหล่ง | ใช้ทำอะไร |
|---|---|
| `Mar7thLover/March7thHoney-OpenSource` branch `4.6` | C# จริงของ `Command*.cs`, `CalyxOverrideManager`, `ChallengePeakManager`, `ServerTimeProvider`, handler ของ Pet/JukeBox/BattleCollege/Phone/Board |
| `Re/1.2.3-Features` | ชื่อ/opcode/proto/ข้อความ usage ของ M7H 1.2.3 (ใช้ protocol เดียวกับเรา: opcode ตรงกัน 1241/1248) |
| DimbreathBot/TurnBasedGameData `ExcelOutput` | `PetConfig`, `BackGroundMusic`, `BattleCollegeConfig`, `BattleTargetConfig` |

ข้อควรระวัง: ห้ามลอก field tag จาก proto ของ RE ตรง ๆ เพราะบาง message สลับกับของเรา (`ChallengePeakSettleScNotify`, `SceneSummonUnitInfo`, `PlayerSyncScNotify` del relic/equip) ให้ยึด `protocol/src/protocol.pb.zig` ของเราเสมอ

## สิ่งที่ไม่ทำในรอบนี้

- คำสั่ง `/spawn`, `/anno`, `/language`
- `/scene prop|remove|unlockall|fsv|gp|reset` (เปลี่ยนสถานะฉาก เสี่ยงจอค้าง)
- `/debug customP`
- `/json` รับไฟล์รูปแบบ freesr (ให้ใช้ SRTools sync เหมือนเดิม)
- จำ `/calyx` และ `/hero` ข้ามการรีสตาร์ท
- ระบบคลังของจริง: เมล, รางวัล challenge และ Battle College จะไม่ให้ไอเทม
- ตัวละครทดลองของ Battle College, ตุ๊กตา blind box ของ Pet
- จำโหมดยาก AA แยกตามกลุ่ม
- License/activation ของ M7H (ไม่แตะเด็ดขาด)

## โครงสร้าง

### ไฟล์ใหม่

| ไฟล์ | หน้าที่ |
|---|---|
| `gameserver/src/manager/profile_store.zig` | เก็บ/โหลด/บันทึก `profile.json` (ย้ายมาจาก `services/profile.zig`) |
| `gameserver/src/manager/override_mgr.zig` | สถานะชั่วคราวของ `/calyx` และ `/debug` (อยู่ในหน่วยความจำเท่านั้น) |
| `gameserver/src/manager/record_mgr.zig` | สถิติ classic + AA ใน `challenge.json` (ใช้รูปแบบเดียวกับ `tierce_mgr.zig`) |
| `gameserver/src/manager/prefs_mgr.zig` | ServerPrefs ใน `server_prefs.json` |
| `gameserver/src/services/pet.zig`, `services/jukebox.zig`, `services/college.zig` | handler ใหม่ |
| `gameserver/src/commands/{calyx,debug,peak,faketime,hero,scene,windy,json}.zig` | 1 คำสั่งต่อ 1 ไฟล์ |
| `resources/BackGroundMusic.json`, `resources/BattleCollegeConfig.json`, `resources/BattleTargetConfig.json` | ข้อมูลที่ตัดมาเฉพาะ field ที่ใช้ จาก DimbreathBot |

### ไฟล์ข้อมูลผู้ใช้

ทุกไฟล์ untracked และใส่ใน `.git/info/exclude`:
- `profile.json` (เพิ่ม field), `challenge.json`, `server_prefs.json`
- โฟลเดอร์ `configs/` และ `lua/`

ไฟล์ที่เสียจะถูกย้ายไปเป็น `<name>.bad` แล้วเริ่มด้วยค่าเริ่มต้น (เหมือน `tierce.json`)

### `profile.json`

```json
{
  "pam_skin": 252000,
  "nickname": "ReversedRooms",
  "chat_bubble": 0, "phone_theme": 0, "phone_case": 254001,
  "head_icon": 0, "personal_card": 253001, "signature": "",
  "display_avatars": [{"avatar_id": 1415, "pos": 0}],
  "assist_avatars": [1510],
  "mail": {"read": [], "deleted": [], "taken": []},
  "pet": 0,
  "jukebox_track": 0,
  "peak_group": 0,
  "fake_date": 0,
  "college_finished": []
}
```

- ทุก field เป็น optional และ field ที่ไม่รู้จักจะถูกข้าม
- ค่าเริ่มต้นเท่ากับที่เซิร์ฟเวอร์ส่งอยู่ทุกวันนี้ ผู้ใช้เดิมจึงไม่เห็นอะไรเปลี่ยน
- `display_avatars` / `assist_avatars` ที่ว่างแปลว่าใช้ค่าตายตัวเดิมใน `services/profile.zig`
- เขียนแบบ atomic ด้วย buffer ที่ขยายได้ (ของเดิม fixed 256 byte ใส่ signature ไม่พอ)
- ไฟล์ `profile.json` เดิมที่มีแค่ `pam_skin` ต้องโหลดได้

### กฎร่วม

- คำสั่งใหม่ลงทะเบียนใน `command.zig` และเพิ่มบรรทัดใน `commands/help.zig`
- ข้อความตอบใช้ `commandhandler.sendMessage`
- คำสั่งที่รับ argument ผิดต้องตอบ usage กลับ ห้าม error หลุดออกจาก handler
- string ที่มาจาก request (ชื่อ, ลายเซ็น, prefs) ต้อง copy ไปเก็บใน allocator ที่อยู่ยาว เพราะ request ถูก `deinit` หลัง handler จบ
- ทุกอย่างในชิ้นที่ 1 มีผลกับ "การต่อสู้ปกติ" เท่านั้น คือ `BattleManager.createBattle`: Calyx, quick Calyx, farm element, มอนในโลก ไม่แตะ `ChallegeStageManager` (MoC/PF/AS/Starward/AA)

## ชิ้นที่ 1: คำสั่งแชท

### `/calyx`: ทีมและ HP ชั่วคราว (`override_mgr.zig`)

| รูปแบบ | ผล |
|---|---|
| `/calyx` | แสดงสถานะ: ทีม override และรายการ HP override |
| `/calyx lineup <id> [id…]` | ทีมในการต่อสู้ 1–4 ตัว ทีมที่เดินในโลกไม่เปลี่ยน (ใช้วิธีเดียวกับ `/funmode`) |
| `/calyx lineup reset` | ยกเลิกทีม override |
| `/calyx modify <wave> <ลำดับ> <HP>` | ตั้ง max HP ของมอนตัวนั้นใน wave นั้น |
| `/calyx off` | ล้างทั้งทีมและ HP override |
| `/calyx on` | ตอบว่าไม่ต้องใช้ (ของเราใช้ config.json เป็นการต่อสู้ตลอดอยู่แล้ว) |

**กฎของ `lineup`:**
- id ต้องมีใน `config.json` หรือเป็น base id 8001/1001 ซึ่งจะแปลงเป็นสาย MC/March ปัจจุบัน
- ห้ามซ้ำ, leader = ช่องแรก
- ถ้าเปิด `/funmode` อยู่ ทีม override ชนะ
- ล้างเองตอน `PlayerLogin`

**กฎของ `modify`:**
- wave และลำดับนับจาก 1 ตาม `config.json battle_config.monster_wave`
- HP อยู่ในช่วง 1..2147483647
- HP ของแต่ละตัวชนะ `/funmode hp`
- ใช้เฉพาะการต่อสู้ที่ใช้ wave จาก `config.json` (ไม่ใช้กับ `/debug` หรือ Battle College)
- ล้างเองเมื่อ `config.json` ถูกโหลดใหม่ ไม่ว่าจะจาก SRTools sync, `/sync` หรือ `/json load`

### `/debug`: เลือกการต่อสู้ครั้งถัดไป (ครั้งเดียว)

| รูปแบบ | ผล |
|---|---|
| `/debug specific <StageID>` | ครั้งถัดไปใช้ `stage_id`, level และ monster wave ของ stage นั้นจาก `resources/StageConfig.json` และไม่ใส่ blessing ของ config.json |
| `/debug monster <id> [id…]` | ครั้งถัดไปใช้ stage/level ของ config.json แต่ใช้ wave เดียวที่มีมอนพวกนี้ (1–5 ตัว) |
| `/debug` | แสดงสิ่งที่ตั้งรอไว้ |
| `/debug off` | ยกเลิก |

- stage ต้องมีอยู่ใน StageConfig.json
- monster id ต้องปรากฏใน wave ของ stage ใดก็ได้ใน StageConfig.json เพราะเราไม่มี MonsterConfig และ id ที่ไม่มีอยู่จริงทำให้จอค้าง
- ตั้งใหม่จะทับของเดิม
- ถูกใช้แล้วล้างทันทีใน `createBattle` ครั้งถัดไป

### `/peak <group>`: เลือกซีซัน AA

- `group` ต้องเป็น id ใน `ChallengePeakGroupConfig` ส่วน `0` = อัตโนมัติ (ตาม stage ที่เลือกใน SRTools หรือซีซันล่าสุด เหมือนทุกวันนี้)
- ถ้า id ผิด ให้ลิสต์ id ที่ใช้ได้
- บันทึกใน `profile.json peak_group` และ `currentPeakGroupId()` จะดูค่านี้ก่อน
- หลังตั้งค่า ส่ง `GetChallengePeakDataScRsp` ทั้งก้อนแบบไม่มีใครขอ และส่ง `ChallengePeakGroupDataUpdateScNotify` ของกลุ่มนั้น (ทำตาม M7H) พร้อมบอกให้ relog ถ้า banner ไม่เปลี่ยน
- ถ้ากำลังเล่น AA อยู่ รอบนั้นยังอยู่ซีซันเดิม

### `/faketime`: ตั้งเวลาเซิร์ฟเวอร์

| รูปแบบ | ผล |
|---|---|
| `/faketime 20260920` หรือ `/faketime 2026-09-20` | ตั้งวันที่ (ปีต้องอยู่ในช่วง 2023–2099) |
| `/faketime off` | กลับไปใช้เวลาจริง |
| `/faketime` | แสดงสถานะ |

- บันทึกใน `profile.json fake_date` (yyyymmdd, 0 = ปิด)
- `utils/clock.zig`: ถ้ามี fake date ให้ใช้ก่อน window เดิม โดย offset = ตอนนี้ − (วันนั้น เวลา **12:00 UTC+8**)
  - คำนวณใหม่ตอนตั้งค่าและทุกครั้งที่ login เวลาจึงเดินต่อจากเที่ยงวันนั้นทุกครั้งที่เข้าเกม
  - ใช้เที่ยงเพราะตาราง MoC/PF/AS เปิดตอน 04:00 UTC+8 ถ้าเริ่มเที่ยงคืนจะยังล็อก
- มีผลกับ heartbeat ทันที และตอบให้ relog เพื่อให้เมนู challenge อ่านวันที่ใหม่ (ไม่เตะผู้เล่นออกแบบ M7H)

### `/hero`: เพศ/สาย MC

| รูปแบบ | ผล |
|---|---|
| `/hero gender 1\|2` | สายเดิม เปลี่ยนเพศ (1 = ชาย = id คี่, 2 = หญิง = id คู่) |
| `/hero type <8001\|8003\|8005\|8007\|8009>` | สายใหม่ เพศเดิม (รับ id คู่ได้ด้วย โดยใช้เพศเดิม) |

- id ปลายทางต้องมีใน `config.json` (config ของผู้ใช้มีครบ 8001–8010) ถ้าไม่มี ให้บอกว่าให้เพิ่มใน SRTools
- ส่ง packet ชุดเดียวกับ `onSetAvatarPath` คือ `AvatarPathChangedNotify` (base 8001), `syncAvatarData`, `SyncLineupNotify` และอัปเดต `AvatarManager.gender`
- ไม่บันทึกข้ามรีสตาร์ท (เหมือนปุ่มเปลี่ยนสายในเกม)
- ตอบว่าถ้าโมเดลยังไม่เปลี่ยนให้ relog

### `/scene`

| รูปแบบ | ผล |
|---|---|
| `/scene cur` | plane, floor, entry และตำแหน่งปาร์ตี้ล่าสุด |
| `/scene group` | group ของฉากปัจจุบันใน `res.json` เรียงตามระยะจากปาร์ตี้ถึง entity ที่ใกล้ที่สุดของ group แสดง 10 อันแรก (group id, จำนวน prop/monster, ระยะ m) |
| `/scene reload` | เข้า entry เดิมใหม่ เกิดที่จุดเกิดของ entry (ใช้ทางเดียวกับ `/tp`) |
| `/scene change <entryId>` | เท่ากับ `/tp <entryId>` |

`scene_mgr.zig` ต้องจำ `plane_id` และ `entry_id` ล่าสุดเพิ่มจาก `party_floor_id` ที่มีอยู่แล้ว

### `/windy`: ส่ง Lua

| รูปแบบ | ผล |
|---|---|
| `/windy` หรือ `/windy list` | ลิสต์ไฟล์ `*.lua` ในโฟลเดอร์ `lua/` (เฉพาะชั้นบนสุด เรียงตามชื่อ มีเลขกำกับ) |
| `/windy <เลข\|ชื่อ>` หรือ `/windy load <…>` | ส่งไฟล์นั้น (ชื่อไม่ต้องใส่ `.lua` ก็ได้) |
| `/windy loaded` | สคริปต์ที่ส่งไปแล้วใน session นี้ |

- ห้ามชื่อที่มี `/`, `\`, `..` หรือ path แบบเต็ม
- ไฟล์ต้องไม่เกิน 64 KB
- ไม่มีโฟลเดอร์ `lua/` = ตอบว่าให้สร้าง
- **การส่ง:** เข้าคิว (สูงสุด 8) แล้ว `PlayerHeartBeatScRsp` ครั้งถัดไปจะส่งสคริปต์ในคิวแทนลายน้ำ ครั้งละ 1 ไฟล์ ใช้ทางเดียวกับลายน้ำซึ่งยืนยันแล้วว่า client รัน ลายน้ำจะกลับมาเองใน heartbeat ถัดไป
- รองรับแค่ Lua ธรรมดาแบบเดียวกับลายน้ำ ไม่รองรับ bundle HoyoToonLua ของ M7H เพราะต้องใช้ mod ฝั่ง client ของเขา

### `/json`: ชุด config

| รูปแบบ | ผล |
|---|---|
| `/json` หรือ `/json list` | ลิสต์ `configs/*.json` พร้อมเลขกำกับ |
| `/json export <ชื่อ>` | copy `config.json` ไปเป็น `configs/<ชื่อ>.json` (ชื่อ `[A-Za-z0-9_-]{1,40}`) ถ้ามีไฟล์อยู่แล้วจะไม่ทับ ให้ใช้ `export <ชื่อ> force` |
| `/json load <เลข\|ชื่อ>` | โหลดชุดนั้น (ขั้นตอนด้านล่าง) |

ขั้นตอนของ `load`:
1. parse ด้วย parser เดียวกับ `config.json` ก่อน ถ้าพังจะไม่แตะอะไร
2. backup `config.json` ไป `config-backups/config-<UTC timestamp>-before-json-load.json`
3. เขียน `config.json` แบบ atomic
4. เรียก `applyConfig` เดิมของ `commands/sync.zig`

ระหว่างต่อสู้ (`on_battle`) จะไม่ยอมโหลด ให้สู้ให้จบก่อน

## ชิ้นที่ 2: โปรไฟล์/โลก

### Phone

- `SelectChatBubble` / `SelectPhoneTheme` / `SelectPhoneCase`:
  - ตรวจว่า id อยู่ใน owned list ของ `data.zig`
  - บันทึกแล้วตอบ `cur_*`
  - id ที่ไม่รู้จักตอบค่าปัจจุบันกลับโดยไม่บันทึก
- `GetPhoneData` ส่งค่าที่บันทึกไว้
- M7H บอกว่า owned list ของ bubble กับ theme อาจสลับกัน ให้ตรวจกับ client จริงก่อน ถ้าสลับจริงค่อยแก้ทีหลัง

### การ์ดผู้เล่น (PlayerBoard)

**Set\* ทั้งหมดบันทึกลง `profile.json`:**
- `SetSignature`: ตัดที่ 256 byte
- `SetHeadIcon`: ต้องอยู่ใน `unlocked_head_icon_list` ที่ `GetPlayerBoardData` ส่ง
- `SetPersonalCard`: ต้องอยู่ใน `unlocked_personal_card_list`
- `SetDisplayAvatar`: สูงสุด 5 ตัว `{avatar_id, pos}` (pos เริ่มที่ 0 แบบ M7H)
- `SetAssistAvatar`: สูงสุด 3 ตัว ตอบ `avatar_id_list`
- `SetIsDisplayAvatarInfo` (2859→2818): echo กลับ

**Getter:**
- `GetPlayerBoardData` ส่งค่าที่บันทึกไว้ (head icon ไม่หายอีกต่อไป)
- ตัวละครที่ไม่มีใน `config.json` แล้วจะถูกกรองออก ถ้าเหลือ 0 ตัวให้ใช้ค่าตายตัวเดิม
- `GetPlayerDetailInfo` เติม nickname, signature, head icon, display/assist avatars, chat bubble, gender, level, world level
- เอา entry ซ้ำที่ใช้ไม่ได้ใน `handlers.zig:162` ออก

### ServerPrefs (`prefs_mgr.zig`)

- `server_prefs.json` = `{"prefs":[{"id":N,"data":"<base64>"}]}` (สูงสุด 256 รายการ รายการละไม่เกิน 64 KB)
- Handler:
  - `GetAllServerPrefsData` (6174→6119): ส่งทั้งหมด
  - `GetServerPrefsData` (6131→6187): ส่งรายการเดียว ถ้าไม่มีให้ส่ง `server_prefs` ที่มีแค่ id
  - `UpdateServerPrefs` (6105→6171): เก็บทับแล้วตอบ `server_prefs_id`
- ถ้า `server_prefs` ไม่มีมาใน request ให้ตอบ retcode 0 โดยไม่บันทึก
- ลบโค้ดใน `services/events.zig` ที่ใช้ชื่อ message ผิดและไม่มีใครเรียก

### ชื่อ / เพศ

- `SetNickname` (4→94):
  - ชื่อยาว 1–32 byte หลัง trim
  - บันทึกแล้วตอบ `{is_modify, set_time}`
  - ตามด้วย `PlayerSyncScNotify{basic_info}` ที่ใช้ค่าชุดเดียวกับตอน login
- `PlayerLoginScRsp.basic_info.nickname` ใช้ชื่อที่บันทึกไว้ (ค่าเริ่มต้น "ReversedRooms")
- ชื่อบอท/ลายน้ำ "MushiSR" ไม่เปลี่ยน
- `SetGender` (22→49): ตอบ retcode 0 และ `cur_avatar_path` = สาย MC ปัจจุบัน โดยไม่บันทึก เพราะเพศมาจาก MC ใน config.json และใช้ `/hero gender` แทน
- `SetPlayerInfo` (66→90): ตอบ retcode 0, `is_modify`, `set_time` และไม่ทำ flow บทนำแบบ M7H

### เมล

- `GetMail` ไม่ส่งเมลที่ลบแล้ว ใส่ `is_read` ตาม set และเอาไอเทมแนบออกถ้ารับไปแล้ว
- `MarkReadMail` (831→887) / `DelMail` (805→871): บันทึก
  - id ที่ไม่รู้จักตอบ `RET_MAIL_MAIL_ID_INVALID` (1702) แบบ M7H
- `TakeMailAttachment`: รายการว่าง = รับทุกฉบับ บันทึก taken + read และตอบ `succ_mail_id_list` โดยไม่ให้ไอเทมจริง

### Pet (`services/pet.zig`)

- **ข้อมูล:** hardcode 5 ตัว `1001..1005` (item 251001..251005) ใน `data.zig` และเพิ่ม 251005 ลง ItemList
- **Handler:**
  - `GetPetData` (7612→7604): ปลดล็อกทั้ง 5 ตัว (`HCAKDJMKDJP`) และตัวปัจจุบัน (`PLKBLNMOOPH`)
  - `SummonPet` (7611→7615): ตั้งตัวปัจจุบัน → ส่ง `PetDataChangeScNotify` (7622) → ตอบ (ค่า enum `LLGIIPALELD` echo จาก request)
  - `RecallPet` (7616→7607): ตั้งเป็น 0
- ไม่ต้องสร้าง scene entity เพราะ summon unit ของ pet เป็นแบบ `IsClient` (client สร้างเอง)
- `BlindBoxGetData` (10052→10039) และ `PetMarbleGetData` (10195→10188) ตอบค่าว่างผ่าน dummy list (ตอนนี้ไม่มีใครตอบตอน login)

### Jukebox (`services/jukebox.zig`)

- **ข้อมูล:** `resources/BackGroundMusic.json` = `[{"id", "group_id"}]` 283 แถว
- `GetJukeboxData`: ทุกเพลงปลดล็อก และเพลงปัจจุบันจาก `profile.json`
- `PlayBackGroundMusic` (3131→3187): ยังไม่รู้ว่า client ส่งรูปแบบไหน จึงตัดสินจาก byte แรกของ payload
  - `0x58` = `FKLMGEFILDI` (tag 11)
  - `0x6A` = `MNCBEDBDDHL` (tag 13)
  - reply รวมที่ decoder ทั้งสองแบบอ่านได้: tag 8 = id และ tag 14 = state echo
  - log hex ครั้งแรกไว้ตรวจกับ client จริง
- `3159→3118` echo id และ `3105→3171` echo การปลดล็อก
- บันทึกเพลงปัจจุบัน

### Battle College (`services/college.zig`)

- **ข้อมูล:** `resources/BattleCollegeConfig.json` = `[{"id", "stage_id"}]` 13 แถว stage ทุกตัวมีใน StageConfig.json อยู่แล้ว
- `StartBattleCollege` ใช้ stage ของห้องนั้น (wave, level, `stage_id`) กับทีมปัจจุบัน (รวม `/calyx lineup`) ไม่ใช้ตัวละครทดลอง และจำ college id ที่กำลังเล่น
- เมื่อชนะใน `onPVEBattleResult`:
  1. ถ้ายังไม่เคยผ่าน ให้เพิ่มลง `college_finished` แล้วบันทึก
  2. ส่ง `SyncBattleCollegeDataChangeScNotify` (5731) **ก่อน** result reply
- `GetBattleCollegeData` (5774→5719) ส่ง `finished_college_id_list` จริง

### สถิติ challenge (`record_mgr.zig`, `challenge.json`)

**หลักสำคัญ (ผู้ใช้เลือก):** ด่าน/ชั้นที่**ยังไม่มีสถิติให้แสดงแบบปลอมว่าผ่านหมดเหมือนเดิม** ส่วนที่มีสถิติแล้วแสดงของจริง จะได้ไม่มีอะไรกลับไปล็อก

**Classic MoC/PF/AS**

ข้อมูล: parse `ChallengeTargetID` และ `ChallengeCountDown` เพิ่มใน `data/challenge_config.zig`

**คำนวณดาวตอนชนะครบทั้ง 2 โหนด** โดยต้องเริ่มที่โหนด 1 (เล่นโหนดเดียวไม่บันทึก):
- กติกา target ใช้ `data/challenge_targets.zig`:
  - MoC: รอบที่เหลือ = `ChallengeCountDown −| รอบรวม` ≥ param, หรือไม่มีตัวละครล้ม (นับจาก `downedAvatars` ที่ Starward ใช้อยู่)
  - PF/AS: คะแนนรวม ≥ param
- ใช้ bit OR ของ mask จริง (ห้ามใช้ `max` ตัวเลขแบบที่ M7H ทำพลาด)
- คำนวณหลังหักรอบของโหนดสุดท้ายแล้ว

**เก็บ** `{id, stars_mask, rounds, score1, score2, buff1, buff2, lineup1[], lineup2[]}`:
- ดาวมากกว่าชนะ
- ดาวเท่ากัน: MoC รอบน้อยกว่าชนะ, PF/AS คะแนนมากกว่าชนะ

**ส่งออก:**
- `ChallengeSettleNotify` / boss phase settle ส่ง star mask จริง
- `GetChallenge`: มีสถิติ = ค่าจริง (`star`, `score_id`, `score_two`), ไม่มี = ค่าปลอมเดิม (7, PF 40000)
- `GetChallengeGroupStatistics`: มีสถิติ = เติม oneof ตามโหมด (default/story/boss) พร้อม lineup, ไม่มี = เหมือนเดิม

**AA (ChallengePeak)**

ข้อมูล: `resources/BattleTargetConfig.json` เฉพาะ id ที่ `normal_target_list` และบอสใช้ (`{id, param}`) แยกจาก `challenge_targets.zig` เพราะ id 3001 มีความหมายต่างกันในสองโหมด

**ตอนจบการต่อสู้:**
- target ที่ทำได้ตัดสินจาก `round_cnt` ≤ param เพราะเราไม่ได้ส่ง target ให้ client รายงาน
- อัศวินแต่ละตัวเก็บ `{level_id, cycles, targets[], team[]}`
- บอสเก็บแยก easy/hard `{level_id, hard, cycles, targets[], buff_id, team[]}`
- ผลใหม่ดีกว่าถ้าได้ target มากกว่า หรือได้เท่ากันแต่รอบน้อยกว่า
- หลัง `ChallengePeakSettleScNotify` ส่ง `ChallengePeakGroupDataUpdateScNotify` ของทั้ง group

**`GetChallengePeakData`:**
- อัศวินที่มีสถิติ: `peaks` จริง (cycles, targets, team)
- ที่ไม่มีสถิติ: ค่าปลอมเดิม
- `obtained_stars` = ผลรวม (มีสถิติ = target ที่ได้ cap 3, ไม่มี = 3)
- บอส: `easy_mode` / `hard_mode` จริงถ้ามีสถิติ ไม่มีก็ใช้ค่าปลอมเดิม (`hard_mode_has_passed=true`)

**`TakeChallengePeakReward`** (8937, ยังไม่มี handler):
- ตอบ `{peak_group_id, peak_reward_group_list = id ที่ขอ แต่ละอันไม่มีไอเทม}` และ retcode 0
- getter รายงาน `taken_star_rewards` 1..12 เหมือนเดิม ปุ่มรับจึงไม่ควรโผล่ handler นี้มีไว้กันค้างเท่านั้น
- `TakeChallengeCumulativeReward` (1747) มี handler อยู่แล้ว ไม่แก้

## การจัดการ error

- handler ใหม่ห้ามทำเซิร์ฟเวอร์ panic:
  - ใช้ `orelse` แทน `.?` กับ field optional ของ request
  - ไฟล์อ่าน/เขียนไม่ได้ให้ log แล้วใช้ค่าในหน่วยความจำต่อ (แบบ `profile.zig` เดิม)
- ทุก id ที่มาจาก client หรือคำสั่งต้องตรวจกับข้อมูลก่อนเก็บ ถ้าไม่ผ่านให้ตอบค่าปัจจุบันโดยไม่บันทึก

## การทดสอบ

1. **Fake client:** ต่อยอด `smoke_record.py` / `starward_test.py` จาก session 3e8d6a2a เทสต์ทุกคำสั่ง (ทั้ง argument ถูกและผิด) และทุก handler ใหม่ รวมทั้ง:
   - บันทึก → รีสตาร์ท gameserver → login ใหม่แล้วค่ายังอยู่
   - ไฟล์เสียกลายเป็น `.bad`
   - `/json load` ไฟล์พังแล้ว config.json ไม่ถูกแตะ
   - `/windy ../x` ถูกปฏิเสธ
   - สถิติ classic/AA: ดีกว่าเท่านั้นถึงทับ, เล่นโหนดเดียวไม่บันทึก, ไม่มีสถิติ = ค่าปลอม
2. **Regression diff:** build เดิม (`git archive HEAD`) เทียบกับ build ใหม่ด้วย `smoke_record.py` + `smoke_diff.py`
   - ต่างได้เฉพาะ packet ที่ตั้งใจเปลี่ยน (GetMail, GetPlayerBoardData, GetPhoneData, GetPetData ฯลฯ) และ field timestamp/seed
   - flow การต่อสู้/challenge ที่ไม่มีสถิติต้องเหมือนเดิมทุก byte
3. **Codex GPT-6 Astra ultra** review diff ก่อน commit
4. **Client จริง** (ผู้ใช้ทำ):
   - login
   - `/calyx lineup` + `modify` แล้วสู้ Calyx
   - `/debug specific`
   - `/peak` เปลี่ยน banner
   - `/faketime` + relog
   - `/hero`
   - `/scene cur`
   - `/windy` สคริปต์ทดสอบ
   - `/json export/load`
   - Phone/การ์ด หลัง relog
   - เปลี่ยนชื่อ
   - เมล อ่าน/ลบ
   - Pet เรียก/เก็บ
   - Jukebox เปิดเพลง (และส่ง hex ใน log มาให้ดู)
   - College ห้องหนึ่ง
   - MoC classic 1 ชั้นแล้วดูดาว
   - AA อัศวิน 1 ตัวแล้วดูสถิติ

## ความเสี่ยงที่รู้อยู่

| ความเสี่ยง | การรับมือ |
|---|---|
| ไม่รู้แน่ว่า client ส่ง Jukebox 3131 รูปแบบไหน | รับทั้งสองแบบ + log hex |
| ค่า enum ของ Pet (`LLGIIPALELD`) และ bool `NHCAOLGBGIF` | echo จาก request แล้วตรวจกับ client จริง |
| `/peak` อาจเปลี่ยน banner ทันทีไม่ได้ | ข้อความบอกให้ relog |
| Battle College ห้องที่เป็น tutorial อาจค้างถ้าไม่มีตัวละครทดลอง | ถ้าค้างจริงให้ตัดห้องนั้นออก (whitelist) |
| สถิติ AA ตัดสิน target จากรอบเท่านั้น (target ประเภทอื่นจะไม่ผ่าน) | ยอมรับในรอบนี้ |
| แก้ `handlers.zig`, `challenge.zig`, `battle_mgr.zig` อาจชนตอน rebase upstream | แก้ให้น้อยที่สุด ใส่ logic ในไฟล์ใหม่ |
