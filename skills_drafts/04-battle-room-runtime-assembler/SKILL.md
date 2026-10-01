---
name: 04-battle-room-runtime-assembler
description: 当在 Godot 中完成或编辑具体战局房间时使用。优先编辑正式房间/变体 TSCN；无正式场景时选择清单或白盒初始化，逐组件引用稳定 PackedScene。禁止整屋 GLB 和未审查重生成覆盖手改。
agent_created: true
metadata:
  display_name_zh: 04 战局具体房间Godot装配
---

# 战局具体房间 Godot 最终装配路由

## 目标

把一个具体房间编号完成为游戏内可调用的视觉房间。输入永远是“房间编号”，不是房间种类：

```text
房间编号
  -> 路由判断
  -> 已有正式场景：直接编辑 Godot 房间/变体 TSCN（优先）
  -> 无正式场景时 A0：房型 component_instances.json 初始化
  -> 无正式场景时 A：具体房间 room_layout.json 初始化
  -> 无正式场景时 B：白盒 + Godot 组件初始化
  -> 保存正式 TSCN / 验收图 / 核实当前接入登记
```

只处理场景美术包装、组件导入和视觉装配。禁止修改玩法、关卡规则、房间拓扑、敌人、掉落、存档、门 FSM、导航或结算代码。

## 触发语句

- `拼装 main_02 房间`
- `把 exit_01 接入 Godot`
- `用白盒直装 branch_03`
- `按 Blender 布局完成安全房入口`
- `检查这个房间应该走哪个装配分支`

## 路由决策

先确认 `block_id / level_id`。battle战局与expedition远征是独立两套分支，各自拥有拓扑、楼层与房间规则；允许显式引用同一组件Prefab，不把共享实现解释为同一关卡。下文旧塔楼撤离房默认值不覆盖远征白盒。

50/3/5仅约束后续新资产，历史边界按02“预算适用范围与历史例外”：既有路径/版本/组件集合保留，不为历史超限追溯删件、重导或重生成；新房型、组件/变体或新几何定义不能借旧目录、升版或历史标签豁免。此例外不修改资源加载拒绝逻辑，也不豁免其他完整性/碰撞检查。

### 正式场景编辑（优先于初始化）

源几何材质归 Blender，组件碰撞与挂点归稳定 Prefab，房间布局归正式 Godot TSCN。允许编辑模块实例位置/旋转、增删、启用和灯光等房间参数；不展开 Prefab 内部几何维护第二份组件。JSON/Blender 实例清单仅初始化与追溯，不可自动回灌覆盖手改。

采用房型 → 房间变体 → 具体房间三层；固定房型不禁止作者变体，变体可用 Godot 场景/明确资源路径管理，无需每房制作 Blender 差异布局。原型白盒维护尺寸、端口、连接和可走空间约束，不持续拥有正式房间视觉摆位。`block_id` 兼容 `battle/expedition`。

当前 `room_03/04` 在 `FloorPlanGenerator.ROOM_INSTANCE_LAYOUT_SOURCES` 中代码注册，轻量 override 仅实现 `remove`。新增资源自动登记、通用 add/transform/enable 解析不是已完成功能；必要代码接线须单独授权，本 Skill 修订不补实现。

组件重导只更新组件资产，保留正式房间实例覆写；几何、包络、原点、节点路径、碰撞/挂点变化先核查受影响场景。已有 TSCN 必须优先加载；下列 A0/A/B 仅供初始化、原型或隔离参考生成，不得成为覆盖正式手改的捷径。

### 分支 A0：房型默认布局初始化

判定条件：

- 02 的 `component_catalog.json`、`component_plan.json`、`component_instances.json` 全部通过验收；
- 具体房间白模与房型默认尺寸、门槽和必需设施一致；
- 03 的 `room_layout.json` 只声明 `base_layout`，没有实例覆盖；
- catalog 中每个 `component_id` 已解析到稳定 PackedScene。

执行：

```text
加载 component_instances.json
  -> 解析 Blender→Godot coordinate_contract
  -> 由 AssetID 注册表逐组件实例化 PackedScene
  -> 绑定房间级门/挂点等运行节点
  -> 与 Blender 默认布局做实例表、bbox、截图三重对照
```

