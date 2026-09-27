# -*- coding: utf-8 -*-
"""2026-09-27 远征关卡01 房型资产转正（场景分账本）

三件事：
 ① 办公室 v006 / 通道桥 v007：制作状态「Blender源已完成」→「正式美术已接入」；
 ② 新增 Boss 房行 ENV-EXPEDITION-L01-BOSS-ROOM（房型美术 v002 + 独立组件库 v008）；
 ③ 同步派生公式与统计区间：S 列区间、总览 12 格、DataValidation sqref、域变更日志。

纪律：
  - 只用 openpyxl 写。**禁止**本地编辑器链路（实测会把 R 列写成 `==LOWER`、S 列写成数组公式）。
  - 只动《资产主表》与《域变更日志》；《3D-场景通用》等摘要锁死表一律不碰。
  - 前置断言齐全，任一条不成立立即 AssertionError 退出，不半写。

用法：python apply_expedition_roomtype_promotion.py
"""
from __future__ import annotations

import shutil
import sys
from copy import copy
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    FIRST_DATA_ROW,
    HEADER_ROW,
    dedupe_key_formula,
    dedupe_result_formula,
)

LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
BACKUP = LEDGER.with_name(LEDGER.name + ".bak_roomtype_promotion")
TODAY = "2026-09-27"

OFFICE = "ENV-EXPEDITION-L01-OFFICE-ROOM"
BRIDGE = "ENV-EXPEDITION-L01-BRIDGE-ROOM"
DB = "ENV-EXPEDITION-L01-ROOM-DB-70X50"
BOSS = "ENV-EXPEDITION-L01-BOSS-ROOM"

wb = load_workbook(LEDGER)
ws = wb[ASSET_SHEET]

LAST_BEFORE = max(
    r for r in range(FIRST_DATA_ROW, ws.max_row + 1) if ws.cell(r, 1).value
)
assert LAST_BEFORE == 246, "资产数据末行变了：%s（脚本按 246 写的）" % LAST_BEFORE
assert str(ws.cell(HEADER_ROW, 1).value) == "AssetID"

row_of: dict[str, int] = {}
for r in range(FIRST_DATA_ROW, LAST_BEFORE + 1):
    aid = str(ws.cell(r, 1).value or "").strip()
    if aid:
        row_of[aid] = r
assert row_of[OFFICE] == 243, row_of.get(OFFICE)
assert row_of[BRIDGE] == 244, row_of.get(BRIDGE)
assert row_of[DB] == 246, row_of.get(DB)
assert BOSS not in row_of, "Boss 行已存在 —— 本脚本不该重跑"

# ------------------------------------------------------------------ ① 转正
PROMOTIONS = {
    OFFICE: (
        "；组件库 v006：25 个唯一组件 / 106 个实例，运行时按 component_instances.json 逐组件重放",
        "未导 GLB、未接 Godot。",
        "2026-09-27：房型组件库 v006 已逐件导出 25 个稳定 GLB/PackedScene 并接入运行时"
        "（room_03 / room_09 各 106 实例、unresolved=0、门 2 扇）；主层地砖运行时换通用 C01/C02 棋盘砖。",
    ),
    BRIDGE: (
        "；组件库 v007：35 个唯一组件 / 242 个实例，运行时按 component_instances.json 逐组件重放",
        "未导 GLB、未接 Godot。",
        "2026-09-27：房型组件库 v007 已逐件导出 35 个稳定 GLB/PackedScene 并接入运行时"
        "（room_05 242 实例、unresolved=0、门 2 扇）；主层地砖换通用 C01/C02 棋盘砖，坑底 36 块砖保持原样。",
    ),
}
for aid, (spec_suffix, old_tail, new_tail) in PROMOTIONS.items():
    r = row_of[aid]
    assert ws.cell(r, 11).value == "Blender源已完成", (aid, ws.cell(r, 11).value)
    ws.cell(r, 11).value = "正式美术已接入"
    spec = str(ws.cell(r, 14).value or "")
    assert spec_suffix not in spec
    ws.cell(r, 14).value = spec + spec_suffix
    note = str(ws.cell(r, 25).value or "")
    assert old_tail in note, (aid, note[-80:])
    ws.cell(r, 25).value = note.replace(old_tail, new_tail)
    ws.cell(r, 22).value = TODAY
    print("PROMOTED %s r%d" % (aid, r))

