# -*- coding: utf-8 -*-
"""登记 FX01-33 `VFX-BOARD-DEBRIS-3D`（暗门木板碎块飞溅）进特效账本。

业主口径（2026-10-19）：「做一个门被打碎的木头飞出来的特效，大块一点的，做完带入然后更新账本」。

改三处（同一本表）：
  1) 《资产主表》新增 r53 —— 唯一登记源，门禁 `--ledger vfx` 的 asset_count 只读这里；
  2) 《3D-特效》新增 r53（FX01-33）—— 特效域自己的 Prefab 分页；
  3) 《总览》把写死的 `$52` 区间统一扩到 `$53`（门禁要求「区间 == 本账本行数」）；
  4) 《域变更日志》新增 r37（v0.1.29）。

纪律（沿用 `scripts/blender/ledger_add_enemy_beast_spikeshell01.py`）：
  - 写前逐条断言表名/表头/行号/既有公式形态，防止静默写错位置；
  - 样式复制用 `copy(cell._style)`（`cell._style` 是 StyleArray，没有 `.copy()`）；
  - 查重键 / 查重结果公式**从 `tools/asset_pipeline/split_asset_ledger.py` 的权威函数生成**；
  - 幂等：`资产主表` 里已存在该 AssetID 就直接退出，不重复写。
"""
from __future__ import annotations

import hashlib
import shutil
import sys
from copy import copy
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.worksheet.cell_range import MultiCellRange

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
from split_asset_ledger import (  # noqa: E402
    FIRST_DATA_ROW,
    HEADER_ROW,
    dedupe_key_formula,
    dedupe_result_formula,
)

LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx"
BACKUP_DIR = ROOT / "_scratch"

NEW_ID = "VFX-BOARD-DEBRIS-3D"
NAME = "暗门木板碎块飞溅"
SUBCLASS = "combat"
LOGIC_ID = "board_debris_3d"
SOURCE_NO = "FX01-33"
PREFAB_REL = "assets/art/vfx/combat_3d/vfx_board_debris_root_top3d.tscn"
SCRIPT_REL = "src/vfx/VfxBoardDebris3D.gd"
TODAY = "2026-10-19"
NEW_ROW = 53
LOG_ROW = 37
LOG_VERSION = "v0.1.29"
TAG = "board_debris_vfx"

SPEC = (
    "8 大块（0.36~0.58m 长 × 0.16~0.26m 宽 × 0.07~0.10m 厚）+ 5 片小碎屑（0.045~0.085m）；"
    "2.85s 寿命；散布 3~5m"
)
ORIGIN = (
    "原点=门底中心（装配点），出生时抬高 1.25m 到门洞中部；"
    "局部 -Z 对齐 context.forward（门→房间侧），碎块朝房间内崩"
)
NOTE = (
    "2026-10-19 新建（业主：「做一个门被打碎的木头飞出来的特效，大块一点的」）。"
    "8 大块 + 5 片小碎屑，程序化抛物飞行 → 触地弹跳 1 次 → 贴地滑行 → 放平静止（不接物理引擎，无碰撞体）；"
    "自带 DebrisLight（峰值 1.5 / 范围 3.6m / 无阴影 / 0.55s 归零）——塔内夜间光，无灯就是黑剪影。"
    "材质：金属度 metallic=0.0 / 反光度 roughness=0.86（PER_PIXEL 受光）+ 自发光 0.38（暗房里保住「木头」读法）。"
    "确定性：脚本内无 randf()，散开由调用方给的 context.seed 派生（同 seed 逐位可复现）。"
    "调用方 SecretDoor3D._break_open()：只在真打破时播，读档恢复 / 静默打开不重播。"
    "验收 tests/verification/verify_board_debris_vfx.tscn（9 条，含大块下限 0.30m + 上限 0.65m 双向）。"
)


def sha256_of(rel: str) -> str:
    digest = hashlib.sha256()
    with (ROOT / rel).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


