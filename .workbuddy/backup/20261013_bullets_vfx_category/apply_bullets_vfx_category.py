#!/usr/bin/env python3
"""特效账本新增「子弹特效」大类并登记 9 条逐弹种弹体特效。

一次性、幂等拒绝重跑的登记脚本（前置断言必须全部成立，否则直接退出 1）。

改动面
------
特效账本 ShellStorm2_特效账本_v001.xlsx
  1. 《资产主表》追加 9 行（1 条补登的通用弹体父体 + 8 条逐弹种专属特效），r26..r34
  2. 重写 R/S 派生列，区间覆盖 r6..r34
  3. 重建 C/K/L 三张下拉（用 CATEGORY_VALUES / STATUS_VALUES / PRIORITY_VALUES 权威常量）
     与 S/K 条件格式、auto_filter，范围全部扩到 r34
  4. 《总览》大类表新增「子弹特效」行，合计行下移一行，8 处公式区间 $25 → $34
  5. 《账本说明》覆盖大类 → 「特效 / 子弹特效」
  6. 《域变更日志》追加 v0.1.14
  7. 《3D-特效》分页**刻意不动**（摘要锁死表；且 9 条里 8 条尚无 PackedScene）

主目录 ShellStorm2_美术资产台账_v001.xlsx
  1. 《分账本索引》特效行 D11/E11 → 「特效 / 子弹特效」/ 2
  2. 《总览》大类表插入「子弹特效」行（归属域=特效）
  3. 《分类与编码》追加 VFX/子弹特效 一行
  4. 《版本记录》追加 v0.2.3（跨域变更）
"""

from __future__ import annotations

import sys
from copy import copy
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.formatting.formatting import ConditionalFormattingList
from openpyxl.formatting.rule import Rule
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path("/Users/summercards/Documents/ShellStorm2")
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))

from ledger_registry import LedgerIndex  # noqa: E402
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CATEGORY_VALUES,
    CF_DONE,
    CF_REPEAT,
    CF_TODO,
    COLUMN_COUNT,
    FIRST_DATA_ROW,
    HEADER_ROW,
    PRIORITY_VALUES,
    STATUS_VALUES,
    dedupe_key_formula,
    dedupe_result_formula,
    sheet_digest,
)

VFX_PATH = ROOT / "assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx"
MASTER_PATH = ROOT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
VFX_PAGE = "3D-特效"
DATE = "2026-10-13"
TS = f"{DATE} 00:00:00"
ROW_HEIGHT = 15.0

OLD_LAST = 25          # 改动前的末数据行
NEW_ROWS = 9           # 追加行数
NEW_LAST = OLD_LAST + NEW_ROWS   # 34

BULLET_VISUAL_SHA = "a3c84c7e8842369fee46a224880589f1470e2beb68b2205a5ad41c4659832685"
CONTENT_DB = "docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx#武器"
DESIGN_DOC = "docs/v0.1/04_技术施工_战斗与局内成长.md"
PARTIAL = "[部分完成] 实例尾号、槽位、已装配件与命运刻印已可视；逐条专属VFX/音频仍待QA"

