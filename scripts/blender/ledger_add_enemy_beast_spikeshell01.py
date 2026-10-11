# -*- coding: utf-8 -*-
"""登记一只新怪：ENM-BEAST-SPIKESHELL01（棘背兽）。

只做登记，不做玩法接线（业主：「作为一只新怪使用，先不考虑调用」）。

改两本表：
  1) 敌人账本 assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx
     - 《资产主表》新增 r18（唯一登记源）
     - 《总览》把写死的 $6:$17 区间统一扩到 $18（门禁要求「区间 == 本账本行数」）
     - 《域变更日志》新增 r9 / v0.1.3
  2) 游戏内容数据库 docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx
     - 《怪物与Boss》新增 r15

刻意不碰（会被逐字节摘要锁死）：
  - 《敌人动画与状态》：verify_ledger_split 断言「随域迁移的专表逐字节不变」。
    新怪暂无动作母版；等做动作时再单独一次改动 + 重建基线。
  - 《3D-敌人》：该表自己的口径是「一行 = 一个实际存在的 Godot PackedScene」，
    当前没有 Prefab，不能凭空加行。

纪律：
  - 写前逐条断言表名/表头/行号/既有公式形态，防止静默写错位置。
  - 复制样式用 copy(cell._style)，并沿用同形行的行高。
  - 查重键/查重结果公式**从 tools/asset_pipeline/split_asset_ledger.py 的
    权威函数生成**，不手写。
  - 绝不运行 tools/asset_pipeline/split_asset_ledger.py（它的 --baseline-only 会从
    已不持有资产行的主目录重建基线 ⇒ 会把 409 行基线清空）。
"""
from __future__ import annotations

import shutil
import sys
from copy import copy
from datetime import datetime
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.worksheet.cell_range import MultiCellRange

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
from split_asset_ledger import (  # noqa: E402
    FIRST_DATA_ROW,
    HEADER_ROW,
    dedupe_key_formula,
    dedupe_result_formula,
)

LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx"
CONTENT = ROOT / "docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx"
TMPDIR = Path(r"I:\工作项目\shellstrom2\_scratch\ledger_gate_cwd")

NEW_ID = "ENM-BEAST-SPIKESHELL01"
NAME = "棘背兽"
SUBCLASS = "normal_beast"
LOGIC_ID = "spike_shell"
CONTENT_ID = "monster_spike_shell"
TODAY = datetime(2026, 9, 23)
TAG = "newbeast_spikeshell"

# ============================ 0) 备份 =====================================
for src in (LEDGER, CONTENT):
    bak = src.with_name(src.name + f".bak_{TAG}")
    tmp = TMPDIR / bak.name
    shutil.copy2(src, bak)
    shutil.copy2(src, tmp)
    print(f"BACKUP {bak.name}  {bak.stat().st_size} bytes")

wb = load_workbook(LEDGER)

# ============================ 1) 前置断言 =================================
for name in ("总览", "账本说明", "资产主表", "敌人动画与状态", "3D-敌人", "域变更日志"):
    assert name in wb.sheetnames, f"sheet missing: {name}"

main = wb["资产主表"]
assert main.cell(HEADER_ROW, 1).value == "AssetID", main.cell(HEADER_ROW, 1).value
assert main.cell(HEADER_ROW, 18).value == "查重键"
assert main.cell(HEADER_ROW, 19).value == "查重结果"
assert main.max_row == HEADER_ROW + 12, f"预期 12 行数据(r6:r17)，实际 max_row={main.max_row}"
assert main.cell(17, 1).value == "ENM-ELITE-RIFT-BOAR-ARMED-3D", main.cell(17, 1).value
assert main.cell(18, 1).value is None, f"r18 已被占用: {main.cell(18,1).value}"
assert main.cell(8, 1).value == "ENM-SUMMON-HIVE01", "r8 不是预期的程序占位普通怪行"
existing = {str(main.cell(r, 1).value) for r in range(FIRST_DATA_ROW, 18)}
assert NEW_ID not in existing, f"AssetID 已存在: {NEW_ID}"

