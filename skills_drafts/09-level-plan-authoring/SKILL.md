---
name: 09-level-plan-authoring
description: 当用户说「准备生成一个新关卡」「生成新关卡」「做一张新关卡」「新关卡设计」「按模板生成关卡」，或要求把一份填好的《新关卡设计表》落成可运行关卡时使用。负责把设计意图（房间表/主路/模板池/生成策略）落成 ShellStorm2 的 L1/L2/L3 白盒设计源，跑校验器，登记关卡 id；若用户要求「能玩到」，还要接上独立单层场景与基地入口按钮。不制作美术资产、不修改玩法数值。默认不打开运行时数据驱动开关（打开会改存档指纹），仅当用户明确接受该代价时才打开。
agent_created: true
metadata:
  display_name_zh: 09 新关卡生成
---

# 09 新关卡生成

把「想设计成什么样」变成一份可校验、可派生的关卡设计源。

## 路由表

| 用户意图 | 该走 |
|---|---|
| 说「准备生成一个新关卡」「生成新关卡」、要填设计表、要把设计落成关卡数据 | **本 Skill** |
| 说「要让这张关卡真能在游戏里玩到」「在基地加个入口」「做成独立关卡场景」 | **本 Skill**，走 §2 第 6 步 |
| 做房间的美术（墙/地/门/固定设施）Blender 源 | `01-battle-room-type-art-authoring` |
| 把房间美术拆成可复用组件 | `02-battle-room-component-decomposer` |
| 给某个具体房间编号摆组件实例布局 | `03-battle-room-instance-layout-authoring` |
| 在 Godot 里把房间装配成能跑的场景 | `04-battle-room-runtime-assembler` |
| 改玩法数值、掉落、存档格式、战斗规则 | **不在本 Skill 范围**，直接说明并拒绝 |

---

## 0. 这个项目的关卡真相源

三层，缺一层都跑不起来：

```text
source/art/whitebox/tower_zones/<level_id>/<版本>/data/
  ├─ level_plan.json                  L1  关卡级：层清单 + 模板池 + 生成策略
  ├─ floors/floor_<NN>.json           L2  层级：房间表 + 主路 + 例外（核心）
  └─ room_templates/<template_id>.json L3  房间模板：尺寸 + 可开门墙 + 合法门槽表
```

版本目录默认 `v001`；已登记覆盖见 `LevelPlanLoader.DATA_ROOT_OVERRIDES`
（`battle_level01` 固定在 `v004`）。

L2 每个房间还有两个**可选**字段：

- `enemy_spawn_plan`（房间级刷怪计划：波次数 / 每波数量 / 怪物组成）。不写就完全不影响现状；
  写了就由设计源全量接管那一间房的刷怪。口径见 §2 第 2 步补充。
- `boss_content_id`（房间级首领指派：指定 Boss 房出场的是名册里的**哪一个**首领）。不写 =
  塔楼按层号取、单层关卡不出 Boss；写了就按名册条目出场。**只指定身份，不写竞技场 / 技能袋。**
  口径见 §2 第 2 步补充二。

**唯一权威规范：** `docs/v0.1/05.2_关卡版图白盒与生成规范.md`。
**可填的设计表：** `docs/v0.1/design/新关卡设计表.md`（六个部分：要你填的 / 可以改的 /
固定的 / 工具自动算的 / 硬规则 / 填完之后。**没有样例，用户明确要求过不要范例**）。

---

## 1. 动手前的必读（按顺序，不要跳）

1. `docs/v0.1/design/新关卡设计表.md` —— 要用户填哪些、哪些有默认值、哪些是固定的、哪些是派生的
2. `docs/v0.1/05.2_关卡版图白盒与生成规范.md` §3 —— 三层 schema 与门槽公式
3. 一个已通过的现存设计源，作为格式基线：
   - `source/art/whitebox/tower_zones/expedition_01/v001/data/`（单层独立关卡，推荐抄这个）
   - `source/art/whitebox/tower_zones/battle_level01/v004/data/`（塔楼多层，字段更全）

**不要凭记忆写 schema。** 现存文件里有的字段名以现存文件为准。

---

## 2. 五步流程 + 第 6 步（接入）

### 第 1 步 · 收集设计意图

**触发词：** 用户说「准备生成一个新关卡」/「生成新关卡」/「做一张新关卡」。

**第一动作 = 把设计表原样发给用户。** 读
`docs/v0.1/design/新关卡设计表.md`，把**第一部分「你要填的」整段**（1.1 关卡本身 / 1.2 层清单 /
1.3 房间模板表 / 1.4 房间表 / 1.5 主路 / 1.6 例外）原样贴给用户，让他在对话里填。

- **不要自己另造一份表**，也不要只问零散几个问题 —— 那份表的字段顺序和分区是刻意的
  （要填的在前、可调的居中、固定的在后），改动它会打乱用户的心智模型。
- 表里没有样例，**贴的时候也不要加样例** —— 用户明确要求过「不需要范例」。
- 同时附上一句：只填第一部分，第二部分不改就用默认，第三部分不能改。

等用户填完回贴。**不要猜。**

