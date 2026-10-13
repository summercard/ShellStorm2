# 远征02 相邻房之间凭空生成通用走廊（墙/地板/挡人碰撞）

日期：2026-10-12。FeatureID：WORLD-EXPEDITION。依据：业主实机反馈——「开阳台→room_01 的门后刷出一堆远征01 的通用墙、排列很糟糕、还有很多空阻挡，不够干净」，并要求参照格式、不要把远征01 的脚本带进远征02。

主设计：[远征关卡02设计](../design/远征关卡02设计.md)。基于现有工作区施工，未提交 Git。

## 症状与实测口径

业主描述的是"开门刷墙"，实际与开门无关：**从关卡加载那一刻起，25 条房间连接件里 23 条就在错误位置铺了东西**，只是开门后走进去才看见。

用探针 `tests/verification/probe_expedition02_assembly.gd` 逐条清点 `_corridor_by_edge`：

| 项 | 修复前 | 修复后 |
|---|---|---|
| 门间距离 > 0.05m 的连接件 | **23 / 25**（最大 75.17m） | **0 / 25** |
| 走廊墙 MultiMesh 实例 | **286** | **0** |
| 走廊地板 MultiMesh 实例 | **143** | **0** |
| `layer=1` 挡人碰撞实体 | **46**（全是空阻挡） | **0** |
| `off the 5m lane` ERROR | 15 条 | **0 条** |

最刺眼的一条：`room_01|start` 门间距离 **25.74m** —— 阳台与前厅本来**共墙**（实测两房矩形贴合 0.00m），距离应当是 0。

## 根因：端口 `side` 被静默丢弃，两门坐标退化成房间中心

链路是两段，缺一不可：

1. `LevelPlanLoader.normalize_floor()` 重建端口字典时只保留 `port_id / target / position_m / outward` —— **`side` 没被登记**。白盒端口本来也不写 `side`（`asset_manifest.json` 只给 `position_m` + `outward`）。
2. `TowerDescent3D._declare_and_register_edge()` 取 `a_port.get("side", "")` 得到空串 ⇒ 走 `else` 的兜底分支 `_direction_between(a_record.position, b_record.position)`，**按两房中心差猜向**。相邻共墙时两房中心连线方向是合法方向，但**门位坐标退化成房间中心**，于是 `start.distance_to(end)` 变成两房中心距 ⇒ 在"错误方向 + 错误长度"上生成走廊。

为什么不能改读 `outward`：白盒门表的 `outward` 只编码「谁排在 `side_a`」，**同一面竖墙上东西两侧的门可能都是 `(+1,0)`**（实测 `d_w1`（→ room_w1）与 `d_e1`（→ room_e1）都是 `outward=(+1,0)`）。拿它判方向会得到与几何相反的 side。

为什么长廊是重灾区：塔楼走廊模型**一面墙只认一扇门**（`RoomDoor3D` 按 `room.doors` 最多 4 个方向各建一个节点，`_room_door_world_position(room, side)` 每面墙只返回那一扇）。远征02 的长廊 `room_02` 一间房有 **11 扇门**（5 西 + 5 东 + 1 南 + 1 北），10 扇侧墙门被塌成 2 扇 ⇒ 门间距离算成 15~60m。

## 修复

两处，都用**判据**而不是 `is_expedition()` 开关，保证 `mode = constrained` 的远征01 逐字不变。

**① `src/map/LevelPlanLoader.gd`** — 在归一化层派生 `side` 与 `lane_m`：

新增 `_side_from_room_boundary(position, room_size)`：按端口压在**房间哪条边界**上判定，先比「离哪条边界更近」再取符号。判据与项目自有定义同源：

- `FloorPlanGenerator._connection_port_is_on_room_boundary()` 的 side 定义逐条一致（north → y≈−half.y，依此类推）；
- 实测 56 个端口两种独立判法（局部边界 vs 世界门线）**56/56 一致**，配对关系 0 冲突。

不能按「绝对分量最大」判：10×75 长廊的侧墙门 `local x=−5, y=−30`，|y|≫|x| 会误判成南北门。派生不出 side 时 `push_warning` 并显式返回空串，不再静默退回猜向。

**② `src/world3d/TowerDescent3D.gd`** — 静态布局已自持墙体时，**不生成走廊几何**：

新增 `_room_walls_owned_by_static_layout(room)`，判据取 `DungeonRoom3D._build_shell()` 静态分支落的房间 meta（`static_layout_scene_loaded` + 非空 `static_layout_scene_path`），**不是** `is_expedition()`。

理由：`mode = authored` 的关卡把相邻两房**逐房共墙**排死（实测 25/25 对父子房贴合 0.00m），门墙也逐扇烘进各自静态布局（长廊一间就有 10 面 `wall_door_5m_h3`），根本不存在"门厅与门厅之间要补一段走廊"。此时连接器只保留拓扑与开门判定，`start/end` 统一退回两房中心连线的中点，让 meta 自洽（长度 0），不再让错误坐标流进 `GameplaySpatialRegistry3D`。

