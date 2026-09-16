# -*- coding: utf-8 -*-
"""探针2：查 r280 内容/公式、r92 的完整样式，以及 sheet10 是否含公式。"""
import re
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET = "xl/worksheets/sheet10.xml"

with zipfile.ZipFile(LEDGER) as z:
    raw = z.read(SHEET).decode("utf-8")

print("has <x:f> (formula):", "<x:f>" in raw)

print("\n=== r280 raw ===")
m = re.search(r'<x:row r="280".*?</x:row>', raw, re.S)
print(m.group(0) if m else "<none>")

print("\n=== r93 raw (地砖登记录样式基准) ===")
m = re.search(r'<x:row r="93".*?</x:row>', raw, re.S)
if m:
    txt = m.group(0)
    print("length:", len(txt))
    print(txt[:900])

print("\n=== all cell styles ===")
styles = sorted(set(int(s) for s in re.findall(r'<x:c r="[A-Z]+\d+" s="(\d+)"', raw)))
print(styles)

print("\n=== row-level styles ===")
rowstyles = re.findall(r'<x:row r="(\d+)"[^>]*?(?:\s(?:ht|s|customHeight)="[^"]*")*[^>]*>', raw)
print("sample rows:", rowstyles[:5])
print("\n=== r92/r93 row tag (raw prefix) ===")
for rn in (90, 91, 92, 93):
    mm = re.search(r'<x:row r="%d"[^>]*>' % rn, raw)
    print(" ", mm.group(0) if mm else "<none>")

print("\n=== sheetData start / dims ===")
print(raw[:600])
print("\n... tail 400 ...")
print(raw[-400:])
