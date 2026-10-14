# 僵尸死亡特效：绿色方块爆开（FX01-19）＋ 去掉倒地动画

> ⚠️ **本文部分内容已被同日晚 23:40 的事务修正**：[2340_hit_routing_and_zombie_death.md](2340_hit_routing_and_zombie_death.md)
> 业主第三轮明确「**小僵尸的死亡特效不要改变**」⇒ FX01-19 **保持 v001**（下面写的 v002 / 放大 2 倍 /
> 绿色冲击波 那部分**不成立**）；「放大两倍 + 绿色冲击波」那条是给**胖子僵尸**用的（FX01-17 v002）。
> 结构上 `VfxZombieGooDeath3D` 已改为继承共享基类 `VfxGooDeathBase3D`（身体是 v001 逐字副本，观感未变）。
> 另：真渲染预览已迁到 `outputs/combat_vfx_batch2/`（四组时间轴）。

时间：2026-10-14 21:50 ｜ 负责人：摩斯拉 ｜ 账本版本：v0.1.20

## 业主口径（原文）

> 制作小僵尸死亡特效，用绿色方块爆开的粒子，掉落地面，然后地面上有用方形向液体一样的扁平模型，
> 停留0.5秒后慢慢下沉消失，特效由三部分组成，爆炸的粒子，飞溅出去的粒子，地上的液体，
> 节奏自己把控好，要有打击力度感，节奏感，粒子不要太小，可以大一点，需要有大小的变化动画。
> 完成后记录到特效账本中去，并且配置在小僵尸和警察僵尸死亡后，状态机上去掉倒地动画。

对应的怪种映射（**这是本次唯一需要推断的一处**，写进 `Enemy3D.GOO_DEATH_KINDS`）：

| 业主叫法 | 逻辑 ID | 依据 |
|---|---|---|
| 小僵尸 | `melee_chaser` | `MonsterInjector.BASE_ENEMY_TYPES` 与 `Enemy3D.configure_from_enemy_data` 的名字归一化都把它叫「小僵尸」 |
| 警察僵尸 | `ranged_caster` | `box_bridge_center.json` 注释与 `level_plan.json` 掉落备注都把 `ranged_caster` 记作「警察僵尸」（另有一个已弃用别名「保安僵尸」） |
| 胖子僵尸 | `fat_zombie03` | **不在**本次范围，且它是 FX01-17 自爆那条路 |

## 交付物

| 项 | 路径 |
|---|---|
| AssetID | `VFX-ZOMBIE-GOO-DEATH-3D`（FX01-19，账本《资产主表》r38） |
| Prefab | `assets/art/vfx/combat_3d/vfx_zombie_goo_death_root_top3d.tscn` |
| 脚本 | `src/vfx/VfxZombieGooDeath3D.gd` |
| 池注册 | `src/vfx/VfxPool3D.gd` → `FX01_ZOMBIE_GOO_DEATH` |
| 调用方 | `src/enemy3d/Enemy3D.gd` → `_die()` / `_spawn_goo_death_burst()` / `_retire_goo_death_visual()` |
| 专项验收 | `tests/verification/verify_zombie_goo_death_vfx.tscn`（`samples=14`） |
| 真渲染预览 | `tests/verification/preview_zombie_goo_death.tscn` → `outputs/zombie_goo_death/` |
| 视觉证据 | `outputs/zombie_goo_death/zombie_goo_death_timeline.png`（9 帧时间轴） |

## 三部分与节奏（总寿命 1.35s）

| 段 | 时刻 | 内容 |
|---|---|---|
| A 爆炸粒子 ×12 | `0 → 0.24s` | 绿色方块从胸口炸开。尺度 `0.25 → 1.15 → 0.35` 倍（**变化 4.6 倍**）；半径 `0.35 → 1.65m`（外推指数 3.0，让「炸开半径」跑在「方块变大」前面） |
| B 飞溅粒子 ×14 | `0 → ~0.29s` | `g = 30` 抛物线（**比真重力 9.8 大三倍** —— 要的是紧凑，不是真实）。落地判定是**解析式**（`t = (v↑ + √(v↑² + 2gh))/g`），不接物理引擎。落地后 squash 压扁再缩没 |
| C 地上液体 ×4 | `0.28 → 1.34s` | 薄方板（0.72m × 0.86~1.16 × 厚 0.05），落在**飞溅粒子的真实落点**上。出现（0.09s，过冲 1.18）→ **严格停留 0.50s**（错峰 0.025s）→ 下沉 **0.30m** 并淡出 0.36s |

`floor_y` 是地面高度**唯一真源**：调用方传 `global_position.y`（脚底行走面）；
未传时特效按「胸口 = 脚底 + 0.65」反推，**绝不以 0 兜底**（塔楼 98F ≈ −1176 m）。

## 两个「真渲染才发现」的坑（首版数值在实拍里读不出业主要求）

1. **爆炸粒子成团**：首版出生半径 `0.05` + 外推指数 `2.0` ⇒ 0.06s 那帧 12 个方块互相插进去，
   读作「一大块绿色」，**看不出「方块爆开」**。改为出生半径 `0.30` + 指数 `3.0`。
   → 新增断言：`burst_radius_min > 0.15`（RC 实测退回 0.05 时红，最小半径 0.0825）。

