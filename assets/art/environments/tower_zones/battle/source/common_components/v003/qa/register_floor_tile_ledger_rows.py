# -*- coding: utf-8 -*-
"""战局区块通用组件库 v003 · 09_地板组件：向「3D-场景通用」表补登两块地砖。

采用外科式 XML 补丁，而不是 openpyxl 重写整本：
  * openpyxl 会丢弃 styles/mergeCells/dataValidations/表格等，台账是唯一登记源，不能冒险；
  * 本脚本逐字节复制 xlsx 内所有条目，只替换 xl/worksheets/sheet10.xml 这一个文件。

写入位置：现有最后一行数据 r91（ENV-BATTLE-L01-CORRIDOR-WALL-5M）之后，r280 空壳之前。
样式沿用 393（当前数据区行样式），保持视觉一致。
"""

import os
import re
import shutil
import zipfile
from xml.sax.saxutils import escape

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"
BACKUP = LEDGER + ".bak_floor_tile_5m"
ROW_STYLE = "393"

COLUMNS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"]

ROWS = [
    [
        "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
        "战局通用地砖 R01_C01 4.94×4.94×0.056m",
        "assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d_v003.tscn",
        "assets/art/environments/tower_zones/battle/components/common_components/floor_tile_5m/floor_tile_r01_c01_visual_top3d_v003.glb",
        "assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend（集合 floor_tile_r01_c01_通用包）",
        "战局01通用组件库 09_地板组件；视觉薄壳地砖，逐实例化可替换单元（范式B：自包含 prefab + 自带碰撞）",
        "无",
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 4.94×0.056×4.94，与可视网格齐平",
        "4.94×4.94×0.056m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v003",
        "2026-09-16：接地砖按L型转角范式B做成自包含可替换组件；GLB 不内嵌色盘，导入经 scene_facility_shared_palette_post_import.gd 绑公共色盘，surface 3/3 生效。契约断言 probe_floor_tile_components.gd 与 tests/verification/verify_common_floor_tile_components.tscn 通过；验收图 outputs/verification/common_floor_tile_components.png。注意与运行时塔楼地砖口径不同（运行时网格5.00m/厚0.30m/几何中心原点），接入需 y=-厚度 并先与 TowerFloorStage3D._build_support() 的整层矩形碰撞去重。",
    ],
    [
        "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
        "战局通用地砖 R01_C02 4.94×4.94×0.081m",
        "assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d_v003.tscn",
        "assets/art/environments/tower_zones/battle/components/common_components/floor_tile_5m/floor_tile_r01_c02_visual_top3d_v003.glb",
        "assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend（集合 floor_tile_r01_c02_通用包）",
        "战局01通用组件库 09_地板组件；视觉薄壳地砖，逐实例化可替换单元（范式B：自包含 prefab + 自带碰撞）",
        "无",
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 4.94×0.081×4.94，与可视网格齐平",
        "4.94×4.94×0.081m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v003",
        "2026-09-16：接地砖按L型转角范式B做成自包含可替换组件；GLB 不内嵌色盘，导入经 scene_facility_shared_palette_post_import.gd 绑公共色盘，surface 3/3 生效。契约断言 probe_floor_tile_components.gd 与 tests/verification/verify_common_floor_tile_components.tscn 通过。注意与运行时塔楼地砖口径不同（运行时网格5.00m/厚0.30m/几何中心原点），接入需 y=-厚度 并先与 TowerFloorStage3D._build_support() 的整层矩形碰撞去重。",
    ],
]

INSERT_AFTER_ROW = 91


def build_row(row_number, values):
    cells = []
    for column, value in zip(COLUMNS, values):
        cells.append(
            '<x:c r="%s%d" s="%s" t="str"><x:v>%s</x:v></x:c>'
            % (column, row_number, ROW_STYLE, escape(value))
        )
    return '<x:row r="%d" ht="90" customHeight="1">%s</x:row>' % (row_number, "".join(cells))


def main():
    if not os.path.isfile(LEDGER):
        raise SystemExit("ledger not found: %s" % LEDGER)

    with zipfile.ZipFile(LEDGER) as archive:
        members = archive.infolist()
        payloads = {info.filename: archive.read(info.filename) for info in members}

    raw = payloads[SHEET_MEMBER].decode("utf-8")

    existing = [int(m.group(1)) for m in re.finditer(r'<x:row r="(\d+)"', raw)]
    if INSERT_AFTER_ROW not in existing:
        raise SystemExit("anchor row %d missing" % INSERT_AFTER_ROW)

    # 幂等：若已存在同 AssetID，直接退出，不重复追加。
    for row in ROWS:
        if row[0] in raw:
            raise SystemExit("already registered: %s" % row[0])

    new_rows = [build_row(INSERT_AFTER_ROW + 1 + index, row) for index, row in enumerate(ROWS)]

    anchor = '<x:row r="%d"' % INSERT_AFTER_ROW
    start = raw.index(anchor)
    end = raw.index("</x:row>", start) + len("</x:row>")
    patched = raw[:end] + "".join(new_rows) + raw[end:]

    payloads[SHEET_MEMBER] = patched.encode("utf-8")

    shutil.copy2(LEDGER, BACKUP)
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as out:
        for info in members:
            out.writestr(info, payloads[info.filename])

    print("backup:", BACKUP)
    print("inserted rows:", [INSERT_AFTER_ROW + 1 + i for i in range(len(ROWS))])
    print("sheet10.xml: %d -> %d bytes" % (len(raw), len(patched)))


if __name__ == "__main__":
    main()