`Dungeon3D.gd` 全局静态开关 `use_expedition_static_layout_scenes` 只服务远征，`static_layout_scene_path` 也只在 `is_expedition()` 分支下发 ⇒ 塔楼全关卡该判据恒 false。

## 本次验证

所有 Godot 进程启动前 `APPDATA` 隔离到工程外；正式用户档未被验收调用。

| 验证 | 退出码与结果 |
|---|---|
| `probe_expedition02_assembly`（新增只读探针） | 0；连接件 25，带几何 **0**，墙/地板实例 **0/0**，`off the 5m lane` ERROR **0** |
| `verify_expedition02_level_plan`（新增「端口 side 可用性」门禁） | 0，`EXPEDITION02_LEVEL_PLAN_VERIFY_OK`；56 个端口 side 全部可用且与几何一致 |
| 同上 · **反向对照**（临时把派生换成 `""`） | **1**，`FAILED count=56`，逐条报 `side 为空` ⇒ 证明该门禁真的会红，不是"本来就没跑到" |
|同上 · 恢复后复跑 | 0，重新转绿 |
| `verify_expedition02_scene` | 0；26 房场景加载、根 meta 完整、实例数与声明一致 |
| `verify_expedition02_ceiling_camera` | 0 |
| `verify_expedition_common_components_v015`（`-s` 入口） | 0，`EXPEDITION_COMMON_V015_VERIFY_OK components=8` |
| `verify_expedition02_assembly_match`（白盒逐件对账） | 0，`EXPEDITION02_ASSEMBLY_MATCH_OK`；26 房 / 1097 实例 / 实墙 211 / 门墙 28 / 地板地砖封顶 864，逐件对上白盒 |
| `probe_stair_lobby_band`（塔楼 98F 回归） | 0；报错 **0**，`STAIR_LOBBY_BAND_DONE` |
| 实际 Forward+ 窗口出图（新增 `probe_expedition02_live_view`） | 0；见下 |
| `check_documentation_contracts` | 1；3 条 issue 均为既有（CHANGELOG 缺链、6 项旧验收未登记、UI 域预期 16/实际 18），**无本次新增** |

实机画面复核（闸门 + 正交顶视，出图时临时关雾；本关 `fog_density=0.04` 会把 90m 高正交机位洗成一片灰）：

- `outputs/expedition02_wall_leak_fix/A_顶视_整关.png`：整关 26 房，**相邻房之间只有一道共墙，没有多余走廊**；
- `B_交界处放大顶视_阳台到room01.png`：阳台↔room_01 交界处只有一道带门洞的共墙；
- `C_阳台内第一人称看门.png`：从阳台内看 room_01 的门，两侧墙、门、出口标牌就位，**无杂墙与空阻挡**。

跑出关卡矩形（x∈[−40,40] z∈[−100,60]）的可见 Mesh 只有玩家自己的 `AimCursor/Ring` 与 `/Dot`（玩家在原点），**无场景件泄漏**。

## 未做与遗留

- 未跑完整游戏套件、手柄硬件、性能压力测试。
- 本次未改 `data/level_plans/expedition_02/**` 任何设计源代码，只修运行时装配；白盒逐件对账保持全绿。

---

# 续：门扇覆盖 —— 21 个门洞只有 11 扇门

日期：2026-10-12（同轮）。业主追加要求：「这次没有随机房间排列种子的需求，不需要关心这个。只要按照规范进行拼接可以开门即可，都是物理门，回头如果需要加开门有命运卡再说。」

## 症状与实测口径

上一轮修完走廊几何后，用 `tests/verification/probe_expedition02_door_coverage.gd` 清点「门洞 vs 门扇」：

| 项 | 修复前 | 修复后 |
|---|---|---|
| 标准门洞（`wall_door_5m*` 实例） | 21 | 21 |
| 实体门扇（`RoomDoor3D`） | **11** | **22**（21 洞 + 1 扇设计内气闸门） |
| 没有门扇的门洞 | **10** | **0** |
| 落在没有洞处的门扇 | **4** | **1**（气闸门，设计要求） |

最刺眼的是长廊 `room_02`：西墙 5 扇客房门、东墙 5 扇，**只有 2 扇有门扇**，其余 8 个是永远开不了的空门洞；而 `room_13` 反倒有一扇门扇悬在离最近门洞 **999m** 外的地方。

## 根因：门扇按「方向」建，而一个方向只能有一个门节点

`DungeonRoom3D._build_runtime_doors_only()` 遍历的是 `room.doors`（**方向**字符串），
`_build_door()` 用 `房间半宽 + 门槽偏移` 推算门位，最后 `_door_nodes[direction] = door`
—— **一个方向只能存一扇**。`room_02` 的 `doors` 只有 4 个方向，11 扇门被塌成 1 扇，
偏移最远 60m。