2. **灯把「停留」糊掉**：首版灯 `0.72s` 才归零，落在地面液体的公共停留窗口 `[0.445, 0.870]` 内
   ⇒ 停留段地面亮度一直在变。实拍 0.50s / 0.85s 两帧像素差最大 **83、13 万像素**受影响。
   改为 `0.34s` 归零后两帧只余渲染噪声（**约 1100 像素**）。
   → 新增断言：灯必须在公共停留窗口**之前**熄灭。
   ⚠️ 判断「两帧是否相同」时先量噪声下限：**同一时刻重绘两次**本身就有约 1100 像素的差，
   别把渲染噪声当回归。

## 状态机改动（去掉倒地动画）

`Enemy3D._die()` 分两路：

```
goo_death = GOO_DEATH_KINDS.has(enemy_kind)
  ├─ true  → 不进 enemy_death_visual_3d 组；_spawn_goo_death_burst()；_retire_goo_death_visual()
  │          （模型同帧收起 + set_process(false) + queue_free ⇒ 无倒地动画、无尸体）
  └─ false → 原链路逐字不变（add_to_group + _spawn_effect + tween_interval(get_formal_death_duration())）
```

「去掉倒地动画」的量化依据：小僵尸的 `get_formal_death_duration()` 实测 **2.4s**（`dead` 段长度），
旧链路必须先留一具躯干播完这 2.4s。新链路**同帧** `avatar.visible = false`。

`GOO_DEATH_KINDS` 用 `enemy_kind` 判，**精英同族一并适用**（「巨大化 · 小僵尸」本来就走压扁回收、
没有倒地动画）—— 避免「同一只怪换个词缀就换一种死法」。

## 验收（`verify_zombie_goo_death_vfx`，samples=14）

机制层：资产契约（AssetID/版本/寿命/三部分计数/按名取件/绿色主导含本色对照）、灯真源（峰值/半程/归零/回收归零/早于停留窗口）、
爆炸粒子节奏（尺度 4.6 倍 + 出生不挤 + 峰值外推 + 窗口末淡净 + 峰值绝对量）、飞溅粒子节奏（起飞 → 全落地 → 不穿地 + 高度对照）、
地上液体节奏（**停留窗口行为测量**（扫描出 scale/y/alpha 同时冻结的连续区间）/ 出现时刻 / 下沉深度 0.30m / 淡净 / 落在飞溅真实落点 + 落点互不相同对照）、
地面平铺（含倾斜 90° 对照）、`floor_y` 三向对照（深层楼 / 缺省反推一致 / 位移精确跟随）、尺寸线性（几何 1.25 + 灯 0.8）、无碰撞体。

端到端：小僵尸真被识别为 goo 怪种 + 倒地段本就 > 2s（对照有效性）+ 不进死亡显影组 + **死亡同帧模型已收起** +
特效经池借出且不跟随挂点 + 出生在胸口 + `floor_local_y == −0.65` + **2 帧内真的回收** + 结算恰好一次 + 组不残留。
反向对照：**胖子僵尸**必须保留倒地动画与尸体。

反向对照四组（均精准变红后还原复绿）：`GOO_DEATH_KINDS → [exploder]`（红 7 条）、
`PUDDLE_HOLD_SEC → 0.30`（红 2 条）、忽略 `context.floor_y`（红 1 条）、`BURST_RING_START → 0.05`（红 1 条）。

`verify_melee_zombie_death_visibility` 已改写为新契约（死前追踪照旧 / 死后无尸体 / 组不残留 / 结算恰好一次）；
`--negative-untracked` 反向对照精准变红（`corpse group leaked`）。

## 门禁与影响面

- `check_asset_registry.py --ledger vfx`：`asset_count` 32 → **33**、`sha_mismatch` 仍为**既有 14 条**（r17–r21、r26–r34，**新增 0 条**）。
  ⚠️ 这 14 条是 2026-10-14 00:55 批量重存的欠账，非本次引入；**不要拿它当「本次改坏了」的证据**。
- 账本「资产主表」数据校验（C/K/L 列）范围从 `$37` 扩到 `$38`（否则新行下拉失效）。
- 账本文件里同时有另一会话「枪族弹体尺寸档」的未提交改动，本次在其上增量写入，未覆盖。
- 既有条目 AssetID / 路径 / 状态 / SHA 逐格保留。

## 回归清单（全部 green）

`verify_zombie_goo_death_vfx`、`verify_melee_zombie_death_visibility`（含 negative）、
`verify_fat_zombie03_death_visibility`、`verify_vfx_pool_lifecycle`、`verify_combat_vfx_toon_v002`、
`verify_monster_startup_roar`、`verify_death_blast_vfx`、`verify_3d_enemy_behavior_flow`。

## 下次可能被问到

- **能不能给胖子僵尸也加这个？** 改 `GOO_DEATH_KINDS` 即可，但它同时有 FX01-17 自爆 + FX01-18 地面伤害场，
  两条死亡表现会叠在一起，需要业主先定优先级。
- **粒子想再大/再小？** 动 `BURST_CUBE_BASE`(0.34) / `SPLAT_CUBE_BASE`(0.26) / `PUDDLE_SIDE_BASE`(0.72)，都是线性系数。
- **停留想改成 N 秒？** 直接改 `PUDDLE_HOLD_SEC`，同时把 `TOTAL_LIFETIME` 一起 ±N（否则尾巴会被切掉）。
  验收的 `EXPECTED_PUDDLE_HOLD_SECONDS` 是**硬编码**的，改常量时它会精准变红提醒你同步。