ov = wb["总览"]
assert str(ov["A6"].value).find("$17") > 0, ov["A6"].value
log = wb["域变更日志"]
assert log.cell(5, 1).value == "台账版本", log.cell(5, 1).value
assert log.cell(8, 1).value == "v0.1.2", log.cell(8, 1).value
assert log.cell(9, 1).value is None, "域变更日志 r9 已被占用"

NEW_ROW = 18
LAST_ROW = NEW_ROW

# ============================ 2) 《资产主表》r18 ==========================
for col in range(1, 26):
    main.cell(NEW_ROW, col)._style = copy(main.cell(8, col)._style)
main.row_dimensions[NEW_ROW].height = main.row_dimensions[17].height

values = {
    1: NEW_ID,
    2: NAME,
    3: "敌人",
    4: SUBCLASS,
    5: LOGIC_ID,
    6: "root",
    7: None,
    8: "侧面朝右（可水平翻转）",
    9: "default",
    10: "单资产",
    11: "待制作",
    12: "P1",
    13: "v001",
    14: "待定",
    15: None,
    16: "待入库（Tripo 生成模型当前仅在 Blender 会话中，尚未保存为 .blend）",
    17: f"{NAME}; 刺背; spike shell; 四足怪; Tripo生成; {NEW_ID}",
    18: dedupe_key_formula(NEW_ROW),
    19: dedupe_result_formula(NEW_ROW, LAST_ROW),
    20: None,
    21: "待分配",
    22: TODAY,
    23: "AI 生成（Tripo）/待确认",
    24: "—",
    25: ("2026-09-23 新登记为独立新怪，只登记不接线。造型：低伏四足、背脊一排尖刺、大圆头带尾，"
         "头部朝 Blender -Y（契约要求 +Y，后续 S3 需整体转 180°）。"
         f"源尺寸 0.8286×0.9995×0.7104m（Tripo 原始尺度，未按展示倍率归一）。"
         "已完成 Rigify 骨架生成 + 自动权重蒙皮（Rigify Basic Human 29 骨 metarig → 219 骨 rig / "
         "34 DEF 骨 / 34 顶点组，3241 顶点全有权重），但**尚未改名到本项目 36 骨契约骨架**，"
         "也**缺契约的 16 根手指骨**（Basic Human 无手指链）。"
         "入库前待办：① 源 .blend 落 source/model/ 并内部改名；② 按展示倍率 0.70 归一尺寸"
         "（源高 = 目标游戏内高 / (0.70×kind×variant)）；③ 朝向归正到 +Y；④ DEF 改名到契约骨架并补手指链；"
         "⑤ 另建动作母版 6 段剪辑；⑥ 导出视觉 GLB + runtime Prefab；⑦ 补《3D-敌人》与"
         "《敌人动画与状态》行（那两张表分别有『一行=一个真实 PackedScene』与逐字节摘要约束，"
         "故本次刻意未动）。玩法数值（HP/速度/伤害/范围/冷却）未定，未接入 Enemy3D.PROFILES。"),
}
for col, value in values.items():
    main.cell(NEW_ROW, col).value = value

# 把查重结果公式的区间扩到新行（否则新行永远判「唯一」——COUNTIF 区间不含自己）
for r in range(FIRST_DATA_ROW, LAST_ROW + 1):
    main.cell(r, 19).value = dedupe_result_formula(r, LAST_ROW)
    assert main.cell(r, 18).value == dedupe_key_formula(r), f"R{r} 公式形态异常"

# 下拉框范围要盖住新行
for dv in main.data_validations.dataValidation:
    before = str(dv.sqref)
    dv.sqref = MultiCellRange(before.replace("$17", "$18").replace(":17", ":18"))
    print(f"DV  {before} -> {dv.sqref}")

# ============================ 3) 《总览》区间扩到 $18 ======================
for ref in ("A6", "C6", "E6", "G6", "B10", "C10", "B11", "C11"):
    cell = ov[ref]
    raw = str(cell.value)
    assert raw.startswith("="), f"{ref} 不是公式: {raw[:60]}"
    cell.value = raw.replace("$17", "$18")
assert "$18" in str(ov["A6"].value) and "$18" in str(ov["G6"].value)

