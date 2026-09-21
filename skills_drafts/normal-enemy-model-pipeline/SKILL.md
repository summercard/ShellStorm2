---
name: normal-enemy-model-pipeline
description: 为 ShellStorm2 制作、替换或验收「普通怪」（normal_melee / normal_ranged / normal_summoner / normal_tank / normal_bomber / normal_ambusher 等已预登记的 7 类原型）的 3D 表现资产——从既有 AssetID 取契约、按 0.70 展示倍率归一尺寸、做 Blender 六段动作母版、导出视觉 GLB、组装 runtime PackedScene 与表现脚本、把 12 态 AI 映射到 6 段剪辑、接上玩法侧 6 处挂载点、跑验收场景并完成账本转正。不用于精英与 Boss（走 game-character-model-pipeline），也不用于武器、道具或场景设施。
agent_created: true
---

# 普通怪模型制作与导入（ShellStorm2）

先证明既有运行时契约，再动 Blender 文件或写挂载代码。普通怪是**唯一一类没有 `configure_*_content()` 函数**的敌人：它的正式表现由 `EnemyAvatar3D._rebuild()` 里的常量分支自动挂载，所以「漏接线」不会报错，只会静默显示旧程序网格。

处理 ShellStorm2 时先读项目 `docs/v0.1/development/2026-09-20_普通怪物制作与导入流程.md`；上游标准是 `docs/v0.1/16.1_角色美术制作与动作导入流程.md`（模型 / 动作双 blend 口径，怪物同源）。项目专属数值、6 处接线位置与实测证据见 [references/shellstorm2-normal-enemy-contract.md](references/shellstorm2-normal-enemy-contract.md)。

## 边界

- 适用：普通怪 7 类原型的 3D 表现包 —— 视觉 GLB、runtime PackedScene、表现脚本、动作母版、12 态 → 6 剪辑映射、玩法侧接线、账本行转正。
- 不适用：精英与 Boss（有 `configure_elite_content()` / `configure_boss_content()` 显式挂载函数，走 `game-character-model-pipeline`）；武器走 `game-weapon-model-pipeline`；道具走 `game-prop-model-pipeline`；场景与设施走环境 / 设施两套 skill。
- 表现包只提供视觉与动作。AI、生命、伤害、掉落、碰撞与刷怪全部归 `Enemy3D`，本链路一行都不改。

## 一句话链路

```text
设计位「7 类普通怪之一」
  → 母版 / Tripo 源入库
  → 尺寸归一（源高 = 展示高 / 0.70）
  → 朝向归正（数据层，Blender +Y 前向）
  → 源级预览（六机位 + 倍率 + 玩家参照）
  → 动作专用 blend（6 段剪辑）
  → 视觉 GLB（无版本号）
  → runtime PackedScene（表现包装 + 5 条 metadata）
  → 表现脚本（12 个 AI 状态 → 6 段剪辑）
  → 玩法侧接线（6 处，漏一处即静默失效）
  → 验收场景（含反向对照）
  → 账本转正（主表迁 3D 口径 + 动画分页补列 + 中转 JSON 推进）
```

比角色链路**多两段**，也是最容易漏的两段：**12 态 AI → 剪辑映射**，以及**玩法侧接线**。

## 四个必须一次记死的数字

| 项 | 值 | 出处 |
|---|---|---|
| 全局展示倍率 | 0.70 | `Enemy3D.gd` `DEFAULT_BASE_SIZE_MULTIPLIER` |
| 源文件高 | 展示高 / 0.70 | 由目标反推 |
| 游戏内高 | 比玩家大一点（ShellStorm2 当前 1.300 m，玩家 1.200 m） | 验收场景硬断言 |
| 玩家参照 | 1.500 m × 0.80 = 1.200 m | 玩家资产验收 |

游戏内尺寸 = 源尺寸 × 0.70 × kind 倍率 × variant 倍率。`Avatar` 与 `CollisionShape3D` 都是 `Enemy3D` 的直接子节点，**两者一起吃这个倍率**。直接把源文件做成目标游戏内尺寸会得到更小的结果，方向反了。

## 目录契约（三段式）