| 要确认的 | 怎么确认 |
|---|---|
| 关卡标识 / 中文名 / 所属区块 | 区块取值：`rooftop` / `base` / `battle` / `stairs` / `expedition` |
| 单层独立关卡，还是塔楼多层 | 单层 → `floor_number = 0`、`reservations = []`、`enforce_core_exclusion = false` |
| 版图来源 `mode` | `authored`（表即最终版图）/ `constrained`（约束内随机） |
| 房间表 | 逐行：`key` / `role` / `parent_key` / `template_id` / 尺寸 / `center_m` / 内容类型 |
| 主路 `main_path` | 入口到终点的 key 序列 |
| 模板池 | 每个模板的 `template_id` / `room_type` / 尺寸 / 可开门墙 |
| 内容房怎么刷 | 建议全部留空（走池子洗牌）；只在需要固定时填 |
| 每间房的刷怪 | **默认不填**（走引擎全局公式）。只有用户明确要求「这一间房的波次数 / 每波数量 / 怪物组合必须固定」时才填 `enemy_spawn_plan`，口径见第 2 步补充 |

**不要问用户的（全是派生量，问了就是错的）：**
`room_id`、`layout_id`、`ports[]`（`side` / `lane_m` / `wall_length_m`）、`reservations`（塔楼除外）、`area_budget`。
手工填几何量正是规范 §1.1 认定的漂移根因。

**最少需要用户给的关键项：**
房间表里每间的 `key` 与 `parent_key`（这决定了连通拓扑）+ `center_m` + 尺寸。
若用户只给了「要几间房、大概怎么连」而没给坐标，**先按 5m 整数格推一版坐标草案给用户确认**，
不要自己默默定稿 —— 坐标就是关卡形状本身。

### 第 2 步 · 产出 L1/L2/L3

按 §3 的 schema 落三个层级。要点：

- L2 的 `key` 用小写语义名（`entry` / `room_01` / `boss` / `exit` …），
  **不要用 `start` / `floor_01_*` 这类旧运行时 ID**（那是派生物）。
- 已上线并存过档的关卡，把旧运行时 ID 写进 `legacy_room_id`；新关卡留空。
- `template_id` 引用的 L3 文件必须真的存在，且 `size_m` 与 L2 的 `size_m` 完全一致。
- L3 的 `wall_lane_table` 按规范 §3.5 公式填：
  15m → `[0]`；25m → `[-5, 0, 5]`；30m / 40m → **没有 0m 槽**，别想当然写 0。
- 所有 `.gd` / `.tscn` / `.json` / `.md` 写 **CRLF** 行尾。

### 第 2 步补充 · 房间级刷怪计划 `enemy_spawn_plan`（可选）

**什么时候填：** 只有用户明确要求「这一间房必须固定波数 / 固定每波数量 / 固定怪物组合」时才填。
不填 / 留空 = 该房继续走引擎的全局公式（`desired = 4 + floor*2`、房型波次表、主题权重池），
这是默认且推荐的行为。**不要主动替用户填。**

**位置：** L2 `floors/floor_<NN>.json` 的 `rooms[]` 里，与 `content_type` 同级。

```json
"enemy_spawn_plan": {
  "waves": [
    { "monsters": [ { "type": "melee_chaser", "count": 2 }, { "type": "ranged_caster", "count": 1 } ] },
    { "monsters": [ { "type": "shielded", "count": 1 }, { "type": "exploder", "count": 2 } ] }
  ]
}
```

- `waves`：一项 = 一波，数组顺序即出场顺序。
- `monsters`：一波里的怪物组成，每条是 `type` + `count`。
- 一波总数 = 该波所有 `count` 之和。

**`type` 只能取这 6 个值**（= `MonsterInjector.BASE_ENEMY_TYPES` 去掉 `boss`）：

| `type` | 名字 |
|---|---|
| `melee_chaser` | 小菌猪 |
| `ranged_caster` | 孢子射手 |
| `summoner` | 蜂巢怪 |
| `shielded` | 壳甲卫兵 |
| `exploder` | 炸弹果 |
| `ambusher` | 地刺虫 |

`boss` **不可填**：Boss 有独立的出场与结算路径，从刷怪入口硬塞会绕过 Boss 逻辑。

**硬上限（超了校验器直接红）：** 波数 ≤ 6、单波总数 ≤ 24、全房总数 ≤ 64。

**只能填在会刷怪的房型上。** 判定口径是 `content_type`（**不是** `room_type`），必须让
`GameDesignConfig.is_spawn_plan_authorable_room(content_type)` 为真 —— 也就是房型属于
`ROOM_TYPES_WITH_HOSTILES`（`COMBAT` / `ELITE` / `BOSS` / `TRAP` / `BASEMENT` / `STORAGE` /
`SCAVENGE`）**且不是 `BOSS`**。填在安全房 / 撤离房这类永不调用刷怪入口的房上会报
`enemy_spawn_plan_on_non_hostile_room`；填在 Boss 房上报 `enemy_spawn_plan_on_boss_room`
（Boss 房不是「不刷怪」，而是**不归设计源管** —— 见下面的「第 2 步补充二」）。
没有这两条断言时它们只会静默失效。

**不要在本文件里复刻那两个房型表。** 唯一口径是
`GameDesignConfig.is_spawn_plan_authorable_room` 与 `GameDesignConfig.is_boss_room`，
静态校验与运行时兜底共用它们；复刻一份必然与真源漂移。

**接管范围（要说清楚给用户）：** 填了之后，该房的**波次数、每波数量、怪物组合**全部以设计源为准，
`desired` 数量公式、COMBAT 波次表 `[1,2,2,3]`、主题权重池 `enemy_pool` 一律不参与。
但**单只怪的数值**（血量 / 伤害 / 速度）仍由 `MonsterInjector` 出，主题倍率与楼层缩放照常生效 ——
设计源只写「要谁、几只」，不写数值。这样数值永远只有一个真源。

**校验错误码：**

