# -*- coding: utf-8 -*-
"""外科式 XML 补丁：第 57 行 ENV-TOWER-WALL-DOOR-5M 由 v004 升到 v005（双面装饰）。

背景：v004 只有房内侧（Godot +Z）有装饰，走廊侧（−Z）是平整结构背——玩家站在
走廊里看到的是一块素板。v005 在派生脚本里把装饰面绕基准面（Blender y=0）镜像
一份到背面，做成两面都有效果。

只改 M / N / O / P / T / W / Y 七个 <c>，不新增行、不动范围引用、不动 R/S：
  · M —— 资产版本 v004 -> v005
  · N —— 描述改为双面包络 5×11.9×0.683m（两面各前凸 0.3415）
  · O —— 稳定路径不变（原样回写，便于幂等核对）
  · P —— 派生链路换成 v005 blend + v005 派生脚本
  · T —— GLB 实测 SHA-256（d5fd5a75… -> 473a2d18…）
  · W —— 追加「，v005 双面」
  · Y —— 追加 2026-09-19 v005 说明段
其余 zip 条目字节原样复制。

用法：
    python patch_ledger_door_row57_v005.py            # dry-run
    python patch_ledger_door_row57_v005.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_场景账本_v001.xlsx")
BACKUP_SUFFIX = ".bak_tower_wall_door_5m_v005"
SHEET_ASSET = "xl/worksheets/sheet3.xml"
ROW = 57
ASSET_ID = "ENV-TOWER-WALL-DOOR-5M"

OLD_HASH = "d5fd5a75043ade71536759d16aab6c08fa29f525c8219f8c52c7e94926ddff84"
NEW_HASH = "473a2d18971202580e37823da026f53528774b527a307b05517a45aaf73cb8e0"

M_OLD = "v004"
M_NEW = "v005"
N_NEW = (
    "GLB / 可视包络 5×11.9×0.683m（双面装饰，两侧各前凸 0.3415；结构阻挡 0.30m）/ "
    "门洞净空 2.2×2.5m / 12m逻辑碰撞 / 共享Mesh / 可旋转"
)
O_NEW = "assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d.glb"
P_NEW = (
    "assets/art/environments/tower_descent_3d/source/wall_height12/"
    "env_tower_wall_door_5m_source_v005.blend; "
    "assets/art/environments/tower_descent_3d/source/wall_height12/"
    "export_env_tower_wall_door_5m_v005.py; "
    "assets/art/environments/tower_zones/battle/source/common_components/v007/"
    "env_battle_common_components_source_v007.blend; "
    "assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn; "
    "src/world3d/DungeonRoom3D.gd"
)
W_OLD = "Blender 派生（自 v007 通用门墙组件）"
W_NEW = "Blender 派生（自 v007 通用门墙组件，v005 双面）"

Y_APPEND = (
    "\n2026-09-19（v005）：门墙改为**双面装饰**。用户原话「我发现这个墙会连着走廊，"
    "做成两面都有效果的，直接复制一个镜像一下，在blender里头制作，完成后重新导入」。"
    "v004 只有房内侧（Godot +Z）有装饰，走廊侧（−Z）是一块平整结构背，玩家站在走廊里"
    "看过去是素板。v005 在派生脚本里新增 mirror_decoration 阶段：在 yaw 烘焙与三角化"
    "之后、朝下剔面之前，把「位于结构面前侧（Blender y ≤ −0.152，结构面 −0.15 加 2mm "
    "切割容差）」的装饰面复制一份，用 Mirror 修改器绕 y=0 基准面（网格中心线）翻转后"
    "与原网格 join。"
    "（grep 关键词：DOOR_V005_DERIVE_REPORT / DOOR_V005_DERIVE_CONTRACT_FAILED / "
    "DOOR_V005_GLB_VERIFY_FAILED / DOOR_V005_EXPORT_CONTRACT_FAILED / DERIVE_OK / "
    "EXPORT_OK / PREFAB_DOOR_WALL_OK / DOOR_WALL_RUNTIME_OK / DOOR_WALL_VISUAL_OK。）"
    "Mirror 必须 use_mirror_merge=false、use_clip=false——门洞隧道与背壳横跨 y=0，"
    "开启合并会把它们粘在基准面上、开启裁剪会把它们钉死；关掉这两项后修改器自动翻转"
    "绕向，镜像面法线朝外，无需手工 flip。**整物体镜像不可行**：会与保留的背板共面闪烁，"
    "并把门洞复制成两条，所以切割后只复制装饰面。"
    "实测：装饰面/侧 7883 面（剔贴地面后 7799），镜像新增 7883（1:1）；跨侧共面孪生 0"
    "（源本身有 132 组薄片双面写法，镜像后恰好 264 组，未新增）；包络 Blender "
    "y∈[−0.3415, +0.3415]（Godot z 同值），关于 z=0 对称；门洞射线三向复测：±X 净宽 2.2、"
    "+Z 净高 2.5、±Y 贯穿厚度无阻挡（clear_through_thickness=true）——镜像面没有把门洞堵死；"
    "门楣底面仍在（朝下面只剔贴地一层 GROUND_BAND_M=0.05，保留 2734 个、删 200 个，"
    "断言「lintel underside was culled」挡住回退）。"
    "⚠️ float32 陷阱：镜像后顶点以 float32 存盘，面色心/法线会差约 1e-5，任何基于色心的"
    "逐项比对（排序后 zip、容差桶贪心匹配）都会误报「不对称」（本次曾误报 911 条、再误报 "
    "29 条）。改用两个对 float32 逐位稳定的不变量：① 顶点位置键多重集（镜像只翻 abs(y)，"
    "逐位精确）② 向量面积相对偏差（抓绕向反转）——实测 position_key_mismatches=0、"
    "area_delta=0.0，两侧顶点位置多重集差异为 0。"
    "⚠️ 退化面陷阱：源含 24 个零面积面（area<1e-9），其法线是数值垃圾，会让「朝下面」的"
    "阈值计数在存盘/重载之间翻转（实测 1367/1368）。已在统计中排除并单独报告 "
    "degenerate_zero_area_faces=24，门楣保留断言加 DOWN_FACE_COUNT_TOLERANCE=4 容差"
    "（门楣是否存在由门洞射线精确证明，不靠计数）。"
    "实测：GLB 1,147,372 B（v004 为 581,392 B）/ sha256 473a2d18…；4 个材质角色"
    "（01_精工金属_紫色骨架 / 02_细腻哑光_青绿大面 / 03_清漆反光_紫粉点缀 / "
    "04_柔和自发光_UI灯光）全部保留；prefab 声明 asset_version=v005、"
    "visual_bounds_size_m=(5,11.9,0.683)、新增 metadata/double_sided=true；"
    "bounds_size_m 仍为 (5,11.9,0.3)（结构阻挡量，刻意与可视包络分离）。"
    "门禁：PREFAB_CONTRACT_OK count=6；TOWER_GRID_COMPONENT_ALIGNMENT_OK；"
    "TOWER_PALETTE_VISIBLE_OK；PREFAB_DOOR_WALL_OK；DOOR_WALL_RUNTIME_OK（递归探针实测 "
    "120 个模块中塔楼 A 套 118 个全部包络 ±0.3415 双面对称、4 表面）；"
    "DOOR_WALL_VISUAL_OK captured=4。"
    "画面取证（probe_door_wall_visual，v004 → v005）：房内侧保持 7 层亮度分层 / 细节能量 "
    "0.0015 不变（v004 与 v005 房内侧图做像素比对，平均通道差 0.04/255，判定「几乎同一画面」）；"
    "走廊侧 2 层 / 0.0004 → 6 层 / 0.0018（×4.5）；两侧能量比 4.247 → 0.829，即真正"
    "「两面都有效果」。走廊侧图与房内侧图互为左右镜像（B1 标牌、警示三角、门楣黄黑警示条"
    "全部左右翻转），水平翻转后平均通道差 1.59 → 0.96/255（v004 基线翻转前后 2.75→2.73，"
    "毫无变化——素背板翻转等于没翻）；门洞近景仍通透、仰视门楣底面仍在。"
    "接线：**未改任何运行时代码**——门洞净空 2.2×2.5 与 TowerGeometry3D."
    "DOOR_CLEAR_WIDTH_M / DOOR_CLEAR_HEIGHT_M 及 DungeonRoom3D._add_tower_wall_collision() "
    "的脚本碰撞代理逐值一致，碰撞代理与门洞口径无需改动；"
    "节点名前缀 Imported_DoorWall5M_* 仍被基地99层设施门墙（ENV-BASE99-WALL-DOOR-5X12，"
    "自身包络 1.051m 深）共用，核对须按 asset_id 过滤。"
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
    cur_t = (cell_text(asset, "T%d" % ROW, shared) or "").strip()
    cur_w = (cell_text(asset, "W%d" % ROW, shared) or "").strip()
    cur_y = cell_text(asset, "Y%d" % ROW, shared) or ""

    # 状态前置检查：不满足即拒改，避免在错误前提上落盘。
    if cur_m != M_OLD:
        raise SystemExit("M%d is %r, expected %r" % (ROW, cur_m, M_OLD))
    if cur_t != OLD_HASH:
        raise SystemExit("T%d is %r, expected the v004 hash %r" % (ROW, cur_t, OLD_HASH))
    if cur_w != W_OLD:
        raise SystemExit("W%d is %r, expected %r" % (ROW, cur_w, W_OLD))
    if "v005" in cur_y and "双面装饰" in cur_y:
        raise SystemExit("Y%d already carries the v005 note — 拒绝重复追加" % ROW)

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
