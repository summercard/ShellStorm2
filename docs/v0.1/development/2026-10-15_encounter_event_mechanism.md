# 2026-10-15 运行时遭遇事件（Encounter Event）独立机制

> 契约正文见 [触发器刷怪设计](../design/触发器刷怪设计.md) §10「运行时遭遇事件」。
> 本记录只写本轮**实做了什么、什么通过了、什么没做**，不改写设计口径。

## 1. 起因

撤离信标启动后的防守刷怪原先硬编码在 `Dungeon3D._spawn_extraction_attackers(stage)` 里：
按撤离进度 0% / 18% / 36% / 58% / 78% 五个阈值直接读 `MonsterInjector` 生成配置并调
`_spawn_enemy_batch`。它有三个问题：

1. **不可复用** —— 想在别的房间、设施或剧情事件里刷一波怪，只能再抄一遍阈值逻辑。
2. **不能配** —— 「刷什么、刷多少、持续多久、分不分波、什么条件才算完成」全部写在代码里。
3. **阶段数是硬编码的** —— 想改成 3 阶段或 8 阶段要改函数。

本轮把它抽成一个**独立、可运行时调用**的遭遇事件机制，并把撤离防守迁移成它的第一个使用方。

## 2. 交付物

| 件 | 路径 | 职责 |
|---|---|---|
| 事件 Owner | `src/world3d/EncounterEventDirector3D.gd` | 配置校验、实例 ID、阶段推进、完成/取消/失败、结果动作、快照导出恢复 |
| 场景适配器 | `src/world3d/EncounterEventHost3D.gd` | 查询房间/玩家/行动上下文、解析敌人编成、调统一刷怪入口、统计事件归属存活、清理事件敌人 |
| 正式入口 | `src/world3d/Dungeon3D.gd` | `start_encounter_event` / `cancel_encounter_event` / `get_encounter_event_snapshot` / `advance_encounter_event` |
| 专项验收 | `tests/verification/verify_encounter_event_flow.{gd,tscn}` | 契约 + 正式接缝 |

Director 是 `RefCounted`，**不读 Dungeon 私有成员**；所有场景私有状态访问集中在 Host。
Host 只暴露五个方法：`encounter_event_current_room_id` / `encounter_event_room_busy` /
`encounter_event_context` / `encounter_event_spawn` / `encounter_event_live_count` /
`encounter_event_despawn` / `encounter_event_apply_result`。

## 3. 关键设计决定

### 3.1 完成模式与进度模式分开

- `completion`：`timer`（时间到即完成，不要求清怪）／`clear`（阶段派发完 **且** 事件归属敌人清空；时间到未完 ⇒ `failed`）／`timer_and_clear`（两者都要）。
- `progress_mode`：`tick`（由 `Dungeon3D._process` 自动推进）／`external`（外部调 `advance_external(instance_id, progress)`）。

撤离用 `completion: "timer"` + `progress_mode: "external"`：**读条完成权仍归信标**。
Encounter Event 只管防守刷怪，不认识「撤离成功」，不触发行动结算。

### 3.2 离房策略

`leave_policy` ∈ `pause` / `cancel` / `follow_current_room`。撤离额外给
`follow_current_room: true`，保持原行为：离开信标或撤离房**不会**自动停掉防守事件。

### 3.3 事件归属与精英归属分离

- 事件敌人写 `encounter_event_instance_id`。
- 精英的 `encounter_instance_id` 属于 `EliteRosterService` 的预约号，**不被覆盖**；只有普通怪才把它当兼容值复用。
- `_encounter_owner_id()` 先读事件字段、再退到精英字段 ⇒ 事件完成、房间清房、击杀奖励、逃脱五条链互不串账。

### 3.4 事件完成 ≠ 房间清房

事件敌人照常进 `_enemy_nodes_by_room` / `_alive_by_room`，但事件完成判定只数**自己归属**的敌人。
所以「事件完成」不会顺手把房间判清，房间清房仍由原有 `_resolve_room_enemy_departure` 负责。

### 3.5 结果动作失败不回滚事件

原实现把结果动作失败写成 `status = "failed"`。这会把「事件条件已满足」和「完成后的副作用没应用上」
混成一件事。现改为：事件保持 `completed`，另记 `result_action_failed: true` 与
`result.action_error`。

### 3.6 Boss 明确拒绝

`type: "boss"` 直接 `_reject("boss_requires_dedicated_flow")`。普通怪必须过
`MonsterInjector.is_authorable_enemy_type()`；精英走 `EliteRosterService` 预约。

## 4. 本轮修掉的问题

