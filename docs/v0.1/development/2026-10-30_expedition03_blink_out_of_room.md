# 远征03 瞬移怪穿墙：落点算法把怪送出房间

**日期**：2026-10-30
**范围**：`Enemy3D._blink_to_random()` / `_tick_egt_wander()` / `Dungeon3D._spawn_enemy_batch()`
**起因**：业主报单「我发现了这只怪物，瞬移后就无法被子弹打中，而且它的子弹也无法击中玩家。」并附截图（`egt_hollowpoint`，空尖弹）。

## 1. 从症状直接定位

「**双向都打不中**」是这次最关键的信息。三种症状对应三种完全不同的病灶：

| 症状 | 病灶范围 |
|---|---|
| 只有玩家打不中它 | 命中盒 / 碰撞层 / 无敌帧 |
| 只有它的子弹打不中玩家 | 弹道 / 发射点 / 玩家碰撞层 |
| **双向都打不中** | **两者不在同一空间** —— 中间隔了东西 |

所以不用先查命中判定，先查"它到底在哪"。

## 2. 根因：一个会自增的圆形近似

```gdscript
func _is_point_inside_room_hint(point: Vector3) -> bool:
	var limit := maxf(6.0, global_position.distance_to(_home_position) + 6.0)
	return point.distance_to(_home_position) <= limit
```

这段代码原本的意图是"只作别穿墙的软约束"。但它有两个叠加的缺陷：

1. **用圆形判矩形**。房间是矩形。25×25 的房，沿边只有 12.5m，半对角线 17.7m ——
   圆形近似在角落方向宽松 42%。
2. **半径依赖当前位置**：`limit = 当前距出生点 + 6`。每瞬移一次，当前位置更远 ⇒ 下一次允许更远。
   于是**永远不会判出界**，只会加速外飘。

失败兜底也没救：`target = global_position + offset * 0.5` 只把这一次位移折半，下次 `limit` 照样涨。

**实测**（`tools/_egt_blink_probe.gd`，真实 25×25 战斗房，600 次瞬移）：

```
egt_hollowpoint  瞬移 600 次：出房 502 次（84%），最远超界 99.84m
egt_hollowpoint  瞬移 600 次：出房 422 次（70%），最远超界 50.20m
```

99.84m = 已经飘到好几间房之外。玩家看到怪还在画面里，是因为房间墙只有 2.8m 高、
俯视相机能越过墙顶看到墙外一小片 —— 但子弹打在墙上，它的子弹也打在墙上。

## 3. 同一模式的第二个受害者

`_tick_egt_wander()`（枪精灵 `egt_gun_fairy`）是同一个写法：

```gdscript
_wander_target = _home_position + Vector3(cos(angle), 0, sin(angle)) * radius * sqrt(randf())
```

以**出生点**为圆心画 8m 的圆。而出生点通常落在房间角落（刷怪盒按格心摆），
从角落画圆有一半在墙外。

游荡是"走过去"不是瞬移，所以不会穿墙 —— 但怪会一直朝墙外那个点走：

```
egt_gun_fairy  取 600 个游荡目标点：出房 348 个（58%），最远超界 5.91m
```

表现是**贴着墙原地抽搐，永远到不了目标点**。血量照掉、不报错、机制静默失效。

## 4. 修法

### 4.1 几何由知道房间的那一层注入

```gdscript
# Dungeon3D._spawn_enemy_batch()，紧跟 enemy.global_position = spawn_positions[index]
var room_half := room.get_dimensions() * 0.5
enemy.set_room_bounds(room.global_transform, room_half)
```

为什么不自己拿：`Enemy3D` 只有 `room_id` 字符串，没有房间引用。
让它去查房表等于把"关卡信息"塞进怪物行为层，也会破坏解耦检查
（`scripts/check_level_decoupling.py`）。注入是唯一干净的接法。

放在 `_spawn_enemy_batch()` 里还有一个好处：**召唤与分裂也走这个函数**
（`_reserve_room_spawn` → `_spawn_enemy_batch`），所以子代怪自动继承约束，不用改两处。

### 4.2 clamp 而不是重抽

```gdscript
func _clamp_into_room(point: Vector3) -> Vector3:
	var local := _room_bounds_transform.affine_inverse() * point
	var margin := get_world_body_radius() + 0.6
	var limit_x := maxf(0.0, _room_bounds_half.x - margin)
	var limit_z := maxf(0.0, _room_bounds_half.y - margin)
	local.x = clampf(local.x, -limit_x, limit_x)
	local.z = clampf(local.z, -limit_z, limit_z)
```

