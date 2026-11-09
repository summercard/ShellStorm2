"""2026-11-09 宝箱「出现」特效：在 FX01-35 行登记第二个消费方，并同步无损基线。

只改**既有行**的三格 + 一条域变更日志，不新增资产、不动总览区间、不动 DataValidation
（本账本行数没变）。

为什么需要单独开这一支：`VFX-TELEPORT-IN-3D` 原本只登记「怪物位移（blink 落点）」，
而 2026-11-09 业主把同一件视觉用在「关卡宝箱出现」上（暖金色 2.0 档）。账本按 AssetID
一行一件，"谁在用它"只记在 J 列与 Y 列，不补就出现「账上说只有怪在用，实际宝箱也在用」。

跑法：
    python tools/asset_pipeline/update_chest_appear_fx_ledger.py
然后跑门禁：
    check_asset_registry.py --scope structure / verify_ledger_split.py
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from copy import copy
from datetime import datetime
from pathlib import Path

import openpyxl

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from split_asset_ledger import (  # noqa: E402
    CONTENT_COLUMNS,
    FIRST_DATA_ROW,
    _row_digest,
    col_digest,
    read_source_rows,
)

BOOKS = ROOT / "assets/registry/ledgers"
BASELINE = ROOT / "assets/registry/ledger_split_baseline.json"
VFX_BOOK = BOOKS / "ShellStorm2_特效账本_v001.xlsx"
ASSET_ID = "VFX-TELEPORT-IN-3D"
TODAY = datetime(2026, 11, 9)

COL_REUSE = 10   # J 复用范围
COL_UPDATED = 22  # V 更新时间
COL_NOTE = 25    # Y 备注

NOTE_APPEND = (
    "\n2026-11-09：新增第二个消费方——**关卡宝箱出现**（业主：「我的救援宝箱，不是有个消失特效嘛？"
    "帮我改个颜色，放在关卡宝箱出现的时候，适当放大一点。这样我宝箱出来的时候不会很突兀」）。"
    "用例在 `TreasureChest3D.play_appear_effect()`：暖金 `Color(1.00, 0.78, 0.32)`、"
    "尺寸 **2.0**（= 救援箱消失那档 1.6 × 1.25）、贴地抬 0.05 m。"
    "**刻意用 IN 不用 OUT**：两者同一脚本的配对，OUT 的环向内收拢，播在「凭空出现」上读作被吸走，"
    "语义正好反了。触发点两处：`DungeonRoom3D.play_chest_appear_effects()`（玩家进房时播一次，"
    "流送重建不重播）与 `DungeonRoom3D.spawn_runtime_chest()`（清房/Boss 掉落当场播）；"
    "基地救援箱不播（那时玩家正趴着听绿苔说话）。Prefab / 脚本 / 版本号均未变。"
)


def fail(message: str) -> None:
    raise SystemExit(f"CHEST_APPEAR_FX_LEDGER_FAILED: {message}")


def find_row(sheet, asset_id: str) -> int:
    rows = [r for r in range(FIRST_DATA_ROW, sheet.max_row + 1) if sheet.cell(r, 1).value == asset_id]
    if len(rows) != 1:
        fail(f"{asset_id} 行数异常: {rows}")
    return rows[0]


def append_log(workbook, title: str, scope: str, details: str) -> str:
    sheet = workbook["域变更日志"]
    last = sheet.max_row
    old_version = str(sheet.cell(last, 1).value)
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", old_version)
    if not match:
        fail(f"域变更日志末行版本号不是 vX.Y.Z: {old_version}")
    version = f"v{match[1]}.{match[2]}.{int(match[3]) + 1}"
    values = [
        version,
        "2026-11-09",
        title,
        scope,
        details,
        "更新既有行的复用范围与备注；不新增资产，行数与总览区间不变。",
        "Codex",
    ]
    for offset, value in enumerate(values, 1):
        sheet.cell(last + 1, offset)._style = copy(sheet.cell(last, offset)._style)
        sheet.cell(last + 1, offset).value = value
    return version


def main() -> None:
    if not VFX_BOOK.is_file():
        fail(f"账本不存在: {VFX_BOOK}")
    workbook = openpyxl.load_workbook(VFX_BOOK)
    sheet = workbook["资产主表"]
    row = find_row(sheet, ASSET_ID)

    reuse_before = str(sheet.cell(row, COL_REUSE).value or "")
    already = "宝箱" in reuse_before
    version = "(skipped)"
    if already:
        # 幂等：账本已写过就只补基线（本脚本在慢盘上被强杀过一次，
        # 当时账本已保存、基线没写完 —— 重跑必须能自愈，不能因为"写过了"直接 fail）。
        print(f"CHEST_APPEAR_FX_LEDGER: 账本已登记，跳过写入，仅重建基线（row={row}）")
    else:
        sheet.cell(row, COL_REUSE).value = (
            "怪物位移（blink 落点）；关卡宝箱出现（贴地金环 · 尺寸 2.0）"
        )
        sheet.cell(row, COL_UPDATED).value = TODAY
        note_before = str(sheet.cell(row, COL_NOTE).value or "")
        sheet.cell(row, COL_NOTE).value = note_before + NOTE_APPEND

        version = append_log(
            workbook,
            "宝箱出现特效复用 FX01-35",
            "特效 / combat",
            "VFX-TELEPORT-IN-3D 新增第二个消费方：关卡宝箱出现（暖金、尺寸 2.0、贴地抬 0.05m）。"
            "Prefab/脚本/版本号未变，仅登记用途。",
        )
        workbook.save(VFX_BOOK)

    # —— 无损基线：只重算本行指纹 + 全量列指纹 + 分类计数 ——
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    index = json.loads((ROOT / "assets/registry/ledger_index.json").read_text(encoding="utf-8"))
    touched = {ASSET_ID}
    all_rows = []
    seen_touched = set()
    for domain in index["domains"]:
        # ⚠ 不传 `read_only=True`：`read_source_rows()` 是逐格 `ws.cell(r, c)` 取值，
        # 而 read_only 模式下每次 cell 访问都要重扫工作表 ⇒ 1017 行的场景账本能吃到
        # 好几分钟（2026-11-09 实测本脚本因此被强杀两次）。普通模式 0.3s 读完 9 本。
        book = openpyxl.load_workbook(BOOKS / domain["file"])
        for number, record in read_source_rows(book["资产主表"]):
            all_rows.append((number, record))
            asset_id = str(record[0])
            if asset_id in touched:
                baseline["assets"][asset_id] = {
                    "v": _row_digest(record),
                    "c": str(record[2]),
                    "d": domain["key"],
                }
                seen_touched.add(asset_id)
    if seen_touched != touched:
        fail(f"基线没找到这些资产行: {sorted(touched - seen_touched)}")

    baseline["captured_at"] = "2026-11-09"
    baseline["asset_count"] = len(baseline["assets"])
    # ⚠ **刻意不重算 `column_digests` / `category_counts`**。
    # 那是"新增行 / 整表重建"时才该做的事。本次只改了一行的三格，重算会把工作区里
    # 其他并行会话尚未提交的账本差异一并吃进基线 —— 等于用"当前文件"掩盖差异，
    # 违反 AGENTS.md 那条「哈希漂移先核对变更来源，不批量接受当前文件」。
    # 保留旧指纹的代价只是门禁报告里多一条 `column_digest_drift`（报告项，不 fail），
    # 换来的是"谁改的、改了哪行"仍然可追。
    BASELINE.write_text(json.dumps(baseline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    print(f"CHEST_APPEAR_FX_LEDGER_UPDATED row={row} log={version}")


if __name__ == "__main__":
    main()
