# 远征关卡01 制作记录（2026-09-19）

## 1. 背景与决策

用户要求抛弃原有的“独立副本”（`RogueMap01TowerSegment3D.tscn` / `standalone_rogue` 分支），**从零生成一个完全不同的新关卡**：入口安全屋 + 5 个随机排列的内容房（编号 01–05，各 25×25）+ 最后一个房间之后接一个撤离房间，作为新区块「远征关卡01」。

已锁定的四项决策：

| 决策点 | 结论 |
|---|---|
| 区块标识 | 新增 `Blocks/Expedition`，`block_id = expedition`，显示名「远征关卡01」 |
| 旧关卡处置 | **完全替换**：删除旧场景与独立分支代码，不做并存 |
| 房间尺寸 | 按 **25×25** 做；房型表在规范中为远征关卡**单列**，不动塔楼 30×25 起的房表 |
| 美术口径 | 先**白盒 + 复用 5m 通用组件**，跑通玩法与验收，不新造美术 |

验收标准（用户原话）：从远征情报室进入后，进入一个**读取界面**的画面，然后进入一个新的关卡，关卡满足基础游戏玩法，包含原有的**刷怪**、过门时候的**命运卡牌选择**、**撤离**、**搜索**等内容。

## 2. 交付物

### 新增

| 文件 | 作用 |
|---|---|
| `scenes/ExpeditionLevel01_3D.tscn` | 远征关卡场景，**继承公共关卡基座 `Dungeon3D.tscn`（不继承塔楼场景 `TowerDescent3D.tscn`）**，覆写脚本为 `TowerDescent3D.gd` 并设定 `expedition_mode = true`、`expedition_run_id = "expedition_01"`、`return_scene_path = "res://scenes/TowerDescent3D.tscn"`（退出落点，2026-09-19 修正见 §10）；区块树自带且仅带 `Blocks/Expedition` 节点（`block_id = expedition`、显示名「远征关卡01」、设定名「远征前哨站」、`production_stage = whitebox`）。到达路径真源见 `GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D` |
| `scenes/ExpeditionLoadingScreen.gd` / `.tscn` | 读取界面。`LEVEL_SCENE` 指向关卡场景，`TOTAL_DURATION_S = 1.35`，含面包屑「远征情报室 → 远征关卡01」、步骤文案、进度条；`_should_skip_delay()` 在无头/编辑器为真 |
| `tests/verification/verify_expedition_level01_flow.gd` / `.tscn` | 专项验收，已注册进 `core` |
| 本文件 | 制作记录 |

### 修改

| 文件 | 改动 |
|---|---|
| `src/map/FloorPlanGenerator.gd` | 新增远征常量与 `generate_expedition()` / `validate_expedition()` / `_expedition_rooms()` / `_shuffle_expedition_types()` |
| `src/world3d/TowerDescent3D.gd` | `standalone` → `expedition` 全量改名；新增 `Blocks/Expedition` 建立、区块路由、入口门策略豁免、撤离信标 `STANDARD` 分支、HUD/到达标题分支；`_runtime_scope_for_save()` 增加 `is_expedition()` 短路；`_instantiate_dynamic_room` 的 `block_id` 改取 `_block_id_for_floor()`；退出提示节点改名 `ExpeditionExitWarning` |
| `scenes/RogueMapSelectMenu.gd` | 标题改「远征情报室 · 远征关卡01」，5 行关卡预览，按钮文案改「传送进入远征关卡」，`change_scene_to_file` 先到读取界面 |
| `scripts/run_verification_suite.sh` | `core` 集合中 `verify_rogue_map_segment_flow` → `verify_expedition_level01_flow` |

### 删除

- `scenes/RogueMap01TowerSegment3D.tscn`
- `tests/verification/verify_rogue_map_segment_flow.gd/.uid/.tscn`
- `tests/verification/verify_rogue_retreat_return_to_base.gd/.uid/.tscn`
- `tests/verification/probe_rogue_resume_exit_flow.gd/.uid/.tscn`

后两者的职责已并入 `verify_expedition_level01_flow` 的 `_verify_expedition_exit_contract` 组。

## 3. 关卡版图

```
start(15×15) ── room_01(25×25) ── room_02 ── room_03 ── room_04 ── room_05 ── extraction(25×25)
```

