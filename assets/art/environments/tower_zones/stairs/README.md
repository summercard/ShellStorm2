# Stairs

- 运行时节点：`Blocks/Stairs`
- `Stair_A`：`ENV-TOWER-STAIRWELL-ROOFTOP-12M`，100F→99F
- `Stair_B`：`ENV-TOWER-STAIRWELL-GENERIC-12M`，99F→98F
- Blender：`assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v011.blend`
- GLB：继续位于 `assets/art/environments/tower_descent_3d/components/`

楼梯由 `TowerDescent3D` 包装碰撞、门、端点和运行时元数据。本轮不移动或重新导入 GLB；`runtime/` 保留给未来独立楼梯 PackedScene。
