# Godot 侧资产替换去版本化 —— 执行计划

日期：2026-09-17；记录ID：待补；工程版本：0.1.0；状态：**执行中 —— P1 / P2 / P4 已完成，原子批 B1（`tower_zones/battle`）、B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）已完成；B3…B9 未开始**。
依据：`assets/art/3D模型资产目录与命名规范.md` §Blender 到 Godot 的更新流程（L126–133）。
基线：commit `b8af6fd`。
作用域：`assets/art/**` 的 Godot 运行资产（`components/` + `runtime/`）与 `src/**/*.gd` 的引用路径；`source/**` 的 Blender 历史版本保留策略**不变**。
索引动作（`development/README.md`、`CHANGELOG.md`）在交付步执行。

## 1. 问题

替换资产时 Godot 侧路径随版本漂移：源文件的 vNNN 被复制进运行资产的目录名与文件名，导致同一逻辑资产出现多份、代码引用与台账随之改动。四条根因：

| # | 层 | 根因 | 证据 |
|---|---|---|---|
| A | 规范 | 导入 skill 规定「替换=新建版本」，与命名规范「替换=覆盖既定路径」相反；执行导入时只加载 skill | `godot-model-asset-import-standard/SKILL.md` L32/L46/L63 vs 命名规范 L126–133 |
| B | 工具 | 版本号是脚本常量，直接拼进目录名与文件名；qa 脚本一版一份 | 全仓 18 个 `^VERSION = "v0NN"`；`source/entry_safe_room/v007/qa/export_packages_v007.py:47-48,144`、`build_package_prefabs_v007.py:43,156`；`tools/asset_pipeline/generate_runtime_scenes.py:43`；同目录另有平行的 `*_v006.py` |
| C | 运行时 | 版本号进 `preload` 常量与路径拼接 | `src/world3d/DungeonRoom3D.gd:75,97-109,1007-1013`；`TowerDescent3D.gd:7-34`；`TowerFloorStage3D.gd:31-46`；src 共 109 行 / 22 个 `.gd` |
| D | 台账 | O 列一格需同时表达源 / GLB / Prefab 三个版本 | 命名规范 L76；`assets/art/asset_import_manifest_v001.json` 顶层键即版本名（`*_v021_optimized_packages` / `*_v022_updates` / `*_v023_stair_bed`） |

已发生的代价（战局区块实测）：`runtime/entry_safe_room/` 存在 v003/v004/v005/v007 四个目录，前三个为空；`components/common_components/` 5 组 `_v003` 与 `_v004` 并存；`components/entry_safe_room/v006` 24 个 GLB 无任何 runtime；战局区块 `.bak_*` 18 个。

全仓存量规模（实测 2026-09-17）：带版本运行资产 **818 个文件**（GLB 527 + tscn 291），版本目录 9 个，`.tscn` 直接引用带版本 GLB **207 处**，`.gd` 引用 **109 行 / 22 个文件**。分布：environments 558、props 86、characters 79、weapons 76、vfx 11、enemies 6、ui 2。

反例（证明不必如此）：`generate_runtime_scenes.py` 的包装场景名恒定、GLB 路径由 manifest 提供；塔楼 4 件替换时 prefab 保持 `_v001`、只换被引用的 GLB 版本。

## 2. 目标规则

- **N1 路径恒定**：Godot 运行资产路径不含版本号、不含版本目录。
  `components/<套件>/<slug>/<slug>_visual_top3d.glb`、`runtime/<套件>/<slug>/<slug>_root_top3d.tscn`。
- **N2 替换即覆盖**：替换 = 覆盖同路径同名文件；不新建目录、不新建文件；`.import` 与 `.uid` 原样保留。Godot 侧**只有覆盖**这一种替换方式。
- **N3 版本号落点**：仅允许出现在 `source/**` 的 Blender 文件名与目录、`asset_manifest.json`、台账 O 列、Prefab 根节点 `metadata/asset_version`。
  *GLB 去版本后，源版本与运行资产的对应关系只能靠这三处追溯，因此 P2 必须保证 manifest 与节点 meta 每次替换都被写入；缺失即视为丢失溯源，门禁拦下。*
- **N4 代码无版本**：`src/**/*.gd` 不得出现 `_v0NN` 形式的资产路径。
- **N5 回滚靠 git**：GLB 不再并存旧版，回滚一律 `git revert` / `git checkout`；工作区不保留 `.bak_*`。
- **N6 不变量**：AssetID、尺寸、原点契约、碰撞归属、资产元数据一律不变；本计划只改路径、命名、引用与登记。

## 3. 决策（已定）

| 编号 | 决策点 | 结论 |
|---|---|---|
| D1 | GLB 是否去版本 | **去版本**。GLB 不带版本号；`components/` 与 `runtime/` 都只保留一份稳定路径，Godot 侧替换只有覆盖 |
| D2 | 存量清理范围 | **全仓一次性对齐，但排在最后（P6）**。规模大不豁免，只是后置；先出全量清单再分批执行 |

D1 的连带影响：旧版不再并存 → 回滚必须依赖 git（N5），manifest + 节点 meta + 台账 O 列成为唯一溯源（N3）。

## 4. 执行阶段

### 4.0 关键耦合 —— 原「P3 → P4 → P5 → P6」顺序不成立（2026-09-17 实测修正）

原计划按「层」推进。**实测证明 P3 / P5 / P6 是同一个重命名事件的三个面，按层拆无法落地**：

| 证据 | 结果 |
|---|---|
| `src/**/*.gd` 里带版本的资产引用 | **112 处 / 22 个文件**；其中**去版本目标已存在 = 0** |
| 单个 `preload()` 指向不存在的 `res://` 路径 | Godot 4.6.3 实测 `--headless --check-only`：`Parse Error: Preload file "…" does not exist` + `Failed to load script … with error "Parse error"`。**是编译期错误，整个脚本不可用**，不是只丢那一个资产 |
| 因此 P3 先行 | `DungeonRoom3D.gd`（48 处）、`WeaponModel3D.gd`（11）、`TowerDescent3D.gd`（9）等 22 个核心脚本会全部编译失败 → 游戏直接起不来 |
| 因此 P5 先行 | 台账会登记尚不存在的路径，等于把账本写成假的 |
| 引用带版本路径的 `.tscn` | **207 处**，同样是硬引用，缺一个即场景加载报错 |

**结论：不能按层拆，也不必「一次性改全仓」。正确单位是「套件原子批」** —— 一个套件内 P6 重命名 + P3 代码引用 + P5 台账 + 该套件的 verifier 必须同批落地、同批验收。全仓一次性动（818 文件 + 112 引用 + 207 场景引用）出问题无法定位、无法回滚，反而是最高风险做法。

