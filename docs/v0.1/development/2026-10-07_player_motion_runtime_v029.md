# 玩家四方向持枪动作正式接入 v029

日期：2026-10-07；功能ID：PLAYER-STATE / ENTRY-AVATAR / ASSET-PIPELINE；工程版本：0.1.0；状态：已接入，专项通过，存在下列明确限制；工作区未提交。
设计：[角色动作契约](../16.1_角色美术制作与动作导入流程.md)。

## 改动与边界

- v029沿用v028耳朵跟随、v026三类持枪待机；补6条持枪前进和8条无枪四方向，共35条新增正式剪辑（3待机+32移动），运行JSON另保留原14条，共49条。标准无网格GLB含35条新动作；原模型和静止骨架SKEL-BUNNY01-004不变。
- 稳定输出`variants/bunny01/components/chr_bunny01_motion/anim_bunny01_library.json/.glb`；原v021包装路径保持，assembly_version仍v021，asset_version/motion_library_version为v029。动作源独立存`source/animation/chr_bunny01_animation_v029.blend`，保留v028；严格中转为变体根`character_transfer_ledger.json`。
- Player3D仍保留八基础态加既有seated/climbing共10态，不新增方向玩法态；输出只读速度/朝向快照。CharacterMotionLibrary3D选择枪型、速度档与局部四方向，10%分量迟滞避免对角边界抖动，切换0.18秒混合并保留移动周期相位。机枪单独分类，近战明确兜底。
- 角色身体、耳朵、手脚继续只采样Blender。枪朝向采样源预览挂点（枪模本身不导出）；位置从已采样手掌跟随，避免过渡混合漂离。源手骨末端为掌心，旧运行HandJoint为腕口，新增只读掌心偏移用于握点核验，不再把新枪位姿吸回腕口。现有手模型/腕口原点保持。
- 本批已登记动作导入，不等同于完成射击/换弹/蓄力/近战动作；上述专用动作缺失仍由快照报告，弹道方向仍归玩法aim_direction。枪械自身后坐/换弹局部动画沿用，不生成角色程序姿势。

## 验证与已知限制

专项`verify_player3d_directional_motion`覆盖三枪型×两速度×四方向×两面朝向、无枪四方向、耳朵运动、掌心握点、支撑点、碰撞不变和标准GLB独立加载。真实Godot兼容渲染输出12张方向截图及60帧三枪型侧移动画，不是Blender图或AI生成。测试启动前隔离APPDATA/LOCALAPPDATA，未触碰正式用户存档。

代表枪（手枪/步枪/机枪）主握和支撑通过。其他同族枪模沿用族动作，左手与其SupportHandSocket仍有差异：霰弹约3.5cm、狙击约2.9cm、发射器约6.8cm、蓄力枪约10.8cm（默认0.8角色倍率）。快照weapon_support_error_m公开实测，不宣称逐枪型左手贴合，不用IK回写Blender曲线。武器命运缩放变化也可能扩大误差。

源步幅较小，沿用原游戏播放节奏，不强行按源参考速度提高十余倍；精确脚底锁地、过渡支持脚锁定仍待调校。仅最近方向选择，不实现二维方向混合。

回归中的旧断言按明确新契约修订：短枪待机从瞄准线改枪口朝上，长枪从单手兜底改双手；源规定的轻微上身跟随替换旧0.016m自由手摆幅要求。原画廊测试写死8态而工程早已注册seated/climbing，本次改为精确核验10个既有状态名称，未更改玩法状态数量。

证据：`outputs/character_pipeline/runtime_v029/`；制作脚本`complete_bunny_locomotion_v029.py`、`export_bunny_runtime_v029.py`，运行隔离脚本`scripts/verify_bunny_runtime.py`。

## 验收收口

Godot正式导入exit 0；方向专项无头/真实渲染、动画、待机、武器握点与碰撞、DIY、尺寸、下身挂点、状态画廊全部exit 0，非预期脚本错误为0，无预期故障注入。每份运行日志再次通过check_verification_log。工程已有公共色盘UID回退警告和临时目录重复UID警告保留，不冒充无警告工程。

Asset guard按version_increment通过。账本主行13更新版本v029/active/包装SHA；35条动作源更新（21既有、14新增），中转114–117，既有3D角色行6更新；单元格白名单与数据验证保留检查通过。未创建额外Prefab，未接受其他资产哈希。角色结构门禁exit 0；角色全量exit 1仅既有头部行21 SHA差异。拆分门禁改前/改后均exit 1，均为其他任务收音机PRP-BASE99-RADIO-3D及3D-道具两处差异，角色分账本无新增失败。文档exit 1仍为4个既有未登记验证入口，新方向测试已登记core。

运行命名门禁保持全局存量问题，未新增带版本运行资源或扩大豁免。未执行全工程core/full、手机性能、所有换装组合或专用战斗动作验收；全库引用扫描此前无输出超时，本轮不重复宣称通过。
