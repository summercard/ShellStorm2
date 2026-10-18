# 传送支线第三阶段：子图按「门与门对接」返工

日期：2026-10-18
关联：[支线秘密房间设计](../design/支线秘密房间设计.md) §3.5 / §3.5.1 / §3.6 · [05 §5.5](../05_技术施工_关卡生成与爬楼.md) · [05.2 §3.5.1 / §3.6](../05.2_关卡版图白盒与生成规范.md)

## 起因

上一轮把「子图走不通」当成新缺口，补了**串联门**（`Area3D` 传送）与**末端返回门**，并把「白盒房间四面封闭，只能靠传送」写进了设计文档。业主指出：**子图不是通过门与门的对接产生的吗？要先看关卡设计文档里的制作方法。**

查证结果：确实是做错了。

| 文档 | 原文要求 | 上一轮实现 |
|---|---|---|
| 05.2 §3.5.1 显式连接端口 | 拼装条件 `world(parent_port) == world(child_port)`、两端 `outward` 点积 ≤ -0.999；**共墙唯一所有权**：一端生成门墙/门扇/碰撞/`RoomDoor3D`，另一端只登记引用；未连接端口保持实体封墙 | 房间是自建盒子，**没有门洞、没有端口、没有门实体** |
| 05.2 §3.6 第 7 条 | 支线房**不引入新模板**，从锁定集合取；`role = "branch"` 只是标注 | 用了自建的 25×25 / 30×25 / 25×30 尺寸，与 L3 模板无关 |
| 设计 §3.5 | 房型池复用 `content_template_pool`：`corridor_45x40` / `office_60x70` / `bridge_60x50` | 三种尺寸都不是模板尺寸 |
| 设计 §3.5.1（上一轮自写） | 「四面封闭的盒子，所以只能靠传送」 | 把实现细节写成了设计，等于给错误背书 |

A16 当时断言的是「串联传送门数量 = 房数 − 1，且目标等于下一间房中心」—— 它证明的是传送门摆对了，**恰好证明了走不通这件事被验收成了通过**。

## 改成什么

子图房间改为**真 `DungeonRoom3D`**，走与主路同一条壳体路径：

- 尺寸读 L3 `size_m`（`LevelPlanLoader.load_room_templates`），代码里不再有第二份数字；取不到才用同值兜底。
- 房间按 `doors` / `door_targets` 开洞并建 `RoomDoor3D`，相邻两间的门**互相指向对方**。
- 相邻两间用**主路同一条** `Dungeon3D._build_corridor` 连接（注入 `Callable`，不复制几何实现）。
- 删掉 `_build_chain_gates` 与 `_build_box_room` / `_add_box`；撤离房也改成真房型（`extraction_25x25`，无门，靠隐藏门进）。
- 桥房只排链中间，并用**转置姿态**（占位尺寸交换为 60×30）表达，不新建模板 id。

## 三个必须同时成立的口径（少一个门就在、但走不过去）

### ① 门位 lane：40 m 墙**没有 0 m 槽**

模板东西墙长度：`corridor_45x40` = 40、`office_60x70` = 40、`bridge_60x50`（转置）= 30。按 05.2 §3.5.2 公式，40 m 墙候选是 `±2.5 … ±12.5`，**不含 0**；30 m 墙是 `±2.5 / ±7.5`。最近槽恒为 `-2.5`。

程序化白盒原来只在**墙面中心**开洞（`_build_wall` 恒对称切两段）。所以：

- `_build_wall` 加 `opening_lane_m`，按 lane 切成**不等长**两段；lane 贴角时一侧长度 ≤ 0 直接跳过（避免退化碰撞）。
- 门洞与门扇必须读**同一个** `wall_door_lane_<side>`：门洞在 `-2.5`、门扇在 `0` 就是「洞在一边、门扇在另一边」。
- lane 用 `RoomDoorLane.nearest_offset()` —— 项目里已有的唯一实现，不写第二份公式。

默认 `opening_lane_m = 0`，与既有全部程序化房间逐字等价，主路/塔楼/基地不受影响。

### ② 走廊中心线必须跟着门位走

门在 `-2.5`、走廊沿房间中心连（z=0）时，走廊宽 3.8（±1.9），门在 -2.5 已经出了走廊侧墙 —— 出门就撞墙。`_build_corridor` 加 `lateral_offset_m`，沿切向整体平移；子图按前一间房的 lane 传。

### ③ 走廊必须常驻启用

`_build_corridor` 建出来的走廊默认 `visible=false`、碰撞禁用，由 `_update_corridor_streaming` 在玩家进入两端房间时打开。子图房间**不进** `_open_edges` / `_spawned_rooms`，这条判据永远返回 false ⇒ 走廊永远不可见、无碰撞，玩家一脚踩空掉出关卡。

因此 `_build_corridor` 加 `persistent` 参数：不登记 `_corridor_by_edge`、建出来即可见、碰撞启用。`TowerDescent3D` 的重写里 `persistent` 直接走基类实现 —— 塔楼那份绑了核心筒与边类型，用在主图外的子图上不成立。