同一轮还发现两处被静默丢弃的端口字段：`LevelPlanLoader` 重建端口字典时**只保留 4 个字段**，
`door_width_m` / `door_axis` / `door_line_m` / `door_center_m` 全部没登记，
`TowerDescent3D` 的端口读法（`get_connection_port_towards`）也取不到它们。

## 修复

**① `src/map/LevelPlanLoader.gd`** — 端口登记补全 `door_width_m` / `door_axis` / `door_line_m` / `door_center_m`（只透传不解释，但必须登记）。

**② `src/world3d/DungeonRoom3D.gd`** — 门扇改为**端口粒度**：

- 新增 `_has_authoritative_door_ports()`：只有端口**带门位声明**（写了门宽或门轴）才走端口粒度。
  塔楼房间没有 `connection_ports`；`mode = constrained` 的远征01 端口只有拓扑信息
  （位置 + 朝外法线），门位由生成器算 —— **两者都必须保留按方向建门的旧行为**。
  实测踩过：不做这条区分，远征01 会从 13 扇门掉到 1 扇。
- 新增 `_build_door_for_port()`：位置直接取端口的房间局部坐标（= 白盒门洞中心），
  不再用方向推算；`side` 决定朝向与门扇旋转；`door_width_m ≤ 3m` 才建实体扇
  （5m 通洞 / 坍塌是纯开口，白盒里本来就没有墙件 —— 与「门宽 ≤3m 的端口 21 个 =
  静态布局 21 个 `wall_door` 件」逐数吻合）。
- 新增 `_door_nodes_by_port`（`port_id → RoomDoor3D`）与 `get_door_node_by_port()`：
  `_door_nodes[direction]` 一面墙只能存一扇（兼容全部旧调用点），全量存在这里。
- 没有端口的方向仍按方向补建，但**仅限 `target` 为空的门位**——远征入口安全房的
  「封闭气闸门」正是这种（`_build_expedition_records` 特意加的：不挂地图边、
  不参与拓扑、只补安全房造型与"退出战局"交互位）。反过来，有端口的方向一律以端口为准，
  那些端口若是 5m 通洞就说明本来没有门扇，补建才是错的。
- 抽取 `_door_panel_visual(target)`：滑升门 / 塔楼门扇的二选一逻辑与 `_build_door` 共用，
  避免第二份实现分叉。

**③ `src/world3d/TowerDescent3D.gd`** — `_bind_shared_edge_doors()` 改为**按端口配对**：
一墙多门时 `get_door_node(方向)` 会张冠李戴（`room_04` 的门被指向"通向 room_03 的那扇"），
改用 `get_connection_port_towards(peer)` 拿 `port_id` 再 `get_door_node_by_port()`。
配套新增 `_edge_expects_door_leaf()`，把「通洞边本来就没有门扇」与
「门扇该有却没建出来」分开，后者才报错。

## 本次验证

| 验证 | 退出码与结果 |
|---|---|
| `probe_expedition02_door_coverage`（新增只读探针） | 0；门洞 **21** / 门扇 **22** / 缺口 **0**，`ERROR` **0** |
| `verify_expedition02_doors`（新增门禁，`scripts/` 与同批验收同址） | 0，`EXPEDITION02_DOORS_VERIFY_OK`；门洞 21 / 门扇 22 / 无洞门扇 1（上限 1） |
| 同上 · **反向对照**（临时禁用端口粒度） | **1**，`FAILED count=15`，精确复现 21 洞 / 11 扇 / 4 扇悬空 ⇒ 证明断言真的会红 |
| 同上 · 恢复后复跑 | 0，重新转绿 |
| `probe_expedition02_door_coverage` 跑**远征01**（`-- res://scenes/ExpeditionLevel01_3D.tscn`） | 0；13 房门扇 **13**、`ERROR` **0** —— 与改动前逐数一致，constrained 关卡未受影响 |
| `verify_expedition02_assembly_match` | 0，`EXPEDITION02_ASSEMBLY_MATCH_OK`（26 房 / 1097 实例全对） |
| `verify_expedition02_level_plan` / `_scene` / `_ceiling_camera` | 0 / 0 / 0 |
| `probe_stair_lobby_band`（塔楼 98F 回归） | 0；`ERROR` **0** |
| 实际 Forward+ 窗口出图 | 0；`D_长廊西墙5扇客房门.png` / `E_长廊东墙5扇客房门.png` 可见长廊两侧门扇成排就位 |

## 续段遗留

- 「开门触发命运卡」是另一条机制（`RoomDoor3D.triggers_fate` 与 `_door_policies_for_record`），
  本次未改；业主要求「回头如果需要加开门有命运卡再说」。
- 长廊 10 扇客房门现在**各自独立**可开；但 `Dungeon3D` 的「边（edge）」粒度仍是"一对房间一条边"，
  所以同一面墙的多扇门共享该边的开关状态。若业主要求"每扇门单独清房/单独消耗钥匙"，
  那是边模型要扩到门粒度的改动，不在本次范围。