BACKUP_DIR.mkdir(parents=True, exist_ok=True)
backup = BACKUP_DIR / (LEDGER.name + f".bak_{TAG}")
shutil.copy2(LEDGER, backup)
print(f"BACKUP {backup}  {backup.stat().st_size} bytes")

wb = load_workbook(LEDGER)

# ============================ 1) 前置断言 =================================
for sheet in ("总览", "账本说明", "资产主表", "3D-特效", "域变更日志"):
    assert sheet in wb.sheetnames, f"sheet missing: {sheet}"

main = wb["资产主表"]
assert main.cell(HEADER_ROW, 1).value == "AssetID", main.cell(HEADER_ROW, 1).value
assert main.cell(HEADER_ROW, 18).value == "查重键"
assert main.cell(HEADER_ROW, 19).value == "查重结果"
existing_ids = {str(main.cell(r, 1).value) for r in range(FIRST_DATA_ROW, NEW_ROW) if main.cell(r, 1).value}
if NEW_ID in existing_ids:
    print(f"SKIP 已登记：{NEW_ID}（脚本幂等）")
    raise SystemExit(0)
assert main.cell(NEW_ROW, 1).value is None, f"r{NEW_ROW} 已被占用: {main.cell(NEW_ROW, 1).value}"
assert main.cell(52, 1).value == "VFX-DAMAGE-NUMBER-3D", main.cell(52, 1).value

fx = wb["3D-特效"]
assert fx.cell(4, 1).value == "编号", fx.cell(4, 1).value
assert fx.cell(4, 2).value == "AssetID"
assert fx.cell(NEW_ROW, 1).value is None, f"3D-特效 r{NEW_ROW} 已被占用: {fx.cell(NEW_ROW, 1).value}"
assert fx.cell(52, 1).value == "FX01-32", fx.cell(52, 1).value

ov = wb["总览"]
assert "$52" in str(ov["A6"].value), ov["A6"].value

log = wb["域变更日志"]
assert log.cell(5, 1).value == "台账版本", log.cell(5, 1).value
assert log.cell(36, 1).value == "v0.1.28", log.cell(36, 1).value
assert log.cell(LOG_ROW, 1).value is None, f"域变更日志 r{LOG_ROW} 已被占用"

LAST_ROW = NEW_ROW

# ============================ 2) 《资产主表》r53 ==========================
for col in range(1, 26):
    main.cell(NEW_ROW, col)._style = copy(main.cell(52, col)._style)
main.row_dimensions[NEW_ROW].height = main.row_dimensions[52].height

values = {
    1: NEW_ID,
    2: NAME,
    3: "特效",
    4: SUBCLASS,
    5: LOGIC_ID,
    6: "root_3d",
    7: None,
    8: "空间3D（朝房间侧）",
    9: "board_debris",
    10: "暗门破板事件",
    11: "已完成",
    12: "P1",
    13: "v001",
    14: SPEC,
    15: PREFAB_REL,
    16: f"{SCRIPT_REL}; docs/v0.1/14.6_特效系统与制作规范.md",
    17: "暗门;破板;木块;碎屑;大块;木板崩飞",
    18: dedupe_key_formula(NEW_ROW),
    19: dedupe_result_formula(NEW_ROW, LAST_ROW),
    20: sha256_of(PREFAB_REL),
    21: "Codex",
    22: TODAY,
    23: "原创Godot Prefab与脚本",
    24: SOURCE_NO,
    25: NOTE,
}
for col, value in values.items():
    main.cell(NEW_ROW, col).value = value

# 查重结果公式的区间扩到新行（否则新行永远判「唯一」，COUNTIF 区间不含自己）
for row in range(FIRST_DATA_ROW, LAST_ROW + 1):
    main.cell(row, 19).value = dedupe_result_formula(row, LAST_ROW)
    assert main.cell(row, 18).value == dedupe_key_formula(row), f"R{row} 公式形态异常"