```text
assets/art/enemies/normal_enemy_3d/<logic_id>/
├── source/        ← Blender 原始文件（唯一允许 _vNNN 的地方）+ 单个 CRLF 空行的 .gdignore
│   ├── model/     ← 模型 blend + textures/
│   └── animation/ ← 动作 blend（与模型共享骨架 ID）
├── components/    ← 视觉 GLB（运行路径，不带版本号）
├── runtime/       ← PackedScene + 表现脚本 + 中转 JSON
└── previews/      ← 源级核对渲染图（PNG，不受命名门禁约束）
```

- 命名前缀 = AssetID 去尾 `-3D` 后全小写、`-` 转 `_`。
- `source/**` 带 `_vNNN`；`components/**`、`runtime/**` **不带**。运行资产替换 = 覆盖同路径同名文件，`.import` / `.uid` 留原位。
- 门禁：`python scripts/check_asset_runtime_naming.py`。

## 阶段明细

每段格式：做什么 / 判据 / 坑。

### S0 定位与身份

- 从《资产主表》取该怪既有 AssetID / 逻辑 ID / 子类，确认是**升级既有行**。
- 坑：7 类普通怪的 AssetID 已全部预登记 ⇒ 新增 = 撞 `duplicate_asset_id`。逻辑 ID 同时被 `Enemy3D.PROFILES`、`FOOTPRINT_PROFILES`、`COLORS`、`MonsterInjector.BASE_ENEMY_TYPES`、`EliteContentCatalog.base_enemy_id` 引用，改名要全库搜。

### S1 源入库

- 模型 blend + 贴图落 `source/model/`，做**内部改名**（Armature / Mesh / 材质 / image），删 0 引用空壳材质；母版自带的中间格式（.fbx）不纳入。
- 坑：母版文件名可能是错的（拼写错误），**只改入库副本，不动桌面原件**。

### S2 尺寸归一

- 等比缩放**网格顶点 + 骨架编辑骨**（绕世界原点），**不写对象级 scale**。
- 判据：脚底 min Z = 0；对象级 rot = 0 / scale = 1.0（无隐藏缩放）。

### S3 朝向归正

- 绕世界 Z 轴旋转，作用在**数据层**（顶点 + 编辑骨，先快照 `edit_bone.matrix` 再整体左乘 R）。
- 判据：六机位渲染图肉眼判 —— 契约前向（ShellStorm2 = Blender **+Y**）看是完整正脸，反向看是后脑勺。
- 坑：判据只能是渲染图，**不要用旋转表反推**；blend 里已有 Action 时必须先做动画重定向。

### S3b 外部已绑定骨架重定向到契约（要求"不改绑定/蒙皮"时用）

外部给来一套**已绑好蒙皮的骨架**（Tripo / Mixamo 产物等），要求"保持原绑定、只对齐契约"时走这条路径；
**不要**套 §S1 的"换成自己的骨架"，也不要重算骨架数据或重新分权重。

- 只做三件事：①骨名 + 顶点组 **1:1 改名**（Armature Modifier 按名字匹配，两者必须同步）；②朝向 / 缩放对**骨与网格施加同一个变换**（作用在数据层，不写对象级 scale）；③补契约缺失的根骨（如 `Root`：head 世界原点、挂到 `Hip` 之上，父级必须是 None）。
- ⇒ "保持蒙皮"按定义成立：没动权重、没动骨架数据、没重算绑定，只是换名字 + 换坐标系。
- 骨名映射要分两张表：契约骨进 `BONE_MAP`，非契约的中间骨（Twist / `*3` `*4` 指骨 / ToeBase / HeadTop_End）进 `EXTRA_MAP` 保留可辨识名，**别让它们撞上契约名**。
- 动画重定向公式（**方向别写反**，写反会产生 80~141° 系统性偏差，容易误判成"重定向失败"）：
  `M_t = M_s @ R_s⁻¹ @ R_t`，其中 `R = matrix_local.to_3x3()`。先解出源姿态相对源静止的局部旋转，再乘目标静止旋转。