- 网格：原点 2.5m，格步 `EXPEDITION_GRID_STEP_M = 35.0`（25m 房 + 10m 门间通道）。
- 坐标：`origin = 2.5`、`near = 37.5`、`mid = -32.5`、`far = -67.5`、`tail = -102.5`。
- 排列随机：4 种旋转（0–3 步）+ 可选 Z 镜像，随机源 `run_seed ^ 0x45585031`。
- 房型池：`["COMBAT", "COMBAT", "SCAVENGE", "STORAGE", "EVENT"]`，对 5 个内容房洗牌。
- `validate_expedition()` 断言：尺寸只能是 `SAFE_ROOM_SIZE(15×15)`（入口）或 `EXPEDITION_ROOM_SIZE(25×25)`；无重叠、在界内、父边存在；主路房恰好 5 个；撤离房间存在且父边指向 `room_05`。

**为什么不复用塔楼 `validate()`**：塔楼通用校验硬性拒绝内容房 `maxf < 30 || minf < 25`，25×25 会被直接拒。因此远征走独立分支，两套房表并存互不干扰。

## 4. 踩到的两个坑

### 4.1 可搜索容器读不到

`DungeonRoom3D` 的房内家具（含可搜索容器）是**懒构建**的，挂在 `RuntimeDetail`（`_detail_root`）下，需先调 `ensure_detail_built()`。验收脚本一开始在构建前就 `find_children` 数 `RoomFurniture3D`，得到 0 个，误报「可搜索房 room_01 没有可搜索容器」。修正为构建后再统计，并断言容器已接上 `searched` 信号。

### 4.2 入口快照被判成非战斗范围

`_runtime_scope_for_save(floor_index, room_id)` 的塔楼逻辑是「`floor_index <= 1` 且房 ∈ {start, facility} → `base`」。远征关卡入口安全房 `floor_index = 0`、`room_id = "start"`，正好命中，于是进图产生的首个快照被标记成 `base` 作用域；`_is_combat_runtime_snapshot()` 会排除 `scope == "base"`，导致该快照**不可续局**，同时主塔也不会把 `expedition_01` 的快照路由回远征场景。

修正：在函数开头加 `if is_expedition(): return "combat"`。远征关卡没有 `facility` 房，也不需要 `base` 作用域。

## 5. 验收

`verify_expedition_level01_flow` 断言组：

1. 目录动作 + 菜单冒烟 + 关键常量
2. 读取界面结构（不进场树，只校验 UI 与目标路径）
3. 关卡：单层、无 `facility` / `floor_01_entry` / 电梯、区块、房间集合、版图、v007 安全房、门策略、撤离、刷怪+搜索、门口命运
4. `Block/Expedition` 区块元数据
5. 门策略：`expedition_entry_gate_edges` 为 free（无清房/钥匙/命运），常规门为默认策略
6. 撤离：`STANDARD` 非锁定信标、不刷怪
7. 刷怪 + 搜索：内容房有敌人计划、可搜索容器已接 `searched`
8. 门口命运：清 room_01、给钥匙、开 room_02 → `_door_fate_active` + 3 选项 + HUD/DoorFateOverlay3D
9. 默认塔楼不变（4 区块、`expedition_01` 快照路由、空 map id 不路由）
10. 弃局契约：`configured_expedition_retreat` → `ExpeditionExitWarning` → 清空物品 → 回基地
11. 96 seed 扫描：全部合法、房间列表与房型池稳定、至少 4 种排列

判据：`EXPEDITION_LEVEL01_FLOW_OK`。

回归（无新增红项）：`verify_tower_level_blocks`、`verify_floor_plan_generator`、`verify_central_expedition_hologram_facility`、`verify_door_passability`、`verify_arrival_gate_floor_bundle_flow`、`verify_tower_descent_flow`、`verify_game_entry_flow`、`verify_tower_extraction_return_flow`、`verify_room_graph_persistence_services`、`verify_full_3d_game_flow`、`verify_unified_player_interaction_flow`、`verify_tower_journey_polish`、`verify_base_rooftop_transit_door_motion`、`verify_hud_presenter_3d`。

## 6. 关卡包围修复（2026-09-19 追加）

### 症状
从远征情报室进入远征关卡01 后表现为「房间没有阻挡」：入口安全房与 03 号房之后的房间踩空，
玩家直接掉出关卡。

