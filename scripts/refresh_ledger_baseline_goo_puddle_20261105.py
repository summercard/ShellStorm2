#!/usr/bin/env python3
"""把 2026-11-05「黏液血泊贴图」改动的两行刷新进无损基线（补录用）。

背景
----
FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D` 与共用身体的 FX01-17 `VFX-DEATH-BLAST-3D`
在 2026-11-05 把 C 段地面液体由纯色 BoxMesh 换成 PlaneMesh + 贴图面片。账本行
（规格 / 关键词 / 更新时间 / 备注）随之改动，`verify_ledger_split.py` 按设计报
`row_content_mutated` + `moved_sheet_mutated`。

处理口径沿用既有先例（`refresh_ledger_baseline_teleport_vfx.py`）：

  1. 备份基线 → `ledger_split_baseline.json.bak_before_goo_puddle_20261105`
  2. **只刷新本批两行的内容指纹**，其余 1435 行逐位不动
  3. `asset_count` / `category_counts` / `column_digests` 从当前账本重算
  4. `sheet_digests` 里只更新 `3D-特效` 一页
  5. **没有新增资产行** —— 贴图按 FX01-16 吼叫图标先例登记在 FX01-19 行内

Run: python scripts/refresh_ledger_baseline_goo_puddle_20261105.py
"""

from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))

from openpyxl import load_workbook  # noqa: E402

from ledger_registry import LedgerIndex  # noqa: E402
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CONTENT_COLUMNS,
    _row_digest,
    col_digest,
    read_source_rows,
    sheet_digest,
)

BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "bak_before_goo_puddle_20261105"

# 本批不新增任何资产行。
EXPECTED_NEW: set[str] = set()

# 只允许这两行的内容指纹变化 —— 它们是本批唯一被改写的行。
REFRESH_ALLOWED = {
    "VFX-ZOMBIE-GOO-DEATH-3D",
    "VFX-DEATH-BLAST-3D",
}

# 本批确实修改过的分页。
TOUCHED_SHEETS = {"3D-特效"}


def main() -> int:
    backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(BASELINE, backup)
    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    index = LedgerIndex.load(ROOT)

    rows: list[tuple[str, tuple]] = []
    collected: list[tuple[int, tuple]] = []
    for domain in index.domains:
        wb = load_workbook(domain.path, data_only=False)
        if ASSET_SHEET not in wb.sheetnames:
            continue
        for row_index, values in read_source_rows(wb[ASSET_SHEET]):
            rows.append((domain.key, values))
            collected.append((row_index, values))

    assets = bl["assets"]
    added: list[str] = []
    refreshed: list[str] = []
    for domain_key, values in rows:
        aid = values[0]
        if not aid:
            continue
        digest = _row_digest(values)
        entry = {"v": digest, "c": values[2], "d": domain_key}
        if aid not in assets:
            added.append(aid)
            assets[aid] = entry
        elif assets[aid]["v"] != digest and aid in REFRESH_ALLOWED:
            refreshed.append(aid)
            assets[aid] = entry

    unexpected = sorted(set(added) - EXPECTED_NEW)
    uncovered = sorted(REFRESH_ALLOWED - set(refreshed))
    if unexpected or uncovered:
        print(json.dumps({
            "error": "补录/刷新集合与本批声明不一致",
            "unexpected": unexpected,
            "uncovered": uncovered,
        }, ensure_ascii=False, indent=2))
        return 1

    bl["asset_count"] = len(assets)
    cats: dict[str, int] = {}
    for entry in assets.values():
        cats[entry["c"]] = cats.get(entry["c"], 0) + 1
    bl["category_counts"] = dict(sorted(cats.items()))

    for column in CONTENT_COLUMNS:
        bl["column_digests"][str(column)] = col_digest(collected, column)

    for domain in index.domains:
        if not TOUCHED_SHEETS & set(domain.sheet_scope):
            continue
        wb = load_workbook(domain.path, data_only=False)
        for sheet in domain.sheet_scope:
            if sheet in TOUCHED_SHEETS and sheet in wb.sheetnames:
                bl["sheet_digests"][sheet] = sheet_digest(wb[sheet])

    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({
        "added": sorted(added),
        "refreshed": refreshed,
        "asset_count": bl["asset_count"],
        "touched_sheets": sorted(TOUCHED_SHEETS),
        "backup": str(backup.relative_to(ROOT)),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
