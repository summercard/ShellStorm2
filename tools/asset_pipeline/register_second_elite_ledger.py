# -*- coding: utf-8 -*-
"""把第二只正式精英（`ENM-ELITE-ARMS-TAKER-3D`）登记进敌人账本。

三个分页各写一处，都是账本契约要求的：
1. 《资产主表》—— 资产身份（AssetID / slug / 路径 / 哈希 / 状态）。唯一登记源。
2. 《3D-敌人》—— Prefab 分类页（Prefab 路径、GLB、碰撞归属、尺寸）。
3. 《敌人动画与状态》—— 下表「敌人条目 × 状态机对照」补一行。

**两个必须守住的细节**（写错了账本门禁会红，或更糟：静默算错）：
- 《资产主表》R 列查重键、S 列查重结果都是**公式**，且 S 列的
  `COUNTIF($R$6:$R$54, ...)` 里范围是**硬编码到 54 行**的。插行后若不同步扩范围，
  新行就会被排除在查重之外 ⇒ 重复 AssetID 查不出来。
- 插行要**复制上一行的单元格样式**，否则新行是白底、与账本视觉不一致。
"""
import os
import shutil
import sys

import openpyxl
from openpyxl.utils import get_column_letter

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
LEDGER = os.path.join(ROOT, "assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx")

ASSET_ID = "ENM-ELITE-ARMS-TAKER-3D"
CN_NAME = "夺械者“收租人”3D精英根"
SLUG = "elite_arms_taker"
PREFAB = "assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn"
GLB = "assets/art/enemies/elite_3d/enm_elite_arms_taker/components/enm_elite_arms_taker/enm_elite_arms_taker_visual_top3d.glb"
SCRIPT = "assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/elite_arms_taker_formal_visual.gd"
ANIM_MERGE = "art_source/enemies/elite_3d/enm_elite_arms_taker/source/animation/author_merge_animation_v001.py"
ANIM_SRC = "art_source/enemies/elite_3d/enm_elite_arms_taker/source/animations/"
MANIFEST = "assets/art/enemies/elite_3d/enm_elite_arms_taker/enm_elite_arms_taker_manifest_v001.json"
GLB_SHA = "074fac37e635d6d4b73c5e274b5ec61e1611a5ed07f3c38d8436d5b0abf91449"
SIZE_NOTE = "3.371×3.500×0.802m；1 Mesh；1 材质；41 骨；18 剪辑；2525 三角"
TODAY = "2026-11-03"


