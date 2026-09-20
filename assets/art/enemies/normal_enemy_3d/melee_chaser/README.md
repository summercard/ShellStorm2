# 小僵尸 · 首只标准普通怪资产包

## 2026-09-20：攻击与跑步修订 v003

源：`source/animation/enm_melee_fungboar01_animation_v003.blend`。仅替换attack/running；其余四Action曲线摘要与v002一致。模型、骨架、UV不改。

攻击整段采用实际右手抬起、前伸跨身弧线、迟缓收势。注意导入骨名左右与角色解剖左右相反：角色前向+Y，实际右侧为-X，对应`L_Hand`；按用户箭头的手执行，不改骨名。跑步胸部前倾目标从21°增至32°，双臂前伸，脚踝前后轨迹跨度从0.25m增至0.36m，摆动抬脚目标从0.07m增至0.105m；这是创作参数，不是已测世界位移。

## 2026-09-20：Godot 正式接入

- 已将模型 v002 + 动画 v003 导出为 `components/enm_melee_fungboar01_visual_top3d.glb`，包含 `idle/walking/running/attack/hurt/dead` 六段剪辑；导入验证为 36 根骨骼、6 个动画。
- `runtime/enm_melee_fungboar01_root_top3d.tscn` 作为正式表现包装；`melee_chaser_formal_visual.gd` 将 12 个 Enemy3D 状态映射到六段 Blender 动画：**只有 `patrol` 用走路，`chase/search/return`（朝玩家接近）一律跑步**，选段不再依据实际速度，避免同一状态在快慢档之间抖动；攻击前摇/命中/恢复只采样表现进度，不改变攻击判定。
- 非精英 `melee_chaser` 隐藏旧程序化 core/shell/appendages，仅保留状态环；精英加载成功或失败均不叠加普通小僵尸表现。碰撞仍由 Enemy3D 的 CylinderShape3D 拥有，尺寸未改。
- 死亡仍立即结算、掉落和注销 AI；小僵尸表现保留 2.4 秒后回收，不再使用旧 0.34 秒压扁。旧存档普通怪名称尾部“小菌猪”精确迁移为“小僵尸”，精英专名不改。
- 已通过 `verify_melee_zombie_presentation`、`verify_full_3d_game_flow`、`verify_first_elite_deployment_flow`。`verify_3d_enemy_behavior_flow` 有七类敌人的浮动伤害数字红项，尚未做变更前基线对照，不能断言与本次无关。实际渲染审查、资产重复门禁适配及 XLSX 登记尚待完成，不视为全部验收通过。

## 2026-09-20：动画修订 v002

当前动画源为 `source/animation/enm_melee_fungboar01_animation_v002.blend`，v001保留。继续关联v002模型，骨架签名、几何、UV不变。待机改为屈肘前伸、肩部下垂；慢走/跑步使用双段腿解析IK与分侧脚踝轨迹，左右支撑比例和抬脚高度不同；抓击重设上臂/前臂方向，受击增加抬脚后撤。死亡暂保留v001后躺回弹动作，并非六段全部重新设计。

独立重开1266个四分之一帧采样通过骨架/缩放/Root/循环门禁；跑步最深微穿入约0.164毫米。动态预览 `outputs/little_zombie_animations_v002/`。尚未完成逐支撑期世界空间零滑步测量、全程自穿插及表演质量独立审查，不标为最终高品质验收通过。用户已明确不需要逐阶段征求确认，应自行迭代，不将参考图当作审批关卡。

## 2026-09-20：六段动画源 v001

动画源：`source/animation/enm_melee_fungboar01_animation_v001.blend`，关联同目录树 `source/model/enm_melee_fungboar01_model_v002.blend`。模型文件、UV、静止骨架不改。30fps，顶部场景选择器切换六段：idle 3.2秒、walking 1.6秒、running 0.8秒、attack 1.7秒、hurt 0.8秒、dead 2.4秒。前三段循环，后三段单次末帧保持。

造型方向：前倾驼背、不对称拖步，攻击大幅摆臂加迟缓恢复；死亡向后躺倒、两次衰减回弹。Root静止，Hip只作表现位移。不能把时间轴自动回到开头误认作死亡循环。

本轮仅用户指定六动作，不是完整12状态接入。现有程序前摇0.38秒、恢复0.34秒、硬直0.16秒与艺术动作时长不同，后续按状态阶段采样，不修改玩法。地面检查不等于支撑脚无滑移；允许低模局部挤压，不宣称零自穿插。中转记录与动态预览在 `outputs/little_zombie_animations_v001/`。

