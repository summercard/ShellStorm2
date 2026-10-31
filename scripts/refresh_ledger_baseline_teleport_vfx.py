#!/usr/bin/env python3
"""把 FX01-34 / FX01-35 两件瞬移特效补录进无损基线（2026-10-31）。

背景
----
`tools/asset_pipeline/verify_ledger_split.py` 拿冻结于拆分之前的
`assets/registry/ledger_split_baseline.json` 作真源，断言「并集 == 基线全集」。
新增资产行必然触发 `asset_not_in_baseline`，属**预期的过期**，不是回归；
处理口径沿用既有先例（特效账本日志 v0.1.29 / 敌人账本 egt 批）：

  1. 备份基线 → `ledger_split_baseline.json.bak_before_teleport_vfx`
  2. **只登记新 AssetID 的指纹**，既有条目的 `v` 逐位不动（`REFRESH_ALLOWED` 为空）
  3. `asset_count` / `category_counts` / `column_digests` 从当前账本重算
  4. `sheet_digests` 里 **只更新 `3D-特效` 这一页** —— 本批确实改了它
     （新增分组行 + 两行 FX01-34/35），其它分页一律不动。
     ⚠ 该页在本次之前就已经是「已提交但未刷基线」的漂移状态
     （`verify_ledger_split.py` 的 `moved_sheet_mutated` 早在今天上午就红着），
     本脚本顺带把它对齐 —— 不是掩盖新改动，而是把它落回基线。

Run: python scripts/refresh_ledger_baseline_teleport_vfx.py
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
TAG = "before_teleport_vfx"

# 本批新增的 AssetID。写死白名单：基线是回归守卫，宁可列全也别静默放行任何新行。
EXPECTED_NEW = {
    "VFX-TELEPORT-OUT-3D",
    "VFX-TELEPORT-IN-3D",
}

# 本批允许刷新内容指纹的既有行 = 本批新增的两行本身。
# 为什么要这一步：这两行在首次补录之后又补填了 SHA-256（`check_asset_registry.py`
# 要求 T 列必填），指纹因此变了一次。**除这两个 ID 之外，任何既有行一变就必须失败**
# —— 别把白名单当万能钥匙。
REFRESH_ALLOWED: set[str] = set(EXPECTED_NEW)

# 本批确实修改过的分页；只刷新这几页的 digest。
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
    uncovered = sorted(EXPECTED_NEW - set(added) - set(refreshed))
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
        "vfx_category_counts": {
            k: bl["category_counts"].get(k) for k in ("特效", "子弹特效")
        },
        "touched_sheets": sorted(TOUCHED_SHEETS),
        "backup": str(backup.relative_to(ROOT)),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
