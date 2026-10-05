# Boss 002 · MONITOR.EXE

## 当前交付 v027（受击坐地反弹、眩晕与线缆电流）

模型/动画双母版 `source/enm_boss_monitor002_model_v027.blend`、`source/enm_boss_monitor002_animation_v027.blend`；打开动画默认播放 `stun_enter`，1—43帧，30fps。保留v026及更早版本。

`stun_enter`：受击后仰、单帧黄色闪形（F4）、F5切换螺旋眼与环绕星星，F19首次坐地，F25反弹最高点（0.48米），F31第二次坐地后稳定；双臂和手腕在反弹时错拍摆动。`stun_loop`保持眩晕；`stun_exit`在F20恢复表情并关闭星星。特效采用纯色块，无勾线。

特殊攻击电流继承数据线骨骼，蓝色细电弧配流动亮芯；`special_insert` F15通电、`special_channel`持续、`special_recover` F9断电。所有正式动作显式重置特效开关，避免切换残留。`BOSS002_DIZZY_ELECTRIC_PREVIEW`为独立预览集合，不属于角色导出几何。

七段动作以半帧采样检查地面、线缆骨链、锁点、分段衔接与循环，通过；真实Cycles预览和报告见 `previews/impact_electric_v027/`。仍为Blender源级交付，未导出GLB或接入Godot。

## 历史交付 v026（剩余五类十剪辑）

模型/动画双母版 `source/enm_boss_monitor002_model_v026.blend`、`source/enm_boss_monitor002_animation_v026.blend`。默认BOSS002_STUDIO、special_prepare；在Action列表切换以下剪辑，结束帧见 `previews/remaining_v026/clips.json`。旧五动作曲线保持，总计15正式剪辑。

新增：special_prepare / special_insert / special_channel / special_recover；hurt；stun_enter / stun_loop / stun_exit；turn_left / turn_right。双臂肩部先动、前后错拍、末端腕部回弹；转向分别制作左右90度视觉示范，root不写运动，正式方向消费尚待运行时适配。特殊持续段插头锁地，坐地屏幕下框接地；循环及分段接续检查通过。动作按1/4帧制作采样，1/2帧验收。原始失败（插头微漂、坐起线身穿地）修正后重测通过。

预览、关键帧及验收报告：`previews/remaining_v026/`。仅Blender源制作，未导出GLB、未接入Godot或伤害/状态机。

## 历史交付 v025（肩部驱动双臂）

打开 `source/enm_boss_monitor002_animation_v025.blend`，BOSS002_STUDIO播放1—61帧。取消世界坐标手部目标，双臂由肩侧关节领动，固定长度的六段弹簧臂逐段滞后，手腕继承末段姿态；身体仅保留小幅预备压重和跟随。支撑骨使用原姿态的朝向基准，修复进出动作时的混合翻滚。螺旋蓄力与快速弧甩保留。

验收：241次连续采样、末端继承与连接专项、正/侧视图关键帧。身体位移跨度0.205米，双手末端局部偏移误差低于0.000002米，链连接误差为0。报告 `previews/cable_v025/fk_quality_audit.json` 与 `audit.json`；同目录含正常及半速预览。旧版本保留；仅Blender源级，未接入Godot。

## 历史交付 v024（后轴跟随、螺旋蓄力与快速甩击）

打开 `source/enm_boss_monitor002_animation_v024.blend`，BOSS002_STUDIO播放1—61帧。双手目标使用后轴局部坐标，随身体转动和位移；局部惯性摆动叠加。前摇螺旋甩线1.5圈，21—24帧停顿后快速横甩。弧带65点曲线重采样，使用切线法向构建顺滑带面。配色沿用普通键盘攻击。预览 `previews/cable_v024/`，模型母版同版本；旧版本保留，未接入Godot。

## 历史交付 v023（数据线近战甩击）

打开 `source/enm_boss_monitor002_animation_v023.blend` 的 BOSS002_STUDIO，选择 `melee_cable`，播放1—61帧（2秒）。沿用原持线手，内部骨名hand.R；不交换道具。后撤蓄势、17—21帧短停，手腕先甩、16段线骨延迟跟随，鞭梢扫过身前弧线，键盘手反摆，随后回弹收回。普通键盘攻击同系蓝/玫红/亮色弧带跟随实际鞭梢轨迹，无勾线。