## 2026-09-20：v002 模型、UV 与手指绑定

用户确认当前人类僵尸男造型，显示名改为小僵尸。AssetID、melee_chaser 与运行时保持不变。以下为当前源版本；后文 v001 记录保留作历史。

- 当前源：`source/model/enm_melee_fungboar01_model_v002.blend`；v001 未覆盖。
- 高度锁定：源 1.857143m × 0.70 = 展示 1.30m；Blender +Y 前向，脚底 Z≈0。
- 重建为 36 根骨骼；四指造型，每手四条两节指链，共16根手指变形骨，全部有权重并逐根旋转测试通过。骨架ID `SKEL-MELEE-FUNGBOAR01-002`。原异常 Twist 链移除并将权重归并到对应肢段，手部重新分配。
- 保留2278顶点、4552三角面及原始外形；左右纹理独立。UV从100岛整理为67岛，单面岛0，≤6面岛1；修复原退化UV，正面积重叠/翻面/越界均0。
- 2K sRGB PNG：`source/model/textures/enm_melee_fungboar01_basecolor_v002.png`，已嵌入blend；原JPG仍保留并嵌入。移除未接线的Normal Map节点，不虚构法线贴图。
- 真实栅格覆盖49.32%；10万点颜色平均绝对误差0.00237。全表面各向异性p95=2.327，>1.3的表面积41.86%，存在局部拉伸；没有将其描述为游戏相机可见区指标。未达到≤50岛最佳目标。
- 重开检查：高度、几何不变、权重归一、16根手指有实际变形且不牵动对侧、贴图嵌入通过。预览包含正/背/侧、棋盘格、手部弯曲与身体姿态。
- 本轮仅模型源。没有正式Pose Actions、动作文件、Godot接入或账本转正；后续动作必须使用新骨架，不能套用旧骨架动画。


> 建立日期：2026-09-20
> 定位：**普通怪 7 类的第一只标准样板**。本目录结构将原样复制给其余 6 类。
> 台账行：`ENM-MELEE-FUNGBOAR01`（敌人账本 · 资产主表 r6，当前状态「程序占位」）

## 身份

| 项 | 值 |
|---|---|
| AssetID | `ENM-MELEE-FUNGBOAR01` |
| 中文名 | 小僵尸（原登记名：小菌猪） |
| 逻辑 ID（= 代码 `enemy_kind`） | `melee_chaser` |
| 子类 | `normal_melee` |
| 所属域 | 敌人（`assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx`） |
| AI 类型 | `chase`（纯近战追击） |
| 碰撞方式 | `CylinderShape3D`，尺寸取自 `EnemyAvatar3D.FOOTPRINT_PROFILES` |

⚠️ **台账行已存在，只能升级既有行，禁止新增**（否则撞 `duplicate_asset_id`）。

## 目录契约（三段式）

```
normal_enemy_3d/melee_chaser/
├── source/            ← Blender 原始文件（唯一允许出现 _vNNN 的地方）
│   ├── .gdignore      ← 空文件（单个 CRLF），阻止 Godot 扫描源目录
│   ├── model/         ← 模型 blend（几何 / UV / 绑定）
│   │   └── textures/  ← 贴图源文件
│   └── animation/     ← 动作 blend（动作库，与模型共享骨架 ID）
├── components/        ← Godot 导入的视觉 GLB（运行路径，不带版本号）
├── runtime/           ← PackedScene 包装（运行路径，不带版本号）
└── previews/          ← 源级核对用渲染图（PNG，不受命名门禁约束）
```

### 文件命名

| 段 | 文件名 | 版本号 |
|---|---|---|
| 模型源 | `source/model/enm_melee_fungboar01_model_v001.blend` | ✅ 带 |
| 贴图源 | `source/model/textures/enm_melee_fungboar01_basecolor_v001.jpg` | ✅ 带 |
| 动作源 | `source/animation/enm_melee_fungboar01_animation_v001.blend` | ✅ 带 |
| 视觉 GLB | `components/enm_melee_fungboar01_visual_top3d.glb` | ❌ 不带 |
| 运行时 Prefab | `runtime/enm_melee_fungboar01_root_top3d.tscn` | ❌ 不带 |

