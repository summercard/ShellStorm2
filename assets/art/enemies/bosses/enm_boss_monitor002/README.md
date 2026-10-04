# Boss 002 · MONITOR.EXE

## 当前交付 v005（骨架蒙皮与表情状态）

模型：`source/enm_boss_monitor002_model_v005.blend`。动作工作文件：`source/enm_boss_monitor002_animation_v005.blend`。共41骨，骨架ID `SKEL-MONITOR002-001`，双文件骨架签名一致。整套18,308三角面（柔性支撑增加轴向环线），低于20,000。旧文件保留。未导出GLB或导入Godot。

模型文件静止T Pose、没有Action；六表情改为持久状态，选 `ExpressionController` 后修改自定义属性 `expression_index`：0默认、1怀疑、2愤怒、3困倦、4挑衅、5故障。不再自动轮播，也没有擅自绑定Enemy3D玩法状态。

绑定控制（选Boss002_Rig进入姿态模式）：

- `hand_ctrl.L/R`：沿本地Y移动，弹簧手臂伸缩；其他方向可改变伸出方向。STRETCH_TO只伸缩轴向，不缩细线圈半径；压缩/回弹节奏由之后的动作关键帧控制，没有添加物理模拟。
- `support_01/02/03`：三段FK弯曲支撑，带平滑归一权重；用于前倾、侧弯和下压。
- `monitor_tilt`：以背部铰链为轴倾斜，支持前砸；`monitor_spin`：本地Y绕屏幕法线旋转。
- `face_anchor_*` 跟随显示器；`face_*` 只复制锚点位置、朝向保持角色root坐标系，屏幕旋转不带着五官转。不是摄像机Billboard，角色整体转向仍正常跟随root。
- `digit1..4_01/02.L/R`：每手三指加拇指，各两节，可进一步制作握持姿势。
- `prop_socket.L`：键盘道具骨挂点；键盘独立、未混入手套蒙皮，可拆换。当前张掌T Pose不等于握持动作。
- `cable_01..05`：长数据线FK链，根部跟右手，接头跟末端。

动作文件有5个 `QA_*` Action：伸缩、屏幕旋转、前砸、下压、手指弯曲。第1帧中立，第36帧测试极值，第72帧恢复。它们只证明绑定可动，不是最终战斗动作；旋转/前砸极值可能使道具或身体触地，正式动作还需制作接触与避穿插。

源级21项验收通过，见 `previews/rig_v005/audit.json`：权重覆盖与归一、静止形态、左右臂独立伸缩且半径保持、屏幕转动与前倾时五官朝向稳定、支撑变形、下压、指骨、键盘跟随、恢复无漂移、表情跨帧保持与双文件签名。导出前需烘焙变形骨约束；表情UV驱动需运行时适配，不能直接当作GLB骨动作。下列旧版说明仅供追溯。

## 当前交付 v004（六表情库）

打开 `source/enm_boss_monitor002_source_v004.blend`。默认、怀疑、愤怒、困倦、挑衅、故障六种表情来自设计稿右下角，使用gpt-image-2参考图生成透明图集，已内嵌Blend；绿色代码沿用v003。三个独立漂浮剪片不增面，整套仍为18,144三角面。身体和手套网格不变，未绑骨，未接入游戏。

时间轴帧 **1 / 25 / 49 / 73 / 97 / 121** 对应上述六表情；24fps，每秒离散切换，帧145回到默认。唯一Action为 `BOSS002_expression_switch_preview`，只驱动 `ExpressionController` 的 `expression_index`，不驱动身体。需手工选择表情时，先在Action编辑器解除该预览Action，再修改控制器自定义属性0–5；保留Action时改对应关键帧。

交接文件 `source/expression_library_v004.json` 包含稳定表情ID、每块眼/嘴的像素裁切、帧号和图集信息。实际实现为各剪片材质UV缩放/偏移及剪片尺寸驱动，固定中心锚点，CONSTANT插值；不做表情间淡化混合。后续Godot需按此数据接入材质或动画，Blender驱动不会自动成为GLB动画。

真实模型六张表情预览位于 `previews/expressions_v004/`，检查记录为该目录 `audit.json`。生成图位于 `source/textures_v004/expressions_atlas.png`（1536×1024，3×2）；提示要求严格参照设计稿六态，独立眼嘴、透明背景、平面色块和黑轮廓。下列v003及更早内容仅作版本追溯。

## 当前交付 v003（低模与贴图）

