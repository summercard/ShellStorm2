# 第二只正式精英：夺械者“收租人”（2026-11-03）

## 一句话

把一套外部迁入的模型资产（电视机头西装人形怪）按正式规范定名为
`ENM-ELITE-ARMS-TAKER-3D / enm_elite_arms_taker`，补齐正式目录、18 剪辑动画母版、
状态机接线、账本登记与设计文档，投放 94—92F。**精英首次使用真骨骼动画。**

## 起点：一个「放着但用不了」的资产

迁入时（17:55–17:57）的文件状态有三处硬缺陷，**拿去 Godot 打开会加载不出模型**：

| 缺陷 | 事实 | 后果 |
|---|---|---|
| tscn 引用断链 | 场景写 `components/<slug>/<slug>_visual_top3d.glb`，而 GLB 实际在**资产根目录**，`components/` 与 `runtime/` 都是空目录 | 打开报加载失败 |
| 布局不符规范 | 规范要求 `components/<slug>/` + `runtime/<slug>/` 两层同名子目录；入库说明却称"按 `rift_boar_armed` 结构生成"，那只是 D3 冻结的存量形态 | 与既有 boss 样板不一致 |
| 清单自相矛盾 | `asset_manifest.json` 的 `runtime_files` 自检查弹出 2 条"缺失"（GLB + tscn 的声明路径） | 三方（实况/清单/台账）互不吻合 |

另外：`enm_elite_tvone01` 这个 slug 是**执行方自拟**的，12 只名册里没有对应槽位；
3 号机源目录当时已 **Connection refused**（`sc@100.117.192.4`），**本地是唯一副本**。

## 定名

主人裁定本资产 = 12 只名册中的 **`elite_arms_taker / 夺械者“收租人”`**。据此：

| 项 | 值 | 依据 |
|---|---|---|
| elite_id | `elite_arms_taker` | 名册既有稳定 ID |
| slug | `enm_elite_arms_taker` | 命名契约 §3.2 精英模板 `enm_elite_<name>` |
| AssetID | `ENM-ELITE-ARMS-TAKER-3D` | 契约 §221 精英模板 |
| 投放窗口 | 94F / 93F / 92F，每局 run_seed 三选一 | 与首只 98—96F **互不重叠**；95F 是 Boss 层，两只都不进 |

模型外观（电视机头 + 西装 + 领带 + 工装靴）与「夺械者」的夺械/近远切换定位不冲突；
`behavior_id=weapon_phase_swap`、`modifier_id=Elite.WeaponParasite` 沿用名册既有挂点。

## 动画母版：18 条单状态 GLB → 1 份 41 骨母版

**为什么必须合并**：18 条动作原本是 18 个独立 GLB，各自带一份完整骨架。
逐状态挂 18 个场景既不符合工程「一份模型一份 GLB」，切换也有开销。
现有普通怪（小僵尸 6 剪辑、胖子僵尸 13 剪辑）都是**单 GLB 多剪辑**，本资产照此规格。

合并脚本 `art_source/.../source/animation/author_merge_animation_v001.py`，
**自带四条会失败的断言**：

1. 18 条动作的 41 个 joints 名与基础模型**逐位相同**（不一致就 `NotImplementedError`，
   避免把错骨架的动作烘进母版）；
2. 产物 clip 名齐备；
3. **无多余 clip**；
4. 时长误差 ≤1 帧。

### 两个实测踩到的坑

| 坑 | 现象 | 正解 |
|---|---|---|
| `export_force_sampling=True` | 强制按**整数帧**重采样。idle 源 127.2 帧 → 127 帧（5.300→5.292s），run 更狠：20.8→20 帧（0.867→**0.833s**），逐条对不上源清单 | **关掉采样**，直接导出关键帧，时间戳原样保留 |
| slam.glb 内含**两条** clip | 只有一条挂到 `animation_data.action`，另一条（Blender 默认名 `ArmatureAction`）留在 `bpy.data.actions` 里被 `ACTIONS` 模式一并导出 ⇒ 产物 19 条 clip | 导出前按名单清理 `bpy.data.actions` |

另一处 Blender 5.x 兼容问题：`Action` 改成了 layered 结构，**没有** `fcurves` 属性，
直接读会 `AttributeError`。帧数取法要兼容 4.x/5.x 两种结构（帧数只用于日志，不参与门禁）。

**产物**：1,230,900 B，1 Mesh / 1 材质 / 41 骨 / **18 剪辑**，时长误差全部 ≤0.01 帧。

## 状态机：精英首次需要状态驱动

首只 `rift_boar_armed` 的表现 GLB 是**纯静态**（`skins=0`、`animations=0`），
所以 `EnemyAvatar3D._formal_elite_root` 一直是「只加载、不驱动」。
本资产带 41 骨 + 18 剪辑，不驱动就会**僵在 bind pose**。

改法（最小侵入）：

```text
Enemy3D._physics_process → avatar.sync_presentation(...)
  ├─ has_formal_normal()                        → _formal_normal_root.sync_state(...)  # 既有
  └─ _formal_elite_root.has_method("sync_state") → 精英 .sync_state(...)              # 新增
```

**判据是「表现根有没有 `sync_state`」，不是按 `elite_id` 写死分支。**
纯静态的精英没有这个方法，自然被挡在外面 —— `EnemyAvatar3D` 不需要知道哪些精英有动画。

新文件 `elite_arms_taker_formal_visual.gd` 提供 `sync_state` / `flash_hit` /
`get_presentation_snapshot`，与普通怪 `*_formal_visual.gd` 同一套契约。

### 一个被验收当场抓到的真 bug