**执行顺序修正为：P1 ✅ → P2 ✅ → P4 门禁 ✅（已上线，带欠账快照）→ 原子批 B1…B8（每批含 P3+P5+P6 该套件部分）→ 收尾批 B9（无耦合的纯清理）。**

### 4.1 原子批（新的执行单位）

欠账实测口径（2026-09-17 起始基线，`scripts/asset_runtime_naming_debt.json`）：**1345 个带版本文件 / 22 个版本目录 / 14 个备份残留 / 112 处 .gd 引用**。文件类型 = 527 `.glb` + 527 `.glb.import` + 291 `.tscn`。全仓共 **21 个套件**受影响，按「谁共享引用方」+「体量」合并为 8 批。

**当前剩余**（B2 完成并缩表后）：**1058 文件 / 13 目录 / 1 备份 / gd 引用 50 / tscn 引用 635**；按大类 = `environments/base_facility_3d` 443、`environments/rooftop_shelter_3d` 311、`characters/player` 144、`weapons/weapon_3d` 127、其余小计 33（vfx 11、enemies 10、weapons/melee_3d 3、ui 2、environments/training_range_3d 1、environments/boss_arenas_v01 6）。B2 已把 `props/dungeon_3d`、`environments/dungeon_3d`、`environments/base_world_3d`、`environments/tower_descent_3d`、`props/base_world_3d` **五类整类清零**（1216 → 1058 文件，另 2 个为 B1 残留的 `tower_zones/base` + `tower_zones/rooftop` zone 场景）。

| 批 | 套件 | 欠账文件 | .gd 引用 | 备注 |
|---|---|---|---|---|
| **B1** ✅ **已完成（2026-09-17）** | `environments/tower_zones/battle`（common_components 5 + entry_safe_room 17） | 131 → 已还 129 文件 / 9 目录 / 13 备份 | 6（+1 处动态拼接）→ 已清零 | **样板批**。以「删 + 稳定化」为主；详见上「B1 执行记录」。**残留**：`tower_zones/base` + `tower_zones/rooftop` 的 2 个文件不属本子集，转后续批 |
| **B2** ✅ **已完成（2026-09-17）** | `props/dungeon_3d` + `environments/tower_descent_3d` + `props/base_world_3d` + `environments/dungeon_3d` + `environments/base_world_3d`（+ B1 残留的 2 个 zone 场景） | 156 → 改名 96 / 删除 64 / 改参照 18 | **56（耦合最重）** → 已清零 | `DungeonRoom3D.gd`(36)、`Dungeon3D.gd`(5)、`TowerFloorStage3D.gd`(4)、`TowerDescent3D.gd`(5)、`TrainingRange3D`(2)。详见上「B2 执行记录」 |
| **B3** | `environments/base_facility_3d` | **443（体量最大）** | 8 | 99F 基地，回归面最广；与其他批无引用重叠 |
| **B4** | `environments/rooftop_shelter_3d` | 311 | 0 | 零 `.gd` 耦合；自带 `verify_rooftop_shelter_asset_contract` |
| **B5** | `weapons/weapon_3d` + `weapons/melee_3d` | 130 | 14 | `WeaponModel3D.gd`(10)、`Player3D.gd`(2)、`ItemModelFactory3D`、`TrainingRack3D` |
| **B6** | `vfx/combat_3d` + `vfx/environment_3d` + `vfx/visibility_3d` + `ui/inventory_3d` + `ui/pause_3d` + `environments/training_range_3d` | 14 | 18 | `VfxPool3D.gd`(7)、`CombatEffectPool3D`、`Projectile3D`、`Enemy3D`、`PlayerMeleeCombat3D`、`ui/*`(5) |
| **B7** | `enemies/enemy_3d` + `elite_3d` + `bosses_v01` + `environments/boss_arenas_v01` | 16 | 9 | `BossContentCatalog.gd`(6)、`EliteContentCatalog`、`Player3DStateGallery`、`Dungeon3D` |
| **B8** | `characters/player` | 144 | 1 | 含 13 个 `production/vNNN/` 目录；与「角色链版本契约」待决项绑定，建议最后做 |
| **B9** | 纯清理：空版本目录 / 孤儿 GLB / `.bak_*` / 欠账快照清零 | 22 目录 + 14 备份 | — | 无代码耦合，随时可做；做完删掉快照与豁免机制 |

**并行度**：B1→B2→B3→B6 共用 `DungeonRoom3D.gd`，**必须串行**；B3/B4/B5/B7/B8 之间无共享引用方，可独立推进（但每批都要跑一遍 core 套件）。

每批固定 8 步：① 出该套件清单 → ② `git mv` 重命名（GLB + tscn + sidecar；删旧 `.import`，搬运 `.uid`） → ③ 改该套件 `.tscn` 内的 `ext_resource` → ④ 改该套件对应的 `src/**/*.gd` 引用 → ⑤ Godot `--import` 重新导入 → ⑥ 跑验收（core 套件 + 专属探针） → ⑦ 台账回填该套件行 + `check_asset_runtime_naming.py --update-debt` 缩表 → ⑧ 单独提交。

