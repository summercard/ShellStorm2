# 远征01：07 / 08 号房房间布局修正（空路封闭 + 中间直穿）

日期：2026-11-17；记录 ID：`2026-11-17_room07_08_layout_fix`；功能 ID：`WORLD-EXP01`；工程版本：`0.1.0`。
设计依据：[远征关卡01设计 §room_07 / §room_08](../design/远征关卡01设计.md)；规范：[05.2 关卡版图白盒与生成规范](../05.2_关卡版图白盒与生成规范.md)。
本轮**只改房间布局**（地砖、外墙、内部门洞），不改房型源、GLB、Prefab、AssetID、刷怪数据、波次、门策略与存档格式。

## 业主反馈与实测定位

业主 2026-11-17 报两处，并给出截图（`CloseAI数据库 · 06号房` 与场景工坊里的 room_08 静态布局）：

1. **07 号房有「空路」，走过去还有隐藏房间入口**（`Clipboard_Screenshot.png` / `-1.png`）。
2. **08 号房有两个通路，反而中间过不来、被阻挡挡住**（`Clipboard_Screenshot-2.png`）；「地砖我都加了，你帮我把阻挡处理干净就好了」「这个房间我的目的是从中间走」。

先把「真身是哪个 tscn」查清：运行时按 `TowerDescent3D.expedition_static_layout_path()` 派生路径，
07 / 08 的正式场景是
`assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_07_static_layout.tscn`
与 `…/f00_room_08_static_layout.tscn`。`room_instances/f00_room_07/room_static_layout.tscn`
是旧路径的残留副本，**不在运行时链路上**，本轮未动。

### 诊断方法（不是看图猜）

工坊截图看不出「哪里能站人」（护墙环、陈设会把包围盒画成大黑块），于是用真实物理查询建可走网格：

- `probe_walk2.gd`：进真实远征01（`test_mode=false`），在目标房间包围盒内按 0.25m 铺格，
  每格放 0.30m 半径球体做 `intersect_shape`，`collision_mask=1`（玩家层），输出可走位图。
- `accept.py`：在该位图上做连通域、门槽落点、8 邻域 BFS 路径（斜向要两个正交邻格都可走，
  不许穿墙角）与「房内可走格 → 房外可走格」的漏出扫描。
- `probe_colliders.gd` / `probe_doors.gd`：dump 真实碰撞体与门节点，用于把黑块追到具体实例名。

### 07 号房实测缺陷

| 缺陷 | 实测 |
|---|---|
| 南墙（烘焙 z=+12.5，接 `room_06`）整面没有墙 | 25m 边长里只有 x=0 处 2.2m 门洞，其余 22.8m 全空 → 漏出段 `[-155.00..-130.00]` |
| 北墙（烘焙 z=−12.5）缺一段 | x=+5 那一段 5m 无墙 → 漏出段宽 4.6m |
| 视觉后果 | 玩家从 room_06 进来，右手一整面敞开；北侧又有个 5m 缺口，正是业主说的「空路」与「过去还有隐藏房间入口」（缺口正对 S3 暗门所在的西墙开阔区） |

### 08 号房实测缺陷

| 缺陷 | 实测 |
|---|---|
| 地砖只铺 L 型两条臂 | 烘焙帧 42 格（应 8×9=72），中部 x∈[−22.5, 7.5]、z∈[−5, 20] 无地面 |
| 内角斜墙横在房间中部 | `WALL_X_10/15/20_FRONT` 与 `WALL_Y_10/15/20_35` 共 5 段斜墙，把 L 的内角切成阶梯，玩家只能绕东北拐角 |
| 北侧两个无目标端口留成空洞 | 端口 C(−15,−20)、D(15,−20) 的 `target` 为空，但墙上留着缺口 → 漏出 `[-155..−135.8]` 宽 18.8m |
| **房内两扇多余的门**（真正的「中间过不来」） | `WALL_Y_30_45/PassagePortal` 与 `WALL_X_35_REAR/PassagePortal` 是 2026-11-16 加进去的「房内固定门洞」。删除父墙后它们成了**孤儿节点**（`parent` 指向已不存在的节点），Godot 把位置归零 ⇒ 两扇门扇正好落在房间中心 `(±1.1..±2.5, −0.15..0.15)`，各带一个 1.4×0.3 的 `WallDoorCollision`，把中部横向切断 |

第 4 条是这一轮最关键的一条：业主看到的「中间被阻挡」，物理上就是这两扇掉到房间正中的门。
它不是画错、不是碰撞代理错，而是**删父节点时把子节点留下了**。