| 问题 | 症状 | 处理 |
|---|---|---|
| `interval_sec` 声明了但不生效 | 只编译出一个 `at_sec = 0.0` 阶段，间隔没有任何作用 | 真按单位敌人拆阶段：第 n 只 `at_sec = n × interval_sec`；`count`/`total_count` 精确截断 |
| `on_cancelled` 声明了但被拒 | 配置白名单收它，校验里直接 `_reject("on_cancelled_not_supported")` | 补齐校验、规范化与执行路径 |
| 事件存活统计漏算在途怪 | 只扫已实例化 `Enemy3D`，漏掉休眠房间快照、`_reserved_room_spawns`、`_pending_delayed_spawns` ⇒ `max_alive` 与 `clear` 判早 | `encounter_event_live_count()` 三类来源全部计入 |
| 事件取消清理不干净 | 只清已实例化敌人，延迟/预约队列与精英预约留着，`_alive_by_room` 占用不释放 | `encounter_event_despawn()` 清三类队列 + 释放精英预约 + `MonsterAIManager.unregister_enemy` |
| 延迟出怪丢弃后存活账悬空 | `_on_delayed_spawn_timeout` 在房间不在/被封锁时只把条目移出队列，**不减** `_alive_by_room` ⇒ 该房永远回不到 0 | 丢弃时同步减 1（见 §5） |
| `TowerDescent3D` 整份脚本编译失败 | `var encounter_state := world_state.get("encounter_events", {})` 从 Variant 推断，撞「警告即错误」 | 显式 `: Variant`（与 `Dungeon3D` 同写法） |
| 事件敌人 `persistent_id` 在恢复路径上不稳定 | 依赖 `_spawn_enemy_batch` 的 `wave_%d:%d` 兜底，续局可能撞号 | Director 维护 `spawn_serial`（进快照），Host 按 `<instance_id>:<serial>:<index>` 下发 `persistent_id` |

## 5. 延迟出怪存活账（同轮发现的既有缺陷）

`_alive_by_room` 的口径是「已实例化 ＋ 在途预约」：`_queue_delayed_spawn` 在**排队那一刻**就把
每一只记进存活账（`base + spawned_count + queued_delayed`），到点实到时按 `count_reserved = true`
不再加。但 `_on_delayed_spawn_timeout` 在「房间已不在 / 未流送 / 被封锁」时**只把条目移出队列就返回**，
那一只的 +1 永远没人还 —— `_alive_by_room` 回不到 0，`_can_advance_room_wave` 的 `alive == 0`
恒不成立，下一波永不自动来（要靠玩家跑去按门触发 `_repair_hostile_room_progress` 用真实实体重算才自愈）。
本轮在丢弃分支补上 `_alive_by_room - 1` 并刷新 HUD。

## 6. 验收结果

### 6.1 专项（本轮实跑）

```text
命令：godot --headless --path . res://tests/verification/verify_encounter_event_flow.tscn
结果：EXIT=0　ENCOUNTER_EVENT_FLOW_OK samples=31
错误面：SCRIPT ERROR 0 / Parse Error 0 / 资源泄漏 0
```

覆盖：非法前置条件不产生副作用、Boss 拒绝、精确请求数量、`max_alive` 挂起与释放后补发、
大 delta 跨阶段、`pause` 离房与返回、外部进度、快照导入、`clear` 完成、重复完成/重复取消幂等、
`interval_sec` 分段与按间隔派发、`on_cancelled` 结果动作只执行一次、Dungeon 正式 API 与正式批量刷怪路径、
事件取消清理。`samples` 从 23 提到 **31**。

### 6.2 回归

| 场景 | 结果 | 备注 |
|---|---|---|
| `verify_death_during_extraction_flow` | ✅ EXIT=0 | 修复 `TowerDescent3D` 编译错误前为红 |
| `verify_dungeon_wave_intermission` | ✅ EXIT=0 | `DUNGEON_WAVE_INTERMISSION_REGRESSION_OK` |
| `verify_room_graph_persistence_services` | ✅ EXIT=0 | 存档/房间持久化 |
| `verify_expedition_resume_entry` | ✅ EXIT=0 | 续局入口 |
| `verify_pause_game_save_reset_flow` | ✅ EXIT=0 | 暂停/存档/复位 |
| `verify_tower_extraction_return_flow` | ❌ EXIT=1 | 失败点**不属本机制**，见 §7 |
| `verify_expedition_extraction_carry_return` | ❌ EXIT=1 | 同上 |
| `verify_new_save_handoff` | ❌ EXIT=1 | 同上（开场刷枪链） |

已知既有资源警告（非本轮引入，未处理）：大量 `.glb` 报
`In external resource #0, invalid UID ... using text path instead`。

### 6.3 登记门禁

- `verify_encounter_event_flow` 已登记进 `scripts/run_verification_suite.sh` 的 `core_scenes`，
  `check_verification_registry.py` 不再报它未注册。