| 取舍 | 理由 |
|---|---|
| clamp 而非"重抽直到落点在房内" | 小房间 + 大半径时重抽可能空转；clamp 一次成功，分布仍随机 |
| 留 `半径 + 0.6` 边距 | 瞬移直接改 transform、不过碰撞求解。贴墙落地会被下一帧碰撞挤开，表现为"瞬移过去抖一下" |
| 房太小（半边长 < 边距）时退化为房心 | 宁可原地不动，也不要穿墙 |
| **未注入时退回旧路径** | 只有声明 `blink` / `wander` 的怪走到这里，而它们全在远征03 ⇒ 塔楼与测试行为逐字不变 |

### 4.3 修后

| 判据 | 修前 | 修后 |
|---|---|---|
| 瞬移出房（600 次 × 5 只） | 70% ~ 84% | **0%** |
| 游荡目标点出房（600 次） | 58% | **0%** |
| 房内中心可被射线命中 | ✓ | ✓ |
| 真实战斗位移（26 种 / 2 种子） | —— | 无出房、无穿地板 |

## 5. 门禁：三层 + 反向验证

新增三个探针，**能力边界各不相同，不能互相替代**：

| 探针 | 覆盖 | 能抓 | 抓不到 |
|---|---|---|---|
| `_egt_mechanic_probe` | 33 只 | 参数自洽（骨架枚举 / 落点半径 vs 房间 / 弹程 vs 射程 / damage 配对） | **任何运行期行为** |
| `_egt_blink_probe` | 5 只 | 600 次压测真实落点函数 | 只覆盖 blink / wander |
| `_egt_enemy_motion_probe` | 26 种 | 一次性大位移穿墙 | **低频累积漂移** |

### 5.1 为什么 motion 探针不能替代 blink 探针

这是实测出来的，不是推测：**把瞬移的房内约束撤掉后跑 motion 探针，结果仍然全绿。**
因为 3~4 秒窗口里空尖弹只瞬移 1~2 次，而这个 bug 要几十次累积才飘出房。

motion 探针第一次写的时候更糟 —— 把每只怪构造到房里、`set_runtime_active(true,true)`
然后跑 2 秒，结果 **33 只里 32 只位移 0.00m**。原因是 AI 的移动由 `_ai_decision.awareness`
驱动，那要完整感知链（视觉 / 光照 / `MonsterAIManager`），构造出来的怪压根没进战斗。
"没动"被记成"没出房"，拿到 33 只全绿 —— 彻底假绿。

改成"逐间战斗房真进去、真打、真监控"之后，位移才有 4.7~11.2m 的意义。

### 5.2 反向验证（本轮新增的验收规矩）

新门禁必须证明自己**抓得住** bug：

> 故意把被测的约束撤掉 → 确认探针报错 → 恢复。

本轮结果：

| 撤掉的约束 | 探针反应 |
|---|---|
| `wander` 的 clamp | `egt_gun_fairy` 58% 目标点出房，FAIL ✓ |
| `blink` 的 clamp + 矩形判定 | 84% / 70% 出房，FAIL ✓ |

同一轮里，还靠这个思路抓出两处**探针自身的**假绿：

| 假绿 | 现象 | 真因 |
|---|---|---|
| 瞬移压测的射线 | 报"未命中任何物体" | 射线高度写死 y=1.0，浮空怪脚部 y≈1.5、碰撞柱在上方 0.9m —— 射线从脚底穿过 |
| 同一探针第二版 | 报"命中 Player3D" | 玩家与怪都被摆在房心、互相重叠，射线先撞玩家 |

## 6. 验收

| 项 | 结果 |
|---|---|
| `_egt_blink_probe`（新） | OK —— 5 只（真实 2 + 墙角构造 3），出房 0%，房内可命中 |
| `_egt_mechanic_probe`（新） | OK —— 33 只机制参数自洽 |
| `_egt_enemy_motion_probe`（新） | OK —— 26 种 / 2 种子，真实战斗无出房、无穿地板 |
| 其余 13 个 EGT 探针 | 全绿 |
| `verify_3d_enemy_behavior_flow` / `verify_strong_variant_monsters` / `verify_3d_combat_progression_flow` / `verify_reward_ground_handoff` | 全绿 |

## 7. 顺带查清、但没改的

「检查每只怪」这一轮把 33 只过了一遍，除本 bug 外**没有发现第二个运行期机制失效**。
静态自检（`_egt_mechanic_probe`）覆盖的 6 类判据全部通过：

- `attack_style` 均在合法枚举内（9 种骨架）
- 所有 `blink` / `wander` 的 `radius_m` 都装得进它实际出现的房间
- 会开火的怪 `projectile_range = 22.0 > range`（7.5~9.8），`projectile_speed > 0`
- 枪歌者 / 抓握大师 `damage = 0`，其余 17 —— 与攻击方式自洽
- `grab` / `orbit` / `flee` / `support` 骨架都配了对应的 profile 键

已知仍未打通的（与本次 bug 无关，属既有差异）：宝箱拟态未接、硝酸怪线爆仍是圆形、
链枪手链会被墙挡、同房远程开火限流 2 只不可配。
