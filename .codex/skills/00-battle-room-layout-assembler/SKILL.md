---
name: 00-battle-room-layout-assembler
description: 当拼装 ShellStorm2 战局或远征房间、制作房型组件、编辑 Godot 房间变体与具体布局时使用。路由组件规划制作、稳定 Prefab 导入及正式 TSCN 装配；Blender/JSON 仅初始化与追溯，不覆盖 Godot 手改，不修改玩法规则。
agent_created: true
metadata:
  display_name_zh: 00 战局房间美术拼装总入口
---

# 战局房间拼装（兼容总入口）

## 路由职责

保留“拼装XXX房间”这一句式作为兼容入口，但不再把全部阶段混在一个 Skill 内。先判断用户目标，再加载对应专职 Skill：

| 用户意图 | 路由 Skill |
|---|---|
| 按概念图制作安全房/通用房/BOSS房/撤离房等房间种类 Blender 源 | `01-battle-room-type-art-authoring` + 制作开始即调用 `02-battle-room-component-decomposer` 冻结组件计划 |
| 将历史整屋 Blender 源归并重建为组件母版＋实例布局 | `02-battle-room-component-decomposer` |
| 制作房间变体/具体房间布局，或可选 Blender 参考布局 | `03-battle-room-instance-layout-authoring` |
| 把组件 GLB/PackedScene 导入 Godot | `02b-godot-model-asset-import-standard` |
| 编辑既有正式 Godot 房间，或选择清单/白盒初始化装配 | `04-battle-room-runtime-assembler` |

出现“拼装XXX房间”时，XXX 若是具体房间编号，直接路由 `04-battle-room-runtime-assembler`；若是“通用房种类”等房间类型，则要求用户明确是制作种类源还是拆解组件，禁止把类型和实例混为同一资产。

完整新资产链路按“01 入口 + 02 制作前规划 → Blender 组件制作与美术验收 → 02b 导入与包装验收 → 03 正式布局 → 04 最终装配验收”执行。00 是路由入口，不是自动按编号执行的程序；直达 03/04 时也须核查 02b 前置门禁，只有已完成独立另存优化与验收、源/优化/运行版本和哈希一致的组件允许复用跳过重复导出；原始文件不动，缺优化证据必须回到 02b。

本兼容入口只处理场景美术包装。不得修改玩法、关卡规则、敌人、掉落、存档、门状态机、导航或结算逻辑。

## 分支与历史基线

先确认 `block_id / level_id`：`battle` 战局与 `expedition` 远征是独立两套分支，各用自己的拓扑、楼层、房间表和结构契约；禁止从 Skill 名或 schema 中的 battle 推断远征归属。仅显式复用已验收组件及稳定 Prefab，不继承来源分支的空间规则。

按 02 的“预算适用范围与历史例外”执行50/3/5：仅约束后续新资产；既有路径/版本/组件集合不追溯整改，实例手调不触发旧库归并。新增房型、组件/变体或几何定义不得借旧目录、旧版本或历史标签豁免。

## 目标

将战局房间制作固定为“制作前规划组件 + Blender 模块化输出 + 稳定组件 PackedScene + Godot 正式房间编辑”。采用房型 → 房间变体 → 具体房间三层；固定房型不等于禁止作者变体，变体可由 Godot 场景或明确资源路径管理，不强制每房制作 Blender 差异布局。

```text
概念图 + 白模
  -> 制作前 component_plan（唯一组件 <= 50；同族常规 <=3、有意变体最多5）
  -> Blender 每组件一份母版，房型源只放实例
  -> component_instances.json
  -> 02b-godot-model-asset-import-standard：组件导出、Godot 导入与包装验收
  -> 每组件稳定 GLB + Godot PackedScene（通过 02b 前置门禁）
  -> 用实例清单初始化房间/变体 Godot TSCN，或在 Godot 直接引用组件装配
  -> 正式房间 TSCN 保存实例摆位、增删、启用和灯光等作者编辑
  -> 初始化双端还原验收；正式编辑后按 TSCN 与已批准差异验收
```