文件名前缀 = AssetID 去掉尾部 `-3D` 后全小写、`-` 转 `_`
（`ENM-MELEE-FUNGBOAR01` → `enm_melee_fungboar01`）。

**运行资产（GLB / tscn）替换 = 覆盖同路径同名文件**，`.import` / `.uid` 留原位。
`v###` 只允许出现在 `source/`、台账 O 列、Prefab 根 `metadata/asset_version`。
门禁：`python scripts/check_asset_runtime_naming.py`（新增违规 exit 1；`source/**` 整体豁免）。

### `source/.gdignore` 说明

内容 = 单个 CRLF 空行（2 字节）。**全仓通行做法**：角色 / 武器 / 环境 / 道具 / 音频的
`source/` 都放这个文件，敌人域本包首次引入。作用是不让 Godot 去导入 `.blend`
（否则生成本地 `.blend.import`，且依赖编辑器里配好的 Blender 路径）。

> ℹ️ 既有不一致（本轮未动）：`elite_3d/rift_boar_armed/source/` 没有 `.gdignore`，
> Godot 会去导入它那个 `.blend`。要不要一起补，等主人定。

## 源资产入库记录（2026-09-20）

**来源**：Tripo 交付目录 `C:\Users\zhuangmenghong\Desktop\tripo_convert_94da5a61-b4d6-4828-bad8-2525eaea77e6`

| Tripo 原件 | 处理 |
|---|---|
| `Moster_01_xiaojunzhu.blend` | 入库为 `source/model/enm_melee_fungboar01_model_v001.blend` |
| `…​.fbm/Moster_01_xiaojunzhu_basecolor.JPEG` | 入库为 `source/model/textures/enm_melee_fungboar01_basecolor_v001.jpg` |
| `tripo_convert_94da5a61-…​.fbx` | **未纳入**（Tripo 中间产物，几何与 Blend 同源，无独立信息） |

> ⚠️ 原件名拼写是 `Moster`（少一个 n）。改名只做在入库副本上，桌面原件未动。

**入库时做的内部改名**（Blender 内对象 / 材质 / 贴图）：

| 类型 | Tripo 原名 | 入库名 |
|---|---|---|
| Armature 对象 | `Armature` | `enm_melee_fungboar01_armature` |
| Mesh 对象 / Mesh 数据 | `tripo_node_94da5a61` / `tripo_mesh_94da5a61` | `enm_melee_fungboar01_mesh` |
| 材质 | `tripo_mat_94da5a61` | `enm_melee_fungboar01_mat` |
| 材质（0 引用的空壳） | `Material` | 已删除 |
| 贴图 image | `Moster_01_xiaojunzhu_basecolor` | `enm_melee_fungboar01_basecolor` |

## 尺寸口径（★ 最重要的一条）

`Enemy3D` 在艺术家尺寸之上**再乘一层全局展示倍率**，且 `Avatar` 与 `CollisionShape3D`
都是 `Enemy3D` 的直接子节点（`Enemy3D.gd:162-163`），**两者一起吃这个倍率**：

```
游戏内尺寸 = 源文件尺寸 × DEFAULT_BASE_SIZE_MULTIPLIER(0.70) × kind 倍率 × variant 倍率
melee_chaser：kind = 1.0；普通怪 variant = 1.0   ⇒   × 0.70
```

出处：`src/enemy3d/Enemy3D.gd:26`（常量）、`:295-300`（写入 `scale`）、`:39`（kind 倍率）。

| 角色 | 源文件高 | 展示倍率 | 游戏内高 |
|---|---|---|---|
| 玩家（兔） | 1.500 m | **0.80** | **1.200 m** ← `verify_player3d_avatar_bounds` 硬断言 |
| **小菌猪（本包）** | **1.857 m** | 0.70 | **1.300 m** |
| 精英·背枪的裂口爬虫 | 1.345 m | 0.70 × 1.16 | 1.092 m |

玩家数字来自 `tests/verification/verify_player3d_avatar_bounds.gd:4`
（`EXPECTED_STATIC_HEIGHT_M := 1.20`）；精英变体倍率 1.16 因为它的
`modifier_id = "Elite.WeaponParasite"`（≠ `Elite.Huge`，后者是 1.5）。

**结论口径**：主人要「比玩家大一点」，指向的是**游戏内显示高度**。玩家 1.20 m
⇒ 取显示 1.30 m（+8.3%）⇒ 源文件必须做 **1.857 m**。
直接把源文件做 1.3 m 会得到游戏内 0.91 m，**比玩家还小**，方向反了。

