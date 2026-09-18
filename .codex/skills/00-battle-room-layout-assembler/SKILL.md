---
name: 00-battle-room-layout-assembler
description: 当用户说“拼装XXX房间”“装配XXX房间”“把XXX房间接入战局”，或要求把 ShellStorm2 战局房间从 Blender 布局接入 Godot 时使用。负责识别目标处于房间种类制作、组件拆解、具体房间布局、Godot组件导入或最终运行装配中的哪一阶段，并路由到对应专职 Skill；仅处理场景美术，不修改玩法与规则。
agent_created: true
metadata:
  display_name_zh: 00 战局房间美术拼装总入口
---

# 战局房间拼装（兼容总入口）

## 路由职责

保留“拼装XXX房间”这一句式作为兼容入口，但不再把全部阶段混在一个 Skill 内。先判断用户目标，再加载对应专职 Skill：

| 用户意图 | 路由 Skill |
|---|---|
| 制作安全房/通用房/BOSS房/撤离房等房间种类 Blender 源 | `01-battle-room-type-art-authoring` |
| 把已验收房间种类源拆成组件 Blender 源 | `02-battle-room-component-decomposer` |
| 根据具体房间编号白模制作 Blender 组件布局 | `03-battle-room-instance-layout-authoring` |
| 把组件 GLB/PackedScene 导入 Godot | `godot-model-asset-import-standard` |
| 拼装具体房间到 Godot，并选择 Blender 布局重放或白盒直装 | `04-battle-room-runtime-assembler` |

出现“拼装XXX房间”时，XXX 若是具体房间编号，直接路由 `04-battle-room-runtime-assembler`；若是“通用房种类”等房间类型，则要求用户明确是制作种类源还是拆解组件，禁止把类型和实例混为同一资产。

本兼容入口只处理场景美术包装。不得修改玩法、关卡规则、敌人、掉落、存档、门状态机、导航或结算逻辑。

## 目标

将战局房间制作固定为“共享组件单一正本 + 房间布局源 + Godot 数据驱动重放”：

```text
通用组件 Blender 母版
  -> 每个组件 GLB + Godot PackedScene
  -> 房间 Blender 源只保存组件实例布局
  -> room_layout.json
  -> Godot 按 AssetID 实例化同一批 PackedScene
  -> 房间运行时验收
```

房间 Blender 文件不是新的组件生产源。房间不得导出墙、地板、门、楼梯或设施的房间专用 GLB/PackedScene。需要改造型时回到通用组件母版，完成组件验收和 Godot 替换后再回放所有房间。

## 触发与输入解析

将以下表达视为本 Skill 的直接触发：

- `拼装XXX房间`
- `装配XXX房间`
- `把XXX房间接入战局`
- `用现有组件拼XXX房间`

从命令中提取 `XXX` 作为 `room_query`，不得把用户没有提供的房间名、版本号或 AssetID 猜出来。

按以下优先级解析房间：

1. 精确匹配当前战局白模目录 `ShellStorm2/source/art/whitebox/**` 中的 `scene_id`、房间 `id` 或 `room_id`。
2. 精确匹配战局正式源目录 `ShellStorm2/assets/art/environments/tower_zones/battle/source/**` 中的房间目录、`room_manifest.json`、`room_layout.json` 或 Blender 源文件。
3. 读取 `source/art/whitebox/tower_zones/battle_level01/**/data/unit_plan.json`，用房间 `id`、`key`、中文名和布局记录反查正式房间源。
4. 读取房间自己的 README、manifest、QA 报告和布局清单，确认 `block_id=battle`、楼层范围、设计文档和 AssetID 挂钩。

出现多个候选且不能由 `room_id` 唯一确定时停止，列出候选路径并请求用户指定；不得随意选第一个。找不到候选时停止并报告搜索过的根目录。

## 资产所有权

严格区分三类内容：

### 共享组件库拥有

共享组件库的 Blender 母版拥有：

- 几何、材质、PaletteUV 和自发光；
- 碰撞策略和包络尺寸；
- 根节点、底部中心锚点、正面轴；
- 组件接口和允许旋转；
- AssetID、GLB、PackedScene 和版本登记。

优先解析当前战局组件库中数值最高且已通过导入门禁的版本，例如：

```text
assets/art/environments/tower_zones/battle/source/common_components/v###/
```

以该目录的 `component_catalog.json`、各包 `asset_manifest.json` 和 Godot 稳定运行路径为依据。不要只因为 Blender 目录版本较新就认为 Godot 已经使用该版本；必须检查 manifest 的 `exported`、`runtime_integrated`、GLB 哈希、PackedScene 元数据和正式运行引用是否一致。

### 房间源拥有

房间 Blender 源只拥有：

- 房间边界、白模尺寸和房间级设计信息；
- 组件实例的 `instance_id`、`component_id`、位置、旋转和启用状态；
- 房间专属的布局标记、门连接、导航/玩法挂点；
- 可重建的 `room_layout.json` 及验收图。

房间源不得拥有共享组件的本地 Mesh、共享材质副本、房间版墙体 GLB 或房间版 PackedScene。

### Godot 拥有

Godot 运行时拥有：