241次四分之一帧采样通过：线身、插头、键盘、屏幕离地；线骨长度误差低于0.001%，骨链无断口，首尾回同一姿态。旧四个动作曲线保持。预览 `previews/cable_v023/`，模型母版同版本。重击完整预览保留在v022；当前文件另留BOSS002_HEAVY_PREVIEW场景，需切换heavy_spin_slam动作。未接入Godot。

## 历史交付 v022（黄色命中高亮）

第65帧爆裂色块及瞬时补光改为黄色，仅持续1帧。源文件 `source/enm_boss_monitor002_animation_v022.blend`，模型同版本；预览 `previews/heavy_v022/`。形状及动作保持，未接入Godot。

## 历史交付 v021（砸地单帧高亮）

打开 `source/enm_boss_monitor002_animation_v021.blend`，播放1—97帧。第65帧为冰白高亮锯齿爆裂地面色块，附瞬时冷色补光；仅1帧（1/30秒），第66帧接回v020赛博脉冲。无勾线。整段预览及高亮帧在 `previews/heavy_v021/`；模型母版同版本，未接入Godot。

## 历史交付 v020（无勾线赛博脉冲）

打开 `source/enm_boss_monitor002_animation_v020.blend` 的 BOSS002_STUDIO，播放1—97帧。移除勾线、星形爆点和高饱和红蓝搭配，重新设计为冷蓝/青蓝色块、少量玫红数据碎片及冰蓝亮片。旋转使用三层断续弧带与扫描刻块；砸地使用三层错峰向外扩张的分段脉冲环、定向能量片和闪断矩形数据碎片，末段衰减消失。无手绘纹理。

角色四个动作曲线与v019相同；模型母版 `source/enm_boss_monitor002_model_v020.blend`。关键帧及整段预览在 `previews/heavy_v020/`。仅源级制作，未接入Godot，旧版本保留。

## 历史交付 v019（纯色色块与勾线特效）

打开 `source/enm_boss_monitor002_animation_v019.blend` 的 BOSS002_STUDIO，播放1—97帧。旋转拖尾、冲击环和爆裂片全部使用高饱和红蓝纯色网格及清晰深色勾线，移除涂鸦纹理、排线和碎笔触。保留v018角色动作、惯性跟随、后仰停顿与砸地节奏。旧版本保留。模型母版 `source/enm_boss_monitor002_model_v019.blend`。

四个角色动作曲线哈希与v018相同。真实渲染预览在 `previews/heavy_v019/`，仅源级制作，未导出或接入Godot。

## 历史交付 v018（重击高饱和红蓝配色）

动作 `source/enm_boss_monitor002_animation_v018.blend`，模型 `source/enm_boss_monitor002_model_v018.blend`。旋转弧带及地面冲击彩色笔触改成高饱和正红、亮蓝，发光强度0.8，减少高亮发白。动作、几何与时间轴保持v017；四个角色Action曲线摘要相同，见 `previews/heavy_v018/palette_audit.json`。受影响特效帧重新Cycles渲染，其余帧复用v017；完整预览 `previews/heavy_v018/heavy_spin_slam.mp4`。源级交付，未接入Godot，v017保留回退。

## 历史交付 v017（惯性跟随与重砸节奏深化）

动作 `source/enm_boss_monitor002_animation_v017.blend`，模型 `source/enm_boss_monitor002_model_v017.blend`。默认heavy_spin_slam，1—97帧/30fps。原idle/move/melee_keyboard保持，v016留作回退。

双手不再固定在世界坐标：跟随后轴的位移与速度，左手滞后3帧、右手5帧，触地后继续向前甩出，再衰减回摆；手腕、键盘和线尾有后续摆动。旋转专门使用6条渐细环形弧带，绕屏幕前后轴连续旋转，旋转期间不出现打击爆点图集。

49—55帧轻微后仰19°、抬高蓄势，55—59帧保持，59—65帧加速前扑砸地；触地后小幅回弹、再次压稳，随后重心回升与手部滞后收回。旋转弧带在停顿前消失，地面爆点仅命中时触发。

