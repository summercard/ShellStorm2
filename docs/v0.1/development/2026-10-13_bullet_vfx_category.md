# 特效域新增大类「子弹特效」并登记 8 弹种专属弹体特效

日期：2026-10-13；记录ID：2026-10-13_bullet_vfx_category；功能ID：`ASSET-PIPELINE`（owner `LedgerIndex`，本记录同时挂在 vfx 域）；工程版本：`0.1.0`（`project.godot` 未改）。
设计依据与修订：[战斗与局内成长 §6.2](../04_技术施工_战斗与局内成长.md)（子弹模块必填字段含 `visual_id`）、[特效系统与制作规范 §1.3](../14.6_特效系统与制作规范.md)（特效账本《资产主表》是特效资产的唯一登记源）、[资产与内容规范 §3](../10_资产与内容规范.md)（`vfx_` 前缀与运行文件名去版本化）、内容库《武器》S/T 列；代码基线：`0.1.2` 分支工作区（`2280526b4`）；交付提交：提交前标记工作区。

主人原话：「特效账本增加子弹特效的大类，然后去游戏内看一下设计文档，然后把不同的子弹特效记录账本。后续可以用于子弹特效的专属制作。」两项口径在动手前确认：新增**独立大类**（不是把子弹塞进既有「特效」大类），登记**8 个弹种 + 现有通用弹体补登**共 9 行。

## 变更与原因

### 为什么要新增大类而不是复用「特效」

8 个弹种当前**只有配色区分**（`WeaponModel3D.BULLET_COLORS`），没有各自的专属 Prefab；设计上（04 §6.2）每个子弹模块必填 `visual_id`，也就是「每个弹种有可路由的专属视觉」。把 8 条排产入口和 20 条既有通用特效混在「特效」大类里，会让 `大类` 这一列失去查询能力（既不能按「弹种专属待制作」筛，也无法与通用特效的 `子类` 语义对齐）。因此新增大类「子弹特效」，`子类` 承载弹种（`bullet_standard` …），`逻辑ID/源键` 直接取内容库的 `mod_bullet_*`，与武器账本里的子弹模块行**同键对齐**。

### 账本结构变更

**`assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx`（9 条新行 + 聚合面）**

- 《资产主表》追加 9 行（`r26`–`r34`，末数据行 `25 → 34`）：

| 行 | AssetID | 子类 | 逻辑ID/源键 | 状态/动画 | 制作状态 | 优先级 | 变体父ID |
|---|---|---|---|---|---|---|---|
| r26 | `VFX-BULLET-VISUAL-3D` | `bullet_shared` | `FX01-06` | `flight` | 已完成 | P0 | — |
| r27 | `VFX-BULLET-STANDARD-3D` | `bullet_standard` | `mod_bullet_standard` | `flight_neutral` | 待制作 | P1 | `VFX-BULLET-VISUAL-3D` |
| r28 | `VFX-BULLET-STICKY-3D` | `bullet_sticky` | `mod_bullet_sticky` | `attach_countdown` | 待制作 | P1 | 同上 |
| r29 | `VFX-BULLET-BOUNCE-3D` | `bullet_bounce` | `mod_bullet_bounce` | `bounce_ricochet` | 待制作 | P1 | 同上 |
| r30 | `VFX-BULLET-PIERCING-3D` | `bullet_piercing` | `mod_bullet_piercing` | `pierce_through` | 待制作 | P1 | 同上 |
| r31 | `VFX-BULLET-EXPLOSIVE-3D` | `bullet_explosive` | `mod_bullet_explosive` | `flight_to_detonate` | 待制作 | P1 | 同上 |
| r32 | `VFX-BULLET-HOMING-3D` | `bullet_homing` | `mod_bullet_homing` | `homing_curve` | 待制作 | P1 | 同上 |
| r33 | `VFX-BULLET-BLACKHOLE-3D` | `bullet_blackhole` | `mod_bullet_blackhole` | `blackhole_pull` | 待制作 | P1 | 同上 |
| r34 | `VFX-BULLET-BALLOON-3D` | `bullet_balloon` | `mod_bullet_balloon` | `inflate_flight` | 待制作 | P1 | 同上 |