| 错误 | 含义 |
|---|---|
| `enemy_spawn_plan_not_object` | 值不是对象 |
| `enemy_spawn_plan_on_non_hostile_room` | 房型不刷怪，写了等于静默失效 |
| `enemy_spawn_plan_on_boss_room` | 写了 Boss 房 —— Boss 房不归设计源管，要指派首领请用 `boss_content_id` |
| `enemy_spawn_plan_waves_empty` | `waves` 缺失或为空 |
| `enemy_spawn_plan_too_many_waves` | 波数超过 6 |
| `enemy_spawn_plan_wave_not_object` | 某一波不是对象 |
| `enemy_spawn_plan_wave_monsters_empty` | 某一波没写 `monsters` 或为空 |
| `enemy_spawn_plan_monster_not_object` | 某一条怪不是对象 |
| `enemy_spawn_plan_unknown_monster` | `type` 不在可填的 6 个里 |
| `enemy_spawn_plan_monster_not_authorable` | `type` 写了 `boss` |
| `enemy_spawn_plan_monster_count_invalid` | `count` ≤ 0 |
| `enemy_spawn_plan_wave_too_large` | 单波总数 > 24 |
| `enemy_spawn_plan_total_too_large` | 全房总数 > 64 |

**落地要有两道闸（缺一即等于没接通）：**

1. `LEVEL_PLAN_RUNTIME_GUARD_OK ... plans=N boss_ids=N` —— 末尾的 `plans` 是这个校验器
   **真找到并逐值比对**过的刷怪计划条数，`boss_ids` 是首领指派条数。填了几间房就该是几。
   **出现 `plans=0` / `boss_ids=0` 而设计源里确实写了，就是字段半路被吞了**（见坑 18），
   不是「没问题」。注意：当前所有关卡都没写 `boss_content_id`，所以门禁会额外打一行
   `LEVEL_PLAN_RUNTIME_NOTE` 说明该字段暂无可比样本 —— 这个字段的透传改由专属门禁的手写
   patch 探针覆盖，别把「没样本」当成「已验证」。
2. 专属门禁里真调一次刷怪入口，逐值断言波次数 / 每波数量 / 总敌数。
   范本：`tests/verification/verify_test_level_99_flow.gd` 的 `_verify_enemy_spawn_plan`
   —— 它同时留一间**没填**的同类房做 A/B，证明覆盖是「按房间可选」而不是「一填全改」。

### 第 2 步补充二 · 房间级首领指派 `boss_content_id`（可选）

**什么时候填：** 只有用户明确要求「这一间 Boss 房出场的**是哪一个**首领」时才填。
不填 = 塔楼按层号取名册条目（95 / 90 / 85），**单层关卡则不出 Boss**（见下面的口径）。
**不要主动替用户填。**

**位置：** L2 `floors/floor_<NN>.json` 的 `rooms[]` 里，与 `content_type` 同级。

```json
{ "key": "boss", "role": "boss", "content_type": "BOSS",
  "boss_content_id": "boss_hollow_choir_85" }
```

**本字段只能写「是哪一个」，不能写「怎么打」。** 首领的**身份**由它指定，其余全部由名册
`BossContentCatalog` 决定：显示名、正式模型、竞技场资产、阶段技能袋、强调色。设计源
**绝不**写竞技场 / 技能袋 / 血量 / 波次 —— 那会和名册形成两份真源。

**可填的值**（`BossContentCatalog.CONTENT` 的键，当前 3 个）：

| `boss_content_id` | 名字 | 固有层号 |
|---|---|---|
| `boss_abyss_archivist_95` | 深渊档案官 | 95 |
| `boss_furnace_warden_90` | 熔炉狱监 | 90 |
| `boss_hollow_choir_85` | 空洞合唱团 | 85 |

**解析口径（唯一真源 `BossContentCatalog.resolve_profile`）：**

1. 写了 `boss_content_id` → **就用它**，层号取该条目的**固有层号**（不是房间所在层号）。
2. 没写 → 按房间所在层号取名册条目（塔楼 95 / 90 / 85 照旧工作）。
3. 两层都取不到（**单层关卡没写**）→ **本房不出 Boss**。这是**合法空房**，不是错误：
   运行时清房放行、状态栏提示「首领房未指派首领 · 区域已放行」，**不会** `push_error`。
4. 写了但名册里没有（拼写错误）→ **什么也不出，且绝不静默换人**。作者只会看到「我明明
   指定了却没出现」，所以静态校验必须提前拦住（见下）。

**校验错误码：**

| 错误 | 含义 |
|---|---|
| `boss_content_id_on_non_boss_room` | 填在了非 Boss 房上（只有 Boss 房能指派首领） |
| `boss_content_id_unknown` | 指向名册里不存在的内容（拼写错误） |

**「Boss 房」的判定口径是 `GameDesignConfig.is_boss_room(content_type, role)`** ——
`content_type == "BOSS"` **或** `role == "boss"` 都算。为什么两者都要认：
`FloorPlanGenerator._assign_content_types_data_driven` 会把 `role == "boss"` 的房间**钉成**
`type = "BOSS"`（玩法不变量），所以只写 `role` 没写 `content_type` 的房间运行时照样是 Boss 房，
只看 `content_type` 会让它绕过静态校验。

**落地要有闸：** 专属门禁里逐条断言四件事 —— ① 写了就按写的出；② 没写且同层有名册条目就按层出；
③ 单层没写就**一只都不出**；④ 写错 ID**不静默换人**。范本：
`tests/verification/verify_test_level_99_flow.gd` 的 `_verify_boss_identity`。
透传侧（设计源 → 运行时计划）另有一条手写 patch 探针，因为至今没有关卡在数据里写这个字段，
纯读现成关卡会让这条断言退化成 0 样本空跑。