- ⛔ **全身位移必须显式搬**：若源动作把位移放在 `Hip`（根骨无动画），而目标 `Hip` 的父骨**不是 None**，把位移搬运写在 `parent is None` 分支里 ⇒ **永不执行**，静默丢掉走路起伏 / 倒地后滑。
  判据：`hip_path_err_m == 源 hip_travel_m`（目标位移恒 0）即命中本坑。
- 保真判据用 **Δ = M_pose · R_rest⁻¹ 逐帧一致**（本路径 Δ_t ≡ Δ_s，实测可到 0.0000°）；
  **不要**用骨指向轴（bone Y 方向角）——两套骨架静止 roll 常差 ~90°，轴指向必然有差，会把正常静止差误读成重定向失败。
- 源数据自带"无顶点组的骨"（如 `*4` 指尖骨、`Toe_End`）先回查**原始 FBX** 是否本就如此；是则属源特性、非本次引入，别当缺陷去"修"，但要在报告里说明。
- 验收补三件：局部性探针（旋转单骨，被移动顶点须落在该骨主导组内）、自运动幅度（防动作被冻成静态帧）、持枪/变体剪辑与基础剪辑的逐骨差（防占位复制，但**位移差异也要看**，不要只比旋转）。

### S4 源级预览

- 正 / 侧 / 顶 / 三分之四 + 朝向**前后六机位对照**，按展示倍率渲染，画面里放玩家游戏内高度参照柱。

### S5 动作源（6 段剪辑）

- 新建 `source/animation/<前缀>_animation_vNNN.blend`，与模型**共享骨架 ID / 骨名 / 父子关系 / 静止姿势 / 单位**；导出前重算两文件骨架签名，差异先修。
- 30 fps 六段：idle / walking / running / attack / hurt / dead；前三段循环，后三段单次末帧保持。
- 坑：源模型通常**不含任何动画数据**（纯静态 T-pose），动作必须从零做；**不要把时间轴自动回到开头误认作死亡循环**。

### S6 导出视觉 GLB

- 二进制 `.glb` 到 `components/`，只含视觉网格 + 验证过的骨架 + 动画；展示地面 / 相机 / 灯光 / 碰撞体不进包。
- 判据：Godot 导入后核对**骨骼数与动画数**，以及每段时长与循环标记。
- 坑：文件名**不带版本号**。

### S7 runtime PackedScene

- `runtime/<前缀>_root_top3d.tscn`，根 = `Node3D` + 表现脚本，子 = 一个视觉 GLB 实例。**不含碰撞、不含逻辑**。
- **必须在 Prefab 根写齐 5 条 metadata**（照同域精英先例）：`metadata/asset_id` / `metadata/content_id` / `metadata/presentation_only = true` / `metadata/collision_owner = "Enemy3D"` / `metadata/godot_forward = "-Z"`。
- 另产 `runtime/character_transfer_ledger.json`（中转记录：模型 / 动作源路径与哈希、骨架签名、各剪辑时长与循环、输出哈希、回滚位置）。
- 门禁：`python scripts/asset_guard.py <包目录> --classify <reuse|replacement|version_increment|child_variant>`。
- 坑：中转 JSON 状态按 `authored → exported_pending_godot_validation → validated → active` 推进；**源或输出哈希一变就退回重验**。

### S8 表现脚本（12 态 → 6 剪辑）

- `<logic_id>_formal_visual.gd` 把 12 个 AI 状态映射到 6 段剪辑，提供 `sync_state()` / 命中闪白 / `get_presentation_snapshot()` 接口。
- 坑：`AnimationPlayer` 要设 `callback_mode_process = MANUAL`，由 `seek` 驱动，避免和玩法状态机抢时序；受击闪白要**复制材质**再改 `emission`；非硬直受击只覆盖表现，**不延迟攻击与伤害事件**。

### S9 玩法侧接线

见「玩法侧接线」一节（6 处，逐条）。**这是本 skill 相对角色链路独有的部分。**

### S10 验收