这是新房型的标准路径。**不要求为每个房间复制 Blender 布局，也不允许把房型 `.blend` 导成整屋 GLB。**

**当前动态初始化链路会把名单内主层地砖替换为通用棋盘砖**，这是现有实现，不是禁止正式 TSCN 编辑地砖实例的规则，也不授予覆盖手改的权限。房型源自有地砖（`slot_role=floor_tile`）在该链路中由
`DungeonRoom3D._runtime_floor_tile_component_id()` 换成通用 `ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01/C02`，
按房间局部 5m 网格棋盘交替（`(roundi((x-2.5)/5) + roundi((z-2.5)/5)) % 2`）。理由：房型地砖多为深色/异形，
各房不一致会让同一层出现两种地板观感，且深色砖吃不到光。

替换名单的写法是「精确 id ＋ 房型前缀」，例如：

```text
办公室   ENV-EXPEDITION-L01-OFFICE-FLOOR_TILE_5M
通道桥   ENV-EXPEDITION-L01-BRIDGE-TILE_UPPER
Boss 房  ENV-EXPEDITION-L01-BOSS-FLOOR_TILE_5M   （A/B/C 三变体共用前缀，用 begins_with 匹配）
```

**换砖只动视觉件**：碰撞与承重仍归 `TowerFloorStage3D`（`collision_owner=floor_support` /
`collision_policy=external_floor_support`），刷怪格仍由 `floor_tile` 角色的实例决定（替换不改变角色），
房型自有地砖件留在组件库与注册表里、只是运行时不引用。**下沉坑底砖**（如桥房 `tile_lower`）**不在**替换名单，
保持原标高与材质。

### 改房型源后同步静态房 TSCN：外科式回填（先例 2026-09-28 L 走廊 `l_turn` 凹口内墙）

静态房 TSCN（`runtime/room_instances/<block>/f00_<room>_static_layout.tscn`）即使最初由生成器初始化，转正后也是**可手工维护的正式布局源**。
现有生成器 `scripts/generate_expedition01_room_static_scenes.gd` 从动态装配重新提取并覆盖输出，**没有自动差异合并、实例覆写保留或手改保护**；`SS_STATIC_ROOMS` 只限制覆盖范围，不保护入选房间。

正式房间禁止未审查全量生成。任何重生成/回填先备份正式文件、在隔离输出核对差异，明确哪些实例摆位、增删、启用、灯光及自定义节点保留，哪些更新需要回填；获得覆盖授权后才改批准范围，不能仅因 JSON 或 Blender 更新就重写 TSCN。

- 🔴 **不要为一次局部修复跑全量重生成**：生成产物会给**每个**组件实例附完整 `metadata/*` 块
  （`asset_id` / `asset_version` / `bounds_size_m` / `collision_policy` …），与早期「编辑器重存」版一跑就产生
  大量无关差异（历史先例 boss 5460 行 / room_05 5560 行），并可能抹掉作者编辑。即使任务是补元数据，也须遵守差异审查、保留/回填计划和授权，不获得全量覆盖豁免。
- 回填步骤：① 在隔离环境跑一次生成器，把输出当**参照**（不是拿去替换）；② 只从参照取**受影响节点**的
  `instance` 路径 / `transform` / 组件 id 元数据，与正式 TSCN 手改逐项裁定后仅回填已授权项；③ 经检查移除本次修改造成的未引用 `ext_resource`；
  ④ 同步根计数 meta（`layout_instance_total`、`authored_layout_room_type_component_count`）。
- 证伪判据（必备）：抽两侧 TSCN 的**节点骨架**（`name` / `instance` 路径 / `transform`）逐节点比对，
  报告 `ONLY-IN-*` / `XFORM-DIFF` / `MISMATCH_COUNT`，区分批准作者差异与意外变化。验收条件是「未授权变化 = 0、应保留覆写未丢失」，不是与生成参照的差异必须减少；正式手改不能为对齐旧清单而消除。