- `r26` 是**补登**：该 Prefab（`assets/art/vfx/combat_3d/vfx_bullet_visual_root_top3d.tscn`，SHA-256 `a3c84c7e…2685`）此前只登记在《3D-特效》分页，本次按 §1.3「《资产主表》＝唯一登记源」补进主表，并作为 8 条专属特效的父体。它由 `Projectile3D` 作为子节点持有、随 `ProjectilePool3D` 回收，**刻意不进 `VfxPool3D`**，避免弹体池与特效池双重所有权。
- 8 条专属行的 `备注` 逐条引用**自己的**内容库《武器》S 列原文，并写明「当前只有 `BULLET_COLORS` 配色、无专属 Prefab」这一事实与制成后的回填动作（登记 PackedScene + 回填 O 列路径与 T 列 SHA-256 + 推进 K 列）。
- `R`/`S` 派生列按行重算，区间扩到 `$R$6:$R$34`；`C`/`K`/`L` 三张下拉重建为 `C6:C34`/`K6:K34`/`L6:L34`；条件格式 `S6:S34`（重复）、`K6:K34`（已完成/待制作）与 `auto_filter` 同步扩到 `A5:Y34`。
- 《总览》大类表新增「子弹特效」行（`r11`），合计行下移为 `r12` 并把合计公式修正为 `=SUM(B10:B11)` / `=SUM(C10:C11)`（原公式 `COUNTIF(…,A11)` 因 `A11` 是字面量「合计」而恒为 0，顺手修掉）；`A6/C6/E6/G6/B10/C10/B11/C11` 区间全部 `$25 → $34`；Prefab 统计块整体下移一行。
- 《账本说明》大类覆盖改为「特效 / 子弹特效」；《域变更日志》追加 `v0.1.14`。
- **《3D-特效》分页刻意不动**：该页声明「一行 ＝ 一个实际存在的 `PackedScene`」，而 8 条专属行尚无 Prefab；且该页属摘要锁死表，改动会被 `verify_ledger_split.py` 以 `moved_sheet_mutated` 拒绝。

**`assets/registry/ShellStorm2_美术资产台账_v001.xlsx`（跨域契约面）**

- 《分账本索引》特效行：覆盖大类 → `特效 / 子弹特效`，大类数 → `2`（域与账本文件列不变，机器可读副本仍是 `ledger_index.json`）。
- 《总览》大类表插入「子弹特效」行（归属域＝特效，条数 9）。
- 《分类与编码》新增 `VFX / 子弹特效 / standard / sticky / bounce / piercing / explosive / homing / blackhole / balloon / assets/art/vfx/combat_3d/ / vfx_bullet_{type}_root_top3d_v{nnn}.tscn / VFX-BULLET-STANDARD-3D`。
- 《版本记录》追加 `v0.2.3`。

**`assets/registry/ledger_index.json`（机器可读真源）**

- `vfx` 域 `categories` → `["特效", "子弹特效"]`；`prefix_category_pairs` 新增 `["VFX", "子弹特效"]`（VFX 前缀一前缀多类，先例是 `AUD` 同时服务音效+音乐）；`scope_note` 补记第二大类。总目录《分账本索引》与 `ledger_index.json` 逐格一致的契约由门禁强制。

**`tools/asset_pipeline/split_asset_ledger.py`**

- `CATEGORY_VALUES` 在 `"特效"` 与 `"音效"` 之间插入 `"子弹特效"`。该常量必须与 `ledger_index.json` 的类别并集**完全相等**（`_enum_contract()` 的 `category_universe_mismatch`），故两处同步是不可分割的原子改动。

**`assets/registry/ledger_split_baseline.json`（无损基线）**

- 按 `reconcile_runtime_truth_ledger.refresh_current_baseline()` 口径重建。**首轮**（改动前基线 `1063`）记录为 `asset_count 1063 → 1072`；**重放轮**（2026-10-13 23:40，改动前基线已是 `1215`）实际为 `1215 → 1232`。差值 17 中，9 条是本记录的 `子弹特效` 新行，另 8 条 `ENV-EXPEDITION-COMMON-*`（场景账本）是上级提交已入账、而基线未跟上的**存量基线债**，被本次按「基线＝当前真相」口径一并接受（详见末节）。9 条新行入册（`c=子弹特效`、`d=vfx`）；`category_counts` 新增 `子弹特效=9`（`特效` 保持 20）；23 个内容列的并集指纹刷新；`captured_at → 2026-10-13`。
- **`sheet_digests` 逐项不变**（`3D-特效` 等锁死表未被触碰）。基线是回归守卫而非迁移一次性检查，任何「静默丢行/改行」都会被它对比改动前的真源抓出来。

**`docs/v0.1/feature_registry.json`**

- `ASSET-PIPELINE.development_records` 追加本记录；`updated_at → 2026-10-13`。

### 兼容性影响