- 新建 `tests/verification/verify_<logic_id>_presentation.gd/.tscn`，用**通用敌人预制体** + `configure_from_enemy_data({"enemy_type": "<logic_id>"})` 驱动，断言：
  - 正式包装已挂载且组件数为 2；
  - **碰撞未变**（「美术接入不动玩法」的证据）；
  - 六段剪辑齐全且时长误差小；
  - 12 个状态逐个 `sync_presentation`，状态透传正确；
  - **结构性断言**：走路剪辑只能出现在 `patrol`；
  - **反向对照**：低速追击仍必须是跑步、高速巡逻仍必须是走路；
  - 攻击前摇 → 命中边界采样连续；死亡立即退组、不被压扁、按表现时长回收；
  - 精英带 `is_elite` 时**不叠加**普通怪表现。
- 跑法：`--headless --path . res://tests/verification/<场景>.tscn`，再 grep `*_OK` + `ERROR`；**不看裸退出码**。
- 纪律：新断言必须做一次**反向对照**（改坏 → 变红 → 还原）。
- 坑：语义失败标记多由 `printerr()` 打、**无 `ERROR:` 前缀**，`grep '^ERROR'` 会漏 —— 先找自打标记，再数 ERROR。

### S11 账本转正

1. 《资产主表》该怪行从 **2D 口径迁到 3D 口径**（组件槽 `root` → `root_3d`、变体父 ID → 生态根、视角 → `Top3D / local -Z 正面`、规格 → 真实包围盒、文件路径 → runtime tscn、SHA-256、源码依据 → 模型 + 动作双 blend）。
2. 《敌人动画与状态》补「动作来源 / 循环 / 挂点 / 首版实现」列 + 条目行。
3. 《3D-敌人》新增该 Prefab 行。
4. 中转 JSON 状态推进到 `active`。

- 写完必查：`python scripts/check_asset_registry.py --ledger 敌人`。
- 坑：**不要碰派生列 R / S 的公式**；`assets/registry/ledger_index.json` 是域 / 文件映射的唯一真源，不得写死账本文件名；改 xlsx 前先做 **openpyxl 保真往返测试**（防丢 table / dataValidation / mergedCell）。

## 状态 → 剪辑映射（普通怪口径）

12 态逐字取自 `src/enemy3d/Enemy3D.gd` 的 `VALID_STATES`。

| # | 状态 | 剪辑 | 说明 |
|---|---|---|---|
| 1 | `dormant` | `idle` | 采样钉在 0 |
| 2 | `idle` | `idle` | 循环 |
| 3 | `patrol` | **`walking`** | **唯一使用走路的移动状态** |
| 4 | `alert` | `idle` | |
| 5 | `chase` | **`running`** | 朝玩家接近 |
| 6 | `search` | **`running`** | 朝最后已知位置 |
| 7 | `return` | **`running`** | 归巡逻点 |
| 8 | `telegraph` | `attack` | 采样到 `length × 0.48 × 进度` |
| 9 | `attack` | `attack` | 钉在 `length × 0.48`（判定帧） |
| 10 | `recovery` | `attack` | 从 0.48 → 1.0 线性 |
| 11 | `stagger` | `hurt` | 按硬直时长采样 |
| 12 | `dead` | `dead` | 按 `state_time` 采样，上限 = 剪辑长 |

**两条硬规则**：

1. **走路只服务巡逻**。只要朝玩家方向移动（追击 / 搜寻 / 归位）**一律跑步**。
2. **选段由状态唯一决定，不按实际速度切档** —— 否则同一状态会在快慢档之间抖动。

`sync_state()` 的 `speed` 形参仍按契约留在参数位（调用方按顺序传），但**不参与选段**。

## 玩法侧接线（6 处，漏一处即静默失效）

精英 / Boss 有 `configure_elite_content()` / `configure_boss_content()` 显式函数；**普通怪没有对应函数**，是 `_rebuild()` 里的常量分支自动加载。