- 与本次无关的同类漂移（如 `tower_wall_direction` 旧值 `south` / 新值 `west`）**保持文件原值**，不夹带。
- 换墙件时坐标与朝向要**实测反推**、不能按命名猜：节点转动 `= 房根 yaw + 源 rotation_y_deg`；层心线沿用全房统一
  `中心 = 边界 + 0.15 − 半厚`（外表面停在 `边界+0.15`）。先例：L 形**凹口两条内边**原是「单块长版剖切面
  `cutaway_reference_a/b`（`visual_only` 无碰撞）＋一排 1.35 m 剖切低墙」⇒ 拆为 6×`wall_5m_a` ＋ 5×`wall_5m_d`
  全高通用墙（实例 id 不变），并登记一条 `layout_repairs` 说明 `generator_gap`。
- 改完运行 `verify_expedition_room_static_scenes` 并核查其判据来源：当前可能仍要求 `layout_instance_total == room.authored_layout_instances.size()`。若旧探针因已批准的 TSCN 手改与初始化数组不同而报红，记录为实现/验收契约缺口，不能回滚手改来迎合旧断言，也不能伪报通过。未触碰文件的既有红项单列。

### 分支 A：具体房间有布局差异

判定条件：同时存在并通过验收：

- 具体房间编号对应的 `room_layout.json`；
- 匹配的 `room_type`；
- 布局引用的组件已按 `02b-godot-model-asset-import-standard` 导出并包装；
- 所有 AssetID 能解析到稳定 PackedScene。

执行：

```text
读取 room_layout.json
  -> 解析 base_layout + instance_overrides（或已展开的完整列表）
  -> 校验布局和组件版本
  -> 由 AssetID 注册表解析稳定 PackedScene
  -> 按 position / rotation / scale 实例化
  -> 初始化房间级挂点并保存正式 TSCN，后续在 Godot 编辑视觉摆位
  -> 运行具体房间验收
```

具体房间 Blender/JSON 差异布局只在初始化时作为输入；保存正式 TSCN 后，Godot 场景成为视觉摆放事实源，允许作者手动编辑。当前轻量 overrides 仅 `remove` 已实现；完整实例表与轻量覆盖是不同输入形态，不能声称所有操作均可自动解析。

运行时门不是可选项。新关卡优先由房间 `connection_ports` 提供稳定 `port_id`、房间局部 `position_m` 和局部朝外 `outward`；连接表按端口编号成对声明。房间旋转时端口位置、朝向和房型美术必须同转。装配器必须校验两端锚点世界坐标误差不超过 0.01m、朝外方向相反，不能再从房间包围盒中点猜门洞。旧关卡未声明显式端口时才允许继续使用历史 lane 推导。

当门槽把 `solid_wall` 提升并替换成另一件 `door_wall` prefab 时，**不得直接继承源实墙的实例旋转**：实例角度是针对源组件局部轴烘焙的，源墙与目标门墙的局部长轴可能相差 90°。最终门墙旋转必须由运行时已解析的墙面 `side` 与目标门墙轴向契约共同确定；验收必须断言门墙平面与 `RoomDoor3D` 门扇平面一致。组件归并也不得只按包络尺寸：门洞墙和实墙即使外包相同也必须按结构语义分开，禁止以门洞墙作为普通墙族的母版。

门验收必须同时证明 `RoomDoor3D/DoorPanel/ImportedDoorVisual` 存在且其后代至少有一个 `MeshInstance3D`；只验证 `RoomDoor3D` 节点数量和位置不能证明门扇可见。若 Blender 源包含 editor-only 门扇预览，运行时必须忽略它，由 `RoomDoor3D` 独占门扇视觉与动画。

### 分支 A 扩展到「整层固定关卡」（2026-09-20 区块00 先例）

当一个楼层由单一 Blender 布局源**整层接管**（不是补一间房）：

