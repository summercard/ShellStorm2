# 远征03 房门：可开启 / 不可开启（2026-10-30）

## 1. 业主报单

> 「远征03 的这个门的状态，使用可开启和不可开启。在可开启状态，人走近了会自动打开，
> 然后再关闭。不可开启状态人走近了不会打开。」

配图为入口安全屋朝北那扇 ARCHIVE 03 双扇滑门。范围：**房门语义**，不含墙、不含黑幕。

## 2. 上一版为什么不够

上一轮（`2026-10-30_expedition03_door_open_state.md`）只解决了「门看起来还在」：
门板开到位后贴到墙内侧，画面上不再是一个空门洞。

但**状态本身还是只有两个**：开着（清完房就永远敞开）／关死（封锁中）。
业主这次要的是第三种东西 —— **关着但能开**。判据：

| 位置 | 权限 | 上一版表现 |
|---|---|---|
| 开 | 可开启 | 清完房一直敞开，走近没有任何反馈 |
| 关 | 不可开启 | 只在战斗封锁中出现 |

也就是说：「可开启」这个状态在画面上根本不存在，玩家读不出「这扇门能不能过」。
更糟的是衔接：清房瞬间门自动开到最大，玩家看不到「门是被我推开的」这件事。

## 3. 改法：把「权限」和「位置」拆成两个正交量

`RoomDoor3D` 新增 `openable`（权限），与既有 `is_open`（门板位置）分离：

| 状态 | 判据 | 走近 | 画面 |
|---|---|---|---|
| **可开启** | 房间未封锁（连通门） | 自动双扇滑开；走远超过 4.4m 停 0.45s 自动关 | 关：门板在门洞；开：两扇贴墙 |
| **不可开启** | 战斗封锁 / 封闭抵达门（退局气闸） | 纹丝不动 | 关：门板在门洞 |

### 3.1 数值口径（都是推出来的，不是拍的）

| 常量 | 值 | 推导 |
|---|---|---|
| `PROXIMITY_OPEN_DISTANCE_M` | 3.6 | 玩家步速约 5.5 m/s，3.6m 约 0.65s；门动画 0.24s ⇒ **人走到门前门已开完**。取 3.6 而非 3.4（交互距离）是为了不与 E 提示抢同一帧 |
| `PROXIMITY_CLOSE_DISTANCE_M` | 4.4 | 开阈 + 0.8m 的**迟滞带**。没有迟滞时站在门槛附近会按浮点抖动反复开合 |
| `PROXIMITY_CLOSE_DELAY_S` | 0.45 | 走远后先留半秒：回头能赶上，也不至于门在身后"啪"地砸上 |

门板行程、碰撞禁用时机、`is_open` 语义**一个字没改** —— 只多了驱动它的时机。

### 3.2 谁改权限（唯一推导点）

`TowerDescent3D._sync_flow_room_doors()` 的返回从 `{opened, closed}` 改成
`{openable, closed}`，内部从 `set_open(true)` 改成 `set_openable(true)`：

| 目标 | 权限 |
|---|---|
| `door_targets` 目标为真实房间 | `not 本房封锁中` |
| `door_targets` 目标为空串（退局气闸） | **恒 false** |

三处入口都经过它，且都只翻权限、不替玩家推门：

- `_open_all_flow_doors()`（装配收尾）
- `_apply_flow_room_seal()` 的 `cleared` / 和平房分支
- `_on_room_unsealed()`（清房）

另加一个**必须的覆盖**：`set_room_seal()`。基类只关本房门扇，不懂 flow 权限 ——
不覆盖的话封锁期间门仍是「可开启」，玩家走近就把自己放出去了（战斗中被自己开门放走）。

### 3.3 共享边的坑

门扇只在**一端**手里（另一端 `_door_nodes` 里没有节点）。旧实现遍历本房
`door_targets` 取节点，取不到就 `continue`。共享边另一侧那扇门于是永远是
「可开启」—— 战斗中被身体顶开就走出去了。

现在本房取不到时，按"通向哪一间"去对端 `get_door_node_towards()` 取同一扇。

### 3.4 交互退役

感应门不接受 E：`is_manual_interaction_enabled()` 为假 ⇒
`Dungeon3D.get_interaction_candidate()` 直接返回空，交互圆点与提示都不亮。

不退役会打架：玩家站在门口看圆点亮着按 E，门却已经自己开了 —— 会以为门卡住。
退局气闸走 `_get_configured_base_door_bindings()` 的独立通道，不受影响。

## 4. 验收

### 4.1 数据判据（`probe_expedition03_playable`）

新增一段 `proximity`，**走真实感应**（把玩家钉在门边 / 房心，让 `_process()` 自己判）：

```text
PLAYABLE unseal room=hub_01 sealed=false openable_leaves=8 open_leaves=0
PLAYABLE proximity room=hub_01 door=Door_North_P1 dir=north away_m=20.00 open_near=true still_open_away=false
PLAYABLE_OK
```

三条新断言，缺一条都算红：

| 断言 | 防什么 |
|---|---|
| 清房后 `openable_leaves > 0` | 权限没翻回来 ⇒ 已清房变死路 |
| 清房后 `open_leaves == 0` | 又退回「清完就敞开」，可开启态消失 |
| 走近开 / 走远关 | 感应器没绑上（`_bind_flow_door_proximity` 漏跑） |

`probe_expedition03_save_doors` / `probe_expedition03_save_roundtrip` 的 A3 段同步改成查
`openable` + `proximity_auto`，并新增 A5：进已清房后 `unopenable` 必须归零。

### 4.2 真实渲染取证

`capture_expedition03_door_state` 重写为四态同机位：