## ★ 朝向：模型原本是错的，已修

**契约**（`docs/v0.1/16.1_角色美术制作与动作导入流程.md:147`）：

> 面罩朝 Blender **+Y**，Z 向上。… 前向为 **-Z**，不额外加偏航补偿。

**实测（修复前）**：模型朝 **Blender +X**。
判据是六个机位的渲染图 —— 从 **+X** 看是**完整正脸**，从 **-X** 看是**后脑勺**，
从 ±Y 看都是**侧脸**。证据图：`previews/enm_melee_fungboar01_orientation_before_v001.png`。

若原样导入，Godot 里角色会**横着站**（面朝 +X，而契约前进方向是 -Z，差 90°）。

**修法**（脚本 `_scratch/xiaojunzhu_intake/fix_orientation.py`）：绕世界 **Z 轴 +90°**
（`Rz(+90°)` 把 +X 映射到 +Y），作用在**数据层** —— 网格顶点（2278 个）
与骨架编辑骨（41 根，先快照 `edit_bone.matrix` 再整体左乘 R，`bone roll` 随之更正）。
**不写对象级旋转**，不留隐藏补偿。本 blend 当时无任何 Action，不存在需重定向的既有动画。

| | 左右 X | 前后 Y | 高度 Z |
|---|---|---|---|
| 修复前 | 0.9535 | 1.2819 | 1.8571 |
| **修复后** | **1.2819** | **0.9535** | **1.8571** |

X / Y 按预期互换，高度不变，脚底仍贴地。对象级 rot / scale 全部归零 / 1.0。
**修复后证据图**：`previews/enm_melee_fungboar01_orientation_after_v001.png`
（cam +Y = 正脸 ✅，cam -Y = 后脑勺 ✅，cam ±X = 侧脸 ✅）。

## 动画：源模型**不含**任何动画数据

实测 `bpy.data.actions` **总数 = 0**，全部对象 `animation_data = None`，
41 根姿态骨只有 2 处 2e-5 量级的浮点噪声（非真实姿势）。
⇒ 这是**纯静态 T-pose 模型**，动作必须从零做，不能"改现有动作"。

### 敌人动画契约：12 态状态机（账本《敌人动画与状态》分页）

`ENEMY_AI_12_STATES`，状态 ID 逐字取自 `src/enemy3d/Enemy3D.gd` 的 `VALID_STATES`：

| # | 状态ID | 中文 | 表现职责 |
|---|---|---|---|
| 1 | `dormant` | 休眠 | 未激活前不表现，不消耗视觉预算 |
| 2 | `idle` | 待机 | 呼吸 / 轻微起伏 |
| 3 | `patrol` | 巡逻 | 沿巡逻点位移；朝向跟随路径 |
| 4 | `alert` | 警觉 | 锁定可疑目标；身体抬升 / 视线上抬 |
| 5 | `chase` | 追击 | 朝玩家追击；步频随速度切换 |
| 6 | `search` | 搜寻 | 丢失目标后在最后已知位置环视 |
| 7 | `return` | 归位 | 脱离战斗归巡逻点 |
| 8 | `telegraph` | 预警 | 出手前的蓄力前摇，**必须可读** |
| 9 | `attack` | 攻击 | 判定生效帧与挥击表现对齐 |
| 10 | `recovery` | 收招 | 攻击后的硬直表现 |
| 11 | `stagger` | 踉跄 | 受击打断；闪白 + 位移 |
| 12 | `dead` | 死亡 | 倒地 / 瓦解；播放结束即回收 |

⚠️ 该分页当前**全部登记为「程序驱动（EnemyAvatar3D 仅记录 ai_state）」**，
循环 / 挂点 / 首版实现三列均为「待登记」。
⇒ **给普通怪做 Blender 动作，是这条分页的首次落地**，要一并把这三列补上。

> ⚠️ 注意与玩家对照：玩家是 12 个**动作库**（`idle/moving/dashing/hurt/locked/falling/landing/dead`
> + `walking/armed_*`），敌人是 **12 个 AI 状态**。两套 ID 不同名，不能照抄玩家的动作表。

**骨架底座**：41 骨、Mixamo 式人形命名，且**网格已刷 30 个顶点组**（重命名后仍与骨名逐一对上）。
做动作前要有意识地决定：是直接驱动这套人形骨架，还是重定向到更像小菌猪的骨架。
（注意：模型当前是 **T-pose**，属"参考姿势"而非"玩法站姿"。）

