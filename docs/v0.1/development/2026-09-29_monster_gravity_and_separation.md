# 2026-09-29｜怪物重力与地面口径 + 怪与怪按权重分离

业主原话：

> 「怪物和怪物之间的这个叠嘛，它是可以跑到阻挡上面去的，然后并且要给我加上一个重力。因为现在的怪物如果没有地板的，出来它还会悬空在那个面上，所以这个是不符合逻辑的，它得向角色一样。如果有洞的话，它会掉下去，它也可以走上坡和下坡。然后，如果很多怪堆叠在一起，实在没办法，比如说四只怪围着一只怪，并且往这一只怪挤的话，然后这只怪会不会挤到上面去？但是它不会被挤到地板下面去。按照这个逻辑去做，然后在做这个逻辑的时候，不要做得太复杂，用一些简单的碰撞逻辑去给他做一些权重就可以了。」

## 一、现状（改前）

`Enemy3D` 是 `CharacterBody3D`，但**速度里从来没有 y**：所有转向、刹车、击退
都写成 `velocity = ...`，而目标速度的 y 恒为 0，`velocity.y` 于是被一路拉向 0。
后果是脚下没有承重面时怪**悬在原高度不落**；同时 `move_and_slide()` 遇到阻挡时
沿面滑动，怪能顺着阻挡爬到顶面。

怪与怪之间：`collision_layer = 4 / collision_mask = 1`，mask 里没有自己那一层，
所以怪**彼此完全不碰**，30 只怪会叠在同一格。`_apply_local_avoidance` 的探路射线
mask 也是 `1`（只探关卡静态世界），`NavigationAgent3D.avoidance_enabled = false`，
两条避让通路都没开。

而 06A 的 17.2 早已把「小菌猪直压、突进与本地避障共同工作，不重叠穿模」
勾成完成 —— 本次是把这条做实。

## 二、改法

### 2.1 垂直方向只有重力和地面（`Enemy3D.gd`）

与 `Player3D` 取同一套口径，不另立参数：

| 常量 | 值 | 与 Player3D 的关系 |
| --- | --- | --- |
| `GRAVITY_MPS2` | 24.0 | 同值 |
| `TERMINAL_FALL_SPEED_MPS` | 32.0 | 同值 |
| `FLOOR_STICK_MPS` | -0.01 | 同「极小负值让 floor snap 保持接触」 |
| `floor_snap_length` | 0.32 | 同值 |
| `floor_max_angle` | `deg_to_rad(44.0)` | 同值 |
| `motion_mode` / `up_direction` | `GROUNDED` / `Vector3.UP` | 同值 |
| `floor_stop_on_slope` / `floor_constant_speed` | `true` | 同值 |
| `safe_margin` | 0.035 | 同值 |

44° 以内算可走的坡（能走上走下），更陡的面算墙 —— 怪不会顺着阻挡爬到顶面；
`floor_snap` 只跨数厘米接缝，不用它模拟楼梯。

为保证**没有一条通路能顺手改动 `velocity.y`**，新增四个水平写入口并把全部
11 处速度赋值改造过去：

| 新入口 | 作用 |
| --- | --- |
| `_steer_planar(target, weight)` | 水平分量按权重逼近目标 |
| `_brake_planar(amount)` | 水平刹车 |
| `_stop_planar()` | 水平归零 |
| `_push_planar(vector)` | 水平叠加（击退） |
| `_commit_motion(delta)` | **唯一的 `move_and_slide()` 出口**：先分离、再重力、后推进 |

改造点：`idle/alert` 刹车、ambusher 埋伏刹车、`telegraph`/`recovery` 刹车、
`stagger` 击退、`_tick_chase`/`_tick_search`/`_tick_return`/`_tick_patrol`、
`_tick_elite_escape`、`_track_stuck_recovery` 的横向脱困、`_tick_return` 到家的归零。

### 2.2 怪与怪按距离权重水平分离

不遍历节点树，直接查已有的空间索引（16m 分桶）：

```
邻居 = GameplaySpatialRegistry3D.query_radius(global_position, 自身体半径 + 2.4, [KIND_ENEMY])
最小间距 = (自身世界碰撞半径 + 对方世界碰撞半径) × 0.90
权重     = 1 - 距离 / 最小间距          # 贴得越近推得越狠，刚好挨着几乎不推
推力速度 = 自身移动速度 × 0.62 × min(Σ权重, 1)
```

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `SEPARATION_WEIGHT` | 0.62 | 推力占自身移动速度的比例 |
| `SEPARATION_RADIUS_SCALE` | 0.90 | 最小间距相对「双方半径和」的收紧系数 |
| `SEPARATION_NEIGHBOR_LIMIT` | 8 | 单帧参与计算的邻居上限 |
| `SEPARATION_PROBE_MARGIN_M` | 2.4 | 查询半径余量，覆盖最大 Boss 世界碰撞半径 |

