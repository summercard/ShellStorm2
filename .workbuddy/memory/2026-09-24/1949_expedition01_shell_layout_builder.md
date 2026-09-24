# 2026-09-24 1949 — 通用壳体组合器（区块级 lane 归属）

Task #41。产物：`src/world3d/RoomShellLayoutBuilder3D.gd`（新，`class_name RoomShellLayoutBuilder3D extends RefCounted`）
＋ 探针 `assets/art/environments/tower_zones/expedition/runtime/qa/probe_room_shell_layout_builder.gd`（新）。

## 做了什么

把「5m 通用件按房间尺寸+门位装配」这件事做成**纯计算类**，供两条链共用（生成器产
`authored_layout_instances` / 设计期 dump 写布局源），避免「生成器一套算法、摆位源又抄一遍」。

关键判断：**必须是区块级，不是逐房**。远征 13 间房**全部墙贴墙**（entry↔room_01 共面 x=−10、
room_01↔room_02 共面 y=20、…、boss↔extraction 共面 z=−30，逐对共面），逐房各自出 4 边墙会在
每个共享平面重叠两套（几何+碰撞翻倍）。语义照抄区块00 布局源的 `placement_model`。

## 算法（顺序不能换，换一次静默错一面墙）

1. **共角去重在前**：同一格点的四角 L 件全局只留一件，先声明者拥有，其余记 `corners_dropped`。
2. **L 臂 lane 预留居中**：**只按留下的角件**预留。每角件占 2 个 lane（角点 ±2.5，即紧邻角点那一个）。
   被臂占掉的 lane 谁都不能放墙。邻房的臂也会占掉本房的 lane。
3. **共面 lane 归属在后**：`(常量轴, 常量坐标, lane_key)` 全局只出一件，先声明者拥有；
   任一侧声明门/出口则该 lane 是门洞（覆盖实墙）。

Lane 网格是**全局**的：中心 `5k+2.5`，lane_key = k；房间某轴 lane 范围 = `[min/5, max/5−1]`，
与落位无关 ⇒ 奇偶格宽（15/25/45 与 50/60/70）**共用一条公式**，别特判。

**判例（第 1 条为什么必须在第 2 条之前）**：区块00 办公室 NE 被会议室 NW 顶掉后，办公室北墙
x=−27.5 那道臂位就空出来放了实墙（`WALL_north_yp10_m27.5`）。若先按「全部角件」预留，
会少一面墙且不报错。

## 验收（双段，全绿）

- `godot --headless --path . --script res://assets/art/environments/tower_zones/expedition/runtime/qa/probe_room_shell_layout_builder.gd`
  → **`ROOM_SHELL_LAYOUT_BUILDER_OK pass=1619 fail=0`**
  - 段 A（1180）：用组合器重放**区块00 已验收摆位源**的四房输入，与源自身逐值对照 ——
    90 件实例逐 instance_id、11 角件 + 1 顶掉、27 条 wall_lane、`slot_role_counts`
    （corner_l 11 / solid_wall 23 / door_wall 4 / door_leaf_preview 3 / floor_tile 49）、
    position/rotation/claims/shared_with/grid/axis/line_m/lane_key 全部一致。
  - 段 B（439）：`to_runtime_instances()` 与区块00 **生产路径**
    `Block00MasterOfficeLayout3D.room_shell_instances()` 逐件对照（name/slot_role/corner_id/
    rotation_y_deg/position/component_id）—— 这一层才是真正喂 `authored_layout_instances` 的。
- 回归：`--scene res://tests/verification/verify_block00_floor98_assembly.tscn` → `BLOCK00_ASSEMBLY_OK checks=230`（基线同值）。
- `scripts/check_classname_unique.py` → `CLASSNAME_UNIQUE_CHECK_OK classes=172 duplicates=0`。

## 口径与判例

- **组件 ID 用通用件名** `ENV-SHARED-GENERIC-*`（注册表 `component_id`）；源侧批次号
  `ENV-BATTLE-COMMON-*` / `ENV-TOWER-CORNER-L-5M` 是 registry 里的 alias。探针比对前按注册表
  归一，**双 ID 指向同一 prefab 不算差异**。
- **命名逐字对齐源**：角件 `CORNER_<ROOM_UPPER>_<corner_id>`；墙 `WALL_<side>_<轴字符><符号><线坐标>_<符号><lane中心>`
  （如 `WALL_west_xm40_m2.5`）；门扇 `DOORLEAF_<同上>`；地砖 `FLOOR_<ROOM_UPPER>_R<y索引+1>_C<x索引+1>`
  —— **R = y 索引（行）、C = x 索引（列）**，一开始写反过。
- `exits`（只留洞不挂门扇）对应源里 `role="exit"` 的 wall_lane，实例 slot_role 仍是 `door_wall`，
  且**不产** `door_leaf_preview`（区块00 门厅东出口即此例）。
- `use_corner_l=false` 的房（单 lane 宽，如区块00 走廊 5×20）不出角件，其边上被邻房 L 臂占掉的
  lane 照常不放墙 —— 这正是「全局预留」而非「逐房跳过」的判别点。
- 脚本语义参考：`DungeonRoom3D._build_authored_layout_shell()`（消费端）、
  `Block00MasterOfficeLayout3D.room_shell_instances()`（生产端转换）。

## 坑

- GDScript `"%s %d" % [a]` 少参不报错也不崩，但字符串格式化失败 ⇒ 打印出**未替换的原始格式串**，
  且 `_expect` 条件仍按真值计 —— 一度把「真实缺行」的信息吞成 `%s 无缺失行…`。
  格式化参数个数必须对齐。
- 探针对照键里的 `lane_key`：JSON 解析出的是浮点、组合器给的是整数，`str()` 结果不同 ⇒ 键集合
  全不匹配（27 条全报「缺失」）。键一律走整数/归一化格式。
- `godot --headless --path .` 必须 `cd` 到仓库根（`I:/工作项目/shellstrom2/ShellStorm2`），
  父目录跑会空转挂住；隔离 `APPDATA='I:\ss2_tmp\appdata_shellbuilder'`。

## 未完 / 下一步

- **#40** Boss 房静态布局清单（6 件专属件 `source_world_origin_m` 换算 + 5 类壳体件）。
- **#42** 设计源加房型模板约束 + `LevelPlanLoader` / `FloorPlanGenerator` 两道 `authored_layout_*`
  透传；生成器产 instances 时调本组合器。13 房**门位**来源（从邻接推 side+offset）尚未落。
- **#43** 账本 + 设计页 §3.1.1 + 全门禁。
- 未决：`_spawn_authored_layout_wall()` 里门墙走硬编码 `SAFE_ROOM_WALL_DOOR_PREFAB`
  （= `wall_door_5m_root_top3d.tscn`，与注册表 `ENV-SHARED-GENERIC-WALL-DOOR-5M` 同路径），
  即门墙没走注册表；功能等价，是否改为查表待裁。
