"""Refresh only Boss002's approved v031 ledger baseline after a rollback."""
import json
import sys
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path("I:/工作项目/shellstrom2/ShellStorm2")
ASSET_ID = "ENM-BOSS-MONITOR002-3D"
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "tools/asset_pipeline")]

from ledger_registry import LedgerIndex
from split_asset_ledger import CONTENT_COLUMNS, _row_digest, col_digest, read_source_rows, sheet_digest

index = LedgerIndex.load(ROOT)
baseline_path = ROOT / "assets/registry/ledger_split_baseline.json"
baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
enemy_book = load_workbook(index.path_for_category("敌人"))

for _, row in read_source_rows(enemy_book["资产主表"]):
    if row[0] == ASSET_ID:
        baseline["assets"][ASSET_ID]["v"] = _row_digest(row)
        break
else:
    raise RuntimeError("Boss002 asset row was not found")

for sheet_name in ["3D-敌人", "敌人动画与状态"]:
    baseline["sheet_digests"][sheet_name] = sheet_digest(enemy_book[sheet_name])

all_rows = []
for domain in index.domains:
    workbook = load_workbook(domain.path)
    all_rows.extend(read_source_rows(workbook["资产主表"]))
all_rows.sort(key=lambda pair: pair[1][0])
baseline["column_digests"] = {str(column): col_digest(all_rows, column) for column in CONTENT_COLUMNS}
baseline.setdefault("targeted_updates", []).append({
    "date": "2026-10-08",
    "asset_id": ASSET_ID,
    "version": "v031",
    "scope": "User-requested restore of the verified v031 Boss002 release.",
})
baseline_path.write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("REFRESHED_V031_BOSS_BASELINE")
