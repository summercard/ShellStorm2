# 胖子僵尸 2.1 · 原始蒙皮还原与待机修订（2026-11-16）

资产 `ENM-NORMAL-FAT-ZOMBIE21` / slug `enm_normal_fat_zombie21`。

## 0. 当前有效修订：v002 原始蒙皮，仅待机

**用户报告上一轮“完全扭曲”，否决重建蒙皮。下文 §1–§8 仅为被否决的 v001 历史，不再代表当前资产。撤销其中“动画质量合格”“移动动画验收通过”的结论；数值不变量不能代替视觉形变验收。**

用户最新要求：“还原蒙皮，用最早的版本制作动画，待机动画”。本次回到桌面最初 `胖子僵尸2.1.blend`；其 SHA-256 与首轮冻结副本一致：`4d3ec3423eea7641a0da67b33403016a4c97ff666832e9e80f6211d45165cab9`。桌面文件和两个正在打开的 Blender 未保存会话均未修改。

- 原 597 顶点、UV、1180 三角、41 骨父子与静止矩阵、29 顶点组所有权重、修改器与绑定/父逆矩阵逐项指纹完全一致。没有重绑、清权重、改骨、旋转或缩放源。
- 新骨架标识 `SKEL-FATZOMBIE21-ORIGINAL-001`，静止签名 `4931ec7ec3e7a2b0978d3cd69aafa99f511656b6c21d68bfb637de53ff29fc65`。原尺寸约 0.79834m、面向 +X 保留；2.2m 游戏目标与项目转向留给后续包装，不伪称已对齐。
- 只交付 `idle`：60fps、3.2秒，F0–F192（F192 为闭合键），播放 F0–F191。缓慢低幅呼吸、躯干左右摇摆约 ±1.65°，四肢不迈步。无骨缩放、Root 固定；原四肢静止坐标保留，仅躯干局部姿态变化。
- 独立重开双母版核对，并采样193帧：首尾逐顶点差 0；F0 对原静止形变差 0.000000085m；最大顶点运动 0.01768m；边长比例 0.9422–1.0765；最小三角面积比 0.9369；触地点最大水平漂移 0.0000706m。最低 z=-0.0001834m，在 0.5mm 容差内，**不称绝对零穿透**。
- GLB 仅41关节和1段 idle；独立回导9个相位，与源形变最大差 0.000000490m。源技术检查通过不等于 Godot 验收，更不替用户签视觉接受。

### 当前文件

- 模型：`art_source/enemies/normal_enemy_3d/fat_zombie21/source/model/enm_normal_fat_zombie21_model_v002.blend`
- 动作：`art_source/enemies/normal_enemy_3d/fat_zombie21/source/animation/enm_normal_fat_zombie21_animation_v002.blend`
- GLB：`assets/art/enemies/normal_enemy_3d/fat_zombie21/components/enm_normal_fat_zombie21/enm_normal_fat_zombie21_visual_top3d.glb`（稳定路径，SHA-256 `71af6e0a627c4b5aa68d602ef5968d15c76e415845317234227bd65d0367594a`）
- 清单/中转/源验收：同资产根 `enm_normal_fat_zombie21_{manifest,transfer_ledger,source_validation}_v002.json`。
- 连续三轮正侧双视角 MP4、GIF、极值对照及便于打开的独立母版副本：工程外 `ShellStorm2-work/outputs/2026-11-16_fatzombie_original_idle/`。
- 失败版与本次修改前文件：`ShellStorm2-backup/2026-11-16_1732_fatzombie_original_idle/`。旧源移出工程，不删原始桌面素材。
- 原始指纹、193帧验收、回导对照、账本逐格自证和门禁日志：`ShellStorm2-work/sessions/2026-11-16_1732_fatzombie_original_idle/`。

### 登记与边界

敌人账本仍是同一 AssetID、资产主表 r57；本次版本 v002，日志 v0.1.44，撤销前轮7动作/蒙皮视觉通过声明。当前状态保持 `exported_pending_godot_validation`，另标 `pending_user_visual_review`。不修改《敌人动画与状态》《3D-敌人》，不替换旧胖子僵尸03、不改玩法接线。当前源索引只增加本资产两份 v002 母版。其他资产基线和专表摘要不接纳历史漂移。

