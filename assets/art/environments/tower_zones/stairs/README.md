# Stairs

- 运行时节点：`Blocks/Stairs`
- `Stair_A`：`ENV-TOWER-STAIRWELL-ROOFTOP-12M`，100F→99F
- `Stair_B`：`ENV-TOWER-STAIRWELL-GENERIC-12M`，99F→98F
- 阶段：正式 Blender 源已完成；Godot 运行时仍沿用现有 GLB，未重新导入
- 反推白盒数据：`source/art/whitebox/tower_zones/stairs/v012/data/whitebox_stairs_v012.json`
- 正式 Blender：`assets/art/environments/tower_descent_3d/source/stairs_12m/env_tower_stairs_12m_source_v001.blend`
- 资产包清单：`assets/art/environments/tower_descent_3d/source/stairs_12m/asset_manifest_v001.json`
- 回滚白盒：`source/art/whitebox/tower_zones/stairs/v011/blender/whitebox_tower_battle_stairs_v011.blend`
- 效果图：`source/art/whitebox/tower_zones/stairs/v011/renders/`
- GLB：继续位于 `assets/art/environments/tower_descent_3d/components/`

楼梯由 `TowerDescent3D` 包装碰撞、门、端点和运行时元数据。正式 Blend 以当前 Godot GLB 反推，只保留 `Stair_A / Stair_B` 两个楼梯间资产包；不含战斗区、基地、天台或其他模型。`runtime/` 保留给未来独立楼梯 PackedScene。