- 既有 20 条特效行的 `AssetID`、运行路径、`SHA-256`、状态、授权与内容顺序**逐格不变**（见下方逐格比对验证）。
- 运行时不改一行代码：8 条专属行是排产入口，`O` 列填「待定」、`T` 列留空；`子弹特效` 大类的引入不改变任何 Prefab 的加载方式。
- 主账本《总览》与《分账本索引》里「特效」的条数（17 / 16）是 2026-09-23 拆分时的**标注快照**，权威数量在分账本《总览》（用 `COUNTIF` 活算）；门禁只比对索引的域/账本文件/覆盖大类/大类数列，不比对快照条数，故本次未去动那些历史快照值。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| 基线重建（内存 diff 改动前基线） | venv python + openpyxl，无运行时 | 通过 | 重放轮 `added 17 / removed 0 / mutated 0`（9 条本次 + 8 条存量场景基线债）；`sheet_digest drift []` |
| 既有 20 行与改动前冻结副本逐格比对 | 同一 openpyxl 读法 | 通过 | 唯一差异＝`S` 列区间 `$R$6:$R$25 → $R$6:$R$34`；`A–R`、`T–Y` 全同 |
| `check_asset_registry.py --scope structure` | — | **0** | `assets=1232 ledgers=9`，`issue_counts {}`，vfx 29 行 |
| `verify_ledger_split.py` | — | **0** | `baseline_assets 1232`，`union_assets 1232`，`failure_count 0`，`column_digest_drift []` |
| `check_asset_registry.py --scope full --ledger vfx` | — | **1** | `sha_mismatch 5`：全部落在**既有行** r19/r22/r23/r24/r25；`r26` 的 `a3c84c7e…2685` 与磁盘一致（见下） |
| `check_asset_runtime_naming.py --quiet` | — | **1** | 既有债务：14 个带版本运行文件、3 个带版本目录、`tscn` 引用计数 93→98；本次未新增任何 `assets/art` 文件 |
| `check_documentation_contracts.py` | ASCII `/tmp` cwd + `python3` 垫片（子检查需 openpyxl） | **1** | 30 项**既有**：历史断链、6 个未注册专项、`UI 期望16实际18`；**0 项涉及本次**（自动筛查关键词 bullet/子弹/VFX 命中 0） |
| `VFX-BULLET-VISUAL-3D` 路径与哈希实读 | `shasum -a 256` | 通过 | 文件存在；`a3c84c7e8842369fee46a224880589f1470e2beb68b2205a5ad41c4659832685` 与账本 `T` 列一致 |

- 8 条专属行的 `备注` 引用逐条回读内容库《武器》核对：`balloon=S11`、`blackhole=S12`、`bounce=S13`、`explosive=S14`、`homing=S15`、`piercing=S16`、`standard=S17`、`sticky=S18`，行号与弹种一一对应，无错位。
- 上一轮曾观察到「`r28`（sticky）引用 S16」的疑虑：本次逐格重读确认 `r28` 引用的是 **S18**，上轮为渲染截断造成的误读。
- 未新增验收场景，故不涉及 `run_verification_suite.sh` 注册；`check_feature_traceability.py` 未见因本次变化产生的红项。

### 预期故障与未执行

- **预期故障（既有，非本次引入）**：特效账本 `r19/r22/r23/r24/r25` 的 `sha_mismatch` 属他人待处理工作（环境云海、基地音乐音符、两套环境鸟群）。依「哈希漂移先核对变更来源，不批量接受当前文件掩盖差异」，本次**未**去动这些行的 `T` 列与基线指纹。归因证据：这 5 行的 `T` 列值与改动前冻结副本逐字节相同，漂移存在于账本与磁盘之间，与本次改动无因果关系。
- **未执行**：未跑 Godot 引擎内验收（本次为账本登记，无可运行表现）；未跑真实渲染；未跑全量 `smoke/core/full` 套件；未做 8 条专属特效的实际制作（本次只建排产入口）。
- **非预期脚本错误**：0（三次账本写入均在内存校验通过后单点落盘，并做跨进程回读复核）。

## 遗留与状态更新

