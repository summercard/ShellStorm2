"""只读：定位《资产主表》里 ENV-TOWER-WALL-DOOR-5M 所在行，并打印表头与整行内容。

用途：写台账补丁前先看清列语义与当前值，避免按错列改错格。
不修改任何文件。
"""

import hashlib
import io
import re
import sys
import zipfile
from pathlib import Path

LEDGER = Path(sys.argv[1] if len(sys.argv) > 1 else (
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_场景账本_v001.xlsx"
))
ASSET_ID = sys.argv[2] if len(sys.argv) > 2 else "ENV-TOWER-WALL-DOOR-5M"


def shared_strings(zf):
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    raw = zf.read("xl/sharedStrings.xml").decode("utf-8")
    items = re.findall(r"<si>(.*?)</si>", raw, re.S)
    return ["".join(re.findall(r"<t[^>]*>(.*?)</t>", item, re.S)) for item in items]


def rows_of(zf, sheet="xl/worksheets/sheet3.xml"):
    sheet_xml = zf.read(sheet).decode("utf-8")
    shared = shared_strings(zf)
    dimension = re.search(r'<dimension ref="([^"]+)"', sheet_xml)
    out = {}
    for match in re.finditer(r'<row r="(\d+)"[^>]*>(.*?)</row>', sheet_xml, re.S):
        index = int(match.group(1))
        cells = {}
        for cell in re.finditer(r'<c r="([A-Z]+)\d+"([^>]*)>(.*?)</c>', match.group(2), re.S):
            col, attrs, body = cell.group(1), cell.group(2), cell.group(3)
            value = re.search(r"<v>(.*?)</v>", body, re.S)
            text = value.group(1) if value else ""
            if 't="s"' in attrs and text.isdigit():
                text = shared[int(text)]
            elif not value:
                inline = re.search(r"<t[^>]*>(.*?)</t>", body, re.S)
                text = inline.group(1) if inline else ""
            cells[col] = text
        out[index] = cells
    return out, dimension.group(1) if dimension else None


zf = zipfile.ZipFile(LEDGER)
rows, dimension = rows_of(zf)
print("ledger      %s" % LEDGER.name)
print("sheet       xl/worksheets/sheet3.xml   dimension=%s   rows=%d" % (dimension, len(rows)))

target = None
for index, cells in sorted(rows.items()):
    if cells.get("A", "").strip() == ASSET_ID:
        target = index
        break
if target is None:
    print("!! 找不到 %s" % ASSET_ID)
    # 退一步：按包含匹配，帮助定位
    for index, cells in sorted(rows.items()):
        if ASSET_ID in str(cells.get("A", "")):
            print("   near-miss row %d A=%r" % (index, cells.get("A")))
    sys.exit(1)

header = rows.get(1, {})
print("\n=== 表头（第 1 行） ===")
for col in sorted(header.keys(), key=lambda c: (len(c), c)):
    print("  %-4s %s" % (col, header[col]))

print("\n=== 目标行 %d ===" % target)
for col in sorted(rows[target].keys(), key=lambda c: (len(c), c)):
    value = rows[target][col]
    if len(value) > 260:
        value = value[:260] + " …(共 %d 字)" % len(rows[target][col])
    print("  %-4s %s" % (col, value))

print("\n=== 磁盘上 GLB 的 sha256（用于核 T 列） ===")
glb = Path(
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_descent_3d"
    r"\components\env_tower_wall_door_5m_top3d.glb"
)
digest = hashlib.sha256(glb.read_bytes()).hexdigest()
print("  bytes  %d" % glb.stat().st_size)
print("  sha256 %s" % digest)
for col in ("T", "U", "V", "W"):
    value = rows[target].get(col, "")
    if value:
        print("  行内 %s 列 = %s   match=%s" % (
            col, value[:80], "YES" if value.strip().lower() == digest else "no"
        ))
