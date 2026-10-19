# minatoSR
#### Honkai: Star Rail server emulator (4.7 beta, client 4.6.51) written in Zig: a PearlSR fork with features added by haltinggoalies (shown in game as **MushiSR**)

## เกี่ยวกับ repo นี้

Repo นี้ fork มาจาก [HonkaiSlopRail/pearl-sr](https://git.xeondev.com/HonkaiSlopRail/pearl-sr) (ผู้พัฒนาหลัก HuLiNap)
ต่อจาก commit `005d2c1` "Fix typo in README" ของต้นฉบับ (2026-10-16, hotfix 4.6.53 CN)

- ฟีเจอร์ในหัวข้อ **ฟีเจอร์ที่ repo นี้เพิ่มเข้ามา** ทำเพิ่มใน repo นี้ทั้งหมด ไม่มีในต้นฉบับ
- ฟีเจอร์ในหัวข้อ **ฟีเจอร์เดิมของ PearlSR** เป็นของต้นฉบับ
- Branch `Main` รองรับ client 4.6.51 (4.7 Beta 1) + hotfix 4.6.53 CN พร้อมฟีเจอร์ทั้งหมดด้านล่าง

## ฟีเจอร์ที่ repo นี้เพิ่มเข้ามา

### 1. MoC / PF / AS (classic)

- เซิร์ฟเวอร์พาจาก node 1 ไป node 2 ให้เองด้วยทีมที่ 2 ไม่ต้องใช้ `/node` แล้ว รองรับ single-node ของเกม และ Restart
  ส่งทีมว่างหรือ ID ผิดจะได้ retcode กลับแทนที่เซิร์ฟเวอร์จะ crash
- เริ่มแต่ละ node ที่จุด Anchor1 จริงของเกม ครบ 82 คู่ map/group (`gameserver/src/data/challenge_anchors.zig`)
  แก้ปัญหาใน AS ที่ตัวละครสายประชิดเดินไปไม่ถึงบอส
- ดาวคิดจากผลจริง (รอบที่เหลือ ตัวละครที่ล้ม คะแนน) ตาม target ของเกม (`gameserver/src/data/challenge_targets.zig`)
  และเก็บรอบที่ดีที่สุดของแต่ละชั้นไว้ใน `challenge.json`
- AS Dominance of Oblivion ชั้น 4 node 1 กลับมาใช้ arena ของตัวเอง

### 2. Starward (Challenge Tierce)

- เล่นทีละ node ได้ครบ ส่งทีมทั้ง 3 node, ไป node ถัดไปได้แม้เริ่มแบบ single-node, ตอบ Restart และ Confirm settle
- Starward ของ MoC ใช้ 45 รอบร่วมกันทั้ง 3 node ตาม `ChallengeMazeTierceConfig` (classic MoC ยังเป็น 30 ต่อ node)
- เก็บรอบที่ดีที่สุด ทีม และบัฟของแต่ละชั้นใน `tierce.json` (`gameserver/src/manager/tierce_mgr.zig`)
- แก้จุดเกิดของ party ที่เคยอยู่ห่างมอนสเตอร์ 20 เมตร

### 3. Anomaly Arbitration (Challenge Peak)

- ทั้ง 40 node ใช้ arena, maze group และ NPC ของ season ตัวเอง (`resources/ChallengePeakConfig.json`) รวม season 10 และ 11
- แก้ node ที่ใส่ monster id แทน NPC id จนจอโหลดค้าง (101, 203, 204, 903, 1103) และ node 501 แสดง Ranger ถูกตัว
- มีหน้าผลแพ้ชนะ, ReStart สู้ node เดิม, เก็บสถิติ knight/boss ใน `challenge.json`, ปุ่มรับรางวัลตอบแล้ว (ยังไม่ให้ไอเทม)
- เลือก season ได้จาก SRTools หรือคำสั่ง `/peak`
- แก้ lobby ของ AA ที่ค้างตอนโหลด

### 4. SRTools "Connect PS" sync

- dispatch รับ sync จาก [srtools.neonteam.dev](https://srtools.neonteam.dev) แล้วแปลงเป็น `config.json` (`dispatch/src/srtools.zig`)
  เขียนแบบ atomic และเก็บไฟล์เดิมไว้ใน `config-backups/` (ไฟล์ก่อน sync ครั้งแรก + 20 ไฟล์ล่าสุด)
- gameserver ใช้ `config.json` ใหม่เองทันที (ถ้าอยู่ใน battle หรือ challenge จะรอให้จบก่อน) คำสั่ง `/sync` ใช้ทางเดียวกัน
- `config.json` ที่เสียจะแจ้งเตือนแทนการ crash

### 5. ทีม

- ทีม preset 50 ทีม เก็บใน `lineups.json` (`gameserver/src/manager/preset_mgr.zig`) สลับทีม ตั้งชื่อ ติด favourite และเลือก leader ได้
- หน้าต่าง Recommended Lineup ในเกมอ่านทีมจาก `recommend_teams.json` (`gameserver/src/manager/recommend_mgr.zig`)
  แก้ไฟล์แล้วมีผลทันทีไม่ต้องรีสตาร์ท ครอบคลุม AA season 4-11 และ Starward ทั้ง 16 ด่าน
  ข้อมูลสร้างด้วย `tools/recommend_teams/` (ดู README ในโฟลเดอร์นั้น)

### 6. คำสั่งแชทใหม่ (พิมพ์หา MushiSR ในเกม)

| คำสั่ง | ทำอะไร |
|---|---|
| `/calyx on` / `/calyx off` | Calyx และมอนสเตอร์บนแมพใช้ battle จาก `config.json` (on, ค่าเริ่มต้น) หรือใช้ด่านจริงของเกม (off) |
| `/calyx lineup <avatar id...>` / `/calyx modify <wave> <monster> <hp>` / `/calyx reset` | ตั้งทีมสำหรับ Calyx และ overworld, ตั้ง HP มอนสเตอร์, ล้างค่า |
| `/debug specific <stage id>` / `/debug monster <id...>` / `/debug off` | เลือก battle ถัดไป (ใช้ครั้งเดียว) |
| `/peak <season>` | เลือก season ของ AA (`0` = อัตโนมัติ) |
| `/faketime <YYYYMMDD>` / `/faketime off` | ตั้งวันที่ของเซิร์ฟเวอร์ สำหรับ challenge ที่ขึ้น Locked |
| `/hero gender <1\|2>` / `/hero type <8001..8009>` | สลับเพศและ path ของ Trailblazer |
| `/scene cur` / `group` / `reload` / `change <entry id>` | ดูตำแหน่ง group ที่ใกล้ที่สุด และเปลี่ยนฉาก |
| `/windy` / `/windy <ชื่อหรือเลข>` / `/windy loaded` | ส่ง Lua script จากโฟลเดอร์ `lua/` เข้าเกม |
| `/json` / `/json export <name>` / `/json load <ชื่อหรือเลข>` | เก็บและสลับชุด `config.json` ในโฟลเดอร์ `configs/` |

ชื่อคำสั่งไม่สนตัวพิมพ์เล็กใหญ่ และคำสั่งที่ error จะไม่ตัดการเชื่อมต่อผู้เล่นอีกแล้ว โค้ดอยู่ที่ `gameserver/src/commands/` (1 คำสั่งต่อ 1 ไฟล์)

### 7. Calyx และมอนสเตอร์บนแมพใช้ด่านจริง (`/calyx off`)

- Calyx, Cavern of Corrosion, Echo of War และ Stagnant Shadow สุ่มด่านของ cocoon ตาม world level ที่เลือก
- มอนสเตอร์บนแมพสู้ด่าน PlaneEvent ของตัวเองที่ world level 6
- ปุ่ม "Challenge Again" หลัง Stagnant Shadow ใช้ได้แล้ว
- ข้อมูล: `resources/CocoonConfig.json`, `resources/FarmElementConfig.json`, `resources/PlaneEvent.json`

### 8. โปรไฟล์และโลกที่จำข้ามการรีสตาร์ท

เก็บใน `profile.json` (`gameserver/src/manager/profile_store.zig`) ยกเว้น ServerPrefs ที่อยู่ใน `server_prefs.json`

- ชื่อผู้เล่น (เปลี่ยนชื่อในเกมได้)
- การ์ดผู้เล่น: signature, head icon, personal card, ตัวละครที่โชว์และ support
- Phone: chat bubble, theme, case
- Mail: สถานะอ่านแล้ว ลบแล้ว รับของแล้ว
- Pet: 5 ตัวหลัก + 17 ตัวจาก blind box, summon และ recall ได้
- Jukebox: 276 เพลงของ client 4.6.51 และจำเพลงล่าสุด
- Battle College: 13 ห้องใช้ด่านจริง และจำห้องที่ผ่านแล้ว
- ชุดของ Trailblazer และตำแหน่งล่าสุดบนแมพ (login แล้วเกิดที่เดิม)
- ชุดของ Pom-Pom (แก้ Express และ Party Train โหลดค้าง)
- ServerPrefs (ค่าตั้งของเกมที่ client ฝากไว้ฝั่งเซิร์ฟเวอร์)

### 9. ภาษาไทยใน 4.7 Beta

- `tools/thai_text/` สร้าง TextMap ภาษาไทยจากเกม live (ราว 95.6% ของข้อความใน 4.6.53 ส่วนที่เหลือเป็นข้อความใหม่จึงยังเป็นอังกฤษ)
- dispatch เสิร์ฟไฟล์ให้ client ผ่านโฟลเดอร์ `design_override/` (`dispatch/src/design_override.zig`)
- วิธีใช้และวิธีอัปเดตเมื่อเกมมี hotfix ดูที่ `tools/thai_text/README.md`

### 10. แก้บั๊กอื่นๆ

- Ex Eidolon ส่งให้เฉพาะตัวละครที่มี Ex Eidolon ของตัวเอง (หน้า Eidolon ไม่ว่างอีก)
- ตอบ tutorial unlock ให้ครบ (แก้ guide dialog เสียและหน้า Currency Wars ที่ปิดเอง)
- หน้า Pet ใน inventory และหน้า Jukebox ไม่ crash แล้ว
- ข้อความตอบกลับในแชทแสดงผลได้ อ่านข้อความแบบ protobuf แทนการอ่านจาก offset ตายตัว
- เวลาเซิร์ฟเวอร์ปลอมได้ (`gameserver/src/utils/clock.zig`) ใช้กับ `/faketime`
- เปลี่ยนชื่อในเกมเป็น MushiSR (watermark สีรุ้ง ชื่อบอทแชท เมลต้อนรับ)

### 11. Test

- `tests/fakeclient/` คือ client 4.6.51 ปลอมที่ยิง packet ใส่ gameserver ชั่วคราว รันบนพอร์ต 23391 จึงไม่ชนกับเซิร์ฟเวอร์ที่เล่นอยู่
- รัน test ทั้งหมด (Windows, build ก่อน): `zig build` แล้ว `python tests/run_all.py`
- Unit test: `cd gameserver` แล้ว `zig build test`
- Regression: `tests/regression/smoke_record.py` อัด packet ของทุก flow และ `smoke_diff.py` เทียบผลระหว่างสอง build

## ไฟล์ที่เซิร์ฟเวอร์เขียนตอนรัน

ไฟล์เหล่านี้เป็นข้อมูลของผู้เล่นแต่ละคน **ไม่ควร commit** เข้า repo

| ไฟล์ | เก็บอะไร |
|---|---|
| `profile.json` | ชื่อ การ์ด phone mail pet เพลง Battle College ชุด ตำแหน่ง season AA วันที่ปลอม |
| `challenge.json` | สถิติ MoC/PF/AS classic และ AA |
| `tierce.json` | สถิติ Starward |
| `lineups.json` | ทีม preset 50 ทีม |
| `server_prefs.json` | ServerPrefs |
| `freesr-data.json` | ข้อมูลดิบที่ SRTools sync มาครั้งล่าสุด |
| `config-backups/`, `configs/`, `lua/`, `design_override/` | backup ของ config, ชุด config ที่เก็บไว้, Lua script, ไฟล์ภาษาไทย |
| `*.json.bad` | ไฟล์ที่อ่านไม่ได้ ระบบย้ายไว้แล้วเริ่มใหม่ด้วยค่าเริ่มต้น |

`.gitignore` ที่ root ครอบคลุมไฟล์เหล่านี้แล้ว (รวม `zig-out/` และ `.zig-cache/`)

## โค้ดที่เพิ่มเข้ามา (สำหรับ dev)

| ที่อยู่ | หน้าที่ |
|---|---|
| `gameserver/src/commands/` | คำสั่งแชทใหม่ทั้งหมด |
| `gameserver/src/manager/profile_store.zig` | อ่าน/เขียน `profile.json` |
| `gameserver/src/manager/record_mgr.zig`, `tierce_mgr.zig` | สถิติ challenge, AA และ Starward |
| `gameserver/src/manager/preset_mgr.zig`, `recommend_mgr.zig` | ทีม preset และทีมแนะนำ |
| `gameserver/src/manager/override_mgr.zig` | สถานะชั่วคราวของ `/calyx` และ `/debug` |
| `gameserver/src/manager/prefs_mgr.zig` | ServerPrefs |
| `gameserver/src/services/pet.zig`, `jukebox.zig`, `college.zig` | handler ของ Pet, Jukebox, Battle College |
| `gameserver/src/data/challenge_anchors.zig`, `challenge_targets.zig` | จุดเกิดและเงื่อนไขดาวของ challenge |
| `dispatch/src/srtools.zig`, `design_override.zig` | SRTools sync และการเสิร์ฟภาษาไทย |
| `docs/superpowers/` | design spec และ implementation plan ของชุดคำสั่งแชทและโปรไฟล์ (ภาษาไทย) |

## งานที่ยังไม่ได้ทำ (ทำต่อได้)

- Currency Wars
- Simulated Universe / Divergent Universe
- ระบบคลังไอเทมจริง: เมล รางวัล challenge และ Battle College ยังไม่ให้ไอเทม
- คำสั่ง `/spawn`, `/anno`, `/language`, `/debug customP` และ `/scene prop|remove|unlockall`
- `/json` ที่รับไฟล์รูปแบบ freesr โดยตรง (ตอนนี้ใช้ SRTools sync แทน)
- จำค่า `/calyx lineup` และ `/hero` ข้ามการรีสตาร์ท
- ตัวละครทดลองของ Battle College และโหมดยากของ AA แยกตามกลุ่ม
- ฟีเจอร์ส่วนใหญ่ test ด้วย fake client แล้ว แต่ควรลองกับ client จริงซ้ำทุกครั้งที่แก้

## แหล่งข้อมูลที่อ้างอิง

March7thHoney (Mar7thLover), CapySR, ppSR, DimbreathBot/TurnBasedGameData, Prydwen และ game8

## Requirements
- [Zig 0.14.1 x64](https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip)

## Running

### From source

Windows:
```
git clone https://github.com/haltinggoalies/minatoSR
cd minatoSR
zig build run-dispatch
zig build run-gameserver
```

### Setup launcher.exe

Copy `launcher.exe` and `hkrpg.dll` from launcher folder inside pearl-sr and paste them inside your client folder.
Then open your `launcher.exe` with administrator.

### Using Pre-built Binaries
Navigate to the [Releases](https://git.xeondev.com/HonkaiSlopRail/pearl-sr/releases)
page of the original PearlSR and download the latest release for your platform.
These binaries do not include the features this repo added; build from source for those.

## Connecting
Get 4.5.5X client: [Gofile](https://gofile.io/d/vtV5JfkO)

Get 4.6.5X client: [Gofile](https://gofile.io/d/cZx9oACJ)

## ฟีเจอร์เดิมของ PearlSR
- Login and player spawn
- Test battle via calyx
- MoC/PF/AS simulator with custom stage sellection
- Anomaly Arbitration (Challenge Peak)
- Starward Mode (Challenge Tierce)
- Gacha simulator 
- Support command for Sillyism

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss
what you would like to change, and why.

## Bug Reports

If you find a bug, please open an issue with as much detail as possible. If you
can, please include steps to reproduce the bug.

Bad issues such as "This doesn't work" will be closed immediately, be _sure_ to
provide exact detailed steps to reproduce your bug. If it's hard to reproduce, try
to explain it and write a reproducer as best as you can.
