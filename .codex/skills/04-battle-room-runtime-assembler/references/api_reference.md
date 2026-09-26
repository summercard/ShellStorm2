# Godot 房间组件重放字段速查

## 装配路由

- `room_type_layout_replay`：直接重放 02 的房型默认实例清单；标准路径。
- `blender_layout_replay`：解析默认布局与 03 的具体房间覆盖后重放。
- `whitebox_direct_assembly`：没有合格布局时按白盒装配，只保证基本结构。

## 组件解析

每个 `component_id` 必须经正式 catalog/AssetID 注册表解析到稳定 PackedScene。要求：

```text
catalog 声明数 = 独立导入单元数 = 可解析 PackedScene 数
```

一个组件可实例化多次，但只能导入一份组件资产。禁止整屋 GLB、裸 GLB 运行时加载和房间专用替代组件。

## 运行时验收

记录装配路由、基础布局、覆盖列表、组件版本、实例数、唯一组件数、bbox、门洞、碰撞责任和截图。坐标转换只执行一次；默认布局与差异布局不得重复实例化同一对象。
