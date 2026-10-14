# -*- coding: utf-8 -*-
"""最小外科补录：把 100F 天台 9 个新 AssetID 写进 ledger_split_baseline.json。

口径见 skill `shellstorm2-asset-ledger-row-authoring`：
- 只新增/更新本次涉及的行指纹，其余资产的 v 保持原值（历史投放/篡改仍可被抓）
- 重算 column_digests（9 域 union × CONTENT_COLUMNS）与 category_counts（报告忠实）
- ⛔ 绝不跑 split_asset_ledger.py --baseline-only（会把 409+ 行基线清空）
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
sys.path.insert(0, str(ROOT / "scripts"))

from ledger_registry import LedgerIndex  # noqa: E402
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CONTENT_COLUMNS,
    _row_digest,
    _text,
    col_digest,
    read_source_rows,
)

BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
BACKUP = BASELINE.with_suffix(".json.bak_20261014_rooftop_components")
NEW_IDS = [
    "ENV-ROOFTOP-FLOWERBED-BROKEN", "ENV-ROOFTOP-SANDBAG-BARRIER",
    "ENV-ROOFTOP-RUBBLE-PILE-A", "ENV-ROOFTOP-RUBBLE-PILE-B", "ENV-ROOFTOP-RUBBLE-PILE-C",
    "ENV-ROOFTOP-DEBRIS-PILE-LARGE",
    "ENV-ROOFTOP-BROKEN-CRATE-A", "ENV-ROOFTOP-BROKEN-CRATE-B", "ENV-ROOFTOP-BROKEN-CRATE-C",
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    from openpyxl import load_workbook

    index = LedgerIndex.load(ROOT)
    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    before_count = bl["asset_count"]
    before_cols = dict(bl["column_digests"])
    before_cats = dict(bl["category_counts"])

    changed: dict[str, str] = {}
    all_rows: list[tuple[str, tuple]] = []
    cats: Counter[str] = Counter()

    for domain in index.domains:
        wb = load_workbook(domain.path)
        ws = wb[ASSET_SHEET]
        rows = read_source_rows(ws)
        for _row, values in rows:
            asset_id = _text(values[0])
            category = _text(values[2])
            cats[category] += 1
            all_rows.append((asset_id, values))
            if asset_id in NEW_IDS:
                digest = _row_digest(values)
                recorded = bl["assets"].get(asset_id)
                if recorded is not None and recorded["v"] != digest:
                    raise SystemExit(f"意外：{asset_id} 已在基线且指纹不同 {recorded['v']} -> {digest}")
                if recorded is None:
                    bl["assets"][asset_id] = {
                        "v": digest, "c": category, "d": domain.key,
                    }
                    changed[asset_id] = digest
                if category != "场景":
                    raise SystemExit(f"{asset_id} 大类不是「场景」：{category}")

    missing = [x for x in NEW_IDS if x not in bl["assets"]]
    if missing:
        raise SystemExit(f"未在账本中读到：{missing}")

    bl["asset_count"] = len(bl["assets"])
    bl["column_digests"] = {
        str(c): col_digest(all_rows, c) for c in CONTENT_COLUMNS
    }
    bl["category_counts"] = dict(sorted(cats.items()))

    print(f"asset_count {before_count} -> {bl['asset_count']}（+{bl['asset_count']-before_count}）")
    print(f"新增指纹 {len(changed)}：")
    for k, v in changed.items():
        print(f"  {k}  {v[:16]}…  {bl['assets'][k]['c']}/{bl['assets'][k]['d']}")
    drift_cols = [c for c in before_cols if before_cols[c] != bl["column_digests"].get(c)]
    print(f"列摘要变化 {len(drift_cols)}/{len(before_cols)} 列：{drift_cols}")
    print(f"分类计数变化：{[(k, before_cats.get(k), v) for k, v in bl['category_counts'].items() if before_cats.get(k) != v]}")

    if not args.apply:
        print("[dry-run] 未写盘")
        return 0
    if not BACKUP.exists():
        shutil.copy2(BASELINE, BACKUP)
        print(f"备份 → {BACKUP.name}")
    BASELINE.write_text(
        json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )
    print(f"[applied] 已写入 {BASELINE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
