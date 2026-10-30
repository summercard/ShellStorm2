#!/usr/bin/env python3
"""远征03 复刻怪数值重定标（2026-10-29 第三轮：重点对齐弹速 / 伤害 / 攻击方式）。

业主口径
--------
「敌人的子弹速度和伤害还有方式，要重点对齐。」

三轮口径演进（读这一节就知道为什么是现在这些数）：

| 项 | 第一轮 | 第二轮 | 第三轮 | **第四轮（当前）** |
|---|---|---|---|---|
| 血量 | 幂律 42×(h/15)^0.72 | EGT×10（按击杀发数） | 不变 | 不变 |
| 伤害 | 5~22 逐只不同 | 17 普通 / 26 爆炸 | **全部 17**（原作爆炸也是半颗心） | 不变 |
| 弹速 | 无（默认 7，射程 0 ⇒ 1 秒自毁） | 16~20（"玩家移速 3.5 倍"） | 8 基准 / 10 fast / 6 慢弹（可躲性反推） | **6 基准 / 7.5 fast / 4.5 慢弹**（反编译 `Speed(6f)` 定锚，全域 ×0.75） |
| 射程 | 0（bug） | range×1.4 ≈ 12m | **22m**（覆盖整个房间，撞墙自然消失） | 不变 |
| 预判 | 粗略估 | 0.20~0.55 | **按 wiki/反编译硬数据**（Veteran 0.62、老兵霰弹 1.00） | 不变 |

### 一、弹速：第三轮按「可躲性」反推 → 第四轮改用反编译定锚

**第三轮的做法**（保留下面的算式，它仍然是可躲性的判据来源）：
原作的事实是**子弹速度和玩家移速几乎同档**（玩家 6.5 单位/秒，子弹约 8），
wiki 里甚至有 "extremely slow pointy bullet" 这种描述。那轮以「玩家 4.5 m/s、
反应 0.25 s、扇形 ±14°」反推上限，得 8 m/s 基准。

**第四轮业主口径**：「怪物的子弹速度去对标挺进地牢的怪物的子弹速度，要 **1:1 匹配**」。
于是改用**唯一一个反编译实锤**当锚：`new Speed(6f, SpeedType.Absolute)`
（`EnemyAPI`，见 `第一层怪物数据表.md §8.1`）—— 通用敌弹 = **6**。

| 档 | 第三轮 | 第四轮 | 依据 |
|---|---:|---:|---|
| 基准（28 只） | 8.0 | **6.0** | 反编译 `Speed(6f)` |
| fast-moving（3 只） | 10.0 | **7.5** | 基准 ×1.25（保留原作「fast」的相对关系） |
| 慢弹（弹跳 / 追踪） | 6.0 | **4.5** | 基准 ×0.75（追踪 + 高速 = 无解，这个相对关系必须留） |
| 吉吉的蛋 | 4.2 | **3.15** | 蛋要慢慢飞才读得出「蛋」，同比例 ×0.75 |

全域统一 **×0.75**（= 6/8），所以**序关系逐条不变**，只有绝对速度整体降一档。
可躲性只会更好：8 m/s 时 8m 处可横移 3.38m（> 半宽 1.99m），6 m/s 时是 4.88m。

⚠ 同批还有一个「单位尺子」的修正，作用于**玩家枪**而不是怪：本作玩家 4.5 m/s、
原作玩家 6.5 单位/秒 ⇒ **1 原作单位 = 0.6923 m**，所以豌豆手枪的 Shot Speed 25
应落成 **17.31 m/s**（原先直接抄成 25 m/s 是快 44%）。见
`docs/v0.1/development/2026-10-30_starting_pistol_and_egt_bullet_alignment.md`。

### 二、伤害：全部 17，爆炸也不例外

原作 §1.2 的约定是「**绝大多数伤害 = 半颗心**」，**没有为爆炸开特例**。
第二轮把爆炸写成 26（1.5×）是我自拟的，本轮撤回。

死亡弹幕单发**也恢复 17**（第二轮折到 0.30 是因为"没有无敌帧必死"）。
弹速降到 8 之后可以靠走位躲，所以应该恢复原作口径：**12 发全中是 204（必死），
但那是"站着不动"的惩罚，不是"没有选择"**。这本身就是对齐原作的「方式」。

### 三、攻击方式：按 wiki 逐条核对，改掉 5 处

| 怪 | 原作原文 | 本轮修正 |
|---|---|---|
| 老兵霰弹枪 | "V-shaped spread of 5 fast-moving bullets with **100% predictive aim**" | 预判 0.55 → **1.00** |
| 老兵小子 | 反编译 `ShootGunBehavior.LeadAmount = 0.62f` | 预判 0.45 → **0.62** |
| 保险销头 | "If the player gets too close, it will **leap** towards the player and explode" | 补「靠近扑击再爆」 |
| 抓握大师 | "**Automatically dies if all other enemies in the room are killed**" + "After unsuccessfully trying to grab the player **3 times**, it will vanish" | 原实现是「场上还有别人时无敌」，语义不同；改为自动死亡 + 抓空 3 次消失 |
| 链枪手 | "If it's the **only enemy alive** in the room, the ball of the chain will **detach and launch** towards the player" | 补「最后一只时弹球脱手」 |

Run: python tools/retune_egt_monsters.py           # dry-run
     python tools/retune_egt_monsters.py --apply   # 写入
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENEMY = ROOT / "src/enemy3d/Enemy3D.gd"

HP_SCALE = 10.0
MIN_HP = 10

## 统一伤害：玩家 100 血的 1/6。原作「半颗心」= 6 格里的 1 格，爆炸也是同一档。
DMG_NORMAL = 17
## 不造成伤害的两只：枪歌者只加 buff、抓握大师只抓人（原作明确 "deal no damage"）。
DMG_NONE = 0

## 弹速分档（见模块 docstring §一）。
## 第四轮（2026-10-30）锚点换成反编译的 `new Speed(6f, SpeedType.Absolute)`：
## 基准 6 / fast ×1.25 = 7.5 / 慢弹 ×0.75 = 4.5 —— 相对第三轮全域 ×0.75，序关系不变。
SPD_BASE = 6.0
SPD_FAST = 7.5
SPD_SLOW = 4.5

## 弹程统一 22m：足够横穿 25m 房间的对角，撞墙自然消失。
## （不设射程会让子弹只有 1 秒寿命 —— 那是第二轮修掉的「子弹飞不出来」根因，别回退。）
PROJ_RANGE = 22.0

# kind -> (egt_hp, 移动 m/s, 冷却 s, 交战射程 m, 伤害, 弹速, 预判)
# 移动/冷却/射程：原作只有定性（slowly/rapidly/occasionally），按定性分档。
# 伤害/弹速/预判：见 docstring 的三节依据。
SPEC = {
    # —— 子弹族（slowly walks）——
    "egt_bullet_kin":       (15.0, 2.0, 2.20, 8.8, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_bandana_kin":      (15.0, 2.0, 1.05, 8.2, DMG_NORMAL, SPD_BASE, 0.0),   # rapidly firing
    "egt_veteran_kin":      (15.0, 2.6, 1.60, 9.6, DMG_NORMAL, SPD_FAST, 0.62),  # LeadAmount=0.62f
    "egt_cardinal":         (22.5, 2.0, 2.30, 9.0, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_hollowpoint":      (25.0, 1.8, 1.05, 9.6, DMG_NORMAL, SPD_FAST, 0.0),   # floats + rapidly
    # —— 霰弹枪族 ——
    "egt_red_shotgun":      (30.0, 2.0, 2.40, 6.4, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_blue_shotgun":     (40.0, 2.0, 2.40, 6.8, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_veteran_shotgun":  (33.8, 2.0, 2.20, 6.8, DMG_NORMAL, SPD_FAST, 1.00),  # 100% predictive
    # —— 爆炸族 ——
    "egt_pinhead":          (13.0, 2.4, 3.00, 2.85, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_nitra":            (10.0, 2.4, 3.00, 2.60, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_king_bullat":      (26.0, 0.6, 2.60, 9.0, DMG_NORMAL, SPD_SLOW, 0.0),   # 弹跳弹偏慢
    # —— 分裂族 ——
    "egt_blobulon":         (20.0, 2.2, 1.40, 2.05, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_blobuloid":        (10.0, 2.4, 1.30, 1.95, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_blobulin":         (1.0,  3.4, 1.10, 1.80, DMG_NORMAL, SPD_BASE, 0.0),  # quickly moves
    "egt_chancebulon":      (50.0, 2.4, 1.50, 2.10, DMG_NORMAL, SPD_BASE, 0.0),
    # —— 书怪族（floats slowly）——
    "egt_bookllet":         (25.0, 1.6, 2.40, 9.2, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_blue_bookllet":    (25.0, 1.6, 2.50, 9.2, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_green_bookllet":   (25.0, 1.6, 2.60, 9.2, DMG_NORMAL, SPD_BASE, 0.0),
    # —— 法术 / 辅助 ——
    "egt_gunjurer":         (18.8, 1.5, 2.20, 8.8, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_gunsinger":        (15.0, 1.0, 3.60, 7.2, DMG_NONE,   SPD_BASE, 0.0),   # 停留，不攻击
    "egt_gigi":             (12.0, 3.6, 2.60, 7.6, DMG_NORMAL, 3.15,     0.25),  # 蛋慢飞（基准×0.525）
    # —— 一次性冲撞族（冲刺速度在 suicide_rush.speed）——
    "egt_bullat":           (1.0,  2.4, 99.0, 7.5, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_shotgat":          (2.0,  2.4, 99.0, 8.0, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_grenat":           (3.0,  2.4, 99.0, 8.0, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_spirat":           (5.0,  2.4, 99.0, 8.5, DMG_NORMAL, SPD_BASE, 0.75),  # 原作有预判
    # —— 触发 / 逃逸 ——
    "egt_keybullet_kin":    (15.0, 3.0, 1.20, 2.00, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_chance_kin":       (15.0, 3.0, 1.20, 2.00, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_confirmed":        (45.0, 2.2, 2.30, 9.8, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_mimic":            (100.0, 2.2, 1.90, 9.0, DMG_NORMAL, SPD_BASE, 0.0),  # rapidly fires
    "egt_gun_fairy":        (15.0, 3.0, 1.35, 8.4, DMG_NORMAL, SPD_BASE, 0.0),   # 游荡 + 高射速
    "egt_gripmaster":       (30.0, 2.0, 6.00, 3.20, DMG_NONE,  SPD_BASE, 0.0),   # 只抓不打
    # —— 重型 ——
    "egt_gun_nut":          (100.0, 1.8, 2.90, 8.6, DMG_NORMAL, SPD_BASE, 0.0),
    "egt_chain_gunner":     (90.0, 2.1, 3.40, 8.0, DMG_NORMAL, SPD_BASE, 0.0),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    text = ENEMY.read_text(encoding="utf-8")
    changed: list[str] = []
    missing: list[str] = []

    for kind, (egt_hp, move_mps, cooldown, atk_range, damage, bullet_speed, predict) in SPEC.items():
        hp = max(MIN_HP, int(round(egt_hp * HP_SCALE)))
        speed = round(move_mps / 0.7, 3)

        block = re.search(
            r'(\n\t"' + re.escape(kind) + r'": \{\n)(.*?)(\n\t\},)',
            text, re.S,
        )
        if block is None:
            missing.append(kind)
            continue
        body = block.group(2)
        stat_line = re.search(r'\n\t\t"hp": [^\n]*', body)
        if stat_line is None:
            missing.append(kind)
            continue
        new_line = (
            '\n\t\t"hp": %d, "speed": %s, "damage": %d, "range": %s, "cooldown": %s,'
            '\n\t\t"projectile_speed": %s, "projectile_range": %s,'
            % (hp, speed, damage, atk_range, cooldown, float(bullet_speed), PROJ_RANGE)
        )
        new_body = body[:stat_line.start()] + new_line + body[stat_line.end():]
        text = text[:block.start(2)] + new_body + text[block.end(2):]
        changed.append(
            "%-24s hp=%-5d dmg=%-3d 弹速=%-4.1f 预判=%.2f 射程=%.1f 弹程=%.0f"
            % (kind, hp, damage, bullet_speed, predict, atk_range, PROJ_RANGE)
        )

    print("\n".join(changed))
    print("\n汇总: 改动 %d 只, 未找到 %d 只 %s" % (len(changed), len(missing), missing))
    if args.apply:
        ENEMY.write_text(text, encoding="utf-8")
        print("已写入", ENEMY)
    else:
        print("(dry-run，未写入)")
    return 0 if not missing else 1


if __name__ == "__main__":
    raise SystemExit(main())