### 第 3 步 · 取门槽数据（禁止手算）

**绝不在第二种语言里复刻门槽公式。** 唯一实现是 `src/map/RoomDoorLane.gd`。
用校验器的只读取数模式拿现成结果：

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path <项目根> \
  res://tests/verification/verify_level_plan_design_source.tscn -- \
  --emit-ports --level=<level_id>
```

逐行输出：

```text
PORT_JSON <level> <floor> <key> [ {端口...} ]      ← 直接粘进 L2 该房的 "ports"
PORT_DATA <level> <floor> <key> declared [ ... ]   ← 当前声明值，用于比对
```

把 `PORT_JSON` 里的数组按 §2 的键序（`port_id` / `target` / `side` / `lane_m` / `wall_length_m`）
逐个房间写进 L2，位置放在 `template_rotation_deg` 之后。

> 也可以干脆**不写 `ports`** —— 加载器会退回几何推导，运行时结果一样。
> 但只要写了，校验器就会逐字段与推导比对，写错必红。

### 第 4 步 · 校验

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path <项目根> \
  res://tests/verification/verify_level_plan_design_source.tscn -- --level=<level_id>
```

**判据（两条都要看到，少一条不算通过）：**

```text
LEVEL_PLAN_VALIDATE_OK levels=1 checks=... rooms=... templates=...
LEVEL_PLAN_RUNTIME_GUARD_OK levels=1 rooms=... checks=... plans=...
```

第一条查设计数据自洽；第二条**真的调一次生成器**，查产出可用（功能房类型 / 尺寸 /
内容房计数）。两条不是一回事 —— 实测曾有设计数据全绿而产出把入口房类型产成空串。

末尾的 `plans=` 是「设计源里写的刷怪计划，有几间真的带到了运行时计划」。没填刷怪计划时它是
`0`，属正常；填了却还是 `0`，就是字段半路被吞了（见坑 18）。

不过就逐条读 `LEVEL_PLAN_ERROR`（设计数据侧）或 `LEVEL_PLAN_RUNTIME_ERROR`（产出侧），
回去改设计源。设计数据侧错误码含义：

| 错误 | 含义 |
|---|---|
| `room_size_not_grid_multiple` | 尺寸分量不是 5m 整数倍 |
| `room_center_not_snapped` | 中心没落在 `5k + 尺寸/2` 格点上 |
| `room_overlap` / `outside_floor_bounds` | 重叠 / 出界 |
| `occupies_core` | 非交通房压了 65×65 核心筒（单层关卡应设 `enforce_core_exclusion: false`） |
| `corridor_not_colinear` | 父子房横向偏移 > 5.01m，不共轴 |
| `corridor_too_short` / `corridor_not_integer_segments` | 净距 < 5m / 段数非整数 |
| `port_derivation_mismatch` | **L2 手写的门侧或 lane 与几何推导不一致** |
| `port_lane_not_in_template_table` | 门槽不在 L3 该墙的合法槽里 |
| `room_template_unknown` / `room_size_differs_from_template` | 模板不存在 / 尺寸对不上 |
| `main_path_short` | 主路内容房数低于 `min_main_content_rooms` |
| `branch_count_out_of_range` | 支线条数越界 |
| `area_budget_exceeded` | 超出 `可用面积 × target_occupancy_ratio` |

### 第 5 步 · 登记与报告

- 新关卡放在 `source/art/whitebox/tower_zones/<level_id>/v001/data/` 即被自动发现；
  非默认版本目录才需要加进 `LevelPlanLoader.DATA_ROOT_OVERRIDES`。
- 若该关卡需要进默认校验集，把 id 加进
  `tests/verification/verify_level_plan_design_source.gd` 的 `TARGET_LEVELS`。
- **登记与否会给用户不同后果，要主动讲清楚（用大白话）：** 不登记 → 这次用它 `--level=<id>`
  能过，但以后没人会再自动检查它，改坏了不会有任何提示；登记 → 每次批量校验都覆盖它，
  但 `LEVEL_PLAN_VALIDATE_OK levels=/rooms=` 的基线数字会变，docs 里记的基线要同批更新。
  纯测试用、可能随时删的关卡默认**不登记**，把取舍讲给用户让他定。
- 报告要给出：产出文件清单（全路径）、校验输出的那一行判据、以及**没做的事**（见 §4）。

### 第 6 步 · 让新关卡真能在游戏里玩到（仅当用户要求）

设计源通过校验只说明「这份数据自洽」，游戏里仍然跑的是内置房表。要真能玩到，**必须**同时做这四件事；
少任何一件都不会报错，只是静默不生效 —— 所以顺序别乱：

**6.1 打开本关卡的数据驱动开关（先确认用户接受代价）**

在 L1 `generation_policy` 加 `"runtime_enabled": true`。**这是逐关卡的**：只改这一关，
不要碰 `expedition_01` / `battle_level01`（它们的设计源只是校验器的输入，运行时仍走内置房表）。
打开会改这一关的 `layout_id`，`expedition_01` 的既有存档不受影响，但**这一关自己的旧档会失效** ——
只有用户明确说「先不管存档」时才能开。

**6.2 关卡 id 登记进 `GameDesignConfig.EXPEDITION_LEVELS`**

这是远征体系新增关卡的**唯一登记点**，一条记录 = 一张可直接进的单层独立关卡：