| 阶段 | 改动点 | 完成判据 |
|---|---|---|
| **P1 规则层** ✅ 已完成（2026-09-17，见下「P1 执行记录」） | ① `godot-model-asset-import-standard` 的 L32/L46/L63、§版本与引用替换、目录模板改为「覆盖既定路径、路径不含版本」；用户级 `~/.workbuddy/skills/` 与工程 `skills_drafts/` 两份逐字节同步。② `assets/art/3D模型资产目录与命名规范.md` L10–11 目录模板去 `_v###`，§坐标与替换契约补「Godot 侧路径恒定、GLB 不含版本」。③ `docs/v0.1/10_资产与内容规范.md:5` 删去「运行时可保留按批次递增的 v021–v024 组件版本」 | 两份 skill diff 为空；`python3 scripts/check_documentation_contracts.py` 通过 |
| **P2 工具层** ✅ 已完成（2026-09-17，见下「P2 执行记录」） | ① 战局区块 `source/**/qa/export_*.py`、`build_*_prefabs_*.py`：`VERSION` 只写 manifest 与节点 meta，不进路径；v006/v007 平行脚本合并为一份带版本参数的脚本。② `tools/asset_pipeline/generate_runtime_scenes.py:43`、`export_split_facilities_and_seating.py:107-129`、`update_character_registry.mjs` 同步。③ manifest 与节点 meta 写入改为必填校验 | 同一输入连跑两次，输出路径集合与 mtime 不变；`git status` 无新增带版本路径；抽 1 件资产确认 manifest + meta 均记录了版本 |
| ~~**P3 运行时层**~~ → **并入原子批**（见 §4.1） | 原设想「先改代码、后改文件」不可行：`preload` 是编译期解析，路径不存在即脚本编译失败。改为在每一批内与重命名同批改 | 每批跑 `run_verification_suite.sh core`；`probe_safe_room_v007_integration` / `probe_tower_palette_visible` 保持 `_OK` |
| **P4 门禁（必须先上线）** | 新增 `scripts/check_asset_runtime_naming.py`：扫描 `assets/art/**/{components,runtime}/**`，出现 `_v\d\d\d\.(glb\|tscn)` 文件名或 `components|runtime/**/v\d\d\d/` 目录即失败（`source/**` 豁免）；同时报告 `src/**/*.gd` 与 `tscn` 里的带版本引用数。存量未清前挂**精确路径欠账清单**（同 `LEGACY_PALETTE_EXEMPT_GLBS` 先例），双向断言：清单内路径消失要缩表、新出现的带版本路径立刻报错。接入 `AGENTS.md` 交付前检查与 run_verification_suite.sh core | 新增一件带版本资产即报错；**每完成一批原子批，欠账表相应缩表**；清零后删除豁免机制 |
| ~~**P5 台账回填**~~ → **并入原子批** | 台账路径必须与磁盘同批改，否则账本先撒谎。每批只改该套件的行（第一批 = `3D-场景通用` r86/r87 + r92–r96） | 每批：`check_asset_registry.py --scope structure` 新增为 0；AssetID / 状态 / 尺寸列不变 |
| ~~**P6 存量清理（全仓一次性）**~~ → **并入原子批 + 收尾批** | 原「全仓一次性、排最后」改为「按套件分批、与代码同批」。删除类无耦合动作（空版本目录、孤儿 GLB、`.bak_*`）集中在收尾批 | 见 §4.1 的批次表；删除类动作集中在 B9 | 每批引用扫描为 0、套件全绿；B9 后 `check_asset_runtime_naming.py` 判绿且欠账表为空 |

### P1 执行记录（2026-09-17，已完成）

发现 P1 的实际落点比原计划宽：除 §4 列出的 3 处，另有 4 处同样在声明「带版本的 Godot 路径」，一并改完才是自洽的。共 10 个文件：

| # | 文件 | 改动 |
|---|---|---|
| 1 | `skills_drafts/godot-model-asset-import-standard/SKILL.md`（基准） | 标准流程第 9/12 步、基地母版第 6 步、台账契约替换流程、目录与命名模板、§版本与引用替换整节、Godot 验收条目、frontmatter description 的「版本目录」→「版本记录」 |
| 2 | `skills_drafts/…/references/acceptance-checklist.md` | §6 版本与登记 3 条改写为「覆盖即替换、路径未变、回滚靠 git、manifest+meta 记源版本」；常见故障「更新后场景没变化」检查项补齐 |
| 3-5 | `.codex/skills/…`、`~/.workbuddy/skills/…`、`~/.codex/skills/…` 三份副本 | 由基准逐字节覆盖；SKILL.md 与 checklist 四副本 md5 一致（`3652c4b3106e` / `26dbbd8302de`） |
| 6 | `assets/art/3D模型资产目录与命名规范.md` | §标准目录模板去 `_v###`；新增「`components/`/`runtime/` 不含版本号、只有覆盖」条目；§坐标与替换契约新增稳定路径条款；§Blender→Godot 更新流程第 2/3/6 步改写 |
| 7 | `docs/v0.1/10_资产与内容规范.md` | §当前基地资产来源优先级去掉「运行时可保留按批次递增版本」；§3 目录与命名拆成「源文件带版本 / 运行资产不带版本」，示例与 `mat_`、`ui_` 例外说明 |
| 8 | `assets/art/模型资产导入说明_v001.md` | 已接入映射表补一行：表内 `_vNNN` 为存量现状，随去版本化批次更新 |
| 9 | `~/.workbuddy/skills/scene-full-pipeline/SKILL.md` | 目录与命名契约块去 `_v###`，新增稳定路径条目 |
| 10 | `~/.workbuddy/skills/scene-art-merge-into-shared-component/SKILL.md` | §5「批量升版」限定为只升源侧与 manifest/meta，Godot 路径不受版本影响 |

副本同步与残留扫描：`scene-full-pipeline` 桌面副本已同步（`~/.workbuddy/skills` 与桌面两份一致）；`skills_drafts/scene-full-pipeline/` 是**空目录**（无文件），未处理；全仓与用户级 skills 已无 `_visual_top3d_v###` / `_root_top3d_v###` 模板残留；`agents/openai.yaml` 在 `.codex/skills` 副本仍是 LF 而其余为 CRLF，**内容一致**（既有行尾差异，非本次引入）。

验收：`python3 scripts/check_documentation_contracts.py` → `issues: []`，EXIT=0（documents 87 / local_links 411 / features 34 / test_references 45）。

P1 遗留（不属于 P1，转 P2/P6 承接）：`godot-model-asset-import-standard/references/` 与 `README.md` 未发现其他带版本路径声明；`skills_drafts/README.md` 的 skill 清单未变（本次未增删 skill）。

### P2 执行记录（2026-09-17，已完成）

**核心产出：命名契约的唯一实现处** —— 新增 `tools/asset_pipeline/godot_runtime_naming.py`，所有导出/构建脚本从这里取 Godot 侧路径，脚本内不再出现 `f"..._{VERSION}.glb"`。

| API | 语义 |
|---|---|
| `visual_glb_name(slug)` / `root_scene_name(slug)` | `<slug>_visual_top3d.glb` / `<slug>_root_top3d.tscn` |
| `legacy_versioned_files(dir, recursive=False)` | 列出仍是 `_vNNN` 命名的运行资产 |
| `guard_no_legacy_versioned(dir, script, allow, recursive=True)` | 存量未去版本时 `SystemExit`；**默认递归**（资产在 `<套件>/<slug>/` 之下，只看一层会全漏）；`--allow-legacy-versioned` 可显式放行 |
| `require_version_metadata(meta_items, version, script)` | manifest / 节点 meta 必须写入本次源版本号，缺失即失败（GLB 去版本后这是唯一溯源入口） |
| `split_glb_version(rel)` / `require_stable_glb(root, rel, script)` | 把清单里带版本的 GLB 路径归一为稳定路径；稳定文件不存在时失败并提示先做 P6，而不是继续引用旧命名 |
| `version_from_argv(default)` / `allow_legacy_from_argv()` | Blender/CLI 参数解析 |

