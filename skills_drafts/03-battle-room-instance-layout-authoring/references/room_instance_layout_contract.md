# 具体房间布局契约

## 身份

```text
level_id + room_id + room_type + layout_version
```

`room_id` 必须在同一 `level_id` 内唯一。

## 事实源

- 白模：尺寸、门洞、连接、可走面和清空区。
- 组件 catalog：组件身份、包络、原点、允许旋转、Godot运行资产。
- Blender 房间布局：视觉组件实例位置。
- Godot：只重放视觉布局并添加玩法节点；不得手工维护第二套视觉坐标。

## 实例字段

```json
{
  "instance_id": "WALL_NORTH_01",
  "component_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
  "slot_role": "solid_wall",
  "position_m": [0.0, 0.0, 0.0],
  "rotation_y_deg": 180.0,
  "scale": [1.0, 1.0, 1.0],
  "enabled": true
}
```

## 撤离房

`EXTRACTION_ROOM` 的布局校验必须满足：

```text
dimensions_m = [30.0, 30.0]
count(slot_role=extraction_beacon) = 1
room_owned_geometry = false
non_unit_scale_count = 0
```