- 翻译器独立成 `RefCounted`（先例 `Block00MasterOfficeLayout3D.gd`）：只把布局源翻成运行时 `plan`，不碰场景树；布局源不可用或自检失败时返回空 → 回退生成器，**绝不静默换布局**。
- `build_plan_override(base_plan)` 必须**保留 base_plan 的 `layout_id`**（否则存档快照校验 mismatch），并**沿用原楼层的房间 id 键**（先例 `floor_01_entry/hub/main_02/exit`），否则存档 `room_progress` 错位。
- 摆位源的绝对平移常缺（只块内相对正确）⇒ 由「楼层锚点 + 门槽」反解（先例 `_resolve_planar_z_shift()`）。
- 运行时房间走**通用**授权壳体装配（`DungeonRoom3D._build_authored_layout_shell`）⇒ **不为某房新增专用拼装函数**。
- ⚠️ **接线点不止一处**：楼层规划注入、plan→record 字段透传、record→`room.configure(...)`。`room.configure(...)` 在项目里有**两处调用点**，**少补一处不报错但该房静默退化成白盒** ⇒ 先 grep 出所有调用点再改。
- ⚠️ **共墙与门实体唯一所有权**：一条连接边只能由一个端点生成门墙、门扇、碰撞和 `RoomDoor3D`；另一端必须删除该槽的重复共墙，并把同一个 `RoomDoor3D` 引用登记到自己的出口方向。禁止“两端各建一扇门再同步状态”，也禁止只隐藏第二块门板来掩盖重叠。端口 `target` 为空时必须保留普通实体封墙，不能留下镂空。
- ⚠️ **端口 Marker 契约**：正式房间静态场景应包含 `ConnectionPorts/Port_<ID>` Marker3D，局部 `+Z` 指向房外；验收必须覆盖编号唯一、端口随房间旋转、连接端重合、方向相反、每边恰好一个门实体、未连接端口有封墙。
- 授权楼层会使「生成器结构契约」类验收（网格 / 走廊计数 / 门墙归属）**设计性假红** ⇒ 加测试 seam 回落生成器（先例 `TowerDescent3D.force_standard_floor_plan_for_test`，默认 false 不影响运行时），授权楼层改由专用验收探针覆盖。

### 分支 B：尚无正式 TSCN，选择白盒初始化

判定条件：没有正式房间/变体 TSCN，也没有合格的初始化 `room_layout.json`，但存在：

- 具体房间白盒；
- 匹配房间种类组件的 catalog、GLB 和 PackedScene；
- 白盒中可推导的墙、地板、门洞、连接和尺寸。

执行：

```text
读取白盒
  -> 生成临时/正式布局记录
  -> 只实例化已导入的 Godot 组件
  -> 将文字需求/效果图作为视觉排序和装饰决策输入
  -> 保存生成的 room_layout.json（若用户允许固化）
  -> 运行具体房间验收
```

分支 B 可以初始化基本结构，但不应声称与 Blender 效果图完全一致。复杂构图交给 03，可直接在 Godot 编辑房间/变体；只有需要 Blender 参考布局时才选择 A 初始化，不强制回到 Blender。

## 02b 前置导入门禁

进入正式房间编辑或 A0/A/B 初始化装配前，核查全部目标组件的来源、源/运行版本、GLB 哈希、稳定 PackedScene 和验收状态。新组件、未导入组件或源版本更新时，必须先加载并执行 `02b-godot-model-asset-import-standard`，通过后才装配；不得因从 00 直接路由到 04 而跳过该阶段。

所有场景组件都须实际优化并另存独立优化文件，原始文件不动，GLB 只能从已保存且重开的优化文件导出。复用必须具备可追溯优化文件、实际优化记录、原始源不变证据、前后三角面统计和保真验收，并且源/优化/运行版本、哈希与稳定引用一致，才记录“02b 复用核查通过”、不重复优化与导出；缺任一证据即返回 02b。缺失源契约或美术未验收时停止并回到组件制作；组件重导不授权覆盖正式 TSCN 的实例摆位、增删、启用、灯光和自定义节点。

## Godot 资产来源

使用 `02b-godot-model-asset-import-standard`，按 catalog 自动逐组件处理：

```text
component_catalog.json
  -> 每个 component_id 的独立 Blender 组件包
  -> 每组件一个 GLB（或一个明确的组件导入单元）
  -> 稳定 components/<asset_id>/...
  -> 稳定 runtime/<asset_id>/...tscn
  -> AssetID 注册表
  -> component_instances / room_layout 重放
```

硬约束：

