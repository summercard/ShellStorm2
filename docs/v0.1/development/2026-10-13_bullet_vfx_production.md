# 8 弹种专属弹体纯视觉制作（特效账本 r27–r34 落地）

日期：2026-10-13（重放于 2026-10-14 凌晨）；记录ID：`2026-10-13_bullet_vfx_production`；功能ID：`VFX-POOL`（owner `VfxPool3D`，本记录同时挂在 vfx 域与 `ASSET-PIPELINE` 的账本面）；工程版本：`0.1.0`（`project.godot` 未改）。
设计依据与修订：[特效系统与制作规范 §1.2/§1.3/§2.2/§7.1/§8/§10](../14.6_特效系统与制作规范.md)（Prefab 是唯一出口、账本唯一登记源、特效 Prefab 不得嵌碰撞、运行资产去版本号）、[战斗与局内成长 §6.2](../04_技术施工_战斗与局内成长.md)（子弹模块必填 `visual_id`）、[资产与内容规范 §3](../10_资产与内容规范.md)（`vfx_` 前缀与运行文件名去版本化）；上游排产登记见 [子弹特效大类登记记录](2026-10-13_bullet_vfx_category.md)；代码基线：`0.1.2` 分支工作区。

主人原话：「开始进行特效制作，先阅读文档、账本、skill」。动手前两项口径确认：**制作范围＝8 弹种全量制作**（不是单弹种试点）；**表现深度＝仅弹体／尾迹／命中视觉**（skill §10 的边界：只做纯表现层，不做玩法行为——反弹折线计数、穿透层数、爆炸伤害时点等仍属玩法层，不在本次）。

## 变更与原因

### 为什么是「一弹种一 Prefab + 共享基类」而不是一个脚本内 `match bullet_type`

14.6 §8 明列反模式「一个总脚本 + `match effect_kind` 分支多个特效」。8 个弹种的差异（弹芯形状／尺寸、外壳配色、尾迹段数与排布、灯范围能量）是**数据差异**而非**逻辑分支**：结构一样（弹芯 + 外壳 + 尾迹锥 + 跟随灯四件套），只是参数不同。因此拆成 `VfxBulletBody3D`（共享基类，管生命周期／构建四件套／出 `get_presentation_snapshot()`）＋ 8 个子类（只覆写 `_bullet_profile()` 返回本弹种参数）＋ 8 个独立 Prefab。这样既满足「一特效一 Prefab」，又不产生 8 份复制粘贴的构建代码。

### 落地清单（8 Prefab + 10 脚本 + 1 路由改动）

- **Prefab（8）**：`assets/art/vfx/combat_3d/` 下平铺

  | AssetID | Prefab | SHA-256 |
  |---|---|---|
  | `VFX-BULLET-STANDARD-3D` | `vfx_bullet_standard_root_top3d.tscn` | `d85bb501f79d65493fa2225b0af3516873bf73e1b5c8060e6055fc6bdd7a6530` |
  | `VFX-BULLET-STICKY-3D` | `vfx_bullet_sticky_root_top3d.tscn` | `a9ecbcc2cf4b74001414b802a5acb0615289fdc8d28ed96fa1360cca52665c4b` |
  | `VFX-BULLET-BOUNCE-3D` | `vfx_bullet_bounce_root_top3d.tscn` | `49bd24a7c468a829e6e7dffe5b6d79c93e9edb4dd3986d9489d151058ba8f6bd` |
  | `VFX-BULLET-PIERCING-3D` | `vfx_bullet_piercing_root_top3d.tscn` | `450125ae4af8dfe45964f78542d09c5e604bc348a56ef52454378b1430daa37c` |
  | `VFX-BULLET-EXPLOSIVE-3D` | `vfx_bullet_explosive_root_top3d.tscn` | `8c1ce8b1e775b884b01e6644cd75f57d9cb47cd18e1a3a41e8374f600d84e93d` |
  | `VFX-BULLET-HOMING-3D` | `vfx_bullet_homing_root_top3d.tscn` | `f3f7ad5dcce3205908cf0a115ce425f6030daf4427ede2d394b6997192546032` |
  | `VFX-BULLET-BLACKHOLE-3D` | `vfx_bullet_blackhole_root_top3d.tscn` | `1f7c02ebe353097eda9d818ce583b9a12935917c69f80929bfc0142d7fa417f2` |
  | `VFX-BULLET-BALLOON-3D` | `vfx_bullet_balloon_root_top3d.tscn` | `e711140cc2daba69230168a54f8f1e03a958015e2c88be8baeaf6f3b1d320e6d` |

  每个 Prefab 根节点带 `metadata/asset_id`（上表 AssetID）与 `metadata/asset_version = "v001"`；文件名与运行引用**不含** `_vNNN`（去版本化口径，与 §2.1 一致）。

