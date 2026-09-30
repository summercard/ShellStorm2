---
name: 03-battle-room-instance-layout-authoring
description: 当制作或调整房间变体、具体房间布局时使用。正式布局在 Godot TSCN 中编辑稳定组件实例；Blender/JSON 仅可选初始化与追溯，不强制每房差异源，不生成新组件，也不自动覆盖正式手改。
agent_created: true
metadata:
  display_name_zh: 03 战局具体房间布局制作
---

# 战局房间变体与具体房间布局制作

## 目标与边界

处理“哪个具体房间”的布局，不处理房间种类造型：

```text
房型（组件计划与白盒约束）
  -> 房间变体（Godot 场景或明确资源路径，可复用）
  -> 具体房间（已登记的正式 TSCN）
  -> 在 Godot 编辑稳定组件实例摆位/增删/启用/灯光
可选初始化输入：component_instances.json / room_layout.json / Blender 组件实例参考布局
```

例如 `COMMON_ROOM / main_02`、`COMMON_ROOM / branch_03`、`EXTRACTION_ROOM / exit_01`。布局源只保存组件实例和房间级标记，不生成新墙、新地板、新门或房间专用组件。

**02 的 `component_instances.json` 是可选初始化与追溯基线，不是正式房间的持续事实源。** 有正式 TSCN 就在 Godot 编辑；无正式 TSCN 时可复用房型/变体场景或按清单初始化。布局不同也不强制创建 Blender 差异文件；Blender 允许用组件实例作参考布局。源几何材质归 Blender，组件碰撞与组件挂点归 Prefab，房间布局和房间级灯光参数归正式 TSCN。

固定房型不等于禁止作者变体。变体可以用 Godot 场景或明确资源路径管理，继承/组合关系必须可追溯；不假定存在新的通用注册功能。`block_id` 依实际输入取 `battle` 或 `expedition`。

不得修改玩法、房间拓扑、敌人、掉落、存档、门状态机、导航和关卡规则代码。

## 触发语句

- `组装通用房02的 Blender 房间源`
- `按白模拼装 main_02 房间`
- `用撤离房组件制作 exit_01 的 Blender 布局`
- `按照这个效果图调整具体通用房03`

## 输入解析

先定位已登记正式 TSCN、房间变体资源及组件引用；没有正式场景时才选择初始化来源。核查以下约束/可选来源：

1. 具体房间白模：`source/art/whitebox/tower_zones/<level>/...`，包含房间编号、尺寸、门方向、连接目标和可走面。
2. 房间种类组件源（`component_catalog.json`）：由 `02-battle-room-component-decomposer` 产出；不得拿另一种房间的组件源冒充。
3. **组件计划与可选实例清单**（`component_plan.json` / `component_instances.json`）：同由 02 产出。计划约束组件预算；实例清单记录房型参考摆放，仅作初始化起点和追溯。正式房间与其不同不要求回写 JSON，更不得以其覆盖正式 TSCN；新造型须回到 02 规划，不能在布局任务中临时造组件。
   🔴 实例的 `rotation_y_deg` **语义是绕 Blender Z 轴**（世界垂直轴；房间平面为 XY）；字段名是历史命名，源自 v005 的 `allowed_rotations_blender_z_deg`。摆位时写入 `rotation_euler.z`，**写成 `.y` 会让墙体直接躺倒**。摆放完成后必须过包围盒判据：拼装总 bbox 等于房间边界（含墙厚）、越界实例数为 0。
4. 房间级需求：文字、效果图、设施要求、门连接、镜头和局部美术约束。

房间编号不能唯一解析时停止，列出候选；白模和组件源的 `room_type` 不匹配时停止。

## 默认继承与差异布局

- **已有正式 TSCN**：以正式场景为布局真源，直接调整模块实例及房间灯光；保留组件 PackedScene 边界，不展开/复制内部 Mesh、碰撞和挂点。
- **尚未初始化**：可复用房型/变体场景，或用 `base_layout`/白盒初始化，再将正式场景保存到稳定资源路径；不要求每房另存 Blender。
- **需要 Blender 参考**：只用 catalog 内组件实例表达构图，可导出完整初始清单；不得自动回灌已手改的正式场景。
- **轻量 JSON 覆盖的实现限制**：当前 `FloorPlanGenerator` 仅支持 `remove`，`room_03/04` 仍在 `ROOM_INSTANCE_LAYOUT_SOURCES` 中代码注册。`add/transform/enable` 是允许的 Godot 编辑操作，不是已实现的 JSON op；不得输出这些 op 并宣称运行时支持。新增通用解析/注册需独立代码授权。
- 组件重导只更新组件资产并保留实例覆写；几何/接口变化先列受影响场景。现有静态生成器没有自动合并保护，任何覆盖须先备份、展示差异、提出保留/回填计划并取得授权，禁止未审查全量生成。
- 若需求新增造型而 catalog 中没有，停止并回到 02 更新组件计划；03 不得临时建模。

## 可选 Blender 参考布局约束

