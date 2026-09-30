# 组件规划与实例清单字段速查

## `component_plan.json`

必填顶层字段：`schema`、`schema_version`、`block_id`、`source_room_type`、`component_budget`、`groups`、`validation`。

```json
{
  "component_budget": {"limit": 50, "planned": 28, "remaining": 22},
  "regular_max_variants_per_family": 3,
  "hard_max_variants_per_family": 5
}
```

每个 `groups[]` 至少包含：`component_id`、`slug`、`component_family`、`axis`、`merge_key`、`instance_count`、`serves_room_types`、`scope`。第 4–5 个同族变体要求族内每件都写同一语义的 `variant_axis` 以及各自的 `variant_value`、`variant_reason`。

## `component_instances.json`

每个初始化/追溯实例包含 `component_id`、`instance_id`、`position_m`、`rotation_y_deg`、`scale`、`source_object`。历史字段 `rotation_y_deg` 在 Blender 端表示绕 Z；必须由 `coordinate_contract` 显式映射到 Godot。`block_id` 兼容 `battle/expedition`。

正式房间布局属于 Godot TSCN，允许编辑实例摆位/增删/启用与灯光。清单不能自动回灌覆盖手改；组件重导只更新组件资产，保留实例覆写，几何/接口变化先核查影响。

## 门禁

- 唯一组件定义 `<= 50`，实例数不限；
- 无状态轴的同族 `<= 3`，有完整统一状态轴的同族 `<= 5`；
- 同一母版重复摆放必须共享 Collection/Mesh datablock；
- `component_plan`、catalog、独立组件包和实例清单的 ID 必须守恒；
- 初始化/隔离验收时 Blender 与 Godot 能用同一清单还原 bbox 与画面；正式编辑后按 TSCN 与批准差异验收，不强制匹配旧清单。禁止整屋 GLB，允许引用组件 Prefab 的房间/变体 TSCN。