房型 Blender 文件是组件制作工作台，也可用组件实例制作参考布局，但不是整屋导出源。禁止整屋 GLB 和房间专用的共享组件几何副本；允许由稳定组件 PackedScene 组成的房间/变体 TSCN。需要改造型时回到组件母版；组件重导只更新组件资产并保留房间实例覆写，几何、包络、原点、节点路径、碰撞或挂点接口变化须先核查所有使用房间。JSON/Blender 实例清单只用于初始化与追溯，不得自动回灌覆盖正式 TSCN。

## 触发与输入解析

将以下表达视为本 Skill 的直接触发：

- `拼装XXX房间`
- `装配XXX房间`
- `把XXX房间接入战局`
- `用现有组件拼XXX房间`

从命令中提取 `XXX` 作为 `room_query`，不得把用户没有提供的房间名、版本号或 AssetID 猜出来。

按以下优先级解析房间：

1. 精确匹配当前战局白模目录 `ShellStorm2/source/art/whitebox/**` 中的 `scene_id`、房间 `id` 或 `room_id`。
2. 精确匹配 `ShellStorm2/assets/art/environments/tower_zones/<block_id>/` 中的正式房间/变体 TSCN、房间目录、`room_manifest.json`、`room_layout.json` 或可选 Blender 参考源；`block_id` 兼容 `battle/expedition`，先确认已登记运行引用。
3. 按已确认分支读取白盒：battle可反查 `battle_level01/**/data/unit_plan.json`；expedition读取自身 `level_id` 的L1/L2/L3，不回落塔楼房表。用房间 `id`、`key`、中文名和布局记录反查正式房间源。
4. 读取房间自己的 README、manifest、QA 报告和布局清单，确认真实 `block_id=battle/expedition`、楼层范围、设计文档和 AssetID 挂钩。

出现多个候选且不能由 `room_id` 唯一确定时停止，列出候选路径并请求用户指定；不得随意选第一个。找不到候选时停止并报告搜索过的根目录。

## 资产所有权

严格区分三类内容：

### 共享组件库拥有

共享组件库的 Blender 母版拥有：

- 几何、材质、PaletteUV 和自发光；
- 几何包络尺寸与碰撞需求；实际组件碰撞和挂点由 Godot Prefab 拥有；
- 根节点、底部中心锚点、正面轴；
- 组件接口和允许旋转；
- AssetID、GLB、PackedScene 和版本登记。

优先解析当前战局组件库中数值最高且已通过导入门禁的版本，例如：

```text
assets/art/environments/tower_zones/battle/source/common_components/v###/
```

以该目录的 `component_catalog.json`、各包 `asset_manifest.json` 和 Godot 稳定运行路径为依据。不要只因为 Blender 目录版本较新就认为 Godot 已经使用该版本；必须检查 manifest 的 `exported`、`runtime_integrated`、GLB 哈希、PackedScene 元数据和正式运行引用是否一致。

### 原型白盒与参考布局拥有

原型白盒维护尺寸、门连接、可走空间和楼层拓扑约束；正式房间的内部视觉实例布局不再由白盒自动覆盖。可选的房间 Blender 参考源只拥有初始化/追溯信息：

- 房间边界、白模尺寸和房间级设计信息；
- 组件实例的 `instance_id`、`component_id`、位置、旋转和启用状态；
- 房间专属的布局标记、门连接、导航/玩法挂点；
- 可重建的 `room_layout.json` 及验收图。

房间源不得拥有共享组件的本地 Mesh、共享材质副本或房间版墙体 GLB；由稳定组件 PackedScene 引用组成的正式房间/变体 TSCN 合法。

### Godot 拥有

Godot 运行时拥有：

- 稳定的组件 PackedScene；
- `RoomLayoutAssembler3D` 或等价装配入口；
- 房间节点、玩法逻辑、门状态、导航和碰撞去重；
- 运行时探针与验收结果。

正式房间布局由 Godot TSCN 拥有，允许在编辑器内调整模块实例位置/旋转、增删、启用状态及房间灯光。源几何材质归 Blender；组件碰撞与组件挂点归 Prefab；房间级挂点、设备参数与视觉布局归正式 TSCN。玩法节点仍由既有运行逻辑拥有并记录来源，不能因编辑布局而修改玩法规则。

现有 `scripts/generate_expedition01_room_static_scenes.gd` 会重新打包并覆盖输出，没有自动合并/手改保护；子集选择也不保护被选房间。正式房间禁止未审查的全量生成；任何回填或重生成都须先备份、输出与正式 TSCN 的差异、列出保留/回填计划，取得覆盖授权后仅修改批准部分。

