#!/usr/bin/env python3
"""登记 2026-11-15 room_08 中庭局内自动贩卖机（场景账本最小追溯）。

本批没有任何新资产、也没有替换 GLB。变动只有两处：

  ① 《资产主表》Y242（`ENV-EXPEDITION-L01-L-CORRIDOR` 的「备注」列）追加本轮说明；
  ② 《域变更日志》新增一行 v0.1.90。

因此基线只允许改**一个**资产行指纹（`ENV-EXPEDITION-L01-L-CORRIDOR`）、
**一列**内容指纹（25=备注）与**两张分页**（没有——域变更日志不在 sheet_digests 里）。
除这一个 ID 外，任何既有行一变就必须失败。

Run: python scripts/register_expedition01_room08_vending_ledger.py
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
    _row_digest,
    col_digest,
    read_source_rows,
)

BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
TAG = "before_room08_vending_20261115"

ASSET_ID = "ENV-EXPEDITION-L01-L-CORRIDOR"
ASSET_ROW = 242          # 场景账本《资产主表》该行（A 列 = AssetID）
NOTE_COLUMN = 25         # Y = 备注
LOG_SHEET = "域变更日志"
LOG_HEADER_ROW = 4       # 数据从第 5 行起
LOG_VERSION = "v0.1.91"

NOTE = (
    "2026-11-15 业主重排 room_08 结构后，在中庭加一台**局内**自动贩卖机："
    "房间静态布局 TSCN 新增 1 个 `Marker3D` 锚点（`metadata/service_station_config`，"
    "type=merchant、trade_extraction=false），运行时由 `DungeonRoom3D._build_authored_service_stations()` 认领；"
    "视觉复用 99F `prp_base_vending_machine`（由铁边疆主题 `merchant_visual_scene` 声明），"
    "交易仍归 `RunMerchantService`/`MerchantUI`。**本房型源、GLB、Prefab、AssetID、版本与哈希均未改**；"
    "不新增资产行。详见 docs/v0.1/development/2026-11-15_expedition01_room08_ingame_vending.md"
)

LOG_ROWS = [
    LOG_VERSION,
    "2026-11-15",
    "远征01 room_08 中庭局内自动贩卖机（作者锚点服务点）",
    "ENV-EXPEDITION-L01-L-CORRIDOR / 远征01 room_08",
    "仅《资产主表》Y242 备注追加 + 本日志；房型源/GLB/Prefab/AssetID/版本/哈希不变，不新增行、不改分页",
    "新增通用能力「作者锚点声明服务点」（不认关卡ID）+ 交互区绕实体居中 + 交易撤离逐服务点声明（默认true）；"
    "专项探针23项exit0、商人集成回归exit0；13房静态场景红项与改前基线同为20条；整关partial不提升",
    "CodeBuddy",
]


def main() -> int:
    index = LedgerIndex.load(ROOT)
    domain = next(
        (d for d in index.domains if ASSET_ID.startswith(tuple(d.id_prefixes))),
        None,
    )
    if domain is None:
        print(json.dumps({"error": f"找不到拥有 {ASSET_ID} 的分账本"}, ensure_ascii=False))
        return 1
    path = domain.path

    xlsx_backup = path.with_suffix(path.suffix + "." + TAG)
    if not xlsx_backup.exists():
        shutil.copy2(path, xlsx_backup)
    baseline_backup = BASELINE.with_suffix(BASELINE.suffix + "." + TAG)
    if not baseline_backup.exists():
        shutil.copy2(BASELINE, baseline_backup)

    wb = load_workbook(path, data_only=False)
    sheet = wb[ASSET_SHEET]

    # ── ① 只追加备注，不让本脚本顺手改别的格 ────────────────────────────────
    if str(sheet.cell(row=ASSET_ROW, column=1).value or "") != ASSET_ID:
        print(json.dumps({
            "error": "行号漂移：A%d 不是 %s" % (ASSET_ROW, ASSET_ID),
            "actual": sheet.cell(row=ASSET_ROW, column=1).value,
        }, ensure_ascii=False))
        return 1
    previous = str(sheet.cell(row=ASSET_ROW, column=NOTE_COLUMN).value or "")
    if NOTE in previous:
        print(json.dumps({"error": "备注已存在，疑似重复执行"}, ensure_ascii=False))
        return 1
    sheet.cell(row=ASSET_ROW, column=NOTE_COLUMN).value = (
        (previous + "；" if previous else "") + NOTE
    )

    # ── ② 域变更日志追加一行 ────────────────────────────────────────────────
    log = wb[LOG_SHEET]
    rows_in_log = log.max_row
    versions = {
        str(log.cell(row=r, column=1).value or "").strip()
        for r in range(LOG_HEADER_ROW + 1, rows_in_log + 1)
    }
    if LOG_VERSION in versions:
        print(json.dumps({"error": f"{LOG_VERSION} 已存在，疑似重复执行"}, ensure_ascii=False))
        return 1
    target_row = rows_in_log + 1
    for offset, value in enumerate(LOG_ROWS, start=1):
        log.cell(row=target_row, column=offset).value = value

    wb.save(path)

    # ── ③ 基线：只刷新本行指纹 + 备注列 + 总数（行数不变则 category 不变）──────
    bl = json.loads(BASELINE.read_text(encoding="utf-8"))
    rows: list[tuple[str, tuple]] = []
    collected: list[tuple[int, tuple]] = []
    for d in index.domains:
        book = load_workbook(d.path, data_only=False)
        if ASSET_SHEET not in book.sheetnames:
            continue
        for row_index, values in read_source_rows(book[ASSET_SHEET]):
            rows.append((d.key, values))
            collected.append((row_index, values))

    assets = bl["assets"]
    mine: dict | None = None
    # 🔴 只认本行。磁盘上另有并行会话留下的既有漂移（他人未刷的行、未登记的两行宝箱），
    # 那些**不吸收**：基线是回归守卫，不能用「顺手刷新」掩掉别人的改动。
    preexisting_drift: list[str] = []
    preexisting_added: list[str] = []
    for domain_key, values in rows:
        aid = values[0]
        if not aid:
            continue
        digest = _row_digest(values)
        entry = {"v": digest, "c": values[2], "d": domain_key}
        if aid not in assets:
            preexisting_added.append(aid)
            continue
        if assets[aid]["v"] == digest:
            continue
        if aid == ASSET_ID:
            mine = entry
        else:
            preexisting_drift.append(aid)

    if mine is None:
        print(json.dumps({"error": "本行指纹未变化，备注可能没写进去"}, ensure_ascii=False))
        return 1
    assets[ASSET_ID] = mine

    # 备注列（25）必须刷新，否则门禁会把这一格报成「已提交未刷基线」。
    # 代价：该列在当前磁盘上若有他人未刷的备注改动，也会一并落到基线里 ——
    # 这是「列级指纹」的固有粒度，报告里如实列出。
    bl["column_digests"]["25"] = col_digest(collected, 25)
    bl["captured_at"] = datetime.now().replace(microsecond=0).isoformat()

    BASELINE.write_text(json.dumps(bl, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    print(json.dumps({
        "ledger": str(path.relative_to(ROOT)),
        "asset_row": ASSET_ROW,
        "changed_rows": [ASSET_ID],
        "log_row": target_row,
        "log_version": LOG_VERSION,
        "asset_count": bl["asset_count"],
        "preexisting_drift_not_absorbed": sorted(preexisting_drift),
        "preexisting_added_not_registered": sorted(preexisting_added),
        "backups": [
            str(xlsx_backup.relative_to(ROOT)),
            str(baseline_backup.relative_to(ROOT)),
        ],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