22项源级专项通过，385个细分帧检查；保留连续1080°、正向五官、固定底座、双母版同签名及关键几何不穿地。证据与整段预览 `previews/heavy_v017/`。测试检查运动契约，视觉品质仍以实际预览评审；未执行Godot接入、玩法伤害或完整网格间碰撞求解。

## 历史交付 v016（屏幕三圈旋转后前扑砸地）

打开 `source/enm_boss_monitor002_animation_v016.blend`，默认 heavy_spin_slam，BOSS002_STUDIO，1—97帧/30fps/3.2秒单次。模型母版 `source/enm_boss_monitor002_model_v016.blend`。旧idle、move、melee_keyboard曲线完全保留；键盘攻击特效预览继续使用v015文件，v016的STUDIO专用于重击。

屏幕绕后轴的前后方向独立旋转三圈（19—49帧），后轴/底座不转，双臂张开拖曳；五官抵消屏幕滚转并保持正向。49—55帧停顿，55—65帧前扑到屏幕正面近乎平贴地面，65—81帧低位暴露，81—97帧支架弹性回升。root固定，动作不产生玩法移动。

复用image-2手绘图集，旋转笔触20—49帧、大范围双层地面环和放射爆点65—82帧，83帧后清除。18项源级验收通过，385个四分之一帧核验1080°连续旋转、后轴不转、五官正向、底座固定、八类关键几何无穿地。完整证据与视频 `previews/heavy_v016/`。未执行完整网格互穿求解、Godot导出/接入与伤害事件；v015留作回退。

## 历史交付 v015（夸张特效与持线手后摆）

动作 `source/enm_boss_monitor002_animation_v015.blend`，模型 `source/enm_boss_monitor002_model_v015.blend`。默认BOSS002_STUDIO场景，1—55帧播放。手绘爆点、冲击环及蓝/玫红干扰统一放大至v014的1.65倍。持线右手蓄力向后上方拉开，下砸后继续后摆、稍滞后达到极值，再收回；前后行程约1.95m、上下约0.94m。数据线增加逐节延迟摆动。

身前平拍、五官22%放大、idle/move曲线保留。动作23项与表现8项通过，217个细分帧检查双手、键盘、数据线与插头不穿地，收招无特效残留。证据与视频 `previews/keyboard_v015/`。复用v014的image-2贴图，未导出或接入Godot。v014保留回退。

## 历史交付 v014（身前平拍与手绘赛博特效）

打开 `source/enm_boss_monitor002_animation_v014.blend`，默认 BOSS002_STUDIO 场景，播放1—55帧。模型母版 `source/enm_boss_monitor002_model_v014.blend`。v012/v013保留回退。

键盘宽面水平向下拍在身前约3.2米处；举高停顿、快速下砸、低位停留和收回保留。修正接触阶段四指握姿；五官以原中心放大22%。idle/move动作曲线与v012完全一致。

image-2制作透明图集 `textures/impact_v014/impact_atlas.png`：手绘白色尖角爆点、贴地冲击环、蓝色挥击笔触、玫红电子碎片。挥击28—34帧点缀，命中33帧触发，44帧前全部消失；独立 `BOSS002_IMPACT_PREVIEW` 集合，角色源场景不含特效。角色仍18,684三角面、64骨、3材质，预览另有3个特效材质。

动作23项与表现5项检查通过，四分之一帧检查无键盘/左手穿地；证据 `previews/keyboard_v014/audit.json`、`presentation_audit.json`。预览 `melee_keyboard.mp4`。仅源级交付，未导出GLB、未接入Godot/伤害事件。

## 历史交付 v012（键盘普通攻击）

动画文件 `source/enm_boss_monitor002_animation_v012.blend` 默认 `melee_keyboard`，并保留idle/move。静态母版 `source/enm_boss_monitor002_model_v012.blend`。64骨、18,684三角面、3材质；骨架拓扑保持，修正弹簧末端握点连接权重。