## 改动

只动两个 TSCN，全部是结构件（地砖 / 实墙 / 门墙）。陈设、灯光、开关、暗门锚点、端口锚点、贩卖机锚点一个未动。

### 07 号房（`f00_room_07_static_layout.tscn`）

| 项 | 改前 | 改后 |
|---|---|---|
| 地砖 | 25 | 25（未动） |
| 实墙 | 9 | **14**（南墙补 4 段 x=−10/−5/+5/+10，北墙补 1 段 x=+5） |
| 门墙 | 1 | **2**（南墙 x=0 补 1 幢，与北墙既有那幢成对） |
| L 角件 | 2 | 2（未动） |
| prefab 实例合计 | 37 | **46** |
| SHA-256 | `9facb41f…a792a5d2` | `9e32cf6d…3df92cc0` |

补的 6 段沿用了本文件既有命名风格与 `metadata/tower_wall_direction`，南墙用单位基（装饰面朝 −Z、房间内部侧），
北墙沿用既有那段的 180° 基，与同侧其余墙段逐项一致；地砖、灯、开关、`SecretDoor_S3`、`ConnectionPorts` 未动。

### 08 号房（`f00_room_08_static_layout.tscn`）

| 项 | 改前 | 改后 |
|---|---|---|
| 地砖 | 42（L 型）+ 9（2026-11-15 手工补的中庭砖，y=+0.08 叠层） | **72**（8×9 满铺，统一 y=−0.056/−0.081 棋盘） |
| 实墙 | 30（L 型轮廓 + 5 段内角斜墙） | **32**（矩形四面：x=±19.8945/20.1055 面各 9 段、z=±22.387 面各 8 段） |
| 门墙 | 3（含两扇房内 PassagePortal） | **2**（只留两条真实主路门） |
| L 角件 | 2 | 0（矩形房间不需要） |
| 房内固定门洞（PassagePortal） | 2 | **0**（父墙删除时一并删除，不再留孤儿） |
| prefab 实例合计 | 121（房型默认布局口径） | **153** |
| SHA-256 | `c8083148…ca033a05a` | `b58c47bc…7a9efc`（第二轮挪贩卖机＋行尾归一 LF 后） |

保留的两条真实门位（烘焙帧 → 运行时）：

- 烘焙 `x=20.1055` 面、`z=−15` → 运行时 `south`，接 `room_07`
- 烘焙 `z=22.387` 面、`x=−12.5` → 运行时 `west`，接 `room_09`

烘焙 `x=19.8945` 面（运行时 `north`）整面封成 9 段实墙，端口 C / D 两个空通路到此为止；
烘焙 `z=−22.387` 面（运行时 `east`）8 段实墙。

**为什么删那 9 块中庭砖**：它们是 2026-11-15 把 L 型凹口填成可走地面的一次性补丁（`slot_role="floor_tile"`、
y=+0.08）。房间现在整面满铺标准地砖，这 9 块变成比周围高 13.6cm 的凸台，正落在玩家「从中间走」的必经路线上。
删掉后地面是一整片平的。

### 08 号房贩卖机挪位（同日第二轮，业主指令「要有阻挡、靠墙、边上能走到」）

| 项 | 改前 | 改后 |
|---|---|---|
| 锚点（烘焙帧） | `(2.75, 0, −2.5)` | `(0, 0, −21.1)` |
| 房间帧位置 / 朝向 | `(2.50, 2.75)`、yaw −180°（房心） | `(21.10, 0)`、yaw 90°，正面朝 −X（房内） |
| 实体碰撞盒（房间帧） | 1.55 × 4.34 × 3.60 m，立在主通道 | 同尺寸，贴东墙：x[20.33, 21.87]、z[−2.17, 2.17] |
| 背面到东墙内表面 | — | **0.26 m**（墙内表面 x ≈ 22.14） |
| 阻挡 | `blocks_player=true`（但未验证物理注册） | `space_valid=true`、`shape_count=1`、内部点 3/3 命中 |

只改了锚点的 `transform` 一行，`metadata/service_station_config` 与视觉声明未动。
门位、地砖、墙、刷怪、存档均未改。

验证（`process_mode` 已恢复继承、房间真激活）：