**改动的生成器（15 个文件）**：`entry_safe_room` v007 导出与 prefab 构建（成为全版本唯一脚本，`--version` 驱动）、v006 两份**转发壳**（`runpy` 转调，保留原路径让 v006 的 README/QA_REPORT 引用继续有效）；`common_components` v004 的导出/构建/色盘绑定 + v003 的导出墙门、导出地砖、构建 prefab、绑定色盘、finalize 包、回填地板 manifest。两版之间除版本号与包数量外主体逐行相同（已用 `diff` 逐行确认），合并未丢失任何逻辑。

**顺带落实 N5**：生成器不再落 `*.bak_pre_generate` / `*.bak_pre_palette`（回滚交给 git）。

**边界划分（本轮明确）**

- **生成器**（会再次运行、产出 Godot 资产）→ 必须去版本（本轮已改）。
- **资产验证器**（`verify_v004_glb.py` 等）与**台账补丁/复验脚本**（`update_ledger_rows_v004.py`、`register_*_ledger_rows.py`、`verify_*_ledger_patch.py`、`sync_catalog_export_status.py`）→ **冻结不动**：前者必须与磁盘现状同步，改了会立刻变红；后两者断言的是历史补丁的确切内容。全部登记为 **P6 同批处理项**。
- **`assets/art/asset_import_manifest_v001.json` 里的 GLB 路径**（实测全部带 `_vNNN`）→ 属数据，**P6 与重命名同批更新**；`generate_runtime_scenes.py` 已改为经 `require_stable_glb` 消费它。

**待决（本轮未动，需主人裁）**：`tools/asset_pipeline/update_character_registry.mjs` 的 `runtime/chr_bunny01_root_${version}.tscn`。角色资产按 `production/<version>/` 整树版本化，改它等于改 `player-avatar-asset-standard` 的版本契约，且该脚本依赖 macOS 侧运行时、本机无法执行验证。建议单列一轮，随角色资产链决定。

**验收**

| 项 | 结果 |
|---|---|
| `py_compile` 全部改动脚本（16 个） | 通过 |
| helper 自测（路径拼接 / 版本解析 / 守卫 / meta 校验 / 旧命名归一） | 11/11 PASS |
| 守卫递归用例（资产在下一层也能检出） | 3/3 PASS |
| 版本解析干跑（默认 / `--version v006` / `--allow-legacy-versioned`） | VERSION 与 VERSION_DIR 正确，`RUNTIME_DIR` 恒为 `runtime/entry_safe_room`（无版本目录） |
| 端到端：`build_package_prefabs_v006.py`（转发壳） | EXIT=1，命中守卫并列出 17 个旧命名文件；`runtime/` 变更文件数 **0**（未写任何文件） |
| 残留扫描：`assets/art/**/battle/source` + `tools/asset_pipeline` 内把版本拼进 Godot 路径 | 仅剩上表「冻结」类别 |

**未执行**：带 `bpy` 的 Blender 导出/构建脚本（会重写 GLB，属资产写入）未实跑，仅做 `py_compile` 与干跑；需 Blender 4.5 + P6 完成后按需重跑。



### 事故记录（2026-09-17 11:52–11:58，B1 执行中）：`assets/art/**` 被抹除并已恢复

**事实链**

| 时间 | 事件 |
|---|---|
| 11:47 | B1 侦察完成（131 欠账文件 / 9 版本目录 / 13 备份） |
| 11:52 | `--apply-renames` 执行：`git mv` 66 个（22 glb + 22 glb.import + 22 tscn），并改写 22 个 tscn 的内部引用 |
| 11:55 | `--apply-deletes` 执行：`git rm` 76 个（`_v003` 冗余 15 + `entry_safe_room/v006` 整树 48 + `.bak_*` 13） |
| 11:56 | 复核时发现 **`assets/art/**` 整棵树从工作区消失**；`find assets/art -type f` = 0 |

**取证（未做任何猜测性动作前先定性）**

- `git status --porcelain` 状态码分布：`2533 ' D'`（未暂存的工作区删除）+ `76 'D '`（我的 `git rm`）+ `66 'RD'`（我的重命名，新路径也在工作区缺失）
- 删除**只在 `assets/art/**` 内**：`src/`、`tests/`、`docs/` 未受影响
- 我的两个工具动作只有：`git mv` ×66、`git rm` ×76（文件粒度）、`rmdir`（仅 `vNNN` 名且为空的目录）。**无法解释 2533 个未暂存的整树删除** → 判定为**外部进程**所为，原因未知
- **补充取证（2026-09-17 13:00）：`git reflog` 在 11:52–11:56 窗口内没有任何条目（上一条是 11:45:22），且 `.git` 在该时段零文件写入** → 排除 git 侧操作（checkout / reset / merge / stash 均无记录），确认为**文件系统层删除**，非版本库行为

**恢复**

1. `git checkout -- assets/art` 从索引恢复被跟踪文件 → 磁盘 2599 = 索引 2599 ✓（未触碰 `src/`、`tests/` 里其它会话的改动）
2. 差额复核（用 P4 门禁的欠账快照做差集）：263 个带版本文件消失 = **129 个属 B1 有意改名/删除的旧名** + **134 个 `*.glb.import`**
3. 那 134 个 `.import` 是 `.gitignore` 的 `*.import` 白名单（第 3–17 行）未覆盖的目录（characters / weapons 等）→ **从未被 git 跟踪** → git 无法恢复；但其**源 `.glb` 全部健在**，由 `godot --headless --import` 重建
4. 其它会话的未跟踪探针文件（`tests/verification/probe_corridor_*`、`probe_floor_blue_slab*`）已不在工作区，需该会话自行重建

**结论**：未损失任何不可重建的资产；所有被跟踪文件已回到索引状态。**外部抹除的起因未能确定（已排除 git 侧操作），属未消除的风险。**

**相关旁证（同日 13:00）**：台账 xlsx 写入时 `os.replace()` 连续 8 次返回 `WinError 5 拒绝访问`，而同一文件 `open('r+b')` 成功 —— 这是「有进程持有该文件但未开放 delete 共享」的典型特征。持有者未确定；环境内查得 **OneDrive.exe / OneDrive.Sync.Service.exe 在运行**（无 Excel `~$` 锁文件）。应对：改用本仓库既有范式**就地写入**（`zipfile.ZipFile(LEDGER, "w")`，见 `_scratch/patch_ledger_safe_room_v007.py:298`），并在写前确认备份与当前文件逐字节一致、写后复验 zip 条目集合与逐条目字节。**后续批次操作台账前，先取 sha/mtime 快照确认无并发写入。**

### B1 执行记录（2026-09-17，已完成）

范围：`assets/art/environments/tower_zones/battle`（common_components 5 + entry_safe_room 17）。工具：`tools/asset_pipeline/deversion_batch.py`（`b1`，`--plan` / `--apply-renames` / `--apply-deletes` / `--fix-scene-refs`）。

