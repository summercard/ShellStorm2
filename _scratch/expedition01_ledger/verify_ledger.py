"""Read-back verification of the expedition01 ledger registration."""
from __future__ import annotations

from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
ASSET_ID = "ENV-EXPEDITION-L01-BOSS-ARENA"

wb = load_workbook(LEDGER)

main = wb["资产主表"]
print("[资产主表] max_row =", main.max_row)
print("header:", [main.cell(row=5, column=c).value for c in range(1, 26)])
for c in range(1, 26):
    print(f"  col{c:>2} {str(main.cell(row=5, column=c).value):<14} | {main.cell(row=241, column=c).value}")

print("\n  row240 (prev) col18/19:", main.cell(row=240, column=18).value, "|", main.cell(row=240, column=19).value)
print("  row241 (new)  col18/19:", main.cell(row=241, column=18).value, "|", main.cell(row=241, column=19).value)
print("  row6  (first) col19   :", main.cell(row=6, column=19).value)

# style parity check: font/border/fill/alignment vs previous row
a = main.cell(row=240, column=1)
b = main.cell(row=241, column=1)
print("\n  style parity row240 vs row241 (col1):",
      a.font.b, b.font.b, "|", a.alignment.horizontal, b.alignment.horizontal,
      "|", a.fill.fgColor.rgb, b.fill.fgColor.rgb)

prefab = wb["3D-场景通用"]
print("\n[3D-场景通用] max_row =", prefab.max_row)
for c in range(1, 17):
    print(f"  col{c:>2} | {prefab.cell(row=147, column=c).value}")

cl = wb["域变更日志"]
print("\n[域变更日志] max_row =", cl.max_row)
for c in range(1, 8):
    print(f"  col{c} | {str(cl.cell(row=18, column=c).value)[:120]}")

ov = wb["总览"]
print("\n[总览] $240 remaining:", [
    cell.coordinate for row in ov.iter_rows() for cell in row
    if isinstance(cell.value, str) and "$240" in cell.value
])
print("[总览] $241 refs:", [
    cell.coordinate for row in ov.iter_rows() for cell in row
    if isinstance(cell.value, str) and "$241" in cell.value
])

# duplicate scan again
ids = {}
for r in range(6, main.max_row + 1):
    v = main.cell(row=r, column=1).value
    if v:
        ids.setdefault(v, []).append(r)
print("\nduplicate AssetIDs:", {k: v for k, v in ids.items() if len(v) > 1} or "none")
print("total id rows:", len(ids))
