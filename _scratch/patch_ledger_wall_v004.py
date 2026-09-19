# -*- coding: utf-8 -*-
"""外科式 XML 补丁：把场景分账本里 ENV-TOWER-WALL-SOLID-5M 的登记从 v003 升到 v004。

为什么走 XML 补丁而不是整本往返：
  分账本里带 ① 表对象 xl/tables/table1.xml ② 数据校验 ③ 派生列 R/S 的数组公式
  ④ 逐格样式 s=??。整本 openpyxl / Office 引擎往返有扰动这些的风险；
  这里只替换目标行的目标 <c> 元素，其余 zip 条目字节原样复制。

写法沿用项目既有范式（patch_ledger_tower_modules.py）：
  文本格 -> t="inlineStr"（不新增 sharedStrings 条目，避免改 count/uniqueCount）；
  数值格（V55 更新时间）-> 保持数值型，不带 t 属性。

用法：
    python patch_ledger_wall_v004.py            # dry-run，只打印将要写入的差异
    python patch_ledger_wall_v004.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import html as _html
import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_场景账本_v001.xlsx")
BACKUP_SUFFIX = ".bak_wall_solid_5m_v004"

SHEET_ASSET = "xl/worksheets/sheet3.xml"    # 资产主表
SHEET_COMMON = "xl/worksheets/sheet4.xml"   # 3D-场景通用
SHARED = "xl/sharedStrings.xml"

TODAY_SERIAL = 46284  # 2026-09-19（Excel 1900 日期序列）

Y55_APPEND = (
    "\n2026-09-19：可视网格换为 v004（自 battle/common_components v007「wall_standard_5m_通用包」派生，"
    "派生脚本 assets/art/environments/tower_descent_3d/source/wall_height12/export_env_tower_wall_solid_5m_v004.py）。"
    "Blender 内对根节点烘焙 180° 偏航后 transform_apply，使装饰面落在 Godot +Z"
    "（与 prp_tower_* A 套 forward_axis=\"+Z\" 对齐）；先三角化再删朝下面（去 1095 面）、join 成单 Mesh，"
    "丢掉无几何的 03_清漆反光_紫粉点缀 槽，只留 01/02/04 三个共享色盘角色。"
    "稳定路径 GLB 原地覆盖（文件名去版本号），节点名统一 ENV_TOWER_WALL_SOLID_5M，根变换为单位矩阵"
    "（该 GLB 被 TowerDescent3D 直接 preload，根变换会直接决定走廊墙位置）。"
    "阻挡不动：结构碰撞仍 0.30m 代理，可视包络 5×11.9×0.4675m（正面装甲凸到 +Z 0.3175）。"
)

R55 = {
    "M": "v004",
    "N": "GLB / 可视包络 5×11.9×0.4675m（结构阻挡 0.30m）/ 12m逻辑碰撞 / 共享Mesh / 可旋转",
    "O": "assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d.glb",
    "P": (
        "assets/art/environments/tower_descent_3d/source/wall_height12/env_tower_wall_solid_5m_source_v004.blend; "
        "assets/art/environments/tower_descent_3d/source/wall_height12/export_env_tower_wall_solid_5m_v004.py; "
        "assets/art/environments/tower_zones/battle/source/common_components/v007/"
        "env_battle_common_components_source_v007.blend; "
        "assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn; src/world3d/TowerGeometry3D.gd"
    ),
    "T": "0bca134eef74148f0df444d72afff769974863cab6fec4ca885b773186649fb9",
    "W": "Blender 派生（自 v007 通用实墙组件）",
}

P48 = (
    "2026-09-17：占位 BoxMesh 替换为正式美术（与 100F/98F 同源同版）。"
    "根节点=PrpTowerWallSolid5m(Node3D)，下挂 ImportedModel；Prefab 视觉专用（visual_only），"
    "结构碰撞由 DungeonRoom3D.TowerWallCollision_*_Run 与 TowerFloorStage3D.OuterBoundaryCollision_* 按 0.30m 代理生成。"
    "资产声明 preserve_authored_palette=true——塔楼 MultiMesh 不再套 WALL_SOLID_MATERIAL_A/B 单色主题，"
    "保留美术自带 PaletteUV（共享色盘角色 01_精工金属_紫色骨架 / 02_细腻哑光_青绿大面 / 04_柔和自发光_UI灯光）。"
    "原点契约 bottom_center（几何 Y=0..11.9），运行时按 -mesh.get_aabb().position.y 反算贴合楼面。"
    "\n2026-09-19：升 v004。GLB 原地覆盖稳定路径（文件名去版本号，节点名统一 ENV_TOWER_WALL_SOLID_5M，根变换为单位矩阵）。"
    "结构包络与可视包络分离：bounds_size_m 仍 5×11.9×0.30（结构阻挡），"
    "visual_bounds_size_m=5×11.9×0.4675（正面装甲凸到 +Z 0.3175，背面 -0.15）。"
    "跨套朝向：Blender 侧 +Y 为厚度轴，B 套（battle/common_components，含 v007）装饰面在 -Y，"
    "导出前烘焙 180° 使装饰面落 Godot +Z，与 A 套 prp_tower_* 的 forward_axis=\"+Z\" 对齐。"
    "该 GLB 除本 Prefab 外还被 TowerDescent3D 直接 preload"
    "（_get_corridor_wall_module_mesh / _build_stair_approach_corridor），故根节点变换必须为单位矩阵。"
)

R48 = {
    "E": (
        "assets/art/environments/tower_descent_3d/source/wall_height12/env_tower_wall_solid_5m_source_v004.blend"
        "（派生自 assets/art/environments/tower_zones/battle/source/common_components/v007/"
        "env_battle_common_components_source_v007.blend）"
    ),
    "K": "GLB / 可视包络 5×11.9×0.4675m（结构阻挡 0.30m）/ 12m逻辑碰撞 / 共享Mesh",
    "O": "v004",
    "P": P48,
}

CELL_RE = re.compile(r'<c r="(?P<ref>[A-Z]+\d+)"(?P<attrs>[^>]*?)(?:/>|>.*?</c>)', re.S)


def cell_block(xml: str, ref: str):
    for m in CELL_RE.finditer(xml):
        if m.group("ref") == ref:
            return m.start(), m.end(), m.group(0)
    return None


def style_of(block: str) -> str:
    m = re.search(r'\ss="(\d+)"', block)
    return ' s="%s"' % m.group(1) if m else ""


def text_cell(ref: str, style: str, text: str) -> str:
    return '<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (ref, style, escape(text))


def number_cell(ref: str, style: str, value: int) -> str:
    return '<c r="%s"%s><v>%d</v></c>' % (ref, style, value)


def patch_row(xml: str, row: int, edits: dict[str, str]):
    log = []
    for col, text in edits.items():
        ref = "%s%d" % (col, row)
        found = cell_block(xml, ref)
        if not found:
            raise SystemExit("cell %s not found" % ref)
        start, end, block = found
        new = text_cell(ref, style_of(block), text)
        log.append("  %-4s [%s] -> inlineStr(%d chars) %s" % (ref, style_of(block).strip(), len(text), text[:48]))
        xml = xml[:start] + new + xml[end:]
    return xml, log


def shared_value(blobs, index: int) -> str:
    sis = re.findall(r"<si>(.*?)</si>", blobs[SHARED].decode("utf-8"), re.S)
    return _html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", sis[index], re.S)))


def main() -> int:
    apply = "--apply" in sys.argv
    with zipfile.ZipFile(LEDGER) as z:
        names = z.namelist()
        infos = {n: z.getinfo(n) for n in names}
        blobs = {n: z.read(n) for n in names}

    asset = blobs[SHEET_ASSET].decode("utf-8")
    common = blobs[SHEET_COMMON].decode("utf-8")

    m = re.search(r'<c r="Y55"[^>]*t="s"><v>(\d+)</v></c>', asset)
    if not m:
        raise SystemExit("Y55 shared-string cell not found")
    y_old = shared_value(blobs, int(m.group(1)))

    edits55 = dict(R55)
    edits55["Y"] = y_old + Y55_APPEND

    found = cell_block(asset, "V55")
    if not found:
        raise SystemExit("V55 not found")
    s, e, blk = found
    print("== %s row 55 ==" % SHEET_ASSET)
    print("  V55  [%s] -> number %d" % (style_of(blk).strip(), TODAY_SERIAL))
    asset2, log1 = patch_row(asset[:s] + number_cell("V55", style_of(blk), TODAY_SERIAL) + asset[e:], 55, edits55)
    for line in log1:
        print(line)

    common2, log2 = patch_row(common, 48, R48)
    print("== %s row 48 ==" % SHEET_COMMON)
    for line in log2:
        print(line)

    if not apply:
        print("\n[dry-run] 未落盘。加 --apply 执行。")
        return 0

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    print("\n备份 -> %s" % backup.name)

    blobs[SHEET_ASSET] = asset2.encode("utf-8")
    blobs[SHEET_COMMON] = common2.encode("utf-8")
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            zi = zipfile.ZipInfo(n, date_time=infos[n].date_time)
            zi.compress_type = infos[n].compress_type
            zi.external_attr = infos[n].external_attr
            z.writestr(zi, blobs[n])
    print("已写回 %s" % LEDGER.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