### 根因
远征是**单层**关卡，唯一层的 `floor_index == 0`；而 `TowerFloorStage3D` 把
`floor_index == 0` 当作「100F 天台」的判据。远征因此静默继承了（此处指**参数口径**沿用，与 §7.1 的**场景继承**是两回事）三套天台窄轮廓参数：

| 参数 | 天台（被错误继承） | 标准层（应有） |
| --- | --- | --- |
| `_floor_world_rect()` | `Rect2(-50, -35, 90, 80)` | `Rect2(-125, -125, 250, 250)` |
| `_floor_grid_dimensions()` | `18 × 16` | `50 × 50` |
| `_outer_world_rect()` / 外圈墙高 | 同窄矩形 / `0.75m` 女儿墙 | 同 250×250 / `12m` 整墙 |
| `_hole_rects()` | 额外挖掉 `BASE_99_100_ATRIUM_WORLD_RECT` | 不挖 |

后果正好切在房间坐标上：`start`(2.5, 2.5) 落在中庭贯通洞里，`room_03/04/05` 与
`extraction`（x ≥ 55、z ≤ −45）落在窄矩形之外 —— 这 6 个房间**既没有 `FloorSupport`
承重楼面，也没有外圈墙**。
入口安全房 v007 的 9 块地砖碰撞被 `_disable_static_collision_descendants()` 主动置
`collision_layer = 0`（原契约是「楼板承重归 `TowerFloorStage3D`」），洞里没有任何替代楼面，
所以玩家一进安全房就开始下落。

### 修复
`TowerFloorStage3D.configure()` 增加第 5 个可选参数 `use_standard_map`，落到新字段
`force_standard_map`；原本用 `floor_index == 0` 判断天台的分支统一改走
`_uses_rooftop_profile() = floor_index == 0 and not force_standard_map`
（覆盖 `_floor_grid_dimensions` / `_floor_map_dimensions` / `_floor_world_rect` /
`_outer_grid_dimensions` / `_outer_map_dimensions` / `_outer_world_rect` /
`_outer_wall_height` / `_outer_visual_transform` 的 0.5 纵向缩放 / `_hole_rects` / 快照字段）。
`TowerDescent3D._rebuild_floor_stage()` 以 `is_expedition()` 传入该参数。

默认值为 `false`，塔楼（含真正的 100F 天台）行为保持不变。

### 实测（`probe_expedition_walls`，seed 77001199）

| 指标 | 修复前 | 修复后 |
| --- | --- | --- |
| 舞台网格 | `18 × 16` | `50 × 50` |
| `floor_world_rect` | `Rect2(-50, -35, 90, 80)` | `Rect2(-125, -125, 250, 250)` |
| `support_rect_count` | 4（窄矩形再挖中庭洞） | 1（整层满铺） |
| 外圈墙高 | 0.75m | 12.00m |
| 房间脚下楼面 | 仅 `room_01` / `room_02` 命中 | 7/7 房间全部命中 `FloorSupport` |
| 房间四向 20m 射线 | — | 每房 4 侧均在 12.3m 撞墙（25×25 半宽 12.5、内壁 12.35） |
| 玩家出生 y | −0.857（下落中） | 0.03（站在楼面） |

> 注：上表「修复后」是**当轮**（整层满铺 250×250）的实测值。同日后续又按内容外框收缩了
> 楼面与外墙，见 §8。

### 走廊不是缺陷（同一轮实测澄清）
走廊墙体一直存在且可用：`_update_corridor_streaming()` 按
`_open_edges[edge] and current_id in edge` 决定通道的 `visible` 与碰撞开关。房门未开时通道
隐藏且碰撞卸载（塔楼既有契约）；**开门后通道可见、两侧墙碰撞生效**（实测
`CorridorWallCollision_LBody/RBody` 在 y=1.5 命中）。远征房间之间是 10m 真实间隔，
通道地面由修复后的整层 `FloorSupport` 承担，因此本轮未改动走廊代码。

### 新增门禁
`verify_expedition_level01_flow.gd` 增 `_verify_level_enclosure()`（紧跟 `_verify_expedition_block`
运行，早于任何开门动作），断言：

