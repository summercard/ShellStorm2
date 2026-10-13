# 2026-10-13

## 项目文档通读（用户要求「查看一下项目文档」）

阅读顺序按 `docs/README.md`：DOCUMENTATION_STANDARD / WORKSPACE_LAYOUT → `docs/v0.1/MODULE_INDEX.md` → `design/README.md` → `audits/2026-09-24_global_acceptance.md` → `development/README.md` + CHANGELOG 头部。

要点：
- 工程版本 0.1.0（`project.godot`），但当前 Git 分支为 `0.1.2`，HEAD `2280526b`「远征02设计」。
- 主线已从「连续爬塔」改为「98F 开场 → 99F 基地 → 远征情报室选关 → 独立单层远征 → 撤离/死亡 → 回基地」；连续爬塔降为隐藏路线、低优先级。
- 37 个 FeatureID，机器追溯在 `docs/v0.1/feature_registry.json`；设计分三色：已实装/用户设计/Codex补充。
- 2026-09-24 全局验收结论：框架可维护，**不能签署全局通过或可发布**；运行实测 158 项（135 通过 / 21 失败 / 2 跳过）。

## 本轮查出的环境性事实（非文档本身缺陷）
- `python3 scripts/check_documentation_contracts.py` 退出码 1，30 项 issue：
  - 24 项断链指向 `../ShellStorm2-backup/...`（上层备份），3 项指向 `docs/art/.../*.log`，1 项 CHANGELOG 内引用 `2026-10-08_boss002_spawn_speed.md` 不存在。
  - `Verification registry invalid`：6 个场景未注册（verify_base99_radio_sound、verify_base99_swivel_chairs、verify_environment_bird_flocks、verify_expedition01_spawn_ramp、verify_expedition_resume_entry、verify_pushable_base_chairs）。
  - `Media asset domains invalid`：本机缺 `openpyxl`，脚本直接 ModuleNotFoundError（环境问题，非文档问题）。
- 本机只有 `Documents/ShellStorm2`（Git 工程根）；`ShellStorm2-work/`、`ShellStorm2-backup/` 均不存在，而 `WORKSPACE_LAYOUT.md` 按 Windows 布局 `I:/工作项目/shellstrom2/` 描述 8 项根布局 → 工程外产物出口与备份约定在这台 Mac 上无法照字面执行，`scripts/workspace_paths.py` 会默认落在 `../ShellStorm2-work`（不存在，需自行建或设 `SHELLSTORM_WORK_ROOT`）。
- 工作区有大量未提交改动（主要是 `assets/**/*.glb.import` 等）。

未做任何写入/修改，仅阅读与跑门禁。

## 特效账本查子弹特效（用户询问）

- 特效分账本：`assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`；工作表 = 总览 / 账本说明 / **资产主表** / **3D-特效**（Prefab 专表）/ 域变更日志。域 primary_skill = `vfx-combat-effect-authoring`。
- **有子弹特效**：`FX01-06` / `VFX-BULLET-VISUAL-3D`「飞行子弹纯视觉特效」，制作状态 **已完成**，v001。
  - Prefab `assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn`（根节点 `VfxBulletVisual3D`，metadata/asset_id + asset_version=v001）；脚本 `src/vfx/VfxBulletVisual3D.gd`。
  - 归属：由 `Projectile3D` 作为子节点持有（`src/combat3d/Projectile3D.gd:9` preload），生命周期随弹体池 `ProjectilePool3D`，**刻意不进 `VfxPool3D` 注册表**（避免双池 ownership）。验收 `verify_combat_vfx_toon_v002`。
  - 规格：弹芯 CapsuleMesh r0.045/h0.20；外壳 r0.075/h0.18；拖尾锥底半径0.06/长0.5；OmniLight3D `ProjectileLight`（energy1.2 / range1.8，无阴影）。弹体沿 local -Z，拖尾向 +Z。无碰撞（碰撞属 Projectile3D 的 r0.12 球）。
  - 加入日期 2026-09-21（域变更日志 v0.1.1）。
