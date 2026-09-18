# Godot房间装配路由契约

## 分支 A：Blender布局重放

使用条件：

```text
room_layout.json exists
layout validation passes
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

分支 B 先满足白盒结构；文字、需求和图片只用于组件选择和构图，不得改变玩法空间。复杂效果应回到 Blender 生成布局后切换到分支 A。

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