`AnimationPlayer` **没有** `playback_speed` 属性（那是 `AnimationTree` 的口径），
正确名是 `speed_scale`。写错只在赋值时抛 `Invalid assignment of property 'playback_speed'`，
被引擎吞成脚本错误 ⇒ 表现静默退化成"永远 1 倍速"。
`verify_second_elite_arms_taker` 第一次运行就把它抓出来了（EXIT=1，8 处报错）。

同一轮还修了两处：
- `const` 用 `%` 拼接字符串 ⇒ GDScript 解析期报 "isn't a constant expression"，
  而报错在 parse 阶段 ⇒ **场景加载失败、`quit()` 永不执行 ⇒ 表现为"验收卡死"**（挂了 6 分钟）。
- `get_animation()` 对不存在的剪辑返回 null，会在一路 `seek()` 上崩；
  改为显式 `has_animation()` 检查 + 告警回退。

## 账本：三处分页 + 两处公式范围

登记进《敌人账本》三处：**资产主表**（身份，唯一登记源）、**3D-敌人**（Prefab 分类页）、
**敌人动画与状态**（下表「敌人条目 × 状态机对照」）。

### 一个只有门禁能抓到的坑

《资产主表》的查重键（R 列）与查重结果（S 列）都是**公式**，且 S 列的
`COUNTIF($R$6:$R$54, ...)` 范围是**硬编码到末行**的。同理《总览》页有 **8 条**汇总公式
（`COUNTA` / `COUNTIF` / `SUMPRODUCT`）也钉死在末行。

插入新行时若不同步扩范围 ⇒ 新行被排除在查重与计数之外，**而账本表面完全正常**
（不报错、不变色、公式照算），只是数字少了一个。
`scripts/check_asset_registry.py` 的 `expected_end` 门禁把它抓出来了（7 issues）。

已把「扩总览公式范围」这一步固化进登记脚本 `tools/asset_pipeline/register_second_elite_ledger.py`，
下次登记不会再漏。

另一处：门禁的 SHA-256 校验对象是**入口 Prefab（.tscn）**，不是 GLB。
第一版填了 GLB 的哈希 ⇒ `sha_mismatch`。已改为 tscn 的哈希。

## 验收

| 门禁 | 退出码 | 读数 |
|---|---|---|
| `verify_second_elite_arms_taker` | 0 | `SECOND_ELITE_ARMS_TAKER_OK` |
| `verify_first_elite_deployment_flow`（回归） | 0 | `FIRST_ELITE_DEPLOYMENT_FLOW_OK` |
| `check_asset_registry --ledger enemies` | 0 | issues=0 |

### 验收内容（新篇）

`verify_second_elite_arms_taker.gd` 检查：目录布局（含"路径不得带版本号"）、
18 剪辑动画母版（**时长逐条硬编码对源清单** —— 只断言"与自己自洽"是不够的，
改坏时长再改实现两边仍自洽）、41 骨、**12 态逐态驱动且每态都落到一条真实存在的剪辑**、
94—92F 窗口与 98—96F 不重叠、95F 不侵入、每局三选一覆盖三层、
表现场景零碰撞、玩法碰撞半径仍是 `melee_chaser` 基线。

### 对既有验收的同步修改

`verify_first_elite_deployment_flow.gd` 原断言 `deployed.size() == 1`。
第二只上线后这条会假红。改为断言**投放集合恰好是这两只**（排序后逐位比对），
并补上两只窗户互不重叠、95F 不投放的断言 —— 比写死计数更耐后续投放。

## 交付物

| 类别 | 路径 |
|---|---|
| 运行资产 | `assets/art/enemies/elite_3d/enm_elite_arms_taker/{components,runtime}/enm_elite_arms_taker/` |
| 清单 / 台账 | `enm_elite_arms_taker_manifest_v001.json` / `enm_elite_arms_taker_transfer_ledger_v001.json` |
| 制作源 | `art_source/enemies/elite_3d/enm_elite_arms_taker/source/`（18 条动作 `animations/<状态>.glb` + 3 预览 + 状态机清单） |
| 合并脚本 | `art_source/.../source/animation/author_merge_animation_v001.py` |
| 账本登记脚本 | `tools/asset_pipeline/register_second_elite_ledger.py` |
| 验收 | `tests/verification/verify_second_elite_arms_taker.{gd,tscn}` |
| 状态机契约 | `src/enemy3d/EliteContentCatalog.gd` §DEFINITIONS、`src/enemy3d/EnemyAvatar3D.gd` |

## 未做 / 待办

- **3 号机源已不可达**（Connection refused）⇒ 无 `.blend` 母版，源侧仅 GLB。
  后续若 3 号机恢复，可考虑补 `.blend` 母版以支撑"覆盖同路径同名文件"式替换。
- **14 条动作目前没有玩法接线**：`turn_left` / `turn_right` / `attack_heavy` /
  `attack_jump` / `block` / `dodge` / `stagger` / `stunned` / `kneel` / `roar` /
  `spawn_standup` / `slam` 等只有映射表里有主段，尚未各自接独立玩法触发
  （如 `roar` 对应启动过程吼叫、`slam` 对应范围技）。当前 `attack_light` 一人分饰
  telegraph/attack/recovery 三段，其余一次性段待专属行为设计。
- **逃生窗/夺械转译的专属表现**：`growth_profile` 已配 `escape_*` 与
  `phase_swap_*` 参数，但对应的动画表现（如撤离时的奔跑 + 夺械阶段的切换姿态）
  尚未逐条接通。
- 未做真实渲染验收（本轮为 headless 逻辑验收）。