- **房间静态 TSCN 的 owner 只改顶层组件实例根**：把运行时组件转挂到房间场景后，只允许 `component_instance.owner = room_scene_root`；不得递归把 `ImportedModel`、Mesh、Collision 等 prefab 内部后代的 owner 改成房间根。递归改 owner 会把组件内部展开写进房间 TSCN，破坏 PackedScene 可编辑边界，并可能在场景退出时造成大规模 RID/ObjectDB 泄漏。验收须比较“正式 TSCN 组件实例根数 = 运行时对应组件数”（房间设备、分组和挂点另计），并确认组件根仍以 `instance=ExtResource(PackedScene)` 保存、内部后代不在房间文件中重复声明；
- catalog 声明数、独立导入单元数、PackedScene 可解析数必须相等；缺一件就整体失败，不能静默跳过；
- 一个组件可被 N 个实例复用；不得因实例数量重复导出 GLB；
- 运行时路径不携带版本号；版本只写在 source、manifest、PackedScene metadata、布局快照和场景账本；
- 不得直接加载裸 GLB，不得从房间 Blender 源导入整屋 GLB；
- 坐标转换只执行一次：布局生产阶段先将源世界变换转换为 `blender_room_local`（`inverse(ROOM_FRAME_world) @ source_instance_world_transform`），运行时再按显式契约执行 Blender 平面 XY / 垂直 Z → Godot 房间局部 XZ / 垂直 Y。`ROOM_FRAME` 的平面原点必须是模板 footprint 包围盒中心，垂直原点必须是几何实测走行面；历史字段 `rotation_y_deg` 在 Blender 端语义为绕 Z，转换后才成为 Godot 垂直轴旋转，禁止按字段名重复旋转、隐式居中或再次减去 bbox 中心。

组件账本路径必须通过：

```text
assets/registry/ledger_index.json
```

解析所属分账本；不得写死总账本或自行新建第二套台账。

## 房间输出

运行时装配不把 Blender 过程源、白盒源或整屋 GLB 复制到 Godot。过程源保持在：

```text
assets/art/environments/tower_zones/<block_id>/source/room_instances/<room_id>/v###/
```

运行时房间的登记、路由结果和验收文件保持在：

```text
assets/art/environments/tower_zones/<block_id>/runtime/room_instances/<room_id>/
```

每个具体房间的最终美术装配至少生成：

- 具体房间运行布局/装配 manifest；
- 正式房间/变体 TSCN 路径、房型 → 变体 → 房间关系及实际登记入口；
- 原初始化 `assembly_route` 可记录 `room_type_layout_replay`、`blender_layout_replay` 或 `whitebox_direct_assembly`；正式 Godot 编辑状态另作验收说明，不声称新增 route 枚举已获代码支持；
- 房间编号、房间种类、白模源、组件源、Godot PackedScene 引用；
- 实例数量、包络、门洞、碰撞责任和版本哈希；
- 运行时验收日志和至少一张游戏内或验收场景截图；
- 关卡调用登记。

建议目录：

```text
assets/art/environments/tower_zones/battle/runtime/room_instances/<room_id>/
├─ room_runtime_manifest.json
└─ acceptance/
```

## 房间自持设备：顶灯与墙面开关固化成静态 TSCN 节点

**触发**：主人说「把房间的灯 / 开关做到 tscn 里头去，作为可手动调整的组件」。
默认房间灯（`WastelandLight3D`）与墙面开关（`RoomLightSwitch3D`）由
`DungeonRoom3D._build_content()` 运行时实例化、落在 `RuntimeDetail` 下 ⇒ 场景文件里查不到、
美术无法手调。要让它们变成编辑器里可拖可改的节点，走下面这套。

### 落盘形态＝裸脚本节点，不是 prefab 实例

静态布局根（`ExpeditionRoomStaticLayout`）下 `parent="."` 直挂两个节点，**导出值内联写在房间 TSCN 里**：

```text
[node name="RoomCeilingLight" type="Node3D" parent="." unique_id=<随机唯一>]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, <x>, 9.28, <z>)
script = ExtResource("900_authored_light")      # res://src/world3d/WastelandLight3D.gd
light_color / energy / light_range / failing / flicker_seed / cast_shadow / fixture_style / light_enabled
metadata/authored_room_device = "ceiling_light"

[node name="RoomLightSwitch3D" type="Area3D" parent="." unique_id=<随机唯一>]
transform = Transform3D(...)
script = ExtResource("901_authored_switch")     # res://src/world3d/RoomLightSwitch3D.gd
metadata/authored_room_device = "light_switch"
```

