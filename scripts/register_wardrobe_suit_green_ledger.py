#!/usr/bin/env python3
"""把衣柜新增的 `suit_green`（苔绿作业服）登记进角色账本（2026-11-02 补记）。

背景
----
98/99F NPC 的绿皮改成**直接取衣柜变体**，因此 `PlayerAvatar3D.CUSTOMIZATION_OPTIONS["body"]`
新增了 `suit_green`。它是**玩法可见的换装项**（玩家能在基地衣柜里选到），属于既有
`CHR-PLY-CAPSULE01-3D-BUNNY01` 资产的能力扩展，不是新资产 ⇒ **不新增行**，只：

  1. 在既有行 13（bunny01 根变体）的「状态/动画」列补 `wardrobe body variants 6`；
  2. 备注列追一句来源；
  3. 《域变更日志》追加 v0.1.28；
  4. 补录无损基线里**这一行**的指纹（行内容变了，`v` 必须同步，否则
     `verify_ledger_split.py` 会报 `asset_hash_mismatch`）。

⚠️ 基线只刷新这一行的 `v`。其它资产的 `v` 一律不动 —— 那是回归守卫，
白名单外任何指纹漂移都必须失败。

Run: python scripts/register_wardrobe_suit_green_ledger.py
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

LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_角色账本_v001.xlsx"
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "before_suit_green"
TARGET_ID = "CHR-PLY-CAPSULE01-3D-BUNNY01"

STATE_APPEND = " / wardrobe body variants 6 (incl. suit_green 苔绿作业服)"
NOTE_APPEND = " v0.1.28：身体槽新增 suit_green（苔绿作业服，Color(0.16,0.68,0.30)），99F NPC「绿苔」的皮肤直接取该变体，不另存色值。"
LOG_VERSION_OFFSET = 1


def _find_row(ws) -> int:
    for row in range(1, ws.max_row + 1):
        if str(ws.cell(row, 1).value or "") == TARGET_ID:
            return row
    raise SystemExit(f"找不到 {TARGET_ID}")


def write_ledger() -> dict:
    backup = LEDGER.with_suffix(LEDGER.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(LEDGER, backup)
        print(f"[backup] {backup.name}")

    wb = load_workbook(LEDGER, data_only=False)
    ws = wb[ASSET_SHEET]
    row = _find_row(ws)

    state = str(ws.cell(row, 9).value or "")
    if "suit_green" not in state:
        ws.cell(row, 9).value = state + STATE_APPEND
    note = str(ws.cell(row, 25).value or "")
    if "suit_green" not in note:
        ws.cell(row, 25).value = note + NOTE_APPEND
    ws.cell(row, 22).value = datetime(2026, 11, 2)

    log = wb["域变更日志"]
    log_row = log.max_row + 1
    last_version = ""
    for r in range(5, log.max_row + 1):
        v = str(log.cell(r, 1).value or "")
        if v.startswith("v"):
            last_version = v
    parts = last_version.lstrip("v").split(".")
    if len(parts) != 3:
        raise SystemExit(f"日志末行版本格式异常：{last_version!r}")
    new_version = f"v{parts[0]}.{parts[1]}.{int(parts[2]) + LOG_VERSION_OFFSET}"

    from copy import copy

    log_values = [
        new_version,
        "2026-11-02",
        "衣柜新增苔绿作业服（suit_green）",
        "角色 / Bunny01 / body",
        "身体槽新增 suit_green；99F NPC「绿苔」皮肤直接取该变体，不再另存色值；玩家衣柜可选用同一档绿。",
        "同 ID 能力扩展：几何/骨架/动画/Prefab 路径与哈希不变，只扩换装枚举；文案·目录·色值三处同步。",
        "摩斯拉",
    ]
    for column, value in enumerate(log_values, start=1):
        cell = log.cell(log_row, column)
        cell.value = value
        cell._style = copy(log.cell(log_row - 1, column)._style)
    log.row_dimensions[log_row].height = log.row_dimensions[log_row - 1].height

    wb.save(LEDGER)
    return {"row": row, "log_row": log_row, "log_version": new_version, "backup": backup.name}


def refresh_baseline() -> dict:
    backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not backup.exists():
        shutil.copy2(BASELINE, backup)
        print(f"[backup] {backup.name}")

    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    index = LedgerIndex.load(ROOT)
    collected: list[tuple[int, tuple]] = []
    rows: list[tuple[str, tuple]] = []
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
        record = {"v": digest, "c": values[2], "d": domain_key}
        if aid not in assets:
            added.append(aid)
            assets[aid] = record
        elif assets[aid]["v"] != digest:
            if aid != TARGET_ID:
                raise SystemExit(f"白名单外的行指纹漂移：{aid}")
            refreshed.append(aid)
            assets[aid] = record

    if added:
        raise SystemExit(f"本批不应新增资产，但有新增：{added}")

    bl["asset_count"] = len(assets)
    cats: dict[str, int] = {}
    for entry in assets.values():
        cats[entry["c"]] = cats.get(entry["c"], 0) + 1
    bl["category_counts"] = dict(sorted(cats.items()))
    for column in CONTENT_COLUMNS:
        bl["column_digests"][str(column)] = col_digest(collected, column)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()
    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return {"refreshed": refreshed, "asset_count": bl["asset_count"]}


def main() -> int:
    print(json.dumps({"ledger": write_ledger(), "baseline": refresh_baseline()},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