### v002 最终门禁（本次重跑）

- 原蒙皮独立回读、193帧形变专项、GLB9相位回导：退出0；不是只对制作脚本内部的同一份新权重自比。
- 账本原始OOXML最小格修订：H/I/M/N/P/T/V/Y57白名单，V57日期文本未变；追加日志r86/v0.1.44。其他已有业务格、公式、专表以及其余ZIP成员保持原样，避免编辑器整体重写派生列。基线仅更新本AssetID和7个批准变更列，其他资产及专表摘要完全不变。
- 资产结构门禁：退出1，17条问题与修改前集合相同，本资产无问题。
- 无损分账本门禁：退出1，24条失败与修改前集合相同，本资产无问题。
- 文档门禁：退出1，18条既有问题；CHANGELOG旧断链行号因顶部增加2行而偏移，目标集合不变，无新增断链。
- 运行资源命名、账本引用门禁：均退出0。
- 敌人域full门禁：退出1，未宣称全域通过；本资产无问题，登记文件8条哈希/大小逐一核对一致。
- 预览视频实测9.600秒，包含3个3.2秒循环。未做Godot播放、完整玩法状态或用户人工视觉签收。

**待完成**：用户连续动态确认；Godot 包装/真实播放；原尺寸/朝向的工程对齐；移动动作重新设计与制作（本次不做）。

---

# 以下为被否决的 v001 历史记录（非当前交付）

原骨架 `SKEL-FATZOMBIE21-001` 已停止使用。

---

## 1. 输入与决策

源素材：`C:\Users\zhuangmenghong\Desktop\新怪物模型\胖子僵尸\胖子僵尸2.1\胖子僵尸2.1.blend`
（Tripo 生成：单 mesh 597 顶点 / 1180 三角，1024² basecolor，41 骨 armature，原始源高 0.798m，面罩朝 +X）

原状的六项结构性缺陷（脚本实测，非目测）：

| # | 缺陷 | 原值 |
|---|---|---|
| 1 | 颈头链没接进头颅 | 合计 0.0256m，`Head` 骨长 0.0100m，距颅心 0.308m |
| 2 | 后腿没有可用的膝 | `L_Calf` 枢轴距髋仅 17% 肢长（应约 45%） |
| 3 | 8 根肢体骨只有半段长 | 骨长 ÷ 到子关节距离 = 精确 2.00 |
| 4 | 右后脚错位 | `L_Foot↔R_Foot` 镜像差 0.1138m（身高 14.3%） |
| 5 | 骨架整体与网格不贴合 | 表面到最近骨骼中位 0.163m（身高 20%），79% 顶点 >0.10m |
| 6 | roll 左右不一致 | `L_Hand` 138.89° vs `R_Hand` 61.35° |

**两个由主人拍板的前置决策（2026-11-16）**：

- **姿态基准：保持四足伏地**，不扶正为双足。理由：网格双腿水平后伸、双手触地，扶正需要重摆 597 顶点并重拟合关节，597 顶点低模在关节处会产生折痕与手部失形。
- **目标尺寸：对齐现有 2.2m 口径**（游戏站立高 2.2m / 显示缩放 0.7 / 源高 3.142857m）。

> ⚠ 后果需知：该模型是**四足爬行体**，与账本里旧 `ENM-NORMAL-FAT-ZOMBIE03`（双足直立）姿态不同，**动作不可互换**。

---

## 2. 骨架重建

网格顶点形状保持不变（只做整体旋转 + 等比缩放 + 重新绑定）。校验：逆变换回原坐标逐点比对 **597/597 通过，最大偏差 0.000000**。

| 项 | 处理 |
|---|---|
| 朝向 | 绕 Z **+90°**（+X 前 → +Y 前，符合项目「面罩朝 Blender +Y / Godot -Z」） |
| 尺寸 | ×3.936738，源高 **3.142857m** |
| Root | 改为竖直 0.5905m（原为横躺 0.2173m），保证根朝向与引擎约定一致 |
| 颈头链 | 沿「肩→颅心」前伸三等分：颈1/颈2/头 各 **0.1213m**，合计 **0.3638m**；`Head` 骨末端到达颅前 0.483 |
| 后腿膝 | 移到髋→踝的 **45%**：`(−0.1885, 0.1617, 0.1415)`；大腿 0.2341 / 小腿 0.2861 |
| 骨长 | 8 根肢体主骨改为全段长；twist 骨保留半段（父子链拼接成全段） |
| 左右 | 右半侧由左半侧**镜像生成**，镜像偏差 **0.000000** |
| roll | 统一 `align_roll(world+Z)`，左右镜像后同号 |

