"""刷新账本拆分基线的逐列指纹（只用于本次 NPC 登记带来的公式区间 +1 行）。

为什么单独写一个：`register_base_npc_ledger.py` 的 `refresh_baseline()` 会校验
"本次新增集合必须恰好是 NEW_ID"，重跑时该行已存在 → 直接 SystemExit。
这里只保留"重算指纹"这一步，不做新增校验。

做法与工具脚本保持同一口径：按 `ledger_index.json` 的域顺序读资产主表，
用 `split_asset_ledger` 的列常量算 digest；`assets` 里已存在的 ID 不动，
只补新行、刷新 `column_digests` / `asset_count` / `category_counts`。
"""

from __future__ import annotations

import json
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
)

BASELINE = ROOT / "assets" / "registry" / "ledger_split_baseline.json"


def main() -> int:
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
    refreshed: list[str] = []
    added: list[str] = []
    for domain_key, values in rows:
        asset_id = values[0]
        if not asset_id:
            continue
        digest = _row_digest(values)
        if asset_id not in assets:
            added.append(asset_id)
            assets[asset_id] = {"v": digest, "c": values[2], "d": domain_key}
        elif assets[asset_id]["v"] != digest:
            assets[asset_id]["v"] = digest
            refreshed.append(asset_id)

    bl["asset_count"] = len(assets)
    cats: dict[str, int] = {}
    for entry in assets.values():
        cats[entry["c"]] = cats.get(entry["c"], 0) + 1
    bl["category_counts"] = dict(sorted(cats.items()))
    for column in CONTENT_COLUMNS:
        bl["column_digests"][str(column)] = col_digest(collected, column)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {"added": added, "refreshed": refreshed, "asset_count": bl["asset_count"]},
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