# 弹种顺序逐字取自 src/base/BlueprintRegistry.gd 的 8 条 _register_bullet（161-211 行）。
# (type, 中文名, 内容库《武器》行号, 内容库 S 列设计原文, BULLET_COLORS 取值)
BULLETS = [
    ("standard", "标准子弹弹体与尾迹特效", "标准子弹模块", 17,
     "使用清晰中性弹体、尾迹和命中；不附加误导性的元素效果",
     "Color(0.76, 0.86, 0.92)", "kinetic;standard",
     "子弹特效;标准子弹;标准弹;中性弹体;尾迹;kinetic;standard;3D", "flight_neutral"),
    ("sticky", "黏黏弹附着与倒计时特效", "黏黏弹模块", 18,
     "命中后弹体留在表面并显示倒计时/状态，结束时反馈与结算同步",
     "Color(0.32, 0.92, 0.62)", "sticky;dot",
     "子弹特效;黏黏弹;附着;倒计时;持续伤害;sticky;dot;3D", "attach_countdown"),
    ("bounce", "回旋镖弹反弹折线与计数特效", "回旋镖弹模块", 13,
     "反弹点有折线闪光与计数递减，飞行方向变化清楚可读",
     "Color(0.30, 0.70, 1.0)", "bounce;ricochet",
     "子弹特效;回旋镖弹;反弹;弹跳;折线闪光;计数递减;ricochet;3D", "bounce_ricochet"),
    ("piercing", "穿甲弹贯穿线与层数特效", "穿甲弹模块", 16,
     "穿透命中显示连续贯穿线与剩余层数，不在首个目标处假性消失",
     "Color(1.0, 0.78, 0.22)", "piercing;armor",
     "子弹特效;穿甲弹;穿透;贯穿线;剩余层数;piercing;armor;3D", "pierce_through"),
    ("explosive", "爆炸弹弹体与爆炸时点特效", "爆炸弹模块", 14,
     "弹体、尾迹、爆炸半径与伤害时点同步，低特效下保留轮廓圈",
     "Color(1.0, 0.28, 0.08)", "explosive;area",
     "子弹特效;爆炸弹;范围伤害;爆炸半径;伤害时点;低特效轮廓圈;explosive;area;3D", "flight_to_detonate"),
    ("homing", "蜂卵弹锁定框与弯曲尾迹特效", "蜂卵弹模块", 15,
     "锁定框、弯曲尾迹和转向动作一致；目标丢失有解除提示",
     "Color(0.50, 1.0, 0.42)", "homing;summon",
     "子弹特效;蜂卵弹;追踪;锁定框;弯曲尾迹;解除提示;homing;3D", "homing_curve"),
    ("blackhole", "黑洞弹核心与吸入流线特效", "黑洞弹模块", 12,
     "黑洞核心、吸入流线和范围边界清晰；命中/结束有收束反馈",
     "Color(0.68, 0.25, 0.95)", "blackhole;pull",
     "子弹特效;黑洞弹;黑洞核心;吸入流线;范围边界;收束反馈;pull;3D", "blackhole_pull"),
    ("balloon", "气球弹膨胀弹体与命中体积特效", "气球弹模块", 11,
     "膨胀弹体、较重尾迹与命中体积一致，不能只改伤害数值",
     "Color(0.98, 0.35, 0.72)", "balloon;big",
     "子弹特效;气球弹;膨胀弹体;命中体积;低速;balloon;big;3D", "inflate_flight"),
]

SHARED_ID = "VFX-BULLET-VISUAL-3D"


def build_rows() -> list[list]:
    """构造 9 行 25 列内容（R/S 先留 None，稍后统一按权威函数写入）。"""
    rows: list[list] = []

    # --- r26：通用弹体父体（由 3D-特效 分页 FX01-06 补登） -----------------
    shared = [None] * COLUMN_COUNT
    shared[0] = SHARED_ID
    shared[1] = "飞行子弹通用弹体视觉（共用父体）"
    shared[2] = "子弹特效"
    shared[3] = "bullet_shared"
    shared[4] = "FX01-06"
    shared[5] = "root_3d"
    shared[6] = None
    shared[7] = "俯视3D"
    shared[8] = "flight"
    shared[9] = "玩家/敌人飞行子弹"
    shared[10] = "已完成"
    shared[11] = "P0"
    shared[12] = "v001"
    shared[13] = "PackedScene/程序几何（铂金亮芯胶囊 + 弹色半透明外壳 + 沿弹道拖尾锥 + 跟随灯）"
    shared[14] = "assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn"
    shared[15] = "src/vfx/VfxBulletVisual3D.gd; src/combat3d/Projectile3D.gd"
    shared[16] = "子弹;弹体;尾迹;飞行;投射物;projectile;bullet;3D;共用弹体"
    shared[19] = BULLET_VISUAL_SHA
    shared[20] = "摩斯拉"
    shared[21] = TS
    shared[22] = "原创程序几何"
    shared[23] = "FX01-06"
    shared[24] = (
        "由《3D-特效》分页 FX01-06 补登进《资产主表》——该 Prefab 此前只登记在分页，主表缺行，"
        "与「《资产主表》＝唯一登记源」的口径不符。宿主唯一生命周期：由 Projectile3D 作为子节点持有，"
        "随 ProjectilePool3D 回收；刻意不进 VfxPool3D 注册表，避免弹体池与特效池双重所有权（见 14.6 §… 与 "
        "skill vfx-combat-effect-authoring）。本行同时是 8 个弹种专属弹体特效的变体父体（G 列指向本 AssetID），"
        "弹种专属 Prefab 落地后仍复用本行的弹芯/外壳/拖尾几何分层，仅按弹种替换外观与行为段。"
    )
    rows.append(shared)

    # --- r27..r34：逐弹种专属特效（待制作） --------------------------------
    for slug, cn_name, module_cn, src_row, s_text, color, tags, keywords, anim in BULLETS:
        row = [None] * COLUMN_COUNT
        row[0] = f"VFX-BULLET-{slug.upper()}-3D"
        row[1] = cn_name
        row[2] = "子弹特效"
        row[3] = f"bullet_{slug}"
        row[4] = f"mod_bullet_{slug}"
        row[5] = "root_3d"
        row[6] = SHARED_ID
        row[7] = "俯视3D"
        row[8] = anim
        row[9] = f"{module_cn}（mod_bullet_{slug}）"
        row[10] = "待制作"
        row[11] = "P1"
        row[12] = "v001"
        row[13] = "待定（弹体 / 尾迹 / 命中三段；程序几何或动画序列）"
        row[14] = "待定"
        row[15] = (
            f"{DESIGN_DOC} §6.2（子弹模块必填 visual_id）; "
            f"{CONTENT_DB} S{src_row}/T{src_row}; "
            f"src/base/BlueprintRegistry.gd（mod_bullet_{slug}）"
        )
        row[16] = keywords
        row[19] = None
        row[20] = "待分配"
        row[21] = TS
        row[22] = "待制作/原创程序几何"
        row[23] = None
        row[24] = (
            f"设计依据（内容库《武器》S{src_row} 原文）：「{s_text}」；"
            f"内容库 T{src_row}：{PARTIAL}。"
            f"当前该弹种只有 WeaponModel3D.BULLET_COLORS 的配色区分（mod_bullet_{slug} = {color}，标签 {tags}），"
            "无专属 Prefab；本行即为该弹种专属弹体/尾迹/命中特效的排产入口。"
            "制成后必须在《3D-特效》分页登记实际存在的 PackedScene、回填 O 列路径与 T 列 SHA-256，"
            "并把本行 K 列推进到「已完成」。"
        )
        rows.append(row)

    return rows