# 下拉框范围要盖住新行
for dv in main.data_validations.dataValidation:
    before = str(dv.sqref)
    dv.sqref = MultiCellRange(before.replace("52", "53"))
    print(f"DV  {before} -> {dv.sqref}")

# ============================ 3) 《3D-特效》r53 ===========================
for col in range(1, 18):
    fx.cell(NEW_ROW, col)._style = copy(fx.cell(52, col)._style)
fx.row_dimensions[NEW_ROW].height = fx.row_dimensions[52].height

fx_values = {
    1: SOURCE_NO,
    2: NEW_ID,
    3: NAME,
    4: PREFAB_REL,
    5: "无（Prefab几何）",
    6: "无（Prefab几何）",
    7: (
        "暗门木板被打碎时，整面板崩成 8 块大木片 + 5 片小碎屑飞向房间侧，"
        "抛物落地、弹一下、贴地滑行后停住；自带 0.55s 暖色短灯照亮碎块"
    ),
    8: SCRIPT_REL,
    9: "无",
    10: "无",
    11: "无",
    12: SPEC,
    13: ORIGIN,
    14: "暗门木板被打碎时（SecretDoor3D._break_open → VfxPool3D.acquire）",
    15: "完成",
    16: "v001",
    17: NOTE,
}
for col, value in fx_values.items():
    fx.cell(NEW_ROW, col).value = value

# ============================ 4) 《总览》区间扩到 $53 =====================
for ref in ("A6", "C6", "E6", "G6", "B10", "C10", "B11", "C11"):
    cell = ov[ref]
    raw = str(cell.value)
    assert raw.startswith("="), f"{ref} 不是公式: {raw[:60]}"
    cell.value = raw.replace("$52", "$53")
assert "$53" in str(ov["A6"].value) and "$53" in str(ov["G6"].value)

# ============================ 5) 《域变更日志》r37 ========================
for col in range(1, 8):
    log.cell(LOG_ROW, col)._style = copy(log.cell(36, col)._style)
log.row_dimensions[LOG_ROW].height = log.row_dimensions[36].height

entry = {
    1: LOG_VERSION,
    2: TODAY,
    3: "新增",
    4: "特效 · 资产主表 / 3D-特效",
    5: (
        f"新增 {SOURCE_NO} {NEW_ID}（{NAME}）：8 大块木片（0.36~0.58m）+ 5 片小碎屑，"
        "程序化抛物/弹跳/滑行/静止，自带 DebrisLight 0.55s 短灯；"
        "调用方 SecretDoor3D._break_open()，读档恢复不重播。"
        "《资产主表》新增 r53，《3D-特效》新增 r53，《总览》区间由 $6:$52 扩到 $6:$53。"
    ),
    6: (
        "新增资产行 ⇒ 既有 47 行内容未变，但《总览》区间与查重结果公式区间随之变化，属预期；"
        "AssetID / 既有 Prefab 路径 / 既有条目 SHA 均未改动。"
    ),
    7: "Codex",
}
for col, value in entry.items():
    log.cell(LOG_ROW, col).value = value

wb.save(LEDGER)
print(f"LEDGER_WRITTEN {LEDGER.name} | 资产主表 r{NEW_ROW} | 3D-特效 r{NEW_ROW} | 日志 r{LOG_ROW} ({LOG_VERSION})")

# ============================ 6) 回读校验 ================================
check = load_workbook(LEDGER)
assert check["资产主表"].cell(NEW_ROW, 1).value == NEW_ID
assert check["3D-特效"].cell(NEW_ROW, 2).value == NEW_ID
assert check["域变更日志"].cell(LOG_ROW, 1).value == LOG_VERSION
assert "$53" in str(check["总览"]["A6"].value)
assert check["资产主表"].cell(NEW_ROW, 20).value == sha256_of(PREFAB_REL)
print("READBACK_OK")
print("DONE", NEW_ID, "|", NAME, "|", SOURCE_NO)
