# 开放世界塔楼场景资产

## 调用入口

- 已拼装跨塔路线：`runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn`，已挂主场景 `Blocks/Rooftop/CrossTowerRoute`。主塔北侧开5m桥口，经低16m不可进入的塔2上方到等高塔3天台；布局与碰撞由路线包装拥有，两个原始建筑Prefab仍为纯表现。参见[路线契约](../../../../docs/v0.1/design/rooftop_cross_tower_route.md)。

- 塔2：`res://assets/art/environments/open_world/runtime/tower_02/env_tower_02_root_top3d.tscn`，源版本 v003，主体70×50m。
- 塔楼03：`res://assets/art/environments/open_world/runtime/tower_03/env_tower_03_root_top3d.tscn`，源版本 v001，主体70×44m，主屋顶40m，机房8m。
- 三台独立塔吊：`runtime/tower_02/cranes/crane_00/`、`crane_01/`、`crane_02/` 下对应的 `env_tower_02_crane_XX_root_top3d.tscn`。

在主场景添加这些 PackedScene 实例，移动/旋转建筑根节点即可；单位米，根缩放1，原点主体底部中心。建筑正面 Blender -Y 对应 Godot +Z。完整视觉包围盒包含脚手架、屋顶设备及塔吊，不等于主体70×50/44m占地。

每栋楼内部按类分组引用稳定组件Prefab；塔2的 `cranes` 分组仅含三个独立塔吊实例，每台内部保留七个可编辑组成件。塔楼03保留天台机房、地坪、风机、风管、电柜、通道、桅杆、卫星天线等布局。

资产当前仅表现，无碰撞、导航、交互脚本或玩法动画。没有自动加入主场景，也不改变远征关卡或玩家规则。导入不意味着已进行移动设备性能验收；大量细节源保留，暂未做LOD或轮廓减面。

## 维护

Blender母版位于 `source/<tower>/<源版本>/`，导出派生文件及清单位于 `source/<tower>/export/<源版本>/`；源文件与派生文件均禁止Godot直接导入。309个组件GLB均不含内嵌图片，通过项目共享色盘导入脚本恢复材质，投影保持开启。

1. Blender导出：`blender --factory-startup --background --python scripts/blender/export_openworld_towers.py -- --project-root .`。
2. 新建初始装配：`python tools/asset_pipeline/assemble_openworld_towers.py`。已有正式建筑/塔吊布局默认不覆盖；只有明确要重新初始化时使用 `--replace-layout`。
3. Godot刷新：隔离APPDATA后运行 `godot --headless --path . --editor --import`。
4. 导出校验：`python tools/asset_pipeline/check_openworld_tower_exports.py`。
5. 实际渲染验收：隔离APPDATA后运行 `godot --path . --rendering-method gl_compatibility --script tools/asset_pipeline/verify_openworld_towers.gd`。

塔2 v003塔吊集合父节点曾对已烘焙世界坐标的网格重复增加位移；导出脚本仅取消该组织位移并逐组件对照catalog冻结包围盒。原始母版不修改，不在Godot布局中叠加补偿变换。