当前文件：`source/enm_boss_monitor002_source_v003.blend`，旧版保留。全模型 **18,144 三角面**（包括键盘、长数据线、屏幕和五官，不含摄影环境），无未应用修改器。每只圆头四指手套2,222三角面；键盘2,184三角面，已删除字符。仍为T Pose、无骨骼和动作。保存重开8项检查通过，见 `previews/optimized_v003/reopen_audit.json`。

`source/textures_v003/screen_code.png`（1024×1536）与 `face_atlas.png`（1024×1024，RGBA）由 sofunny-image CLI 明确调用 **gpt-image-2** 生成；图片已打包到Blend，外部原图保留。屏幕文字为贴图；五官保留三个独立漂浮平面，仅6三角面。预览：`previews/optimized_v003/overview.png`、`hand_detail.png`、`face_detail.png`。

生成提示语：屏幕为无边框、无透视的黑绿底竖屏终端代码，荧绿等宽文字与底部光标；五官以用户设计图为参考，透明图集左上为异形阴影线大眼、右上圆眼与睫毛、下方不对称红唇，要求平面色块及黑色轮廓。未进行额外图像编辑，仅通过UV区域映射使用生成图。以下段落为旧版追溯。

当前源版本为 `source/enm_boss_monitor002_source_v002.blend`。v002按用户修正双手为平展、掌心朝下的四指手套（1拇指+3手指），旧v001保留。键盘与数据线保留为独立展示件，张掌姿势不握持。当前含修改器总三角面230,190；基础网格多边形21,294（不包括曲线与文字求值）；单手套68,784三角面。新预览与检查见 `previews/hands_v002/`，下文初版交付路径保留追溯。

资产身份：`ENM-BOSS-MONITOR002-3D`。用户于 2026-10-03 提供设计图并指定：竖屏显示器、绿色代码、漂浮的毕加索式平面五官、线圈手臂、白手套、键盘与长数据线；保持 T Pose，暂不绑骨。

## 本次交付

- `source/enm_boss_monitor002_source_v001.blend`：可编辑模型源。打开默认场景 `BOSS002_SOURCE_TPOSE`；`BOSS002_STUDIO` 为单独的灯光与摄影场景。
- `source/boss002_production_ledger.xlsx`：本资产新建制作明细账；唯一正式登记仍在敌人分账本《资产主表》，经 `ledger_index.json` 解析。
- `reference/design.png`：用户提供的设计图。
- `previews/overview.png`、`front.png`、`back.png`、`side.png`：真实 Blender 渲染。
- `previews/source_audit.json`：保存后重开的独立源级检查。

## 源级契约

米制，脚底近原点，Blender +Y 为正面，所有对象缩放为 1。总包围盒约 6.555 × 1.007 × 3.427 米（含展开手臂及数据线），不是运行时碰撞尺寸。显示器本体为竖屏，双掌同高，线圈从背部插口连至袖口。模型按七种部件与 default 样式两级 Collection 分类。

眼睛、嘴巴、轮廓、睫毛均为真正平面网格，分层前后距离约毫米级，整体浮在屏幕前约 0.28–0.34 米。没有将五官做成球体，也未贴整张概念图代替模型。绿色代码使用可编辑文本，不依赖外部字体或贴图；本轮无需 image-2。

用户指定无骨骼，因此不创建 Armature、权重、动作或动作母版；制作阶段标记 `authored_unrigged`，映射项目现行 XLSX 枚举为 `Blender源已完成`。工作模型保留倒角、手套细分与可编辑曲线；尚未进行运行时减面和导出。

## 消费者证据与延期

项目 Boss 消费链为 `src/enemy3d/BossContentCatalog.gd` → `Enemy3D`。现有档案只有 95/90/85 层 Boss，没有 `boss_monitor002` 映射。后续接入应建立稳定 PackedScene，由 Enemy3D 保持碰撞、AI、生命与伤害所有权；专项入口为 `tests/verification/verify_unique_boss_content_flow.gd`。本轮只制作用户明确要求的美术源，不替换现有 Boss，不把 002 当楼层号，不伪造已接入状态。

后续骨骼、动作双母版、UV烘焙、低模优化、GLB、Godot 包装、内容映射与运行时验收均未执行。

## 复现

使用 Blender 4.5 后台运行 `scripts/blender/build_boss002.py` 构建；该脚本会重建本资产源，应只在需要重新生成本版时使用。`scripts/blender/verify_boss002.py` 只读重开检查；登记工具为 `scripts/blender/register_boss002.py`。
