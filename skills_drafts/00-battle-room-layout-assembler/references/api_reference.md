# 战局房间布局契约

## 1. 单一事实源

- 组件几何事实源：战局 `common_components/v###` 中已通过美术与导入门禁的最高正式版本。
- 组件运行事实源：Godot 稳定 PackedScene 路径及其 metadata。
- 正式房间视觉布局事实源：Godot 房间/变体 TSCN，允许模块实例摆位/增删/启用和灯光编辑；Blender/JSON 实例清单仅初始化与追溯，不能自动回灌。
- 组件碰撞和组件挂点事实源：稳定组件 Prefab；源几何材质归 Blender。房型 → 房间变体 → 具体房间三层可用 Godot 场景或明确资源路径管理，固定房型不禁止作者变体。
- 楼层拓扑事实源：`FloorPlanGenerator` / `unit_plan.json` 的房间位置、尺寸、连接关系。

`room_layout.json` 只描述房间内部组件实例，不重复保存 Mesh，不负责决定房间在楼层中的世界坐标。

## 2. 坐标约定

ShellStorm2 场景源采用 Blender Z-up。Godot 使用 Y-up。布局文件推荐直接保存 Godot 局部坐标，字段明确带 `godot_` 前缀；若保存 Blender 坐标，必须同时声明 `coordinate_system`，由转换器统一转换，禁止调用方猜测。

默认转换：

```text
Blender (x, y, z) -> Godot (x, z, -y)
Blender rotation_z -> Godot rotation_y（符号按已验收转换器固化）
```

布局实例相对房间局部原点。房间整体世界变换由 `TowerDescent3D` / `DungeonRoom3D` 负责。

## 3. 推荐 Schema

```json
{
  "schema": "shellstorm2.battle.room_layout",
  "schema_version": 1,
  "room_id": "battle_main_room_02",
  "room_asset_id": "ENV-BATTLE-L01-MAIN-02",
  "block_id": "battle",
  "layout_version": "v004",
  "coordinate_system": "godot-y-up-room-local",
  "source_blend": "assets/art/environments/tower_zones/battle/source/main_room_02/v004/main_room_02_source_v004.blend",
  "source_blend_sha256": "...",
  "whitebox_source": "source/art/whitebox/tower_zones/battle_level01/v001/data/unit_plan.json",
  "component_library": {
    "source_blend": "assets/art/environments/tower_zones/battle/source/common_components/v006/战局区块_通用组件库_v006.blend",
    "catalog": "assets/art/environments/tower_zones/battle/source/common_components/v006/component_catalog.json",
    "catalog_sha256": "..."
  },
  "room_bounds_m": {
    "size": [30.0, 12.0, 25.0],
    "walk_plane_y": 0.0,
    "grid_m": 5.0
  },
  "instances": [
    {
      "instance_id": "WALL_NORTH_01",
      "component_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
      "runtime_scene": "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn",
      "slot_role": "solid_wall",
      "transform": {
        "position_m": [-10.0, 0.0, -12.35],
        "rotation_y_deg": 180.0,
        "scale": [1.0, 1.0, 1.0]
      },
      "enabled": true,
      "collision_policy": "component_default",
      "metadata": {}
    }
  ],
  "connections": [
    {
      "connection_id": "DOOR_EAST_MAIN",
      "direction": "east",
      "target_room_id": "battle_corridor_02",
      "door_instance_id": "DOOR_EAST_01"
    }
  ],
  "validation": {
    "room_owned_geometry": false,
    "non_unit_scale_count": 0,
    "illegal_rotation_count": 0,
    "missing_component_count": 0,
    "outside_room_bounds_count": 0,
    "component_instance_count": 1
  }
}
```

## 4. 必填字段

### 顶层

