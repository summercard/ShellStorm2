# 2357 远征13房消费第5环：Boss 专属件装配 + 侧墙判据修假红 + 远征豁免 Boss 层信标

提交 `229a6ce7`（本地 ahead 11，push 仍被凭据阻塞）。承接 `b2b89e21`（第 4 环）。

## 第 5 环：Boss 房 6 件专属件真正装配

- `FloorPlanGenerator`：新增 `BOSS_LAYOUT_SOURCE_PATH` 常量 + `_load_boss_layout_instances()` + `_boss_room_exclusive_instances(room, boss_layout)`；
  `attach_authored_layout_shell` 里按需读盘（仅当有 `role=="boss"` 时），逐房投影末尾把专属件 `append` 进 `filtered`。
- `DungeonRoom3D`：新增 `exclusive_component` 分支 + `_spawn_authored_layout_exclusive()`（**y 不归一**，`position` 直接用摆位源算出的 Vector3）+ `set_meta("authored_layout_exclusive_count")`。
- 坐标契约：`Godot 房间局部 = (bx − cbx, bz, −(by − cby))` —— **y 取 bz（底面离走行面高度）**，不是 0。与区块00 的 y=0 常量不同。
- 取证（`probe_expedition_authored_runtime`）：6/6 落地，`EXCL_MAIN_FAULT_SCREEN y=3.805`、`EXCL_NORTH_WALL_TYPOGRAPHY y=7.4461` 悬空高度保住，Boss 房 `E=6`，节点 27049，ERROR=0。

## 修 `verify_expedition_level01_flow` 侧墙判据的 8 条假红

- 症状：改成「逐 5m lane 中心打射线 + 最多 1 条 lane 打空」后反而 **9 条假红**，全是「整边 N 条 lane 全部打空」（room_03/06.west/east、room_04.north/south、boss.west/east）。
- **根因：`span` 一个量被当成两个用。** 原写 `span = 东西墙 ? dimensions.y : dimensions.x`，既当「沿墙跨度」（定 lane 数）又当「法向距离」（定 reach）。方房两者相等；50×40 / 60×70 这类非方房一混用，`reach = 短边半宽 + 3` 就**够不到该侧墙** —— boss 东西墙 reach=23 但实距 25 ⇒ 整边打空。
- 修法：拆成
  - `length_span`（沿墙跨度：东西墙 → `dimensions.y`，南北墙 → `dimensions.x`）→ 定 lane 数；
  - `depth_span`（法向跨度：东西墙 → `dimensions.x`，南北墙 → `dimensions.y`）→ `reach = depth_span * 0.5 + 3.0`。
- 修后 `EXPEDITION_LEVEL01_FLOW_OK`（8 条假红 + 下面那条基线红全清）。
- 教训：**任何「从房间中心往四向打射线」的判据，都要把「沿墙方向跨度」与「法向距离」显式分成两个变量**；方房上等价，非方房上必错。

## 修「远征关卡未装配可用撤离信标」（本轮新引入的真 bug）

- `TowerDescent3D._commit_floor_bundle` L4485 先跑 `if plan.boss_floor and _extraction == null:` 给 Boss 房挂 BOSS_KILL；L4492 的远征分支 `if is_expedition() and _extraction == null:` 因此**永远为假** ⇒ STANDARD 信标从不生成。
- 为什么以前没踩：内置回退 `generate_expedition()` 是**旧 7 房、无 boss 房** ⇒ `boss_floor=false`；13 房数据驱动版设计源含 `key=boss role=boss` ⇒ `boss_floor=true`（`FloorPlanGenerator` 只要任一房 `role=="boss"` 就置 true）。
- 修法：该分支加 `not is_expedition()`（远征的 boss 房是「路上的一战」，不是塔楼 boss 层）；类头硬约束注释同步补「远征豁免」。
- 等价性：非远征路径 `not is_expedition()` 恒真 ⇒ 新旧条件逐位等价 ⇒ 塔楼零影响。

## 回归

| 套件 | 结果 |
| --- | --- |
| `verify_expedition_level01_flow` | `EXPEDITION_LEVEL01_FLOW_OK` ✅ |
| `verify_block00_floor98_assembly` | `checks=230` ✅（与改前一致） |
| `verify_tower_descent_flow` | rc=0 ✅ |
| `verify_tower_extraction_return_flow` | `TOWER_EXTRACTION_RETURN_OK` ✅ |
| `verify_3d_parity_core` | **既有基线红**（非本轮，需另开任务） |

### `verify_3d_parity_core` 判为既有基线红的证据

报 `Opened adjacent room was not streamed in` + `Streamed parity slice exceeds node budget: 2559/2200`。
该场景 `IronFrontier3D.tscn` 的根 = `scenes/Dungeon3D.tscn` → `Dungeon3D.gd`（**纯 Dungeon3D，不含** `TowerDescent3D._commit_floor_bundle`）；且 `Dungeon3D.gd` / `verify_3d_parity_core.gd` 最近提交均为 `afb69b7a`（非本轮）⇒ 不可达本轮改动。
**未修**。基线红名单原先未收录它，应补进 `godot-verification-suite-triage` 的基线清单。

## 待办

- 副线（业主裁决本轮做）：4 个非矩形轮廓写进 `room_templates/*.json`（挂「模板+变体」）＋ 通道桥多层几何（上层平台先做／下层标准墙下延围合／坑深 12 m／坑底铺普通地砖／下层不可达纯装饰）；`db_70x50.json` 的 note「外轮廓与门槽表一致」口径需修（`2156` 已证形状确为不规则）。
- `git push` 仍被凭据阻塞（ahead 11），未获凭据前不得动远端。
- 探针：`probe_expedition_authored_runtime.*` 保留（承载第 5 环断言）；一次性定点探针 `probe_expedition_room03_west.*` 已删。
- 本轮测试跑动污染了 `Godot/app_userdata/弹壳风暴2/base_save.json`（未暂存），提交时须排除。