| 字段 | 作用 |
|---|---|
| `level_id` | = 设计源目录名 = `LevelPlanLoader` 的 level_id |
| `run_id` | 运行时标识：进存档、也是续局路由的键 |
| `display_name` / `setting_name` / `subtitle` / `objective_line` | 菜单标题、读取界面副标题、HUD 目标文案 |
| `scene_3d` | 到达场景路径 |

选关菜单、读取界面、续局路由**全都从这张表取值**，所以任何地方都不要再写一份路径字符串。
清单首条就是「未指定关卡时的默认终点」，新增关卡一律追加在后面。

**6.3 新建独立场景 `scenes/ExpeditionLevel<NN>_3D.tscn`**

直接照抄 `ExpeditionLevel01_3D.tscn`：父场景是**公共关卡基座** `scenes/Dungeon3D.tscn`
（**不是** `TowerDescent3D.tscn`），覆写 `script = TowerDescent3D.gd`，然后设
`expedition_mode = true` / `expedition_run_id = "<run_id>"` / `expedition_plan_id = "<level_id>"`。
`Blocks` 下**只挂 `Expedition`**，不要挂 Rooftop / Base / Battle / Stairs —— 挂上就是塔楼内容随加载。

**6.4 设计源的房间 `room_id` 必须对齐运行时契约（最容易漏、且完全静默）**

见 §5 坑 12。远征关卡运行时是**按字面量认房**的：入口房恒 `start`、撤离房恒 `extraction`、
主路 `room_01…room_0N`。而 05.2 §7.1 的 `f%02d_<key>` 命名规则是**塔楼层**的约定，套到远征上会错。

**6.5 写专属门禁**

照 `tests/verification/verify_test_level_99_flow.gd` 写一份 `verify_<关卡>_flow.gd/.tscn`，
至少断言：数据驱动真的生效（`plan.trigger == "level_plan_data"`，**不是** `expedition_bootstrap`）、
房间编号就是 `start` / `room_01..N` / `extraction`、内容房数等于设计值（不是内置房表的 5+2 房）、
`Blocks` 下只有 `Expedition`、入口门免费、撤离信标是 `STANDARD` 且挂在 `extraction` 房里、
菜单里有关卡入口按钮、读取界面终点跟随待进入态。然后加进
`scripts/run_verification_suite.sh` 的 `core_scenes`。

> 判据名约定：`<LEVEL>_FLOW_OK`（与 `EXPEDITION_LEVEL01_FLOW_OK` 同一风格）。

---

## 3. 南北方向约定（跨语言红线，写错不会报几何错）

```text
平面 +y  →  世界 +z  →  south（南）
平面 −y  →  世界 −z  →  north（北）
```

来源：`TowerDescent3D._plan_world_position`（`Vector3(x, -层高, y)`）
+ `Dungeon3D._direction_between`（`delta.z >= 0 → "south"`）。

门侧写反**不会让任何几何校验失败**（`lane_m` 仍然对）。历史上这条约定曾经整体反向却无人发现，
现在靠 `port_derivation_mismatch` 断言盯住。所以：**不要目测，跑第 3 步取数。**

---

## 4. 禁区

| 不要做 | 为什么 |
|---|---|
| 未经用户明确同意就打开 `generation_policy.runtime_enabled` | 切数据驱动会改 `layout_id`，存档按它比对，不一致**整档恢复失败**。05.2 §9 的 D4（存档兼容）尚未裁决 —— 只有用户明说「先不管存档」才能开，且只开他指定的那一关（见 §2 第 6 步） |
| 打开 `expedition_01` / `battle_level01` 的 `runtime_enabled` | 这两关的设计源当前只是校验器输入，运行时走内置房表。打开会直接改动**已上线关卡**的存档指纹 |
| 给远征关卡的 L2 写 `f%02d_<key>` 形式的 `room_id` | 运行时按字面量认房（`start` / `extraction`），写错不报错，只是出生点与撤离信标静默失效（见 §5 坑 12） |
| 手改已上线关卡的 `legacy_room_id` | 会打断旧档的 `room_progress` 索引 |
| 在 Python / 其它语言里复刻门槽或走廊公式 | 这正是规范 §1.1 的病根；一律走 Godot 侧唯一实现 |
| 把 05.2 已经写好的公式抄到第二个地方 | 改一处漏一处，必然漂移 |
| 动 `grid_unit_m` / `wall_thickness_m` / `floor_height_m` / 场地与核心筒尺寸 | 全局几何基准，改等于改引擎口径，不属本 Skill 授权 |
| 顺手改 `FloorPlanGenerator` 的塔楼内置房表 | 塔楼路线已冻结；新关卡走设计源，不动老表 |
| 改了 `.gd` 却忘了 `.tscn` / `preload` 的引用 | 改名与引用必须同一批完成 |
| 擅自给房间填 `enemy_spawn_plan`（或替用户猜波数 / 怪物组合） | 它是**可选覆盖项**。用户没明确要求「这一间房固定刷法」时，留空走全局公式才是对的；替他猜会静默改掉那一间房的节奏 |
| 在 `enemy_spawn_plan` 里写单只怪的数值（血量 / 伤害 / 速度） | 设计源只写「要谁、几只」。数值由 `MonsterInjector` 统一出，写第二份必然漂移 |
| 给 Boss 房写 `enemy_spawn_plan` | Boss 房不归设计源管。写了会让刷怪入口跳过 boss 生成，表现为「Boss 房没有 Boss」并可能锁死下楼门 —— 校验器报 `enemy_spawn_plan_on_boss_room` |
| 在 `boss_content_id` 里写竞技场 / 技能袋 / 血量 | 设计源**只指定身份**，其余全由 `BossContentCatalog` 名册条目决定。写第二份必然与名册漂移 |
| 擅自给房间填 `boss_content_id` | 同为可选覆盖项。用户没明确说「这一间房要出哪个首领」时，留空（塔楼按层取 / 单层不出 Boss）才是对的 |
| 以为「单层 Boss 房没写首领」是配置错误 | 那是**合法空房**：运行时清房放行、不报错。别去补 `enemy_spawn_plan` 或硬塞一个小怪顶替 |

