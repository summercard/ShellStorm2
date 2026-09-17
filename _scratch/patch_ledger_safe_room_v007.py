# -*- coding: utf-8 -*-
"""安全房 v007 正式美术接入运行时：把「3D-场景通用」表里的登记就地升级。

本脚本做两件事：

  1. **r86 / r87（ENV-BATTLE-L01-SAFE-ENTRY / SAFE-EXIT）整行重建**
     从「白模源已完成,QA PASS / v003」升为「正式美术已接入 / v007」。
     v007 是单一方位布局：南/东墙中段各开一个 2.2×2.5 门洞、其余 10 段为
     5m 实墙、地面 3×3 棋盘地砖；运行时按本层实际门向把整房旋转，
     故入口与出口安全房共用同一套资产，不再按方位分版本。

  2. **r92..r96（战局区块通用组件库 v004 五件）只改 M / N / P 三格**
     这五件的几何与路径上一轮已登记（见 update_ledger_rows_v004.py）。
     本轮安全房 v007 在运行时直接 preload 它们，故「使用位置」与
     「制作状态」要从「暂未接入」改为「安全房 v007 已接入」，
     否则台账自相矛盾（r86 说改引用 v004，而 v004 行说未接入）。

为什么整行重建 r86/r87 而不是逐格补丁：r86/r87 除 AssetID 外几乎每一列都要
改，且它们与 update_ledger_rows_v004.py 重建出的行同构（s="393" t="str"、
文本落 <x:v>、行带 ht），整行重建最不易残留白模期的旧描述。

为什么 r92..r96 只改三格：那五行的 C/D/E/F/... 上一轮已按 v004 写准，
本轮只有「是否被引用」这一事实变了，逐格改可最大限度保留原内容与样式。

全程外科式 XML 补丁：逐字节复制 xlsx 内所有 zip 条目，只替换
xl/worksheets/sheet10.xml，绝不走 openpyxl 整本重写（会丢 styles /
mergeCells / dataValidations，台账是唯一登记源）。

幂等：目标内容若已就位，则不重复写入。

用法：
  python patch_ledger_safe_room_v007.py            # dry-run，只打印
  python patch_ledger_safe_room_v007.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import os
import re
import shutil
import sys
import zipfile
from xml.sax.saxutils import escape

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"
BACKUP_SUFFIX = ".bak_safe_room_v007"
ROW_STYLE = "393"
ROW_HEIGHT = "90"

COLUMNS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"]
COL_ORDER = {c: i for i, c in enumerate(COLUMNS)}

RUNTIME_ROOT = "assets/art/environments/tower_zones/battle/runtime"
COMPONENTS_ROOT = "assets/art/environments/tower_zones/battle/components"
SOURCE_BLEND = ("assets/art/environments/tower_zones/battle/source/entry_safe_room/v007/"
                "局内关卡01_入口安全房_15x15m_正式美术_v007.blend")

PACKAGE_RUNTIME = (RUNTIME_ROOT + "/entry_safe_room/v007/*/*_root_top3d_v007.tscn"
                   "（17 包）；墙/地/门引用 "
                   + RUNTIME_ROOT + "/common_components/*_root_top3d_v004.tscn")
PACKAGE_GLB = (COMPONENTS_ROOT + "/entry_safe_room/v007/*/*_visual_top3d_v007.glb（17 包）")
SCRIPT_PATH = "src/world3d/DungeonRoom3D.gd（_build_safe_room_shell / _build_safe_room_packages）"

COLLISION_OWNER = ("通用组件 v004（PackedScene 自带，collision_owner=self）"
                   " + TowerFloorStage3D（楼板承重）")
COLLISION_WAY = (
    "实墙/门墙自带 0.30m 结构碰撞即玩法阻挡（10 实墙 + 2 门墙；门洞 2.2×2.5 不产生碰撞）；"
    "地砖与门扇自带碰撞在接入时按层关闭去重（collision_layer=0），"
    "楼板承重归 TowerFloorStage3D._build_support()、门扇通行归 RoomDoor3D 升降碰撞；"
    "南/北向门另留唯一 camera-only 门墙代理承接镜头探针（与旧塔楼路径同契约）。"
)
SIZE_TEXT = ("15×15×11.9m（可行走面 z=0.30；墙中线 ±7.35，墙内脸 7.2 / 外脸 7.5，墙厚 0.30；"
             "网格 5.0m，地砖模块 4.94m 见方 + 0.06m 勾缝）")
ORIGIN_TEXT = "房间局部坐标：X/Y 居中、底面 Z=0；Godot -Z；整房按本层门向旋转 0/90/180/270°"

COMMON_NOTE = (
    "2026-09-17：v007 正式美术完整接入运行时。房间只保留槽位与引用，"
    "墙/地/门（含其装饰）全部由战局区块通用组件库 v004 提供——"
    "实墙 10 + 门墙 2（南/东）+ 门扇 2 + 地砖 9（r01_c01 ×5 / r01_c02 ×4）；"
    "共 23 槽位、311 槽位对象（结构 36 + 装饰 275）。"
    "房间自有的 15 个墙/地模块、16 个旧资产包与 7 个已被 v004 吸收的装饰包（249 件）已显式移除，"
    "仅承重底板 FLOOR_BASE（15×15×0.26）由房间自持。"
    "运行时由 DungeonRoom3D._build_safe_room_shell() 按本层门向整房旋转，"
    "单一方位服务全部楼层；墙/门墙自带 0.30m 碰撞即玩法阻挡，"
    "地砖/门扇自带碰撞接入时按层关闭去重，楼板承重归 TowerFloorStage3D、门扇通行归 RoomDoor3D。"
    "楼板侧配合变更：TowerFloorStage3D 为每个 STAIR_LOBBY 房间在通用可视地砖上挖出 15×15m 可视洞"
    "（每房间 9 格，承重碰撞不变），新增 additional_visual_holes 与 _additional_visual_hole_tile_count"
    "（与楼梯洞按点去重后记账），已并入塔楼楼板 tile 契约，"
    "verify_tower_grid_component_alignment 通过。"
    "美术验收：构建自检 32/32、独立重开复测 34/34、包导出 EXPORT_OK count=17、"
    "Prefab PREFAB_OK total=17 written=17、GLB 独立复验 20/20；"
    "运行时探针 probe_safe_room_v007_integration 通过（SAFE_ROOM_V007_INTEGRATION_OK："
    "10 实墙 / 2 门墙 / 9 地砖 / 17 包，门扇落 ±7.5 边界网格线，旧塔楼拼装无残留）。"
    "未做游戏内灯光验收与性能验收。"
)

ENTRY_NOTE = (
    "2026-09-17：由白模 v003 升为正式美术 v007 并接入运行时。"
    "v007 为单一方位布局（南/东墙中段各开 2.2×2.5 门洞，其余 10 段 5m 实墙，地面 3×3 棋盘地砖），"
    "运行时按本层实际门向整房旋转，故任意楼层共用同一套资产。" + COMMON_NOTE
)

EXIT_NOTE = (
    "2026-09-17：由白模 v003 升为正式美术 v007 并接入运行时。"
    "出口安全房与入口安全房是同一 STAIR_LOBBY 房间类型、同一 15×15m 布局，"
    "v007 单一方位资产按本层门向旋转后同时服务入口与出口，"
    "故共用 ENV-BATTLE-L01-SAFE-ENTRY 的 v007 资产，不再单独产出白模→正式美术的出口版本。" + COMMON_NOTE
)

ROWS = {
    86: [
        "ENV-BATTLE-L01-SAFE-ENTRY",
        "局内关卡01 入口安全房 15×15m 正式美术（单一方位；运行时按门向整房旋转）",
        PACKAGE_RUNTIME,
        PACKAGE_GLB,
        SOURCE_BLEND,
        "战局01入口安全房 15×15m 正式美术；单一方位布局——南/东墙中段各开 2.2×2.5 门洞，"
        "其余 10 段为 5m 实墙，地面 3×3 棋盘地砖；运行时按本层实际门向把整房旋转 0/90/180/270°，"
        "任意楼层共用同一套资产，无需按方位分版本。墙/地/门引用战局区块通用组件库 v004，"
        "房间设施（14 设施 + 3 支持件，含承重底板）由 17 个房间包按各自 metadata 的 "
        "room_placement_position 摆位。",
        SCRIPT_PATH,
        "开",
        COLLISION_OWNER,
        COLLISION_WAY,
        SIZE_TEXT,
        ORIGIN_TEXT,
        "局内关卡01 / Battle（已接入）",
        "正式美术已接入",
        "v007",
        ENTRY_NOTE,
    ],
    87: [
        "ENV-BATTLE-L01-SAFE-EXIT",
        "局内关卡01 出口安全房 15×15m 正式美术（与入口安全房同源 v007，共用同一套资产）",
        PACKAGE_RUNTIME,
        PACKAGE_GLB,
        SOURCE_BLEND,
        "战局01出口安全房 15×15m 正式美术；与入口安全房同类型同布局——南/东墙中段各开 "
        "2.2×2.5 门洞，其余 10 段为 5m 实墙，地面 3×3 棋盘地砖；"
        "共用 ENV-BATTLE-L01-SAFE-ENTRY 的 v007 单一方位资产，运行时按本层门向整房旋转。"
        "墙/地/门引用战局区块通用组件库 v004，房间设施由 17 个房间包按 "
        "room_placement_position 摆位。",
        SCRIPT_PATH,
        "开",
        COLLISION_OWNER,
        COLLISION_WAY,
        SIZE_TEXT,
        ORIGIN_TEXT,
        "局内关卡01 / Battle（已接入）",
        "正式美术已接入",
        "v007",
        EXIT_NOTE,
    ],
}

# r92..r96：只改「使用位置 / 制作状态 / 备注」三格。
COMMON_COMPONENT_ROWS = [92, 93, 94, 95, 96]
UNUSED_M = "局内关卡01 / Battle（暂未接入）"
UNUSED_N = "组件已完成；未接入"
USED_M = "局内关卡01 / Battle（安全房 v007 已接入）"
USED_N = "组件已完成；已接入"
USED_NOTE_SUFFIX = (
    "2026-09-17：已由入口/出口安全房 v007 在运行时直接引用"
    "（DungeonRoom3D preload 本组件 PackedScene）；其余战局房间尚未接入。"
)

ROW_PAT = re.compile(r'<x:row r="(?P<r>\d+)"[^>]*>.*?</x:row>', re.S)


def row_block(xml: str, row: int):
    for m in ROW_PAT.finditer(xml):
        if int(m.group("r")) == row:
            return m.start(), m.end(), m.group(0)
    return None


def build_row(row_number: int, values) -> str:
    cells = []
    for column, value in zip(COLUMNS, values):
        cells.append(
            '<x:c r="%s%d" s="%s" t="str"><x:v>%s</x:v></x:c>'
            % (column, row_number, ROW_STYLE, escape(value))
        )
    return '<x:row r="%d" ht="%s" customHeight="1">%s</x:row>' % (
        row_number, ROW_HEIGHT, "".join(cells)
    )


def cell_body(block: str, coord: str):
    m = re.search(r'<x:c r="%s"((?:[^>]*?))(?:/>|>(.*?)</x:c>)' % coord, block, re.S)
    if not m:
        return None
    return m.group(1) or "", m.group(2) or ""


def set_cell_text(block: str, coord: str, text: str) -> str:
    """保留该格原有 s= 样式，只换文本。文本落 <x:v>（与整表既有口径一致）。"""
    m = re.search(r'<x:c r="%s"((?:[^>]*?))(?:/>|>(.*?)</x:c>)' % coord, block, re.S)
    if not m:
        raise SystemExit("找不到单元格 %s" % coord)
    style_m = re.search(r'\ss="(\d+)"', m.group(1))
    style = ' s="%s"' % style_m.group(1) if style_m else ""
    new_cell = '<x:c r="%s"%s t="str"><x:v>%s</x:v></x:c>' % (coord, style, escape(text))
    return block[: m.start()] + new_cell + block[m.end():]


def main() -> int:
    apply = "--apply" in sys.argv
    if not os.path.isfile(LEDGER):
        raise SystemExit("ledger not found: %s" % LEDGER)

    with zipfile.ZipFile(LEDGER) as archive:
        members = archive.infolist()
        payloads = {info.filename: archive.read(info.filename) for info in members}

    raw = payloads[SHEET_MEMBER].decode("utf-8")
    patched = raw

    # ---------- r86 / r87 整行重建 ----------
    for row_number in sorted(ROWS):
        values = ROWS[row_number]
        found = row_block(patched, row_number)
        if not found:
            raise SystemExit("sheet10 找不到目标行 r%d" % row_number)
        s, e, block = found
        old_ids = re.findall(r'<x:v>(ENV-[^<]*)</x:v>', block)
        if not old_ids or old_ids[0] != values[0]:
            raise SystemExit("r%d 的 AssetID 不符：表内=%s 期望=%s"
                             % (row_number, old_ids[:1], values[0]))
        new_block = build_row(row_number, values)
        if block == new_block:
            print("r%-4d %-32s 已是最新，跳过" % (row_number, values[0]))
            continue
        patched = patched[:s] + new_block + patched[e:]
        print("r%-4d %-32s 整行重建 -> %s / %s"
              % (row_number, values[0], values[14], values[13]))

    # ---------- r92..r96 三格补丁 ----------
    for row_number in COMMON_COMPONENT_ROWS:
        found = row_block(patched, row_number)
        if not found:
            raise SystemExit("sheet10 找不到目标行 r%d" % row_number)
        s, e, block = found
        aid = (re.findall(r'<x:v>(ENV-[^<]*)</x:v>', block) or ["?"])[0]
        if not aid.startswith("ENV-BATTLE-COMMON-"):
            raise SystemExit("r%d 不是战局通用组件行：%s" % (row_number, aid))

        m_body = cell_body(block, "M%d" % row_number)
        n_body = cell_body(block, "N%d" % row_number)
        p_body = cell_body(block, "P%d" % row_number)
        old_m = re.sub(r".*<x:v>(.*?)</x:v>.*", r"\1", m_body[1], flags=re.S) if m_body else ""
        old_n = re.sub(r".*<x:v>(.*?)</x:v>.*", r"\1", n_body[1], flags=re.S) if n_body else ""
        old_p = re.sub(r".*<x:v>(.*?)</x:v>.*", r"\1", p_body[1], flags=re.S) if p_body else ""

        new_block = block
        notes = []
        if old_m != USED_M:
            new_block = set_cell_text(new_block, "M%d" % row_number, USED_M)
            notes.append("M:%s -> %s" % (old_m, USED_M))
        if old_n != USED_N:
            new_block = set_cell_text(new_block, "N%d" % row_number, USED_N)
            notes.append("N:%s -> %s" % (old_n, USED_N))
        if USED_NOTE_SUFFIX not in old_p:
            new_p = old_p.rstrip() + USED_NOTE_SUFFIX
            new_block = set_cell_text(new_block, "P%d" % row_number, new_p)
            notes.append("P:追加接入说明")

        if new_block == block:
            print("r%-4d %-36s 已是最新，跳过" % (row_number, aid))
            continue
        patched = patched[:s] + new_block + patched[e:]
        print("r%-4d %-36s %s" % (row_number, aid, "; ".join(notes)))

    if patched == raw:
        print("\nSHEET 内容无变化，无需写盘")
        return 0

    if not apply:
        print("\n[dry-run] 未落盘。sheet10.xml %d -> %d bytes。加 --apply 执行。"
              % (len(raw), len(patched)))
        return 0

    # 复验：仍是合法 XML，且行数不变，且 r86/r87 的 AssetID 仍在
    import xml.etree.ElementTree as ET
    ET.fromstring(patched)
    n_before = len(re.findall(r"<x:row ", raw))
    n_after = len(re.findall(r"<x:row ", patched))
    assert n_before == n_after, "行数变了：%d -> %d" % (n_before, n_after)
    for row_number in (86, 87):
        vals = re.findall(r'<x:v>(ENV-[^<]*)</x:v>',
                          row_block(patched, row_number)[2])
        assert vals and vals[0] == ROWS[row_number][0], "r%d AssetID 丢失" % row_number

    backup = LEDGER + BACKUP_SUFFIX
    shutil.copy2(LEDGER, backup)
    payloads[SHEET_MEMBER] = patched.encode("utf-8")
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as out:
        for info in members:
            out.writestr(info, payloads[info.filename])

    print("\nbackup: %s" % backup)
    print("rows kept: %d" % n_after)
    print("sheet10.xml: %d -> %d bytes" % (len(raw), len(patched)))
    print("LEDGER_SAFE_ROOM_V007_UPDATED rows=[86, 87] + common runtime status [92..96]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
