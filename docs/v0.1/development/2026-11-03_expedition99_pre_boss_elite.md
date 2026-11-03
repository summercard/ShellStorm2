# 收租人投放到远征99 boss 前置房（2026-11-03）

## 一句话

把「夺械者“收租人”」投到**远征关卡 99**（测试关卡）boss 前那间 `room_01`，
**保留该房原有普通战斗**，额外追加这一只。

## 「远征99」不是 99F

先把名字对齐，避免后面对错层：

| 说法 | 实际指向 |
|---|---|
| 99F | 基地层（`assets/art/.../base_facility`），常驻 NPC「绿苔」所在，**不是**这个 |
| **远征关卡 99** | `data/level_plans/99`，`level_name_zh = 测试关卡99`，场景 `scenes/ExpeditionLevel99_3D.tscn` |

结构（`floors/floor_00.json`）：`start`(SAFE) → **`room_01`(COMMON/COMBAT)** → `boss` → `extraction`。
`main_path = ["room_01"]`，`boss` 的 `parent_key = "room_01"`
⇒ **「boss 前那间」= `room_01`**（25×25）。

## 为什么不能靠现成机制

三条看起来能用的路，实际都不满足「保留普通战斗 + 另加精英」：

| 路 | 为什么不行 |
|---|---|
| 把 `room_01` 改成 `ELITE` 房 | `_spawn_room_enemies` 的 `ELITE` 分支是 `assign()` **替换**整房编成 ⇒ 普通战斗没了 |
| `spawn_placements`（刷怪盒） | 房间声明了就「**只认盒子**」，旧编成整体不参与 |
| `encounter.stages[].monsters` | 这是**触发式遭遇**，同样会替换本房编成 |

所以新增了一个房间级能力字段 `elite_id`，语义是**追加**。

## 真正的障碍：楼层窗口

「收租人」的名册窗口是 94/93/92F（`EliteContentCatalog`），每局按 `run_seed` 三选一。
而远征关卡是单层：`TowerDescent3D._organize_existing_rooms_by_block()` 统一写
`room.set_meta("floor_number", 100 - floor_index)`，`floor_index = 0`
⇒ 远征房间的 `floor_number` 恒为 **100**。

`_generate_elite` 原本只走 `EliteRosterService.select_and_reserve(seed, floor_number, ...)`，
`get_deployable_for_floor(100)` 与 [94,93,92] 无交集 ⇒ **照现状永远出不来**。

**没有**把 100 塞进窗口（那会污染名册，让所有远征关卡都凭空可能出精英）。
改成在生成请求里支持**点名**：

```gdscript
# MonsterInjector._generate_elite
if requested_elite_id.is_empty():
    elite_snapshot = EliteRosterService.select_and_reserve(seed, floor_number, encounter_id)  # 原路径
else:
    if not EliteRosterService.reserve(requested_elite_id, encounter_id, floor_number):
        return {}                                                                             # 点名路径
    elite_snapshot = EliteRosterService.get_record(requested_elite_id)
```

点名路径**仍然走 `reserve()`** —— 不走就会绕过「同 ID 全局单例 / 预约唯一性」，
同一局里同一只精英能被刷出两只。

## 五个文件的跨文件契约（本项目点名的坑）

这条改动跨了 5 处，缺任何一环的表现都是「设计源写了，运行时房间里没有这只怪」，
**且不打任何日志**。工程里同类坑已踩过三次（`spawn_placements` / `reward_plan` / `chest_placements`）。

| # | 文件 | 作用 | 漏了会怎样 |
|---|---|---|---|
| 1 | `art_source/design/whitebox/tower_zones/99/v001/data/floors/floor_00.json` | 设计源声明 `elite_id` | 一切无从谈起 |
| 2 | `src/map/LevelPlanLoader.gd` `normalize_floor` | **白名单重建**，登记 `elite_id` | 字段被静默丢弃 |
| 3 | `src/map/FloorPlanGenerator.gd` `room_from_source` | 出口白名单，登记 `elite_id` | 同上（另一条构造路径） |
| 4 | `src/world3d/Dungeon3D.gd` + `TowerDescent3D.gd` `configure` | 透传到 `DungeonRoom3D` | 房间读不到，`elite_id` 恒为空串 |
| 5 | `src/world3d/Dungeon3D.gd` `_commit_room_waves` | 消费：追加到第一波 | 见下节 |

> `data/level_plans/99/**` 是 `art_source/.../v001/data/**` 的**逐字节投影**
> （`scripts/sync_runtime_design_data.py`）。改投影不改源 ⇒ `--check` 会报 drift。
> 本轮先误改投影，已纠正为「改源 → 投影」。