```text
E3_DOORSTATES openable_closed  cleared=true sealed=false openable=true  open=false panel_x=-0.55 panel_z=0.00 blocks=true
E3_DOORSTATES openable_near    cleared=true sealed=false openable=true  open=true  panel_x=-1.71 panel_z=0.23 blocks=false
E3_DOORSTATES auto_open_near=true
E3_DOORSTATES openable_away    cleared=true sealed=false openable=true  open=false panel_x=-0.55 panel_z=0.00 blocks=true
E3_DOORSTATES auto_close_away=true
E3_DOORSTATES locked_near      cleared=true sealed=true  openable=false open=false panel_x=-0.55 panel_z=0.00 blocks=true
E3_DOORSTATES locked_open_near=false（必须为 false）
```

产出（`outputs/expedition03_door_states_20261030/`）：

| 文件 | 内容 |
|---|---|
| `e3_doorstates_0_openable_closed.png` | 可开启·静止：双扇合拢，ARCHIVE 03 门面完整 |
| `e3_doorstates_1_openable_near.png` | 可开启·走近 1.5m：双扇滑开，门洞全通、能看到隔壁 |
| `e3_doorstates_2_openable_away.png` | 可开启·走远：0.45s 后自动关回门洞（与 0 逐像素同态） |
| `e3_doorstates_3_locked_near.png` | 不可开启·走近：门板纹丝不动，与 0 唯一差别是 `sealed=true` |

**②与④是这次的关键对照**：同一个人、同一距离、同一条走路路径，
唯一差别是 `openable`。门开了 / 没开，证明权限真的在起作用，
而不是被位置判断或时序碰巧盖住。

### 4.3 回归

| 套件 | 结果 |
|---|---|
| `probe_expedition03_playable` | `PLAYABLE_OK` |
| `probe_expedition03_save_roundtrip` | `STATE_PROBE` 全 PASS（14 项） |
| `probe_expedition03_save_doors` | 气闸门 `openable=false`、连通门 `openable=true`，门板不再被推开 |

## 5. 踩的坑

| 坑 | 表现 | 处理 |
|---|---|---|
| 绑定做成「全局只做一次」 | 后面建的房间拿不到感应器 ⇒ 所有门都不开 | `_sync_flow_room_doors()` 按房间绑，`_process` 兜底补绑 |
| 退局气闸被一起绑了 | `is_manual_interaction_enabled()` 变假 ⇒ 「[E] 退出战局」消失 | 绑定时跳过 `target_room_id` 为空的封闭抵达门 |
| 探针把 `_hold_player_at` 的返回当成门态 | 报「走远后门没关」，实际 `snapshot` 里 `is_open=false` | 辅助函数改成纯位移；门态由调用方在 await 之后直接读 |
| 探针把玩家钉在门边却让物理纠正回房心 | 一帧就"走远了"，走近那条永远测不到 | 逐帧钉（每帧重设位置 + 清零速度） |
| 取证相机 `look_at()` 早于 `add_child()` | `Node not inside tree`，机位静默不对 | 先入树再定位 |
| 出生点本来就贴着安全屋北门 | A3b 断言「门应是关的」假红 | 改查 `proximity_auto`（驱动方式），不查当下开没开 |

## 6. 改动清单

| 文件 | 改动 |
|---|---|
| `src/world3d/RoomDoor3D.gd` | 新增 `openable` / `set_openable()` / `set_proximity_target()` / `has_proximity_target()` / `is_manual_interaction_enabled()` / `_process()` 感应；`get_snapshot()` 增 `openable`、`proximity_auto`；提示文案补「门扇已落下·无法开启」；`_build()` 末尾 `set_process(false)`（未绑感应器的门不跑 _process） |
| `src/world3d/TowerDescent3D.gd` | `_sync_flow_room_doors()` 改为推导权限（含共享边对端）；新增 `_bind_flow_door_proximity()` / `_bind_proximity_on_room()`（按房间绑、跳过封闭抵达门）；覆盖 `set_room_seal()`；`_on_room_unsealed()` / `_open_all_flow_doors()` 改口径；meta 改 `flow_doors_openable_on_start` |
| `src/world3d/Dungeon3D.gd` | `get_interaction_candidate()` 跳过感应门 |
| `tests/verification/probe_expedition03_playable.gd` | 新增 `_verify_proximity_cycle` + 三条断言，`_openable_leaf_count` |
| `tests/verification/probe_expedition03_save_doors.gd` | dump 增 `openable`，盯门态改盯 `openable` |
| `tests/verification/probe_expedition03_save_roundtrip.gd` | A3 / A3b / A4 / A5 改口径 |
| `tests/verification/capture_expedition03_door_state.gd` | 重写为四态取证；修相机入树顺序 |
| `docs/v0.1/design/远征关卡03设计.md` | §2.1 表格改「门状态」行；§2.1.0 重写为「权限 × 位置」 |

## 7. 取舍记录

- **不存门态**：`openable` 派生自 `cleared` / 封锁，`is_open` 派生自玩家距离。
  存任何一个都会与真值分叉 —— 那正是「门自己开了、存档又记着关」的成因。
- **感应检测目标只有一个玩家，不做 Area3D**：Area3D 需要额外碰撞层与信号，
  且门扇本身已经是 `StaticBody3D`（碰撞体在同一节点上），加 Area 会和门板碰撞
  互相干扰。距离判定每帧一次 `distance_to`，25 扇门总计可忽略。
- **不动塔楼 / 基地 / 远征01-02**：它们的门 `_proximity_target` 恒为 null，
  `_process` 不跑，`openable` 缺省 true 且无人改它 —— 行为逐字不变。