---

## 5. 已知坑

1. **`class_name` 全局标识符不可靠。** 新增脚本在
   `.godot/global_script_class_cache.cfg` 刷新前用全局名会直接 parse error，
   headless 门禁会**静默红掉**。新增模块一律用显式
   `const X := preload("res://...")`，别依赖 `class_name`。
2. **`^` 的左右操作数必须都是 int。** `absf()` 返回 float，会让整行 parse error。
   要用 `absi()` / `abci()`。
3. **新脚本首次跑之前先 `--headless --path . --import`** 刷一次导入与类缓存。
4. **`Node3D` 类型变量上的方法返回值不能用 `:=` 推断**，必须显式标注类型，
   否则 parse error 会让场景空跑并挂死且无输出。
5. **功能房的 `type` 不在设计源里，但运行时靠它认房。** 入口 / 出口楼梯厅 / 撤离房 /
   Boss / Boss 前厅的类型来自 `FloorPlanGenerator._default_type_for_role()`，与内置房表
   逐值一致（`STAIR_LOBBY` / `EXTRACTION` / `BOSS` / `UPGRADE`）。设计源不写
   `content_type` 是合法的，这类房间**不会**被内容池洗牌 —— 所以改动
   `_assign_content_types_data_driven` 的 skip 列表时，务必让功能房保留缺省值。
   护栏：`LEVEL_PLAN_RUNTIME_GUARD_OK`（见第 4 步）。
6. **行尾**：`.gd` / `.tscn` / `.json` / `.md` 一律 CRLF。
   `sed -i` 在 MSYS 下会把 CRLF 变成 LF，改完要转回来。
7. **不要批量 `rm -rf`**：沙箱守卫会拦（`SAFE_DELETE_BULK_CONFIRM_REQUIRED`）。
   逐场景跑 `--headless --path . res://tests/verification/<场景>.tscn` 再 grep `*_OK`。
8. **校验通过 ≠ 可以上线。** 设计源校验只证明「这份数据自洽」，不证明运行时行为符合预期。
   所以第 4 步必须**同时看到两条判据**：`LEVEL_PLAN_VALIDATE_OK`（数据自洽）与
   `LEVEL_PLAN_RUNTIME_GUARD_OK`（产出可用）。少任何一条都不算通过。
9. **Windows 原生 Python 不认 bash 的 `/tmp`。** 用 bash heredoc 把脚本写到 `/tmp/x.py`
   再用 `python.exe /tmp/x.py` 跑，会 `No such file or directory` —— 两者解析出的目录不同
   （Windows Python 把 `/tmp` 当成 `I:\tmp`）。脚本一律落在真实 Windows 路径
   （项目 `_scratch/` 或 `%TEMP%`）再执行，或改用 `python.exe - <<EOF` 走 stdin。
10. **GDScript 的 `%` 格式化不支持 `%g`。** 写了 `"%gx%g" % [w, h]` 只会在**运行时**抛
    `ERROR: String formatting error: unsupported format character`，parse 阶段不报，
    校验判据照样全绿 —— 只有日志里每房一条 `ERROR` 能看出来。受支持的是
    `%s %d %f %x %X %o %c %v %%`。要按数值拼字符串键，用
    `FloorPlanGenerator._size_catalog_key()`（`"%.3f"` + `rstrip("0")`）。
    跑完校验**必 grep `ERROR`**，不能只 grep `*_OK`。
11. **同一份文件的多次编辑必须串行，且改完立刻回读。** 并行发多个改同一文件的编辑请求时，
   各自按「读原文件 → 写回」执行，**后写的会整体覆盖先写的**，而每个请求都回「成功」——
   结果只保留一处改动，且没有任何报错。批量改一个文件要么串行，要么一次改完。
   **实测复现**（2026-09-19）：给同一份验收脚本连发 3 个编辑，其中 **2 个静默丢失**，
   直到跑门禁报 `Identifier "guard_boss_ids" not declared` 才发现。
   纪律：**改完一处就 grep 回读那一处**（别攒着最后一起看），也别把「工具回成功」
   当成「改动已落地」。
12. **远征关卡的运行时房间编号不是 `f%02d_<key>`。** 05.2 §7.1 的
   `room_id = "f%02d_%s" % [floor_number, key]` 是**塔楼层**的约定；远征关卡运行时
   （`TowerDescent3D`）是**按字面量认房**的：入口房恒取 `"start"`、撤离房恒取 `"extraction"`、
   主路恒取 `room_01…room_0N`。所以远征 L2 里 `entry` 的 `room_id` 要写 `start`，
   其余房间与 `key` 同名。

   写错的代价是**完全静默**：几何校验、`port_derivation`、`LEVEL_PLAN_VALIDATE_OK`、
   连 `LEVEL_PLAN_RUNTIME_GUARD_OK` 全都照样绿（`_commit_floor_bundle` 是按 `key` 找房的，
   撤离信标按 `ids_by_key["extraction"]` 挂也照样对），但玩家出生点会取不到房、
   塔楼侧的 `start` 兼容位全是空。**只有真装配一次场景才看得见** → 见 §2 第 6.4 / 6.5 步。

   另外：新关卡一律把 `legacy_room_id` 留空（那是给已上线关卡迁移旧档用的）。
