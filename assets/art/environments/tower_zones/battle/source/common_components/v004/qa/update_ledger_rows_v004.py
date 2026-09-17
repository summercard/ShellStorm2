# -*- coding: utf-8 -*-
"""战局区块通用组件库 v004：把「3D-场景通用」表里五个组件的登记行从 v003 就地升到 v004。

为什么是「就地改」而不是「追加新行」：
  * 台账是唯一登记源，AssetID 不重复（全表无 version-suffixed ID，无重复 ID），版本写在 O 列；
  * r10 的 ENV-TOWER-CORNER-L-5M 就是先例：它是 v002 的 GLB、v004 的 tscn，一行一 AssetID；
  * 因此 v004 的五个组件改写各自那一行的路径与版本，而不是让同一 AssetID 出现两行。

采用外科式 XML 补丁，而不是 openpyxl 重写整本：
  * openpyxl 会丢弃 styles/mergeCells/dataValidations 等，台账是唯一登记源，不能冒险；
  * 本脚本逐字节复制 xlsx 内所有条目，只替换 xl/worksheets/sheet10.xml 这一个文件。

幂等：目标行若已是 v004 且内容与目标一致，则整体退出，不重复写入。

用法：
  python update_ledger_rows_v004.py            # 写入
  python update_ledger_rows_v004.py --dry-run  # 只打印将要写入的内容
"""

import os
import re
import shutil
import sys
import zipfile
from xml.sax.saxutils import escape

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"
BACKUP = LEDGER + ".bak_common_components_v004"
ROW_STYLE = "393"

COLUMNS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"]

LIBRARY_ROOT = "assets/art/environments/tower_zones/battle"
COMPONENTS_REL = LIBRARY_ROOT + "/components/common_components"
RUNTIME_REL = LIBRARY_ROOT + "/runtime/common_components"
SOURCE_BLEND = LIBRARY_ROOT + "/source/common_components/v004/战局区块_通用组件库_v004.blend"

GODOT_TEST = ("tests/verification/verify_common_wall_door_components_v004.tscn 与 "
              "verify_common_floor_tile_components_v004.tscn")
BLEND_NOTE = ("GLB 不内嵌色盘，导入经 scene_facility_shared_palette_post_import.gd 绑公共色盘。"
              "Godot 契约断言通过（%s）。" % GODOT_TEST)
NO_CARRIER = "无"


def wall_standard_note():
    return ("2026-09-17：v004 把房间 v006 的墙面装甲并进本组件——每槽位自带 4 件槽位装甲单元"
            "（局部盒 [[-2.45,0.125,0.45],[2.45,0.153,8.3575]]，与朝向无关）。"
            "结构体仍 5.0×0.30×11.9、底面中心原点、贴网格中线面 z=+0.15 不变，"
            "故碰撞盒与 v003 完全相同（5.0×11.9×0.30 中心 y=5.95），装饰不改变体积；"
            "美术外廓因装饰前凸变为 5.0×0.303×11.9。"
            "北/南/东三面装甲单元在组件局部帧逐值相同（容差 2mm），故「不用按方位」。"
            "西墙原稿 5×2.9m 节奏不落 5m 槽位，已显式正常化为同一单元（唯一非逐值复刻处）。"
            "承接房间侧 7 个方位包共 249 件（wall_armor_north/south/east/west 等）。" + BLEND_NOTE)


def wall_door_note():
    return ("2026-09-17：v004 把房间 v006 的南/东门禁并进本组件——每槽位自带 11 件装甲门禁"
            "（门框立柱、门框蓝色灯条、门楣护板、门楣顶灯、禁行屏、门禁底板、状态灯）。"
            "门垛/门楣几何与碰撞盒与 v003 完全相同（门洞 2.2×2.5 不产生碰撞，"
            "门楣底=门扇顶=2.5m），装饰不改变体积；美术外廓因门禁前凸变为 5.0×0.365×11.9。"
            "门禁 LED 条向净宽内探 17.5mm（洞口名义 2.2m、灯条间 2.165m），属规范允许的"
            "纯表现突出细节，已记录在房间 v007 的 doorway_jamb_lips_under_core_skin。"
            "南/东两门禁在组件局部帧逐值相同，故「不用按方位」。承接房间侧南/东门禁共 22 件。"
            + BLEND_NOTE)


def door_note():
    return ("2026-09-17：v004 复核本组件无需变更——门扇几何 2.2×0.18×2.5 与碰撞盒"
            "（中心 y=1.25）与 v003 一致，仍与 wall_door_5m 门洞严格配对。"
            "本次仅随库升版重新导出并复验。"
            "接入 RoomDoor3D 时只取其 ImportedModel 子树（或直接传 GLB PackedScene 作 panel visual），"
            "并先与本组件内嵌碰撞去重，避免与 DoorCollision 重复。" + BLEND_NOTE)


