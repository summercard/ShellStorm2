"""把「大世界 · 地下街区 v001」补录进无损基线 ledger_split_baseline.json。

只做最小外科编辑（不动其它资产的 v 指纹）：
  1. 备份 ledger_split_baseline.json → .bak_before_ugstreet
  2. 读当前分账本全部行，把新 AssetID 写入 assets
  3. asset_count / category_counts / column_digests 从当前账本重算
  4. sheet_digests 保持不动（本轮未改任何 3D-* 分页）

Run：python scripts/refresh_ledger_baseline_ugstreet.py
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
)

BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "before_ugstreet"
REFRESH_ALLOWED = {"ENV-OPENWORLD-UNDERGROUND-STREET"}


def main() -> None:
    backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(BASELINE, backup)
    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    index = LedgerIndex.load(ROOT)

    rows: list[dict] = []
    collected: list[tuple[int, tuple]] = []
    for domain in index.domains:
        wb = load_workbook(domain.path, data_only=False)
        if ASSET_SHEET not in wb.sheetnames:
            continue
        for row_index, values in read_source_rows(wb[ASSET_SHEET]):
            rows.append({"values": values, "domain": domain.key})
            collected.append((row_index, values))

    assets = bl["assets"]
    added, refreshed = [], []
    for row in rows:
        aid = row["values"][0]
        if not aid:
            continue
        digest = _row_digest(row["values"])
        entry = {"v": digest, "c": row["values"][2], "d": row["domain"]}
        if aid not in assets:
            added.append(aid)
            assets[aid] = entry
        elif assets[aid]["v"] != digest and aid in REFRESH_ALLOWED:
            refreshed.append(aid)
            assets[aid] = entry

    bl["asset_count"] = len(assets)
    cats: dict[str, int] = {}
    for entry in assets.values():
        cats[entry["c"]] = cats.get(entry["c"], 0) + 1
    bl["category_counts"] = dict(sorted(cats.items()))

    for column in CONTENT_COLUMNS:
        bl["column_digests"][str(column)] = col_digest(collected, column)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({
        "added": added,
        "refreshed": refreshed,
        "asset_count": bl["asset_count"],
        "category_counts": bl["category_counts"],
        "backup": str(backup.relative_to(ROOT)),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
