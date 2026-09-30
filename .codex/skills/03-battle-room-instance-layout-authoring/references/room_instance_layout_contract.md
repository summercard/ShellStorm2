# 具体房间布局契约

## 身份

```text
level_id + room_type -> 房间变体（Godot场景/明确资源路径） -> room_id + 正式TSCN
layout_version 仅在初始化/追溯清单使用
```

`room_id` 必须在同一 `level_id` 内唯一。

## 事实源

- 白模：尺寸、门洞、连接、可走面和清空区。
- 组件 catalog：组件身份、包络、原点、允许旋转、Godot运行资产。
- Blender：拥有源几何材质，可用组件实例作参考布局。
- 02 的 `component_instances.json` / 可选房间 Blender：仅供初始化与追溯，不自动覆盖正式手改，不要求每房差异源。
- 组件 Prefab：拥有稳定引用、组件碰撞和挂点。
- 正式 Godot TSCN：拥有房间模块实例摆位/增删/启用、房间级挂点及灯光，允许作者编辑；运行时仍使用既有玩法接口。
- 固定房型不禁止作者变体；变体通过 Godot 场景/明确路径管理，不声称已实现新注册器。`block_id` 兼容 `battle/expedition`。

## 继承与覆盖

```json
{
  "base_layout": ".../component_instances.json",
  "source_blend": null,
  "instance_overrides": []
}
```

- 选择清单初始化且默认布局适用时，可用 `instances=[]`、`instance_overrides=[]`；正式 TSCN 编辑不要求回写这些字段。
- 当前轻量 override 仅 `remove` 已实现，`room_03/04` 仍代码注册；`add/transform/enable` 可在 Godot 编辑，不是可提交给现有 JSON 解析器的操作。
- 覆盖解析后引用的唯一组件数不得超过房型 `component_budget.limit=50`。
- 新造型不属于布局覆盖，必须回到 02 更新组件计划和 catalog；保持 50/3/5 定义预算，实例数量另计。
- 组件重导只更新组件资产并保留实例覆写，几何/接口变化先做影响核查。现有静态生成器没有自动合并保护；正式房间禁止未审查全量生成，回填须备份、差异、保留/回填计划及授权。

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