def require(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"前置断言失败: {msg}")


def bump_range(formula: str, old_last: int, new_last: int, ref: str) -> str:
    require(isinstance(formula, str) and formula.startswith("="), f"{ref} 不是公式: {formula!r}")
    require(f"${old_last}" in formula, f"{ref} 不含 ${old_last}: {formula!r}")
    return formula.replace(f"${old_last}", f"${new_last}")


def main() -> int:
    index = LedgerIndex.load(ROOT)
    domain = index.domain_for_key("vfx")
    require(domain.categories == ("特效", "子弹特效"), f"vfx 大类不是两项: {domain.categories}")
    require(("VFX", "子弹特效") in index.prefix_pairs(), "缺少 (VFX, 子弹特效) 前缀对")

    wb = load_workbook(VFX_PATH)
    page_before = sheet_digest(wb[VFX_PAGE])

    # ------------------------------------------------------------------ 前置断言
    require(wb.sheetnames == ["总览", "账本说明", ASSET_SHEET, VFX_PAGE, "域变更日志"],
            f"页签不符: {wb.sheetnames}")
    main_ws = wb[ASSET_SHEET]
    rows_before = [(r, v) for r, v in _read(main_ws)]
    require(len(rows_before) == 20, f"资产主表行数不是 20: {len(rows_before)}")
    require(rows_before[-1][0] == OLD_LAST, f"末数据行不是 {OLD_LAST}: {rows_before[-1][0]}")
    require(main_ws.cell(row=HEADER_ROW, column=1).value == "AssetID", "表头行不是 5")
    for r, v in rows_before:
        require(str(v[0]) != SHARED_ID, f"{SHARED_ID} 已在资产主表 r{r}，不能重复补登")

    ov = wb["总览"]
    for ref in ("A6", "C6", "E6", "G6"):
        require(f"${OLD_LAST}" in str(ov[ref].value), f"总览 {ref} 区间不是 ${OLD_LAST}")
    require(ov["A10"].value == "特效" and ov["A11"].value == "合计", "总览大类表结构不符")

    # ------------------------------------------------------- 1. 追加 9 行资产
    new_rows = build_rows()
    style_pending = copy(main_ws.cell(row=10, column=1)._style)     # 未实现/占位行的形态
    style_done = copy(main_ws.cell(row=21, column=1)._style)        # 已完成 3D 行的形态
    h_pending = main_ws.row_dimensions[10].height or ROW_HEIGHT
    h_done = main_ws.row_dimensions[21].height or ROW_HEIGHT

    for offset, values in enumerate(new_rows):
        r = OLD_LAST + 1 + offset
        prefix = style_done if values[0] == SHARED_ID else style_pending
        for col in range(1, COLUMN_COUNT + 1):
            cell = main_ws.cell(row=r, column=col)
            cell.value = values[col - 1]
            cell._style = copy(prefix)
        main_ws.row_dimensions[r].height = h_done if values[0] == SHARED_ID else h_pending

    # --------------------------------------------- 2/3. 派生列 / 下拉 / 条件格式
    for r in range(FIRST_DATA_ROW, NEW_LAST + 1):
        main_ws.cell(row=r, column=18).value = dedupe_key_formula(r)
        main_ws.cell(row=r, column=19).value = dedupe_result_formula(r, NEW_LAST)

    main_ws.data_validations.dataValidation.clear()
    for col, values in ((3, CATEGORY_VALUES), (11, STATUS_VALUES), (12, PRIORITY_VALUES)):
        dv = DataValidation(type="list", formula1='"' + ",".join(values) + '"',
                            allow_blank=True, showDropDown=False, showErrorMessage=False)
        main_ws.add_data_validation(dv)
        dv.add(f"{get_column_letter(col)}{FIRST_DATA_ROW}:{get_column_letter(col)}{NEW_LAST}")

    main_ws.conditional_formatting = ConditionalFormattingList()
    main_ws.conditional_formatting.add(
        f"S{FIRST_DATA_ROW}:S{NEW_LAST}",
        Rule(type="containsText", operator="containsText", text="重复", dxf=CF_REPEAT, priority=1))
    main_ws.conditional_formatting.add(
        f"K{FIRST_DATA_ROW}:K{NEW_LAST}",
        Rule(type="containsText", operator="containsText", text="已完成", dxf=CF_DONE, priority=2))
    main_ws.conditional_formatting.add(
        f"K{FIRST_DATA_ROW}:K{NEW_LAST}",
        Rule(type="containsText", operator="containsText", text="待制作", dxf=CF_TODO, priority=3))
    main_ws.auto_filter.ref = f"A{HEADER_ROW}:Y{NEW_LAST}"

    # ------------------------------------------------------------- 4. 总览改写
    for ref in ("A6", "C6", "E6", "G6"):
        ov[ref] = bump_range(str(ov[ref].value), OLD_LAST, NEW_LAST, ref)

    old_b10 = bump_range(str(ov["B10"].value), OLD_LAST, NEW_LAST, "B10")
    old_c10 = bump_range(str(ov["C10"].value), OLD_LAST, NEW_LAST, "C10")
    ov["B10"] = old_b10
    ov["C10"] = old_c10
    style_cat = copy(ov["A10"]._style)
    for col in range(1, 11):
        ov.cell(row=10, column=col)._style = copy(style_cat)

    # 分页统计标题行在第 13 行且跨列合并；先拆掉再下移，否则 A13 是 MergedCell 不可写
    require("A13:J13" in [str(r) for r in ov.merged_cells.ranges], "总览 A13:J13 合并区不存在")
    ov.unmerge_cells("A13:J13")

    # 旧 r11..r16（合计行 + Prefab 统计块）整体下移一行
    shifted = {}
    for r in range(11, 17):
        shifted[r] = [(ov.cell(row=r, column=c).value, copy(ov.cell(row=r, column=c)._style))
                      for c in range(1, 11)]
    heights = {r: ov.row_dimensions[r].height for r in range(11, 17)}
    for r in range(11, 18):
        for c in range(1, 11):
            cell = ov.cell(row=r, column=c)
            cell.value = None
            cell._style = copy(style_cat)

    require(old_b10.count("A10") == 1 and old_c10.count("A10") == 1, "总览 C10/SUMPRODUCT 结构异常")
    ov["A11"] = "子弹特效"
    ov["B11"] = old_b10.replace("A10", "A11")
    ov["C11"] = old_c10.replace("A10", "A11")
    for col in range(1, 11):
        ov.cell(row=11, column=col)._style = copy(style_cat)
    ov.row_dimensions[11].height = ov.row_dimensions[10].height or ROW_HEIGHT

    # 合计行：改为覆盖两个大类的 SUM（原 `COUNTIF(…,A11)` 对文本「合计」恒为 0，是坏公式）
    style_total = copy(shifted[11][0][1])
    ov["A12"] = "合计"
    ov["B12"] = "=SUM(B10:B11)"
    ov["C12"] = "=SUM(C10:C11)"
    for col in range(1, 11):
        ov.cell(row=12, column=col)._style = copy(style_total)
    ov.row_dimensions[12].height = heights[11] or ROW_HEIGHT

    for old_r in range(12, 17):
        new_r = old_r + 1
        for c in range(1, 11):
            value, style = shifted[old_r][c - 1]
            cell = ov.cell(row=new_r, column=c)
            cell.value = value
            cell._style = copy(style)
        ov.row_dimensions[new_r].height = heights[old_r]
    ov["B17"] = "=SUM(B16)"
    ov["C17"] = "=SUM(C16)"
    ov["D17"] = "=SUM(D16)"
    ov["E17"] = "=SUM(E16)"

    ov.merge_cells("A14:J14")

    # ---------------------------------------------------------- 5. 账本说明
    note = wb["账本说明"]
    require(note["B8"].value == "特效", f"账本说明 B8 不是「特效」: {note['B8'].value!r}")
    note["B8"] = "特效 / 子弹特效"

    # ------------------------------------------------------- 6. 域变更日志
    log = wb["域变更日志"]
    log_row = log.max_row + 1
    log_style = copy(log.cell(row=log.max_row, column=1)._style)
    entry = [
        "v0.1.14", DATE, "新增大类 + 新增条目", "特效 / 子弹特效",
        "新增域内第二大类「子弹特效」：逐弹种专属弹体/尾迹/命中特效各占一行，"
        "8 个弹种（标准/黏黏弹/回旋镖弹/穿甲弹/爆炸弹/蜂卵弹/黑洞弹/气球弹）全部为「待制作」，"
        "以内容库《武器》S 列表现要求与 04 §6.2 子弹模块 visual_id 契约为设计依据；"
        "同时把原只登记在《3D-特效》分页的通用弹体 VFX-BULLET-VISUAL-3D 补登进《资产主表》并作为 8 条的变体父体。"
        "同步：C 列下拉加入新大类、S 列查重区间与总览公式区间 $25→$34、条件格式与 auto_filter 扩到 r34；"
        "《3D-特效》分页刻意未改（8 条尚无 PackedScene，且该页一行 = 一个实际存在的 PackedScene）。",
        "稳定 AssetID 与既有 Prefab 路径不变；《3D-特效》逐格不变；"
        "主目录《分账本索引》特效行大类数 1→2、《分类与编码》新增一行；纯登记变更，不改玩法数值与运行时行为。",
        "CodeBuddy",
    ]
    for i, value in enumerate(entry, start=1):
        cell = log.cell(row=log_row, column=i)
        cell.value = value
        cell._style = copy(log_style)
    log.row_dimensions[log_row].height = 46

    # --------------------------------------------------------------- 主目录
    mwb = load_workbook(MASTER_PATH)
    idx_ws = mwb["分账本索引"]
    d_row = FIRST_DATA_ROW + [d.key for d in index.domains].index("vfx")
    require(idx_ws.cell(row=d_row, column=2).value == "特效", "分账本索引定位失败")
    idx_ws.cell(row=d_row, column=4).value = "特效 / 子弹特效"
    idx_ws.cell(row=d_row, column=5).value = 2

    mov = mwb["总览"]
    require(mov["A16"].value == "特效", f"主总览特效行不在 r16: {mov['A16'].value!r}")
    center_row = 17
    mh16 = mov.row_dimensions[16].height or ROW_HEIGHT
    mshift = {}
    for r in range(center_row, 21):
        mshift[r] = [(mov.cell(row=r, column=c).value, copy(mov.cell(row=r, column=c)._style))
                     for c in range(1, 11)]
    mheights = {r: mov.row_dimensions[r].height for r in range(center_row, 21)}
    for r in range(center_row, 22):
        for c in range(1, 11):
            mov.cell(row=r, column=c).value = None
    for old_r in range(center_row, 21):
        new_r = old_r + 1
        for c in range(1, 11):
            value, style = mshift[old_r][c - 1]
            cell = mov.cell(row=new_r, column=c)
            cell.value = value
            cell._style = copy(style)
        mov.row_dimensions[new_r].height = mheights[old_r]
    style_src = copy(mov.cell(row=16, column=1)._style)
    for i, value in enumerate(["子弹特效", "特效",
                               "assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx",
                               NEW_ROWS], start=1):
        cell = mov.cell(row=center_row, column=i)
        cell.value = value
        cell._style = copy(style_src)
    mov.row_dimensions[center_row].height = mh16

    enc = mwb["分类与编码"]
    require(enc["A13"].value == "VFX" and enc["B13"].value == "特效", "分类与编码 VFX 行不在 r13")
    enc_row = 17
    enc_style = copy(enc.cell(row=13, column=1)._style)
    for i, value in enumerate([
        "VFX", "子弹特效",
        "standard / sticky / bounce / piercing / explosive / homing / blackhole / balloon",
        "assets/art/vfx/combat_3d/",
        "vfx_bullet_{type}_root_top3d_v{nnn}.tscn",
        "VFX-BULLET-STANDARD-3D",
    ], start=1):
        cell = enc.cell(row=enc_row, column=i)
        cell.value = value
        cell._style = copy(enc_style)

    relog = mwb["版本记录"]
    relog_row = relog.max_row + 1
    relog_style = copy(relog.cell(row=relog.max_row, column=1)._style)
    relog_entry = [
        "v0.2.3", DATE, "新增大类", "特效域 / 子弹特效",
        "特效域新增第二大类「子弹特效」，登记 8 个弹种的专属弹体/尾迹/命中特效（均待制作）"
        "并把通用弹体 VFX-BULLET-VISUAL-3D 补登进《资产主表》作为其变体父体。"
        "同步《分账本索引》特效行（覆盖大类 → 特效 / 子弹特效、大类数 → 2）与《分类与编码》新增 VFX/子弹特效 前缀行。",
        "AssetID、既有 Prefab 路径与运行时行为不变；总目录仍不持有资产行；"
        "《总览》新行的「条数」为当前值（9），其余自动作行的条数仍为 2026-09-23 拆分快照。",
        "CodeBuddy",
    ]
    for i, value in enumerate(relog_entry, start=1):
        cell = relog.cell(row=relog_row, column=i)
        cell.value = value
        cell._style = copy(relog_style)
    relog.row_dimensions[relog_row].height = 46

    # ------------------------------------------------- 回读自检（内存，通过才落盘）
    check = wb
    cws = check[ASSET_SHEET]
    data_rows = [r for r, _v in _read(cws)]
    require(data_rows == list(range(FIRST_DATA_ROW, NEW_LAST + 1)),
            f"回读末行不是 {NEW_LAST}: {data_rows[-1]}")
    for r in data_rows:
        require(cws.cell(row=r, column=18).value == dedupe_key_formula(r), f"R{r} 形状错")
        require(cws.cell(row=r, column=19).value == dedupe_result_formula(r, NEW_LAST), f"S{r} 形状错")
    cov = check["总览"]
    for ref in ("A6", "C6", "E6", "G6", "B10", "C10", "B11", "C11"):
        require(f"${NEW_LAST}" in str(cov[ref].value), f"回读总览 {ref} 区间错")
    require(sheet_digest(check[VFX_PAGE]) == page_before, "《3D-特效》分页被改动，违反摘要锁死")
    require(len(check[ASSET_SHEET].data_validations.dataValidation) == 3, "下拉数量不是 3")

    # --------------------------------------------------------------- 落盘
    wb.save(VFX_PATH)
    mwb.save(MASTER_PATH)

    # 落盘后再做一次跨进程回读，确认公式与摘要真的进了 zip
    final = load_workbook(VFX_PATH)
    fws = final[ASSET_SHEET]
    frows = [r for r, _v in _read(fws)]
    require(frows == data_rows, f"落盘后行集合不一致: {frows[-1]}")
    fov = final["总览"]
    for ref in ("A6", "C6", "E6", "G6", "B10", "C10", "B11", "C11"):
        require(f"${NEW_LAST}" in str(fov[ref].value), f"落盘后总览 {ref} 区间错")
    require(sheet_digest(final[VFX_PAGE]) == page_before, "落盘后《3D-特效》被改动")
    fdv = sorted(str(dv.sqref) for dv in fws.data_validations.dataValidation)
    require(fdv == [f"C{FIRST_DATA_ROW}:C{NEW_LAST}", f"K{FIRST_DATA_ROW}:K{NEW_LAST}",
                    f"L{FIRST_DATA_ROW}:L{NEW_LAST}"], f"落盘后下拉区间错: {fdv}")
    require(fws.auto_filter.ref == f"A{HEADER_ROW}:Y{NEW_LAST}", "落盘后筛选区间错")

    print("APPLY_OK rows", len(frows), "last", frows[-1], "page_digest", page_before[:12])
    return 0


def _read(ws):
    from split_asset_ledger import read_source_rows
    return read_source_rows(ws)


if __name__ == "__main__":
    raise SystemExit(main())