## 标准工作流

### 1. 建立工作快照

开始写入前读取并记录：

- `git diff --name-only`；
- 目标房间源、组件库、Godot 运行资产和现有验收清单的时间戳与 SHA-256；
- 当前 Blender 是否正在打开目标源文件；
- 当前 Godot 是否正在重导入目标资源。

不要覆盖历史 Blender 源；可选 Blender 参考修改另存源版本。正式房间布局在稳定 TSCN 编辑，写入前备份/核对现有手改，不要求为此另建 Blender 源版本。

### 2. 解析白模与房间契约

从白模 JSON 和房间设计文档读取，不从旧模型猜尺寸：

- 房间尺寸、楼层高度、5m 网格和墙厚；
- 门洞宽高、门方向和连接目标；
- 房间边界、可走面、导航和碰撞要求；
- 允许的组件族、槽位类型和旋转集合；
- `block_id`、`floor_range`、`design_scope`、`scene_design_docs`、`asset_ledger`。

对战局普通房，不强行套用安全房 15x15m 双门契约。安全房契约只是已验证样板；普通房必须按自己的白模尺寸和门连接生成槽位。

### 2b. 组件导入与版本同步门禁（正式布局前置）

在建立完整组件解析表、执行 Godot 正式布局编辑或初始化之前，先核查目标组件的源版本与导入状态。不得把本门禁推迟到第 8 步，也不得只按 01→02→03→04 的编号顺序跳过 02b。

- **新组件、未导入组件或源文件更新**：源文件先通过美术验收，再明确加载并执行 `02b-godot-model-asset-import-standard`，逐组件实际执行优化并另存独立优化文件，验证原始源哈希不变，从重开的优化文件完成 GLB 导出，再做 Godot 正式重导入、稳定 PackedScene 包装、碰撞与挂点核查、公共色盘、登记和独立加载验收。未通过不得进入后续正式布局与装配。
- **复用已有组件**：核查独立优化文件与实际优化记录、原始源不变证据、前后三角面统计与保真验收、源/优化/运行版本与哈希、PackedScene 元数据和稳定引用；全部一致时记录“02b 复用核查通过”，不重复优化与导出。缺优化文件或证据时必须回到 02b，不能以旧验收豁免。
- **资料缺失或未通过美术验收**：停止后续装配并报告阻塞项，回到 01/02 或组件制作阶段；不得用旧版、整屋 GLB 或房间专用副本补位。
- **组件接口变化**：先列出受影响房间与适配范围；02b 只定点更新组件资产，保留正式 TSCN 的实例覆写，不授予重生成房间的权限。
- **可选 Blender 参考布局**：允许在导入前以组件实例制作，但不能替代 02b；正式 Godot 布局只能消费通过门禁的组件。

门禁通过后再进入第 3 步；第 3 步发现缺失或版本漂移时返回本步骤处理，不绕过规范。

### 3. 建立组件解析表

从 `component_catalog.json` 和组件 manifest 建立：

```text
component_id
  -> package_id / slug
  -> Blender collection / root_object
  -> local_bounds
  -> origin_contract
  -> front_axis
  -> allowed_rotations
  -> stable GLB
  -> stable PackedScene
  -> collision_owner / collision_policy
  -> source_version / runtime_version
```

Godot 稳定路径必须不带版本号。版本只写入 source、manifest、PackedScene metadata、布局快照和台账。

组件解析规则：

- 优先用 manifest 明确的 `runtime_scene`；没有时才按已登记的稳定目录规则解析，不得凭文件名猜不存在的场景。
- `component_id` 必须全库唯一。
- 组件缺少 GLB、PackedScene、尺寸、原点、方向或导入状态时停止。
- 运行版本和 Blender 源版本不一致时，先报告“源已更新但 Godot 尚未接入”，不得偷偷使用旧组件或生成房间专用替代品。

### 4. 优先读取正式 Godot 布局，按需制作参考布局

已有正式房间/变体 TSCN 时直接读取并在 Godot 编辑，不用旧 JSON 或 Blender 布局覆盖。没有正式场景时，可从已验收房型实例清单、可选 Blender Collection Instance 参考布局或白盒初始化；初始化完成后正式 TSCN 接管视觉布局。

