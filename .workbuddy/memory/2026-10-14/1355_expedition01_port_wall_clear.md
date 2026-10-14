# 13:55 远征01 第二处门堵：本局门槽上的实墙无人清理（room_09 → room_10）

## 业主报障
「09 到 10 房子的门开起来又被堵住了」—— 正是 12:35 那份诊断里留下的**唯一一扇**
（当时判定为「旧版就有，另一条独立老问题」）。

## 根因（实测定位，非读码推断）
`room_10` 的门位与它烘焙的静态布局**对不上**，且缺一步清理：

- `room_10` 本局 `dims=30×40`、`rot=270`、`doors=["east","north"]`、
  `door_endpoint_owners={"east": false, "north": true}`、`door_targets={"east":"room_09","north":"boss"}`。
- 烘焙静态布局（`f00_room_10_static_layout.tscn`）是 **40×30**：北侧 6 段**全实墙**
  （`GenericShell_WALL_north_yp160_m42_5` … `_m67_5`，x=−12.5…12.5）；
  东侧有一道**门墙**（`GenericShell_DOORWALL_east_xm35_p147_5`，z=−2.5）。
- 经 `_align_static_layout_to_room()` 的 `rot=270` 整体对齐后：
  - 烘焙北侧 6 段 → 落到**东侧** lane −12.5…12.5；
  - 其中 `x=12.5` 那段（`..._m42_5`）→ room_10 局部 `(15.00, 12.50)`，
    **正好压在本局「东门 → room_09」的门槽（lane 12.5）上**；
  - 烘焙那道门墙 → 落到南侧 lane 2.5（本局南侧**无门**），被
    `_rehome_static_layout_door()` 搬去北侧 lane 2.5（→boss，room_10 自有的那扇）✓。
- 「东门」这条边由 `room_09` 持有门（room_10 的 `owners["east"]=false`）⇒ room_10 侧
  **不生成门墙件**顶替；而 `_seal_stray_door_walls()` 只处理**门墙件**、且 `east ∈ doors`
  天然跳过 ⇒ **那段落在外侧门槽上的实墙没有任何机制移开** ⇒ 门被永久焊死。

一句话：**静态布局路径缺了清单路径那条「委派侧不生成墙」**（清单路径见
`_build_authored_layout_shell()` 里的 `if not ... owns_door_endpoint(...): continue`）。

## 修复（已实施并实测通过，**未提交**）
`src/world3d/DungeonRoom3D.gd`：
1. 新增 `_clear_connection_port_walls(static_layout)`，在 `_align_static_layout_to_room()`
   里紧跟 `_seal_stray_door_walls()` 调用 —— 把「落面 ∈ 本局 `doors` 且沿墙偏移命中该侧
   **真实门槽车道**」的**实墙**删掉（门墙件不在此列，那是门本身）。清理清单写进
   meta `authored_layout_port_walls_cleared` 便于取证。
2. 新增 `_live_door_lane(side)`：从 `connection_ports` 的 `lane_m` 取真实门槽。
   **不读 `tower_wall_door_offset_<side>`** —— 那 meta 有两个写入方
   （`TowerDescent3D._plan_room_layout()` 写端口 lane；基类 `Dungeon3D._plan_room_layout()`
   写「离 0 最近的 5m 段」启发式），直读端口不依赖写入顺序、口径唯一。

判据只在门位上动手：非门位的墙一段不碰（含 `_seal_stray_door_walls()` 与
`_backfill_rehomed_door_spot()` 的补墙）。

## 验收
- `probe_exp01_door_block`，14 个种子（含业主截图种子 286648852、当前存档种子 3198984856）：
  **每局 12 扇门全部畅通，被挡 0**（修复前分别是 7/6/5/3 与 5/5/6/6/5/5/6/3/5/6）。
- **改动范围安全核查**（`probe_exp01_room10_door` 读 meta `authored_layout_port_walls_cleared`）：
  - 种子 3198984856：只清 `GenericShell_WALL_north_yp160_m42_5 @east 12.5`
  - 种子 286648852：只清同一件 `@east 12.5`
  - 种子 20260919：只清同一件 `@west −12.5`（该局版图镜像 ⇒ 落面镜像）
  - **其余 12 房一件未动**。每个种子只删 1 段墙。
- `verify_expedition_level01_flow` → **`EXPEDITION_LEVEL01_FLOW_OK`**
  （轮廓感知判据「每侧最多 1 条 lane 打空」未被破坏 —— 被清掉的正是该侧那 1 条门洞 lane）。
- `probe_exp01_room10_to_boss` → **`ROOM10_TO_BOSS_OK checks=4 failures=0`**。
- 改动为**纯新增 92 行、0 删除**（`git diff --numstat`），未触碰任何既有代码行。

## 新增探针
`scripts/probe_exp01_room10_door.gd/.tscn`：逐件列出目标房在门位附近的所有美术子件
（名字 / 组件来源 / 烘焙局部位置 / 对齐后房间局部位置 / 落面 / 是否压门），
并打印 `doors` / `door_targets` / `door_endpoint_owners`。定位「谁压门」用它最快。

## 教训（补前一份）
- **预烘焙静态布局 + 运行时装门位**这条链路，凡「本局门位」与「烘焙墙位」不一致处，
  都必须有一条显式的对齐动作：门 → 搬、实墙 → 清、非门位门墙 → 封。三步缺一不可。
  本次缺的是第二步。
- 判据要用**权威口径**（连接端口的 `lane_m`），不要用同名启发式 meta —— 后者有多个写入方，
  谁最后执行决定结果，是典型的「静默不一致」温床。