- **重要差异（可复核）**：`资产主表` 自称「唯一登记源」，但其只登记 20 条 VFX；Prefab 专表 `3D-特效` 有 14 条 FX 编号，其中 8 条在资产主表查不到：FX01-01/02/03/04/05/**06(子弹)**/FX02-01/FX02-02。`scripts/check_asset_registry.py` **只读 `资产主表`** 取资产行（`ASSET_SHEET`），Prefab 专表仅做分页归属校验，故漏登不会被门禁拦住（门禁 full 报 vfx:20）。
  - 域变更日志 v0.1.1 对 FX01-06 明确写过「资产主表未改」→ 属已知偏差，非静默丢失。
- 区分：`武器账本` 另有 8 条 `WPN-BUL-MOD-BULLET-*`（标准/黏黏/回旋镖/穿甲/爆炸/蜂卵/黑洞/气球弹，全为**程序占位**），那是**子弹模块（物品）**，不是特效。
- 环境：本机需 `openpyxl` 读 xlsx；已装入托管 venv `/Users/summercards/.workbuddy/binaries/python/envs/default`。仓库 `scripts/check_media_asset_domains.py` 在系统 python 下会因缺 openpyxl 崩溃。

## 「战场道具」文档 + 账本 定位（用户询问）

- 项目**没有**「战场道具」这个词：文档/代码用「**战局**区块」（`battle`、局内关卡01）与「**场景道具**」（大类）两种叫法。用户口语的"战场道具"落到三条线，需按 AssetID 判断归属。
- **文档层**（`docs/v0.1/`）：
  - 主设计：`05.1_关卡区块设计.md`、`05.2_关卡版图白盒与生成规范.md`
  - 资产规范：`10_资产与内容规范.md`（§6 武器/子弹/道具、§11 道具固有色规范）、`10.1_3D场景美术生产流程.md`
  - 玩法侧道具流转：`design/战斗奖励与物品流转设计.md`（功能ID WEAPON-COMBAT / INVENTORY-SLOTS / REWARD-SERVICE / WORLD-LOOT）
  - 最核心契约文档：`development/2026-09-19_关卡通用物体资产契约对照.md`（塔楼六件通用物体统一 11 项 metadata 契约 + 8 项断言门禁 `PREFAB_CONTRACT_OK count=6`）
  - 链路/记录：`development/2026-09-16_battle_common_component_library_v001~v003.md`（43 包 7 类通用组件库）、`2026-09-16_battle_level01_whitebox_wall_modules_v003.md`、`2026-09-18_战局房间美术制成与导入链路.md`、`2026-09-23_battle_l_corridor_room_type_v001~v003.md`、`2026-10-12_exit_neon_sign.md`
- **账本**：路由真源 `assets/registry/ledger_index.json`；总目录 `assets/registry/ShellStorm2_美术资产台账_v001.xlsx`（分账后**不登记资产行**，只留索引与跨域契约）。战场条目分落两个分账本：
  - `ledgers/ShellStorm2_场景账本_v001.xlsx`：资产主表 872 行（表体到 872）、`3D-场景通用` 732 行、`3D-设施` 56 行、`3D-其他` 4 行。ENV-BATTLE-* 在主表仅 3 行（`ENV-BATTLE-FATHER-OFFICE-SOURCE` 836、`ENV-BATTLE-BLOCK00-STORY-ROOMS-SOURCE` 838、`ENV-BATTLE-EXIT-NEON-SIGN` 872）；`3D-场景通用` 有 25 行 `ENV-BATTLE-*`（COMMON-COMPONENT-LIBRARY、SAFE-ENTRY/EXIT、ROOM-MAIN 01–10、ROOM-BRANCH 01–04、BOSS-ARENA、CORRIDOR-WALL/FLOOR）；`3D-设施` 含 EXIT 霓虹灯标牌。PRP-* 共 49 行（含 PRP-BLOCK00-* 24 件 98F 战局房间陈设）。
  - `ledgers/ShellStorm2_道具账本_v001.xlsx`：资产主表 30 行（ITM-*/PRP-*），`3D-道具` 4 件（战术指挥椅/维修圆凳/房间家具/99F 收音机）、`3D-物品` 1 件（小号背包）。
