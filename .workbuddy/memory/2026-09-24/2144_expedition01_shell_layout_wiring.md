# 远征01 壳体装配接线（Task #42-A 前半）

时间：2026-09-24 21:44｜分支 `0.1.2`

## 本轮完成（两步，各自提交）

1. **注册表纳入 6 件 Boss 专属件** — 提交 `0b6a77e5`
   - `shared/runtime/shell_component_catalog.json`：`component_count` 6→12；新增 6 条
     `kind:"exclusive"` 条目（`aliases:[]`，不设 alias —— 只属一个房间种类、只有一条来源链）；
     `resolution_contract` 加 `kind`（generic/exclusive，缺省 generic）与 `alias_policy`；
     加 `exclusive_single_source`（expedition 侧 component_catalog）与 `consumers`
     （`FloorPlanGenerator.gd::_load_boss_layout_instances()`）。
   - `qa/probe_shell_component_catalog.gd`：加 G 段 `_expect_exclusive_ids()`（逐件比对
     `resource_path` / `kind=="exclusive"` / `aliases` 为空 / 根节点 `asset_id`）+
     `EXPECTED_COMPONENT_TOTAL := 12` 替换硬编码 6。
   - 验证：`SHELL_COMPONENT_CATALOG_OK pass=148 fail=0`。
   - ⚠ 探针里 `Shared 源目录 packages.size()==6` **保持不变**是刻意的：6 件专属件在
     expedition 侧源目录，不进 shared 源目录。

2. **两道白名单透传** — 提交 `ed5999ce`
   - `LevelPlanLoader.normalize_floor`（源头闸）＋ `FloorPlanGenerator.room_from_source`（出口闸）
     各补 6 个字段：`authored_layout_shell` / `_asset_id` / `_version` / `_room_id` /
     `_peaceful` / `_instances`（Array 走 `duplicate(true)` 深拷贝）。
   - 下游**本来就通**，无需改：`TowerDescent3D._append_plan_room_record` L1881 读 `spec`
     透传、`Dungeon3D` L1584/1592 与 `TowerDescent3D` L4614-4619 两处 `configure` 已支持。
   - 验证：`LEVEL_PLAN_VALIDATE_OK levels=3 checks=234 rooms=33 templates=17`、
     `LEVEL_PLAN_RUNTIME_GUARD_OK levels=3 rooms=33 checks=3`；区块00 `BLOCK00_ASSEMBLY_OK checks=230`。

## 🔴 本轮钉死的新认知（下一步必须遵守）

**constrained 模式下，设计源里写的 `authored_layout_*` 到不了运行时。**
`generate_from_level_plan` 在 `mode=="constrained"` 时把 `floor_source` **整份换成**
`_generate_constrained_floor()` 的现算结果 —— `floor_00.json` 的房表只当**兜底样例**。
⇒ `room_from_source` 读到的是**生成结果**的房间字典，里面没有 `authored_layout_*`。
⇒ 第 4 环（生成器产 instances）的**正确落点**是 `_generate_constrained_floor` 之后、
`room_from_source` 之前，对 `floor_source["rooms"]` 逐房补写，**不能改 floor_00.json**。

**门位必须与运行时同源。** 运行时门槽由 `TowerDescent3D._plan_room_layout()` 从房间
**世界位置**现算（走 `RoomDoorLane`，L2563-2566 写 `tower_wall_door_offset_<side>`），
不是从设计源读。组合器若自己算门位，两套算法必然静默分叉 ⇒ 组合器的 `doors` 输入
必须取自同一份几何（`RoomDoorLane.port_pair` 的 `a_lane/b_lane`，本次已确认是全项目唯一实现）。

**`to_runtime_instances()` 的 `y=0` 常量只对落地件成立**（墙 / L 角 / 地砖）。
Boss 房 6 件专属件含**悬空件**（主屏底 z=3.805、墙面标识底 z=7.4461）⇒ 专属件路径
必须走 `Godot_local = (bx − cbx, bz, −(by − cby))`，**不可复用** `to_runtime_instances()`。

**设计源 planar → Blender 世界**：`bx = center_m.x`、**`by = −center_m.y`**（因为
`_plan_world_position` = `Vector3(planar.x, …, planar.y)` ⇒ 设计源 +y = 世界 +z = 南 = Blender −Y）。
此镜像下**东西墙的门槽偏移符号翻转**，南北墙不翻。

## 剩余（#42-A 后半 + #42-B）

- 第 4 环：生成器调 `RoomShellLayoutBuilder3D.build_block()` 产 13 房 instances，
  统一置 `authored_layout_shell=true`；输入投影按上面两条（`by=−center_m.y`、门槽符号）。
- 第 5 环：`DungeonRoom3D._build_authored_layout_shell` 加 `exclusive_component` 分支
  （Boss 房 6 件专属件追加进同一 instances 数组，保留 bz）。
- #42-B：通道桥「只短边开门」的**放置层约束**（`template_rotation_deg` 路线已判定不可行）。
- #43：6 件登记资产账本 + 设计页 §3.1.1 同步 + 全套门禁。

## 阻塞

`git push` 仍被凭据阻塞（本地领先 7 个提交）。待业主提供 GitHub 凭据或改 SSH 远端。