| 字段 | 规则 |
|---|---|
| `schema` | 固定为 `shellstorm2.battle.room_layout` |
| `schema_version` | 当前为整数 `1` |
| `room_id` | 项目内唯一稳定 ID |
| `block_id` | 按真实区块使用 `battle` 或 `expedition`；历史 schema 名不限制区块 |
| `layout_version` | `vNNN`，只表示布局版本 |
| `coordinate_system` | 必须明确，禁止省略 |
| `source_blend` | 可选初始化参考源，无 Blender 差异布局时可为 null；正式布局使用已登记 TSCN 路径 |
| `whitebox_source` | 房间尺寸和门连接来源 |
| `component_library` | 必须包含 catalog 来源与版本/哈希 |
| `instances` | 组件实例数组；允许空，但不能缺字段 |
| `connections` | 房间接口数组；允许空 |
| `validation` | 导出时的静态门禁摘要 |

### 实例

| 字段 | 规则 |
|---|---|
| `instance_id` | 房间内唯一；稳定且可用于门状态/存档 |
| `component_id` | 共享组件 AssetID；禁止用 Blender 对象名代替 |
| `runtime_scene` | 稳定 `res://` PackedScene 路径，不带版本号 |
| `slot_role` | `solid_wall/door_wall/door/floor/ceiling/stair/facility/decor/...` |
| `transform.position_m` | 房间局部坐标 |
| `transform.rotation_y_deg` | 默认 0/90/180/270 |
| `transform.scale` | 默认必须 `[1,1,1]` |
| `enabled` | 布尔值 |
| `collision_policy` | 默认 `component_default`，覆盖需登记原因 |

## 5. 允许的房间内容

默认允许：

- 共享结构组件；
- 共享固定设施；
- 房间级空节点、门连接和玩法挂点；
- 运行时生成的敌人/掉落/交互逻辑引用。

默认禁止：

- 复制进房间的共享 Mesh；
- 房间专用墙、地板、门 GLB；
- 将整个房间焊成单一 GLB；
- 把摆放位置写回组件 PackedScene；
- 为一个房间在 `DungeonRoom3D.gd` 增加整套硬编码槽位数组；
- 用缩放适配非标准尺寸；
- 用房间布局承担楼层世界位置。

## 6. 例外组件

房间需要独特美术时，执行：

```text
独特对象进入共享/房间族组件生产流程
-> 获得独立 AssetID
-> 通过 Blender 资产验收
-> 导出稳定 GLB / PackedScene
-> 登记 catalog
-> 房间布局引用该 AssetID
```

即使只在一个房间出现，也必须先成为可独立验证的组件；不能藏在房间 Blender 内作为未登记几何。

## 7. 版本语义

- `component source version`：组件几何源版本。
- `runtime asset version`：PackedScene metadata 中当前已接入版本。
- `layout_version`：组件实例位置和房间连接版本。
- `room gameplay version`：房间玩法逻辑版本，可与布局版本不同。

组件重导只更新组件资产并保留正式房间实例覆写；几何、包络、原点、节点路径、碰撞/挂点接口变化须核查所有受影响 TSCN 与运行结果，不直接重放覆盖。现有静态生成器不具自动合并保护；正式房间禁止未审查全量生成，回填须先备份、输出差异、提出保留/回填计划并取得授权。

当前 `room_03/04` 仍在代码中注册，轻量 override 仅支持 `remove`；通用资源自动注册和 add/transform/enable JSON 解析不是已完成能力。

## 8. 最低验收指标

```text
missing_component_count = 0
room_owned_geometry = false
non_unit_scale_count = 0
illegal_rotation_count = 0
outside_room_bounds_count = 0
初始化验收：Blender参考实例数 = JSON实例数 = 隔离Godot实例数
正式编辑后：TSCN组件实例与运行结果一致，批准差异保留；不强制等于旧JSON
房间专用共享组件数 = 0
组件Stable PackedScene加载失败数 = 0
```

结构验证不能代替真实画面验收。涉及灯光、材质、遮挡和构图时，必须运行非 headless 视觉验收。
