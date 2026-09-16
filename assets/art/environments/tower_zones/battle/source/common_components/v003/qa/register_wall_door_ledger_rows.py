# -*- coding: utf-8 -*-
"""战局区块通用组件库 v003 · 08_墙壁组件 与 10_门组件：向「3D-场景通用」表补登三件。

采用外科式 XML 补丁，而不是 openpyxl 重写整本：
  * openpyxl 会丢弃 styles/mergeCells/dataValidations 等，台账是唯一登记源，不能冒险；
  * 本脚本逐字节复制 xlsx 内所有条目，只替换 xl/worksheets/sheet10.xml 这一个文件。

写入位置：自动取「有内容的最大数据行」（当前 r93，两块地砖），其后追加 r94/r95/r96，
跳过 r280 空壳行。样式沿用 393（当前数据区行样式），保持视觉一致。

幂等：任一 AssetID 已存在即整体退出，不重复追加。
"""

import os
import re
import shutil
import zipfile
from xml.sax.saxutils import escape

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"
BACKUP = LEDGER + ".bak_wall_door_5m"
ROW_STYLE = "393"

COLUMNS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"]

LIBRARY_ROOT = "assets/art/environments/tower_zones/battle"
COMPONENTS_REL = LIBRARY_ROOT + "/components/common_components"
RUNTIME_REL = LIBRARY_ROOT + "/runtime/common_components"
SOURCE_BLEND = LIBRARY_ROOT + "/source/common_components/v003/战局区块_通用组件库_v003.blend"

ROWS = [
    [
        "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
        "战局通用标准墙 5×0.30×11.9m",
        RUNTIME_REL + "/wall_standard_5m/wall_standard_5m_root_top3d_v003.tscn",
        COMPONENTS_REL + "/wall_standard_5m/wall_standard_5m_visual_top3d_v003.glb",
        SOURCE_BLEND + "（集合 wall_standard_5m_通用包）",
        "战局01通用组件库 08_墙壁组件；静态实墙，与网格 5m 同宽可平铺（范式B：自包含 prefab + 自带碰撞）",
        "无",
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 5.0×11.9×0.30，中心 y=5.95，底面中心原点",
        "5.0×0.30×11.9m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v003",
        "2026-09-16：本轮从 v003 源 blend 重新导出 GLB（此前工作区缺该导出件），并做自包含 prefab；白模前身为 r90。视觉墙高 11.9m，逻辑层高 12.0m，墙顶留 0.10m 净空与 TowerGeometry3D.WALL_VISUAL_TOP_CLEARANCE_M 一致。GLB 不内嵌色盘，导入经 scene_facility_shared_palette_post_import.gd 绑公共色盘。契约断言 tests/verification/verify_common_wall_door_components.tscn 通过；验收图 outputs/verification/common_wall_door_components.png。",
    ],
    [
        "ENV-BATTLE-COMMON-WALL-DOOR-5M",
        "战局通用门墙 5×0.30×11.9m（门洞 2.2×2.5）",
        RUNTIME_REL + "/wall_door_5m/wall_door_5m_root_top3d_v003.tscn",
        COMPONENTS_REL + "/wall_door_5m/wall_door_5m_visual_top3d_v003.glb",
        SOURCE_BLEND + "（集合 wall_door_5m_通用包）",
        "战局01通用组件库 08_墙壁组件；带门洞的隔墙，由左/右门垛与门楣三块构成（范式B：自包含 prefab + 自带碰撞）",
        "无",
        "开",
        "本组件（PackedScene 自带）",
        "3×BoxShape3D：左/右门垛 1.4×11.9×0.30（x=∓1.8）+ 门楣 2.2×9.4×0.30（y 底=2.5），门洞处不产生碰撞",
        "5.0×0.30×11.9m（净门洞 2.2×2.5m）",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v003",
        "2026-09-16：新建。门洞净空 2.2×2.5 取自 TowerGeometry3D.DOOR_CLEAR_WIDTH_M / DOOR_CLEAR_HEIGHT_M，门垛宽 1.4、门楣高 9.4 由网格 5.0 与墙高 11.9 推得；与 door_5m 门扇严格配对（门楣底=门扇顶=2.5m）。GLB 不内嵌色盘，导入经 scene_facility_shared_palette_post_import.gd 绑公共色盘。契约断言 tests/verification/verify_common_wall_door_components.tscn 通过（含门洞无碰撞与门墙/门扇配对断言）；验收图 outputs/verification/common_wall_door_components_door.png。",
    ],
    [
        "ENV-BATTLE-COMMON-DOOR-5M",
        "战局通用门扇 2.2×0.18×2.5m",
        RUNTIME_REL + "/door_5m/door_5m_root_top3d_v003.tscn",
        COMPONENTS_REL + "/door_5m/door_5m_visual_top3d_v003.glb",
        SOURCE_BLEND + "（集合 door_5m_通用包）",
        "战局01通用组件库 10_门组件；门扇本体，底边中心原点、开门为垂直升起（范式B：自包含 prefab + 自带碰撞）",
        "无",
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 2.2×2.5×0.18，中心 y=1.25，底边中心原点",
        "2.2×0.18×2.5m",
        "底边中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v003",
        "2026-09-16：新建。口径与 RoomDoor3D 一致——面板 2.2×2.5×0.18（PANEL_THICKNESS_M=0.18），导入门以底边中心为原点，开门改 panel.position.y 垂直升起而非旋转。接入 RoomDoor3D 时只取其 ImportedModel 子树（或直接传 GLB PackedScene 作 panel visual），并先与本组件内嵌碰撞去重，避免与 DoorCollision 重复。GLB 不内嵌色盘，导入经 scene_facility_shared_palette_post_import.gd 绑公共色盘。契约断言 tests/verification/verify_common_wall_door_components.tscn 通过；验收图 outputs/verification/common_wall_door_components.png。",
    ],
]