Blender 房间应使用 Library Link 或 Collection Instance 引用通用组件；不得用 Append 复制共享组件作为最终生产方式。对每个实例记录：

```json
{
  "instance_id": "WALL_NORTH_01",
  "component_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
  "slot_role": "solid_wall",
  "transform": {
    "position_m": [0.0, 0.0, 0.0],
    "rotation_y_deg": 180.0,
    "scale": [1.0, 1.0, 1.0]
  },
  "enabled": true,
  "collision_policy": "component_default"
}
```

房间布局必须是可重建的，不要把 Blender 的展示相机、灯光、临时标记或编辑器辅助对象导出为运行实例。

### 5. 执行布局门禁

在导出布局前逐项验证：

- 每个 `component_id` 都能解析到共享组件 catalog 和稳定 PackedScene；
- `room_owned_geometry=false`，房间没有共享组件本地几何副本；
- 根节点局部原点、包络和正面轴符合组件 manifest；
- 默认 `scale=[1,1,1]`；禁止用缩放修复房间尺寸；
- 组件旋转属于其 `allowed_rotations`，墙体默认只允许 0/90/180/270 度；
- 墙、地板、楼梯和门落在设计网格与接口位置；
- 门墙与门扇的 2.2m x 2.5m 门洞一致；
- 实例不穿地、不越房间边界、不遮挡门洞、不产生重复碰撞；
- 房间尺寸可由组件数量表达，不能把 5m 墙拉长成任意墙段；
- 同一房间内 `instance_id` 唯一；初始化时核对清单与 Blender 参考实例，正式编辑后以 TSCN 及批准差异核对运行实例；
- 房间不输出整屋视觉 GLB、共享组件副本或房间版组件碰撞包；允许保存引用稳定 Prefab 的房间/变体 TSCN。

使用随 Skill 提供的 `scripts/validate_layout_manifest.py` 做 JSON 结构和基础变换检查；尺寸、包络、Godot 资源存在性仍需在项目环境中执行专项验证。

### 6. 保存正式场景与可选初始化追溯

正式布局保存为已登记的房间/变体 TSCN；仅选择清单初始化路径时，将追溯布局写入房间源版本目录：

```text
assets/art/environments/tower_zones/<block_id>/source/room_instances/<room_id>/v###/room_layout.json
```

若项目已有房间源目录约定，保持其目录，不为迁移强行改名。布局文件至少包含：

```json
{
  "schema": "shellstorm2.battle.room_layout",
  "schema_version": 1,
  "room_id": "...",
  "block_id": "battle",
  "layout_version": "v###",
  "source_blend": "...",
  "whitebox_source": "...",
  "component_library": "...",
  "instances": [],
  "connections": [],
  "validation": {
    "room_owned_geometry": false,
    "non_unit_scale_count": 0
  }
}
```

布局文件是 Blender 到 Godot 的可选初始化与追溯输入，不是正式房间的持续覆盖源。正式实例位置保存于房间 TSCN，不得固化到组件 PackedScene 的 `room_placement_position` metadata，也不得复制进另一套代码布局数组。

### 7. 核查现有装配与登记能力，不虚报实现

核查组件 AssetID → 稳定 PackedScene、正式房间/变体资源路径、当前登记入口，以及实例 Transform、包络、碰撞和加载验收。目标是按房型 → 房间变体 → 具体房间选择资源，避免新增房间专用拼装函数；允许作者通过 Godot 场景/明确资源路径管理变体。

当前 `FloorPlanGenerator.ROOM_INSTANCE_LAYOUT_SOURCES` 中 `room_03/04` 仍为代码注册，轻量 `base_layout + instance_overrides` 只支持 `remove`，不是通用 add/transform/enable 解析器。不能把“新增资源即可自动注册新房间”写成已完成能力。缺少加载或登记能力时报告实现限制并请求独立授权，不能在纯美术/Skill 任务中顺手修改程序；已有能力直接复用。

### 8. 接入 Godot

通过已核实的房间登记入口加载正式 TSCN；资源路径与绑定方式按当前实现验证，不假定新资源会自动注册。下列是尚无正式 TSCN 时的初始化概念流程，`RoomLayoutAssembler3D` 仅为等价装配入口示意，不声明项目已实现该类：