def main():
    backup = LEDGER + ".bak_before_second_elite_20261103"
    shutil.copy2(LEDGER, backup)
    print("[ledger] 已备份 →", os.path.basename(backup))

    wb = openpyxl.load_workbook(LEDGER)

    # ————————————— 1. 资产主表 —————————————
    ws = wb["资产主表"]
    last_row = ws.max_row
    new_row = last_row + 1
    if new_row < 6:
        raise RuntimeError("资产主表起始行异常")
    # 先查重（用公式口径复算一遍），避免重复登记
    for r in range(6, last_row + 1):
        if str(ws.cell(r, 1).value or "") == ASSET_ID:
            raise RuntimeError("AssetID 已在第 %d 行存在，拒绝重复登记" % r)
        if str(ws.cell(r, 5).value or "") == SLUG:
            raise RuntimeError("slug 已在第 %d 行存在，拒绝重复登记" % r)

    values = {
        1: ASSET_ID,
        2: CN_NAME,
        3: "敌人",
        4: "elite",
        5: SLUG,
        6: "root_3d",
        7: "ENM-ECOSYSTEM-KIT-3D",
        8: "Top3D / local -Z 正面",
        9: "default / weapon_phase_swap",
        10: "每次行动94—92F三选一；目标层随机ELITE房",
        11: "已完成",
        12: "P0",
        13: "v001",
        14: SIZE_NOTE,
        15: PREFAB,
        16: "%s; %s; %s; %s; src/enemy3d/EliteContentCatalog.gd" % (GLB, SCRIPT, ANIM_MERGE, ANIM_SRC),
        17: "唯一精英;夺械者;收租人;elite_arms_taker;weapon_phase_swap;94F;93F;92F;命名血条;18剪辑",
        18: '=LOWER(TRIM(C{r})&"|"&TRIM(D{r})&"|"&TRIM(E{r})&"|"&TRIM(F{r})&"|"&TRIM(H{r})&"|"&TRIM(I{r}))'.format(r=new_row),
        19: '=IF(COUNTIF($R$6:$R${last},R{r})>1,"重复","唯一")'.format(last=new_row, r=new_row),
        20: GLB_SHA,
        21: "Codex",
        22: TODAY,
        23: "原创 Blender/Godot 组合（3 号机动作库迁入）",
        24: "—",
        25: (
            "GLB 仅表现；41 骨 + 18 剪辑动画母版（idle/walk/run/turn_left/turn_right/"
            "attack_light/attack_heavy/attack_jump/block/dodge/hit/stagger/stunned/death/"
            "spawn_standup/roar/kneel/slam）；PackedScene 无碰撞；Enemy3D 继续持有 "
            "melee_chaser 碰撞、AI、生命、伤害与掉落；Elite.Huge 词缀叠加前基线 3.5 m。"
            "本次为精英首次使用真骨骼动画（首只 rift_boar_armed 为纯静态 0 骨）。"
            "2026-11-03 由 enm_elite_tvone01（执行方自拟 slug）正式定名为 %s。" % ASSET_ID
        ),
    }
    for col, value in values.items():
        cell = ws.cell(new_row, col)
        cell.value = value
        src = ws.cell(last_row, col)
        if src.has_style:
            cell.font = src.font.copy()
            cell.fill = src.fill.copy()
            cell.border = src.border.copy()
            cell.alignment = src.alignment.copy()
            cell.number_format = src.number_format
    print("[ledger] 资产主表 +1 行（第 %d 行）" % new_row)

    # 旧行的 S 列 COUNTIF 范围是硬编码的，插行后必须**全部**扩到新行，
    # 否则新行被排除在查重之外 —— 重复 AssetID 会静默漏检。
    patched = 0
    for r in range(6, new_row + 1):
        current = ws.cell(r, 19).value
        if isinstance(current, str) and current.startswith("=IF(COUNTIF("):
            ws.cell(r, 19).value = '=IF(COUNTIF($R$6:$R${last},R{r})>1,"重复","唯一")'.format(
                last=new_row, r=r
            )
            patched += 1
    print("[ledger] 查重公式范围已扩到第 %d 行（改写 %d 条）" % (new_row, patched))

    # ————————————— 2. 3D-敌人 分类页 —————————————
    ws3 = wb["3D-敌人"]
    r3 = ws3.max_row + 1
    row3 = {
        1: ASSET_ID,
        2: "夺械者“收租人”",
        3: PREFAB,
        4: GLB,
        5: "（无 .blend 母版：3 号机产物只有 GLB）",
        6: "第二只唯一精英独立表现；18 剪辑真骨骼动画、西装电视头造型与命名专属血条",
        7: "%s; src/enemy3d/EliteContentCatalog.gd; src/enemy3d/EliteRosterService.gd; src/enemy3d/EnemyAvatar3D.gd; src/enemy3d/Enemy3D.gd" % SCRIPT,
        8: "关（表现资产）",
        9: "Enemy3D",
        10: "复用 melee_chaser CylinderShape3D",
        11: SIZE_NOTE,
        12: "底部可预测（脚底 z=0）；Blender -Y / Godot -Z 正面；根 Scale=1",
        13: "每次行动按 run_seed 在 94F/93F/92F 三选一；目标层随机 ELITE 房",
        14: "正式美术已接入",
        15: "v001",
        16: "AssetID 与 elite_id 稳定；与首只 98-96F 窗口互不重叠。动画母版由 18 条单状态 GLB 合并（41 骨逐条一致）；slam 的源 clip 名不规范已归一。",
    }
    for col, value in row3.items():
        cell = ws3.cell(r3, col)
        cell.value = value
        src = ws3.cell(r3 - 1, col)
        if src.has_style:
            cell.font = src.font.copy()
            cell.fill = src.fill.copy()
            cell.border = src.border.copy()
            cell.alignment = src.alignment.copy()
            cell.number_format = src.number_format
    print("[ledger] 3D-敌人 +1 行（第 %d 行）" % r3)

    # ————————————— 3. 敌人动画与状态（下表）—————————————
    wsa = wb["敌人动画与状态"]
    # 下表头在第 20 行；数据从 21 行起
    header_row = None
    for r in range(1, wsa.max_row + 1):
        if str(wsa.cell(r, 1).value or "") == "序号" and "敌人ID" in str(wsa.cell(r, 2).value or ""):
            header_row = r
            break
    if header_row is None:
        raise RuntimeError("找不到『敌人条目 × 状态机对照』表头")
    ra = wsa.max_row + 1
    row_a = {
        1: ra - header_row,
        2: ASSET_ID,
        3: "夺械者“收租人”",
        4: "Blender 动作母版（GLB 合并版）：41 骨；18 剪辑",
        5: "ENEMY_AI_12_STATES",
        6: "骨骼 GLB / runtime Prefab（无碰撞，Enemy3D 持有玩法）",
        7: "有：%s" % ANIM_SRC,
        8: "已接入（verify_second_elite_arms_taker）",
        9: "18 条动作按 12 态映射；循环段 idle/walk/run 按相位播，一次性段按状态时间采样。源清单见 art_source/.../source/状态机动画清单.md。",
    }
    for col, value in row_a.items():
        cell = wsa.cell(ra, col)
        cell.value = value
        src = wsa.cell(ra - 1, col)
        if src.has_style:
            cell.font = src.font.copy()
            cell.fill = src.fill.copy()
            cell.border = src.border.copy()
            cell.alignment = src.alignment.copy()
            cell.number_format = src.number_format
    print("[ledger] 敌人动画与状态 +1 行（第 %d 行）" % ra)

    wb.save(LEDGER)
    print("[ledger] 已保存")

    # 总览页的 8 条汇总公式（COUNTA / COUNTIF / SUMPRODUCT）同样把主表范围
    # 硬编码到末行。只改《资产主表》的查重公式而漏掉总览 ⇒ 资产计数、分类计数
    # 全都**少算新行**，而账本表面完全正常（不报错、不变色）。
    # 这一条由 scripts/check_asset_registry.py 的 expected_end 门禁抓出来。
    patched = extend_overview_ranges(LEDGER, new_row)
    print("[ledger] 总览页汇总公式范围已扩到第 %d 行（改写 %d 条）" % (new_row, patched))


## 把《总览》页里所有指向主表的硬编码末行号替换成新末行。
def extend_overview_ranges(ledger_path, new_last_row):
    wb = openpyxl.load_workbook(ledger_path)
    ws = wb["总览"]
    old = "$%d" % (new_last_row - 1)
    patched = 0
    for row in range(1, ws.max_row + 1):
        for col in range(1, ws.max_column + 1):
            value = ws.cell(row, col).value
            if isinstance(value, str) and "'资产主表'!" in value and old in value:
                ws.cell(row, col).value = value.replace(old, "$%d" % new_last_row)
                patched += 1
    if patched:
        wb.save(ledger_path)
    return patched


main()
