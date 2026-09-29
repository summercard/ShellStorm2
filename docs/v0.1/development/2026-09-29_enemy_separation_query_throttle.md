# 2026-09-29｜怪物同类分离导致的物理帧预算超支（开枪时卡顿）

业主反馈原话：

> 「帮我检查一下，新增加了怪物碰撞后，玩家使用子弹的过程中严重卡顿。是怎么回事。」

结论先说：**卡顿确实是新加的「怪物同类分离」引入的，但它不是碰撞本身的开销，
而是它把一次半径查询变成了「每物理帧 × 每只激活怪」的固定支出。**
另一半责任在公共核心模块 `GameplaySpatialRegistry3D.query_radius` 自己的两个缺陷。
两边都已修复，实测 120 只怪从 **42.4ms/帧（23.6 FPS）回到 16.3ms/帧（60 FPS）**。

## 一、归因（不是猜，是量出来的）

### 1.1 先确认「是我引入的」

```
git show fe14591e^:src/enemy3d/Enemy3D.gd | grep -c "_apply_separation"   # 0
grep -c "_apply_separation" src/enemy3d/Enemy3D.gd                       # 2
```

`_apply_separation` 是本次新增，改动前不存在 —— 所以「每帧一次的同类分离查询」
确实是新支出。

### 1.2 但「`TIME_PHYSICS_PROCESS` 指标不可用」

第一轮探针用 `Performance.TIME_PHYSICS_PROCESS` 测量，同一配置（10 只怪）两次跑出
`21.3ms` 和 `56.1ms`，**完全不可重复**；而同时测的墙钟物理帧间隔稳定在 16.2~16.7ms。
说明 headless 下该引擎计时器被主循环等待时间污染，**不能作为判据**。

改用的可靠指标有两个：
- `GameplaySpatialRegistry3D.get_snapshot().query_count` 的**帧均增量**（纯计数，确定性）
- 相邻 `physics_frame` 之间的**墙钟间隔**（端到端帧率）

### 1.3 量出来的账

探针：只放地板 + N 只全身激活的 `melee_chaser`，跑 150 物理帧。

| N | 查询次数/帧 | 单次查询 | **真实帧间隔** |
| --- | --- | --- | --- |
| 0 | 0.00 | — | 16.67 ms |
| 10 | 10.40 | 94 µs | 16.35 ms |
| 30 | 31.20 | 124 µs | 16.38 ms |
| 60 | 62.40 | 167 µs | 16.29 ms（最差单帧 31.8ms） |
| **120** | **124.80** | **263 µs** | **42.38 ms ⇒ 23.6 FPS** |

两个关键读数：

1. **查询次数/帧 精确等于 N**（1.04×N）——**每只怪每物理帧一次半径查询**，与代码一致。
2. **单次 `query_radius` 要 94~263 微秒**。把空注册表也拿来测（一只怪都没有）：
   **固定成本就有 75~185 微秒** —— 也就是说成本的大头在「扫桶」本身，不在邻居计算。

### 1.4 为什么症状是「玩家使用子弹的过程中」

这一条不是猜的，链路是明确的：

- `Dungeon3D.ENEMY_PREACTIVATION_RANGE = 38.0` —— 玩家 **38 米**内的怪全部被激活，
  而只有激活怪的 `physics_process` 是开着的（`set_runtime_active` 里
  `set_physics_process(active)`）。**38m 半径下同时激活几十只是常态。**
- 于是「开枪」正好是放大器：
  1. `WeaponModel3D.gd:495` 与 `Projectile3D.gd:283` **每开一枪都各调一次
     `broadcast_sound_stimulus`**，而它内部又调一次 `query_radius`；
  2. 枪声把 38m 内本来没醒的怪唤醒 ⇒ **激活集合变大，且不会自己变小** ⇒
     分离查询的每帧支出**永久上升**；
  3. 再叠加子弹、命中特效、伤害数字本身的成本，就越过了 16.7ms 预算。

