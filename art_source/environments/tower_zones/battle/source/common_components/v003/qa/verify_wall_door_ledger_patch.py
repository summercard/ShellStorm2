# -*- coding: utf-8 -*-
"""校验台账补登结果：只改了 sheet10.xml，新增 r94/r95/r96 内容正确，其余条目逐字节未变。"""

import hashlib
import re
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
BACKUP = LEDGER + ".bak_wall_door_5m"
SHEET = "xl/worksheets/sheet10.xml"

failures = []

with zipfile.ZipFile(LEDGER) as new_zip, zipfile.ZipFile(BACKUP) as old_zip:
    new_names = new_zip.namelist()
    old_names = old_zip.namelist()
    if new_names != old_names:
        failures.append("zip 条目列表变化：%s" % set(new_names) ^ set(old_names))
    changed = []
    for name in old_names:
        old_hash = hashlib.sha256(old_zip.read(name)).hexdigest()
        new_hash = hashlib.sha256(new_zip.read(name)).hexdigest()
        if old_hash != new_hash:
            changed.append(name)
    raw = new_zip.read(SHEET).decode("utf-8")

if changed != [SHEET]:
    failures.append("被改动的条目不止 sheet10.xml：%s" % changed)
print("changed members:", changed)

with zipfile.ZipFile(LEDGER) as z:
    if z.testzip() is not None:
        failures.append("zip 完整性校验失败")

rows = [int(m.group(1)) for m in re.finditer(r'<x:row r="(\d+)"', raw)]
print("row max:", max(rows), "| 94/95/96 present:", all(r in rows for r in (94, 95, 96)))

expected = {
    94: [
        "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
        "战局通用标准墙 5×0.30×11.9m",
        "wall_standard_5m_root_top3d_v003.tscn",
        "wall_standard_5m_visual_top3d_v003.glb",
        "5.0×0.30×11.9m",
    ],
    95: [
        "ENV-BATTLE-COMMON-WALL-DOOR-5M",
        "战局通用门墙 5×0.30×11.9m（门洞 2.2×2.5）",
        "wall_door_5m_root_top3d_v003.tscn",
        "wall_door_5m_visual_top3d_v003.glb",
        "2.2×2.5",
    ],
    96: [
        "ENV-BATTLE-COMMON-DOOR-5M",
        "战局通用门扇 2.2×0.18×2.5m",
        "door_5m_root_top3d_v003.tscn",
        "door_5m_visual_top3d_v003.glb",
        "2.2×0.18×2.5m",
    ],
}

for row_number, needles in expected.items():
    match = re.search(r'<x:row r="%d"[^>]*>(.*?)</x:row>' % row_number, raw, re.S)
    if not match:
        failures.append("缺少行 %d" % row_number)
        continue
    body = match.group(1)
    cells = re.findall(r'<x:c r="([A-Z]+)%d"[^>]*>(?:<x:v>(.*?)</x:v>)?</x:c>' % row_number, body, re.S)
    letters = [c[0] for c in cells]
    if letters != list("ABCDEFGHIJKLMNOP"):
        failures.append("行 %d 列不完整：%s" % (row_number, letters))
    for needle in needles:
        if needle not in body:
            failures.append("行 %d 缺内容：%s" % (row_number, needle))
    print("\n=== row %d ===" % row_number)
    for letter, value in cells:
        print("  %-2s %s" % (letter, (value or "")[:150]))

# 老行未被破坏
for row_number, needle in ((92, "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01"), (93, "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02")):
    match = re.search(r'<x:row r="%d"[^>]*>(.*?)</x:row>' % row_number, raw, re.S)
    if not match or needle not in match.group(1):
        failures.append("原有行 %d 内容被破坏" % row_number)

# 结构区块仍在
for tag in ("</x:sheetData>", "<x:mergeCells>", "<x:dataValidations"):
    if tag not in raw:
        failures.append("sheet10.xml 丢失结构块：%s" % tag)

if rows != sorted(rows):
    failures.append("行号顺序被破坏")

print()
if failures:
    for failure in failures:
        print("[FAIL]", failure)
    raise SystemExit(1)
print("LEDGER_PATCH_OK: 台账仅新增 r94/r95/r96，其余条目逐字节不变")