## 验收

| 项 | 结果 |
|---|---|
| `verify_secret_branch_flow` | 通过（16 条断言） |
| A16 新增判据 | 无串联传送门；每间是真 `DungeonRoom3D`；相邻门互指；门扇落在 lane 上；相邻有走廊、可见、中心线与门位重合 |
| 反向对照 ① | 不接走廊 → `第 0→1 间没有走廊` × 3 条精确报红 |
| 反向对照 ② | 房间不开门 → 门互指断言 × 6 条精确报红 |
| `verify_expedition_level01_flow` | `EXPEDITION_LEVEL01_FLOW_OK`（13 房/Boss/撤离/塔楼未改动） |

## 没做的

- 撤离信标与结算、子图刷怪与掉落加成仍 `[UNIMPLEMENTED]`。
- 走廊几何仍是通用矩形走廊（不含子图专属美术）；子图房是程序化壳体，没有静态美术布局。
- 本轮的清理检查：套件退出时临时工作区未被删掉（内含 16 个指回主工程的 junction），清理脚本按护栏拒绝删除。已在会话中记录，未强删 —— 强删有穿透 junction 破坏主工程的风险。

## 追加：撤离信标接上（同日）

业主指出「撤离信标在撤离房里本来就有」。查证结果：

- **信标不在任何房间 tscn 里。** 全工程 `prp_extraction_beacon_root_top3d.tscn` 只在 `Dungeon3D.gd` 被引用一次；13 个房间 tscn 的非墙体节点只有 `RoomCeilingLight` / `RoomLightSwitch3D` / `ConnectionPorts`。它由 `_create_extraction()` → `_create_extraction_beacon()` 在运行时挂成房间子节点。
- 也就是说：**机制本来就有，我漏的是「把子图撤离房接上这条机制」** —— 上一轮把它列进「未实现」，那是把「没接线」写成了「没有系统」。

做法：`SecretBranch3D` 接收 `Dungeon3D` 注入的信标工厂，在 `secret_extraction_<pair>` 房里创建 `STANDARD` + 非锁定的 `ExtractionBeacon3D`。不新建撤离系统、不新建结算分支 —— `extraction_completed → _finish_run(true)` 原样生效（设计 §6.3）。

一个必须处理的差异：`_on_extraction_started` 按 `_current_room_id` 取房来建防线遭遇，而子图房不在 `_room_by_id` 里 ⇒ 遭遇会落到玩家**已经离开**的主图房间（人在子图读条、主图房里刷怪）。所以子图信标打 `secret_branch` 标记，该处只跳过遭遇，其余照旧。

验收：新增 A17（信标 1 个 / `STANDARD` / 非锁定 / 在组内），反向对照「`if false and ...` 不放信标」→ `A17 pair 0/1 撤离房信标 0 个` 精确报红，还原复绿。`verify_secret_branch_flow` 现 17 条断言。

## 追加：子图房间借主路房间的正式美术（同日）

业主指示「直接拿已有房间的去拼」。子图房原来是**程序化灰盒** —— 能走、门也对、走廊也通，但房间里什么都没有，只有真进游戏才看得出来。这类缺陷任何结构断言都抓不到，因为结构确实是对的。

做法：四个**共享房壳**放在 `room_instances/expedition_01/`，各 instance 一份主路房间的正式 tscn：

| 模板 | 壳 | 借自 |
|---|---|---|
| `corridor_45x40`（45×40） | `f00_secret_shared_corridor_45x40_static_layout.tscn` | `f00_room_01` |
| `office_60x70`（30×40） | `f00_secret_shared_office_60x70_static_layout.tscn` | `f00_room_03` |
| `bridge_60x50`（烘焙 30×60） | `f00_secret_shared_bridge_60x50_static_layout.tscn` | `f00_room_05` |
| `extraction_25x25`（25×25） | `f00_secret_shared_extraction_25x25_static_layout.tscn` | `f00_extraction` |

为什么必须是「壳」而不是直接指过去：`DungeonRoom3D._build_shell` 会比对布局根的 `metadata/room_id` 与房间自己的 id，不一致直接 `push_error`；而子图房 id 是 `secret_<pair>_<i>`，每局抽到的模板还不同。壳根**刻意不写 `room_id`**（空值时该比对跳过），路径由 `SecretBranch3D._shared_layout_path()` 按模板显式下发 —— 不靠「同名猜测」。

摆在哪儿、门开在哪儿全交给运行时现成逻辑：`_align_static_layout_to_room()` 转朝向、`_rehome_static_layout_door()` 搬门墙、`_seal_stray_door_walls()` 封废门洞。桥房借的是烘焙 30×60 的美术，而子图链沿 X 串联、门要落在东西短墙 ⇒ 运行时整体转 90° 变成 60×30，与 05.2 §3.6 第 8 条一致。

验收：新增 A18（每间房 `static_layout_scene_loaded` 必须为真）。反向对照「`_shared_layout_path` 直接 return ""」→ 7 间房全部报 `退回程序化灰盒：<无路径>`，还原复绿。
