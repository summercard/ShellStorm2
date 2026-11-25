# 赛博虚空

归属 `VFX-POOL` 的宿主持有效果，工程 0.1.0，设计 r6，资产 `VFX-ENV-VOID-EROSION-3D`。正式名称为「赛博虚空」，特效账本编号 `FX03-04`。来源为用户提供的参考图与 2026-11-25 的可选坠落要求。

## 表现契约

- 宿主场景放置一个可旋转的侵蚀盒，以米编辑三轴尺寸。地板、墙和栏杆共享盒子的网格。大块缺口与细小剥落共同构成轮廓。浅层网格贴在原模型表面，开口内由相机射线绘制深浅不同的体素断面和侧壁。少量暖色高光沿断面外缘出现，格面和深处侧壁以冷紫为主。
- 蚀边网格限于幸存表面及开口交界。开口内部的深空使用与墙面片元前后高低无关的共同射线基准，跨墙板接缝和墙地交界连贯。布置时让侵蚀盒在法线方向覆盖预期吞噬区域的整个墙厚及其接缝背板。
- 洞内的独立方块以与蚀边一致的 `cell_size` 为基础格宽。近处方块为 2–4 格，远处方块为 2–3 格。每块有沿网格缺掉的角或边，有多种缺口布局，射线可以穿过空格看到后面。由朝向和景深决定屏幕上的格子大小。
- 方块在各自景深内持续漂移与摆动。近层和远层分别可调数量，包含遮挡、冷暖色与景深亮度差。星屑分布在洞口之后的多个三维深度区间，每颗有固定空间中心和实际粒径。视线经过不同深度的星屑，在相机平移时产生不同视差。体积雾、方块和前景场景模型按空间深度参与合成。
- 默认只显示视觉开口。格宽、边缘过渡、颜色、空间深向和漂浮物可按场景设置。

## 可选的物理开口

- 打开检查器「物理开口」组中的 `Remove Collision In Void`（`remove_collision_in_void`）后，虚空在选中的环境静态碰撞中切出局部开口。共享地板可以只切掉洞口，洞外仍承重。同一个开口盒供 Shader 和物理使用，发光过渡带保留实体阻挡。开启物理开口时，深空与实体的交界沿盒面，网格和内侧断面保留。展开期间随进度更新开口，关闭或收回时恢复。
- `Collision Roots` 为空时沿用视觉目标树，另填时可绑定同房间中独立的承重层。范围要贯穿地板或墙体的碰撞厚度。编辑器仅预览开口。运行支持局部裁切静态盒与静态三角网，其他静态形状可在完全被包住时移除，部分相交会保留并在运行时报告。排除子树、刚体角色和触发区由原宿主管理。
- 每个虚空持有自己的开口请求，同一静态碰撞上的多个开口合并处理。收回、关闭、改目标、卸载会撤销该虚空的请求；最后一个请求撤销时恢复原形状资源与形状所有者。无额外存档或事件。晚装配的目标可由宿主调用 `refresh_targets()`。
- 角色通过现有重力自然下落，有下层支撑时走原有落地流程。玩家保留已有 15 米安全回位，坠落不新增伤害或关卡结算规则。

## 接入、状态与恢复

- 实例化 `assets/art/vfx/environment_3d/void_erosion/runtime/vfx_env_void_erosion_root_top3d.tscn`。实例唯一持有本次范围、进度和临时覆盖材质，宿主负责触发与释放，无需池化或存档字段。
- 将预制体置于房间或组件组的根节点下。空的 `target_roots` 默认递归收集父节点下的 `MeshInstance3D`，墙地、栏杆、箱柜和装饰使用同一空间遮罩。构件跨过破口时，按片元处理范围内的部分，留出蚀边过渡。显式填写 `target_roots` 可限定参与的子树。用 `excluded_roots` 排除玻璃、带顶点变形的材质、角色或应保持原貌的组件。遍历去重，单个目标只接受一个侵蚀盒。已有材质覆盖或被其他盒持有的网格保留原效果。
- 宿主可用 `seam_fill_planes` 声明隐藏的 `PlaneMesh` 节点，覆盖墙板接缝背后。组件复制这些标记的平面，只在已经侵蚀的范围显示深空。补面使用场景深度测试，关闭和卸载时随覆盖层释放。静态碰撞以宿主原始形状为准计算物理开口。
- `progress` 从 0 到 1 展开至设定尺寸，并可逆向动画。0 或关闭 `enabled` 清除临时覆盖；大于 0 时可由检查器、`AnimationPlayer` 或 Tween 驱动。室内模型晚于组件创建时由宿主调用 `refresh_targets()`，返回本次绑定的网格数。路径失效时跳过，关闭、换目标或卸载会归还各目标当前的材质覆盖。编辑器预览只写渲染实例，目标场景序列化属性由原场景所有者维护。