- **状态口径**：战局通用组件（wall_standard / wall_door / floor_tile，2026-10-12 域日志 v0.1.28/29 换成塔楼 A 套 v005/v004 可视美术）+ 入口/出口安全房 17 包 + EXIT 霓虹灯 = 已接入；局内关卡01 主路/支路房、Boss 竞技场 190×90、走廊墙地砖 = **未接入白模**；98F 父亲办公室/会议室 = **仅 Blender 源，无 GLB/Prefab**。
- 门禁：`scripts/check_asset_registry.py --scope structure`、`tools/asset_pipeline/verify_ledger_split.py`（**基线债**：`ledger_split_baseline.json` 停在分账时刻，每次有意新增资产必报 `extra=1`；场景账本 R/S 列公式红项 235×2 为既有）、`scripts/check_asset_runtime_naming.py`（运行路径不带版本号）。

## 特效账本新增大类「子弹特效」+ 登记 8 弹种专属特效（已交付）

用户要求：特效账本增加「子弹特效」大类 → 读局内设计文档 → 把不同子弹特效记进账本，供后续专属制作。
两项口径经确认：**新增独立大类**（不复用「特效」）；范围 = **8 弹种 + 现有通用弹体补登 = 9 行**。

**改动面（6 个文件，原子）**
- `tools/asset_pipeline/split_asset_ledger.py`：`CATEGORY_VALUES` 插入 `"子弹特效"`（必须与 `ledger_index.json` 类别并集完全相等）。
- `assets/registry/ledger_index.json`：vfx 域 `categories` → `["特效","子弹特效"]`；`prefix_category_pairs` 加 `["VFX","子弹特效"]`（一前缀多类，先例 `AUD`→音效+音乐）。
- `ledgers/ShellStorm2_特效账本_v001.xlsx`：《资产主表》追加 r26–r34（末行 25→34）；R/S 扩到 `$R$6:$R$34`；DV `C6:C34/K6:K34/L6:L34`；CF `S6:S34`/`K6:K34`；autofilter `A5:Y34`；《总览》加 r11「子弹特效」+ 合计下移到 r12（并把坏公式 `COUNTIF(…,A11)` 修成 `=SUM(B10:B11)`）；8 处区间 `$25→$34`；《账本说明》B8 → `特效 / 子弹特效`；《域变更日志》+v0.1.14。**《3D-特效》刻意不动**（摘要锁死表 + 8 条无 PackedScene）。
- `ShellStorm2_美术资产台账_v001.xlsx`：《分账本索引》D11→`特效 / 子弹特效`、E11→2；《总览》插「子弹特效」行（域=特效，条数9）；《分类与编码》加 `VFX/子弹特效` 行（目录 `assets/art/vfx/combat_3d/`，模式 `vfx_bullet_{type}_root_top3d_v{nnn}.tscn`）；《版本记录》+v0.2.3。
- `ledger_split_baseline.json`：按 `refresh_current_baseline` 口径重建 —— `asset_count 1063→1072`，9 条新行入册，`category_counts` 新增 `子弹特效=9`（`特效` 仍 20），23 列并集指纹刷新，`captured_at→2026-10-13`，`targeted_updates` +1 条；`sheet_digests` **不变**。
- 文档：新建 `docs/v0.1/development/2026-10-13_bullet_vfx_category.md`；CHANGELOG + README 各加条目；`feature_registry.json` 把记录 append 到 `ASSET-PIPELINE.development_records`、`updated_at→2026-10-13`。

