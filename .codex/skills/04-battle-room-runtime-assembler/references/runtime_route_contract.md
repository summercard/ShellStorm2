# Godot房间装配路由契约

## 正式场景优先

已有正式房间/变体 TSCN 时，直接在 Godot 编辑稳定组件实例位置/旋转、增删、启用和灯光，不重放旧清单覆盖。源几何材质归 Blender，组件碰撞挂点归 Prefab，正式布局归 TSCN；白盒仍约束原型尺寸、端口、连接和可走空间。

房型 → 房间变体 → 具体房间三层可由 Godot 场景/明确资源路径管理；固定房型不禁止作者变体，不强制每房 Blender 差异布局。以下 A0/A/B 仅用于无正式场景的初始化或隔离参考。

## 分支 A0：房型默认布局初始化

使用条件：

```text
component_plan.json / component_catalog.json / component_instances.json pass
room_layout.json references base_layout and has no overrides
all component PackedScenes resolve
source_version == runtime_version
```

初始化可记录 `assembly_route=room_type_layout_replay`；逐组件导入并重放后保存正式 TSCN，禁止整屋 GLB。路由记录不能变成持续回灌权限。

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
formal room/variant TSCN absent
room_layout.json absent or explicitly bypassed for initialization
whitebox exists
room type component set is complete
all component PackedScenes resolve
```

输出：`assembly_route=whitebox_direct_assembly`。

分支 B 先满足白盒结构，后续可通过 03 在 Godot 编辑复杂构图/变体，不强制转回 Blender。文字、需求和图片不能越权改变玩法空间；JSON/Blender 仅初始化与追溯。

## 三条共同门禁

- catalog 声明组件数 = 独立导入单元数 = 可解析 PackedScene 数；
- 房型唯一组件数 `<= 50`；同族常规 `<= 3`、有明确状态轴 `<= 5`；实例数量另计；
- Blender→Godot 坐标转换只执行一次；历史 `rotation_y_deg` 在 Blender 端表示绕 Z；
- 默认布局与差异布局不得重复实例化同一批对象；
- 禁止整屋 GLB、裸 GLB 运行时加载和房间专用组件替代品。

## 更新保护与实现限制

- 组件重导仅更新组件资产，保留房间实例覆写；几何、原点、包络、节点路径、碰撞/挂点接口变化先核查所有受影响房间。
- 当前静态生成器直接覆盖输出，没有自动合并保护；子集开关不保护被选房。正式房间禁止未审查全量生成；任何回填须备份、差异、保留/回填计划和授权。
- 当前 `room_03/04` 仍通过 `ROOM_INSTANCE_LAYOUT_SOURCES` 代码注册，轻量 JSON override 仅 `remove` 已实现。新增通用注册与其他 op 未完成；必要实现另获授权，不能在 Skill/美术任务中自动补代码。

## 隔离边界

实际资产任务授权范围内允许修改（`block_id` 取 `battle/expedition`；仅修订 Skill 时不修改下列项目文件）：

- `assets/art/environments/tower_zones/<block_id>/source/**`
- `assets/art/environments/tower_zones/<block_id>/components/**`
- `assets/art/environments/tower_zones/<block_id>/runtime/**`
- 已授权的视觉探针和验收场景；通用装配器/注册表缺口先报告，代码实现须独立授权
- 场景分账本中对应资产行

默认禁止修改：

- `src/map/FloorPlanGenerator.gd`
- 敌人、战斗、掉落、任务、结算和存档逻辑
- 门状态机、导航规则和房间拓扑算法
- 非场景资产域

如果关卡数据确实需要新增撤离房节点，应作为独立玩法/关卡数据任务执行；本美术链路只准备 `EXTRACTION_ROOM` 的白模、组件、布局和运行视觉装配接口。