13. **`peek_/consume_pending_*` 永远不返回空串。** 它们刻意做了「空则回退默认值」，
   所以拿返回值判「已清空」会永远失败 —— 要判清空得直接看静态量本身。
   同理，验收脚本里**不要**为了测「未登记关卡被拒绝」去调 `select_expedition_level(坏 id)`：
   它会 `push_error`，而套件靠「日志里零 `ERROR`」判绿，故意制造的引擎错误会污染判据。
14. **GDScript 协程不 `await` 就直接调，只跑到第一个 `await` 就返回。** 视觉探针里
   `_capture_overview(...)` 内部有 `await _settle()`，漏写 `await` 会让它在后台继续跑，
   等主流程把相机挪到下一间房时才存图 —— 结果是 `overview.png` 里装的是**下一间房**的画面，
   两张图逐像素相同，而 `*_OK` 照样绿、`ERROR` 也是 0。**凡是带 `await` 的函数，
   调用处一律 `await`。** 自检手段：打印每个采样点的机位，并对比产出图的差异
   （用 `scripts/png_diff.py`，零依赖），别只信 `*_OK`。
15. **写「画面」验收（visual 探针）时的五个必踩点** —— `verify_test_level_99_visual.gd`
   是现成范本（它把这五条全踩了一遍并留下注释）：

   | 症状 | 真因 | 正确做法 |
   |---|---|---|
   | 六张图互相逐像素相同 | 协程没 `await`（坑 14） | 调用处 `await`；再用 `scripts/png_diff.py` 客观比对 |
   | 机位怎么设都被打回默认视角 | `TowerDescent3D._physics_process` 每帧调 `_apply_indoor_camera_pose()` 覆写 `player.camera` | 要自定机位就先 `tower.set_physics_process(false)`，拍完恢复 |
   | 整套图漆黑一片 | `PlayerFlashlight3D.start_enabled` 默认 **false**（要玩家按 F）。探针误把它关掉就没了主光源 | 显式 `set_light_enabled(true)`；房间默认也关灯，用 `RoomLightSwitch3D.toggle_light()` 开 |
   | 130m 外的俯瞰糊成一片灰 | 本关 `Environment.fog_density = 0.04`，130m 处雾遮挡 ≈99.5% | 俯瞰图临时 `fog_enabled = false`（**隔离变量**，不是掩盖问题——雾在十几米游玩距离下观感正常）；房间图一律不动雾 |
   | 房间图相机穿墙／只拍到一整面墙 | 游戏相机在玩家局部系偏出约 `(6.2, 10.3, 6.2)`m；玩家站到离房心 9m 时相机已落到墙外 | **玩家站房间正中央**（相机离房心仅约 6.2m，15m/25m 房都在墙内）；别去调 `adjust_debug_camera_trailing`，拉近反而贴到玩家背后 |

   另外两条取景事实（不是 bug，别去改）：**游戏相机俯角 ≈55°，看不到正前方的门洞**，
   所以「走廊有没有接上门」这类判读要走独立近距机位；**房间外壳是惰性构建的**，
   拍俯瞰图前必须对每间房调一次 `force_enter_room_for_test()` 把外壳建出来。
16. **走廊可见性由「当前房是否属于该边两端」决定，只调 `force_enter_room_for_test()`
   不够。** `_update_corridor_streaming()` 里 `active = _open_edges[edge] and current_id in ids`，
   而 `current_id` 取自**玩家实际所在房**。所以探针里若只 `force_enter_room_for_test("room_01")`
   却没把玩家挪过去，`room_01↔room_02` 会按契约继续隐藏 —— 这是**正确行为**，不是关卡缺陷。
   要么把玩家真的放进那间房（`player.global_position = room.global_position + ...`），
   要么明确说明本张图刻意显示全部走廊（俯瞰图就是这么做的，并在注释里写明为何偏离契约）。
17. **拍单体资产图（不加载关卡）时的两个必踩点** —— 范本
   `tests/verification/probe_door_leaf_visual.gd`：

   | 症状 | 真因 | 正确做法 |
   |---|---|---|
   | `ERROR: Node not inside tree. Use look_at_from_position()`，机位全乱、图里只有几层亮度 | `Camera3D` 还没 `add_child` 就调 `look_at()`/`make_current()`，树外 `global_transform` 是恒等、静默失败 | 先 `add_child(camera)` **再**设 `position` / `look_at()` / `make_current()` |
   | 金属/高反光资产在纯色背景里渲染成**近黑**（中心像素 luma 0.05–0.11），判据误报「没渲染出内容」 | 金属靠**环境反射**才有亮度，纯色 `Environment` 没有可反射内容 | `Environment` 用 `ProceduralSkyMaterial` 天空 + `ambient_light_source = AMBIENT_SOURCE_SKY`；光源能量调足（1.15→2.1） |
   | 门扇等**底边为原点**的资产在关卡里判「没贴地」 | 资产以底边中心为原点，装配时靠 `visual.position.y = -DOOR_CLEAR_HEIGHT_M * 0.5` 对齐门中心；实测有个位数 mm 余量（门扇 8mm 悬空）属**正常** | 核贴地用**世界空间 AABB 底边**（阈值 `MAX_BOTTOM_GAP_M≈0.012`），     别用局部坐标拍脑袋；8mm 要在文档里**如实登记**为已知边界，不是 bug |
