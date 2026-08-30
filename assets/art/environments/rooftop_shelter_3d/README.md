# 末世天台庇护所 50m 模块化场景

- 资产 ID：`ENV_ROOFTOP_SHELTER_50M`
- 网格契约：50×50m，由 10×10 个 5×5m 标准地砖组成。
- Blender 单位：米；正面 `-Y`；上方向 `+Z`。
- 场景源文件保留独立地砖、结构、家具、植物、设备、灯光和动效对象。
- `01_制作组件_已统一材质` 保存 12 种隐藏地砖母版；`02_游戏输出_独立模块` 保存可编辑总场景。
- 运行 GLB 不内嵌图片；引擎导入时绑定项目公共色盘。

灯光变体：

- `source/env_rooftop_shelter_50m_lighting_day_v011.blend`：大雾阴天白昼。
- `source/env_rooftop_shelter_50m_lighting_night_v011.blend`：此前夜间暖灯参数，使用同一套 v011 实体化场景模型。

唯一公共色盘：

`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`

材质角色固定为：

1. `01_精工金属_紫色骨架`
2. `02_细腻哑光_青绿大面`
3. `03_清漆反光_紫粉点缀`
4. `04_柔和自发光_UI灯光`

`components/` 对应 Blender 内部资产分类；对象级位置、尺寸、材质、集合、动画和资产 ID 记录于 `reports/asset_manifest_v011.json`。`components/UI/` 保持为空，场景展示不包含 UI。