- **脚本（10）**：`src/vfx/VfxBulletBody3D.gd`（共享基类，`extends VfxEffectBase3D`）＋ `VfxBullet{Standard,Sticky,Bounce,Piercing,Explosive,Homing,Blackhole,Balloon}3D.gd`（8 子类）＋ 既有的 `VfxBulletVisual3D.gd`（r26 通用弹体）。子类唯一覆盖点是 `_bullet_profile()`，其余（外壳／尾迹／灯的构建、回收归零、`context.follow` 跟随）全在基类。
- **路由**：`Projectile3D` 按 `visual_id` 选弹体 Prefab（04 §6.2 契约）；未登记 `visual_id` 与缺省值一律回落通用弹体 `VFX-BULLET-VISUAL-3D`。
- **归属（刻意不进池）**：弹体视觉由 `Projectile3D` 作为**子节点**持有、随 `ProjectilePool3D` 回收，**不**注册进 `VfxPool3D`——与 r26 同口径，避免「弹体池 + 特效池」双重所有权（§1.2）。

### 账本回填（`assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`）

- 《资产主表》`r27`–`r34`：`K 制作状态` 由 `待制作 → 已完成`；`N 规格` 填本弹种几何真值（弹芯／外壳／尾迹／灯的尺寸与能量）；`O 文件路径` 填上表 Prefab 路径；`T SHA-256` 填上表哈希（与磁盘实测逐字节一致）；`U 负责人 → 摩斯拉`、`V 更新时间 → 2026-10-13 00:00:00`、`W 来源/许可 → 原创程序几何`、`Y 备注` 改为「已制成并实装：Prefab + 脚本 + 根节点 + 变体父体」的成品描述。
- 《3D-特效》分页：新增分组表头行 `「▼ 01 战斗反馈（续）· 子弹特效（FX01-06 系列）」` 与 8 条数据行，编号 `FX01-08`..`FX01-15`（该页由 12 条 → 22 条）。该页声明「一行＝一个实际存在的 `PackedScene`」，此前 8 行因无 Prefab 刻意未登记，本次 Prefab 落地后补登记。
- 《域变更日志》追加 `v0.1.15`（条目更新 + 新增 Prefab）。
- **基线刷新**：`refresh_current_baseline()` 重建 `assets/column_digests/sheet_digests/category_counts`——`asset_count 1232 → 1232`、`子弹特效=9` 不变、`sheet_digests` 仅 `3D-特效` 漂移（该页是摘要锁死表，新增 9 行必改其摘要）。**未**跑域协调（`reconcile_domain`/`main`），后者会全量重写 9 本账本并删行改哈希，超出本次范围。

### 文档回写

