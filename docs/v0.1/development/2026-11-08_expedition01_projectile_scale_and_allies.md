# 远征01 弹体放大与敌弹敌我通吃（2026-11-08）

业主口径两条：① 视觉倍率改成 1.8；②「打死会散射出子弹的那个小怪，它的子弹会对敌方也造成伤害」。

## 一、视觉倍率 1.8

`monster_rules.projectile.visual_scale = 1.8`（新段，远征01 专属）。

| 项 | 改前 | 改后 |
| --- | --- | --- |
| 视觉倍率 | 1.0（无配置） | **1.8** |
| 外壳圆柱半径 | 0.075 m | **0.135 m**（直径 27 cm） |
| 弹芯半径 | 0.045 m | 0.081 m |
| 尾迹锥底半径 / 长 | 0.06 / 0.5 m | 0.108 / 0.9 m |
| 判定球半径 | 0.12 m | **0.12 m（不变）** |

链路沿用远征03 的既有通道：关卡 → `MonsterInjector._projectile_look_overrides()` →
怪物 config → `Projectile3D.visual_scale` → `_visual_scale_factor()`。
判定球走 `_collision_scale_factor()`，**刻意不含任何视觉倍率**，可躲性判据不受影响。

## 二、敌弹敌我通吃

新增关卡级白名单 `monster_rules.projectile.hit_allies_kinds`（怪种 id 数组，缺键 / 空数组 = 不生效），远征01 写 `["exploder"]`。

| 项 | 定法 |
| --- | --- |
| 生效范围 | **只有炸弹果 `exploder`**（业主 2026-11-08 二次裁定「只有一只会有」）；警察僵尸 `ranged_caster` 与宝箱拟态 `egt_mimic` 的子弹仍然只打玩家 |
| 实现 | `Enemy3D._projectile_hits_allies_now()` 按 `enemy_kind` / `_asset_kind()` 比对白名单 → 只在命中时才给 `Projectile3D` 下发 `hit_allies=true` → `projectile_collision_mask \|= 4`（敌人层，与玩家子弹掩码 5 同口径） |
| 发射者 | 由 `_tracked_collision_exceptions` 排除，不会自伤 |
| 仇恨归属 | 命中敌对怪时**不传 attacker**、不调 `notify_attacked_by()` —— 只结算伤害。带 attacker 会让 `MonsterAIManager` 把一只怪当成玩家处理，AI 目标链会被搅乱 |
| 击杀结算 | 仍旧走 `Enemy3D._die()` 的 `killed` 记帐（掉落 / 清房），不区分击杀者 |

**「打死会散射子弹的那只」= 炸弹果 `exploder`**：它由 `data/spawn_boxes/box_room_spread.json` 刷出
（远征01 的 `floor_00.json` 引用了 8 次该盒，每次 2 只 `melee_chaser` + 1 只 `exploder`），
死亡时走 `Enemy3D._spawn_death_fragments()` —— 向 8 个方向各射一发（伤害 = 接触伤害 × 0.28）。
这就是唯一需要敌我通吃的子弹来源。

排除掉的三个近似项（都不是业主说的那只）：
- `melee_chaser` / `ranged_caster` 死后散开的是 `VFX-ZOMBIE-GOO-DEATH-3D` 的绿色方块，**纯视觉、无伤害**；
- `ranged_caster` 平时打单发，但那是常态攻击，不是「死后散射」；
- `fat_zombie03` 死后是爆炸 + 地面伤害场，早已是敌我通吃，与子弹无关。

白名单按怪种匹配，因此强变异体 `exploder_strong`（血量/体型 ×1.5 那档）会自动跟随 ——
`_asset_kind()` 会剥掉 `_strong` 后缀再比。

## 三、改动文件

- `data/level_plans/expedition_01/level_plan.json`、`art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json`
- `src/combat3d/Projectile3D.gd`（`COLLISION_LAYER_ENEMY` 常量、`hits_allies` 字段与 mask、命中不传 attacker）
- `src/enemy3d/Enemy3D.gd`（`_projectile_hit_allies_kinds` 读取、`_projectile_hits_allies_now()` 白名单判定与下发）
- `src/map/MonsterInjector.gd`（`_projectile_look_overrides()` 读 `hit_allies_kinds`）
- 设计文档：`远征关卡01设计.md` §4.5.3（JSON + 说明）、`怪物设计.md`（新增「远征01：关卡档 1.8 + 敌弹敌我通吃」小节）
- 账本：`ShellStorm2_游戏内容数据库_v010.xlsx`《怪物与Boss》O9 备注

## 四、验收状态

只做了 `--check-only` 语法检查（三个脚本除既有 autoload 缺失报错外无解析错误），
**未跑任何运行用例**。受影响但未执行：`verify_expedition01_monster_rules`、
`_egt_dodgeability_probe`（判定球未变，理论上不受影响）、敌我通吃的实际命中链（需真渲染观察怪互殴）。
