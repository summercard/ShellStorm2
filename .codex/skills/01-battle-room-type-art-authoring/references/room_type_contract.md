# 房间种类美术契约

## 稳定枚举

```text
SAFE_ROOM
COMMON_ROOM
BOSS_ROOM
EXTRACTION_ROOM
```

## 固定挂钩

所有阶段都保留：

```text
block_id
floor_range
design_scope
scene_design_docs
asset_ledger
room_type
```

## 房型、房间变体与具体房间分离

```text
room_type = COMMON_ROOM
room_id = main_02
```

`room_type` 决定组件计划与约束；房间变体可用 Godot 场景或明确资源路径管理；`room_id` 决定具体白模约束、正式 TSCN 与关卡调用。固定房型不禁止作者变体，不要求每房 Blender 差异布局；这些概念不声明新的通用注册功能已实现。

源几何材质归 Blender，组件碰撞挂点归稳定 Prefab，正式房间实例摆位/增删/启用/灯光归 Godot TSCN。Blender 可以摆参考实例，JSON/Blender 清单仅初始化与追溯，不自动回灌覆盖手改。原型白盒继续约束尺寸、连接与可走空间；`block_id` 按实际来源兼容 `battle/expedition`。

正式建模前执行 02 组件计划：唯一组件 ≤50，同族常规 ≤3、有明确状态轴 ≤5；不把实例数或布局变体数当组件定义数。组件重导保留房间覆写，几何/接口变化先做影响核查；现有生成器没有自动合并保护，正式房间覆盖必须有差异、保留/回填计划及授权。

## 局内关卡01目标房间集

```json
{
  "level_id": "battle_level01",
  "room_types": {
    "SAFE_ROOM": {"count": 2},
    "COMMON_ROOM": {"count": 14},
    "BOSS_ROOM": {"count": 1},
    "EXTRACTION_ROOM": {
      "count": 1,
      "dimensions_m": [30.0, 30.0],
      "required_components": ["extraction_beacon"]
    }
  }
}
```

这只是美术生产目标清单。要改变游戏实际房间数量、拓扑、房间类型枚举或撤离规则，必须另走玩法/关卡规则变更，不由本 Skill 自动改写。

## 撤离信标

撤离信标属于固定场景设施：

- 组件身份稳定且可单独替换；
- `pickup=false`；
- 视觉组件不实现激活、计时、撤离和结算；
- 运行时由已有玩法层绑定既有接口；
- 缺少信标时，撤离房美术装配失败。

## 资产状态

```text
room_type_source_created
components_decomposed
components_exported
godot_runtime_integrated
room_instance_layout_created
runtime_assembled
```

后一状态不能覆盖前一状态；每个状态需有路径、版本、SHA-256、验收命令和未执行项。