根节点补 `metadata/authored_room_devices = true`。ext_resource 用可读 id
（`900_authored_light` / `901_authored_switch`）而不是 Godot 自动编号，便于人工核对。

现有迁移采用裸脚本节点，这是历史落盘形态，不是禁止 Prefab 实例覆写的通则。`prp_wasteland_light_root_top3d.tscn` / `prp_room_light_switch_root_top3d.tscn` 的房间实例可保存已暴露属性的覆写；实际编辑器可调字段须验证。不能声称调实例属性必须修改组件母版。

🔴 **灯节点必须写出自己的 `transform` 行**（2026-09-29 踩过）。灯块里 `transform` 紧跟在节点声明行之后、
`script` 之前；**漏掉它，灯就静默落到艺术根原点（y=0，贴地）**，而属性值（energy/range/seed）全对
⇒ 光看「数值都对」是发现不了的。核对时必须**单独断言节点级 `transform` 行**存在且等于真值，
不能只比对「property = value」那些行。同理开关块也必须有 `transform`。

🔴 **块必须插在场景树最前面**（2026-09-29 实证）。设备节点要落在**根 `metadata/*` 全部结束之后、
第一个 `[node …]` 之前** —— 即成为根的**第一、第二个子节点**。若按最早的做法追加到**文件末尾**，
它们就是第 100+ 个子节点，被整房组件压在场景树底下：主人打开场景默认滚到顶部 ⇒ **看不到**，
会直接来问「我怎么没看到灯和开关的组件？叫什么名字？」（实测 room_01 落在 853/867 行＝第 124/125 个子节点，
必现；room_02 同理第 107/108）。注入器已按此插入点实现，且发现设备块已在别处时会**原样摘出再重插**
（保留原 `unique_id` 与全部导出值，幂等，输出 `MOVED`）。

回答主人这个问题时的标准答案：**灯 = `RoomCeilingLight`（Node3D + `WastelandLight3D.gd`）；
开关 = `RoomLightSwitch3D`（Area3D + `RoomLightSwitch3D.gd`）**，都在静态布局根
`ExpeditionRoomStaticLayout` 的最上面两个。

### 运行时认领

`DungeonRoom3D._adopt_authored_room_devices()`，在 `_build_content()` 最前调用：

```gdscript
var authored_devices := _adopt_authored_room_devices()   # 静态根下有 WastelandLight3D 才 true
… elif authored_devices: pass                            # 只登记，不重建
```

- 探测＝按**节点类型**递归收集（`_collect_wasteland_lights` / `_collect_room_light_switches`），
  只认 `AuthoredLayoutArtRoot` / `SafeRoomArtRoot` 两个根名；`metadata/authored_room_devices` 只是标记、不被读取。
- 认领后 `_light_switch != null` ⇒ 原「自建 + `_add_runtime_detail_child()`」被 `if _light_switch == null:` 跳过。
- **blast radius 精确**：静态根下没有 `WastelandLight3D` 的房间逐字走老路径 ⇒ 逐批迁移安全。

### 首次无损迁移抄运行时值；正式 TSCN 编辑后保留作者值

| 值 | 公式 |
| --- | --- |
| `energy` | `theme.fixture_energy × (2.20 if size_class in [large, arena, floor] else 1.85)` |
| `light_range` | `max(theme.fixture_range × 1.72, min(房间短边) × 0.94)` |
| `y` | `TOWER_GEOMETRY.FLOOR_HEIGHT_M − 2.72` |
| 平面位置 | `_snap_planar_position_into_footprint(Vector3.ZERO)`（真砖格 ⇒ L 房不是 0,0） |
| `flicker_seed` | `room_seed` |
| 开关位置 | `_resolve_light_switch_position()`，真砖格外缘内缩 `SWITCH_WALL_INSET_M = 0.34` |

真值来源＝验收探针的 `DUMP` 行（`var_to_str(transform)` 输出可直接当 TSCN 文本）。

### 工具链

