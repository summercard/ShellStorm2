# Godot 房间组件重放字段速查

## 装配路由

- 已有正式 TSCN：优先在 Godot 编辑房间/变体，引用稳定组件 Prefab；不新增未经实现的 route 枚举。
- `room_type_layout_replay`：无正式场景时用 02 的房型实例清单初始化。
- `blender_layout_replay`：用默认布局与实际受支持的覆盖/完整清单初始化。
- `whitebox_direct_assembly`：无正式 TSCN、无合格初始化清单时按白盒装配，只保证基本结构。

房型 → 房间变体 → 具体房间三层可通过 Godot 场景/明确资源路径管理；固定房型不禁止作者变体，不强制每房 Blender 差异布局。`block_id` 兼容 `battle/expedition`。

## 组件解析

每个 `component_id` 必须经正式 catalog/AssetID 注册表解析到稳定 PackedScene。要求：

```text
catalog 声明数 = 独立导入单元数 = 可解析 PackedScene 数
```

一个组件可实例化多次，但只能导入一份组件资产。禁止整屋 GLB、裸 GLB 运行时加载和房间专用替代组件。

## 运行时验收

记录正式 TSCN 路径、房型/变体/房间关系、初始化来源、批准作者差异、组件版本、实例数、唯一组件数、bbox、门洞、碰撞责任和截图。源几何材质归 Blender，组件碰撞挂点归 Prefab，正式布局与灯光归 TSCN。初始化坐标只转换一次；Godot 手改后不再重放旧清单，正式场景与运行实例一致即可。

组件预算保持 50/3/5，实例数量另计。组件重导仅更新组件资产、保留实例覆写；几何/接口变化须影响核查。当前静态生成器没有自动合并保护，正式场景覆盖须备份、差异、保留/回填计划及授权；禁止未审查全量生成。

当前 `room_03/04` 仍代码注册，轻量 override 仅 `remove` 已实现。Godot 允许增删/变换/启用，不等于 JSON 已支持 add/transform/enable，也不代表通用注册功能完成。