**验收（脚本断言）**：

- 主骨骨长 = 到子关节距离，比值 **1.000**（8/8）
- 左右镜像 `|d_head|` / `|d_tail|` 全部 **0.000000**
- 骨骼数 41，骨名与精英 `arms_taker` **完全同名同构**（可直接做静止姿态转换后复用其剪辑）

---

## 3. 蒙皮

放弃了 Blender 的 `ARMATURE_AUTO`（bone heat）。实测它把 `Head` 权重撒到整个背部气罐：
70 个非头部顶点拿到最高 0.67 的 `Head` 权重，转 `Head` 45° 时背部被甩出 **2.56m**。

改为**解析权重**：`w_i ∝ k_i / (d_i + 0.05)^4`，其中 `k_i` 为 twist 骨抑制系数 0.30；

- 左右硬分侧：`L_*` 只许在 −X、`R_*` 只许在 +X（容差 0.03）
- 头部顶点（y>1.40）只许颈头链；颈部过渡区（y>0.90）许颈头链 + 上脊椎
- 沿网格邻接平滑 2 轮（0.55 自留 + 0.45 邻域），每轮后重新施加区域硬约束
- 掌部硬化：后掌（25 顶点）Foot+ToeBase 占 0.90，前掌（17 顶点）Hand 占 0.92 —— 否则膝肘一弯掌面就被拖着沉
- top-4 归一

**验收**：

| 指标 | 结果 |
|---|---|
| 未加权顶点 | **0 / 597** |
| 每顶点最大影响 | **4** |
| 权重和 | min 0.999999 / max 1.000001 |
| 左右串权（w>0.03） | **0 组** |
| `Head` 转 45° 带动头颅 | 最大位移 **0.3948m = 身高 12.6%**（原 0.020m） |
| 弯膝 45° 该侧足部 | 41 顶点移动，最大 **0.9876m** |

---

## 4. 动作：四足移动 7 段

30fps / F0 起 / Root 固定 / 非 Root 骨 Scale 恒 1 / 循环动作在 Fn 放闭合键。

| 剪辑 | 帧 | 时长 | 循环 | 步态相位（LH/LF/RH/RF） | 占空比 |
|---|---|---|---|---|---|
| `idle` | 0–96 | 3.200s | ✅ | — | — |
| `walking` | 0–30 | 1.000s | ✅ | 0.00 / 0.25 / 0.50 / 0.75（侧序） | 0.75 |
| `running` | 0–16 | 0.533s | ✅ | 0.00 / 0.18 / 0.50 / 0.68（侧序） | 0.60 |
| `move_start` | 0–12 | 0.400s | 单次 | 接 walking F0 | — |
| `move_stop` | 0–18 | 0.600s | 单次 | 回 idle | — |
| `turn_l` | 0–24 | 0.800s | 单次 | 抬左脚换脚 | — |
| `turn_r` | 0–24 | 0.800s | 单次 | 抬右脚换脚 | — |

### 4.1 左右摇晃（重量感）的承载方式

这是本轮最关键的设计约束，由两条实测几何事实逼出来：

1. **后腿 rest 伸展率 100%**（膝角 180.00°）—— 髋部一抬升，后足就离地够不着；且向后行程 **0.000m**，后脚只能从**前方**起踏、向后推到 rest。
2. **腹部最低 z=0.03 且横跨 ±1.6m** —— 髋部一侧倾，腹部立刻穿地。

因此：

- **髋只做水平侧移，不做竖直抬升、不做侧倾**。动作内用 `BASE_OFF` 把后脚整体前移 0.415m 换出步伐空间。
- **侧移由支撑状态驱动，不是正弦**：`hip_dx = −sway × net`，`net = (左支撑权重−右支撑权重)/2`，支撑权重在起落时做 0.12 周期的平滑过渡。这样重心移动与真实落脚同步。
- **重量感全部由 Waist 以上承载**：侧倾 4.0°/5.8°（walk/run）、偏航 4.6°/7.0°，逐级滞后 0.018/0.036/0.054/0.072/0.090/0.108 周期、幅度递减到 0.08 倍，颈头再加反向稳定把视线拉回。

