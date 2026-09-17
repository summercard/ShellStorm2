# -*- coding: utf-8 -*-
"""外科式 XML 补丁：把 4 个塔楼模块 Prefab 已在台账「3D-场景通用」中的登记
从「原型已接入 / 当前Prefab尚未直接引用」更新为「正式美术已接入 / 已直接引用」。

沿用上一轮（wall_door_5m / common_components_v004）的既有范式：
只改 xl/worksheets/sheet10.xml 里目标行的目标单元格，其余 zip 条目原样复制，
不触碰 styles.xml / table1.xml / 其它 sheet，避免 openpyxl 往返丢样式。

用法：
    python patch_ledger_tower_modules.py            # dry-run，只打印将要写入的内容
    python patch_ledger_tower_modules.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx")
SHEET_XML = "xl/worksheets/sheet10.xml"
SHEET_TITLE = "3D-场景通用"
BACKUP_SUFFIX = ".bak_tower_modules_prefab"

# (row, column) -> 新文本
EDITS: dict[tuple[int, str], str] = {
    # ---- r42 ENV-TOWER-FLOOR-TILE-5M ----
    (42, "C"): "assets/art/props/dungeon_3d/prp_tower_floor_tile_5m_v001.tscn",
    (42, "D"): "assets/art/environments/tower_descent_3d/components/floor_tile_5m/env_tower_floor_tile_5m_top3d_v002.glb",
    (42, "E"): "assets/art/environments/tower_descent_3d/source/floor_tile_5m/env_tower_floor_tile_5m_source_v002.blend",
    (42, "I"): "TowerFloorStage3D.FloorSupport",
    (42, "J"): "BoxShape3D 5×0.30×5m，由 FloorSupport 按槽位生成（Prefab 不再自带碰撞）",
    (42, "K"): "GLB / 5×5×0.3005m / 共享Mesh / MultiMesh平铺",
    (42, "L"): "centered_slab（板厚居中；可视顶面与承重面 Y=0 对齐）",
    (42, "N"): "正式美术已接入",
    (42, "O"): "v002",
    (42, "P"): (
        "2026-09-17：占位 BoxMesh 替换为正式美术 env_tower_floor_tile_5m_top3d_v002.glb"
        "（与 100F/98F 同源同版）。根节点=PrpTowerFloorTile5m(Node3D)，下挂 ImportedModel 引用该 GLB；"
        "Prefab 原 FloorTileCollision 已移除，承重碰撞由 TowerFloorStage3D.FloorSupport 生成。"
        "资产声明 preserve_authored_palette=true，运行时不再用暖色 A/B 主题地砖材质覆盖，"
        "保留美术自带双表面 PaletteUV。原点契约 centered_slab，运行时按 -FLOOR_THICKNESS*0.5 偏移对齐承重面 Y=0。"
    ),
    # ---- r45 ENV-TOWER-WALL-DOOR-5M ----
    (45, "C"): "assets/art/props/dungeon_3d/prp_tower_wall_door_5m_v001.tscn",
    (45, "I"): "Prefab自身（3×BoxShape3D 代理）+ DungeonRoom3D",
    (45, "J"): "3×BoxShape3D：左/右门柱 1.4×12×0.30（x=∓1.8）+ 门楣 2.2×9.5×0.30（y 底=2.5），门洞镂空可通行",
    (45, "L"): "bottom_center（几何 Y=0..11.9）；朝 +Z",
    (45, "N"): "正式美术已接入",
    (45, "O"): "v003",
    (45, "P"): (
        "2026-09-17：占位 BoxMesh 替换为正式美术 env_tower_wall_door_5m_top3d_v003.glb。"
        "根节点=PrpTowerWallDoor5m(Node3D)，下挂 ImportedModel；美术自带静态门扇 DoorLeaf_OPEN 置 visible=false，"
        "门扇改由运行时 RoomDoor3D.DoorPanel 提供（与基地99层带门墙同规范，GLB 只作墙体/门框）。"
        "保留原 3×BoxShape3D 碰撞代理（门柱 2 + 门楣 1，门洞镂空可通行）。"
        "资产声明 preserve_authored_palette=true，保留美术自带材质，不再用塔楼暖色 A/B 主题覆盖。"
    ),
    # ---- r46 ENV-TOWER-WALL-PARAPET-5M ----
    (46, "C"): "assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m_v001.tscn",
    (46, "D"): "assets/art/environments/tower_descent_3d/components/env_tower_wall_parapet_5m_top3d_v001.glb",
    (46, "E"): "10C_MOD_WALL_PARAPET_5M_U01（Blender 集合）；export_env_tower_5m_modules_v001.py",
    (46, "I"): "TowerFloorStage3D",
    (46, "J"): "BoxShape3D 5×1.5×0.30，由 OuterBoundaryCollision 按槽位生成（Prefab 不再自带碰撞）",
    (46, "L"): "bottom_center（几何 Y=0..1.50）；朝 +Z",
    (46, "N"): "正式美术已接入",
    (46, "O"): "v001",
    (46, "P"): (
        "2026-09-17：占位 BoxMesh 替换为正式美术 env_tower_wall_parapet_5m_top3d_v001.glb。"
        "根节点=PrpTowerWallParapet5m(Node3D)，下挂 ImportedModel；Prefab 视觉专用（visual_only），"
        "楼顶四周边界碰撞由 TowerFloorStage3D.OuterBoundaryCollision 按 0.30m 代理生成。"
        "资产声明 preserve_authored_palette=true，保留美术自带 PaletteUV，不再用塔楼暖色 A/B 主题覆盖。"
        "原点契约 bottom_center（几何 Y=0..1.50）。"
    ),
    # ---- r48 ENV-TOWER-WALL-SOLID-5M ----
    (48, "C"): "assets/art/props/dungeon_3d/prp_tower_wall_solid_5m_v001.tscn",
    (48, "I"): "DungeonRoom3D + TowerFloorStage3D",
    (48, "J"): "DungeonRoom3D TowerWallCollision_*_Run 0.30m 代理；视觉走 MultiMesh，Prefab 不再自带碰撞",
    (48, "L"): "bottom_center（几何 Y=0..11.9）；朝 +Z",
    (48, "N"): "正式美术已接入",
    (48, "O"): "v003",
    (48, "P"): (
        "2026-09-17：占位 BoxMesh 替换为正式美术 env_tower_wall_solid_5m_top3d_v003.glb（与 100F/98F 同源同版）。"
        "根节点=PrpTowerWallSolid5m(Node3D)，下挂 ImportedModel；Prefab 视觉专用（visual_only），"
        "结构碰撞由 DungeonRoom3D.TowerWallCollision_*_Run 与 TowerFloorStage3D.OuterBoundaryCollision_* 按 0.30m 代理生成。"
        "资产声明 preserve_authored_palette=true——塔楼 MultiMesh 不再套 WALL_SOLID_MATERIAL_A/B 单色主题，"
        "保留美术自带 PaletteUV（MAT_Structure_DarkSteel）。"
        "原点契约 bottom_center（几何 Y=0..11.9），运行时按 -mesh.get_aabb().position.y 反算贴合楼面。"
    ),
}

COL_ORDER = {c: i for i, c in enumerate("ABCDEFGHIJKLMNOPQRST")}
ROW_PAT = re.compile(r'<x:row r="(?P<r>\d+)"[^>]*>.*?</x:row>', re.S)


def row_block(xml: str, row: int) -> tuple[int, int, str] | None:
    for m in ROW_PAT.finditer(xml):
        if int(m.group("r")) == row:
            return m.start(), m.end(), m.group(0)
    return None


def cell_pat(coord: str) -> re.Pattern[str]:
    return re.compile(r'<x:c r="%s"((?:[^>]*?))(?:/>|>.*?</x:c>)' % coord, re.S)


def build_cell(coord: str, style: str, text: str) -> str:
    return (
        '<x:c r="%s"%s t="inlineStr"><x:is><x:t xml:space="preserve">%s</x:t></x:is></x:c>'
        % (coord, style, escape(text))
    )


def apply_to_row(block: str, row: int, edits: dict[str, str]) -> str:
    for col, text in edits.items():
        coord = "%s%d" % (col, row)
        pat = cell_pat(coord)
        m = pat.search(block)
        if m:
            style_m = re.search(r'\ss="(\d+)"', m.group(1))
            style = ' s="%s"' % style_m.group(1) if style_m else ""
            block = block[: m.start()] + build_cell(coord, style, text) + block[m.end():]
        else:
            # 该列原本整格缺失：按列序插到正确位置
            insert_at = len(block)
            for other in re.finditer(r'<x:c r="([A-Z]+)\d+"', block):
                if COL_ORDER[other.group(1)] > COL_ORDER[col]:
                    insert_at = other.start()
                    break
            else:
                insert_at = block.rindex("</x:row>")
            style = ' s="192"'
            block = block[:insert_at] + build_cell(coord, style, text) + block[insert_at:]
    return block


def main() -> int:
    apply = "--apply" in sys.argv
    with zipfile.ZipFile(LEDGER) as z:
        names = z.namelist()
        blobs = {n: z.read(n) for n in names}
    xml = blobs[SHEET_XML].decode("utf-8")

    by_row: dict[int, dict[str, str]] = {}
    for (row, col), text in EDITS.items():
        by_row.setdefault(row, {})[col] = text

    # 先校验每行都能定位到，且列出原本存在的单元格
    for row, edits in sorted(by_row.items()):
        found = row_block(xml, row)
        if not found:
            print("!! row %d 未找到" % row)
            return 2
        s, e, block = found
        present = set(re.findall(r'<x:c r="([A-Z]+)\d+"', block))
        missing = [c for c in edits if c not in present]
        print("row %-3d 存在列=%s" % (row, ",".join(sorted(present, key=lambda c: COL_ORDER[c]))))
        if missing:
            print("        需新增列=%s" % ",".join(sorted(missing)))

    if not apply:
        print("\n[dry-run] 未落盘。加 --apply 执行。")
        return 0

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    print("\n备份 -> %s" % backup)

    for row, edits in sorted(by_row.items()):
        s, e, block = row_block(xml, row)
        new_block = apply_to_row(block, row, edits)
        xml = xml[:s] + new_block + xml[e:]
        print("row %d 已改写" % row)

    blobs[SHEET_XML] = xml.encode("utf-8")
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            z.writestr(n, blobs[n])
    print("已写回 %s" % LEDGER)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