1. 楼面舞台快照：`force_standard_map == true`、`has_content_bounds == true`、
   `content_world_rect` 对齐 5m 网格且完整包住 7 个房间、`floor_world_rect == content_world_rect`、
   `support_rect_count ≥ 1`、`base_99_100_atrium_enabled == false`、
   `outer_wall_height == 12`、`outer_visual_scale_y == 1.0`（防隐形挡墙）、舞台 `block_id == "expedition"`；
2. 物理：7 间房逐房向下射线必须命中楼面，四向射线必须命中本房墙体；
3. 走廊：每条通道中点向下必须命中地面；逐条临时置为「已开启 + 玩家在成员房」后必须
   `visible == true` 且两侧 3.5m 射线命中侧墙，测完恢复 `_open_edges` 并重放流送。

判据仍为 `EXPEDITION_LEVEL01_FLOW_OK`。

### 回归
`ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`、`TOWER_FLOOR_ROOM_AUTHORITY_OK`、
`TOWER_RUNTIME_RESTART_OK`、`CENTRAL_EXPEDITION_HOLOGRAM_FACILITY_OK` 全绿。
`verify_3d_performance_budget` 的 HUD 固定节点红项（267/278 超阈值）属既有红项，与本轮无关。

### 诊断工具
`tests/verification/probe_expedition_walls.gd/.tscn`：只读物理探针，打印楼面舞台快照、逐房
楼面/四向墙体命中体、逐条走廊地面/侧墙与碰撞体 enabled 状态，以及走廊流送契约实测。

## 7. 干净场景改造（2026-09-19 追加）

### 诉求
「新增加的远征关卡应该是一个干净的场景，只会保留游戏基础逻辑和新的关卡。」

### 症状
进入远征关卡01 后地面上散布**看不见却撞得到**的阻挡：入口安全房北侧 6.3/6.4/7.8m、
走廊中点 23.1/25.0m、`room_02`/`room_03` 西侧 32.6/67.6/102.6m 均有射线命中体。

### 根因（三处塔楼残留）

| # | 残留 | 后果 |
|---|---|---|
| 1 | `Blocks/Base/Art`（99F 基地美术：卷帘主门、补给机、工作台、枪械工坊等约 **1200 节点**）在 `_ready()` 里只被置 `visible = false` | **碰撞体仍留在物理空间**。塔楼流程会把它 `reparent` 到 99F `facility` 房（降到 y = −12）；远征没有 `facility` 房，`_install_facilities()` 直接 early-return，美术就原地留在 **y ≈ 0**——正是远征的行走平面。命中的 `(2.87, 0, −31.35)` 与场景里「枪械工坊」的作者坐标完全吻合 |
| 2 | 水平走廊建在 `Blocks/Battle` | 远征的通道被算作塔楼内容，区块归属错 |
| 3 | 楼面与外墙铺满塔楼整块 **250×250** | 内容只占一角，远处空地上立着一圈没有内容的墙；同时 `_floor_index == 0` 还把外墙**可视高度压到 0.5 倍**（5.95m）而碰撞盒仍是 12m → 上沿 6m 是隐形挡墙 |

第 3 条的 0.5 缩放是 §6 那次修复的**漏网之鱼**：`_outer_visual_transform()` 当时也被改成了
`_uses_rooftop_profile()`，但同轮把「天台女儿墙 1.50m → 0.75m」的判据一并写成了
`floor_index == 0`，远征因此继续被压扁。

### 修复

| 文件 | 改动 |
|---|---|
| `src/world3d/TowerDescent3D.gd` | ① `_ready()` 对远征调用新 `_remove_tower_base_art()`：`remove_child` + `queue_free` 整棵摘除基地美术，并把 `Blocks/Base` 上的 `asset_ids`/`source_blends` 清空（避免台账从远征场景读出「有基地美术」的假信息）；② 新增 `_connector_block()`（远征 → `Blocks/Expedition`，塔楼 → `Blocks/Battle`），水平走廊改走它；③ 新增 `_expedition_content_world_rect()`：7 房实际包围盒外扩一格（5m）并对齐 5m 网格，作为 `configure()` 第 6 参传入 |
| `src/world3d/TowerFloorStage3D.gd` | 新增 `content_world_rect` / `_has_content_bounds` / `_outer_visual_scale_y`；`configure()` 增第 6 参 `content_bounds`；`_floor_grid_dimensions`/`_floor_world_rect`/`_outer_grid_dimensions`/`_outer_world_rect` 非空内容外框时一律以它为准；**`_outer_visual_transform()` 的 0.5 纵向缩放改挂 `_uses_rooftop_profile()`**；`_build_outer_shell()` 回填 `_outer_visual_scale_y` 供门禁断言 |

