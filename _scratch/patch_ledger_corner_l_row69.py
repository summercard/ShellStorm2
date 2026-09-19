# -*- coding: utf-8 -*-
"""外科式 XML 补丁：把场景分账本《资产主表》第 69 行 ENV-TOWER-CORNER-L-5M 升级为塔楼 A 套正式美术。

为什么是「升级既有行」而不是「追加新行」：
  该 AssetID 早在 2026-08-18 就已登记（第 69 行，塔楼L型转角5米），当时挂的是**程序化 BoxMesh
  占位**，登记路径还停留在 base_facility 的 99F 资产上。本次是把同一件资产的**可视本体**换成
  tower_descent_3d 的 A 套正式 GLB——身份不变，改的是内容。AssetID 是稳定身份，不得换行重建。

  同批的 8.4 墙体（ENV-TOWER-WALL-SOLID-5M，第 55 行）走的也是「升级既有行」这条路。

范围引用**一律不动**：本次不新增行，表还是 236 行数据（6..241），
  dimension / autoFilter / table1 ref / 条件格式 / 数据校验 / 总览 末行引用 / $R$6:$R$241 全部保持不变。

只改第 69 行的指定 <c>，其余 zip 条目字节原样复制。

用法：
    python patch_ledger_corner_l_row69.py            # dry-run，只打印将要写入的差异
    python patch_ledger_corner_l_row69.py --apply    # 落盘（先自动备份）
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
BACKUP_SUFFIX = ".bak_corner_l_5m_row69"

SHEET_ASSET = "xl/worksheets/sheet3.xml"    # 资产主表
SHARED = "xl/sharedStrings.xml"

ROW = 69
TODAY_SERIAL = 46284  # 2026-09-19（Excel 1900 日期序列）

# 对齐塔楼 A 套兄弟行（第 55 行实心墙 / 第 241 行门扇）的登记范式
R69 = {
    "D": "room_kit",
    "E": "tower_descent",
    "F": "corner_l_5m",
    "H": "俯视3D",
    "I": "godot_runtime",
    "K": "原型已接入",
    "L": "P0",
    "M": "v001",
    "N": (
        "GLB / 可视包络 5.15×11.9×5.3175m（原点=转角，两臂向 +X/-Z 伸出）/ "
        "结构占地 5×11.9×5m / 单 Mesh 三材质角色 / 自带两臂碰撞"
    ),
    "O": "assets/art/environments/tower_descent_3d/components/env_tower_corner_l_5m_top3d.glb",
    "P": (
        "assets/art/environments/tower_descent_3d/source/corner_l_5m/"
        "export_env_tower_corner_l_5m_v001.py; "
        "assets/art/props/dungeon_3d/prp_corner_l_5m.tscn; src/world3d/DungeonRoom3D.gd; "
        "assets/art/props/dungeon_3d/qa/verify_tower_module_prefabs.gd"
    ),
    "Q": "塔楼L型转角5米;12米逻辑墙;11.9米可见墙;PaletteUV;L墙角;corner_l;bottom_corner",
    "T": "297ffb52654c5ea187565d64357f2b4bcdd83fc7c5fe5343979a1c50d54c9527",
    "W": "Blender 派生（由两份通用墙刚性拼成）",
}

Y69_APPEND = (
    "\n2026-09-19：可视本体换成塔楼 A 套正式美术（grep 关键词：bottom_corner / CORNER_L_V001）。"
    "稳定 AssetID 不变，仍 ENV-TOWER-CORNER-L-5M；prefab 仍是 assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"
    "（DungeonRoom3D.TOWER_CORNER_L_PREFAB，非 FACILITY 房间的四个转角）。"
    "本次把原来的程序化 BoxMesh 占位换成 A 套正式 GLB，做法是**由两份同一通用墙刚性拼成**而非单独建模："
    "取自与实心墙同源的包 battle/source/common_components/v007（包 wall_standard_5m_通用包 / 根件 "
    "ROOT_wall_standard_5m_通用组件）。摆位：长臂 T(+2.5,0,0) 沿 +X 覆盖 0..5m，短臂 T(0,+2.5,0)@Rz(90°) 沿 -Z 覆盖 -5..0m；"
    "两臂先在烘焙坐标系内各自完成 triangulate→删朝下面，再刚性复制两次，逐臂断言 5319 三角面 == 通用墙、"
    "L 合计 10638 == 2×墙，因此与直墙逐面一致。装饰面朝外（长臂 Godot +Z、短臂 Godot +X）。"
    "原点契约由 bottom_center 变为 bottom_corner（原点=转角，两臂向 +X/-Z 伸出）："
    "DungeonRoom3D._spawn_room_corner() 直接摆到房间角点再按 NW/NE/SW/SE 旋转，把几何重新居中会让所有房间角错位；"
    "统一契约门禁 verify_tower_module_prefabs.gd 为此新增 bottom_corner 识别。"
    "本件是六件通用物体里唯一自带碰撞的件（visual_only=false / collision_owner=self）："
    "prefab 内两个 StaticBody3D（WallCollisionLong / WallCollisionShort，12m 高 0.30m 厚）的节点名是 "
    "_configure_corner_camera_collisions() 的镜头下压契约，改名即回归。"
    "保留美术自带共享色盘（01 精工金属_紫色骨架 / 02 细腻哑光_青绿大面 / 04 柔和自发光_UI灯光；空槽 03 已丢）。"
    "版本提法：本行 M 由 v004 改为 v001 —— 旧值 v004 属于 base_facility(99F) 那条派生线，"
    "本件的稳定 GLB 改走 tower_descent_3d/source/corner_l_5m/ 的 v001 线，与实心墙 v004 / 门扇 v001 同口径。"
    "原登记的 O/P 指向 base_facility_3d 的 env_base99_corner_l_5m（99F 那条线，运行时由 "
    "BASE99_CORNER_L_PREFAB 承担 FACILITY 房间），与塔楼 prefab 无关，本次一并纠正。"
    "注意：新生成 GLB 的 .import 不会自动绑定 scene_facility_shared_palette_post_import.gd，"
    "缺绑定会渲染成白板且不触发任何 *_OK 门禁，需手工绑定。"
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
    return '<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (ref, style, escape(text))


def shared_value(blobs, index: int) -> str:
    sis = re.findall(r"<si>(.*?)</si>", blobs[SHARED].decode("utf-8"), re.S)
    return _html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", sis[index], re.S)))


def cell_text(blobs, xml: str, ref: str) -> str | None:
    """读出某个格子的显示文本：inlineStr 直接取，共享字符串查表。"""
    found = cell_block(xml, ref)
    if not found:
        return None
    block = found[2]
    m = re.search(r'<v>(\d+)</v>', block)
    if 't="s"' in block and m:
        return shared_value(blobs, int(m.group(1)))
    m2 = re.search(r"<t[^>]*>(.*?)</t>", block, re.S)
    return _html.unescape(m2.group(1)) if m2 else None


def esc_formula(text: str) -> str:
    """按本账本第 69 行既有写法转义公式：& -> &amp;，\" -> &quot;，> -> &gt;。"""
    return text.replace("&", "&amp;").replace('"', "&quot;").replace(">", "&gt;")