def build_row(row_number, values):
    cells = []
    for column, value in zip(COLUMNS, values):
        cells.append(
            '<x:c r="%s%d" s="%s" t="str"><x:v>%s</x:v></x:c>'
            % (column, row_number, ROW_STYLE, escape(value))
        )
    return '<x:row r="%d" ht="90" customHeight="1">%s</x:row>' % (row_number, "".join(cells))


def has_content(row_body):
    return "<x:v>" in row_body


def main():
    if not os.path.isfile(LEDGER):
        raise SystemExit("ledger not found: %s" % LEDGER)

    with zipfile.ZipFile(LEDGER) as archive:
        members = archive.infolist()
        payloads = {info.filename: archive.read(info.filename) for info in members}

    raw = payloads[SHEET_MEMBER].decode("utf-8")

    # 取「有内容的最大数据行」作为锚点（跳过 r280 之类空壳行）
    anchors = []
    for match in re.finditer(r'<x:row r="(\d+)"[^>]*>(.*?)</x:row>', raw, re.S):
        if has_content(match.group(2)):
            anchors.append(int(match.group(1)))
    if not anchors:
        raise SystemExit("sheet10 没有可辨识的数据行")
    anchor_row = max(anchors)
    print("anchor row (last data row):", anchor_row)

    for row in ROWS:
        if row[0] in raw:
            raise SystemExit("already registered: %s" % row[0])

    new_rows = [build_row(anchor_row + 1 + index, row) for index, row in enumerate(ROWS)]

    anchor = '<x:row r="%d"' % anchor_row
    start = raw.index(anchor)
    end = raw.index("</x:row>", start) + len("</x:row>")
    patched = raw[:end] + "".join(new_rows) + raw[end:]

    payloads[SHEET_MEMBER] = patched.encode("utf-8")

    shutil.copy2(LEDGER, BACKUP)
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as out:
        for info in members:
            out.writestr(info, payloads[info.filename])

    print("backup:", BACKUP)
    print("inserted rows:", [anchor_row + 1 + i for i in range(len(ROWS))])
    print("sheet10.xml: %d -> %d bytes" % (len(raw), len(patched)))


if __name__ == "__main__":
    main()