**步骤**：① 侦察（131 欠账文件 / 9 版本目录 / 13 备份）→ ② `git mv` 改名 66 个 → ③ 删除 76 个（`_v003` 冗余 15 + `entry_safe_room/v006` 整树 48 + `.bak_*` 13）→ ④ 改引用（`DungeonRoom3D.gd` 5 条 preload + 动态拼接；7 个 tests 验证器；2 份文档）→ ⑤ `godot --headless --import` 重建 134 个被抹掉的 `.import` → ⑥ 场景内部引用改写 `--fix-scene-refs`（22 个 tscn，幂等）→ ⑦ 退役 4 个 v003 期验证器 → ⑧ 台账补丁 → ⑨ 缩欠账表。

**验收**

| 项 | 结果 |
|---|---|
| `probe_safe_room_v007_integration` | `SAFE_ROOM_V007_INTEGRATION_OK` ✓ |
| `verify_common_wall_door_components_v004` | 通过 ✓ |
| `verify_common_floor_tile_components_v004` | 通过 ✓ |
| `verify_scene_facility_shared_palette` | 通过 ✓ |
| `verify_tower_grid_component_alignment` | `TOWER_GRID_COMPONENT_ALIGNMENT_OK` ✓ |
| `check_asset_runtime_naming.py` | 新增违规 **0**；已还欠账 129 文件 / 9 目录 / 13 备份（全部 `tower_zones`）；缩表后 exit 0 ✓ |
| `check_asset_registry.py --scope structure` | **38**（等于基线，无新增）✓ |
| `check_documentation_contracts.py` | `issues: []` ✓ |
| `src` 内对 `tower_zones/battle` 的引用 | 全部版本无关（6 处，含动态拼接已注释原因）✓ |

**退役 4 个 v003 期验证器**（主人确认）：`verify_common_wall_door_components` / `verify_common_floor_tile_components` 及其 2 个 `_visual` 变体 —— 共 12 个文件（`.gd`/`.tscn`/`.uid`）已从仓库删除，并移出 `run_verification_suite.sh` 的 core / renderer 名单。理由：它们断言 v003 版几何，而 v003 资产已按 N1「同一资产只留一份」在本批删除，稳定路径现装 v004 内容；实测不符是**真差异非错位**（`wall_standard_5m` 可视包围盒 z=0.3030 且区间 `[-0.1530,0.1500]` 不对称 —— v004 并入装饰的 3mm 凸出；两块地砖厚度 0.0830/0.0852 vs v003 期望 0.056/0.081 —— v004 加了砖面美术）。v004 期验证器已覆盖活契约且通过。

**台账回填**（`_scratch/patch_ledger_b1_deversion.py`）：`3D-场景通用` r86/r87、r92–r96 的 C/D 列去版本（含 `/entry_safe_room/v007/` 目录段，runtime 与 components 两侧都去），**O 列版本事实保留**（r86/r87=v007，r92–r96=v004）。复验：zip 29 条目集合不变、仅 `sheet10.xml` 变化、行数 142 不变、B1 行 C/D 列无残留。备份 `*.xlsx.bak_b1_deversion`（保留：台账当前状态尚未提交，git HEAD 里没有它）。

**残留（转后续批）**：`tower_zones/base` + `tower_zones/rooftop` 的 2 个文件（`zone_base_v002.tscn`、`zone_rooftop_v021.tscn`）不属 battle 子集，未动。

**事故与两个工具层缺陷**：见上「事故记录」与 P2/B1 缺陷条 —— ① tscn 内部引用改写未暂存，被事故恢复回滚（已加 `--fix-scene-refs`）；② 引用扫描漏「版本目录拼接」形式（已修）；③ `--apply-deletes` 曾错误复用「保留最高版本」逻辑，重命名后会反过来删掉刚改名成功的文件 —— 已拆出 `collect_leftovers()`：第二步只认「稳定名已存在则删带版本的那个」。

### B2 执行记录（2026-09-17，已完成）

范围：`props/dungeon_3d` + `environments/tower_descent_3d` + `props/base_world_3d` + `environments/dungeon_3d` + `environments/base_world_3d` 五根（欠账 156 文件 / `.gd` 引用 56，全批耦合最重），另清 B1 残留的 `tower_zones/base`（`zone_base_v002.tscn`）+ `tower_zones/rooftop`（`zone_rooftop_v021.tscn`）两个 zone 场景。工具：`tools/asset_pipeline/deversion_batch.py`（`b2`，`--plan` / `--apply-renames` / `--apply-deletes` / `--fix-scene-refs`）。**全部落在同一个提交内。**

**步骤**：① 出清单 → ② `git mv` 改名 96 → ③ 删除 64 → ④ 改参照 18 个文件 → ⑤ `godot --headless --import` 重建 `.import` → ⑥ `--fix-scene-refs` 改写场景内部 `ext_resource` → ⑦ 台账补丁 16 格 → ⑧ 缩欠账表。

| 动作 | 明细 |
|---|---|
| 改名 96 | GLB 15（`R100` 逐字节）+ `.glb.import` 15（内容由 Godot 重生成，`R077…R098`）+ tscn 66（`R100` 逐字节 46 + 内部引用改写 20） |
| 删除 64 | 冗余 GLB 31 + 对应 `.glb.import` 31 + 退役探针 `probe_tower_module_art.gd` 与 `.uid` 各 1 |
| 改参照 18 | `src/**/*.gd` 6（`DungeonRoom3D` 36 处、`Dungeon3D` 5、`TowerDescent3D` 5、`TowerFloorStage3D` 4、`TrainingRange3D`、`TrainingRangeEnvironment3D`）、`scenes/*.tscn` 2（`BaseWorld3D` / `TowerDescent3D`）、`tests/verification/*.gd` 6、`tools/asset_pipeline/validate_base99_corner_wrapper.gd` 1、资产侧参照方 3（`props/dungeon_3d/qa/verify_tower_module_prefabs.gd`、`environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v001.tscn`——**B3 的资产本身未动，只改它指向 B2 的 `ext_resource`**、`tower_zones/battle/source/.../probe_floor_tile_components.gd`——**B1 残留的 `_v003` 地砖引用补改**） |
| 引用纯度 | 39 个「两侧都有」的 diff 块，**剥掉 `_vNNN` 后与原文逐行完全一致**（纯路径替换，无逻辑改动）；`R100` 的 61 个逐字节相同 |