def patch_cell(xml: str, ref: str, make) -> tuple[str, str]:
    found = cell_block(xml, ref)
    if not found:
        raise SystemExit("cell %s not found" % ref)
    start, end, block = found
    new = make(ref, style_of(block), block)
    return xml[:start] + new + xml[end:], block


def main() -> int:
    apply = "--apply" in sys.argv
    with zipfile.ZipFile(LEDGER) as z:
        names = z.namelist()
        infos = {n: z.getinfo(n) for n in names}
        blobs = {n: z.read(n) for n in names}

    asset = blobs[SHEET_ASSET].decode("utf-8")

    # 断言本行身份未被替换成别的资产
    cur_id = cell_text(blobs, asset, "A%d" % ROW)
    if cur_id != "ENV-TOWER-CORNER-L-5M":
        raise SystemExit("row %d is not ENV-TOWER-CORNER-L-5M (got %r)" % (ROW, cur_id))

    # 现有 Y69 用于追加
    y_old = cell_text(blobs, asset, "Y%d" % ROW)
    if y_old is None:
        raise SystemExit("Y%d not found" % ROW)
    if "2026-09-19：可视本体换成塔楼 A 套正式美术" in y_old:
        raise SystemExit("Y%d already carries the 2026-09-19 note — 拒绝重复追加" % ROW)

    log = []
    edits = dict(R69)
    edits["Y"] = y_old + Y69_APPEND

    for col, text in edits.items():
        ref = "%s%d" % (col, ROW)
        asset, blk = patch_cell(asset, ref, lambda r, s, _b, t=text: text_cell(r, s, t))
        log.append("  %-4s [%s] -> inlineStr(%d chars) %s" % (ref, style_of(blk).strip(), len(text), text[:44]))

    # R 查重键：公式 + 缓存值同步（公式结果的拼接键随 D/E/F/H/I 变化）
    new_r_formula = ('=LOWER(TRIM(C%d)&"|"&TRIM(D%d)&"|"&TRIM(E%d)&"|"&TRIM(F%d)&"|"&TRIM(H%d)&"|"&TRIM(I%d))'
                     % (ROW, ROW, ROW, ROW, ROW, ROW))
    new_r_value = "场景|room_kit|tower_descent|corner_l_5m|俯视3d|godot_runtime"

    def make_r(ref: str, style: str, _blk: str) -> str:
        return ('<c r="%s"%s t="str"><f>%s</f><v>%s</v></c>'
                % (ref, style, esc_formula(new_r_formula), escape(new_r_value)))

    asset, blk_r = patch_cell(asset, "R%d" % ROW, make_r)
    log.append("  %-4s [%s] -> 查重键公式/缓存值同步 -> %s" % ("R%d" % ROW, style_of(blk_r).strip(), new_r_value))

    # V 更新时间
    asset, blk_v = patch_cell(asset, "V%d" % ROW,
                              lambda r, s, _b: '<c r="%s"%s><v>%d</v></c>' % (r, s, TODAY_SERIAL))
    log.append("  %-4s [%s] -> number %d" % ("V%d" % ROW, style_of(blk_v).strip(), TODAY_SERIAL))

    # S 列公式不得被破坏（范围引用本次不动）
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