单次1.8秒/30fps：设计F0对应Blender帧1，F22=23帧蓄力停顿、F26=27帧启动快速下砸、F32=33帧命中、F40=41帧低位暴露结束、F54=55帧回待机。左手握键盘中段，由外侧举高后向前下方砸落；右手持线避让，末帧保持，不循环。代码UV持续上升。

表情统一由Boss002_Rig自定义属性expression_state驱动（0默认/1怀疑/2愤怒/3困倦/4挑衅/5故障）。攻击按阶段切换，idle/move均设默认，静态模型可手调此属性。ExpressionController.expression_index现在跟随该属性，不再直接手调。

证据 `previews/keyboard_v012/audit.json`，视频 `melee_keyboard.mp4`，六张关键姿态渲染。未制作冲击特效、伤害/碰撞判定或Godot接入；候选命中帧只用于后续同步。数据线甩击是另外的动作，本次未制作。

## 历史交付 v011（左右挪动移动动画）

动画 `source/enm_boss_monitor002_animation_v011.blend` 包含idle与move，默认move。静态T Pose模型 `source/enm_boss_monitor002_model_v011.blend`。新增pedestal_motion视觉骨，64骨、SKEL-MONITOR002-005，双母版同签名；18,684三角面、3材质保持。

move：30fps，1—48帧播放，49闭环，1.6秒。左右各23°底座压重与抬边，总横移0.46米，局部挪转±11°；屏幕和弹簧臂形成大幅高低差与延迟晃动。底座下缘逐帧贴地，手腕反向补偿保持键盘中段握持及垂线。逻辑root无累积位移，正式游戏前进由控制器负责。

idle原动作保留，切换后需将播放范围改为1—96；idle新增底座中立轨道，避免残留移动姿态。代码UV在两动作中连续向上。证据 `previews/move_v011/audit.json`，视频 `move.mp4`。未接入Godot，剩余攻击等动作未制作。

## 历史交付 v010（夸张弹性待机）

打开 `source/enm_boss_monitor002_animation_v010.blend`，默认动作idle，30fps、1—96帧循环（97闭环）。静态母版为 `source/enm_boss_monitor002_model_v010.blend`。63骨、18,684三角面、3材质。

双臂改为更强的连续弧线和上下摆动，左手握键盘长边中段；右手握线，线环下垂、插头朝下。三段支撑伸缩驱动屏幕明显上下呼吸，底座不动；眼睛和嘴通过各自锚点错拍浮动。code_scroll每周期增加1，UV负向采样令文字向上刷，曲线使用线性+REPEAT_OFFSET，跨周期不断流。

逐帧与握持/UV专项见 `previews/idle_v010/audit.json`，动态预览 `idle.mp4`。显示器与五官的旋转约束仍保留。Blender材质UV动画需后续Godot适配，尚未导出或接入。

## 历史交付 v009（握持与自然垂线待机）

动画文件 `source/enm_boss_monitor002_animation_v009.blend` 默认播放 `idle`；静态T Pose母版 `source/enm_boss_monitor002_model_v009.blend`。v008张掌挂道具和上翘线圈的待机方案由此版替代。

左手三根手指越过键盘上边缘，拇指从背侧对握，键盘与握点重新对齐。右手闭合握住长线，线环受重力下垂，线尾和插头朝下。修正四指根部蒙皮过渡；数据线从5节细化到16节，轻微摆动延迟于手腕。idle为3.2秒/30fps，1—96播放、97闭环；保持五官原位，底座固定。

63骨、18,684三角面、3材质，骨架SKEL-MONITOR002-004，双母版签名一致。逐帧循环与接触等16项检查通过；键盘最低约10.5cm、线环最低约3.6cm。近景含双手正背面，证据 `previews/idle_v009/`，视频 `idle.mp4`。表面距离测试只验证贴合，穿插另经多角度渲染检查；未进行完整三角形碰撞求解。尚未导出/接入Godot，其他正式动作未制作。

## 历史交付 v008（五官恢复与正式待机）

模型 `source/enm_boss_monitor002_model_v008.blend` 保持无动作T Pose；动画 `source/enm_boss_monitor002_animation_v008.blend` 默认播放正式 `idle`。五官恢复v006位置，骨架回到相同签名的SKEL-MONITOR002-002。52骨、18,320三角面、3材质。