| # | 位置 | 作用 | 漏了会怎样 |
|---|---|---|---|
| 1 | `EnemyAvatar3D` 的 FORMAL_* 常量（kind / 场景路径 / 视觉高度） | 逻辑 ID、Prefab 路径、视觉高度 | 找不到包 |
| 2 | `_rebuild()` 末尾 `if enemy_kind == <常量>` 分支 | 挂载正式包装并隐藏旧程序化壳 / 核 / 附肢 | 仍显示程序化网格 |
| 3 | `sync_presentation()` | 把状态转发给表现脚本 | 模型静止不动 |
| 4 | `get_component_snapshot()` | 报 2 组件（骨骼模型 + 状态特效） | 验收数量对不上 |
| 5 | `Enemy3D.configure_from_enemy_data()` | 显示名迁移 + 精英互斥 | 旧存档名字错、精英叠双模型 |
| 6 | `Enemy3D._die()` | 正式普通怪走表现回收；否则走压扁 | 死亡立刻压扁，看不到倒地动画 |

配套必须同批改（**改外观不改这两处 = 静默出错**）：

- `FOOTPRINT_PROFILES` —— 受击 / 物理 `CylinderShape3D`、头顶血条高度、导航半径、出生点高度都读它。它是**局部值**（还要 × 0.70 才是世界尺寸），且是**玩法数值**（命中判定体积）⇒ 收紧会明显改手感，**改前须拍板**。
- `COLORS` —— 程序网格回落色。

另：刷怪唯一入口是 `Dungeon3D._spawn_room_enemies()`，敌人挂 `$ActiveEnemies`；`MonsterInjector.BASE_ENEMY_TYPES` 是 2D 侧名称 / 数值表，也是同名逻辑 ID 的消费者。

## 门禁与验收

| 门禁 | 命令 |
|---|---|
| 运行时命名 | `python scripts/check_asset_runtime_naming.py` |
| 资产归类 / 查重 | `python scripts/asset_guard.py <包目录> --classify <类型>` |
| 账本结构 | `python scripts/check_asset_registry.py --ledger 敌人` |
| 专项验收 | `--headless --path . res://tests/verification/verify_<logic_id>_presentation.tscn` |
| 全链路回归 | `verify_full_3d_game_flow`、`verify_first_elite_deployment_flow` |

判定纪律：**红项 ⊆ 基线 ∪ 本次有意变更才算过**（逐项比对 marker 数）；不看裸退出码。既有红项必须用**改动前的同一资产**做基线对照，别直接声称无关。

## 复制到其余 6 类的 checklist

- [ ] S0 从主表取 AssetID / 逻辑 ID / 子类，确认升级既有行
- [ ] S1 源入库 + 内部改名 + 放 `.gdignore`
- [ ] S2 尺寸归一（源高 = 展示高 / 0.70，脚底贴地，无对象级 scale）
- [ ] S3 朝向归正 + 六机位渲染图判据
- [ ] S4 `previews/` 四机位 + 前后对照 + 玩家参照柱
- [ ] S5 动作 blend：六段、共享骨架 ID、骨架签名与模型一致
- [ ] S6 导出视觉 GLB（无版本号）+ 核对骨骼数 / 动画数
- [ ] S7 runtime Prefab（**含 5 条 metadata**）+ 表现脚本 + 中转 JSON
- [ ] S8 选段规则（走路只服务巡逻，选段由状态唯一决定）
- [ ] S9 6 处接线；逻辑 ID 变更时把 `_rebuild()` 的分支按 kind 扩展，**别再堆 if**
- [ ] S10 验收场景 + **反向对照**（走路越界 / 低速追击 / 高速巡逻）
- [ ] S11 主表迁 3D 口径 + 动画分页补列 + `check_asset_registry.py`
- [ ] 跑 `check_asset_runtime_naming.py`，确认没新增带版本引用

## 参考

- 项目流程文档：`docs/v0.1/development/2026-09-20_普通怪物制作与导入流程.md`
- 资产包自述样板：`assets/art/enemies/normal_enemy_3d/melee_chaser/README.md`
- 同域先例（精英，结构更简）：`assets/art/enemies/elite_3d/rift_boar_armed/`
- 角色制作标准（模型 / 动作双 blend 口径）：`docs/v0.1/16.1_角色美术制作与动作导入流程.md`
- 账本路由真源：`assets/registry/ledger_index.json`
- 项目专属数值与实测证据：[references/shellstorm2-normal-enemy-contract.md](references/shellstorm2-normal-enemy-contract.md)