## 独立验收

打开 [预览场景](../../../tests/visual/scene_void_erosion_preview.tscn)，选中 `VoidErosion`，改变 `progress`、盒位置和相机角度。运行预览后用 `1`、`2`、`3` 切换关闭、半开、全开，用空格播放展开或收回，方向键旋转相机，`P` 切换正交与透视。

| 检查器参数 | 用法 |
|---|---|
| Target Roots / Excluded Roots | 默认覆盖父节点下的场景组件。填写 Target Roots 可限定参与的子树，Excluded Roots 可保留指定组件。楼面若由留缝砖块拼成，可将现有连续基板一起选入。 |
| Seam Fill Planes | 选填。把隐藏的 PlaneMesh 放在墙板或地砖背后，补齐真实拼缝中断开的深空。标记调整后可刷新侵蚀目标。 |
| Box Size / Transform | 用米设三轴尺寸，用节点的移动和旋转对齐房间。 |
| Progress | 动画轨道驱动这一项，或移动节点做扫过场景的效果。 |
| Remove Collision In Void / Collision Roots | 打开局部切除阻挡。承重节点和模型分组不在同一子树时，另填碰撞根。留空沿用视觉目标树。 |
| Cell Size / Edge Width / Edge Irregularity | 调整台阶格宽、亮网格带宽和纯视觉模式下的边缘参差程度。 |
| Rim Depth | 设定体素断面的基础深度，单位为米。设为 0 可查看纯表面网格与洞内深空。 |
| Edge Color / Nebula Color / Warm Accent | 调整表面网格、星云及暖色高光。 |
| Interior Axis / Depth Scale | 设定相对节点的虚空深向，以及方块群随深度的间距。 |
| Cube Count / Far Cube Count / Drift Speed | 分别调整近处与深处的方块数量，以及持续漂移的速度。0 速度便于静帧预览。 |
| Star Density | 调整洞内空间星屑的密度，设为 0 可独立验收星屑层。 |

[独立验收命令](../../../scripts/run_scene_void_erosion_qa.py)在 Autoload 启动前隔离用户数据。运行 `python scripts/run_scene_void_erosion_qa.py --godot <Godot console 路径>` 复核展开、方块开关对照、互斥、排除目标、关闭与删除后的画面恢复。截图保存在工程外工作目录，用于检查墙地连续性、前景遮挡及方块视差。

同一命令追加 `--movie` 可用 Godot Movie Maker 录制固定 30 帧的绕拍，再通过 FFmpeg 生成 MP4。[Godot Movie Maker 文档](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)

追加 `--physics` 用正式玩家场景检查洞内外碰撞、下落与落地、重叠开口和碰撞恢复。[物理开口验收场景](../../../tests/visual/scene_void_opening_physics.tscn)

开发记录见[可选物理开口](../development/2026-11-25_cyber_void_collision.md)、[场景组件覆盖](../development/2026-11-21_cyber_void_component_scope.md)、[墙面连贯性修复](../development/2026-11-21_cyber_void_wall.md)、[赛博虚空正式登记与景深改版](../development/2026-11-21_cyber_void.md)、[体素断面与动态绕拍](../development/2026-11-21_scene_void_erosion_depth.md)和[首版接入](../development/2026-11-21_scene_void_erosion.md)。