- `docs/v0.1/14.6_特效系统与制作规范.md`：§2.2 目录树标注 `combat_3d` 含 `bullet_<弹种>×8`（平铺套件根）与 `VfxBulletBody3D.gd`；§10 追加 `v003` 条目。
- `docs/v0.1/MODULE_INDEX.md`：`VFX-POOL` 行补 `verify_bullet_vfx_profiles` 与制作事实（含本记录链接）。
- `docs/v0.1/feature_registry.json`：`VFX-POOL` 增补开发记录与本记录、增补验收场景 `verify_bullet_vfx_profiles`。
- `scripts/run_verification_suite.sh`：`verify_bullet_vfx_profiles` 登记进 `core_scenes`（`check_verification_registry.py` 要求每个 `verify_*.tscn` 恰有一个套件归属）。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 证据 |
|---|---|---|---|
| `verify_bullet_vfx_profiles`（Godot 真实运行） | 独立场景，不读 viewport 纹理 | 通过 | `BULLET_VFX_PROFILES_OK: 8 bullet profiles / routing / size / wiring pass (samples=48)`；套件 `VERIFICATION_SUITE_OK suite=scene count=1` |
| 账本回读 + 哈希实测（8 行） | venv python + openpyxl，无运行时 | 通过 | `r27..r34` 的 `K=已完成`；`T` 列与 `shasum -a 256` 实测**逐行 MATCH**（上表 8 个哈希） |
| 基线刷新 diff | 同上 | 通过 | `asset_count 1232→1232`；`category_counts` 无增减；`sheet_digests` 仅 `3D-特效` 变 |
| `verify_ledger_split.py` | — | **0** | `LEDGER_SPLIT_VERIFY_OK assets=1232 ledgers=9`，`failure_count 0` |
| `check_asset_registry.py --scope structure` | — | **0** | `ASSET_REGISTRY_CHECK_OK scope=structure assets=1232 ledgers=9`，`issue_counts {}` |
| `check_asset_registry.py --scope full --ledger vfx` | — | **1** | `sha_mismatch 5`：全部落在**既有行** `r19/r22/r23/r24/r25`；本次 `r27..r34` **全过** |
| `check_asset_runtime_naming.py --json` | — | **1** | `new_files 14 / new_dirs 3 / gone 0`；`ref_up` 中 `tscn [93, 98]`。全部为 HEAD 存量债务，**本次 0 贡献**（见下） |
| `check_documentation_contracts.py` | ASCII `/tmp` cwd + `python3` 垫片（子检查需 openpyxl） | **1** | `engine_version 0.1.0 | documents 280 | links 1553 | features 37 | test_refs 85`；`issues total 30`，**涉及本次 0**。聚合：`Broken link 28` + `Verification registry invalid 1`（6 个既有场景未注册）+ `Media asset domains invalid 1`（`ui row count: expected 16, got 18`） |

- **命名门禁归因（本轮 0 贡献，实测证明）**：排除本次新增文件后 `tscn` 带版本引用仍为 `98`（快照记 `93`），14 个带版本文件与 3 个目录均为角色／道具资产（`bunny01 v022/v023/v024`、`mission_command_chair v004`、`workshop_stool v004`），在 HEAD 已存在且工作区未改动。本次 8 个 Prefab 只含根元数据 `metadata/asset_version="v001"`（合规），文件名与 `[ext_resource]` 路径均无 `_vNNN`。依「不为过门禁而无脑重写欠账快照」，本次**未**跑 `--update-debt`。
- **`sha_mismatch` 5 条的漂移方向**：`git status` 显示这 5 个目标文件在工作区**未改动**，即漂移存在于 HEAD 账本与磁盘之间，与本轮无因果关系；依「哈希漂移先核对变更来源」，本次不回填、不批量接受。
- 新增验收 `verify_bullet_vfx_profiles`：8 个 Prefab 可加载 + AssetID／版本 meta 正确 + 灯光真相（名 `ProjectileLight`／不投影／范围 1~3m／出生能量>0／回收归零且不可见／复借复亮）+ 尾迹落在弹体身后 + 八弹种彼此可区分（含设计原文可测特征：穿甲弹芯更细、气球弹芯更大且球形、黑洞球形暗核、爆炸灯范围更大）+ `visual_id` 路由（8 命中／未登记回落／缺省回落）+ `effect_size` 线性（1.0/0.8 比值 ≈1.25）+ 真装配真开火端到端 + 纯视觉无碰撞体 + 防假绿哨兵（样本数下限）；`samples=48`。

### 预期故障与未执行