所以不是「子弹和怪碰撞」贵，是**开枪把怪叫醒了，每只醒着的怪每帧要交一次查询费**。

## 二、根因：`query_radius` 自己的两个缺陷

### 2.1 每个候选桶都用字符串格式化生成 key

```gdscript
var key := _coords_key(center + Vector3i(x_offset, floor_offset, z_offset))  # "%d:%d:%d" % [...]
```

`_coords_key` 原来是 `"%d:%d:%d" % [coords.x, coords.y, coords.z]`。
一次查询要**几十次**字符串格式化，每次约 1~4 微秒且每次新建一个 `String` ——
**这就是「空注册表也要 75~185 微秒」的来源**。

### 2.2 桶扫描范围被 `+1` 放大成 75 个桶

```gdscript
var bucket_radius := maxi(1, ceili(maxf(0.0, radius) / BUCKET_SIZE_M) + 1)
```

`BUCKET_SIZE_M = 16`，分离查询半径约 3m ⇒ `ceili(3/16) = 1` ⇒ `+1 = 2`
⇒ 循环 `3(层) × 5 × 5 = `**75 个桶**。
但相邻桶心只相距 16m，**`ceili(radius/16)` 个桶就已经覆盖整个查询半径**，
多出来的 48 个桶永远是空的。3m 查询实际只需要 `3 × 3 × 3 = 27` 个桶。

### 2.3 `ids.keys()` 每次查询都为每个桶新建数组

```gdscript
for instance_id_value in ids.keys():
```

`Dictionary.keys()` 返回一个新 `Array`。GDScript 里 `for k in dict` 直接迭代 key，
不需要这个中间数组。

## 三、修复

### 3.1 `src/core/GameplaySpatialRegistry3D.gd`（公共核心，同时惠及光照与枪声）

| 改动 | 依据 |
| --- | --- |
| 桶 key 从字符串改为**整数位打包** | 每轴 10 位、偏移 ±512 桶。实际地图 `250×250m`（±8 桶）、塔楼 100 层 × 12m（y 桶 0~100），余量充足 |
| `bucket_radius` 去掉 `+1`，改用 `ceili(radius / BUCKET_SIZE_M)` | 相邻桶心相距 16m，该值即已覆盖查询半径。半径 3m ⇒ 27 桶；半径 28m（光源）⇒ 仍是 75 桶，**不退化** |
| `ids.keys()` → `for key in ids:` | 免掉每桶一次数组分配 |
| `str(record.get("kind")) not in kinds` → `kinds.has(record.get("kind"))` | 免掉 Variant→String 转换 |

`BUCKET_KEY_NONE := -1` 作为「尚未入桶」哨兵（打包结果恒非负，不会与真实 key 冲突）。

### 3.2 `src/enemy3d/Enemy3D.gd`（分离力自身降频错峰）

新增 `SEPARATION_INTERVAL_FRAMES := 3`：
- 分离是「视觉上不要叠在一起」的**软约束**，20Hz 足够；
- 中间帧沿用上一次的推力向量（`_separation_push` 缓存）；
- **相位按实例 ID 固定错开**（`absi(get_instance_id()) % 3`），
  避免全场怪在同一帧集体查询造成尖峰 —— 否则每 3 帧一次的 6ms 尖峰比均匀 2ms 更难看；
- 原来的 `_apply_separation` 拆成「取缓存 / 算推力」两半（`_compute_separation_push`）。

## 四、修复后实测

| N | 查询次数/帧 | 单次查询 | 空查询固定成本 | 真实帧间隔 |
| --- | --- | --- | --- | --- |
| 10 | 10.40 → **3.73** | 94 → **28 µs** | — → 12 µs | 16.35 → 16.59 ms |
| 30 | 31.20 → **11.20** | 124 → **60 µs** | 160 → 13 µs | 16.38 → 16.62 ms |
| 60 | 62.40 → **22.40** | 167 → **105 µs** | 75 → 12 µs | 16.29 → 16.37 ms |
| 120 | 124.80 → **44.80** | 263 → **197 µs** | — → 12 µs | **42.38 → 16.31 ms（23.6 → 60 FPS）** |

