# 2026-10-16 修复：触发式遭遇封不住入口门（共享门归属 + 绑定）

- **FeatureID**：`ENCOUNTER-EVENT` / `WORLD-SEGMENT`；工程 0.1.0。
- **业主口径**（原话）：*「激活后进来的门还是开着的，还能往房间外走。检查以下」*。
- **症状**：踩点触发式遭遇激活后 `_room_is_sealed(room_id)` 已为真、`get_interaction_candidate()` 也确实
  不再给门交互候选，**但玩家顺着进来那条门巷往外走，能一路走到房外**。数据、其它日志都看不出异常。

## 1. 复现（先做出可重复的复现，再动手）

新建探针 `tests/verification/probe_encounter_seal_door.gd`（保留，属 `probe_*`，按仓内惯例免登记）：

1. 进入 `room_03`，**先把入口那条边打开** —— 玩家在真实游玩里就是从那儿进来的；
   不开边的话入口门本来就是关的，后面"封门后门扇不能是开的"会**空过**（假绿）。
2. 走到房心触发遭遇。
3. 让玩家**沿门巷**（不是沿 z=0，那里是实墙）逐帧往房外走，记最远到达的局部 x。

| | 修复前 | 修复后 |
|---|---|---|
| 封门后 `room_02` 东侧门扇 `is_open` | **true** | **false** |
| 沿门巷走出去最远局部 x | **−23.00**（房外 8 m） | **−14.49**（房内） |

> 探针第一版沿 `z = 0` 直走，撞的是实墙，把"墙挡住了"误读成"封门有效" —— 同一个坑踩了两次。
> 走位必须走**门洞那条线**（端口 `position_m[1]` 给的门巷）。

## 2. 根因（两层，一层是直接原因、一层是为什么它一直没被发现）

`set_room_seal()` 的写法是「遍历本房 `door_targets`，逐个 `set_door_open(方向, false)`」。
但**共享边的门扇只由边的一端建出并持有**（`door_endpoint_owners`）。`room_03` 的入口
（西墙、通向 `room_02`）就是这样：门扇 `Door_West` 挂在 **`room_02` 名下**，
`room_03` 的 `_door_nodes` 里**根本没有这个键**。

```text
direction="west" 在 door_targets 里
  ⇒ get_door_node("west") 返回 null
  ⇒ 循环体什么都不做，也不报错
  ⇒ 封门「成功」返回，门却一直开着
```

**第二层**：为什么 `room_03` 的 `_door_nodes` 里没有入口门 ——
`TowerDescent3D._bind_shared_edge_doors()` 负责把共享门绑进对端，但它取门扇时只认**端口**：

```gdscript
if not owner_port_id.is_empty():
    shared_door = owner.get_door_node_by_port(owner_port_id)
if shared_door == null:
    continue                       # ← 拿到 null 就静默跳过
```

而远征01 的门扇是 `_build_door()` 的**按方向**路径建出的，`_door_nodes_by_port` **始终为空**
⇒ 按端口必然拿到 `null` ⇒ **共享门在本关从未被绑过**。绑定是死代码。

## 3. 修法（两处都做，互为兜底）

| # | 位置 | 改动 |
|---|---|---|
| 1 | `Dungeon3D.set_room_seal()` | 本房取不到门扇时，**按"这扇门通向哪一间"去对端取同一扇**（新增 `DungeonRoom3D.get_door_node_towards(target_room_id)`），拿到后调它的 `set_open(false)`。**不依赖绑定是否成功** |
| 2 | `TowerDescent3D._bind_shared_edge_doors()` | 取门扇时"按端口失败要**回落**按方向"（一墙多门时端口优先，回退只在端口取不到时生效） |

为什么要两处：绑定发生在**场景装配期**，`set_room_seal` 发生在**运行时**，中间隔着一条
"绑定有没有成功"的隐式依赖。只修绑定，将来绑定再出问题，封门又会退化成静默空转。

**不能用"本房方向"去对端查**：共享门两端的方位标号是**镜像**的（本房 `west` ↔ 对端 `east`），
一墙多门时还会张冠李戴。所以 `get_door_node_towards()` 按**目标房 id** 找：
先在本房 `_door_nodes` 里找 `target_room_id` 匹配的，再退到 `door_targets` 里该目标对应的方向。

## 4. 连带修好的两个后果（同一个根因）

绑定生效后，实测（远征01 逐房对比**计划门数**与**运行时登记门数**）：

| 房 | 计划 | 修复前 live | 修复后 live |
|---|---|---|---|
| room_01 / 02 / 03 / 04 / 05 / 06 / 07 / 08 / 09 / 10 | 各 2 | 各 **1**（缺对端那扇） | 各 **2** ✓ |
| boss | 2（east / south） | 2（east / **west**）—— 凑巧相等 | 3（east / south / west） |

⇒ **修复前每间房都缺对端那一扇**，`get_nearest_door()`（只遍历本房 `_door_nodes`）
在本房一侧找不到它 ⇒ 那扇门在本房是**单向门**（进来能进、回去不能回）。
`verify_expedition_room_static_scenes` 的「必须保留全部运行时门」在修复前 **8 间房报错**，
修复后这 8 间全部达标。