- **预期故障（既有，非本次引入）**：`r19/r22/r23/r24/r25` 的 `sha_mismatch` 属他人待处理工作（环境云海、基地音乐音符、两套环境鸟群）；`check_asset_runtime_naming.py` 与 `check_documentation_contracts.py` 的红项同理为 HEAD 存量债务。其中文档契约的 2 个非断链 issue 已核明实体：① 验收注册表——6 个**既有**场景未登记（`verify_base99_radio_sound / verify_base99_swivel_chairs / verify_environment_bird_flocks / verify_expedition01_spawn_ramp / verify_expedition_resume_entry / verify_pushable_base_chairs`）；② 媒体资产域——`ui row count: expected 16, got 18`。本次新增的 `verify_bullet_vfx_profiles` **未**出现在未注册列表（即登记成功）；本记录 4 个相对链接（`../14.6_特效系统与制作规范.md`、`../04_技术施工_战斗与局内成长.md`、`../10_资产与内容规范.md`、`2026-10-13_bullet_vfx_category.md`）全部存在。见上两节归因证据。
- **未执行**：未做玩法行为（反弹计数、穿透层数、爆炸伤害时点、锁定框切换等——本次口径限定纯表现层）；未做真实渲染截图比对（本次 Prefab 为程序几何纯视觉，逻辑与接线已由专项覆盖，观感仍待真实渲染验收）；未跑全量 `smoke/core/full` 套件（仅跑本次场景）。
- **非预期脚本错误**：0。
- **环境限制（既有）**：macOS 上套件隔离工作区是符号链接农场，`purge_stale_verification_workspaces.py` 的重解析点守卫拒绝删除，且沙箱对 >50 项批量删除要求二次确认；故套件退出时打印的「临时工作区未被清理」属既有环境限制，**不改判定**（场景本身判据为 `BULLET_VFX_PROFILES_OK` 行 + ERROR 计数）。本次未绕开该保护。

## 遗留与状态更新

- **状态更新**：特效账本 `K=已完成` 行数 `20 → 28`（`r27..r34` 推进）；《3D-特效》`12 → 22` 条；`VFX-POOL` 仍为 `partial`（本次是表现层落地，非完成度提升）；`ASSET-PIPELINE` 保持 `partial`。
- **账本与磁盘一致性**：8 条专属行的 `O`/`T` 已回填并与磁盘哈希逐行一致，`check_asset_registry --scope full` 对本次 8 行零报错——「已登记排产入口」至此推进为「已登记成品」。
- **未动项**：主账本《总览》「特效＝17」「子弹特效＝9」等**标注快照**未动（口径修订是独立任务）；`FEATURE_RELATIONSHIP_MATRIX.md` 的 `VFX-POOL` 行保持原样（跟踪视图，不因单次落地改状态栏）。
- **回滚路径**：8 个 Prefab、10 个脚本、专项验收三件套均为**未跟踪新文件**，`rm` 即回滚；账本与基线为已跟踪文件，`git checkout -- <path>` 可回到 HEAD（HEAD 为回填前态）。回填脚本与改动前副本存于 `.workbuddy/backup/20261013_bullet_vfx_production/`（`apply_bullet_vfx_production.py` 幂等、含前置断言；`before_edits/` 为账本改动前副本）。

## 工作区被外部重置与重放（2026-10-14 00:1x）

上一轮本记录的已跟踪改动（账本回填、基线刷新、套件登记、`data/runtime_design_data_manifest.json` 重建）在一次 `git pull --rebase` 后**被整体冲掉**：`HEAD` 前移（reflog `HEAD@{2}` 为远端提交「账本：特效域新增『子弹特效』大类 + 8 弹种专属特效排产入口（按本机版本重放）」），工作区回到该提交（回填前态：`r27..r34` 仍 `待制作`、日志停在 `v0.1.14`）。**未跟踪的 8 Prefab、10 脚本、专项验收三件套未受影响**（`pull/rebase` 不触碰未跟踪文件）。

本次按本机版本原样重放已跟踪改动：

1. `.workbuddy/backup/20261013_bullet_vfx_production/apply_bullet_vfx_production.py` 重跑 → `APPLY_OK main_rows 29 page_rows 22 page_last 33 log_last 21`（幂等前置断言全部通过，说明工作区确为回填前态）。
2. `refresh_current_baseline()` 重建基线 → `asset_count 1232→1232`、`sheet_digests changed: ['3D-特效']`、`captured_at 2026-10-14`。
3. 重新登记 `scripts/run_verification_suite.sh` 的 `core_scenes`。
4. 本次一并完成文档回写（14.6 §2.2/§10、`MODULE_INDEX.md`、`feature_registry.json`、本记录）——这些在外部重置前尚未落笔。