**9 行的键**：r26 `VFX-BULLET-VISUAL-3D`（`bullet_shared`/`FX01-06`/`flight`/已完成/P0，由 3D-特效 FX01-06 补登为主表父体，SHA `a3c84c7e…2685`）；r27–r34 八弹种（`VFX-BULLET-{STANDARD,STICKY,BOUNCE,PIERCING,EXPLOSIVE,HOMING,BLACKHOLE,BALLOON}-3D`，子类 `bullet_*`、逻辑ID = 内容库 `mod_bullet_*`、均**待制作/P1**、`O`=待定、`T` 空、`G`=`VFX-BULLET-VISUAL-3D`）。顺序逐字取自 `src/base/BlueprintRegistry.gd` 161–211 行；配色取自 `WeaponModel3D.BULLET_COLORS`（line 87）。

**设计依据**：`04_技术施工_战斗与局内成长.md` §6.2「子弹模块必填 `content_id / added_damage / speed_multiplier / behavior_tags / **visual_id** / compatibility_rules`」；内容库《武器》S 列（每弹种表现原文）/T 列（`[部分完成] 实例尾号…逐条专属VFX/音频仍待QA`）；`14.6_特效系统与制作规范.md` §1.3「特效账本《资产主表》是唯一登记源」。内容库行号映射（已逐条回读核对，无错位）：balloon=S11 / blackhole=S12 / bounce=S13 / explosive=S14 / homing=S15 / piercing=S16 / standard=S17 / sticky=S18。

**门禁结果（退出码单独捕获）**
- `check_asset_registry.py --scope structure` → **0**（`assets=1072 ledgers=9`，`issue_counts {}`，vfx 29）。
- `verify_ledger_split.py` → **0**（union 1072，`failure_count 0`，`column_digest_drift []`）。
- 基线干跑 diff → `added 9 / removed 0 / mutated 0 / meta 0`，`sheet_digests` 漂移 []。
- 既有 20 行 vs 冻结副本逐格 → **唯一差异 = S 列区间 `$R$6:$R$25→$R$6:$R$34`**。
- `--scope full --ledger vfx` → 1：`sha_mismatch 5`，全落既有行 r19/r22/r23/r24/r25（其 T 列与改前逐字节相同 ⇒ 非本次）。
- `check_asset_runtime_naming.py` → 1：既有债务（14 文件 / 3 目录 / tscn 93→98）。
- `check_documentation_contracts.py` → 1：仍是 **30** 项既有（断链 / 6 未注册 / UI 期望16实际18），**涉本次 0**。
- `check_feature_traceability.py` → **0**，`issues []`。

**本机/工具链新经验（已写进 skill）**
- `check_documentation_contracts.py` 用裸 `python3` 起子检查；本机 `python3` 缺 openpyxl ⇒ `check_media_asset_domains.py` ModuleNotFoundError。修法：造 ASCII 目录放 `python3` **wrapper 脚本**（`exec <venv>/bin/python "$@"`）前置进 PATH。⛔ **`ln -s` 指向 venv python 无效**（找不到 `pyvenv.cfg` ⇒ 丢 site-packages）。
- 账本落盘纪律：**内存校验 → 单点 save → 跨进程回读**。踩过「断言失败但 save 已执行 → 留下半写账本」。
- 宽列（备注 Y）大批量 dump 会截断，曾误判「r28 引用了 S16」，逐行回读澄清为 S18。
- 既有红项官方清单在 CHANGELOG 2026-10-12 条目里（断链 / 6 未注册 / UI 16→18 / 14 文件 3 目录 tscn 93→98），与本次实测逐项吻合 ⇒ 别消红。
- 主账本《总览》「特效＝17」与《分账本索引》「特效条数＝16」是 2026-09-23 标注快照，与分账本活算值 20 本就不一致；**门禁不校验快照条数**，未去动。

**备份**：`.workbuddy/backup/20261013_bullets_vfx_category/`（`before_edits/` 冻结 5 个文件；特效账本改前 SHA `53749a2c…65c2`，改后 `e679b39f…588b`）。