**实测摇晃幅度（背甲顶点群质心，源空间）**：

| 剪辑 | X 摆幅 | 占体宽 | Z 起伏 | 头相对背甲滞后 |
|---|---|---|---|---|
| `walking` | 0.317 m | 8.5% | 0.092 m | 0.182 m |
| `running` | 0.636 m | 17.0% | 0.146 m | 0.258 m |
| `idle` | 0.089 m | 2.4% | 0.092 m | 0.035 m |

（换算到游戏显示空间除以 1.4286：walking 0.222m / running 0.445m / idle 0.062m。）

> 设计取舍：`running` 原用对角步态（trot），会让左右支撑权重恒等、**完全没有左右摇晃**；已改侧序步态。

### 4.2 贴地

用「逐帧迭代抬升四条肢的 IK 目标」钳制（抬 Hip 无效：脚是绝对 IK 目标，不会被带着走）。

7 段全部 **zmin ≥ +0.00050 m**（源空间，等于显示 0.35mm 以上正余量），无穿透。

### 4.3 步态真实度

| 剪辑 | 四足踩实率 | 占空比 | 支撑相逐帧后移 |
|---|---|---|---|
| `walking` | 24/31 = **77%** | 0.75 | 每帧 0.0169 |
| `running` | 11/17 = **65%** | 0.60 | 每帧 0.0396 |
| `idle` | **100%** | 1.00 | — |

踩实率与占空比吻合，说明摆动/支撑切换正确，没有「假装踩地」。

### 4.4 自然速度

| 剪辑 | 步幅 | 周期 | 源空间 | 显示空间 |
|---|---|---|---|---|
| `walking` | 0.38 m | 1.000s | 0.380 m/s | **0.266 m/s** |
| `running` | 0.38 m | 0.533s | 0.713 m/s | **0.499 m/s** |

较旧胖子僵尸口径（巡逻 0.30 / 追击 0.60）偏低：四足体步幅受限（后腿伸展 100%、不能向后迈），
若玩法要求 0.30/0.60，需**提高播放倍率**（walking ×1.13、running ×1.20，仍在 0.85–1.15 与 1.2 区间边缘），
或加大 `BASE_OFF` 换取更长步幅并重跑验收。**本轮未擅自改玩法速度**。

---

## 5. 交付物

### 制作源（`art_source/`）

```
art_source/enemies/normal_enemy_3d/fat_zombie21/
├─ source/.gdignore
├─ source/model/enm_normal_fat_zombie21_model_v001.blend        ← 模型母版
├─ source/model/textures/enm_normal_fat_zombie21_basecolor_v001.jpg
└─ source/animation/enm_normal_fat_zombie21_animation_v001.blend ← 动作母版
```

双母版**骨架签名一致**：`cc58abd4f2823e33335ca20458b2601f45ba8d967bb461876e6f687532372fda`
几何指纹：`2da28da4e23998bb188d183dcd86aec385bd2d8989144ff7b534a394825921bd`

### 运行资产（`assets/art/`）

```
assets/art/enemies/normal_enemy_3d/fat_zombie21/
├─ components/enm_normal_fat_zombie21/enm_normal_fat_zombie21_visual_top3d.glb   (737.6 KB)
├─ enm_normal_fat_zombie21_manifest_v001.json
├─ enm_normal_fat_zombie21_transfer_ledger_v001.json
└─ previews/enm_normal_fat_zombie21_{front,side,back,top,overview}_v001.png
```

GLB SHA-256 `92a2b793baed68a274975f5046014e3be888c62041edcd364fad19063d5b564f`
GLB 内容：1 mesh（JOINTS_0 / WEIGHTS_0 / NORMAL / POSITION / TEXCOORD_0）、1 skin **41 joints**、**7 animations**、1 material、1 embedded jpeg。

### 账本

`assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx` **资产主表 r57**

