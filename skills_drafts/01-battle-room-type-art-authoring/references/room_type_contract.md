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

## 房间种类与实例分离

```text
room_type = COMMON_ROOM
room_id = main_02
```

`room_type` 决定组件来源；`room_id` 决定具体白模、具体布局和关卡调用。房间种类源不能写死具体房间编号，房间实例源不能反向维护组件几何。

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