## 一个实测抓到的执行位置错误

第一版把追加逻辑放在 `_spawn_room_enemies` 的**房型分支之后**（普通战斗 `_:` 分支末尾）。
逻辑上没错，但**永远不会执行** —— 那个函数有**四条早退**：

1. `_room_has_encounter_trigger` → 触发式遭遇
2. `authored_layout_peaceful` → 和平区
3. `_spawn_box_waves` 非空 → **「只认盒子」**
4. `spawn_boxes_only` → 没盒子不刷

`room_01` 走的是**第 3 条**（盒子路径直接 `return _commit_room_waves(room, box_waves)`），
所以追加代码一次都没跑到。

**抓到这个的是场景探针，不是契约验收**：`verify_expedition99_pre_boss_elite` 全绿
（它只验到「房间拿到字段」），而 `probe_expedition99_pre_boss_elite` 打印出
`total=4 ordinary=4 elites=[]` —— 普通怪 4 只、精英 0 只。

正解：移到 `_commit_room_waves` —— 它是**唯一提交点**（盒子 / 授权编成 / 普通编成
三条路都过它），并对同一房加 `_extra_elite_appended` 防重
（`_commit_room_waves` 若被调用两次会出两只）。

## 改了哪些

### 数据（设计源，再由脚本投影）

`art_source/design/whitebox/tower_zones/99/v001/data/floors/floor_00.json`

```json
{ "key": "room_01", ..., "content_type": "COMBAT", "elite_id": "elite_arms_taker" }
```

### 代码

| 文件 | 改动 |
|---|---|
| `src/map/MonsterInjector.gd` | `_generate_elite` 支持 `request.elite_id` 点名（走 `reserve`，绕过楼层窗口） |
| `src/map/LevelPlanLoader.gd` | `normalize_floor` 白名单登记 `elite_id` |
| `src/map/FloorPlanGenerator.gd` | `room_from_source` 出口白名单 + flow 装配白名单登记 `elite_id` |
| `src/world3d/DungeonRoom3D.gd` | 新增 `var elite_id`，`configure` 读取 |
| `src/world3d/Dungeon3D.gd` | `configure` 透传；`_commit_room_waves` 追加（带防重 + 失败告警） |
| `src/world3d/TowerDescent3D.gd` | `_append_plan_room_record` 落字段；`_instantiate_dynamic_room` 透传 |

### 只对普通战斗房生效

`_commit_room_waves` 里的判据：

```gdscript
if not room.elite_id.is_empty()
    and room.room_type not in ["ELITE", "BASEMENT", "BOSS"]
    and not room.has_meta("_extra_elite_appended"):
```

`ELITE` / `BASEMENT` 房上面已经出过精英，`BOSS` 房自带精英随从 —— 这三类再追加会出两只。
**判据是房型（能力），不是关卡 ID**，所以 `check_level_decoupling` 仍然是 `violations 0`。

## 验收

| 入口 | 结论 |
|---|---|
| `verify_expedition99_pre_boss_elite` | `EXP99_PRE_BOSS_ELITE_OK`（数据/白名单/装配/点名生成/窗口未污染/普通战斗未改） |
| `probe_expedition99_pre_boss_elite` | `EXP99_ELITE_PROBE_OK`：`total=4 ordinary=3 elites=["elite_arms_taker/ENM-ELITE-ARMS-TAKER-3D"]` |
| `check_level_decoupling` | `violations 0` |
| `sync_runtime_design_data --check` | `issues: []` |

### 两个验收的分工（这轮证明了它必要）

- `verify_*`：**契约断言** —— 数据里声明了、白名单没吞、房间拿到了、点名能生成、
  不点名时 100 层出不来（反证窗口没被放宽）、94/93/92 窗口没漂移、`room_type` / `content_type` 原样。
- `probe_*`：**真实场景跑一遍** —— 加载 `ExpeditionLevel99_3D.tscn`，
  调 `_spawn_room_enemies(room_01)`，数节点确认「普通 3 只 + 精英 1 只」。

**只有后者能发现「逻辑写对了但被早退跳过」**。本轮就是靠它抓到。

## 顺带

演练中还确认了一条既有事实：远征房间的 `room_type` 在运行时是 **`COMBAT`**
（不是 `COMMON_ROOM`）—— `content_type` 会被映射成运行时的房型名。
探针打印 `room_id=room_01 room_type=COMBAT` 即此。不影响本改动（`COMBAT` 正是想追加的那类）。

## 未做

- 没有改 `room_01` 的普通编成（仍是全局公式随机出怪）。
- 没有为「99 关卡专属」写任何 `if level_id == "99"` 分支。
- 未做真实渲染验收（本轮 headless）。