# ------------------------------------------------------------ ② 数据库房 v014 转正
DB_ROW = row_of[DB]
assert ws.cell(DB_ROW, 11).value == "Blender源已完成", (DB, ws.cell(DB_ROW, 11).value)
ws.cell(DB_ROW, 11).value = "正式美术已接入"
ws.cell(DB_ROW, 13).value = "v014"
ws.cell(DB_ROW, 14).value = (
    "40×30m；房型组件库 v014：35 个唯一组件 / 86 个实例；"
    "运行时 3 间房均按 component_instances.json 重放，42 块主层地砖换通用 C01/C02，"
    "44 个普通房型组件，unresolved=0，门 2 扇；db_02 仍待另行制作"
)
ws.cell(DB_ROW, 15).value = "assets/art/environments/tower_zones/expedition/source/room_types/db_room/v002/"
ws.cell(DB_ROW, 16).value = (
    "assets/art/environments/tower_zones/expedition/source/common_components/v014/component_catalog.json；"
    "component_instances.json；运行时 PackedScene 注册表 shell_component_catalog.json"
)
ws.cell(DB_ROW, 20).value = "ba0d29bcd4e89d901fa3102f66fa449ea6028bcb860c5be170bdc50fd31303c6"
ws.cell(DB_ROW, 22).value = TODAY
ws.cell(DB_ROW, 25).value = (
    "2026-09-27：数据库房 v014 已完成 35 个独立 GLB/PackedScene 导出并接入 Godot。"
    "room_02 / room_06 / room_10 均通过组件重放验收（86 实例、42 通用棋盘砖、44 普通组件、"
    "unresolved=0、2 扇门）；room_06 当前暂重放 db_01 默认布局，db_02 变体仍待另行制作。"
)
print("PROMOTED %s r%d" % (DB, DB_ROW))

# ------------------------------------------------------------ ③ 新增 Boss 行
NEW_ROW = LAST_BEFORE + 1
BOSS_PATH = (
    "assets/art/environments/tower_zones/expedition/source/room_types/"
    "boss_room/v002/Boss房种类_故障数据库_50x40m_v002.blend"
)
BOSS_SHA = "e61a8ca0dcd5b133a09bc13d6567bbcba513838709ea77fbac951670b9ad0b29"
assert (ROOT / BOSS_PATH).is_file(), BOSS_PATH

boss_values = {
    1: BOSS,
    2: "远征关卡01 Boss竞技场 故障数据库 50×40m 房间种类源",
    3: "场景",
    4: "boss_room",
    5: "expedition_01_boss_room",
    6: "room_type",
    8: "Top3D / Blender Z-up",
    9: "scene_art / reference_derived",
    10: "远征关卡01 专用；boss 房（boss_50x40，50×40m）。房型套件为独立一库（common_components/v008，与 office / bridge 两批不混用）",
    11: "正式美术已接入",
    12: "P1",
    13: "v002",
    14: (
        "50×40×11.9m（10×8 个 5m 槽 / 72 个墙位）；组件库 v008：38 个唯一组件 / 210 个实例（17 族）；"
        "主层地砖 80 格运行时换通用 C01/C02 棋盘砖；门位 2（西 / 东 lane −2.5）；QA PASS（专项探针 2051 项断言）"
    ),
    15: BOSS_PATH,
    16: (
        "assets/art/environments/tower_zones/expedition/source/common_components/v008/component_plan.json；"
        "component_slug_map.json；归并工具 scripts/blender/regroup_room_type_components.py"
    ),
    17: "远征关卡01;Boss竞技场;故障数据库;房间种类;50×40m;服务器机柜;主屏;桥架;组件库;v008",
    18: dedupe_key_formula(NEW_ROW),
    20: BOSS_SHA,
    21: "摩斯拉",
    22: TODAY,
    23: "用户设计（参考图见 room_type_manifest.json 的 reference_image）",
    24: "—",
    25: (
        "服务远征关卡01 的 boss 房（BOSS，中心 -20/0/-85）。房型套件独立一库（common_components/v008，"
        "38 组件 / 210 实例），运行时按 component_instances.json 重放；主层地砖统一换通用 C01/C02 棋盘砖，"
        "墙 / 家具 / 标识 / 碎屑保留自有美术。"
    ),
}
for col in range(1, 26):
    ws.cell(NEW_ROW, col)._style = copy(ws.cell(row_of[OFFICE], col)._style)
ws.row_dimensions[NEW_ROW].height = ws.row_dimensions[row_of[OFFICE]].height
for col, value in boss_values.items():
    ws.cell(NEW_ROW, col).value = value
print("NEW_ROW %s r%d" % (BOSS, NEW_ROW))