**boss 那一条是真阳性，不是本次引入的回归**（见 §6）。

## 5. 验收与对照实验

新增/加强的断言都在 `verify_encounter_trigger_room_flow` 里（**91 项**，`EXIT=0`）：

- **前置**：进房后入口门必须是"已打开"的 —— 否则后面测不出封门失效（这条是防假绿的关键）。
- **封门**：`room.door_targets` 的**每个方向**都要能取到门扇（本房有就查本房，没有就去对端按目标房查
  同一扇），且两侧**都不许有开着的门扇**。取不到门扇 = 失败，不再被静默当成通过。
- **波间**：`seal` 未解除、房间未判清。
- **肃清后**：解封，且入口门扇能从房内一侧取到（防单向门）。

**对照组（撤掉修复看断言是否真的变红）**：

| 对照 | 结果 |
|---|---|
| 撤掉绑定回落（共享门不绑） | 4 条断言红，含「封门后仍拿不到门扇」「封门只覆盖 1/2 扇门」「解封后仍拿不到入口门扇 ⇒ 玩家从房里走不回去」 |
| 把带子跨度写死 5 m（上一轮的对照，本轮复跑） | 8 条贴边断言 + 走位全红 |

## 6. 连带发现：`boss` 有一扇通向无处的西侧门（**既有缺陷，本轮未改**）

boss 的房间数据里有 **3 个端口**，其中第三个是**空目标**：

```json
{ "port_id": "P3", "target": "", "position_m": [-40.0, -22.5], "outward": [-1.0, 0.0], "door_width_m": 2.2 }
```

`_build_door_for_port()` 照样为它建出门扇 ⇒ `_door_nodes["west"]` 多出一扇
（`door_targets` 里没有 `west`、计划门也没有它）。修复前它"通过"检查纯属巧合：
boss 少了南门、多了西门，**计数正好相等**。绑定补上南门后计数变 3，断言才如实报出来。

⇒ 正确修法是**决定这个端口该去掉还是该补目标**（内容裁定），不是改断言。**未代做**。

## 7. 其它未通过项（本轮之前即红，未代修）

- `verify_expedition_room_static_scenes`：修复后仍 9 项红（修复前 18 项）。
  余项是内容漂移 —— `room_02 / room_03 / room_06 / room_09 / room_10` 的
  「房型件 metadata 必须等于实际实体数」、`room_07` 的未解释差项、`room_10` 的
  `RehomeFill` 额外实例、以及 §6 的 boss 空端口。
- `verify_door_passability` 测试 9「找不到 EVENT 测试房」：该测试加载
  `battle_level01/floor_98`，而该层当前 **16 间房全是 `COMMON_ROOM` / `SAFE_ROOM`，
  没有 `EVENT` 房** ⇒ 断言失去对象。属**过期测试**（关卡内容被改过），非回归。
- `verify_block00_floor98_assembly`：`floor_01_entry 刷怪登记=3 期望 0`（既有）。
- `verify_expedition01_spawn_ramp`：`room_02` 盒数 2 ≠ 倍率口径 5（既有）。
- `verify_expedition_level01_flow`：怪物掉落表 16 vs 13（既有）。
- `verify_tower_extraction_return_flow`：保险格 / 背包棋盘化一族（既有）。

## 8. 一处实现细节的兼容性说明（写进代码注释，防止后来者误判）

绑进来的那扇门，其 `RoomDoor3D.direction` 记的仍是**建门方**的方位标号，与本房登记的键
**不同名**（共享边两端方位镜像）。这不影响功能：

- `direction` 只作诊断用，**全仓没有任何生产代码读它**（已全量 grep 确认）；
- 交互目标走的是本房 `door_targets[登记键]`（`DungeonRoom3D.get_nearest_door`），
  所以对端拿到的**目标房是正确的**；
- 唯一依赖「键 == `door.direction`」的是 `verify_door_passability` 测试 1，已随之改正
  （改为「目标房非空」且「方向同名 **或** 确为绑入的共享门（以绑定时写的
  `shared_edge_key` 元数据为准）」）。

## 9. 验收实跑（本轮）

| 项 | 结果 |
|---|---|
| `verify_encounter_trigger_room_flow` | ✅ `EXIT=0`，`ENCOUNTER_TRIGGER_ROOM_OK samples=91` |
| `verify_door_passability` | 测试 1 由 `6/8` 修复为 **`8/8`**；仅余过期测试 9 |
| `verify_door_function_check` / `verify_room_graph_persistence_services` / `verify_tower_descent_flow` / `verify_expedition_wave_chain` / `verify_dungeon_wave_intermission` / `verify_death_during_extraction_flow` / `verify_encounter_event_flow` / `verify_expedition_extraction_carry_return` | ✅ 均 `EXIT=0` |
| 逐房「计划门数 == 运行时门数」（远征01） | 12/13 房达标（唯 boss 见 §6） |

## 10. 遗留

- boss 空端口 P3 的处置（去掉 / 补目标）需要内容裁定。
- `verify_expedition_room_static_scenes` 的内容漂移项属其它改动流。
- 共享边「本房侧开门」现已随绑定生效；但**跨房门的开合状态是否需要在两侧同步持久化**，
  本轮未涉及，未验证。