- AssetID `ENM-NORMAL-FAT-ZOMBIE21`，子类 `normal`，逻辑ID `fat_zombie21`，变体父 `ENM-ECOSYSTEM-KIT-3D`
- 制作状态 `exported_pending_godot_validation`（S2 出口；S3/S4/S5 未做）
- 域变更日志 r85 **v0.1.43**
- 无损基线：只补本 AssetID 指纹，`asset_count` 1459 → 1460

---

## 6. 门禁结果（退出码单独捕获）

| 门禁 | 退出码 | 说明 |
|---|---|---|
| `check_asset_registry.py --scope structure` | 1 | 17 条既有红项：scenes r987/988/989/997/1010（AssetID 前缀 + 分类写成路径）、enemies r55 `开发中（partial）`、vfx r62。**反向对照：改前 17 条、改后 17 条，逐条集合全同；新资产不在其中** |
| `check_asset_registry.py --scope full --ledger enemies` | 1 | 同上 + 既有 `sha_mismatch`（与本次无关） |
| `verify_ledger_split.py` | 1 | `failure_count=24`（row_content_mutated 8 / category_mutated 5 / category_outside_ledger 5 / moved_sheet_mutated 4 / asset_not_in_baseline 2）。**反向对照：改前 24 条、改后 24 条，逐条 kind+asset 集合全同；`missing_assets=0`、`column_digest_drift=0`；`baseline_assets` 1459→1460 恰为本行** |
| `check_asset_runtime_naming.py` | **0** | `ASSET_RUNTIME_NAMING_OK` |
| `check_ledger_refs.py` | **0** | `LEDGER_REFS_OK pending=0` |
| `check_documentation_contracts.py` | 1 | 18 条全为既有/并行会话问题（缺 `2026-11-16_expedition01_combat_feel.md`、`verify_projectile_enchant_visuals` 未登记、ui 行数 21→23）。**grep 本资产 0 命中** |

反向对照做法：把账本与基线换回 `.bak_before_fatzombie21_20261116` 跑同一门禁，比对后 `finally` 恢复并校验 sha 一致。

> 基线自证：**不含新行重算的 23 列列指纹与存量基线 23/23 完全一致**，证明重算方法未偏离既有口径；
> 含新行后 `category_counts` 变化恰为 `{'敌人': (51, 52)}`。

---

## 7. 未完成（不得当作已接入）

1. **S3 Godot 导入与 PackedScene 包装** —— 无 `.tscn`，故《3D-敌人》分页未加行（该分页要求「一行 = 一个实际存在的 PackedScene」）。
2. **S4 Enemy3D 12 态映射接线** —— 当前只有 7 段移动动作，`dormant/alert/chase/search/return/telegraph/attack/recovery/stagger/dead` 未映射；`hit_light` 局部叠加未做。
3. **S5 专项验收与真实渲染** —— 只在 Blender 源侧验收，未在 Godot 内跑状态流/渲染。
4. **替换 `ENM-NORMAL-FAT-ZOMBIE03`** —— 按主人指示「回头需要替换」，本轮**未改动**旧行、旧 Prefab、运行时接线、旧模型/动作哈希。替换前须重做 S3/S4/S5，且需确认四足体与既有碰撞柱、血条高度、镜头构图兼容。
5. **攻击与死亡动作** —— `attack`（抱扑）、`hurt`、`dead` 未做；旧胖子僵尸设计文档里的 13 段规格不适用于四足体几何（后腿不能向后迈、腹部贴地不能压扁接地）。
6. 网格 2 处开放边界（背部气罐接缝，18 条边界边）未补面。

---

## 8. 后续替换旧资产时的硬约束（写下来，避免下次重新踩）

1. **后腿不能向后迈**：rest 伸展 100%，`BASE_OFF` 已前移 0.415m。任何「后脚向后蹬」的设计都会立刻被 IK 钳制。
2. **髋不能抬升、不能侧倾**：腹部 z=0.03 且 ±1.6m 宽，两者都会穿地。重量感只能放 Waist 以上。
3. **脚掌在支撑相必须保持水平**（`foot_follow=0`）。让脚掌跟随小腿会把掌面拖低 1–2cm。
4. **掌部权重必须硬化**（Foot+ToeBase ≥0.90 / Hand ≥0.92），否则膝肘弯曲时掌面漂移。
5. **不能用 bone heat**：会把 `Head` 权重撒到背部气罐。
6. **动作不可与旧胖子僵尸互换**（四足 vs 双足）。