def tile_note(cover):
    extra = ("c02 源美术里 4 块真分带/不带检修盖两款，组件统一取带盖版——"
             "与 v003 组件内嵌上板同一版，未删任何已画美术。" if cover else
             "c01 的 5 块一律带检修格栅，是唯一干净的一版，逐值复刻。")
    return ("2026-09-17：v004 把房间 v006 的地砖压边/蓝色拼缝/磨损并进本组件——每槽位自带"
            "%s砖面美术。结构板与内嵌板（主体_输出 / 主体_输出.001）与 v003 逐值相同，"
            "故碰撞盒与 v003 完全相同（本组件只在装饰上做增量）；"
            "美术外廓含装饰后为 4.94×4.94×%s。"
            "结构框（4 条压边 + 2 条蓝色拼缝）在 9 块砖上逐值相同；"
            "磨损每块独一无二，组件不可能逐块浮雕，故 9 块共用同一套磨损（风格化表现）。%s"
            "承接房间侧 floor_trim 共 205 件。注意与运行时塔楼地砖口径不同"
            "（运行时网格 5.00m/厚 0.30m/几何中心原点），接入需 y=-厚度 并先与 "
            "TowerFloorStage3D._build_support() 的整层矩形碰撞去重。" % (
                "25 件（4 压边 + 2 蓝拼缝 + 磨损/徽标/格栅）" if not cover else
                "22 件（4 压边 + 2 蓝拼缝 + 磨损/徽标/检修盖）",
                "0.083" if not cover else "0.0852",
                extra) + BLEND_NOTE)


ROWS = {
    92: [
        "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
        "战局通用地砖 R01_C01 4.94×4.94×0.056m（含砖面美术，外廓 0.083m）",
        RUNTIME_REL + "/floor_tile_5m/floor_tile_r01_c01_root_top3d_v004.tscn",
        COMPONENTS_REL + "/floor_tile_5m/floor_tile_r01_c01_visual_top3d_v004.glb",
        SOURCE_BLEND + "（集合 floor_tile_r01_c01_通用包）",
        "战局01通用组件库 09_地板组件；视觉薄壳地砖 + 自带砖面美术，逐实例化可替换单元"
        "（范式B：自包含 prefab + 自带碰撞）",
        NO_CARRIER,
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 4.94×0.056×4.94，与结构网格齐平（装饰不改变体积）",
        "4.94×4.94×0.056m 结构；含装饰外廓 4.94×4.94×0.083m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v004",
        tile_note(False),
    ],
    93: [
        "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
        "战局通用地砖 R01_C02 4.94×4.94×0.081m（含砖面美术，外廓 0.0852m）",
        RUNTIME_REL + "/floor_tile_5m/floor_tile_r01_c02_root_top3d_v004.tscn",
        COMPONENTS_REL + "/floor_tile_5m/floor_tile_r01_c02_visual_top3d_v004.glb",
        SOURCE_BLEND + "（集合 floor_tile_r01_c02_通用包）",
        "战局01通用组件库 09_地板组件；视觉薄壳地砖 + 自带砖面美术（带检修盖版），"
        "逐实例化可替换单元（范式B：自包含 prefab + 自带碰撞）",
        NO_CARRIER,
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 4.94×0.081×4.94，与结构网格齐平（装饰不改变体积）",
        "4.94×4.94×0.081m 结构；含装饰外廓 4.94×4.94×0.0852m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v004",
        tile_note(True),
    ],
    94: [
        "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
        "战局通用标准墙 5×0.30×11.9m（含槽位装甲，外廓 0.303m）",
        RUNTIME_REL + "/wall_standard_5m/wall_standard_5m_root_top3d_v004.tscn",
        COMPONENTS_REL + "/wall_standard_5m/wall_standard_5m_visual_top3d_v004.glb",
        SOURCE_BLEND + "（集合 wall_standard_5m_通用包）",
        "战局01通用组件库 08_墙壁组件；静态实墙 + 自带槽位装甲单元，与网格 5m 同宽可平铺，"
        "每槽位自动对齐、无需按方位（范式B：自包含 prefab + 自带碰撞）",
        NO_CARRIER,
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 5.0×11.9×0.30，中心 y=5.95，底面中心原点（与 v003 一致，装饰不改变体积）",
        "5.0×0.30×11.9m 结构；含装饰外廓 5.0×0.303×11.9m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v004",
        wall_standard_note(),
    ],
    95: [
        "ENV-BATTLE-COMMON-WALL-DOOR-5M",
        "战局通用门墙 5×0.30×11.9m（门洞 2.2×2.5，含装甲门禁，外廓 0.365m）",
        RUNTIME_REL + "/wall_door_5m/wall_door_5m_root_top3d_v004.tscn",
        COMPONENTS_REL + "/wall_door_5m/wall_door_5m_visual_top3d_v004.glb",
        SOURCE_BLEND + "（集合 wall_door_5m_通用包）",
        "战局01通用组件库 08_墙壁组件；带门洞的隔墙 + 自带装甲门禁（门框/灯条/门楣护板/"
        "禁行屏/状态灯），由左/右门垛与门楣三块构成，每槽位自动对齐、无需按方位"
        "（范式B：自包含 prefab + 自带碰撞）",
        NO_CARRIER,
        "开",
        "本组件（PackedScene 自带）",
        "3×BoxShape3D：左/右门垛 1.4×11.9×0.30（x=∓1.8）+ 门楣 2.2×9.4×0.30（y 底=2.5），"
        "门洞处不产生碰撞（与 v003 一致）",
        "5.0×0.30×11.9m 结构（净门洞 2.2×2.5m）；含装饰外廓 5.0×0.365×11.9m",
        "底面中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v004",
        wall_door_note(),
    ],
    96: [
        "ENV-BATTLE-COMMON-DOOR-5M",
        "战局通用门扇 2.2×0.18×2.5m",
        RUNTIME_REL + "/door_5m/door_5m_root_top3d_v004.tscn",
        COMPONENTS_REL + "/door_5m/door_5m_visual_top3d_v004.glb",
        SOURCE_BLEND + "（集合 door_5m_通用包）",
        "战局01通用组件库 10_门组件；门扇本体，底边中心原点、开门为垂直升起"
        "（范式B：自包含 prefab + 自带碰撞）",
        NO_CARRIER,
        "开",
        "本组件（PackedScene 自带）",
        "BoxShape3D 2.2×2.5×0.18，中心 y=1.25，底边中心原点",
        "2.2×0.18×2.5m",
        "底边中心（Godot 底面 Y=0、XZ 居中）；朝 -Z",
        "局内关卡01 / Battle（暂未接入）",
        "组件已完成；未接入",
        "v004",
        door_note(),
    ],
}