世界碰撞半径取 `get_world_body_radius() = 碰撞柱 radius × scale.x`，与
`get_state_snapshot().world_collision_radius` 同源，不引入第二套体型数据。
完全重合时按实例 ID 取固定切向拆开，确定性、不用随机数、不产生 NaN。

**关键点：分离只写水平分量。** 所以四只怪围挤中间的怪时，水平推力互相抵消，
中间的怪只会被夹在原地 —— 既不会被顶到同伴头顶，也不会被挤到地板以下。

> 后续（同日）：本节这套「每只怪每物理帧查一次同类邻居」的实现造成了物理帧预算超支，
> 表现为**开枪时严重卡顿**（枪声唤醒怪 ⇒ 激活集合变大 ⇒ 每帧查询次数永久上升）。
> 已改为 20Hz 错峰重算，并修掉了 `query_radius` 自身两个缺陷。
> 见 `2026-09-29_enemy_separation_query_throttle.md`。

### 2.3 掉出可行走层：超过 15m 直接判死

重力生效后，脚下真出现洞的怪会离开房间。掉落超过出生点下方 `15m`
（`FALL_DEATH_DROP_M`）即判定已离开可行走层，**直接走标准死亡流程**
（`_die()`：击杀结算、死亡特效、房间计数、精英名册）—— 房间因此不会因
「有怪但打不到」永远清不掉。

判死而不是拉回出生点：拉回会让一只明明掉下深渊的怪原地复活，穿帮且反直觉。
早期实现（同日第一版）是 `8m` 拉回出生点，已废弃。

**取值下界由塔楼层高决定。** 塔楼整层层高 `TowerGeometry3D.FLOOR_HEIGHT_M = 12.0`，
半层 6m；怪沿楼梯/连接通道追玩家下一层时是 12m 级落差，**不能算掉出世界**。
`15m` 因此是「整层落差 12m 之上再留 3m」的安全余量。
真的掉出世界是无限下坠，重力 `24 m/s²` 下 1.1s 就过 15m，判死依然及时。

**判死前先落回出生点。** `Dungeon3D._on_enemy_killed` 用敌人当前位置投递地面掉落
（`_deliver_ground_rewards(..., enemy.global_position, ...)`），而落点只做
`+3m / -4m` 的向下支撑探测（`_find_supported_spawn_position`）—— 在虚空里探不到
承重面，奖励会挂在够不着的半空。出生点是同一房间内保证可行走的点，落回后再
`_die()`，掉落物和死亡特效都落在玩家拿得到、看得见的地方。

### 2.4 刻意不做的部分

- **不加硬物理互撞**：怪与怪的 `collision_mask` 仍为 `1`（只碰关卡静态世界）。
  硬互撞会在窄门和房间入口造成堵死，且寻路器不知道彼此的路径点，容易死锁。
- **不改避障射线与视野/受光遮挡射线的 mask**：两者继续只探关卡静态世界。
  06 的 7.3 明确要求「不让相邻怪物短暂经过造成整群怪物受光状态闪烁」，
  把相邻怪当障碍物会直接违反该口径。怪与怪的感知改由空间索引承担。

## 三、验收

### 3.1 新增断言（`verify_3d_enemy_behavior_flow`）

新专项 `_verify_vertical_physics_and_separation`，并在玩家入场前执行
（避免「全部扑向玩家」污染分离断言）：

1. **无承重面必须下坠**：在 ±100m 承重面之外的 `(-150, 3, 0)` 生成，30 物理帧后
   `y` 至少下降 0.5m。
2. **有承重面必须落地且不穿地**：从 `y=3` 落到地板，120 帧后 `is_on_floor()` 为真
   且 `|y| ≤ 0.08`。
3. **地面口径与 Player3D 同源**：`floor_max_angle == 44°`、`motion_mode == GROUNDED`、
   `up_direction == UP`。
4. **重叠必然被拆开**：同点错开 0.05m 生成两只，180 帧后水平间距
   ≥ 双方世界碰撞半径和 × 0.90 的 90%。