- 稳定的组件 PackedScene；
- `RoomLayoutAssembler3D` 或等价装配入口；
- 房间节点、玩法逻辑、门状态、导航和碰撞去重；
- 运行时探针与验收结果。

Godot 不应重新手工摆一套视觉组件。视觉位置必须来自房间布局清单，玩法节点可以由运行时额外生成，但必须记录其来源。

## 标准工作流

### 1. 建立工作快照

开始写入前读取并记录：

- `git diff --name-only`；
- 目标房间源、组件库、Godot 运行资产和现有验收清单的时间戳与 SHA-256；
- 当前 Blender 是否正在打开目标源文件；
- 当前 Godot 是否正在重导入目标资源。

不要覆盖原始房间 Blender 源。房间布局调整应在新的房间源版本目录或用户明确指定的工作副本中进行。

### 2. 解析白模与房间契约

从白模 JSON 和房间设计文档读取，不从旧模型猜尺寸：

- 房间尺寸、楼层高度、5m 网格和墙厚；
- 门洞宽高、门方向和连接目标；
- 房间边界、可走面、导航和碰撞要求；
- 允许的组件族、槽位类型和旋转集合；
- `block_id`、`floor_range`、`design_scope`、`scene_design_docs`、`asset_ledger`。

对战局普通房，不强行套用安全房 15x15m 双门契约。安全房契约只是已验证样板；普通房必须按自己的白模尺寸和门连接生成槽位。

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

### 4. 读取或制作房间 Blender 布局

优先读取房间已有 `room_layout.json`。没有时，从房间 Blender 的链接 Collection Instance、槽位对象和白模数据生成布局清单。

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
- 同一房间内 `instance_id` 唯一；布局文件中的组件数量与 Blender 实例数量一致；
- 房间不输出新的视觉 GLB、组件 PackedScene 或房间版碰撞包。

使用随 Skill 提供的 `scripts/validate_layout_manifest.py` 做 JSON 结构和基础变换检查；尺寸、包络、Godot 资源存在性仍需在项目环境中执行专项验证。

### 6. 固化房间布局源

将布局写入房间版本目录的稳定位置：

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

布局文件是 Blender 到 Godot 的共同输入。不要让 Godot 代码复制布局数组，也不要把布局位置固化到组件 PackedScene 的 `room_placement_position` metadata 中；该 metadata 只允许描述组件自身默认信息。

### 7. 首次执行时补齐通用装配基础设施

在拼装当前房间前检查项目是否已有以下通用能力：

- 组件 AssetID 到稳定 PackedScene 的运行时注册表；
- 可读取 `room_layout.json` 的 `RoomLayoutAssembler3D` 或等价装配器；
- 房间布局资源的加载、结构校验和错误报告；
- 组件实例计数、Transform、包络和碰撞的运行时探针；
- 至少一个不依赖特定房间名称的验收场景模板。

若缺少这些能力，不得要求用户另开任务，也不得退回到房间专用硬编码。先完成一次项目级基础设施建设并运行回归验证，再继续当前房间拼装。基础设施必须满足：

- 装配器不包含任何具体房间 ID、槽位数组或组件数量；
- 新房间只新增布局资源和房间登记，不新增专用 GDScript 函数；
- 组件注册表优先由正式 catalog/manifest 生成或验证，不维护第二份手写名称表；
- 找不到组件、场景加载失败或布局非法时明确失败，不静默跳过；
- 跨文件契约有一条会失败的断言盯住；
- 既有安全房、旧塔楼隐藏关卡和存档接口不得因装配器抽取而改变。

基础设施已存在时只复用和补强，不重复创建第二套装配器。

### 8. 接入 Godot

把房间记录接入 `TowerDescent3D` 的房间实例化流程，把房间内部布局交给通用装配器，例如：

```text
TowerDescent3D
  -> 创建房间节点和房间级玩法
  -> RoomLayoutAssembler3D.load_layout(room_layout.json)
  -> 按 component_id 实例化稳定 PackedScene
  -> 应用 position / rotation / unit scale
  -> 处理碰撞归属、门状态、导航和诊断 metadata
```

不要为单个新房间新增 `SAFE_ROOM_*` 一类硬编码组件数组。新增房间应只新增或修改布局清单；若必须修改 GDScript，先判断是否是装配器缺少通用能力，而不是把房间特例继续堆入 `DungeonRoom3D.gd`。

Godot 导入阶段必须使用 `godot-model-asset-import-standard`：重新导入 GLB，独立加载 PackedScene，确认公共色盘、碰撞、包络、正面方向和稳定引用。

### 9. 运行时验收

至少运行：

1. 房间布局 JSON 结构验证；
2. Blender 组件实例回放和数量验证；
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
- 布局验证通过但运行时实例数量或位置不一致；
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
- `godot-model-asset-import-standard`：GLB、PackedScene、稳定路径和 Godot 验收。
- `godot-runtime-probe`：运行时实际装配探针。
- `01-battle-room-type-art-authoring`：房间种类 Blender 美术源制作。
- `02-battle-room-component-decomposer`：房间种类源拆解为组件源。
- `03-battle-room-instance-layout-authoring`：具体房间编号 Blender 布局制作。
- `04-battle-room-runtime-assembler`：Godot 最终装配双分支路由。
