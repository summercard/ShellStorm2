# -*- coding: utf-8 -*-
"""外科式 XML 补丁：第 57 行 ENV-TOWER-WALL-DOOR-5M 换成通用组件派生美术。

背景：门墙原先的可视本体来自塔楼旧套件 env_tower_descent_kit_top3d_v007.blend 的
集合 10D_MOD_WALL_DOOR_5M_U01（本行 W 列原文即「程序生成 Blender 源集合」），
41,760 B、没有共享色盘、.import 连 post_import 脚本都没绑。现改为自战局通用组件库
v007 的 wall_door_5m_通用包派生到塔楼 A 套，与实心墙 v004 同一套做法。

只改 M / N / O / P / T / W / Y 七个 <c>，不新增行、不动范围引用：
  · M —— 资产版本 v003 -> v004
  · N —— 描述改为新来源 + 可视包络 5×11.9×0.4915m + 门洞净空 2.2×2.5m
  · O —— 路径由带版本号的 _v003.glb 改为稳定路径（运行时实际引用的那条）
  · P —— 源 blend / 派生脚本 / 通用组件源 / prefab / 代码
  · T —— GLB 实测 SHA-256（a78cbb01… -> d5fd5a75…）
  · W —— 「程序生成 Blender 源集合」->「Blender 派生（自 v007 通用门墙组件）」
  · Y —— 追加 2026-09-19 替换说明段
其余 zip 条目字节原样复制。

用法：
    python patch_ledger_door_row57_v004.py            # dry-run
    python patch_ledger_door_row57_v004.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_场景账本_v001.xlsx")
BACKUP_SUFFIX = ".bak_tower_wall_door_5m_v004"
SHEET_ASSET = "xl/worksheets/sheet3.xml"
ROW = 57
ASSET_ID = "ENV-TOWER-WALL-DOOR-5M"

OLD_HASH = "a78cbb01866ee86984535ab0168c6cf23439f03f78a97ca84ac4e062cdb542bc"
NEW_HASH = "d5fd5a75043ade71536759d16aab6c08fa29f525c8219f8c52c7e94926ddff84"

M_NEW = "v004"
N_NEW = (
    "GLB / 可视包络 5×11.9×0.4915m（结构阻挡 0.30m）/ 门洞净空 2.2×2.5m / "
    "12m逻辑碰撞 / 共享Mesh / 可旋转"
)
O_NEW = "assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d.glb"
P_NEW = (
    "assets/art/environments/tower_descent_3d/source/wall_height12/"
    "env_tower_wall_door_5m_source_v004.blend; "
    "assets/art/environments/tower_descent_3d/source/wall_height12/"
    "export_env_tower_wall_door_5m_v004.py; "
    "assets/art/environments/tower_zones/battle/source/common_components/v007/"
    "env_battle_common_components_source_v007.blend; "
    "assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn; "
    "src/world3d/DungeonRoom3D.gd"
)
W_NEW = "Blender 派生（自 v007 通用门墙组件）"

Y_APPEND = (
    "\n2026-09-19：可视本体由「塔楼旧套件程序生成源」换成战局通用组件派生美术"
    "（grep 关键词：DOOR_V004_DERIVE_REPORT / DOOR_V004_APERTURE_FAILED / "
    "PREFAB_DOOR_WALL_OK / DOOR_WALL_VISUAL_OK）。"
    "旧 GLB 出自 env_tower_descent_kit_top3d_v007.blend 的集合 10D_MOD_WALL_DOOR_5M_U01"
    "（本行 W 列原值即「程序生成 Blender 源集合」）：41,760 B、方块门垛+门楣、"
    "没有 PaletteUV、.import 里 import_script/path 为空且 embedded_image_handling=1，"
    "游离在共享色盘体系之外——同批其它塔楼构件（实墙/门扇/L 墙角）都已绑定。"
    "新资产自 tower_zones/battle/source/common_components/v007 的 wall_door_5m_通用包"
    "（ROOT_wall_door_5m_通用组件 + 主体_输出 4410 面 + UI灯光_柔和自发光 182 面）派生："
    "绕竖轴 180°（美术自述正面在 Blender +Y，经 YUP 会落到 Godot -Z，而塔楼 A 套硬要求 "
    "forward_axis=+Z）后把偏移烘焙进顶点、ROOT 空物体丢弃、两网格合并为单 Mesh、"
    "12 个审阅场景塌缩为 1 个。"
    "朝下面剔除刻意只剔「贴地」那一层：门墙有门楣，其底面朝下且位于净高 2.5m 处，"
    "照实墙那样全剔会让玩家仰头看穿墙体；实测删掉 116 个地面封口面、保留 1376 个高于"
    "地面的朝下面，派生脚本内置断言（lintel underside was culled）挡住回退。"
    "门洞净空不采信源文件自报包络，改用射线从门洞内部实测复核：净宽 2.2（±1.1）、"
    "净高 2.5（门楣底），与 TowerGeometry3D.DOOR_CLEAR_WIDTH_M / DOOR_CLEAR_HEIGHT_M "
    "及 DungeonRoom3D._add_tower_wall_collision() 的脚本碰撞代理逐值一致，"
    "故碰撞代理与门洞口径无需改动。"
    "实测：GLB 581,392 B / sha256 d5fd5a75…；4 个材质角色（01/02/03/04）全部有面、"
    "无空槽；.import 已绑 tools/asset_pipeline/scene_facility_shared_palette_post_import.gd "
    "且 embedded_image_handling=0，探针实测四个表面 albedo_texture=true（色盘真的生效）；"
    "可视包络 5×11.9×0.4915（装饰面朝房内 Godot +Z 凸到 0.3415、结构背 -0.15）；"
    "PREFAB_CONTRACT_OK count=6；TOWER_GRID_COMPONENT_ALIGNMENT_OK；"
    "TOWER_PALETTE_VISIBLE_OK（各房间 Imported_DoorWall5M_* 全部 override=null 且无残留门扇）；"
    "运行时递归探针实测 118 个塔楼门墙模块全部 4 表面 / AABB=(5,11.9,0.4915) / 装饰面朝 +Z；"
    "DOOR_WALL_VISUAL_OK captured=4（房内侧/外侧细节能量比 4.247，外侧为纯平板无装饰）；"
    "PREFAB_DOOR_WALL_OK（无静态门扇、无内嵌碰撞）。"
    "程序生成旧资产自带的那片静态门扇 DoorLeaf_OPEN 随重导出消失（通用包本来就不含门扇），"
    "qa/probe_tower_palette_visible.gd 的对应断言已由「必须隐藏」反转为「必须不存在」。"
    "注：节点名前缀 Imported_DoorWall5M_* 被两条路径共用——基地99层设施房走 "
    "ENV-BASE99-WALL-DOOR-5X12（自身包络 1.051m 深），核对时须按 asset_id 区分，"
    "否则会拿 A 套契约量出假失败。"
)

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
    return '<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (
        ref, style, escape(text)
    )


def shared_value(shared_xml: str, index: int) -> str:
    import html as _html
    sis = re.findall(r"<si>(.*?)</si>", shared_xml, re.S)
    return _html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", sis[index], re.S)))


def cell_text(xml: str, ref: str, shared_xml: str = "") -> str | None:
    """inlineStr 直接取 <t>；共享字符串（t="s"）查 sharedStrings 表。"""
    import html as _html
    found = cell_block(xml, ref)
    if not found:
        return None
    block = found[2]
    if 't="s"' in block:
        m = re.search(r"<v>(\d+)</v>", block)
        if not m:
            return None
        return shared_value(shared_xml, int(m.group(1)))
    m = re.search(r"<t[^>]*>(.*?)</t>", block, re.S)
    return _html.unescape(m.group(1)) if m else None


def main() -> int:
    apply = "--apply" in sys.argv
    with zipfile.ZipFile(LEDGER) as z:
        names = z.namelist()
        infos = {n: z.getinfo(n) for n in names}
        blobs = {n: z.read(n) for n in names}

    asset = blobs[SHEET_ASSET].decode("utf-8")
    shared = blobs["xl/sharedStrings.xml"].decode("utf-8")

    cur_id = cell_text(asset, "A%d" % ROW, shared)
    if cur_id != ASSET_ID:
        raise SystemExit("row %d is not %s (got %r)" % (ROW, ASSET_ID, cur_id))

    cur_m = (cell_text(asset, "M%d" % ROW, shared) or "").strip()
    cur_o = (cell_text(asset, "O%d" % ROW, shared) or "").strip()
    cur_t = (cell_text(asset, "T%d" % ROW, shared) or "").strip()
    cur_w = (cell_text(asset, "W%d" % ROW, shared) or "").strip()
    cur_y = cell_text(asset, "Y%d" % ROW, shared) or ""

    # 状态前置检查：不满足即拒改，避免在错误前提上落盘。
    if cur_m != "v003":
        raise SystemExit("M%d is %r, expected v003" % (ROW, cur_m))
    if not cur_o.endswith("env_tower_wall_door_5m_top3d_v003.glb"):
        raise SystemExit("O%d is %r, expected the versioned v003 path" % (ROW, cur_o))
    if cur_t != OLD_HASH:
        raise SystemExit("T%d is %r, expected the legacy hash %r" % (ROW, cur_t, OLD_HASH))
    if cur_w != "程序生成 Blender 源集合":
        raise SystemExit("W%d is %r, expected the procedural-source label" % (ROW, cur_w))
    if "2026-09-19" in cur_y and "通用门墙组件" in cur_y:
        raise SystemExit("Y%d already carries the 2026-09-19 v004 note — 拒绝重复追加" % ROW)

    log = []
    for col, text in (
        ("M", M_NEW),
        ("N", N_NEW),
        ("O", O_NEW),
        ("P", P_NEW),
        ("T", NEW_HASH),
        ("W", W_NEW),
        ("Y", cur_y + Y_APPEND),
    ):
        found = cell_block(asset, "%s%d" % (col, ROW))
        if not found:
            raise SystemExit("cell %s%d not found" % (col, ROW))
        start, end, block = found
        asset = asset[:start] + text_cell("%s%d" % (col, ROW), style_of(block), text) + asset[end:]
        log.append("  %-4s [%s] -> inlineStr(%d chars) %s" % (
            "%s%d" % (col, ROW), style_of(block).strip(), len(text), text[:44]))

    # S 列公式与范围引用本次不动，做一次结构自检
    s_block = cell_block(asset, "S%d" % ROW)
    if not s_block or "COUNTIF($R$6:$R$241,R%d)" % ROW not in s_block[2]:
        raise SystemExit("S%d formula shape unexpected" % ROW)

    if not apply:
        for line in log:
            print(line)
        print("\n[dry-run] 未落盘。加 --apply 执行。")
        return 0

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    print("备份 -> %s" % backup.name)

    blobs[SHEET_ASSET] = asset.encode("utf-8")
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            zi = zipfile.ZipInfo(n, date_time=infos[n].date_time)
            zi.compress_type = infos[n].compress_type
            zi.external_attr = infos[n].external_attr
            z.writestr(zi, blobs[n])
    for line in log:
        print(line)
    print("已写回 %s" % LEDGER.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
