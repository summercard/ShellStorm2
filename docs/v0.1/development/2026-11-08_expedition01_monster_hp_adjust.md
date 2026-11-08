# 远征01 怪物生命值下调（2026-11-08）

业主口径：本关四只怪生命全部下调，其余数值不动。

## 改动

| 怪 | 内容键 | 生命 | 伤害 | 速度 |
| --- | --- | --- | --- | --- |
| 小僵尸 | `melee_chaser` | 350 → 250 → **180**（同日二次下调） | 18（不变） | 3.5 m/s（不变） |
| 胖子僵尸 | `fat_zombie03` | 800 → **500** | 35（不变） | 1.5 m/s（不变） |
| 警察僵尸 | `ranged_caster` | 250 → **150** | 30（不变） | 未配（不变） |
| 显示器Boss | `boss` | 32000 → **18000** | — | 3.612 m/s（不变） |

## 落点

- `data/level_plans/expedition_01/level_plan.json` —— 运行时真源，`monster_rules.stats.per_kind` 四个 `hp` 值。
- `art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json` —— 白盒设计源同副本，同步。
- 设计文档：`docs/v0.1/design/远征关卡01设计.md` §4.5.3（JSON 现值 + 调整说明；旧实测表标注为 2026-10-14 当时读数）、`怪物设计.md`（远征01 覆盖段）、`胖子僵尸03运行配置.md`、`Boss002显示器技能设计.md`（03 复用说明）。
- 账本：`docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx`《怪物与Boss》O8 / O9 / O16 / O17 各追加「2026-11-08 生命下调」备注。D 列（`Enemy3D.PROFILES` 基线）刻意不改。

## 边界

- 小僵尸强化变体随原怪实时派生，自动由 500 变 **360**（×2），未另存绝对数值。
- 只改**绝对值**，不引入缩放；`Enemy3D.PROFILES` 基线与 `BossContentCatalog` 身份基线均未动，其它关卡不受影响。
- 死亡自爆（180 / 半径 5 m）与地面持续伤害场（3 s / 每 0.5 s 24）参数未动 —— 它们与生命值无耦合，但血量减半后一场战斗中触发的自爆次数会变多。
- **远征03 未同步**：`data/level_plans/expedition_03/level_plan.json` 的 `boss.hp` 仍是 32000，需另行裁定。

## 验收状态

按业主要求未跑任何用例；本轮只做数据与文档同步，**不代表**数值手感已验证。受影响但未执行：`verify_expedition01_monster_rules`、Boss 三阶段血量阈值相关的战斗回归。