- `docs/v0.1/feature_registry.json` 新增 `ENCOUNTER-EVENT`（38 项），
  `check_feature_traceability.py` 由红转绿（`issues: []`）。顺带修掉两处让它恒红的格式问题：
  `MODULE_INDEX` 的 `VFX-POOL` 行原为 8 个单元格（多余 `|`），已并入第 6 格；
  `INVENTORY-SLOTS` 补登记 `design/装备与棋盘式包裹设计.md`（MODULE_INDEX 早已链接）。
  新增 FeatureID 后该脚本的期望功能数 37 → 38，并把硬编码的成功输出改为按登记数打印。
- `check_documentation_contracts.py`：失效链接 2 → 1（`14.6` 那条 `../outputs/...` 本就该是
  `../../outputs/...`，目标文件存在，已修）；仍余 `CHANGELOG.md:813` 指向一份**从未存在**的
  `2026-10-08_boss002_spawn_speed.md`，属他人历史条目，**未擅自改写**（正确修法是补写那份记录，不是改链接）。
- 仍余 7 个未注册验收入口（**全部不属于本机制**）：`verify_base99_radio_sound`、
  `verify_base99_swivel_chairs`、`verify_environment_bird_flocks`、`verify_expedition01_spawn_ramp`、
  `verify_expedition_resume_entry`、`verify_grid_inventory_layout`、`verify_pushable_base_chairs`。
  其中 6 个在 `HEAD` 就存在且一直未注册（属既有安排），1 个（`verify_grid_inventory_layout`）是未提交的新件。
  本轮 headless 试跑结果：**5 通过 / 2 失败**（`verify_expedition01_spawn_ramp`、`verify_grid_inventory_layout` 为 1）。
  登记会改变套件成员与耗时，属他流决定，**未代做**。
- 另一条既有门禁红（非本机制）：媒体资产域检查 `ui row count: expected 16, got 18`。
- `git diff --check` 退出 0。

## 7. 未完成与归属说明

以下红项经逐函数比对确认**与遭遇事件无关**，属并行推进的其它改动流，本轮**没有修改**（避免撞正在改的设计）：

- `verify_tower_extraction_return_flow`
  - `door_endpoint_owners` 缺失键报错（`TowerDescent3D._register_edge_topology` 第 5619 行）：
    该函数、`_append_tower_record`、`_append_plan_room_record`、`_reset_initial_loop_world_after_retreat`、
    `_return_successful_extraction_to_facility` 与 `HEAD` **逐字节相同**，属已提交代码在该路径上的既有缺陷。
  - 「无法准备成功撤离装备背包」「清房开门回归房没有可控灯光」「死亡结算没有区分未保险物品」：
    落在背包棋盘化／保险结算那条未提交改动上（`BASE_INVENTORY_CAPACITY` 已由 12 改 24，
    `INVENTORY_CAPACITY_BY_EQUIPMENT` 与 `GridInventoryBoard` 为新增件）。
- `verify_expedition_extraction_carry_return`：同上（背包准备失败，断言自报「后续断言会假绿」）。
- `verify_new_save_handoff`：开场剧本刷枪与拾取幂等（`WORLD-LOOT` / `NARRATIVE-TRIGGER` 链）。

**未做**：`light` 结果动作当前明确返回失败（房间灯光所有权仍在房间/设施系统，Host 无正式接口）——
要么补正式接口，要么把它从允许配置里移除，需要单独裁定；`on_cancelled` 是否长期保留在公开契约、
结果动作失败的持久化重试语义、休眠房间与预约/延迟三类来源同时存在时的去重，均留待后续。

## 8. 文档同步

| 文档 | 改了什么 |
|---|---|
| [触发器刷怪设计](../design/触发器刷怪设计.md) | 新增 §10 运行时遭遇事件契约（配置键、状态、完成模式、离房策略、前置、结果动作、归属、快照） |
| [远征关卡01设计](../design/远征关卡01设计.md) | 撤离防守改为遭遇事件驱动，写明信标仍持读条与结算权 |
| [06 怪物精英与Boss](../06_技术施工_怪物精英与Boss.md) | 普通怪/精英/Boss 与遭遇事件的边界、两个归属字段的分工 |
| [08 剧情触发](../08_技术施工_剧情触发.md) | 遭遇事件三段信号、`flag`/`hint` 结果动作、`light` 不保证成功 |
| [09 存档结算与复活](../09_技术施工_存档结算与复活.md) | 遭遇事件快照字段与恢复语义、三条取消路径 |
| [13 性能优化与热管理](../13_技术施工_性能优化与热管理.md) | 事件房间流送、离房策略、延迟刷怪在途账 |
| [MODULE_INDEX](../MODULE_INDEX.md)、[feature_registry.json](../feature_registry.json) | 新增 `ENCOUNTER-EVENT` 登记行 |