**口径提示**：本项目工作区存在并发会话与外部回退（本记录上一轮记录 `2026-10-13_bullet_vfx_category.md` 亦载明一次 `git reset --hard`）。因此「已跟踪改动的完成」必须以**提交**为准，未提交的改动随时可能被并行 `pull/rebase/reset` 覆盖；未跟踪成果相对安全。

## 路由半边的缺失与还原（2026-10-14 00:4x，提交前独立复验）

**发现**：截至提交前，工作区的路由半边**不在树里**。`git status` 与 HEAD 一致，而 HEAD 版 `Projectile3D.gd` 只有单一 `BULLET_VISUAL_SCENE`：既无 `visual_id` 查表，`get_orientation_snapshot()` 也不含 `visual_asset_id`；全 `src/` 对 `visual_id` **零引用**。上一节的「按本机版本重放」清单（账本/基线/套件/文档四项）**不含 `Projectile3D` / `WeaponModel3D` 的路由改动**——即该改动随外部 `pull --rebase` 一并被冲掉后**未被重放**。

**隔离复验证据**（`bash scripts/run_verification_suite.sh scene verify_bullet_vfx_profiles`，临时工作区隔离）：`BULLET_VFX_PROFILES_FAIL: 18 failures`。分层明确——Prefab 加载 / 八弹种特征 / 尺寸线性 / 无碰撞体**全过**；18 条失败**全部**落在 `visual_id` 路由与端到端接线，且「实测」值**一律为空**（连回落用例也是空，说明路由代码整体不在场）。

**还原**：从 `git stash@{0}`（`Fork autostash 2026-10-14 00:09`）取回原版实现，两文件与 stash **blob 哈希逐一相同**（`Projectile3D.gd` = `0949cde2027962035b89c98b96548bba89fecf84`、`WeaponModel3D.gd` = `ba60f799479fc90db489591e1e6c9ec193e99e69`），相对工作区为**纯增量**（`Projectile3D.gd` +53/-2、`WeaponModel3D.gd` +7/-1）。内容：`const BULLET_VISUAL_REGISTRY`（8 键 visual_id → Prefab）、`_visual_scene_for()`（未登记回落通用弹体）、`_sync_visual_route(config)`、`_ensure_visual()`、`_build_visual()` 不再无条件覆盖、`get_orientation_snapshot()` 增 `visual_asset_id` / `visual_profile`、子投射物继承父弹种视觉，以及 `WeaponModel3D` 在 3 处 spawn 配置注入 `"visual_id": bullet_id`（副枪回落主枪 `bullet_id`）。

**复验（还原后，同一隔离套件）**：
- `verify_bullet_vfx_profiles` → **`BULLET_VFX_PROFILES_OK: 8 bullet profiles / routing / size / wiring pass (samples=48)`**，`VERIFICATION_SUITE_OK suite=scene count=1`，`^ERROR` 计数 **0**。（该用例判据为 OK 行 + ERROR 计数，**不看裸退出码**；本机「批量删除需确认」守卫会让临时工作区无法自动清理，令套件以 1 收尾，属环境现象。）
- 关联回归 `batch`：`verify_vfx_pool_lifecycle` **OK**、`verify_combat_vfx_toon_v002` **OK**、`verify_player3d_firing_motion` **OK**（`BUNNY_FIRING_MOTION_OK checks=376`）。
- **一项既有失败，与本次无关**：`verify_3d_inventory_weapon_flow` 以 10 条 `UNEXPECTED_ENGINE_ERROR` 失败（全是「left click did not equip…」的 UI 合成点击类）。**对照实验**：临时撤回路由改动（`src/combat3d/` 对 HEAD 零改动）单跑同一用例，**同样 10 条、同样失败** ⇒ 与弹体路由无因果关系。

**同时一并修复的旁支**：`data/runtime_design_data_manifest.json` 在 HEAD 上即为陈旧——`python3 scripts/sync_runtime_design_data.py --check` 报 `projection manifest drift`（源文件与投影目标**逐字节一致且都与 HEAD 相同**，仅清单记录的 40 条 sha256 有 39 条对不上）。该门禁是套件前置，不过则任何场景都跑不到，故按脚本原意 `python3 scripts/sync_runtime_design_data.py` 重建（只写这 1 个派生文件，不动源/注册表/玩法参数）。
