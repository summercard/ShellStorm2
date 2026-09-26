# Godot房间装配路由契约

## 分支 A0：房型默认布局重放

使用条件：

```text
component_plan.json / component_catalog.json / component_instances.json pass
room_layout.json references base_layout and has no overrides
all component PackedScenes resolve
source_version == runtime_version
```

输出：`assembly_route=room_type_layout_replay`。这是标准路径；逐组件导入并重放，禁止整屋 GLB。

## 分支 A：具体房间差异布局重放

使用条件：

```text
room_layout.json exists and has instance_overrides or an authored differential layout
base_layout + overrides validation passes
all component PackedScenes resolve
source_version == runtime_version
```

输出：`assembly_route=blender_layout_replay`。

## 分支 B：白盒直装

使用条件：

```text
room_layout.json absent or explicitly bypassed
whitebox exists
room type component set is complete
all component PackedScenes resolve
```

输出：`assembly_route=whitebox_direct_assembly`。

分支 B 先满足白盒结构；文字、需求和图片只用于组件选择和构图，不得改变玩法空间。复杂效果应回到 02 完成房型默认组件布局，或回到 03 制作具体房间差异布局，再切换到 A0/A。

## 三条共同门禁

- catalog 声明组件数 = 独立导入单元数 = 可解析 PackedScene 数；
- 房型唯一组件数 `<= 50`；实例数量不限；
- Blender→Godot 坐标转换只执行一次；历史 `rotation_y_deg` 在 Blender 端表示绕 Z；
- 默认布局与差异布局不得重复实例化同一批对象；
- 禁止整屋 GLB、裸 GLB 运行时加载和房间专用组件替代品。

## 隔离边界

允许修改：

- `assets/art/environments/tower_zones/battle/source/**`
- `assets/art/environments/tower_zones/battle/components/**`
- `assets/art/environments/tower_zones/battle/runtime/**`
- 纯通用布局装配器、AssetID注册表、视觉探针和验收场景
- 场景分账本中对应资产行

默认禁止修改：

- `src/map/FloorPlanGenerator.gd`
- 敌人、战斗、掉落、任务、结算和存档逻辑
- 门状态机、导航规则和房间拓扑算法
- 非场景资产域

如果关卡数据确实需要新增撤离房节点，应作为独立玩法/关卡数据任务执行；本美术链路只准备 `EXTRACTION_ROOM` 的白模、组件、布局和运行视觉装配接口。