**退役 1 个 v003 期探针**：`assets/art/props/dungeon_3d/qa/probe_tower_module_art.gd`（+ `.uid`）。理由：它是「列出塔楼模块各候选版本、判断哪一版符合运行时契约」的**版本比较**探针 —— 稳定路径化之后已无「候选版本」可比较，其存在前提消失。同目录 `verify_tower_module_prefabs.gd` 与 `probe_tower_palette_visible.gd` **保留**（断言活契约，已改引用，直接 `--script` 跑通）。

**验收**

| 项 | 结果 |
|---|---|
| `verify_formal_3d_asset_import` | `[PASS] 正式3D资产导入：5设施/2独立座椅/18枪的场景、材质预算、比例与节点契约均通过` ✓ |
| `verify_formal_3d_asset_gallery_visual` | `FORMAL_3D_ASSET_GALLERY_VISUAL_OK：设施朝向/人物比例与18枪侧视比例验收图已生成` ✓ |
| `aggregate core`（68 场景） | 16 红，**逐条判定为既有基线**，见下 ✓ |
| `check_asset_runtime_naming.py` | 新增违规 **0**；缩表后 `文件 1058 / 目录 13 / 备份 1；gd=50 tscn=635`，exit 0 ✓ |
| `check_asset_registry.py --scope structure` | **38**（等于基线，无新增）✓ |
| `check_documentation_contracts.py` | `issues: []` ✓ |
| `_scratch/validate_b2_index.py` | `INDEX_ASSET_REFS_OK` —— 334 个 `.import` 的 `source_file=`、781 个 tscn/gd 的 971 处 `res://assets/**` 引用，**全部可解析**；B2 七根无带版本运行资产 ✓ |
| `_scratch/verify_ledger_b2_deversion.py` | `LEDGER_B2_VERIFY_OK` —— 16 格变化、zip 29 条目不变、仅 `sheet10.xml` 变化、行数 142 不变、O 列与 AssetID 逐字节不变、B2 行 C/D 残留 0 ✓ |

**本批回归判定（本套件不是全绿，但 16 项全部为既有基线，非本批引入）**

`aggregate core` 68 场景 / 16 红：**5 项 exit 1 + 1 项 exit 143**，与 `docs/v0.1/audits/2026-09-12_engineering_audit.md` §5 的 core 基线**逐条同源且数值吻合** —— `verify_3d_performance_budget`（`HUD 267 > 171`、`HUD+预览 278 > 190`，基线原文即 267/278）、`verify_graphics_settings_ui_flow`（`没有提供完整的9项效果控制`）、`verify_base_world_flow`（`Player3D moving state has no independent locomotion animation cycle` + `locked state does not drive the amber ring`，即基线的「移动动画/locked环」）、`verify_3d_melee_feedback_flow`（`did not emit one slash and two impacts` + `readable slash/impact geometry`）、`verify_3d_enemy_behavior_flow`（`does not create a 3D floating number` + VFX 回收）、`verify_base_fixture_glow`（`SCRIPT ERROR: Assertion failed.` 后无法退出 → 180s 超时 143）。**该 6 项在 2026-09-12 审计时即为红，早于 B1/B2；本批未修改这 6 个用例或其依赖。**

**另 10 项 exit 4 全部是「资源泄漏」单一信号**：逐场景日志 `fail_markers = 0`、断言区打印全部通过（如 `verify_door_passability` 收尾 `通过 15 / 失败 0`），唯一失败信号是 `check_verification_log.py` 把 `resources still in use at exit` 记为泄漏并返回 4。10 个场景的泄漏签名**恒为同一句 `2 resources still in use at exit`**，与场景无关 —— 若由资产引起，数值必随各场景加载的不同 B2 资产而变；verbose 实测泄漏物为 BGM `rooftop_relax_b_v001.ogg`（autoload `MusicManager` 未在 `_exit_tree` 释放），**与资产无关**。该泄漏在 B1 提交时的 `aggregate smoke` 已同样出现（`verify_tower_level_blocks:4`、`verify_tower_lighting_wall_combat_regressions:4`）。反向亦成立：基线里 6 项红（`verify_base99_structural_asset_integration` 等）本批已转绿或只剩泄漏。

**决定性证据（重命名未破坏任何资产解析）**：68 个场景日志中 `Cannot open file` / `Failed loading resource` / `Failed to load` / `does not exist` / `No loader found` = **0 条**；`SCRIPT ERROR` 仅 `verify_base_fixture_glow` 1 处（既有）；B2 五根套件路径未出现在任何错误行。`preload` 是编译期解析，若有漏改的 `res://` 会立刻炸掉整个脚本 —— 实测没有。

**环境备注**：本机跑套件时最终退出码可能被 safe-delete 守卫污染（脚本 EXIT trap 的 `rm -rf <temp 工作区>` 被拦，返回非零覆盖原退出码 → 打印了 `VERIFICATION_SUITE_OK` 却 `EXIT=1`）。**判定一律看 `VERIFICATION_SUITE_OK` / `FAILED_SCENE` 行，不看裸退出码。**

**台账回填**（`_scratch/patch_ledger_b2_deversion.py`，16 格，带「期望旧值」漂移守卫）：`3D-场景通用` 的 r5/r7/r8/r42–r46/r48/r61 的 C/D 列去版本；**O 列版本事实与 AssetID 逐字节保留**。复验见上 `verify_ledger_b2_deversion.py`。备份 `*.xlsx.bak_b2_deversion`（gitignored）。

**新增的工具层缺陷**（两条，均已修/已建护栏）

1. **`git status` 在本仓不可信（危险）**：本批暂存 186 项、索引与工作区实际有 **16** 处差异，而 `git status --porcelain` 只报了 **1** 处。漏掉的 15 个是 `godot --import` 重建后的 `.glb.import` —— 索引里存的仍是**重建前**的内容（`source_file=` 指向已被删除的 `_v003.glb`）。若按 `status` 判断「已干净」直接提交，仓库里会留下指向不存在目标的 `.import`，Godot 加载即失败。**结论：暂存完整性一律用 `git diff --name-only` 判定，不用 `git status`。**
2. **`deversion_batch.py --plan` 在已应用批次上误报**：B2 应用后再跑 `--plan` 会打印「superseded 声明要删的废弃版不存在」，读起来像数据损坏，会诱导操作者去「恢复」一个**故意删掉**的文件。已加 `batch_applied()`：能判定为本批已应用时，打印「本批已应用：superseded 声明的废弃版已删除、正式版已去版本化（N 项）……（无需重复执行；这条不是错误，是正常终态）」并返回 0。`b1 --plan` 路径不受影响。