- **空查询固定成本降 85%+**（75~185 µs → 12 µs）：证明「字符串 key + 75 桶」是主因。
- **查询次数降到 1/3**：降频生效。
- **120 只怪（极端最坏，全挤在一小片）恢复满帧**。真实场景怪分散在不同桶，
  候选遍历更少，会明显好于这个数。
- 大 N 时单次仍偏高（197 µs）是因为探针把所有怪挤在同一桶，
  `_resolve()` 要逐个解弱引用；这是探针的最坏情况，不是实测分布。

## 五、验收

`verify_3d_enemy_behavior_flow` 新增**第 9 条：分离查询节拍契约**。

用**查询计数**而不是耗时做断言 —— 计数是确定性的，不会因机器负载抖动：

- `SEPARATION_INTERVAL_FRAMES > 1`（防「退回每帧」）；
- 32 只激活怪跑 60 物理帧，帧均查询数 **不得超过 `N / INTERVAL × 2.0`**
  （余量 2 倍是给光照传感器等其他 `query_radius` 调用方的，它们每 0.12s 一次）；
- **下界**：帧均查询数不得低于 `N / INTERVAL × 0.5` ——
  否则说明夹具没真的跑出分离查询，上界断言会变成恒真的假绿。

**三条都做了反向验证（把参数改坏，确认断言变红）**：

| 反向实验 | 期望 | 实测 |
| --- | --- | --- |
| `SEPARATION_INTERVAL_FRAMES` 改回 1 | 报间隔回退 | ✅ `Separation recompute interval fell back to every frame` |
| 上界系数 2.0 → 0.01 | 报未节流 | ✅ `Separation queries are not throttled: 10.9 per frame, budget 0.1 (N=32)` |
| 下界系数 0.5 → 100 | 报夹具空转 | ✅ `Cadence fixture did not exercise separation queries: 10.8 per frame (N=32)` |

正向实测 **10.9 次/帧**，与 `32 / 3 = 10.67` 精确吻合 —— 夹具确实在测分离查询本身。

回归（`godot --headless`，独立 APPDATA）：`verify_3d_enemy_behavior_flow`、
`verify_monster_ai_system_complete`、`verify_monster_ai_light_effects`、
`verify_enemy_stimulus_activation`、`verify_enemy_illumination_states`、
`verify_3d_melee_feedback_flow`、`verify_first_elite_deployment_flow`、
`verify_reward_ground_handoff`、`verify_3d_flashlight_charge_flow` **全部 OK**。
光照与枪声专项特意纳入 —— 它们与分离力共用同一个 `query_radius`。

## 六、遗留与教训

1. **`query_radius` 单次在大候选量下仍可达 200 µs**，成本重心已从「扫桶」转到
   `_resolve()` 的逐候选弱引用解引用。当前实测已满足预算，暂不继续优化；
   若以后同桶怪数继续上升，下一步是给它加「候选上限」参数。
2. **`HEADLESS` 下不要用 `Performance.TIME_PHYSICS_PROCESS` 判性能** ——
   实测同配置抖动 21ms↔56ms。用 `query_count` 增量或墙钟帧间隔。
3. **不要在这个工作区用 `git stash` 做前后对照** ——
   本机 git 的 `stash push <path>` 会把**整个工作区** stash 走，而工作区有
   并发会话在改文件并提交；pop 时极易撞上别人的在途改动而 `Aborting`，
   造成「自己的改动看起来消失了」。本次就撞上一次（实际是我的改动已被并发会话
   随 `fe14591e` 提交，虚惊一场）。需要版本对照时改用只读方式：
   `git show <rev>:<path>` 或 `git worktree`。
