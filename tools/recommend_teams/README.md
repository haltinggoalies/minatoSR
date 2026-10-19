# ทีมที่แนะนำ (Recommended Lineup) สำหรับ Beta 4.7

เซิร์ฟเวอร์ Beta 4.7 (PearlSR) อ่านทีมจาก `recommend_teams.json` ที่ root ของ repo (โฟลเดอร์เดียวกับ `config.json`)
ไฟล์นี้ใช้ schema เดียวกับ `Config/Custom/RecommendTeams.json` ของเซิร์ฟเวอร์ 4.6 ทุกอย่าง ก๊อปไปใช้สลับกันได้

| ประเภท | เลขที่ client ส่ง | `format` | 1 รายการคือ | เพดาน |
|---|---|---|---|---|
| `CHALLENGE_PEAK_MOB` | season ของ AA (`ChallengePeakGroupConfig` ID) | `team_list` | ทีมอัศวิน 1/2/3 | 300 |
| `CHALLENGE_PEAK_BOSS` | season ของ AA | `avatars_buff` | ทีมบอส + บัฟบอส | 100 |
| `IGDNEOELFKC` (Starward) | ด่านใน `ChallengeMazeTierceConfig` | `team_list_buff` | ทีม Node 1/2/3 | 300 |

- Trailblazer เขียนเป็น ID ผู้หญิง (เลขคู่ 8002–8010) เซิร์ฟเวอร์สลับตามเพศผู้เล่นให้เอง
- ID ตัวละครต้องมีใน `resources/AvatarConfig.json` ของ 4.7

## ไฟล์ในโฟลเดอร์นี้

- `fetch_prydwen.py` ดึงข้อมูล Prydwen ลง `cache/` (AA season 4–9, หน้า PF/AS) และพิมพ์ phase ที่ Prydwen มี
- `make_recommend.py` สร้าง `frag_aa_4_10.json` จาก `cache/` แล้วรวม `frag_*.json` ทุกไฟล์เป็น `recommend_teams.json`
- `prydwen_characters.json` ชื่อตัวละครของ Prydwen → avatar ID (เพิ่ม `aha` = 1511, `pearl` = 1503 และตัว 4★ เก่า
  `arlan`, `dan-heng`, `hook`, `sushang`, `yanqing` แล้ว)
- `make_aa11.py` สร้าง `frag_aa11.json` (AA season 11 ของ 4.7 beta ทีม theorycraft เขียนไว้ในสคริปต์ ไม่ต้องดึงข้อมูล)
- `make_starward.py` สร้าง `frag_starward.json` (Starward ทั้ง 16 ด่าน) ข้อมูล Prydwen เก็บใน `cache/starward/`
- `frag_*.json` ข้อมูลแต่ละส่วน schema เดียวกับไฟล์จริง commit ไว้ทุกไฟล์ (มีทีมที่เขียนเองและ game8 ที่สร้างจาก cache ไม่ได้)
  - `frag_aa_4_10.json` = AA season 4–10
  - `frag_aa11.json` = AA season 11
  - `frag_starward.json` = Starward
- `pipeline/` สำเนาสคริปต์ของ 4.6 ที่รันซ้ำไว้ตรวจผล (ไม่ต้องใช้ตอนอัปเดต, อยู่ใน `.gitignore`)

## อัปเดตข้อมูล

```
cd tools/recommend_teams
python fetch_prydwen.py           # ดึงข้อมูลใหม่
python make_recommend.py          # สร้าง frag_aa_4_10.json ใหม่ แล้วรวมเป็น ../../recommend_teams.json
python make_recommend.py merge    # รวมอย่างเดียว (หลังแก้หรือเพิ่ม frag_*.json)
python make_starward.py           # สร้าง frag_starward.json ใหม่ (แล้วรัน merge)
python make_aa11.py               # สร้าง frag_aa11.json ใหม่ (แล้วรัน merge)
```

gameserver อ่านไฟล์ใหม่เองเมื่อขนาดหรือเวลาแก้ไขของไฟล์เปลี่ยน ไม่ต้อง restart

ตอนรวม สคริปต์จะ:
- หยุดถ้า: ทีมไม่ใช่ 1–4 คนหรือมีตัวซ้ำในทีม, ID ไม่มีใน AvatarConfig, `format` ไม่ตรงประเภท (ตารางข้างบน),
  season/ด่านไม่มีใน `resources/`, บัฟบอสไม่อยู่ใน `BuffList` ของ season นั้น (`ChallengePeakBossConfig`),
  มี `buff_id` ในทีมอัศวินหรือ Starward ของ MoC, ทีม Starward ของ AS/PF ไม่มีบัฟของ Node นั้น
  (`starward_buffs.json`), สอง frag ให้ประเภท + ID เดียวกัน
- เตือนแต่เก็บไว้: ทีมไม่ครบ 4 คน, ตัวละครเดียวกันอยู่สองทีมในชุดเดียว (ชุดของ game8 season 10 ทั้ง 16 ชุดมีตัวซ้ำข้ามอัศวิน 1 ตัว)
- ตัดทิ้ง: รายการที่ซ้ำกันทุกอย่าง (ไม่นับ `note`), รายการเกินเพดาน
- เปลี่ยน Trailblazer ชายเป็นหญิง เรียงประเภทตามตัวอักษรและเลข ID ตามตัวเลข (เก็บเป็น string)