18. **给房间加「房间级字段」时，两处 `configure` 调用点都要改 —— 漏一个就静默丢字段。**
   房间实例有**两处**实例化点，各自把 record 拷进 `DungeonRoom3D.configure({...})`：
   - `Dungeon3D._generate_layout()` —— 塔楼 / 公共基座路径
   - `TowerDescent3D._instantiate_dynamic_room()` —— **远征关卡走这一个**

   两处的 `configure({...})` 都是**显式白名单**：没列进去的键根本不会传，字段在房间实例上就是空。
   实测：只给前者加了 `enemy_spawn_plan`，远征关卡 99 的房实例上仍是空字典，而
   `LEVEL_PLAN_VALIDATE_OK`、`LEVEL_PLAN_RUNTIME_GUARD_OK`、设计源校验**全部照样绿** ——
   因为它们只验到「生成的 plan」为止，不碰房间实例。**只有真装配一次场景、再读房实例才看得见。**

   配套两条纪律：
   - `DungeonRoom3D.configure` 里新增字段一律写成 `config.get("key", 当前值)`（保留式），
     别写 `config.get("key", {})` —— 后者会让任何一次忘了带键的重复 configure 把已有值洗掉。
   - 新增房间级字段后，要在专属门禁里断言 `room.<字段>` 真的非空，**别只断言 plan**。

19. **房间级可选字段是「四道白名单」，漏任何一道都静默丢字段。** 以
   `enemy_spawn_plan` / `boss_content_id` 为例，从设计源到房实例要过四关，**每关都是重建式
   白名单、都得手工登记**：

   | # | 关卡 | 位置 | 漏了会怎样 |
   |---|---|---|---|
   | 1 | 源文件 → 规范化层 | `LevelPlanLoader.normalize_floor` 的房间字典 | 静态校验看不到该字段 |
   | 2 | 规范化层 → 运行时计划 | `FloorPlanGenerator.room_from_source` | 生成器产出里没有该字段 |
   | 3 | 计划 → 塔楼 record | `TowerDescent3D._append_plan_room_record` | 远征侧房间 meta 是空 |
   | 4 | record → 房实例 | 两处 `configure({...})`（见坑 18） | 房实例上是空值 |

   四关全绿而字段仍丢是**完全静默**的：`LEVEL_PLAN_VALIDATE_OK`、
   `LEVEL_PLAN_RUNTIME_GUARD_OK`、设计源校验都只验到第 2~3 关为止。
   **两个反向的坑要同时防：**
   - **别把字段塞进 `layout_id`。** `layout_id` 是存档指纹，加字段会让既有存档失配。
     `boss_content_id` 刻意不进 `layout_id`。
   - **别只靠「专属门禁里读现成关卡」验证透传。** 只要没有任何关卡在数据里写该字段，
     端到端断言就是 **0 样本空跑**、照样绿。必须另加**手写 patch 探针**直接驱动
     第 2 关的函数（`FloorPlanGenerator.room_from_source`），范本见
     `verify_test_level_99_flow.gd._verify_boss_identity` 尾段。
     同理，门禁末尾的样本计数（`plans=` / `boss_ids=`）要打出来并**当判据读**：
     写了字段却仍是 0，就是被吞了；本就没有样本，则要打一行 `*_NOTE` 声明而非静默通过。

---

## 6. 交付自检

- [ ] 用户说「准备生成一个新关卡」时，**先把设计表第一部分原样贴出**，没加样例、没自己另造表
- [ ] 用户填完后才动手，没有替他猜坐标或连通关系
- [ ] L1/L2/L3 三个文件都在 `<level_id>/v001/data/` 下，schema 字段名与现存文件一致
- [ ] `template_id` 全部有对应 L3 文件，且尺寸与 L2 一致
- [ ] L2 的 `ports` 来自第 3 步取数（不是手算），或干脆没写
- [ ] `LEVEL_PLAN_VALIDATE_OK` 出来了，且日志里零 `SCRIPT ERROR`、零 `ERROR:`
- [ ] `LEVEL_PLAN_RUNTIME_GUARD_OK` 也出来了（**两条判据缺一不可**）
- [ ] 若用户在 1.7 填了刷怪计划：`LEVEL_PLAN_RUNTIME_GUARD_OK` 末尾的 `plans=` 等于他填的房数
      （`plans=0` 就是没接通，回来查坑 18），且专属门禁里真调过刷怪入口、逐值断言过波次与数量
- [ ] 若用户指定了某个 Boss 房出场的首领：`boss_content_id` 写在该房上且值在名册里
      （`boss_abyss_archivist_95` / `boss_furnace_warden_90` / `boss_hollow_choir_85`），
      该房是 Boss 房（`content_type: "BOSS"` 或 `role: "boss"`），且**没**给同一间房写 `enemy_spawn_plan`
- [ ] 若用户只要求「生成设计源」：`runtime_enabled` 仍是 `false`
- [ ] 若用户要求「能玩到」：`runtime_enabled` 为 `true`**且只对他指定的那一关开**，
      `EXPEDITION_LEVELS` 已登记、独立场景已建、`room_id` 已对齐 `start`/`room_NN`/`extraction`、
      专属门禁已写并加进 `run_verification_suite.sh`
- [ ] 若做了画面验收：6 张图**逐张肉眼确认过**，且用 `scripts/png_diff.py` 确认两两不同
      （别只信 `*_OK` —— 协程没 `await` 会产出互相相同的图，拷问见 §5 坑 14/15）
- [ ] 所有文件 CRLF
- [ ] 报告里写清了产出清单 + 判据 + 未做事项
- [ ] 报告末尾**没有**用计算机术语向用户解释待决策项（说影响，不说 `layout_id` / 内存 / 字段名）
