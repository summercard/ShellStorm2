"""Register ENV-EXPEDITION-L01-BOSS-ARENA in the split scene ledger.

Run from any directory that is NOT the project root (the project shadows the
stdlib `inspect` module):

    python scripts/register_expedition01_boss_arena_ledger.py

Writes stay inside assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx:
  * 《资产主表》 (sheet 3)  — row 241, the canonical asset entry
  * 《3D-场景通用》 (sheet 4) — row 147, prefab-page parity with the 17 battle
    whitebox rows that already live there
  * 《总览》 (sheet 1)      — extend the 资产主表 ranges from $240 to $241
  * 《域变更日志》 (sheet 7) — row 18, v0.1.12

Derived columns R/S are recomputed for every 资产主表 row, because the dedupe
formula is row-self-referential and the range end must cover the new last row.
Every other cell is copied by style array, never rewritten.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"

ASSET_ID = "ENV-EXPEDITION-L01-BOSS-ARENA"
FIRST_DATA_ROW = 6
BLEND_PATH = (
    "source/art/whitebox/tower_zones/expedition_01/v001/blender/"
    "远征关卡01_白模_Boss竞技场_50x40m_v001.blend"
)
SOURCE_BLEND = (
    "source/art/whitebox/tower_zones/battle_level01/v003/blender/"
    "局内关卡01_白模_Boss竞技场_190x90m_v003.blend"
)

MAIN_ROW_VALUES = {
    1: ASSET_ID,
    2: "远征关卡01 Boss竞技场 50×40m 白模",
    3: "场景",
    4: "boss_arena",
    5: "expedition_01_boss_arena",
    6: "root",
    7: None,
    8: "Top3D / Blender Z-up",
    9: "whitebox / default",
    10: "远征关卡01 专用",
    11: "Blender源已完成",
    12: "P1",
    13: "v001",
    14: "50×40×11.9m；10×8 个 5m 槽",
    15: BLEND_PATH,
    16: SOURCE_BLEND,
    17: "远征关卡01;Boss竞技场;白模;50×40m;竞技场",
    20: None,
    21: "摩斯拉",
    22: "2026-09-22",
    23: "用户设计（由局内关卡01竞技场白模派生）",
    24: "远征关卡01 Boss竞技场 50×40m 白模_资产管理",
    25: (
        "由局内关卡01 Boss竞技场190×90m白模v003按5m网格重建（非缩放；"
        "1/3线性缩放落在63.33×30m、X轴非5m整数倍，业主裁决取50×40m）。"
        "墙按固定5m槽位拼装，门墙完整占用5m槽并保留左右柱与门楣；"
        "两轴均为5m整数倍，无FIXED_TRIM收边。"
        "门：南→boss_prep(+2.5)、西→boss_exit(-2.5)。未导GLB、未接Godot。"
    ),
}

PREFAB_ROW_VALUES = {
    1: ASSET_ID,
    2: "远征关卡01 Boss竞技场 50×40m 白模",
    3: "未制作",
    4: "未制作",
    5: BLEND_PATH,
    6: (
        "远征关卡01 Boss竞技场白盒；50×40m / 10×8个5m槽；"
        "墙按固定5m槽位拼装，门墙完整占用5m槽并保留左右柱与门楣；"
        "两轴均为5m整数倍，无FIXED_TRIM收边。"
    ),
    7: "无",
    8: "无",
    9: "无",
    10: "无",
    11: "50×40×11.9m",
    12: "房间局部坐标：X/Y居中；底面Z=0；Godot -Z",
    13: "远征关卡01 / Expedition",
    # 与 battle_level01 的 17 行白模条目保持同值。该值不在本页 N 列 DV 的 7 项枚举内，
    # 但那 17 行同样不在，属既有的 DV 过期问题，不因本行新增类别。
    14: "白模源已完成；QA PASS",
    15: "v001",
    16: (
        "由局内关卡01 Boss竞技场190×90m白模v003按5m网格重建（非缩放）；"
        "1/3=63.33×30m不合5m模数，业主裁决取50×40m；"
        "南门boss_prep(+2.5)、西门boss_exit(-2.5)；未导GLB。"
    ),
}

CHANGELOG_ROW_VALUES = {
    1: "v0.1.12",
    2: "2026-09-22",
    3: "新增条目",
    4: "关卡场景 / 远征关卡01",
    5: (
        "新增 ENV-EXPEDITION-L01-BOSS-ARENA（远征关卡01 Boss竞技场 50×40m 白模）："
        "由局内关卡01 Boss竞技场190×90m白模按5m网格重建（非缩放）；"
        "1/3线性缩放落在63.33×30m、X轴非5m整数倍，经业主裁决取50×40m（10×8槽）。"
        "墙按固定5m槽位拼装，门墙完整占用5m槽，两轴无FIXED_TRIM收边；"
        "南门boss_prep(+2.5)、西门boss_exit(-2.5)。"
        "同批登记《资产主表》第241行与《3D-场景通用》第147行。未导GLB、未接Godot。"
    ),
    6: (
        "新增条目，不改动既有 AssetID / 路径 / 哈希；"
        "账本门禁历史问题数不变（仍为6项：1项主账本索引漂移 + 5项「白盒组件」非法状态）。"
    ),
    7: "摩斯拉",
}


def copy_style(source_cell, target_cell) -> None:
    target_cell._style = copy.copy(source_cell._style)


def dedupe_key(row: int) -> str:
    return (
        f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})'
        f'&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'
    )


def dedupe_result(row: int, last_row: int) -> str:
    return f'=IF(COUNTIF($R${FIRST_DATA_ROW}:$R${last_row},R{row})>1,"重复","唯一")'


def main() -> None:
    wb = load_workbook(LEDGER)
    report: dict[str, object] = {}

    # ---- 1. 《资产主表》: new row + recomputed derived columns ----
    main_sheet = wb["资产主表"]
    template_row = main_sheet.max_row
    new_row = template_row + 1
    for column, value in MAIN_ROW_VALUES.items():
        cell = main_sheet.cell(row=new_row, column=column)
        cell.value = value
        copy_style(main_sheet.cell(row=template_row, column=column), cell)
    main_sheet.cell(row=new_row, column=18).value = dedupe_key(new_row)
    main_sheet.cell(row=new_row, column=19).value = dedupe_result(new_row, new_row)
    copy_style(main_sheet.cell(row=template_row, column=18), main_sheet.cell(row=new_row, column=18))
    copy_style(main_sheet.cell(row=template_row, column=19), main_sheet.cell(row=new_row, column=19))

    rewritten = 0
    for row in range(FIRST_DATA_ROW, new_row + 1):
        expected = dedupe_result(row, new_row)
        cell = main_sheet.cell(row=row, column=19)
        if cell.value != expected:
            cell.value = expected
            rewritten += 1
    if main_sheet.row_dimensions[template_row].height:
        main_sheet.row_dimensions[new_row].height = main_sheet.row_dimensions[template_row].height
    report["main_sheet"] = {
        "new_row": new_row,
        "asset_id": main_sheet.cell(row=new_row, column=1).value,
        "dedupe_result_rows_rewritten": rewritten,
    }

    # ---- 2. 《总览》: extend the 资产主表 ranges ----
    overview = wb["总览"]
    extended: list[str] = []
    for row in overview.iter_rows():
        for cell in row:
            value = cell.value
            if isinstance(value, str) and "资产主表" in value and "$240" in value:
                cell.value = value.replace("$240", "$241")
                extended.append(cell.coordinate)
    report["overview_extended_cells"] = extended

    # ---- 3. 《3D-场景通用》: prefab-page parity row ----
    prefab_sheet = wb["3D-场景通用"]
    prefab_template = prefab_sheet.max_row
    prefab_row = prefab_template + 1
    for column, value in PREFAB_ROW_VALUES.items():
        cell = prefab_sheet.cell(row=prefab_row, column=column)
        cell.value = value
        copy_style(prefab_sheet.cell(row=prefab_template, column=column), cell)
    report["prefab_sheet"] = {
        "new_row": prefab_row,
        "asset_id": prefab_sheet.cell(row=prefab_row, column=1).value,
    }

    # ---- 4. 《域变更日志》 ----
    changelog = wb["域变更日志"]
    changelog_template = changelog.max_row
    changelog_row = changelog_template + 1
    for column, value in CHANGELOG_ROW_VALUES.items():
        cell = changelog.cell(row=changelog_row, column=column)
        cell.value = value
        copy_style(changelog.cell(row=changelog_template, column=column), cell)
    report["changelog_row"] = changelog_row

    wb.save(LEDGER)
    report["overview_startswith_double_equals"] = [
        overview[ref].value[:24] for ref in ("A6", "B10")
    ]
    print("EXPEDITION01_LEDGER_REGISTER_OK", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