def build_row(row_number, values):
    cells = []
    for column, value in zip(COLUMNS, values):
        cells.append(
            '<x:c r="%s%d" s="%s" t="str"><x:v>%s</x:v></x:c>'
            % (column, row_number, ROW_STYLE, escape(value))
        )
    return '<x:row r="%d" ht="150" customHeight="1">%s</x:row>' % (row_number, "".join(cells))


def main():
    dry = "--dry-run" in sys.argv
    if not os.path.isfile(LEDGER):
        raise SystemExit("ledger not found: %s" % LEDGER)

    with zipfile.ZipFile(LEDGER) as archive:
        members = archive.infolist()
        payloads = {info.filename: archive.read(info.filename) for info in members}

    raw = payloads[SHEET_MEMBER].decode("utf-8")

    # 目标行必须存在，且必须已经登记着同一个 AssetID —— 就地升版的前提
    patched = raw
    for row_number in sorted(ROWS):
        values = ROWS[row_number]
        pat = re.compile(r'<x:row r="%d"[^>]*>.*?</x:row>' % row_number, re.S)
        found = pat.search(patched)
        if not found:
            raise SystemExit("sheet10 找不到目标行 r%d" % row_number)
        old = found.group(0)
        old_ids = re.findall(r'<x:v>(ENV-[^<]*)</x:v>', old)
        if not old_ids or old_ids[0] != values[0]:
            raise SystemExit("r%d 的 AssetID 不符：表内=%s 期望=%s"
                             % (row_number, old_ids[:1], values[0]))
        if old == build_row(row_number, values):
            print("r%-4d 已是最新，跳过" % row_number)
            continue
        patched = patched[:found.start()] + build_row(row_number, values) + patched[found.end():]
        print("r%-4d %s  已更新" % (row_number, values[0]))

    if patched == raw:
        print("SHEET 内容无变化，无需写盘")
        return

    if dry:
        print("\n--dry-run：未写盘。sheet10.xml %d -> %d bytes" % (len(raw), len(patched)))
        return

    # 复验：补丁后仍是合法 XML，且行数不变
    import xml.etree.ElementTree as ET
    ET.fromstring(patched)
    n_before = len(re.findall(r'<x:row ', raw))
    n_after = len(re.findall(r'<x:row ', patched))
    assert n_before == n_after, "行数变了：%d -> %d" % (n_before, n_after)

    payloads[SHEET_MEMBER] = patched.encode("utf-8")

    shutil.copy2(LEDGER, BACKUP)
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as out:
        for info in members:
            out.writestr(info, payloads[info.filename])

    print("backup:", BACKUP)
    print("rows kept: %d" % n_after)
    print("sheet10.xml: %d -> %d bytes" % (len(raw), len(patched)))
    print("LEDGER_V004_ROWS_UPDATED rows=%s" % sorted(ROWS))


if __name__ == "__main__":
    main()
