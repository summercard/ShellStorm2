# 远征03 逐只怪物清单（弹速 / 体型 / 碰撞）

> 生成日期：2026-11-02
> 数据来源：运行时实测（`tools/_egt_enemy_size_probe.tscn`）+ 代码解析（`Enemy3D.PROFILES`）
> 本轮为**只读核对**，未修改任何参数。

## 0. 每只怪有四个独立控制点

| 参数 | 位置 | 粒度 |
|---|---|---|
| 弹速 / 弹程 / 血量 / 伤害 / 冷却 / 弹幕形态 | `src/enemy3d/Enemy3D.gd::PROFILES` 的怪种行 | 逐只一行，改一行只动这一只 |
| 体型倍率（根节点 `scale`） | 同文件 `BODY_SCALE_BY_KIND` | 逐只显式登记（egt_ 33 只全登记，不靠别名回退） |
| 借用哪只模型 | `src/enemy3d/EnemyAvatar3D.gd::PROXY_ASSET_KIND` | 逐只一行 |
| 碰撞柱半径 / 高度 | 同文件 `FOOTPRINT_PROFILES`（按基类，egt_ 走借用的基类） | 按基类，egt_ 四只共用一档 |

三个**全局乘数**会同时作用到所有怪，改它们等于改全体：
`NORMAL_HP_MULTIPLIER = 3.0`（血量）、`GLOBAL_MOVE_SPEED_MULTIPLIER = 0.70`（移速）、
碰撞半径硬上限 `MAX_COLLISION_RADIUS_M = 0.935`（直径 1.87 = 门洞 2.2 × 0.85）。
弹速**不受任何全局乘数影响**，`_fire_projectile()` 直接取 `_active_profile["projectile_speed"]`。
强化怪倍率（`projectile_speed_mult = 1.3`）对本关不生效 —— `monster_rules.strong_variant.chance = 0.0`。

## 1. 逐只清单（33 只）

