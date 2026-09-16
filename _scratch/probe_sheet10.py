# -*- coding: utf-8 -*-
"""探针：读 3D-场景通用（sheet10.xml）最后若干行，确认 r92/r93 是否已登记。"""
import re
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET = "xl/worksheets/sheet10.xml"

with zipfile.ZipFile(LEDGER) as z:
    raw = z.read(SHEET).decode("utf-8")

rows = [int(m.group(1)) for m in re.finditer(r'<x:row r="(\d+)"', raw)]
rows_sorted = sorted(rows)
print("row count:", len(rows), "min:", rows_sorted[0], "max:", rows_sorted[-1])
print("has 91:", 91 in rows, "| has 92:", 92 in rows, "| has 93:", 93 in rows)
print("last 8 rows:", rows_sorted[-8:])

print("\n=== last 5 rows detail ===")
for rn in rows_sorted[-5:]:
    m = re.search(r'<x:row r="%d"[^>]*>(.*?)</x:row>' % rn, raw, re.S)
    if not m:
        print("  r%d: <no match>" % rn)
        continue
    body = m.group(1)
    cells = re.findall(r'<x:c r="([A-Z]+)%d"[^>]*>(?:<x:v>(.*?)</x:v>)?</x:c>' % rn, body, re.S)
    print("  r%d %s" % (rn, {c[0]: (c[1] or "")[:64] for c in cells if c[0] in ("A", "B", "K", "O")}))

# 表头行（若第1行）
print("\n=== row 1 (header) ===")
m = re.search(r'<x:row r="1"[^>]*>(.*?)</x:row>', raw, re.S)
if m:
    cells = re.findall(r'<x:c r="([A-Z]+)1"[^>]*>(?:<x:v>(.*?)</x:v>)?</x:c>', m.group(1), re.S)
    for letter, value in cells:
        print("  %-2s %s" % (letter, (value or "")[:60]))
else:
    print("  no row 1")

print("\nstructural:", "mergeCells=" + str("<x:mergeCells>" in raw),
      "dataValidations=" + str("<x:dataValidations" in raw),
      "sheetData_end=" + str("</x:sheetData>" in raw))
styles = sorted(set(re.findall(r'<x:c r="[A-Z]+\d+" s="(\d+)"', raw)))
print("cell styles used:", styles[:16], "... total", len(styles))
