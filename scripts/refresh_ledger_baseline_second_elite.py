"""刷新账本拆分的逐列指纹（本次新增第二只精英 `ENM-ELITE-ARMS-TAKER-3D` 带来的行数 +1）。

为什么必须单独有一个：`register_second_elite_ledger.py` 只负责往《资产主表》补行、
扩公式区间，**不重算 `ledger_split_baseline.json`**。基线不刷的后果不是账本错，
而是 `verify_ledger_split.py` 报 `extra_assets: [新 ID]` + 整片列指纹漂移 ——
看起来像"账本被改坏了"，实际只是基线停在旧行数。

口径与 `refresh_ledger_baseline_npc_polish.py` 完全一致（同一组函数、同一顺序）：
按 `ledger_index.json` 的域顺序读资产主表，用 `split_asset_ledger` 的列常量算 digest；
已有 ID 只刷新指纹，新 ID 追加。

⚠ 它会**顺带刷新 `captured_at`**。旧值 `2026-11-02T17:51:12` 与 1433 行那次扩容不匹配，
长期误导"基线没动过"；本次一并纠正。

用法：
    python scripts/refresh_ledger_baseline_second_elite.py [--dry-run]
"""

from __future__ import annotations

import argparse
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
    sheet_digest,
)

BASELINE = ROOT / "assets" / "registry" / "ledger_split_baseline.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="只打印将要发生的变化，不落盘")
    args = parser.parse_args()

    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    index = LedgerIndex.load(ROOT)
    rows: list[tuple[str, tuple]] = []
    collected: list[tuple[int, tuple]] = []
    domain_books = {}
    for domain in index.domains:
        wb = load_workbook(domain.path, data_only=False)
        domain_books[domain.key] = (domain, wb)
        if ASSET_SHEET not in wb.sheetnames:
            continue
        for row_index, values in read_source_rows(wb[ASSET_SHEET]):
            rows.append((domain.key, values))
            collected.append((row_index, values))

    assets = bl["assets"]
    before_count = bl.get("asset_count")
    before_captured = bl.get("captured_at")
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

    # 分页指纹：`register_second_elite_ledger.py` 会往《3D-敌人》写使用位置、
    # 往《敌人动画与状态》写映射行，两页都会变。不刷这里 ⇒ verify 报
    # `moved_sheet_mutated`。**逐个打印旧→新**，让提交记录可审计哪几页被接受。
    sheets_touched: dict[str, dict[str, str]] = {}
    for domain_key, (domain, wb) in domain_books.items():
        for sheet in domain.sheet_scope:
            if sheet not in wb.sheetnames:
                continue
            actual = sheet_digest(wb[sheet])
            previous = bl["sheet_digests"].get(sheet)
            if previous != actual:
                sheets_touched[sheet] = {"from": previous or "", "to": actual}
                bl["sheet_digests"][sheet] = actual

    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    report = {
        "added": added,
        "refreshed": refreshed,
        "asset_count": f"{before_count} -> {bl['asset_count']}",
        "captured_at": f"{before_captured} -> {bl['captured_at']}",
        "sheets_touched": sheets_touched,
        "dry_run": args.dry_run,
    }
    if not args.dry_run:
        BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