```text
TowerDescent3D
  -> 创建房间节点和房间级玩法
  -> RoomLayoutAssembler3D.load_layout(room_layout.json)
  -> 按 component_id 实例化稳定 PackedScene
  -> 应用 position / rotation / unit scale
  -> 处理碰撞归属、门状态、导航和诊断 metadata
```

不要为单个新房间新增 `SAFE_ROOM_*` 一类硬编码组件数组。布局可在正式 Godot TSCN 编辑；新房间若仍需 GDScript 登记，应如实报告并另获代码修改授权，不宣称只改布局清单就已完成接入。

接入前复核第 2b 步的导入门禁与组件验收结果，确认公共色盘、碰撞、包络、正面方向和稳定引用仍有效；发现新组件或版本漂移时返回 02b 处理。本步骤不得成为首次执行组件导入规范的延后入口。

### 9. 运行时验收

至少运行：

1. 正式 TSCN 结构与稳定组件引用验证；采用 JSON 初始化时另验 JSON 结构；
2. 初始化时验证 Blender/清单还原；正式编辑后比较 TSCN 与运行实例及批准差异，不强制等于旧 Blender 数量；
3. Godot 组件 PackedScene 独立加载验证；
4. 房间运行时装配探针；
5. 门向和允许旋转的四向测试；
6. 房间包络、门洞、地面、碰撞套数和导航检查；
7. 真实渲染或非 headless 画面验收；
8. 既有 core/aggregate 验证回归。

报告必须给出：

- 解析到的房间源和布局文件；
- 实例总数、按 component_id 的计数；
- 使用的稳定 PackedScene 路径和运行版本；
- 非单位缩放、非法旋转、越界、缺失资源和重复碰撞数量；
- 运行时关键探针输出；
- 是否生成了房间专用组件；必须为 0；
- 未执行项和阻塞原因。

## 失败与回退规则

遇到以下任一情况，停止接入，不交付“看起来能跑”的半成品：

- 房间名不唯一或找不到正式源；
- 房间只有整屋 GLB，没有可追溯的组件布局；
- 共享组件被 Append 成本地副本且无法证明内容与母版一致；
- component_id 找不到 catalog、GLB 或 PackedScene；
- Blender 源版本高于 Godot 运行版本；
- 使用非单位缩放掩盖尺寸不匹配；
- 门洞、锚点、墙高、网格或碰撞契约失败；
- Godot 运行时仍走旧 `prp_tower_*` 程序化墙体，且任务要求使用共享组件；
- 正式 TSCN 与运行时实例数量或位置存在未解释差异（不把相对旧 JSON/Blender 的批准手改判失败）；
- 验收套件出现 exit 3 或 exit 4；
- 视觉验收只能由 headless 结构结果代替。

回退时保留原文件、报告阻塞点，并提出最小修复路径：补组件导入、补布局清单、修正锚点/包络、抽出装配器，或回退到上一份正式稳定运行资产。不得删除房间源、旧版本、`.workbuddy` 目录或已有 Godot 资源。

## 用户交付格式

完成后用短句汇报：

```text
已拼装：<room_id>
房间源：<path>
布局源：<path>
共享组件：<count> 类 / <count> 实例
Godot运行资产：<稳定路径摘要>
运行时验收：通过 / 阻塞
房间专用组件：0 / <数量及原因>
未改动：<原始源、非目标房间、组件母版等>
```

只有产生了新的报告、布局文件、验收图或其他可查看交付物时才展示文件。仅完成运行时检查时，在回复中给出关键结果和失败原因。

## 参考资料

- `references/api_reference.md`：布局清单字段、坐标和门禁的详细契约。
- `scene-full-pipeline`：全流程阶段门禁和固定挂钩。
- `blender-game-prop-standard`：共享组件制作、锚点、PaletteUV 和范围锁定。
- `02b-godot-model-asset-import-standard`：GLB、PackedScene、稳定路径和 Godot 验收。
- `godot-runtime-probe`：运行时实际装配探针。
- `01-battle-room-type-art-authoring`：房间种类 Blender 美术源制作。
- `02-battle-room-component-decomposer`：房间种类源拆解为组件源。
- `03-battle-room-instance-layout-authoring`：房间变体/具体房间 Godot 布局与可选 Blender 参考。
- `04-battle-room-runtime-assembler`：正式 Godot 场景编辑优先，无正式场景时路由初始化装配。