# ============================ 4) 《域变更日志》r9 =========================
for col in range(1, 8):
    log.cell(9, col)._style = copy(log.cell(8, col)._style)
log.row_dimensions[9].height = log.row_dimensions[8].height
entry = {
    1: "v0.1.3",
    2: "2026-09-23",
    3: "新增登记",
    4: "敌人",
    5: (f"新增 {NEW_ID}（{NAME}）作为独立新怪，制作状态=待制作。"
         "AssetID 与既有 7 类预登记不冲突（新原型 " + SUBCLASS + " / 逻辑ID " + LOGIC_ID + "）。"
         "《资产主表》新增 r18，规格、文件路径、SHA-256 留空（无产物），"
         "来源记为 Tripo 生成模型待入库。"
         "《总览》公式区间由 $6:$17 扩到 $6:$18 以满足门禁「区间 == 本账本行数」。"
         "本次只登记、不接线：游戏侧 Enemy3D.PROFILES / FOOTPRINT_PROFILES / EnemyAvatar3D 挂载分支 "
         "与《怪物与Boss》数值均未定义。"
         "未触碰《敌人动画与状态》与《3D-敌人》——前者受逐字节摘要约束，后者要求「一行=一个真实 PackedScene」。"),
    6: ("新增资产行 ⇒ 其余 11 行内容未变，但《总览》区间随之变化，属预期。"
        "无损基线 verify_ledger_split 会报 extra_assets=1 + 资产主表列指纹漂移（仍 exit 0）。"),
    7: "摩斯拉",
}
for col, value in entry.items():
    log.cell(9, col).value = value

wb.save(LEDGER)
print("LEDGER_WRITTEN", LEDGER.name, "| row", NEW_ROW, "| log r9")

# ============================ 5) 内容数据库《怪物与Boss》===================
cwb = load_workbook(CONTENT)
assert "怪物与Boss" in cwb.sheetnames
mb = cwb["怪物与Boss"]
assert mb.cell(4, 1).value == "内容ID", mb.cell(4, 1).value
assert mb.cell(4, 15).value == "备注", mb.cell(4, 15).value
assert mb.cell(14, 1).value, f"r14 应为最后一行业绩，实际空"
assert mb.cell(15, 1).value is None, f"内容库 r15 已被占用: {mb.cell(15,1).value}"
cids = {str(mb.cell(r, 1).value) for r in range(5, 15)}
assert CONTENT_ID not in cids, f"内容ID 已存在: {CONTENT_ID}"

CROW = 15
for col in range(1, 16):
    mb.cell(CROW, col)._style = copy(mb.cell(14, col)._style)
mb.row_dimensions[CROW].height = mb.row_dimensions[14].height

crec = {
    1: CONTENT_ID,
    2: NAME,
    3: LOGIC_ID,
    4: "待定", 5: "待定", 6: "待定", 7: "待定", 8: "待定",
    9: "待设计（未定形态；造型为低伏四足、背脊尖刺）",
    10: "待定（未接入关卡/主题池）",
    11: "待定",
    12: "[用户设计]",
    13: "未实现（仅登记，未接入玩法；无正式3D数值）",
    14: f"assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx（《资产主表》r{CROW - 0} = {NEW_ID}）",
    15: ("2026-09-23 由业主指示登记为新怪，先不考虑调用。"
         "HP/速度/伤害/攻击范围/冷却全部待定：按《字段字典》「怪物与Boss·正式3D数值」要求，"
         "这些列必须是 Enemy3D.PROFILES 的正式 3D 基线、不得混用旧 2D 基线，"
         "而本怪尚未进入 PROFILES ⇒ 刻意留「待定」而不编造数值。"
         "补数时机：接入玩法并写入 Enemy3D.PROFILES 时一并回填。"),
}
for col, value in crec.items():
    mb.cell(CROW, col).value = value
cwb.save(CONTENT)
print("CONTENT_WRITTEN", CONTENT.name, "| 怪物与Boss r", CROW)

print("\nDONE", NEW_ID, "|", NAME, "| 资产主表 r18 | 域变更日志 r9 | 怪物与Boss r15")
