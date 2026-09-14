# 塔楼区块白盒

战斗区仍处于白盒阶段。楼梯区 v012 已从当前 Godot GLB 反推尺寸与布局，并提升为独立正式 Blender 源；旧 v011 混合白盒保留回滚。每个白盒版本固定使用 `data/`、`blender/`、`renders/` 三类目录；正式 Blender 源不得放在这里。

- `data/`：可由 `tools/3Dgame-design` 直接读取的 v3 场景 JSON；固定使用 Blender Z-up、米、角度和 `groups/components`，项目追溯字段放在 `projectMetadata`。
- `blender/`：根据同版本 JSON 组装或迁移的白盒 Blender 文件。
- `renders/`：由该白盒输出的顶视图、无标注图、立面、剖面和效果图。

楼梯区正式源：`assets/art/environments/tower_descent_3d/source/stairs_12m/env_tower_stairs_12m_source_v001.blend`。该文件只包含两套楼梯间资产包；当前 Godot GLB 未重新导入。
