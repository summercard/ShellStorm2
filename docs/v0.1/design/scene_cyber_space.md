# 赛博空间

归属 `VFX-POOL` 的宿主持有环境表现，工程 0.1.0，设计 r1。来源为用户提供的五张全息场景参考和与普通场景、赛博虚空混用的要求。

## 表现

选中的墙、地板、栏杆、货箱和装饰以深色体块保留原有空间遮挡。模型表面共享米制网格，较细的分格铺在面上，实际结构边沿和网格交点更亮。高亮导线与少量流动光点提供方向感。紫、绿、蓝三个预设调用同一 Shader，可独立调整主体、网格、轮廓和信号颜色。

## 接入与交界

- 将预制体放在房间根节点下，默认绑定其下的静态场景网格。可用 `Target Roots` 限定子树，或用 `Excluded Roots` 排除角色、玻璃等对象。宿主持有实例并驱动 `progress`、`strength` 和范围，组件不参与战斗特效池与存档。
- `Box Size` 和节点位置、旋转决定米制范围，`Edge Width` 控制普通场景切换带。进度从 0 到 1 展开盒形范围。网格先在软边出现，亮的扫描线跟随交界，内部进入完整全息色调。
- 场景几何使用跟随现有网格的临时渲染节点。赛博空间先绘制在普通材质上，赛博虚空后绘制。两者可作用于同一模型，虚空内部优先显示深空，虚空断面与空间网格在交界叠合。格线对齐时使用相同的 `Cell Size` 与朝向，再用 `Grid Origin Offset` 调整空间网格原点。这个参数以本地米为单位，可以独立于效果盒的位置编辑。
- 关闭、清空强度或卸载会清理临时节点。刷新可重新读取晚加载或替换的宿主模型。室内原模型资源和物理状态由场景持有。使用两个面层时，建议以不透明静态环境为目标。

## 预设与验收

| 预设 | AssetID | 配色 |
|---|---|---|
| [紫色](../../../assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_root_top3d.tscn) | `VFX-ENV-CYBER-SPACE-3D` | 靛紫底面、紫白结构、青色导线与粉紫节点 |
| [绿色](../../../assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_green_root_top3d.tscn) | `VFX-ENV-CYBER-SPACE-GREEN-3D` | 深绿底面、青绿结构与黄绿信号 |
| [蓝色](../../../assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_blue_root_top3d.tscn) | `VFX-ENV-CYBER-SPACE-BLUE-3D` | 深蓝底面、冰蓝结构、蓝青导线与少量暖紫信号 |

打开[独立预览](../../../tests/visual/scene_cyber_space_preview.tscn)，用 0 还原，1／2／3 切换紫／绿／蓝，4 查看普通、赛博空间和赛博虚空混用，空格播放过渡。运行 `python scripts/run_scene_void_erosion_qa.py --cyber-space --godot <Godot console 路径>` 可采集三色、关闭还原和同场景交界对照。

Forward+ 可读法线缓冲强化轮廓，Compatibility 使用深度重建结构边沿。[Godot 屏幕读取 Shader 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)

工程变更和验证数据见[交付记录](../development/2026-11-21_cyber_space.md)。