- 正面 0.6 / 1.2 / 2.0 / 3.0 m × z = −1.8…+1.8 共 5 条线**全部可站立**
- 门 A（西门内侧 −20.9, −12.5）与门 B（南门内侧 15.0, 18.4）→ 机器正面点 (18.93, 0) **BFS 均可达**
- 全房可走 **1653 / 1800 m²（91.8%）**、连通域 **1**、四面零漏出、中心到四门 1.08/1.05/1.05/1.04 不变
- 贩卖机占地 9×5 = 45 个采样点 **45/45 不可走**；房中心与正面 1.5 m 处仍可走

## 验证

环境：`APPDATA` / `LOCALAPPDATA` 在进程启动前隔离到 `_scratch/room_fix_1117/` 下的独立子目录；
真实远征场景 `res://scenes/ExpeditionLevel01_3D.tscn`；真实物理（`test_mode=false`）。

| 命令 / 场景 | 结果 | 关键数值 |
|---|---|---|
| `probe_walk2.gd` + `accept.py`（`SS2_ROOMS=room_07,room_08`） | **exit 0，`ROOM_LAYOUT_ACCEPT_OK`** | 见下表 |
| `tests/verification/run_expedition01_combat_geometry.py`（种子 77001199） | **exit 0，`EXP01_GEOMETRY_DONE failures=0`** | 五房最大编译数量逐项相符（room_08=25）；门洞净空/门垛/支撑 5 点 ×2 门全通过 |
| `verify_expedition01_room08_preplaced_positions.gd`（隔离 APPDATA + `EXP01_REPORT`） | **exit 0，`samples=224 success=224 failed=0`** | 真实胶囊图取合法点、正式编译与整房预选；`real_commit count=25 blocked=false` |
| `check_level_decoupling.py` | exit 0 | `violations=0` |
| `check_asset_runtime_naming.py` | exit 0 | `ASSET_RUNTIME_NAMING_OK`，无新增欠账 |
| `check_documentation_contracts.py` | exit 1（**既有 15 条断链**，与本次无关） | 逐条核对：无一条指向本事务新增文件 |

### 房间级实测（改前 → 改后）

| 指标 | room_07 改前 | room_07 改后 | room_08 改前 | room_08 改后 |
|---|---|---|---|---|
| 房内可走面积 / 理论 | — | 583 / 625 m²（93.3%） | — | 1653 / 1800 m²（91.8%，含贩卖机实体） |
| 房内可走连通域 | — | **1** | **2**（两臂互不相通） | **1** |
| 漏出到房外 | 南 22.8m + 北 4.6m | **无** | 北 18.8m / 东 13.5m / 西 9.5m / 南 24.5m | **无** |
| 房中心 → 各门 路径/直线 | — | 1.02 / 1.02 | — | **1.08 / 1.05 / 1.05 / 1.04** |

08 房「中心 → 四门」的绕行比全部落在 1.04–1.08（几乎直线），即**从中部直穿**；
改前中部被两扇掉落门扇切断，A（西）与 B（南）分属两个连通域，只能绕东北拐角。

> 绕行比口径：8 邻域 BFS，斜向步长按 1.414 计、且要求两个正交邻格都可走（不许穿墙角）。
> 用 4 邻域会得出 ≈1.4 的假绕行（曼哈顿度量），不能用来判断「是否绕路」。

### 测试契约同步（必改，否则专项必红）

`verify_expedition01_combat_geometry.gd::_verify_portals()` 与
`verify_expedition01_room08_preplaced_positions.gd` 原先直接引用
`ENV-EXPEDITION-L-CORRIDOR-WALL_Y_30_45/PassagePortal` 与 `…/WALL_X_35_REAR/PassagePortal`。
这两个节点随 L 型斜墙删除后，两条测试分别在 `get_node` 处 `SCRIPT ERROR: Cannot call method 'get_node' on a null value`。

按「不删断言、只换被测对象」的原则改：

1. `_verify_portals()` 改为遍历房内**真实主路门墙**（`DOORWALL*` + `wall_door` 来源），断言数量 == 2；
   逐门校验 `wall_visual_height_m=11.9`、`door_clear_width_m=2.2`、`door_clear_height_m=2.5`、
   自持碰撞体 `WallDoorCollision` 存在、长轴正交；再沿门洞 5 点（0 / ±0.7 / ±1.8）判
   「`|along|<1.0` 墙线处无碰撞、`=1.8` 处必须被门垛挡住、门洞正下方有物理地面」。
2. 量门洞净空时**临时排除 `Door_*` 门扇 RID**：主路门墙配的是真实可开关门扇（`RoomDoor3D`），
   门关着时门洞必然被挡，那是门的功能、不是几何缺陷。改前那条断言测的是**房内固定门洞**（无门扇），
   换成主路门墙后必须把门扇排除，否则口径不一致。