**新增护栏**：`_scratch/validate_b2_index.py` —— 直接读**暂存索引 blob**（`git cat-file --batch` 批量，不用工作区）校验：① 每个 `.import` 的 `source_file=` 可解析；② 每个 `.tscn`/`.gd` 的 `res://assets/**` 引用可解析；③ B2 七根无带版本运行资产。**这一步专门用来兜住缺陷 1**，后续每批都应跑同构检查。

**残留（转后续批）**：无。B1 残留的 2 个 zone 场景本批已清；五根套件引用扫描为 0。

**一个既有噪声（非本批、待主人决定）**：`source/entry_safe_room/v007/qa/probe_floor_tile_components.gd` 之类**资产侧** `.gd` 不在 P4 门禁的引用扫描口径内（该门禁只数 `src/**/*.gd` 与 tscn），因此 B1 期间漏改、由 B2 顺手补齐。若希望后续批次自动发现这类「资产侧引用方」，需要把扫描口径扩到 `assets/art/**/*.gd`（改动小，但会改变欠账数，需独立一批）。

### B3 预备（2026-09-17 调研，**未开工**）

用 `_scratch/scan_batch_debt.py assets/art/environments/base_facility_3d` 出的实测数据（该脚本参数化，B4–B9 可直接复用）：

| 项 | 实测 |
|---|---|
| 门禁口径欠账 | `components/`+`runtime/` 下 **152 个 `.glb`（各带 1 个 `.glb.import`）+ 139 个 `.tscn` = 443**，与批次表一致 |
| 版本目录 | **0 个**（B3 无 `vNNN/` 目录，比 B1/B2 少一层 `collapse`/`keep_version` 规则） |
| 同子树内其他带版本文件 | `components/**` 另有 3 个 `.json`（不计入门禁） |
| `source/` 侧（豁免） | 14 `.blend` / 4 `.json` / 3 `.png` |
| 备份残留 | 3 个 `source/**/previews/*.png.import<digits>.tmp`（在豁免区，留 B9） |

**引用面 67 条 / 35 个文件**（远超批次表写的「8」——8 只是 `src/**/*.gd` 的硬引用数）：

| 位置 | 条数 | 性质 |
|---|---|---|
| `src/world3d/` | **8**（3 文件） | **硬引用**，`preload` 编译期解析，必须与本批同批改 |
| `tests/verification/` | 26（16 文件） | 断言磁盘现状的探针，同批改 |
| `tools/asset_pipeline/` | 25（12 文件） | 生成 / 导入 / 台账同步脚本 |
| `scripts/blender/` | 8（4 文件） | Blender 装配脚本 |

`src/` 侧 8 处明细：`DungeonRoom3D.gd` 6 处（`:37` corner_l_5m v004、`:54` wall_plain_5x12 v002、`:57` floor_plain_5m v001、`:60` floor_rivet_5m v001、`:63` wall_door_5x12 v004、`:66` door_lift_2p2x2p5 v002）、`TowerDescent3D.gd:12`（door_lift_2p2x2p5 v002）、`TowerFloorStage3D.gd:40`（corner_l_5m **GLB** v002）。

⚠️ **`DungeonRoom3D.gd` 同时是 B2 与 B6 的引用方** —— B3 会再改它 6 处。开批前必须先确认 B2 提交后该文件没有未提交改动。

**两种目录布局混存（B3 特有的复杂度）**：

1. **两级**（同 B1/B2）：`components/<slug>/<slug>_visual_top3d_vNNN.glb`，如 `env_base99_corner_l_5m/`。
2. **三级**（B3 特有）：`components/env_base99_<批次>_v021/<slug>/<slug>_visual_top3d_vNNN.glb` —— 中间那层是**批次分组目录**（`env_base99_remaining_facilities_v021` / `env_base99_wall_contents_v021` / `env_base99_structural_v021`），目录名自身也带 `_vNNN`。写 `rules` 时必须把这一层一并去版本化。

**同名收敛检查**：A 类（同目录多版本，剥后缀后合并属正常）**80 组**；B 类（**跨目录两代并存，剥离会互相覆盖，须人工定策略**）**1 组**：

```
runtime/env_base99_floor_visuals_v017/…_root_top3d_v001.tscn
runtime/env_base99_floor_visuals_v020/…_root_top3d_v002.tscn
runtime/env_base99_floor_visuals_v021/…_root_top3d_v003.tscn
runtime/env_base99_floor_visuals_v021/…_root_top3d_v004.tscn
```

→ 归一后都会落到 `runtime/env_base99_floor_visuals/env_base99_floor_visuals_root_top3d.tscn`。需先查引用方（`verify_base99_floor_visuals_v021.gd` 等）确认留哪一代。

**开批第一步**：在 `deversion_batch.py` 的 `BATCHES` 里新增 `b3` 定义（现存只有 `b1`/`b2`，`--plan b3` 会报 `invalid choice`）——含 root + rules（两级/三级各写一条）+ 上述 B 类冲突的处理策略。

### P4 执行记录（2026-09-17，已完成）

**产出**：`scripts/check_asset_runtime_naming.py`（纯标准库）+ 欠账快照 `scripts/asset_runtime_naming_debt.json`。

**扫描口径**

| 类别 | 判定 |
|---|---|
| 运行资产文件 | `assets/art/**` 下（`source/` 整树豁免）文件名匹配 `_v\d{3}\.(glb\|tscn)(\.(import\|uid))?` |
| 版本目录 | `assets/art/**` 下（`source/` 豁免）任一层目录名匹配 `v\d{3}` |
| 备份残留 | 文件名含 `.bak_`，单列一类（对应 N5） |
| 引用计数 | `src/**/*.gd` 与 `assets/art`/`scenes`/`tests`/`src` 下 `.tscn` 里的 `res://…_vNNN.(glb\|tscn)` 引用数 |

**退出码语义（快照 = 「磁盘现状必须逐项一致」）**

| 码 | 含义 |
|---|---|
| 0 | 与快照一致（打印剩余欠账规模） |
| 1 | **新增违规**：快照之外出现带版本文件/目录/备份，或引用计数上升 |
| 2 | **快照陈旧**：快照内条目已消失或引用计数下降 → 必须 `--update-debt` 缩表 |

退出 2 是刻意设计的强制项：每完成一批原子批就必须缩表，否则这张表会重新变成假账（做法沿用仓库既有的 `LEGACY_PALETTE_EXEMPT_GLBS` 双向断言先例）。另提供 `--json` 供机器消费。

**基线实测（2026-09-17）**：**1345 文件 / 22 版本目录 / 14 备份残留 / gd 引用 112 / tscn 引用 702**。文件类型 = 527 `.glb` + 527 `.glb.import` + 291 `.tscn`。受影响共 **21 个套件**（构成 §4.1 分批依据）。