idle为30fps、3.2秒循环，播放1—96帧，97为闭环关键帧。双臂六段形成向下弧线，左右错拍，支撑轻微呼吸、腕部和数据线滞后；底座固定，键盘/数据线离地。曲线含Cycles循环修改器。预览 `previews/idle_v008/idle.mp4`，逐帧检查见同目录audit.json。其余正式动作未制作，未接入Godot。下文为历史记录。

## 历史交付 v007（五官下移与动画设计）

模型 `source/enm_boss_monitor002_model_v007.blend`，动作工作文件 `source/enm_boss_monitor002_animation_v007.blend`；骨架 `SKEL-MONITOR002-003`，52骨、18,320三角面、3材质。大眼/小眼/嘴中心Z分别为2.20/2.10/1.20，六态与旋转跟随保留。33项源级检查通过。

动画设计主文档：[Boss002显示器动画设计](../../../../../docs/v0.1/design/Boss002显示器动画设计.md)。10类动作拆为15个正式剪辑候选，含动作阶段、表情、建议节奏、接触点、状态衔接和制作验收；正式动画尚未制作，动作母版仍只有既有QA动作。底座局部移动控制、插头锁地与砸地/坐地接触需在正式动画阶段实现。下文为历史版本说明。

## 历史交付 v006（中心后轴、分段双臂、三材质）

打开 `source/enm_boss_monitor002_model_v006.blend`。动作工作文件 `source/enm_boss_monitor002_animation_v006.blend`。52骨、18,320三角面、全文件仅3个材质，双母版签名一致；旧源保留，未导出或接入Godot。

- 后轴位于显示器中心背面 `(0,-0.52,2.02)`，三段柔性支撑延长到轴座。`rear_axle` 带动双臂根部，`monitor_spin` 本地Y独立旋转屏幕，双臂不随屏幕自转。
- 双臂各 `arm_01..06.L/R` 六段FK骨，直接旋转这些骨骼弯曲。选择 `Boss002_Rig` 对象自定义属性 `stretch_L/R` 控制弹簧轴向长度（1为静止长度），半径保持；`hand_ctrl.L/R` 用于手部姿势，不再通过移动它控制整臂伸缩。
- `support_01..03` 弯曲后支撑，`monitor_tilt` 控制屏幕前倾；四指骨、五节数据线骨、`prop_socket.L` 键盘道具挂点保留。
- 表情保持 `ExpressionController.expression_index` 六种持久状态。脸部锚点跟屏幕位置，五官朝向跟角色root，屏幕自转时五官平面不旋转。
- 身体：`BOSS002_01_BodyPalette`，色块图 `source/textures_v006/body_palette.png`，每个面的UV落入对应色块；色盘采用Non-Color线性值，详见同目录JSON。
- 表情：`BOSS002_02_ExpressionAtlas`，六表情共用v004一张RGBA图。三个五官网格的 `expression_slot_id` 属性区分裁切位置，材质只有一个。
- 屏幕：`BOSS002_03_ScrollingCode`，一张代码贴图、Repeat采样。`Boss002_Rig.code_scroll` 增大时文字从下往上移动，增加1滚动一张纹理高度；静态模型默认0，可插线性关键帧。

动作文件包含5个独立QA动作：双臂弯曲、单臂拉伸、屏幕旋转、前砸、代码滚动。源级32项检查通过，见 `previews/rig_v006/audit.json`；后轴/弯臂/独立旋转及六表情均有Cycles渲染。QA动作不是正式战斗动作。导出时需要烘焙骨骼驱动与约束；表情属性和UV滚动需游戏材质适配，Blender节点不会自动变成Godot动画。下文是历史版本记录。

## 历史交付 v005（骨架蒙皮与表情状态）

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

源级22项验收通过，见 `previews/rig_v005/audit.json`：权重覆盖与归一、静止形态、左右臂独立伸缩且半径保持、屏幕转动与前倾时五官朝向稳定、支撑变形、下压、指骨、键盘跟随、恢复无漂移、表情跨帧保持与双文件签名。导出前需烘焙变形骨约束；表情UV驱动需运行时适配，不能直接当作GLB骨动作。下列旧版说明仅供追溯。

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