1. 使用 Library Link 或 Collection Instance；最终生产文件不得使用 Append 复制共享组件网格。
2. 只允许新增实例、位置、旋转、启用状态、布局标记和展示相机；不允许修改组件几何、材质或组件根原点。
3. 默认 `scale=[1,1,1]`；墙、门、地砖、楼梯等建筑模块默认只允许 `0/90/180/270` 度。
4. 房间尺寸通过组件数量和布局表达，不通过拉伸 5m 组件。
5. 布局源可包含白模参考和展示相机，但导出的 `room_layout.json` 只能包含运行组件和明确的房间级挂点。
6. 具体房间可有房间专属摆位，但不能产生房间专属组件资产。
7. 读取白模对象变换必须使用 `matrix_world`；禁止直接把 `object.location` 当世界/房间局部坐标，否则父级或集合变换会静默丢失。
8. Library Link 只加载 Collection datablock，禁止再把被链接的组件集合本体挂到 `scene.collection.children`；房间场景根只能看见 `ROOM_LAYOUT_INSTANCES` 的 Collection Instance，不能同时显示组件库散件。
9. 门墙实例根点必须来自完整5m门槽的 `wall_slot_center_m` 与墙边界根平面，禁止使用左/右门柱原点（典型偏差 `±1.8m`）或门楣原点（典型高度 `2.8m`）。
10. 房间尺寸是逻辑边界；墙组件根点落在 `±width/2`、`±depth/2` 的5m网格边界。0.3m墙厚属于视觉包络，允许外包络比逻辑尺寸多0.3m；不得为追求视觉包络等于房间尺寸而把根点内缩0.15m。
11. 门槽必须复用游戏关卡的5m lane规则：奇数段墙可取0m中心槽；偶数段墙没有0m槽，取与运行时相同的最近合法中心（如30m墙取`-2.5m`，不是`0m`）。布局 `ports[].offset_m`、门墙实例和白模 `wall_slot_center_m` 必须一致。
12. 组件 `front_axis=-Z` 时，南北墙必须让展示面朝房内：Blender +Y 北墙使用 180°，-Y 南墙使用 0°；东墙 90°、西墙 -90°。门墙视觉实例、门扇/RoomDoor3D 旋转必须使用同一方向表，禁止只旋转门墙而不旋转门扇。
13. 白盒若只表达结构槽位，房间布局脚本必须从房间级需求/参考图补入已验收共享设施实例（如 `west_desk`、`island_00`），并记录到 `slot_role=facility`；不能因白盒没有设施对象而把正式房间做成空房。
14. 在链接任何共享组件前，必须逐 Collection 断言 `instance_offset=(0,0,0)`；该偏移会在 Collection Instance 阶段额外作用，不能由 ROOT/Mesh 坐标归零替代。至少对普通墙、门墙、门扇做同族差异检查，禁止只抽查普通墙后推断门组件正确。
15. 门扇的运行时所有者是 `RoomDoor3D` 时，Blender 房间源必须在同一门槽放置 `door_5m` 的 editor-only 预览实例以供肉眼验收，但 `room_layout.json` 不得序列化该预览；运行时只由 `RoomDoor3D` 生成一份可动画门扇，避免 Blender 无门可看或 Godot 重复门扇。

## 撤离房实例规则

`EXTRACTION_ROOM` 默认尺寸为 30×30m。每个撤离房布局必须存在且只存在一个主撤离信标实例：

```text
component_id: ...EXTRACTION-BEACON...
slot_role: extraction_beacon
required: true
pickup: false
```

信标的视觉位置、朝向由正式 TSCN 记录，可选 `activation_socket` 组件接口由 Prefab 拥有；Blender/JSON 仅记录初始化参考。撤离判定、激活条件和结算仍由玩法层拥有。

## 输出布局契约

正式交付是已登记的房间/变体 Godot TSCN，保留稳定组件引用。以下 JSON 仅适用于选择清单初始化/追溯的路径，不强制为每次 Godot 编辑回写；示例 `block_id=battle` 可按实际来源为 `expedition`。

可选初始化清单保存到：

```text
assets/art/environments/tower_zones/<block_id>/source/room_instances/<room_id>/v###/room_layout.json
```

最小结构：

```json
{
  "schema": "shellstorm2.battle.room_instance_layout",
  "schema_version": 1,
  "block_id": "battle",
  "room_id": "main_02",
  "room_type": "COMMON_ROOM",
  "whitebox_source": "...",
  "component_source": "...",
  "base_layout": ".../component_instances.json",
  "source_blend": null,
  "instance_overrides": [],
  "component_budget_limit": 50,
  "dimensions_m": [30.0, 25.0],
  "instances": [],
  "room_markers": [],
  "validation": {
    "room_owned_geometry": false,
    "non_unit_scale_count": 0,
    "missing_components": []
  }
}
```

坐标使用 Godot 运行坐标约定写入；若布局源来自 Blender，必须先按 `room_local_transform = inverse(ROOM_FRAME_world) @ source_instance_world_transform` 转换，其中 `ROOM_FRAME` 的平面原点固定为模板 footprint 包围盒中心、垂直原点固定为几何实测走行面。`coordinate_contract` 必须记录 `source_space`、`origin_mode`、`source_bounds_xy_m`、`walk_plane_z_m` 和映射公式，不能由运行时猜，也不能把 `source_world_origin_m` 直接作为房间局部坐标。

## 验收

- 白模尺寸、门洞、连接和边界一致。
- 所有组件来自匹配的组件源和 catalog，解析后的唯一组件数不得突破房型计划的 50 个预算。
- 正式 TSCN 与运行实例、灯光、启用状态和批准差异一致；仅初始化验收要求清单重放一致，不把合法手改判成漂移。
- 使用 JSON 时只提交现有解析器实际支持的覆盖；可选 Blender 参考只含 Collection Instance，无共享 Mesh 本地副本、无整屋 GLB；允许引用组件 Prefab 的房间/变体 PackedScene。
- 无非单位缩放、非法角度、穿地、越界、门洞侵入和重复碰撞声明。
- 通过后将布局交给 `04-battle-room-runtime-assembler`；不要直接把 Blender 房间整屋导入 Godot。