- **状态更新**：特效域大类数 `1 → 2`；特效账本资产条数 `20 → 29`；基线资产总数 `1215 → 1232`（首轮口径为 `1063 → 1072`，差异见末节）；`category_counts` 新增 `子弹特效=9`。主账本《分账本索引》《总览》《分类与编码》《版本记录》与特效账本《总览》《账本说明》《域变更日志》同步完成。
- **8 条专属特效仍为「待制作」**，`O` 列「待定」、`T` 列空。制成动作需要：先落地独立 Prefab（复用 r26 的弹芯/外壳/拖尾几何分层，只换外观与行为段）→ 在《3D-特效》分页登记实际存在的 `PackedScene` → 回填 `O`/`T` → 把 `K` 列推进到「已完成」。本次**不**把「已登记排产入口」等同于「特效已完成」。
- **未动的历史快照**：主账本《总览》「特效＝17」与《分账本索引》「特效条数＝16」是 2026-09-23 的标注快照，与分账本活算值（20）本就不一致；本次新增的「子弹特效＝9」是当前值。若后续要统一成活算口径，属独立的账本口径修订任务，不在本次范围。
- **回滚路径**：`assets/registry/ledger_split_baseline.json` 与 `ledger_index.json` 为纯文本，可直接 `git checkout`；两个 `.xlsx` 与脚本的改动前副本存于 `.workbuddy/backup/20261013_bullets_vfx_replay/before_replay/`（本机无 `ShellStorm2-backup/` 工程外目录，改放工作区 `.workbuddy/backup/`；本记录首轮写的 `ShellStorm2-backup/20261013_bullets_vfx_category/before_edits/` 同理落在 `.workbuddy/backup/`）。特效账本改动前 SHA-256 为 `53749a2c5a6a92367329fca5783bf3c88e485477f674167752415c82af5565c2`。

## 重放与口径变更（2026-10-13 23:40）

本记录所述的已跟踪改动曾一次落盘成功并复核，但当日 `23:34:36` 的一次 `git reset --hard`（`reflog: 2280526b4 HEAD@{2026-10-13 23:34:36}: reset: moving to HEAD`）把 4 个已跟踪文件（特效账本 xlsx、美术资产台账 xlsx、`ledger_index.json`、`split_asset_ledger.py`）**整体回退到改前**，未跟踪的备份与本文档保留。

本次按本机版本原样重放（用户裁定「子弹特效账本以本地为主」）：

1. `ledger_index.json`：`vfx.categories → ["特效", "子弹特效"]`、`prefix_category_pairs` 新增 `["VFX", "子弹特效"]`、`scope_note` 补记第二大类；`split_asset_ledger.py`：`CATEGORY_VALUES` 在 `"特效"` 与 `"音效"` 之间插入 `"子弹特效"`。
2. `.workbuddy/backup/20261013_bullets_vfx_category/apply_bullets_vfx_category.py` 重放 → `APPLY_OK rows 29 last 34`（幂等前置断言全部通过，说明两个 `.xlsx` 确为改前态）。
3. `refresh_current_baseline()` 重建基线（**只**调该函数，未跑 `reconcile_domain`／`main`——后者会全量重写 9 本账本并删行改哈希，超出本次范围）。

### 重放轮的两个口径变化

- **基线起点 `1063 → 1215`**：期间上级提交把 89 组音效素材入库（`a826bf90` 音效重制与替换），基线随之刷新。故本次的实际增量是 `1215 → 1232`，而非首轮的 `1063 → 1072`。
- **差值 17 = 9（本次）+ 8（存量基线债）**：`ENV-EXPEDITION-COMMON-{CEILING-DECK,FLOOR-BASE,FLOOR-TILE,WALL-COLLAPSE,WALL-DOOR×2,WALL-STANDARD×2}-*` 8 条已在 HEAD 场景账本（923 行）里，但 HEAD 的 `ledger_split_baseline.json` 仍停在 `scenes=915` —— 即**上级提交遗留的基线债**（`verify_ledger_split` 会以 `extra_assets` 报出）。本次按「基线＝当前真相」口径接受，`scenes 915 → 923`。这 8 条不是本次登记的资产，归因证据：`git show HEAD:` 场景账本已含对应 AssetID，而改动前基线的 `assets` 里查无此键。

### 未验证／未做

- 重放轮的写入未再逐格比对既有 20 行（首轮已比对：唯一差异＝`S` 列区间 `$R$6:$R$25 → $R$6:$R$34`）；本次以两个门禁 `exit 0` 与 `sheet_digest drift []` 为回归依据。
- 未跑 `check_documentation_contracts.py` 全量以外的场景门禁；未跑 Godot 引擎内验收（本次仍为纯账本登记）。
- 8 条专属特效的实际制作由并行会话进行中（工作区已有 `src/vfx/VfxBullet*3D.gd` 与 `vfx_bullet_*_root_top3d.tscn`），与本记录无关，本记录不据此推进 `K` 列状态。
- **相关功能**：`ASSET-PIPELINE`（owner `LedgerIndex`，状态 `partial` 不变——本次是持续维护而非完成度提升）；`VFX-POOL` 未受影响（子弹表现刻意不进 `VfxPool3D`）。功能关系跟踪表 `FEATURE_RELATIONSHIP_MATRIX.md` 的 `ASSET-PIPELINE` 行保持原样（跟踪视图，不因单次登记改状态栏）。