3. `verify_expedition01_room08_preplaced_positions.gd` 的 PassagePortal 锚点改为「存在才纳入」，
   不再把已删除的节点当成必验锚点。

这两处改的是**被测对象与取样口径**，「门洞可通行 / 门垛阻挡 / 地面连续」这条核心断言的判据数值逐字未变。

## 遗留与未宣称

- **`authored_layout_instances` 与 TSCN 地砖仍未统一**：运行时足迹清单来自生成器（房型布局源），
  TSCN 现在是 72 格，两者数量不同。这不影响本轮的墙 / 门 / 可走性，但「刷怪点池按 TSCN 地砖算」这条口径债
  **没有修**——它需要改 13 房通用的足迹来源，不在「只动房间布局」范围内。
  本轮 `courtyard_floor_debt` 报 0 条，是因为该查询只统计 `slot_role="floor_tile"` 的节点、而这些节点已删除，
  **不等于足迹口径债消失**。
- **局内贩卖机已挪位并确认带实体阻挡（同日第二轮，业主指令）**：`ServiceStation_Merchant_00`
  锚点从烘焙帧 `(2.75, 0, −2.5)` 改到 `(0, 0, −21.1)` = **房间帧 (21.10, 0)、yaw 90°**，
  贴运行时东墙中段、正面朝房间内（−X）。**同时更正一条错误认知**：首版记录与设计文档写
  「它是 `Area3D`、不参与玩家层阻挡」，实测是错的 —— `ServiceStation3D._build_facility_visual()`
  会把视觉 prefab 里的 `StaticBody3D`（`collision_layer = 1`）连同 `CollisionShape3D` 拆出来挂进房间，
  所以它确实挡人。房间流送激活后 `PhysicsServer3D.body_get_space(rid)` 有效、`shape_count = 1`、
  机器内部点（房间帧 21.10 / y = 0.5、1.0、1.5）三点全部命中阻挡。
  ⚠️ **测量口径提醒**：`TowerDescent3D` 会把未流送房间设成 `PROCESS_MODE_DISABLED`，
  此时房间内（含墙、含贩卖机）的碰撞体都不在物理空间里（`space_valid=false`）。
  只 `ensure_detail_built()` 不激活 `process_mode` 的探针会得出「全房无阻挡」的假结论。
  本轮所有可走性数字都在 `process_mode = PROCESS_MODE_INHERIT` 之后采集。
- 真实渲染截图、手动游玩、Android 均未执行 ⇒ 不宣称视觉验收；不把 `WORLD-EXP01` 标为完结。
- 整关流程验收（`verify_expedition_level01_flow`）的既有红项未在本轮复核。

## 回退

```
.workbuddy/backup/20261117_room_layout_fix/
  f00_room_07_static_layout.tscn.bak                 # 9facb41f…a792a5d2
  f00_room_08_static_layout.tscn.bak                 # c8083148…ca033a05a
  verify_expedition01_combat_geometry.gd.bak
  verify_expedition01_room08_preplaced_positions.gd.bak

.workbuddy/backup/20261117_vending_block/           # 第二轮（贩卖机挪位）
  f00_room_08_static_layout.tscn.bak                 # b9a2da35…ebc607d0（挪位前）
  ShellStorm2_场景账本_v001.xlsx.bak_before_vending
  global_script_class_cache.cfg.bak
```

## 附带修复：`_scratch/Dungeon3D.fixed.gd` 影子类导致的全项目解析失败

`_scratch/Dungeon3D.fixed.gd`（704 KB、未入 git、2026-11-17 15:42 的临时副本）也写了
`class_name Dungeon3D`，与 `src/world3d/Dungeon3D.gd` 撞名，`.godot/global_script_class_cache.cfg`
里同时登记了两条 `Dungeon3D`。表现是所有 Godot 运行启动即报
`SCRIPT ERROR: Parse Error: Class "Dungeon3D" hides a global script class.`
——第一轮记录的「room08 站位容量专项启动停滞、跑不完」就是它引起的（探针本身没问题）。

处理：文件改名为 `_scratch/Dungeon3D.fixed.gd.bak`（不改内容、不删除），再
`godot --headless --editor --quit` 重建类缓存；核对缓存里 `Dungeon3D` 只剩
`res://src/world3d/Dungeon3D.gd` 一条。