`content_bounds` 默认 `Rect2()`（尺寸为 0 → `_has_content_bounds = false`），塔楼行为零变化。

### 实测（只读探针，seed 77001199）

| 指标 | 改造前 | 改造后 |
| --- | --- | --- |
| `Blocks/Base/Art` | 存在（1200 节点） | **已移除** |
| 场景总节点 | ≈ 2744 | **1544** |
| `content_world_rect` | `Rect2(-125,-125,250,250)` | **`Rect2(-10,-50,135,70)`**（27×14 格） |
| 楼面地砖数 `tile_count` | ≈ 2500 | **369** |
| `outer_visual_scale_y` | 0.5（墙可视 5.95m / 碰撞 12m） | **1.0**（可视 12m = 碰撞 12m） |
| `Blocks/Rooftop` / `Base` / `Battle` / `Stairs` 子节点 | `Base`→1200、`Battle`→6 | **全为 0** |
| `Blocks/Expedition` 子节点 | — | 14（7 房 + 6 走廊 + 1 楼面舞台） |
| 6 条 `Corridor_00..05` 父节点 | `Blocks/Battle` | **`Blocks/Expedition`** |

### 新增门禁
`verify_expedition_level01_flow.gd` 增 `_verify_clean_scene()`（紧跟 `_verify_expedition_block`），断言：
`Blocks/Base/Art` 不存在、`Rooftop/Base/Battle/Stairs` 四个塔楼区块**子节点为 0**、
`Blocks/Base` 不声明塔楼资产、每条走廊的父节点都是 `Blocks/Expedition`。
`_verify_level_enclosure()` 同步改为内容外框口径（见 §6「新增门禁」）。

### 判据与回归
`EXPEDITION_LEVEL01_FLOW_OK`。
`ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`、`TOWER_LEVEL_BLOCKS_OK`、`FLOOR_PLAN_GENERATOR_OK`、
`ARRIVAL_GATE_FLOOR_BUNDLE_OK`、`TOWER_FLOOR_ROOM_AUTHORITY_OK`、`TOWER_EXTRACTION_RETURN_OK`、
`TOWER_JOURNEY_POLISH_OK`、`LEVEL_PLAN_VALIDATE_OK` 全绿（塔楼路径未受影响）。

### 未改动项（本节口径，已被 §7.1 取代）
- ~~`Blocks/Rooftop|Base|Battle|Stairs` 四个**空容器**仍留在远征场景里~~ —— **§7.1 已改为彻底不生成这些容器**（场景只带 `Blocks/Expedition`）。
- 垂直楼梯走廊仍落 `Blocks/Stairs`：它只在塔楼生成，且**不能**改走 `_connector_block()`
  （该方法在塔楼返回 `Battle`，会把楼梯走廊从 `Stairs` 挪走，破坏 `verify_tower_level_blocks`）。**此条仍然有效**：远征是单层，永不生成垂直楼梯走廊，因此新场景不需要 `Blocks/Stairs` 容器。

## 7.1 结构性独立重建（2026-09-19 二次追加，取代 §7 的「运行时减法」）

### 决策
用户判定「远征关卡的场景之前说过要**新建**，为什么变成了**继承**？这样是不对的」，指令：**把远征关卡重头新建一份、把被污染的（继承）场景直接删掉**，并把基地内指向远征情报设施的传送链终点落到新场景。

### 为什么 §7 的减法模型不够
§7 靠 `is_expedition()` 在**运行时逐条排除**塔楼内容。但 `is_expedition()` 在 `TowerDescent3D.gd` 里**散落 31 处、三种写法**，且默认分支恒为塔楼形态——**漏一处就是一次污染**。根因是场景本身 `instance=ExtResource` 继承了塔楼整棵节点树，属于结构性缺陷，运行时打补丁只能治标。

### 改法（一处结构改动取代 31 处运行时排除）
把 `scenes/ExpeditionLevel01_3D.tscn` 的父场景从 `TowerDescent3D.tscn` 换成公共关卡基座 `scenes/Dungeon3D.tscn`：