NEW_LAST = NEW_ROW

# ------------------------------------------- ③ S 列派生公式区间扩到新末行
rewritten = 0
for r in range(FIRST_DATA_ROW, NEW_LAST + 1):
    want = dedupe_result_formula(r, NEW_LAST)
    if ws.cell(r, 19).value != want:
        ws.cell(r, 19).value = want
        rewritten += 1
print("S_FORMULA_REWRITTEN %d" % rewritten)

# ------------------------------------------------------------ ④ DV sqref
old_token = str(LAST_BEFORE)
new_dvs = []
for dv in ws.data_validations.dataValidation:
    ranges = []
    for rng in dv.sqref.ranges:
        text = str(rng)
        if text.endswith(old_token):
            text = text[: -len(old_token)] + str(NEW_LAST)
        ranges.append(text)
    ndv = copy(dv)
    ndv.sqref = ",".join(ranges)
    new_dvs.append((",".join(ranges), ndv))
ws.data_validations.dataValidation = [ndv for _t, ndv in new_dvs]
print("DV:", [t for t, _ in new_dvs])

# ------------------------------------------------------------ ⑤ 总览区间
ov = wb["总览"]
OV_CELLS = ["A6", "C6", "E6", "G6", "B10", "C10", "B11", "C11", "B12", "C12", "B13", "C13"]
for ref in OV_CELLS:
    old = str(ov[ref].value or "")
    assert old.startswith("="), (ref, old[:40])
    assert "$%s" % LAST_BEFORE in old, (ref, "未含旧末行 246")
    ov[ref].value = old.replace("$%s" % LAST_BEFORE, "$%s" % NEW_LAST)
print("OVERVIEW_UPDATED", OV_CELLS)

# ------------------------------------------------------- ⑥ 域变更日志
lg = wb["域变更日志"]
last_ver_row = None
for r in range(1, lg.max_row + 1):
    if str(lg.cell(r, 1).value or "").startswith("v0."):
        last_ver_row = r
assert last_ver_row, "找不到版本行"
assert str(lg.cell(last_ver_row, 1).value) == "v0.1.16", lg.cell(last_ver_row, 1).value
target = last_ver_row + 1
for col in range(1, 8):
    lg.cell(target, col)._style = copy(lg.cell(last_ver_row, col)._style)
lg.cell(target, 1).value = "v0.1.17"
lg.cell(target, 2).value = TODAY
lg.cell(target, 3).value = "状态转正 + 新增条目"
lg.cell(target, 4).value = "关卡场景 / 远征关卡01"
lg.cell(target, 5).value = (
    "① ENV-EXPEDITION-L01-OFFICE-ROOM（组件库 v006）与 ENV-EXPEDITION-L01-BRIDGE-ROOM（组件库 v007）"
    "制作状态「Blender源已完成」→「正式美术已接入」：两套房型源按组件优先规则归并为唯一组件库，"
    "逐件导出稳定 GLB / PackedScene 并接入运行时（room_03 / room_09 各 106 实例、room_05 242 实例，"
    "unresolved 全 0，主层地砖统一换通用 C01/C02 棋盘砖）。"
    "② 新增 ENV-EXPEDITION-L01-BOSS-ROOM（远征关卡01 Boss竞技场 故障数据库 50×40m 房间种类源，v002，"
    "服务 boss 房）：房型套件为独立一库，组件库 v008 = 38 个唯一组件 / 210 个实例。"
)
lg.cell(target, 6).value = (
    "① 两行只改「制作状态 / 规格 / 备注 / 更新时间」，AssetID、路径、SHA-256 逐格未动"
    "（--scope full 既有 40 条 sha_mismatch 逐项不变，可反向对照）。② 新增一行 ⇒ S 列派生公式区间与"
    "《总览》12 格区间随之扩到 $%d（属预期，门禁 stale_overview_formula 盯着）。"
    "③ 《3D-场景通用》等摘要锁死表未动。④ 无损基线按既有「从当前分账本重建」口径做最小补录"
    "（加新行指纹、更新两行既有指纹，其余 413 条逐位不变，列摘要与分类计数重算），"
    "补录前基线备份见 _scratch/ledger_roomtype/ledger_split_baseline.json.bak_before。" % NEW_LAST
)
lg.cell(target, 7).value = "摩斯拉"
print("LOG v0.1.17 r%d" % target)

shutil.copy2(LEDGER, BACKUP)
wb.save(LEDGER)
print("LEDGER_SAVED")
print("LEDGER_ROOMTYPE_PROMOTION_DONE")