```text
1. 跑 probe_expedition_room_device_dump（遍历生成器 ROOM_IDS＝13 房，只打印不断言）
   → 拿每房 DUMPX 行的 art_local_tf
   ⚠️ 别抄 probe_expedition_room_authored_light_devices 的 light.transform 当源值：那是运行时口径，
      未迁移的房挂在 RuntimeDetail 下 ⇒ 那是 RuntimeDetail 局部坐标、不是艺术根局部。
2. 抄进 scripts/patch_expedition01_room_authored_devices.py 的 ROOMS 表（浮点尾数照抄、不修饰），
   并把同一批房名同步进 generate_expedition01_room_static_scenes.gd 的 AUTHORED_DEVICE_ROOMS 声明
3. python scripts/patch_expedition01_room_authored_devices.py [room_id …]   # 省略＝全部；幂等、行尾保真
   输出 PATCHED（新插入）/ MOVED（原在别处，原样搬到顶部）；插入点＝场景树最前
4. 复跑探针验收 + 相邻验收（verify_expedition_room_static_scenes / verify_expedition_room_type_component_replay）
5. 核对「只是插了一段、别的行一行没动」：⚠️ **别用 `difflib`** —— 这类文件里成百上千行 `[node …]` /
   `transform = Transform3D(…)` 形态几乎相同，difflib 会错误对齐，把一次纯块移动报成 1500+ 行差异
   （已实际踩过）。改用**「剥离新增行后 body 逐行比对 + 新增行多重集比对」**，并断言：
     · 设备节点＝根 `metadata/*` 之后的**前两个** `[node …]`（灯在前、开关在后）；
     · 每房新增正好 **27 行**（2 ext_resource + 1 根 meta + 空行&灯 18 + 空行&开关 6）；
       ⚠️ room_01/room_02 是 **26 行** —— 它们由更早一版注入器写就、少一行公式注释，走 MOVED 时原样保留；
     · 每房行尾与改前**逐字节一致**（远征01：`boss` 是 CRLF，其余 12 房 LF）；
     · 灯块里 `transform` 行在（见上一条）。
```

🔴 **不要为了加一间房就跑生成器**。`generate_expedition01_room_static_scenes.gd` 里的
`AUTHORED_DEVICE_ROOMS`（名单**单一真源**，探针直接读它；2026-09-29 已从 room_01/room_02 扩到
远征01 **全 13 房**）与 `SS_STATIC_ROOMS=<逗号分隔房名>` 子集开关虽然能自动产出设备节点，
但有两点不对付，别拿它当落地手段：

- 生成器走 `PackedScene.pack()` ⇒ 设备会按 **prefab 实例**形态写出（`instance=ExtResource(...)`，
  同现有组件节点那种写法），与磁盘上现行的**裸脚本节点**形态不是一套（两者运行时等价，
  但会让「设备块长什么样」出现两种写法）。生成器自己的注释就写着「搬过去的是组件母版实例本身」。
- 整份产物顺带丢 `[gd_scene] uid=`、重编全部 `ext_resource` id、把编辑器早先剥掉的组件元数据补回来
  —— 那是「静态 TSCN 全量重生成」这个独立待办，不属本路径。

⇒ 首次设备迁移可在审查差异、保留计划和授权后使用注入器；正式房间已有设备时直接在 Godot TSCN 调整，不以旧 ROOMS 表或运行公式覆盖作者值。注入器也须核查具体行为，不能因为“幂等”就假定会保护所有手改。生成器里的 `AUTHORED_DEVICE_ROOMS` 是当前迁移声明，不能被当成自动合并保护。

### 验收判据

`tests/verification/probe_expedition_room_authored_light_devices.tscn`（直跑约 20 s；
2026-09-29 全 13 房实测 `rooms=13 checks=91`，即每房 7 项断言）：

- `static_lights ≥ 1`、`static_switches ≥ 1`（设备真在静态根下）；
- 灯 / `central_light` / 开关三者均 `from_static = true`，`parent = AuthoredLayoutArtRoot`；
- `switch_controls_lights` 翻转成功（开关真能控这盏静态灯）。⚠️ **方向按房型而异**：
  `start`（STAIR_LOBBY）/ `boss`（BOSS）初始**亮** ⇒ 探针打印 `true→false`，其余 11 房 `false→true`。
  别把「必须 false→true」当判据。

成功标记 `EXPEDITION_ROOM_AUTHORED_LIGHT_DEVICES_OK`。

#### 探针「站位」的两个坑（2026-09-29 扩到 13 房时踩实）

设备迁移把开关从 `RuntimeDetail` 下搬到**艺术根**下，于是探针里**算玩家站位的坐标口径悄悄变了**。
room_01/room_02 因为艺术根恰为 identity 而一直没暴露；扩到 `start` / `boss` 后立刻现形：

1. **坐标系各归其位**。`switch.position` 现在是**艺术根局部**；而砖格 `_authored_tile_cells`
   是**房间局部**（来自 `authored_layout_instances` 的 `floor_tile` 槽位）。老代码
   `room.to_global(switch.position)` 把艺术根局部当房间局部用 —— 入口安全房的艺术根带 yaw −90°，
   同一个站位点直接偏出 **10.6m**（交互半径才 2.2m）⇒ `get_interaction_candidate()` 恒空。
   正解：`room.global_transform.affine_inverse() * switch.global_position` 先换回房间局部再比，
   最后 `room.to_global()` 出世界坐标。
2. **别把玩家塞进开关里**。砖格 clamp 出来的点可能与开关**重合**（BOSS 房实测 dist=0）：开关贴墙，
   重合点＝让玩家站在墙体/开关体内，物理把他挤出去，**归属甚至会掉到隔壁房**
   （实测 boss 的开关站位被判成 `owner=room_10`）。故最终点必须与开关保持 ≥ 玩家身位直径
   （`MIN_STAND_DISTANCE_M = PLAYER_BODY_RADIUS_M × 2 = 0.9m`）的平面距离，方向朝房心；
   无砖格可依（安全房 cells=0）时走同一条退化路径。

🔴 判断「是设备坏了还是探针站位算错了」的**快刀**：写个一次性诊断探针，对同一房并列试
`art_root.to_global(局部点)` / 世界直算 `switch.global_position + 朝房心 × {0.6, 0.9, 1.2}`，
各自真放玩家、刷归属、读 `get_interaction_candidate`。若世界直算全 `YES` ⇒ 设备与开关完好，
问题在探针。**别靠猜，也别为了让探针变绿而放宽断言**。

### 已知残留

- 灯泡外形（`CeilingMount`/`Fixture`/`Lens`/`LampLight`/`LightPool`）与开关的
  `SwitchPlate`/`Indicator`/`Lever`/`CollisionShape3D`/`InteractLabel` 仍由 `_build_fixture()` /
  `_build_visual()` 运行时建（自带 `get_node_or_null(...) != null → return` 守卫，不会建第二份）
  ⇒ **交互范围与提示文字目前仍不能在编辑器里调**。
- 改完必须让主人**重启场景/编辑器**再截图：Godot 不热重载 GDScript。

## 撤离房门禁

对于 `EXTRACTION_ROOM`：

- 默认尺寸必须为 30×30m，除非白模 manifest 明确变更并完成审批记录；
- 必须实例化一个 `slot_role=extraction_beacon` 的固定设施组件；
- 信标不得是拾取物，不得把撤离判定写入视觉组件；
- 运行时必须报告信标实例存在、位置在房间边界内、无重复实例；
- 玩法层已有撤离逻辑时只绑定既有接口，不重新实现。

## 严格失败条件

遇到以下任一情况立即失败，不用旧资产冒充新链路：

- 房间编号、房间种类或白模无法唯一解析；
- 组件缺 GLB、PackedScene、AssetID、包络或来源，或 catalog / 导入单元 / PackedScene 数量不守恒；
- Blender 源版本高于 Godot 已接入版本；
- 房型唯一组件数超过 50，或组件实例引用了计划/catalog 外的 ID；
- 布局包含房间自有共享 Mesh、整屋 GLB 或非法缩放；
- 默认布局与具体房间差异布局同时复制同一批实例，导致重复视觉/碰撞；
- Blender→Godot 坐标转换缺失、执行两次，或把历史 `rotation_y_deg` 错当 Blender Y 轴；
- JSON/Blender/白盒被用作覆盖正式 TSCN 的第二视觉事实源，或未经审查授权重生成正式房间；
- Godot 代码需要新增房间专用拼装函数；
- 撤离房缺失信标；
- 资产导入任务试图触碰玩法/规则类文件。