| 项 | 旧（继承塔楼，已删） | 新（独立场景） |
|---|---|---|
| 父场景 | `TowerDescent3D.tscn` | `Dungeon3D.tscn` |
| 脚本 | 继承而来 | 显式覆写 `script = TowerDescent3D.gd` |
| 区块树 | 随塔楼整棵加载 Rooftop/Base(含 Art 1200 节点)/Battle/Stairs | **只有 `Blocks/Expedition` 一个根** |
| 塔楼污染 | 靠 `is_expedition()` 运行时逐条排除 | 塔楼节点**根本不参与加载** |
| HUD/玩家/环境 | 来自塔楼场景 | 来自 `Dungeon3D.tscn`（同一套骨架，15 个 `$` 硬依赖全满足） |

`Dungeon3D.tscn` 已含 WorldEnvironment、DirectionalLight3D、Player3D、HUD 整棵子树、走廊/房间/敌人/抛射物容器，但**没有 `Blocks`**——所以新场景自带 `Blocks/Expedition`。
`_remove_tower_base_art()` 保留为**防御性空操作**（新场景无 `Blocks/Base/Art`，调用即跳过），以兼容旧存档续局时若仍能载入到其它结构。

### 到达路径单一真源
新增 `GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D`（`src/framework/GameDesignConfig.gd`）作为「基地 → 情报室 → 选关菜单 → 读取界面 → 到达关卡」这条链的**唯一终点真源**。下列各处改为由它取值，不再各写路径字符串：

| 位置 | 角色 |
|---|---|
| `BaseFacilityCatalog.mission_operations` | 基地 99F 情报室设施（`action_path` 指向选关菜单） |
| `scenes/RogueMapSelectMenu.gd` `LEVEL_SCENE` | 选关菜单 → 读取界面 |
| `scenes/ExpeditionLoadingScreen.gd` `LEVEL_SCENE` | 读取界面 → 到达关卡 |
| `TowerDescent3D.RUNTIME_MAP_SCENE_BY_ID` | 续局/断线重连路由 |

验收脚本 `verify_expedition_level01_flow.gd` 的 `EXPEDITION_SCENE` **有意保留字面量**，作为独立旁证断言「链终点确实指向该文件」。

### 门禁升级：从「子节点为 0」到「结构不含塔楼」
`_verify_clean_scene()` 由 §7 的运行时断言（`Blocks/Base/Art` 不存在、四区块**子节点为 0**）升级为**结构断言**：
- 场景文件文本**不含**指向塔楼场景的 `[ext_resource ... path="res://scenes/TowerDescent3D.tscn"]` —— 即真正不含对塔楼场景的 `instance` 继承或子资源引用。**判据绝不能退化成「源文里出现 `TowerDescent3D.tscn` 字样就算红」**：`return_scene_path`（退出落点）合法地指向塔楼场景，见 §10。
- 运行时 `Blocks/Base/Art` 不存在；
- `Blocks` 的子节点**恰好等于** `["Expedition"]`（不再是「允许空容器」）；
- `Rooftop`/`Base`/`Battle`/`Stairs` **不得存在**；
- 每条走廊的父节点为 `Blocks/Expedition`。

### 判据
`EXPEDITION_LEVEL01_FLOW_OK`，无头直跑 `EXIT=0`，日志 **0 泄漏 / 0 USER ERROR / 0 SCRIPT ERROR / 0 FAIL**；OK 行含 `Blocks/Expedition only (scene is structurally independent of TowerDescent3D.tscn)` 与 `default tower unchanged`。

## 8. 与本机验收套件的既有约束

`scripts/run_verification_suite.sh` 会建隔离工程目录并在收尾 `rm -rf`，本机沙箱的批量删除守卫会拦下（`SAFE_DELETE_BULK_CONFIRM_REQUIRED`），core 套件跑不完。本机口径改为逐场景直跑：

```bash
GODOT="/i/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
"$GODOT" --headless --path . res://tests/verification/verify_expedition_level01_flow.tscn
```

`verify_base_world_flow` 存在**既有红项**（节点切片 563 > 阈值、`Player3D` 动画状态断言），经 `git stash` 对照证明与本轮改动无关，不属远征关卡责任范围。

## 9. 未决

