# 房间种类组件拆解契约

## 组件来源

```text
概念图/白盒约束 -> 02 前置组件计划（唯一组件 <=50，同族常规 <=3、有状态轴 <=5）
  -> room_type_source_blend（组件母版 + 可选实例参考布局）
  -> component_source_blend
  -> component catalog / manifest
  -> GLB
  -> runtime PackedScene
```

组件源可以按房间种类独立存放，也可以把跨房间复用组件提升到 `common_components`。提升必须有唯一 AssetID；禁止两边各维护一份同几何组件。

## 组件包最小字段

```json
{
  "component_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
  "room_type": "COMMON_ROOM",
  "source_room_type_blend": "...",
  "component_source_blend": "...",
  "collection": "...",
  "root_object": "...",
  "bounds_size_m": [5.0, 0.3, 11.9],
  "origin_contract": "bottom_center",
  "front_axis": "-Z",
  "allowed_rotations_y_deg": [0, 90, 180, 270],
  "runtime_scene": "res://assets/art/.../runtime/...tscn",
  "collision_owner": "godot_wrapper",
  "palette_uv_layer": "PaletteUV",
  "asset_ledger": "resolved_by_ledger_index"
}
```

## 禁止事项

- 禁止把具体房间世界坐标写入组件源。
- 禁止把白盒参考、临时灯光、展示相机导出到组件 GLB。
- 禁止通过缩放修复组件接口。
- 禁止房间实例反向成为组件源。
- 禁止在 Godot 为每个房间生成一套组件几何/材质副本；允许房间/变体 TSCN 引用稳定组件 PackedScene 并保存实例摆位、增删、启用和灯光。
- 源几何材质归 Blender，组件碰撞挂点归 Prefab，正式布局归 Godot TSCN。JSON/Blender 清单仅初始化与追溯，不能自动回灌。
- 组件重导只更新组件资产、保留实例覆写；几何/接口变化先核查影响。现有静态生成器无自动合并保护，覆盖正式场景须差异、保留/回填计划及授权。
- `block_id` 兼容 `battle/expedition`；组件预算只计定义，不计重复实例。
