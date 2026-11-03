# ELITE · 2026-11-03 第二只正式精英：夺械者“收租人”

## 事务

把外部迁入的一套模型资产（电视机头西装人形怪，迁入时 slug 为执行方自拟的 `enm_elite_tvone01`）
按正式规范定名为 **`ENM-ELITE-ARMS-TAKER-3D` / `enm_elite_arms_taker`**，主人裁定它 =
12 只名册中的 **夺械者“收租人”**（`elite_arms_taker`）。投放 94—92F。

**精英首次真骨骼动画**：首只 `rift_boar_armed` 的 GLB 是纯静态（0 骨/0 动画），
本只是 **41 骨 / 18 剪辑**。

## 起点：资产「放着但用不了」

迁入时三处硬缺陷，拿去 Godot 打开**加载不出模型**：

| 缺陷 | 事实 |
|---|---|
| tscn 引用断链 | 场景写 `components/<slug>/...glb`，GLB 实际在资产根目录；`components/`、`runtime/` 都是**空目录** |
| 布局不符规范 | 规范要 `components/<slug>/` + `runtime/<slug>/` 两层；入库说明却称"按 `rift_boar_armed` 结构"，那只是 D3 冻结的存量形态 |
| 清单自相矛盾 | `asset_manifest.json` 的 `runtime_files` 自检查弹出 2 条"缺失" |

⚠ **3 号机源已不可达**（`sc@100.117.192.4` Connection refused）⇒ **本地是唯一副本**，
无 `.blend` 母版，源侧只有 GLB。

## 交付

| 项 | 值 |
|---|---|
| slug / AssetID | `enm_elite_arms_taker` / `ENM-ELITE-ARMS-TAKER-3D` |
| 运行资产 | `assets/art/.../elite_3d/enm_elite_arms_taker/{components,runtime}/enm_elite_arms_taker/`（路径不带版本号） |
| 动画母版 | 1,230,900 B；1 Mesh / 1 材质 / **41 骨 / 18 剪辑**；时长误差 ≤0.01 帧 |
| 状态机 | `elite_arms_taker_formal_visual.gd`（新） |
| 投放 | 94F / 93F / 92F 每局 run_seed 三选一；与首只 98—96F **互不重叠**；95F Boss 层两只都不进 |

## 四个关键技术点（都留了会失败的断言）

1. **动画合并**：18 条单状态 GLB → 1 份母版。脚本
   `author_merge_animation_v001.py` 自带 4 条断言：17 条骨架逐位一致、clip 齐备、
   **无多余 clip**、时长 ≤1 帧。
2. **两个实测坑**：
   - `export_force_sampling=True` 按**整数帧**重采样 ⇒ run 从 0.867s 变 **0.833s**，逐条对不上源清单。**关掉采样**。
   - slam.glb 内含**两条** clip，第二条（`ArmatureAction`）留在 `bpy.data.actions` 被一并导出 ⇒ 产物 19 条。导出前按名单清理。
3. **Blender 5.x**：`Action` 是 layered 结构，**无 `fcurves`** 属性，直接读 `AttributeError`。
4. **精英状态驱动**：`EnemyAvatar3D.sync_presentation` 新增精英分支。判据是
   **「表现根有没有 `sync_state`」**，不是写死 `elite_id` —— 纯静态精英自然被挡在外面。

## 验收当场抓到的真 bug

**`AnimationPlayer` 没有 `playback_speed`**（那是 `AnimationTree` 口径），正确名是 **`speed_scale`**。
写错只在赋值时抛错、被引擎吞成脚本错误 ⇒ 表现静默退化成"永远 1 倍速"。
`verify_second_elite_arms_taker` 第一次跑就抓到（EXIT=1，8 处报错）。

同轮还修两处：
- `const` 用 `%` 拼接 ⇒ GDScript 解析期报错；报错在 parse 阶段 ⇒ **场景加载失败、`quit()` 永不执行 ⇒ 表现为"验收卡死"**（挂了 6 分钟）。
- `get_animation()` 对不存在剪辑返回 null，会在一路 `seek()` 上崩；改为显式 `has_animation()` + 告警回退。

## 账本：一个只有门禁能抓到的坑

《资产主表》查重公式（R/S 列）与《总览》页 **8 条**汇总公式
（`COUNTA`/`COUNTIF`/`SUMPRODUCT`）都把范围**硬编码到末行**。
插行不同步扩 ⇒ 新行被排除在查重与计数外，**而账本表面完全正常**（不报错、不变色），只是数字少一个。
`check_asset_registry.py` 的 `expected_end` 抓出 7 issues。已把扩范围固化进
`tools/asset_pipeline/register_second_elite_ledger.py`。

另一处：门禁 SHA-256 校验的是**入口 Prefab（.tscn）**，不是 GLB。第一版填 GLB 哈希 ⇒ `sha_mismatch`。

## 门禁读数（实跑）

| 门禁 | 退出码 | 读数 |
|---|---|---|
| `verify_second_elite_arms_taker` | 0 | `SECOND_ELITE_ARMS_TAKER_OK` |
| `probe_second_elite_motion` | 0 | `SECOND_ELITE_MOTION_OK`（12 态真实循环，骨骼逐态在动） |
| `verify_first_elite_deployment_flow`（回归） | 0 | `FIRST_ELITE_DEPLOYMENT_FLOW_OK` |
| `check_asset_registry --ledger enemies` | 0 | issues=0 |
| `check_asset_runtime_naming` | 0 | 欠账 289 文件 / 13 目录（未增） |
| `check_level_decoupling` | 0 | violations 0 |
| `check_verification_registry` | 1 | 5 条 unregistered —— **均为历史欠账**（最后提交 10-18～11-02），本轮未引入 |

## 对既有验收的同步修改

`verify_first_elite_deployment_flow.gd` 原断言 `deployed.size() == 1`，第二只上线后必假红。
改为断言**投放集合恰好是这两只**（排序后逐位比对），并补「两窗口不重叠 / 95F 不投放」。
比写死计数耐后续投放。

## 待办

- **14 条动作未接玩法触发**：`turn_*`/`attack_heavy`/`attack_jump`/`block`/`dodge`/
  `stagger`/`stunned`/`kneel`/`roar`/`spawn_standup`/`slam` 等只有映射表主段。
  当前 `attack_light` 一人分饰 telegraph/attack/recovery。
  **不为"用上动画"而加行为** —— 那会让状态机长出无意义转移。
- 逃生窗/夺械转译的专属表现未接（`growth_profile` 已配参数）。
- 未做真实渲染验收（本轮 headless）。

## 交付物

- 开发记录 `docs/v0.1/development/2026-11-03_second_elite_arms_taker.md`
- 施工口径 `docs/v0.1/06_技术施工_怪物精英与Boss.md` §5.7（含"2/12"口径更新）
- 外观设计 `docs/v0.1/design/怪物设计.md` 新增章节
- 内容数据库 `精英怪` 分页第 12 行更新
- 账本登记脚本 `tools/asset_pipeline/register_second_elite_ledger.py`
- 验收 `verify_second_elite_arms_taker` / 探针 `probe_second_elite_motion`