- 内容房 25×25 的实际美术布局未接（当前白盒 + 复用 5m 通用组件）。
- 是否在远征关卡加终点 Boss、以及撤离条件是否升级为 `BOSS_KILL`，未定。
- `05.2 §7.4` 提到的塔楼侧 `EXTRACTION_ROOM` 30×30 通用撤离房仍是设计方案，未施工；与远征 25×25 不冲突。

## 10. HUD 文案与退出落点修复（2026-09-19 三次追加）

主人实测反馈两条：① 地图 UI 仍显示「100F 外层区域」；② 安全房里往回走（退出门）**没传回塔楼，而是传回一个老的测试场景**。

### 10.1 地图 / 房间文案残留塔楼语义

#### 根因（两块标签各自独立写死塔楼口径）

| 标签 | 位置 | 错误来源 |
|---|---|---|
| 房间标签 | HUD 顶栏 `$HUD/TopBar/Margin/HBox/RoomLabel` | `TowerDescent3D._on_room_entered()` 按塔楼口径赋值：`room_id == "start" → "100F · 天台避风港"`、`facility → "99F · 归航基地"`，其余 `floor_number = 100 - depth`。远征入口安全房的 `room_id` **恰好也叫 `"start"`**，直接落进塔楼的天台分支；其余房间会显示成「N 层 · 探索区」 |
| 地图区域标签 | 小地图正上方那块 | `Dungeon3D._process()` 每 `MINIMAP_RUNTIME_INTERVAL` 写死 `"高塔外层 · %s" % minimap.get_floor_label()`；单层关卡的 `get_floor_label()` 返回 `"LIVE"`，于是显示成「高塔外层 · LIVE」 |

#### 修复（把文案抽成可覆写的虚方法，塔楼口径原样不动）

| 文件 | 改动 |
|---|---|
| `src/world3d/Dungeon3D.gd` | 把 `_process()` 里写死的区域文案抽成虚方法 `_hud_floor_label_text()`，默认返回 `"高塔外层 · %s" % minimap.get_floor_label()`；`_process()` 改为调用它 |
| `src/world3d/TowerDescent3D.gd` | 覆写 `_hud_floor_label_text()`：`is_expedition()` 时返回 `"<关卡名> · 单层"`（关卡名取 `get_expedition_display_name()`），否则 `super()` 走塔楼口径。新增 `_expedition_room_label(room)`：入口安全屋 → `"<关卡名> · 入口安全屋"`、`EXTRACTION` 房 → `"<关卡名> · 撤离点"`、`room_NN` → `"<关卡名> · <N>号房 · <房型>"`、兜底 `"<关卡名> · 探索区 · <房型>"`。`_on_room_entered()` 对 `is_expedition()` 早分支走它，**不再进入塔楼的楼层判断** |

#### 新增门禁（已反证）
`verify_expedition_level01_flow.gd` 增 `_verify_hud_labels()`：断言远征的区域标签与房间标签**都不含** `高塔外层` / `100F` / `99F` 且**含**关卡名；并在 `_verify_default_tower()` 加反向断言「塔楼区域标签仍以 `高塔外层` 开头」。
该门禁已用临时短路（`if false and is_expedition()`）**实测翻红**，两条失败信息均按预期打出，证明是真门禁而非假绿。

### 10.2 安全房退出落点指向旧兼容基地

#### 根因
退出链：安全房退出门（`configured_expedition_retreat`）→ `_show_expedition_exit_warning()` → `_confirm_expedition_exit()` → 丢弃战利品 → `BaseManager.unregister_runtime_checkpoint_provider` + `clear_active_run_checkpoint("expedition_retreat")` → `GameEntryFlow.request_gameplay_entry(REASON_ABORT_RETURN_99F, SPAWN_BASE_99F)` → `change_scene_to_file(return_scene_path)`。

问题出在最后一个变量：`return_scene_path` 由 `Dungeon3D.gd` 导出，默认 `GameDesignConfig.BASE_SCENE_3D`（= `BaseWorld3D.tscn`）；两个远征场景也都把它硬写成 `BaseWorld3D.tscn`。而 `BaseWorld3D` 是历史遗留的**「兼容基地」**，**不是玩家出发的地方** —— 玩家真正的出发点是 `project.godot` 的 `run/main_scene` = `TowerDescent3D.tscn`，其 99F `Blocks/Base` 里才有远征情报室（`mission_operations`）。
`Dungeon3D._request_return_entry_context()` 把 `MAIN_SCENE` 与 `BASE_SCENE_3D` **都当成「回基地」**处理，正好把「退回的是兼容基地而非主场景」这个错位盖住了。