| # | 怪种 | 攻击方式 | 弹速 m/s | 弹幕规格 | 特殊机制 | 借用模型 | scale | 世界高 m | /玩家 | 碰撞直径 m |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | egt_bandana_kin | volley | 6.0 | 3 发，0.12s 间隔 | — | ranged_caster | 0.79 | 1.28 | 0.71 | 1.39 |
| 2 | egt_blobulin | contact | 6.0 | 不开火 | — | melee_chaser | 0.77 | 1.00 | 0.56 | 1.26 |
| 3 | egt_blobuloid | contact | 6.0 | 不开火 | 死亡分裂 2 只 blobulin | melee_chaser | 0.94 | 1.22 | 0.68 | 1.53 |
| 4 | egt_blobulon | contact | 6.0 | 不开火 | 死亡分裂 2 只 blobuloid | melee_chaser | 1.15 | 1.50 | 0.83 | 1.87 |
| 5 | egt_blue_bookllet | volley | 6.0 | ring 8 发 ×2 圈，0.12s 间隔 | 隔 3 次改 N 字母弹 9 发；浮空 | summoner | 0.83 | 1.51 | 0.84 | 1.87 |
| 6 | egt_blue_shotgun | volley | 6.0 | 5 发 ±26°，0.16s 间隔 + 追射 4 发 ±26°，0.07s | 死亡喷 6 发（35%） | ranged_caster | 0.94 | 1.52 | 0.84 | 1.65 |
| 7 | egt_bookllet | volley | 6.0 | letter R 10 发，0.06s 间隔 | 浮空 | summoner | 0.80 | 1.46 | 0.81 | 1.87 |
| 8 | egt_bullat | rush | 6.0 | 不开火 | 一次冲撞 11.0 m/s | exploder | 0.78 | 1.00 | 0.56 | 1.37 |
| 9 | egt_bullet_kin | volley | 6.0 | 单发直射 | — | ranged_caster | 0.75 | 1.22 | 0.68 | 1.33 |
| 10 | egt_cardinal | volley | 6.0 | 单发直射 | 隔 3 次改 ring 5 发追踪 0.45 | ranged_caster | 0.85 | 1.38 | 0.77 | 1.50 |
| 11 | egt_chain_gunner | orbit | 6.0 | 不开火（环绕子弹链 4.8 m/s，3 圈/秒 ×2 秒） | — | fat_zombie03 | 0.80 | 2.51 | 1.39 | 1.40 |
| 12 | egt_chance_kin | flee | 6.0 | 不开火 | 逃跑，11 秒后消失 | melee_chaser | 0.83 | 1.08 | 0.60 | 1.36 |
| 13 | egt_chancebulon | chance | 6.0 | 随机借同族招式 | 20% 概率直接自灭 | melee_chaser | 1.23 | 1.60 | 0.89 | 1.87 |
| 14 | egt_confirmed | volley | 6.0 | serpentine 4 条，0.16s 间隔，预判 0.3 | 追踪 0.4 | ranged_caster | 0.99 | 1.60 | 0.89 | 1.74 |
| 15 | egt_gigi | volley | 3.15 | 1 枚蛋，预判 0.25 | 蛋落地炸 8 发环 | summoner | 0.84 | 1.52 | 0.84 | 1.87 |
| 16 | egt_green_bookllet | volley | 6.0 | clover 4 瓣 ±12°，0.07s 间隔 | 浮空 | summoner | 0.86 | 1.56 | 0.87 | 1.87 |
| 17 | egt_grenat | rush | 6.0 | 不开火 | 冲撞 10.0 m/s，撞到吐 1 发爆炸弹 | exploder | 0.86 | 1.10 | 0.61 | 1.51 |
| 18 | egt_gripmaster | grab | 6.0 | 不开火 | 悬停 2.2 m 抓人抛回 10 m；有同伴时无敌 | summoner | 0.71 | 1.30 | 0.72 | 1.74 |
| 19 | egt_gun_fairy | volley | 6.0 | 3 发 ±6°，0.08s 间隔 | 房内游荡；浮空 | ranged_caster | 0.65 | 1.06 | 0.59 | 1.15 |
| 20 | egt_gun_nut | volley | 6.0 | compass 7 发 ±45°，锁 45° 罗盘 | 隔 2 次改箭头弹 4 发；jammed 弹 4.875 m/s | fat_zombie03 | 0.84 | 2.64 | 1.47 | 1.48 |
| 21 | egt_gunjurer | volley | 6.0 | spiral 9 发，0.1s 间隔，每发转 40° | 出手后瞬移；浮空 | summoner | 0.88 | 1.60 | 0.89 | 1.87 |
| 22 | egt_gunsinger | support | 6.0 | 不开火 | 群体 +35% 血 / ×1.35 速；原地不动 | summoner | 0.93 | 1.70 | 0.94 | 1.87 |
| 23 | egt_hollowpoint | volley | 7.5 | 4 发 ±3°，0.09s 间隔，预判 0.2 | 每 5 秒瞬移 7 m；浮空 | ranged_caster | 0.62 | 1.01 | 0.56 | 1.10 |
| 24 | egt_keybullet_kin | flee | 6.0 | 不开火 | 逃跑，11 秒后消失 | melee_chaser | 0.78 | 1.02 | 0.57 | 1.28 |
| 25 | egt_king_bullat | volley | 4.5 | ring 8 发，0.05s 间隔，弹跳 3 次 | 死亡分裂 2 bullat + 2 shotgat；原地不动 | exploder | 1.16 | 1.48 | 0.82 | 1.87 |
| 26 | egt_mimic | volley | 6.0 | ring 8 发，0.06s 间隔 | 伪装宝箱，12 秒兜底现形；隔 2 次改 12 发 | fat_zombie03 | 0.80 | 2.53 | 1.41 | 1.42 |
| 27 | egt_nitra | explode | 6.0 | 不开火 | 扑 8.0 m/s ×0.22s 后自炸（半径 3.4） | exploder | 0.94 | 1.21 | 0.67 | 1.66 |
| 28 | egt_pinhead | explode | 6.0 | 不开火 | 扑 9.5 m/s ×0.22s 后自炸（半径 2.6） | exploder | 1.00 | 1.28 | 0.71 | 1.76 |
| 29 | egt_red_shotgun | volley | 6.0 | 5 发 ±14°，齐射 | 死亡喷 6 发（35%） | ranged_caster | 0.85 | 1.38 | 0.77 | 1.50 |
| 30 | egt_shotgat | rush | 6.0 | 不开火 | 冲撞 10.5 m/s，撞到吐 V 型 2 发 | exploder | 0.82 | 1.05 | 0.58 | 1.44 |
| 31 | egt_spirat | rush | 6.0 | 不开火 | 冲撞 9.5 m/s，中途重定位 3 次 | exploder | 0.90 | 1.15 | 0.64 | 1.58 |
| 32 | egt_veteran_kin | volley | 7.5 | 4 发 ±1.5°，0.12s 间隔，预判 0.62 | — | ranged_caster | 0.83 | 1.34 | 0.74 | 1.46 |
| 33 | egt_veteran_shotgun | volley | 7.5 | v 型 5 发 ±22°，预判 1.0 | 死亡必喷 12 发 | ranged_caster | 0.90 | 1.45 | 0.81 | 1.58 |

## 2. 分布

- 弹速：6.0 × 28 只 / 7.5 × 3 只（veteran_kin、hollowpoint、veteran_shotgun）/ 4.5 × 1 只（king_bullat）/ 3.15 × 1 只（gigi）。
  另有三个子机制独立速度：gun_nut 的 jammed 弹 4.875、chain_gunner 的环绕链 4.8、三只冲撞怪 9.5–10.5。
- 体型：0.56×–1.47×（玩家 1.8 m）。最小 hollowpoint 1.01 m，最大 gun_nut 2.64 m。
- 碰撞直径：1.10–1.87 m。到 1.87 的 9 只（blobulon、三色书怪、chancebulon、gigi、gunjurer、gunsinger、king_bullat）
  是撞到了 `MAX_COLLISION_RADIUS_M` 上限 —— **这是设计夹紧，不是异常**，直径 1.87 = 门洞 2.2 × 0.85，过门仍有 15% 余量。
  副作用是这些怪的模型比碰撞柱宽（gunsinger 宽约 18%），属于刻意的视觉/判定解耦。

## 3. 已知文档漂移

`data/level_plans/expedition_03/level_plan.json` 的 `monster_rules.note` 仍写「弹速 8（基准）/10/6」
和基于 16 m/s 的可躲性反推 —— 那是第三轮的说法。现行是第四轮 6 / 7.5 / 4.5，锚点为反编译
`new Speed(6f, SpeedType.Absolute)`。该字段只是注释，运行时不读，但会让后人对不上账。

`DEFAULT_ENEMY_PROJECTILE_SPEED = 7.0` 只服务没写 `projectile_speed` 的老怪，33 只 egt_ 全都不走它。