5. **分离无垂直分量**：五只怪挤成一点，180 帧后**每一只**的 `|y| ≤ 0.12`。
6. **判死深度必须深于塔楼一层**：`FALL_DEATH_DROP_M > 12.0`。
7. **一层落差（12m）不准死**：承重面顶面放在出生点下方 12m，240 帧后既不是
   `dead`，也正常落在 `y = -9.0` 上（容差 0.10m）—— 证明怪走楼梯下一层不会被误杀，
   也证明它**没有**被拉回出生点。
8. **超过判死深度必死**：承重面顶面放在出生点下方 23m（到不了），怪在
   `y ≤ 出生点 - 15m + 1m` 的范围内死亡 —— 容差 1m 是因为判死在每帧开头按
   上一帧位移后的位置结算，最后一次存活取样必然停在触发线上方不到一帧的
   下落距离（末端速度 32m/s ⇒ 约 0.53m）。

同时该场景补了 200×200 的承重面：怪物有重力后，没有地面的验收台会让
位置类断言失去意义。

### 3.2 连带修复

`verify_monster_ai_light_effects` 的两条追击断言在改动后失败，回退对照确认是本次引入：
该验收台的 `_verify_flashlight_hunter` / `_verify_proximity_and_damage_aggro` 会激活
怪物物理，而验收台没有地面，怪一路下坠 —— 垂直位移（0.65s ≈ 5.07m）直接抵消并超过
水平接近量，`distance_to` 的三维距离于是从 `8.000` 反向涨到 `8.055`。
**修法是给该验收台补 200×200 承重面，不是放宽断言**；补面后原样通过。

### 3.3 实跑结果（`godot --headless`，独立 APPDATA）

| 场景 | 结果 |
| --- | --- |
| `verify_3d_enemy_behavior_flow` | **OK**（含新增 5 条断言） |
| `verify_monster_ai_light_effects` | **OK**（补承重面后） |
| `verify_monster_ai_system_complete` | OK |
| `verify_enemy_illumination_states` | OK |
| `verify_enemy_stimulus_activation` | OK |
| `verify_3d_melee_feedback_flow` | OK |
| `verify_first_elite_deployment_flow` | OK |

对照归因（回退本次改动后重跑，确认失败与本次无关）：

- `verify_3d_melee_combat_flow`：`Adding melee changed the eight-state locomotion machine` —— 回退后同样失败，属玩家八态移动机既有问题。
- `verify_3d_melee_combat_visual`：武器视觉预览缺四条挥砍弧 —— 与怪物无关。
- `verify_3d_parity_core`：房间流式节点预算 2391/2200 超限 —— 与怪物无关。
- `verify_ai_performance_soak`：600s 内未跑完（soak 档），非断言失败。

### 3.4 已知债务（不是本次引入）

`python3 scripts/check_documentation_contracts.py` 报三个场景未登记：
`verify_base99_swivel_chairs`、`verify_expedition01_spawn_ramp`、`verify_pushable_base_chairs`。
三个文件均已在 `d2789750` 提交且工作区无改动，与本次无关，未擅自代登记。

## 四、遗留风险

1. **分离力的性能开销**：每只怪每物理帧一次 `query_radius`。30 只怪 = 30 次/帧，
   桶查询只扫本格，实测无尖峰，但 `verify_ai_performance_soak` 需要在完整预算内
   复跑一次确认（本次 600s 未跑完，无法给出该结论）。
2. **分离力与接敌槽位的分工**：`MonsterAIManager` 已有近战/远程攻击令牌限制同时出手，
   分离力只负责「不叠在一起」。两者的交互待一次 30 只怪的实机观察确认。
3. **正式关卡必须有地板碰撞**：重力生效后，任何缺承重面的房间都会让怪掉到
   `出生点 - 15m` 判死。正式房间的地板是 layer 1 的 StaticBody，正常成立；
   新增房间类型时需要把「地板碰撞存在」纳入房间自检。
4. **掉出世界按「被击杀」结算**：`_die()` 走的是标准死亡流程，所以掉出世界的怪
   会照常发掉落、记击杀数、给精英名册记 `killed`。`Elite.*` 唯一精英如果在掉洞里
   死亡，名册会当玩家击杀处理。当前塔楼与房间都没有能让怪主动走进去的开放缺口
   （房间地板与坑区都保留承重），所以这是理论路径；若以后出现「可把怪推下深坑」
   的交互，需要决定这类死亡是否仍发全额奖励。