#### 修复（主人拍板：改回塔楼 99F 基地）

| 层 | 改动 |
|---|---|
| 代码（钉死，新增关卡漏写也不会退错） | `TowerDescent3D._ready()` 开头对 `is_expedition()` 设 `return_scene_path = GameDesignConfig.MAIN_SCENE` |
| 场景 | `ExpeditionLevel01_3D.tscn` / `ExpeditionLevel99_3D.tscn` 的 `return_scene_path` 由 `BaseWorld3D.tscn` 改为 `TowerDescent3D.tscn` |
| 门禁 | 验收脚本的两处断言（`_verify_expedition_level` 与 `_verify_expedition_exit_contract`）由 `BASE_SCENE_3D` 改为 `MAIN_SCENE` |

**为什么在代码里钉死而不只改场景**：`return_scene_path` 只是场景文件里的一个普通导出属性，**新增关卡时漏写一处就会把玩家退回旧兼容基地**。代码对 `is_expedition()` 统一赋值，把「远征退出必回主场景」变成结构性保证。

#### 连带修正一个假红
`_verify_clean_scene()` 原先用 `scene_text.contains("TowerDescent3D.tscn")` 判「场景仍引用塔楼」。退出落点改回塔楼后，`return_scene_path = "res://scenes/TowerDescent3D.tscn"` 是**合法内容**，却被这条断言误判成「仍继承塔楼」而翻红（`ERROR: 远征关卡场景仍引用塔楼场景…`）。
修正：**逐行判定**，只有「行首为 `[ext_resource` 且 `path="res://scenes/TowerDescent3D.tscn"`」才算真继承了塔楼场景；普通属性字符串不算。已在源码加注释警示此退化风险（见 §7.1）。

### 10.3 姊妹门禁同步（测试关卡99）
`verify_test_level_99_flow`（`TEST_LEVEL_99_FLOW_OK`，core）是远征体系**第二张关卡**（`GameDesignConfig.EXPEDITION_LEVELS[1]`，level id `99`）的验收。它同属 `is_expedition()` 体系，因此本轮改动会让它翻红 —— **已实测** `EXIT=1`：

```
ERROR: 测试关卡99 的结算返回场景不是正式基地：res://scenes/TowerDescent3D.tscn
ERROR: 测试关卡99 的场景仍引用塔楼场景 res://scenes/TowerDescent3D.tscn（塔楼内容会整棵随加载）
```

两处同类断言同批改：

| 行 | 旧断言 | 新断言 |
|---|---|---|
| `:307` | `return_scene_path == BASE_SCENE_3D`（「不是正式基地」） | `== MAIN_SCENE`（「不是塔楼 99F 基地」）—— 代码对 `is_expedition()` 统一钉死，99 同属远征 |
| `:360` | `scene_text.contains(TOWER_SCENE)`（与 §10.2 同一误判） | 逐行看 `[ext_resource ... path=塔楼]` |

并新增 HUD 文案断言（区域标签/房间标签不得含 `高塔外层`/`100F`/`99F`，且须含 `测试关卡99`），把 §10.1 的盲区在姊妹关卡上同样堵住。
判据：`TEST_LEVEL_99_FLOW_OK`，无头直跑 `EXIT=0`，**0 泄漏**。

### 判据与回归
`EXPEDITION_LEVEL01_FLOW_OK` + `TEST_LEVEL_99_FLOW_OK`，无头直跑均 `EXIT=0`，日志 **0 ERROR / 0 泄漏**。OK 行末段仍为 `abort-return-to-base contract, default tower unchanged`。
回归（全绿）：`GAME_ENTRY_FLOW_OK`、`HUD_PRESENTER_3D_OK`、`ROOM_GRAPH_PERSISTENCE_SERVICES_OK`、`TOWER_EXTRACTION_RETURN_OK`。
日志中的 `[BaseFacility3D] Missing interaction/body shape: mission_operations` 属**既有告警**（默认塔楼装配路径，`BaseFacility3D.gd` 未被本轮改动，已用 `git status` 对照确认）。