**บัฟ Starward ของ AS และ PF:** ถ้าทีมแนะนำของ AS/PF มี `buff_id = 0` ปุ่ม "Replace" ในเกมจะไม่ใส่ทีมให้
(MoC ไม่มีบัฟ จึงใช้ 0 ได้) เกมส่งบัฟมา Node ละ 1 ตัวตอนเริ่มด่าน (gameserver พิมพ์ `STARWARD LINEUP ...` ทุก Node)
- AS: แต่ละ Node มีรายการของตัวเอง (Node 1–3 = `BuffList1`–`BuffList3` ของ `ChallengeBossGroupExtra`)
  log 4.6 ของ 30205: `3111092` / `3111058` / `3111079`
- PF: ทุก Node เลือกจากรายการเดียวกัน (`BuffList` ของ `ChallengeStoryGroupExtra`) เลือกซ้ำกันได้
  log 4.7 ของ 20285: `3031354` / `3031366` / `3031354`
- `make_starward.py` ใส่บัฟตัวแรกของแต่ละ Node ให้ทุกทีม (ไม่มีแหล่งไหนบอกว่าผู้เล่นเลือกบัฟไหน)
- ID มาจาก `ExcelOutput/` ของ DimbreathBot/TurnBasedGameData (AS 3018–3021, PF 2022–2027) ส่วน AS 3022/3023
  และ PF 2028 ของ 4.7 beta จับคู่ด้วยชื่อบัฟจาก nanoka.cc 4.6.51 บัฟใหม่ที่ยังไม่รู้ ID เป็น 0 ในตาราง (ไม่ได้ใช้)

## ที่มาข้อมูล AA (ตรวจ 2026-10-01)

- season 4–9: API ของ Prydwen (`/api/star-rail/analytics?phaseId=N`) ผลที่ดึงใหม่ตรงกับไฟล์ของ 4.6 ทุกทีม
- season 10: game8 (หน้า 553079, 553120, 553103, 553128 อัปเดตล่าสุด 2026-09-28 ทีมเดียวกับที่ใช้ใน 4.6)
  เก็บเฉพาะชุดที่มีตัวซ้ำข้ามอัศวินแค่ 1 ตัว (16 จาก 48 ชุด) ชุดที่เหลือมีทีมเดียวกันหรือ DPS ตัวเดียวกันในสองอัศวิน
  ใช้จริงไม่ได้ (ไฟล์ของ 4.6 ยังมีครบ 48 ชุด)
  Prydwen ยังไม่มีข้อมูล 4.6 (phase ID หลัง 63 ตอบ 404) บัฟบอส 3033082/3033083 ยังมีใน `ChallengePeakBossConfig` 1004 ของ 4.7
- season 1–3: ไม่มีแหล่งข้อมูล ตั้งใจไม่ใส่ (analytics ของ Prydwen เริ่มที่ phase 4 = AA 4.0.1 = season 4,
  ไฟล์ของ 4.6 ก็ไม่มี) ถ้าเปิด season 1–3 หน้าต่างจะขึ้น "กำลังรวบรวมข้อมูล"
- season 11 (ใหม่ใน 4.7 beta): ยังไม่มีแหล่งข้อมูลสาธารณะ ใช้ทีม theorycraft จาก `make_aa11.py` (อัศวิน 40 ชุด บอส 19 ทีม)

## ที่มาข้อมูล Starward (ตรวจ 2026-10-01)

- Prydwen: 5213, 5313, 20245, 20255, 20265, 30185, 30195, 30205 (300 รายการ, 20265/30205 ตรงกับ 4.6)
- game8 หน้า 438117: 5413 (100 รายการ แยก Node 1/2/3 ตามแท็บ First Half / Second Half / Starward)
- theorycraft (30 รายการ): 5513, 5613, 20275, 20285, 30215, 30225, 30235

## ต้องทำเมื่อมีข้อมูลใหม่

- เมื่อ Prydwen มี AA season 10 (น่าจะราว 7 ต.ค.) `fetch_prydwen.py` จะพิมพ์ phase ใหม่ ให้เพิ่ม `10: <phaseId>` ใน
  `AA_SEASON_PHASES` (ใช้ phase สุดท้ายของ season) แล้วรันใหม่ ทีม game8 จะไม่ถูกใช้อีก
- เมื่อมีข้อมูล AA season 11 (หลัง 4.7 ออก) ให้เปลี่ยนไปใช้ Prydwen/game8 แบบ season 10 แล้วลบ `frag_aa11.json` / `make_aa11.py`
- เมื่อ Prydwen มีรอบ Starward ที่เป็น theorycraft ให้ย้ายด่านจาก `THEORY` ไป `PRYDWEN_STAGES` ใน `make_starward.py`
- ถ้า Prydwen ใช้ชื่อตัวละครที่ไม่มีใน `prydwen_characters.json` ทีมนั้นจะถูกข้ามเงียบ ๆ ให้เพิ่มชื่อ → ID จาก AvatarConfig
