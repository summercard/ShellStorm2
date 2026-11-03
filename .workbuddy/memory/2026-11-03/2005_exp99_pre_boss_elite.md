# EXPEDITION99 · 2026-11-03 收租人投放到远征99 boss 前置房

## 事务

主人要求把「收租人」投到「远征99 的 boss 前那间房间」。

**先纠正一个层错**：不是 **99F**（基地层、常驻 NPC 绿苔），而是**远征关卡 99**
（`data/level_plans/99`，`level_name_zh = 测试关卡99`，场景 `ExpeditionLevel99_3D.tscn`）。

结构 `start → room_01 → boss → extraction`；`boss.parent_key = "room_01"`
⇒ **boss 前那间 = `room_01`**（25×25，COMMON/COMBAT）。

主人选定：**保留普通战斗，另加精英**（不是改成精英房）。

## 为什么不能用现成机制

三条路都会**替换**本房编成，与本需求相反：

| 路 | 结果 |
|---|---|
| 房型改 `ELITE` | `assign()` 替换整房编成 |
| `spawn_placements` 刷怪盒 | 「只认盒子」，旧编成不参与 |
| `encounter.stages[].monsters` | 触发式遭遇，同样替换 |

⇒ 新增房间级能力字段 `elite_id`，语义是**追加**。

## 真正的障碍：楼层窗口

远征单层，`room.set_meta("floor_number", 100 - floor_index)` ⇒ 房间 `floor_number` 恒为 **100**
（`TowerDescent3D._organize_existing_rooms_by_block`）。
收租人名册窗口是 94/93/92 ⇒ `get_deployable_for_floor(100)` 空 ⇒ **照现状永远不出**。

**没有**把 100 塞进窗口（会污染名册）。改为 `MonsterInjector._generate_elite` 支持**点名**：
请求带 `elite_id` → 走 `EliteRosterService.reserve()`（不查窗口）；
**仍受**「同 ID 全局单例 / 预约唯一性」约束（不走 reserve 就能刷出两只）。

## 跨 5 文件契约（缺一环 = 静默失效、不打日志）

1. 设计源 `art_source/design/whitebox/tower_zones/99/v001/data/floors/floor_00.json`
2. `LevelPlanLoader.normalize_floor`（**白名单重建**）
3. `FloorPlanGenerator.room_from_source` + flow 装配白名单（出口白名单）
4. `Dungeon3D` / `TowerDescent3D` 房间 `configure` → `DungeonRoom3D.elite_id`
5. `Dungeon3D._commit_room_waves`（消费）

⚠ `data/level_plans/99/**` 是源的**逐字节投影**（`sync_runtime_design_data.py`）。
第一版误改投影，被 `--check` 抓到；已纠正为「改源 → 投影」。

## 最重要的教训：位置错了，逻辑对也没用

第一版把追加逻辑放在 `_spawn_room_enemies` 的**普通战斗 `_:` 分支末尾**。
逻辑正确，但**一次都没执行** —— 该函数有**四条早退**：
触发遭遇 / 和平区 / **只认盒子（`_spawn_box_waves` 非空直接 return）** / `spawn_boxes_only`。
`room_01` 走的是**第三条**。

**抓到它的不是契约验收，是场景探针**：
- `verify_expedition99_pre_boss_elite` 全绿（只验到「房间拿到字段」）
- `probe_expedition99_pre_boss_elite` 打出 `total=4 ordinary=4 elites=[]` ⇒ 真相暴露

正解：移到 `_commit_room_waves` —— **唯一提交点**（盒子/授权编成/普通编成三条路都过它），
并加 `_extra_elite_appended` meta 防重（该函数被调两次会出两只）。

> **教训固化**：凡「在某函数的某个分支末尾追加」，先确认该函数有几个 `return`。
> 多个早退分支时，要加在**所有路径的共同汇合点**，不是某一个分支里。

## 门禁读数（实跑）

| 门禁 | 退出码 | 读数 |
|---|---|---|
| `verify_expedition99_pre_boss_elite` | 0 | `EXP99_PRE_BOSS_ELITE_OK` |
| `probe_expedition99_pre_boss_elite` | 0 | `total=4 ordinary=3 elites=["elite_arms_taker/ENM-ELITE-ARMS-TAKER-3D"]` |
| `verify_second_elite_arms_taker`（回归） | 0 | `SECOND_ELITE_ARMS_TAKER_OK`（未点名路径未被改坏） |
| `check_level_decoupling` | 0 | **violations 0**（判据是房型能力，不是关卡 ID） |
| `sync_runtime_design_data --check` | 0 | `issues: []` |
| `check_asset_registry --ledger enemies` | 0 | 通过 |
| `check_verification_registry` | 1 | 4 条 unregistered —— **均为历史欠账**（本轮两个新文件已注册） |

## 与本改动无关的三个既有失败（已核证）

| 门禁 | 失败 | 归属证据 |
|---|---|---|
| `verify_expedition01_spawn_ramp` | room_02 盒数 2≠5、count_multiplier 1≠2 | 门禁文件是 HEAD 版本（未改）；远征01 设计源 `git diff` 为空；**远征01/02/03 数据里没有任何 room 带 `elite_id`** ⇒ 我的 `_commit_room_waves` 分支短路零执行 |
| `verify_expedition_fate_surplus` | room_01 总量 15→14、room_02 12→6 | 同上（同一盒子倍率根因） |
| `verify_test_level_99_flow` | 「城市缺少两座入口楼」「读取界面标题被改变：CloseAI数据库」 | 全息城市/读取界面，属**其他会话**的 UI/场景改动（`src/ui/*`、`TowerAtmosphere3D.gd` 等本会话前已是 M） |

## 文档

- 开发记录 `docs/v0.1/development/2026-11-03_expedition99_pre_boss_elite.md`
- 关卡接入规范 §3.1.1（新字段契约 + 5 处落点 + 「别放在房型分支」的警告）
- 测试关卡99设计表 §1.4 / §1.7.1
- 怪物设计 §第二只精英·投放；06 施工 §5.7.1
- 内容库《精英怪》G 列、敌人账本《资产主表》J 列 + 《3D-敌人》使用位置
- 12_完成度清单 / MODULE_INDEX：1/12 → **2/12**

## 待办

- 若要改回「普通怪也被替换」的形态，只需换成 `encounter` 编成（不要动 `elite_id`）。
- 未做真实渲染验收（本轮 headless）。
