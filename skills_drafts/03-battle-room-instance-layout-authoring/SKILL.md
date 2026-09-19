---
name: 03-battle-room-instance-layout-authoring
description: 当为通用房02、入口安全房、BOSS房01、撤离房01等具体房间编号制作 Blender 组件布局时使用。读取该房间白盒和对应房间种类组件源，只摆放共享组件实例而不生成新组件，并导出可由 Godot 重放的房间布局清单。
agent_created: true
metadata:
  display_name_zh: 03 战局具体房间布局制作
---

# 战局具体房间编号 Blender 布局制作

## 目标与边界

处理“哪个具体房间”的布局，不处理房间种类造型：

```text
具体房间白模 + 房间需求/效果图
  + 对应房间种类组件 Blender 源
  -> 具体房间布局 Blender 源
  -> room_layout.json
```

例如 `COMMON_ROOM / main_02`、`COMMON_ROOM / branch_03`、`EXTRACTION_ROOM / exit_01`。布局源只保存组件实例和房间级标记，不生成新墙、新地板、新门或房间专用组件。

不得修改玩法、房间拓扑、敌人、掉落、存档、门状态机、导航和关卡规则代码。

## 触发语句

- `组装通用房02的 Blender 房间源`
- `按白模拼装 main_02 房间`
- `用撤离房组件制作 exit_01 的 Blender 布局`
- `按照这个效果图调整具体通用房03`

## 输入解析

必须同时定位三类输入：

1. 具体房间白模：`source/art/whitebox/tower_zones/<level>/...`，包含房间编号、尺寸、门方向、连接目标和可走面。
2. 房间种类组件源：由 `02-battle-room-component-decomposer` 产出；不得拿另一种房间的组件源冒充。
3. 房间级需求：文字、效果图、设施要求、门连接、镜头和局部美术约束。

房间编号不能唯一解析时停止，列出候选；白模和组件源的 `room_type` 不匹配时停止。

## Blender 布局约束

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

信标的视觉位置、朝向和可选 `activation_socket` 由布局源记录；撤离判定、激活条件和结算仍由玩法层拥有。

## 输出布局契约

保存到：

```text
assets/art/environments/tower_zones/<block_id>/source/room_instances/<room_id>/v###/room_layout.json
```

最小结构：

```json
{
  "schema": "shellstorm2.battle.room_instance_layout",
  "schema_version": 1,
  "room_id": "main_02",
  "room_type": "COMMON_ROOM",
  "whitebox_source": "...",
  "component_source": "...",
  "source_blend": "...",
  "dimensions_m": [30.0, 25.0],
  "instances": [
    {
      "instance_id": "WALL_NORTH_01",
      "component_id": "...",
      "slot_role": "solid_wall",
      "position_m": [0.0, 0.0, 0.0],
      "rotation_y_deg": 180.0,
      "scale": [1.0, 1.0, 1.0],
      "enabled": true
    }
  ],
  "room_markers": [],
  "validation": {
    "room_owned_geometry": false,
    "non_unit_scale_count": 0,
    "missing_components": []
  }
}
```

坐标使用 Godot 运行坐标约定写入，Blender 原始坐标变换必须写入 `coordinate_contract`，不能由运行时猜。

## 验收

- 白模尺寸、门洞、连接和边界一致。
- 所有组件来自匹配的组件源和 catalog。
- 组件实例数量、位置、旋转、包络可重建。
- 无共享 Mesh 本地副本、无房间专用 GLB/PackedScene。
- 无非单位缩放、非法角度、穿地、越界、门洞侵入和重复碰撞声明。
- 通过后将布局交给 `04-battle-room-runtime-assembler`；不要直接把 Blender 房间整屋导入 Godot。
