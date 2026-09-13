# WORLD-BLOCKS 四区块场景树与资产目录整理

日期：2026-09-13  
工程版本：0.1.0（未修改 `project.godot`）  
功能状态：WORLD-BLOCKS r1 已接入

## 交付结果

- `TowerDescent3D` 的主要浏览树统一为 `Blocks/Rooftop`、`Blocks/Base`、`Blocks/Battle`、`Blocks/Stairs`。
- 楼层使用 `Floor_100` 一类短名；房间直接使用稳定 `room_id`；首两段楼梯固定为 `Stair_A`、`Stair_B`；水平走廊和独立电梯分别使用 `Corridor_序号`、`Elevator_楼层F`。
- 活跃整区 PackedScene 迁入 `assets/art/environments/tower_zones/<block>/runtime/`；原 AssetID 和 GLB 保持不变，不执行重新导入。
- 新增[关卡区块设计](../05.1_关卡区块设计.md)，集中维护区块范围、命名、运行路径和 Blender 对照。
- 主资产台账和 `3D-场景通用` 表已同步天台、基地、战斗母版和两段楼梯的运行路径、源文件、短名及哈希。

## Blender 源文件处理

- 天台 v021 与塔楼母版 v011 只补充 Godot 区块、运行路径、命名契约和 `no_reimport` 元数据；未改中文集合、几何、材质或导出文件。
- 基地 v026 由 Blender 4.3.3 写入，当前自动化 Blender 为 4.2。试开后立即从 `.blend1` 恢复，恢复文件 SHA-256 为 `0eec20ede096ce97180b185d18a7d0b06b54d2b100ee1423380e62e09ca47690`；正式源文件未被低版本重存。Godot 对照改记于同目录 `base_facility_runtime_layout_hq_v026.godot.json`。

## 验收

| 验收项 | 退出码 | 结果 |
| --- | ---: | --- |
| `verify_tower_level_blocks` | 0 | 输出 `TOWER_LEVEL_BLOCKS_OK`；四区块、楼层/房间归属、短名和楼梯 AssetID 均通过。 |
| `verify_tower_grid_component_alignment` | 0 | 输出 `TOWER_GRID_COMPONENT_ALIGNMENT_OK`。 |
| `verify_base99_structural_asset_integration` | 0 | 输出 `BASE99_STRUCTURAL_ASSET_INTEGRATION_OK`。 |
| `python3 scripts/check_documentation_contracts.py` | 0 | 59 份文档、340 条链接、33 个功能、45 个测试引用通过。 |
| `python3 scripts/check_asset_registry.py --scope structure` | 0 | 418 项资产结构通过。 |
| `python3 scripts/check_asset_registry.py` | 1 | 本次涉及的区块资产无漂移；全表仍有 206 项历史 SHA 漂移，未批量接受。 |

三个场景测试均无预期故障、非预期脚本错误或资源退出警告。

## 未执行项

- 按用户要求未重新导入 GLB，也未改 Blender 内中文命名。
- 未做编辑器人工游玩或真实渲染截图；本次改动只整理场景树、路径、名字和追溯关系。