**接入**：`run_verification_suite.sh` 在 `core|aggregate|full` 三条路径的**场景全过之后**追加该门禁（失败打印 `reason=asset_runtime_naming` 或 `reason=asset_runtime_naming_debt_stale`）；`AGENTS.md` 的交付前检查已加入该命令与命名契约。

**验收**

| 项 | 结果 |
|---|---|
| 无快照时 | 退出 1 并提示先建基线 |
| 建立基线 | `DEBT_UPDATED … files=1345 dirs=22 backup=14 refs(gd=112 tscn=702)` |
| 复跑 | `ASSET_RUNTIME_NAMING_OK …` 退出 0 |
| 自测·新增违规 | 临时放一件 `_v999.tscn` → 退出 **1** 并点名该文件；已删除 |
| 自测·快照陈旧 | 临时移走一件已登记的备份残留 → 退出 **2** 并点名；已还原 |
| 自测·`--json` | 字段齐全，`remaining` 计数正确 |
| 集成（套件真的会调用它） | 用假 Godot 桩跑 `GODOT_BIN=<stub> bash scripts/run_verification_suite.sh aggregate smoke` → 6 个场景全过 → 打印 `ASSET_RUNTIME_NAMING_OK …` → `VERIFICATION_SUITE_OK suite=aggregate count=6` |
| `bash -n` 语法 | 通过 |

**未覆盖（明确不做）**：不校验 `asset_manifest.json` / 节点 `metadata/asset_version` 是否存在（那是 P2 生成器侧的必填校验）；不校验 `.import` 内容与 UID 一致性；不判定某件资产是否仍被引用（属 B* 批的第 ①/⑥ 步）。

**顺带实测（与本阶段无关但需记录）**：真实跑 `aggregate smoke` 时 3 个场景红 —— `verify_3d_only_project_structure:1`（`Retired 2D directory returned: assets/art/characters/player/chr_player_capsule01`，该目录在 `a0871af` 就已入库，**非本次改动引入**）、`verify_tower_level_blocks:4` 与 `verify_tower_lighting_wall_combat_regressions:4`（退出码 4 = 既有资源泄漏，见 §6 基线备注）。这 3 项在动手做 P4 前就已存在，需要在开 B 批之前先确认基线。



回滚：每批次以独立提交交付；不使用工作区备份文件。

风险提示：B2 的「稳定命名重命名」是体量与耦合的双高点（156 文件 / 56 处 gd 引用），必须脚本化 + 分批，禁止手工逐个改。

## 5. 存量清单（B1 战局区块已实测；其余套件由 P4 脚本按批出）

| 位置 | 内容 | 引用状态 |
|---|---|---|
| `runtime/entry_safe_room/v003`、`v004`、`v005` | 空目录（0 个 `.tscn`） | 无 |
| `components/entry_safe_room/v003`、`v004`、`v005` | 空目录（0 个 `.glb`） | 无 |
| `components/entry_safe_room/v006` | 24 个 GLB | 无 runtime、无代码/场景引用；仅 v004 组件元数据 `carries_room_art_from` 提及源侧 `source/entry_safe_room/v006`（保留） |
| `components|runtime/common_components/` 的 5 组 `_v003` | wall_standard_5m、wall_door_5m、door_5m、floor_tile_r01_c01、floor_tile_r01_c02 的 GLB/tscn | src 只 preload `_v004`；`_v003` 仅被自身 tscn 的 `ext_resource` 与 `source/common_components/v003/` 的 manifest/catalog 引用 |
| 战局区块 `.bak_*` 18 个 | `*.glb.import.bak_pre_palette` 8、`*.tscn.bak_pre_generate` 5、源侧备份 5 | 备份，非运行资产 |
| 验证器与台账脚本（P2 登记，**必须与重命名同批改**） | `common_components/v004/qa/verify_v004_glb.py`、`update_ledger_rows_v004.py`、v003 的 `register_*_ledger_rows.py` / `verify_*_ledger_patch.py`、`sync_catalog_export_status.py` | 这些脚本按确切文件名/路径断言磁盘现状或历史补丁；早改会立刻变红，晚改会漏检——只能与 P6 重命名同批 |
| `assets/art/asset_import_manifest_v001.json` | 全部 `*.glb` 字段实测带 `_vNNN` | 数据侧，与 P6 同批去版本；`generate_runtime_scenes.py` 已按稳定路径消费并硬拦未重命名的项 |
| 角色链（待决） | `update_character_registry.mjs` 与 `production/<version>/runtime/*.tscn` | 属 `player-avatar-asset-standard` 版本契约，建议单列一轮 |

其余套件（environments 558、props 86、characters 79、weapons 76、vfx 11、enemies 6、ui 2）在 P6 第①步由脚本出清单，不在本文件手工枚举。

## 6. 验收命令

```bash
export GODOT_BIN="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
bash scripts/run_verification_suite.sh core
bash scripts/run_verification_suite.sh scene probe_safe_room_v007_integration
bash scripts/run_verification_suite.sh scene verify_tower_grid_component_alignment
python3 scripts/check_documentation_contracts.py
python3 scripts/check_asset_registry.py --scope structure
python3 scripts/check_asset_runtime_naming.py
```

基线备注：`check_asset_registry.py --scope structure` 在基线即有 38 项问题（424–428 行状态与总览公式），只判「是否新增」；`check_verification_log.py` 会把 `resources still in use at exit` 记为泄漏并返回 4，本仓库塔楼相关场景基线即有 2 处，退出码 4 不等于回归。

**core 套件基线（判「是不是本批引入」的唯一起点）**：见 `docs/v0.1/audits/2026-09-12_engineering_audit.md` §5 与 `docs/v0.1/audits/evidence/core_results.json`（61 项 / 11 项 exit 1 / 1 项 exit 143）。B2 复跑 `aggregate core` 为 68 项 / 16 红，**16 项逐条落回该基线**（6 项断言类 + 10 项纯泄漏），详见「B2 执行记录 › 本批回归判定」。**不要用「core 是否全绿」当批次判据**，要用「红项集合是否 ⊆ 基线」。

**本机退出码陷阱**：safe-delete 守卫会拦下套件 EXIT trap 的临时工作区 `rm -rf` 并返回非零，覆盖掉脚本原本的退出码（表现为打印 `VERIFICATION_SUITE_OK` 但 `EXIT=1`）。**一律按 `VERIFICATION_SUITE_OK` / `FAILED_SCENE` 行判定，不看裸退出码。**

## 7. 不在本次范围

- `source/**` 的 Blender 版本历史策略（美术侧继续保留 v02/v03 后缀）。
- 资产内容本身的任何改动：本计划只改路径、命名、引用与登记。
- `assets/art/shared/`（色盘等非版本化资产）。