## 尺寸归一执行记录（2026-09-20）

脚本 `_scratch/xiaojunzhu_intake/scale_to_target.py`；日志 `scale_to_target.log`。

| 项 | 值 |
|---|---|
| 目标显示高度 | 1.300 m |
| 目标源高度 | 1.300 / 0.70 = **1.857143 m** |
| 缩放前高度 | 0.999512 m |
| **缩放系数** | **×1.85804878** |
| 缩放后包围盒 | X **0.9535** / Y **1.2819** / Z **1.8571** m（⚠️ 这是朝向修复**前**的值；修复后 X/Y 互换） |
| 脚底 | min Z = 0.000000（仍贴地） |
| 对象级 scale | 全部 1.0（**无隐藏缩放**） |

做法：等比缩放**网格顶点**（2278 个）与**骨架编辑骨**（41 根），都绕世界原点；
不写对象级 scale，导出后源文件即真实尺寸。缩放前快照留在
`_scratch/xiaojunzhu_intake/pre_scale/enm_melee_fungboar01_model_v001.pre_scale.blend`
（sha256 `d359548c…9566b`），回滚只需覆盖回来。

**↳ 之后又做了朝向归正**（见上节），最终包围盒为
**X 1.2819 / Y 0.9535 / Z 1.8571**。朝向修复前的快照另一份留在
`_scratch/xiaojunzhu_intake/pre_orient/enm_melee_fungboar01_model_v001.pre_orient.blend`
（sha256 `de58a869…446c9`）。**两个快照叠加 = 可精确回到任意中间态。**

审计快照（`--factory-startup` 重开复核）：

| 项 | 值 |
|---|---|
| 单位 | `METRIC`，`scale_length = 1.0` |
| 网格 | 2278 verts / 4552 polys / 1 材质 / UV 层 `UVMap` / 无形变键 |
| 骨架 | **41 骨，人形 Mixamo 式命名**（`Hip/Pelvis/Spine01-02/Waist/Neck/Head` + `Clavicle/Upperarm/Forearm/Hand` + `Thigh/Calf/Foot/ToeBase`，各段含 Twist） |
| 绑定 | 单个 `Armature` 修改器，30 个顶点组 |
| 贴图 | 2048×2048，sRGB，外链未打包；**仅 basecolor，无法线 / 粗糙度 / 金属度贴图**（见下） |
| UV | 单层 `UVMap`，覆盖 `u=[0,1]` `v=[0,1]` 完整 0–1 空间，无越界 |

### 贴图现状：只有一张 basecolor

Tripo 只交付了 `…_basecolor.JPEG`。`enm_melee_fungboar01_mat` 的标准做法节点里有一个
**`NORMAL_MAP` 节点但未接线**（没有法线贴图可用），材质 `Roughness` 用常量 0.9。

⇒ 若要在游戏里保住表面细节，需要**补烘法线贴图**（或接受纯色平光）。
这是"模型 + 贴图核对"里唯一还没闭合的一项。

## 预览图（previews/）

| 文件 | 内容 |
|---|---|
| `enm_melee_fungboar01_front_v001.png` | 正面（cam +Y） |
| `enm_melee_fungboar01_side_v001.png` | 侧面（cam +X） |
| `enm_melee_fungboar01_top_v001.png` | 顶视（可见双臂 T-pose 沿 X） |
| `enm_melee_fungboar01_three_quarter_v001.png` | 三分之四视角 |
| `enm_melee_fungboar01_orientation_before_v001.png` | **朝向修复前**六机位对照（可看出原为 +X） |
| `enm_melee_fungboar01_orientation_after_v001.png` | **朝向修复后**六机位对照（+Y = 正脸） |

渲染口径：Cycles CPU 64spp，**按 `Enemy3D` 的 0.70 展示倍率渲染**，
画面里左侧蓝柱 = 玩家游戏内 1.20 m 参照，用于肉眼校尺寸。
渲染脚本 `_scratch/xiaojunzhu_intake/preview_and_anim_audit.py`（只读，不保存 blend）。

## 换模型必须同步的表（改外观不改这两处 = 静默出错）

