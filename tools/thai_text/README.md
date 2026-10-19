# ภาษาไทยใน Beta 4.7 (ไคลเอนต์ CN)

Beta มีข้อความแค่ อังกฤษ/จีน/ญี่ปุ่น/เกาหลี แต่ตารางภาษาของเกมยังมีแถวภาษาไทยอยู่ (ฟอนต์ `RPG_TH` + ตัวตัดบรรทัดภาษาไทย)
`thai_text.py` สร้าง TextMap ภาษาไทยให้ Beta จาก TextMap ไทยของเกม live แล้วตั้งภาษาข้อความของ Beta เป็นไทย
ภาษาเสียงไม่แตะ (ใช้ตามที่ตั้งไว้ เช่น ญี่ปุ่นจาก hsrlingo)

ข้อความแต่ละแถวได้ภาษาไหน:

- live มีคำแปลไทย และภาษาอังกฤษใน Beta ยังเหมือน live (ข้อความไม่เปลี่ยน) → ไทย
- ภาษาอังกฤษใน Beta ต่างจาก live แค่ตัวพิมพ์เล็กใหญ่ เครื่องหมายวรรคตอน การขึ้นบรรทัด การเพิ่ม/ลบคำเล็กๆ
  (a/an/the/to/is/and/of/'s) หรือคำซ้ำ (เช่น Beta แก้ `when the the` เป็น `when the`) → ไทย
- Beta เหลือแค่ `...` (Beta ตัดเนื้อเรื่องเก่าออกเกือบหมด) แต่ live มีไทย → ไทย (ได้เนื้อเรื่องเก่ากลับมาด้วย)
- ข้อความใหม่ (live ไม่มี) หรือที่ Beta เปลี่ยนความหมาย/ศัพท์ (เช่น `Fusion` → `Joint`) หรือเปลี่ยนแค่ตัวเลข
  เครื่องหมาย `+ - < > = ≤ ≥ ? /` (เช่น `+5` → `-5`) หรือตัวอักษรที่เป็นชื่อ (เช่น `Route A` → `Route`) → อังกฤษ
  (ยังไม่มีคำแปล)

4.6.53: ไทย 95.6% (377,181 จาก 394,721 แถว) อังกฤษ 17,540 แถว (ใหม่ใน 4.7 17,273 + เปลี่ยนความหมาย 267)

ชื่อ Eidolon และชื่อเฉพาะหลายอย่างเป็นอังกฤษในเกม live ภาษาไทยอยู่แล้ว ไม่ใช่บั๊ก

## สิ่งที่ต้องมี

- เกม Beta ไคลเอนต์ CN (ค่าเริ่มต้น `D:\Games\StarRail_4.6.53_CN_ReversedRooms`)
- เกม live ที่เคยโหลดข้อความไทยและอังกฤษแล้ว (ค่าเริ่มต้น `H:\Games\Star Rail Games`)
  ต้องมี `StarRail_Data\Persistent\DesignData\Windows\th` และ `en` ถ้าไม่มี ให้เปิดเกม live ตั้งภาษาข้อความเป็นไทย
  และอังกฤษอย่างละครั้งให้เกมโหลด
- Python 3 ใน PATH (ใช้แค่ standard library)
- เซิร์ฟเวอร์นี้ (dispatch ต้องเป็นตัวที่มี `dispatch/src/design_override.zig`) และอินเทอร์เน็ต (โหลด index จาก CDN)

ถ้าเกมอยู่โฟลเดอร์อื่น ส่ง `--beta` / `--live` (ค่าเริ่มต้นคือ `DEFAULT_BETA` / `DEFAULT_LIVE` บนสุดของ `thai_text.py`)
อย่าแก้ `thai_text.py` เอง เพราะ `Update-PearlSR-4.6.51.bat` จะไม่ยอมอัปเดตถ้ามีไฟล์ใน repo ที่แก้ค้างไว้
ถ้าอยากให้ดับเบิลคลิกแล้วใช้โฟลเดอร์ใหม่เลย ให้แก้บรรทัด `call` ใน `G:\Cluade Code\HRSLOPRail\Thai-Beta.bat`
(อยู่นอก repo) เป็นแบบนี้ เปลี่ยนแค่ชื่อโฟลเดอร์ Beta:

```
call "%~dp0pearl-sr-4.6.51\tools\thai_text\Thai-Beta.bat" --beta "D:\Games\<โฟลเดอร์ Beta>" %*
```

## ใช้งาน

**ปิดเกมก่อนทุกครั้ง** แล้วดับเบิลคลิก `Thai-Beta.bat` (ในโฟลเดอร์นี้ หรือตัวที่โฟลเดอร์ `G:\Cluade Code\HRSLOPRail`
ซึ่งเรียกตัวนี้) จากนั้นเปิด `Start-PearlSR-4.6.51.bat` แล้วเข้าเกม

```
Thai-Beta.bat                                    สร้างและเปิดภาษาไทย (= build)
Thai-Beta.bat restore                            กลับไปภาษาข้อความก่อน build ครั้งแรก (ภาษาเสียงคงตามที่ตั้งอยู่)
Thai-Beta.bat --beta "D:\Games\<โฟลเดอร์ Beta>"   Beta อยู่โฟลเดอร์อื่น (--live ก็ใส่แบบเดียวกัน, ต่อท้ายด้วย restore ได้)
Thai-Beta.bat --help                             ดูตัวเลือกทั้งหมด
```

คำสั่งที่มีตัวเลือกต้องพิมพ์เอง: เปิด cmd ที่โฟลเดอร์นี้ (พิมพ์ `cmd` ในช่อง address ของ Explorer แล้วกด Enter)
ถ้าใช้ PowerShell / Windows Terminal ต้องใส่ `.\` ข้างหน้า เช่น `.\Thai-Beta.bat restore`
หรือเรียกตรงๆ จากโฟลเดอร์นี้ `python thai_text.py [build|restore] [--beta ...] [--live ...]`

### Beta มี hotfix (เวอร์ชันเดิม)

dispatch ไม่ถามหา hotfix ใหม่ของเวอร์ชันที่มีใน `hotfix.json` แล้ว hotfix ใหม่จึงเข้ามาทาง `Update-PearlSR-4.6.51.bat`
(ได้ `hotfix.json` ใหม่จาก upstream)

1. ปิดเซิร์ฟเวอร์แล้วรัน `Update-PearlSR-4.6.51.bat`
2. เปิดเซิร์ฟเวอร์และเกม เกมยังเล่นภาษาไทยได้ด้วยข้อมูลชุดเก่า ถ้า `hotfix.json` ได้โฟลเดอร์ CDN ใหม่
   หน้าต่าง Dispatch จะขึ้นคำเตือน `run Thai-Beta.bat again`
3. ปิดเกม รัน `Thai-Beta.bat` แล้วเข้าเกมใหม่ จะได้ข้อมูล hotfix ใหม่

### Beta เวอร์ชันใหม่ (เช่น 4.6.54 หรือ 4.7 Beta 2)

1. ถ้าจะอัปเดตเกมด้วย ldiff ในโฟลเดอร์เดิม ให้ปิดเกมแล้วรัน `Thai-Beta.bat restore` ก่อน
   (build แก้ไฟล์ใน StreamingAssets ไฟล์ที่ถูกแก้จะ patch ไม่ผ่าน) ถ้าโหลดเกมตัวเต็มลงโฟลเดอร์ใหม่ ข้ามข้อนี้
2. อัปเดตเซิร์ฟเวอร์ให้รองรับเวอร์ชันใหม่
3. เปิดเซิร์ฟเวอร์และเกม Beta หนึ่งรอบ (ยังเป็นอังกฤษ/จีน) ให้ dispatch ดึง hotfix ของเวอร์ชันใหม่ลง `hotfix.json`
   แล้วปิดเกม
4. รัน `Thai-Beta.bat` (โฟลเดอร์ใหม่: `Thai-Beta.bat --beta "D:\Games\<โฟลเดอร์ Beta ใหม่>"`)
5. เข้าเกม

### เกม live อัปเดต (เช่น live ได้ 4.7)

คำแปลไทยทั้งหมดมาจากเกม live พอ live ได้เนื้อหาเดียวกับ Beta ข้อความใหม่ของ Beta ก็จะได้ไทยด้วย

1. อัปเดตเกม live แล้วเปิดเข้าเกมจริง (เซิร์ฟเวอร์ทางการ) ให้โหลด hotfix จนครบ
2. สคริปต์ใช้ทั้งข้อความไทยและอังกฤษของ live (ใช้อังกฤษเทียบว่าข้อความเปลี่ยนไหม) ถ้า `Thai-Beta.bat` ขึ้น
   `the live client has no en TextMap` หรือ `no th TextMap` ให้เปิดเกม live ตั้งภาษาข้อความเป็นภาษานั้นหนึ่งรอบให้โหลด
   แล้วค่อยเปลี่ยนกลับ
3. ปิดเกมทั้งสองตัว แล้วรัน `Thai-Beta.bat` (live ไม่ได้อยู่ที่ `DEFAULT_LIVE`: `Thai-Beta.bat --live "<โฟลเดอร์ live>"`)

ข้อความที่ HoYo แก้ระหว่าง Beta กับตัวจริงจะยังเป็นอังกฤษ (ภาษาอังกฤษของ Beta ไม่ตรงกับ live)
ถ้าย้ายไปเล่น Beta ตัวถัดไป (เช่น 4.8 Beta) ก็ใช้ live 4.7 เป็นต้นทางคำแปลแบบเดียวกัน ทำตามหัวข้อ Beta เวอร์ชันใหม่

### เปลี่ยนภาษาเสียง (hsrlingo)

hsrlingo ไม่มีตัวเลือก `th` และตั้งภาษาข้อความไปด้วยทุกครั้ง ปิดเกม รัน hsrlingo เลือกภาษาเสียงที่ต้องการ
(ภาษาข้อความเลือกอะไรก็ได้) แล้วรัน `Thai-Beta.bat` อีกรอบ ข้อความกลับเป็นไทย เสียงคงตามที่เลือก
(`restore` ยังกลับไปภาษาข้อความก่อน build ครั้งแรก)

### เล่น Beta กับเซิร์ฟเวอร์อื่น

หลัง build เกม Beta ต้องใช้ dispatch ตัวนี้ (มีตัวนี้ตัวเดียวที่ส่ง TextMap ไทยให้)
ถ้าจะเล่นกับเซิร์ฟเวอร์อื่น (เช่น March7thHoney หรือ PearlSR ตัวเก่า) ให้ปิดเกมแล้วรัน `Thai-Beta.bat restore` ก่อน
ไม่งั้นเกมจะขึ้นป๊อปอัปว่างแล้วรีบูตวน กลับมาเล่นกับตัวนี้ค่อยรัน `Thai-Beta.bat` ใหม่

## แก้ปัญหา

log ของเกม: `%USERPROFILE%\AppData\LocalLow\miHoYo\崩坏：星穹铁道\Player.log` (เขียนใหม่ทุกครั้งที่เปิดเกม)

- **ทุกข้อความเป็นอังกฤษ/เกมไม่โหลดไทย**: ยังไม่ได้ build เวอร์ชันนี้ หรือรัน hsrlingo หลัง build
  (hsrlingo ตั้งภาษาข้อความใหม่) ปิดเกมแล้วรัน `Thai-Beta.bat`
- **จอดำ / รีบูตวน / ป๊อปอัปไม่มีข้อความ**: ดูหน้าต่าง Dispatch ก่อน ต้องมีบรรทัด
  `Ex Resource: http://127.0.0.1:21000/design_override/...` และ `Design data: sent ...M_Design_ArchiveV.bytes`
  - `Ex Resource:` เป็น URL ของ CDN (`https://...`): dispatch นี้ไม่มี build ของเวอร์ชันนี้ (ยังไม่ได้ build,
    ลบ `design_override/` หรือย้าย repo) ปิดเกมแล้วรัน `Thai-Beta.bat` ถ้ารันแล้วยังเป็น URL ของ CDN แปลว่า dispatch
    เป็นตัวเก่า: ปิดเซิร์ฟเวอร์ ลบ `zig-out\bin\dispatch.exe` แล้วเปิด `Start-PearlSR-4.6.51.bat` (จะ build ใหม่ให้)
  - ไม่มีบรรทัด `Ex Resource:` ตอนเปิดเกมเลย: เกมต่อ dispatch ตัวอื่นอยู่ (มีเซิร์ฟเวอร์อื่นใช้พอร์ต 21000)
    ปิดตัวนั้น หรือถ้าจะเล่นกับเซิร์ฟเวอร์อื่นจริงๆ รัน `Thai-Beta.bat restore`
  - มีครบ: หา `Textmap` หรือ `DesignData` ใน Player.log ถ้าเจอ
    `SyncLoadAsset fail, path is BakedConfig/ExcelOutput/Textmap..._th...` แปลว่าเกมหา TextMap ไทยไม่เจอ
    ให้ปิดเกมแล้วรัน `Thai-Beta.bat` ใหม่ ถ้ายังไม่หาย รัน `Thai-Beta.bat restore` เพื่อกลับไปเล่นภาษาเดิมก่อน
- **สคริปต์ขึ้น error**: สคริปต์อ่านและตรวจทุกอย่างก่อนเขียนลงเกม (index และตารางภาษาต้องอ่านแล้วเขียนกลับได้ไบต์เดิม
  TextMap ต้องอ่านได้พอดีทั้งตาราง md5 ของไฟล์จาก CDN ต้องตรง) ถ้าไม่ผ่านจะหยุดโดยยังไม่แก้อะไรในเกม
  - `cannot download ...`: ไม่มีอินเทอร์เน็ต หรือโฟลเดอร์ CDN ใน `hotfix.json` ไม่มีแล้ว (อัปเดตเซิร์ฟเวอร์)
  - `no beta client in ...`: `--beta` (หรือ `DEFAULT_BETA`) ไม่ใช่โฟลเดอร์เกม Beta
  - `no design data index in ...`: `--live` ไม่ใช่โฟลเดอร์เกม live หรือเกม live ยังไม่เคยเปิด
  - อย่างอื่น (เช่น `round trip failed`): เวอร์ชันใหม่เปลี่ยนรูปแบบไฟล์ ต้องแก้สคริปต์

## ทำงานยังไง

ทุกครั้งที่เปิด เกมขอ `M_Design_ArchiveV.bytes` จาก `ex_resource_url` แล้วโหลด index (`DesignV_<md5>.bytes`)
ตาม md5 ในบรรทัด `M_DesignV` จากนั้นลบไฟล์ design data ที่ index ไม่ได้อ้างถึง การแก้ไฟล์ในเครื่องเฉยๆ จึงอยู่ไม่ถึงรอบหน้า

1. `build` โหลด index ของ CDN (URL จาก `hotfix.json`) เพิ่มไฟล์ TextMap ไทย 2 ไฟล์ (ไฟล์ใหญ่ lang `th`
   และไฟล์เล็กที่ใช้ตอนเปิดเกม) โดยใช้ hash ตารางเดียวกับเกม live แล้วเขียน index ใหม่ +
   `M_Design_ArchiveV.bytes` / `M_DesignV.bytes` ที่ชี้ไป index ใหม่ + `Design_PatchV_<md5>.bytes` ของ CDN ลง
   `design_override/<version>/<โฟลเดอร์ CDN>/client/Windows/` และ `upstream.txt` ลง `design_override/<version>/<โฟลเดอร์ CDN>/`
   (เขียนเป็นโฟลเดอร์ `.partial` ก่อน ชุดเก่ายังใช้ได้จนชุดใหม่เสร็จ และ `M_DesignV.bytes` เขียนเป็นไฟล์สุดท้าย)
2. ก๊อป index และไฟล์ไทยลง `Persistent/DesignData/Windows` ของ Beta ให้เปิดครั้งแรกไม่ต้องโหลด
3. เพิ่ม TextMap ไทยไฟล์เล็ก (`TextmapMain_th`) ลง index ของ StreamingAssets ด้วย (`DesignV` ใหม่ +
   `M_DesignV` + `M_Design_ArchiveV`) เพราะตอนเปิดเกม ก่อนต่อเซิร์ฟเวอร์ เกมอ่าน index ของ StreamingAssets อย่างเดียว
   ถ้าไม่มีจะ NullReferenceException ใน `TextmapExcelTable._LoadStartupDataImpl` แล้วจอดำ
4. แก้ตารางภาษาตาม region ในไฟล์ config ของ StreamingAssets (ตารางเดียวกับที่ hsrlingo แก้)
   ให้ภาษาข้อความเป็น `th` (ขนาดไฟล์เท่าเดิม) ภาษาเสียงไม่แตะ
5. dispatch (`dispatch/src/design_override.zig`) เห็นว่ามี `design_override/<version>/<โฟลเดอร์>/client/Windows/M_DesignV.bytes`
   ก็ส่ง `ex_resource_url` เป็น `http://127.0.0.1:21000/design_override/<version>/<โฟลเดอร์ CDN>` ให้เกม
   ไฟล์ที่ไม่มีในโฟลเดอร์ redirect ไป CDN ถ้า CDN เปลี่ยนโฟลเดอร์ (hotfix) ยังใช้ชุดเก่าและเตือนให้ build ใหม่

ไฟล์ StreamingAssets เดิมเก็บไว้ที่ `design_override/<version>/boot_backup/` (`added.txt` = ไฟล์ที่ build เพิ่มเข้าไป)
`restore` คืน index และภาษาข้อความเดิม (ภาษาเสียงคงตามที่ตั้งอยู่ตอนนั้น) ลบไฟล์ที่เพิ่ม ลบ `design_override/<version>/`
และลบ `M_DesignV.bytes` ใน Persistent (รอบหน้าเกมโหลด index ของ CDN ใหม่)
ถ้า backup หาย (ลบ `design_override/` หรือย้าย repo) build และ restore คำนวณไฟล์เดิมจากไฟล์ของเกมเองได้
(index เดิมได้ไบต์ต่อไบต์ ภาษาข้อความกลับเป็นอังกฤษ)

`design_override/` อยู่ใน `.git/info/exclude` (ไฟล์ไทยประมาณ 100 MB)

รูปแบบไฟล์ (M_DesignV, DesignV, TextMap, ตารางภาษา) เขียนไว้ใน docstring บนสุดของ `thai_text.py`
