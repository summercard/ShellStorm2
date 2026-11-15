#!/usr/bin/env python3
"""修正 room_08 贩卖机登记备注里的视觉来源说明（主题 → 锚点）。

2026-11-15 同一批内的自我修正：第一版把 `merchant_visual_scene` 写进了**共用**主题
`env_iron_frontier`，会连带改掉远征02 / 99F / 塔楼 flow 的商店外观，已回退。
视觉改为由锚点 `service_station_config.visual_scene` 声明。

因此《资产主表》Y242 的备注里那句「由铁边疆主题 `merchant_visual_scene` 声明」
必须改成实际做法，否则账本记的是没做的事。

只改这一行、这一格，并刷新该行指纹与第 25 列指纹。

Run: python scripts/fix_expedition01_room08_vending_note.py
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
from split_asset_ledger import ASSET_SHEET, _row_digest, col_digest, read_source_rows  # noqa: E402

BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "before_room08_vending_note_fix_20261115"

ASSET_ID = "ENV-EXPEDITION-L01-L-CORRIDOR"
ASSET_ROW = 242
NOTE_COLUMN = 25

OLD = "（由铁边疆主题 `merchant_visual_scene` 声明）"
NEW = "（由锚点 `visual_scene` 声明，**不写进共用主题**：env_iron_frontier 还供远征02/99F/塔楼 flow 使用，且每张 flow 都有 1 间 SHOP→MERCHANT 房）"


def main() -> int:
    index = LedgerIndex.load(ROOT)
    domain = next(d for d in index.domains if ASSET_ID.startswith(tuple(d.id_prefixes)))

    xlsx_backup = domain.path.with_suffix(domain.path.suffix + "." + TAG)
    if not xlsx_backup.exists():
        shutil.copy2(domain.path, xlsx_backup)
    baseline_backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not baseline_backup.exists():
        shutil.copy2(BASELINE, baseline_backup)

    wb = load_workbook(domain.path, data_only=False)
    sheet = wb[ASSET_SHEET]
    if str(sheet.cell(row=ASSET_ROW, column=1).value or "") != ASSET_ID:
        print(json.dumps({"error": "行号漂移"}, ensure_ascii=False))
        return 1
    current = str(sheet.cell(row=ASSET_ROW, column=NOTE_COLUMN).value or "")
    if OLD not in current:
        print(json.dumps({"error": "找不到待替换文本，可能已修"}, ensure_ascii=False))
        return 1
    sheet.cell(row=ASSET_ROW, column=NOTE_COLUMN).value = current.replace(OLD, NEW)
    wb.save(domain.path)

    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    collected: list[tuple[int, tuple]] = []
    mine: dict | None = None
    drift: list[str] = []
    for d in index.domains:
        book = load_workbook(d.path, data_only=False)
        if ASSET_SHEET not in book.sheetnames:
            continue
        for row_index, values in read_source_rows(book[ASSET_SHEET]):
            collected.append((row_index, values))
            aid = values[0]
            if not aid:
                continue
            digest = _row_digest(values)
            if aid == ASSET_ID:
                mine = {"v": digest, "c": values[2], "d": d.key}
            elif aid in bl["assets"] and bl["assets"][aid]["v"] != digest:
                drift.append(aid)
    if mine is None:
        print(json.dumps({"error": "基线里找不到本行"}, ensure_ascii=False))
        return 1
    bl["assets"][ASSET_ID] = mine
    bl["column_digests"]["25"] = col_digest(collected, 25)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()
    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    print(json.dumps({
        "asset_row": ASSET_ROW,
        "note_updated": True,
        "preexisting_drift_not_absorbed": sorted(drift),
        "backups": [str(xlsx_backup.relative_to(ROOT)), str(baseline_backup.relative_to(ROOT))],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