1. `src/enemy3d/EnemyAvatar3D.gd` → `FOOTPRINT_PROFILES`（radius / height）
   被 `Enemy3D.gd:197-203` 直接读取生成 `CylinderShape3D`（受击 / 物理体积），
   `:381-386` 算头顶血条高度，`:1288` 算导航半径，`:1702-1704` 算出生点高度。

   ⚠️ 该表是**局部值**（要再 × 0.70 才是世界尺寸），且**当前值已与新模型不匹配**：

   | | radius | height |
   |---|---|---|
   | 现值（旧程序网格口径） | 1.02 → 世界 0.714 m | 1.30 → 世界 0.910 m |
   | 按新模型几何推出 | **0.641** → 世界 0.449 m | **1.857** → 世界 1.300 m |

   新模型横向最大半展 = max(X 0.9535, Y 1.2819) / 2 = **0.6410**（旧值 1.02 大 59%）。
   ⚠️ 这是**玩法数值**（命中判定体积），缩半径会明显提高闪避难度 ⇒ **不擅自改**，
   等主人拍板「按几何收紧 / 保持现有手感」。

2. `src/enemy3d/EnemyAvatar3D.gd` → `COLORS`
   程序网格回落色，与正式美术的色盘需要口径一致。

## runtime Prefab 必须具备的元数据（照精英先例）

`enm_elite_rift_boar_armed_root_top3d_v001.tscn` 是现有唯一完整先例，五条元数据：

```
metadata/asset_id         = "ENM-MELEE-FUNGBOAR01"
metadata/content_id       = "melee_chaser"
metadata/presentation_only = true
metadata/collision_owner  = "Enemy3D"
metadata/godot_forward    = "-Z"
```

Prefab 内只挂一个 `ImportedModel`（= 视觉 GLB），**不含碰撞、不含逻辑**。

## 台账行要从 2D 口径迁到 3D 口径

r6 现在仍是 2D 时代的字段：视角「侧面朝右（可水平翻转）」、组件槽 `root`、变体父ID 空、
规格「待定」、文件路径空、源码依据 `src/enemy/EnemyTypes.gd`。

3D 化后照精英行 r17 改：视角 → `Top3D / local -Z 正面`、组件槽 → `root_3d`、
变体父ID → `ENM-ECOSYSTEM-KIT-3D`、规格 → 真实包围盒、文件路径 → runtime tscn。

## 当前待补（按顺序做）

- [x] 模型 blend 落地 `source/model/`，贴图落地 `source/model/textures/`
- [x] **尺寸归一 → 源 1.857143 m（游戏内 1.30 m）**
- [x] **朝向归正 → 源 +X 已转到契约要求的 +Y**（`fix_orientation.py`）
- [x] 源级预览图（正面 / 侧面 / 顶视 / 三分之四 + 朝向前后对照）
- [ ] **补烘法线贴图**（当前只有 basecolor；不接受的话明确登记为「纯色平光」）
- [ ] **动画前置决策**：沿用这套 41 骨人形架，还是重定向到更贴合小菌猪的骨架
- [ ] 动作 blend 落地 `source/animation/`，与模型共享骨架 ID，
      按 12 态契约产出（`telegraph` 前摇必须可读、`attack` 判定帧对齐）
- [ ] 导出视觉 GLB 到 `components/`
- [ ] 生成 runtime Prefab 到 `runtime/`
- [ ] **代码侧前置**：`EnemyAvatar3D` 目前只给 Boss / 精英留了挂载函数
      （`configure_boss_content` / `configure_elite_content`），**普通怪没有对应函数**。
      需照 `configure_elite_content()` 的形态新增 `configure_enemy_content(kind, asset_id, scene_path)`，
      并在 `Enemy3D.configure_from_enemy_data()`（现第 269 / 277 行两处内联 if）接入。
- [ ] 同步 `FOOTPRINT_PROFILES` / `COLORS`（数值见上，待拍板）
- [ ] 新建 / 更新验收场景（`tests/verification/`）
- [ ] 台账 r6 迁 3D 口径登记；《敌人动画与状态》r21 补 循环 / 挂点 / 首版实现 三列

## 参考

- 同域最近先例：`assets/art/enemies/elite_3d/rift_boar_armed/`
- 全链路状态矩阵：`docs/v0.1/development/2026-09-17_3D资产正式制成链路总表.md`（P0「建立第一只标准怪物」）
- 角色制作标准（模型 / 动作双 blend 口径）：`docs/v0.1/16.1_角色美术制作与动作导入流程.md`
- 技能：`game-character-model-pipeline`
