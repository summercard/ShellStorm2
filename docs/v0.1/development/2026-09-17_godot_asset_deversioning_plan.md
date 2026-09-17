# Godot 侧资产替换去版本化 —— 执行计划

日期：2026-09-17；记录ID：待补；工程版本：0.1.0；状态：**P1 / P2 / P4 已完成；原子批 B1（`tower_zones/battle`）、B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）、B3（`environments/base_facility_3d`，443 欠账 / 体量最大）、B4（`environments/rooftop_shelter_3d`，311 欠账 / 扁平 runtime 多代并存）、B6（`vfx/*` + `ui/*` + `environments/training_range_3d`，14 场景 / 纯改名批）均已完成（2026-09-17）；**按 D3 决策，B5 / B7 / B8 冻结（不再执行）**，B9 降级为可选清理**。
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
| D3 | 存量带版本名是否必须清零 | **冻结（2026-09-17 用户指示）**：既有带版本号的文件名**视为正式命名**，不再追改；门禁只保证「**不新增**」—— 快照内的既有项不再当欠账追。已完成批次不回滚；未执行的 B5 / B7 / B8 取消，B9 与命名无关部分降级为可选 |

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
| **B3** ✅ **已完成（2026-09-17）** | `environments/base_facility_3d` | **443（体量最大）** → 改名 266 / 删除 180 / 改参照 23 文件·46 处 | 8（另 14 处散在 tests/assets/tools，同批改） → 已清零 | 99F 基地，回归面最广。三级批次目录一并去版本；两处同名冲突已裁决；详见下「B3 执行记录」 |
| **B4** ✅ **已完成（2026-09-17）** | `environments/rooftop_shelter_3d` | 311 → 改名 145 / 删除 158 / 改参照 3 文件·4 处（另套件内 69 处） | 0（无 `.gd` 耦合） | **扁平 runtime + 多代并存批**：为工具新增 `obsolete_globs` 整代淘汰模式；`layout_v017/` → `layout/`；规范名归当前在用代 v021、旧代加 `_genNNN`；50m 代经台账核对后恢复 v011、只删 v003–v010；详见下「B4 执行记录」 |
| **B5** ❄ **已冻结（2026-09-17，D3）** | `weapons/weapon_3d` + `weapons/melee_3d` | 130（保留） | 14 | 原本耦合 `WeaponModel3D.gd`(10)、`Player3D.gd`(2)、`ItemModelFactory3D`、`TrainingRack3D`。按 D3 不再去版本化：`GUN_VISUAL_SCENES`/`MELEE_VISUAL_SCENES` 里的 `_v001`/`_v003` 视为正式命名 |
| **B6** ✅ **已完成（2026-09-17）** | `vfx/combat_3d` + `vfx/environment_3d` + `vfx/visibility_3d` + `ui/inventory_3d` + `ui/pause_3d` + `environments/training_range_3d` | 14 → **纯改名批**：改名 14（13 R100 + 1 R095）/ 删除 0 | 18 → 已清零（另散在 tests / 资产侧场景，同批改） | **唯一版本批**：六套件内无 `.glb`、无版本目录，故 0 删除。`VfxPool3D.gd`(7)、`CombatEffectPool3D`、`Projectile3D`、`Enemy3D`、`PlayerMeleeCombat3D`、`ui/*`(5)；顺带修 dust 场景陈旧 UID；详见下「B6 执行记录」 |
| **B7** ❄ **已冻结（2026-09-17，D3）** | `enemies/enemy_3d` + `elite_3d` + `bosses_v01` + `environments/boss_arenas_v01` | 16（保留） | 9 | 原耦合 `BossContentCatalog.gd`(6)、`EliteContentCatalog`、`Player3DStateGallery`、`Dungeon3D`。按 D3 不再执行 |
| **B8** ❄ **已冻结（2026-09-17，D3）** | `characters/player` | 144（保留） | 1 | 含 13 个 `production/vNNN/` 目录；原本还绑「角色链版本契约」待决项。按 D3 不再执行 |
| **B9** ⚪ **降级为可选清理（2026-09-17，D3）** | 纯清理：空版本目录 / 孤儿 GLB / `.bak_*` | 22 目录 + 14 备份 | — | 与命名无关的部分（空目录、备份残留）仍可做，但非法务；**欠账快照清零已取消**（D3 后快照即「已接受的既有命名」） |

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
### B3 执行记录（2026-09-17，已完成）

**范围**：`assets/art/environments/base_facility_3d`（99F 基地，回归面最广）。门禁口径欠账 **443**（152 `.glb` + 139 `.tscn`，各带 sidecar）全部清零；执行后 B3 根内 **0 带版本文件、0 带版本目录**。

**改名 / 删除明细**（暂存区实测：**266 改名 + 180 删除 = 446 条目**，全部落在 B3 根内，越界为 0）

| 类别 | 改名 | 删除 | 备注 |
|---|---|---|---|
| `.glb` | 92 | 60 | 92 个逐字节改名（R100，内容不变）；60 个为被取代的冗余代 |
| `.glb.import` | 92 | 60 | 改名后由 `godot --import` 重新生成（`source_file=` / `dest_files=` 重写） |
| `.tscn` | 82 | 57 | 82 个**全部**含内部 `ext_resource` 改写（相似度 R057–R098，无逐字节相同者） |
| `.json` | 0 | 3 | `env_base99_floor_details` / `floor_full_replacement` 三代的 `*_runtime_manifest_v*.json`，随被取代代退役 |
| **合计** | **266** | **180** | 暂存区 R100 仅 92（即 92 个 `.glb`）；其余 174 为低相似度的内部改写型 rename |

**三级目录布局（B3 特有）**：`components/env_base99_<批次>_v021/<slug>/…` 的**中间批次分组层**一并去版本 —— `env_base99_structural_v021` → `env_base99_structural`、`env_base99_wall_contents_v021` → `env_base99_wall_contents`、`env_base99_remaining_facilities_v021` → `env_base99_remaining_facilities`、`env_base99_floor_visuals_v021` → `env_base99_floor_visuals`；`runtime/` 侧同构。

**两处同名冲突的裁决（执行前已取证）**

1. **`corner_l_5m` 跨代「规范名」冲突**：`*_root_top3d_v005.tscn`（美术壳）与 `*_root_top3d_v004.tscn`（碰撞壳）剥后缀后同名。**v005 保留规范名** → `env_base99_corner_l_5m_root_top3d.tscn`；**v004 改名** → `env_base99_corner_l_5m_collision_top3d.tscn`。落地同时改写 `tools/asset_pipeline/validate_base99_corner_wrapper.gd` 的 `VISUAL_WRAPPER` / `COLLISION_WRAPPER` 两条常量。
2. **`floor_visuals` 四代并存**（v017/v020/v021 两目录 + v021 内两代）：保留最高代 **v004 → `env_base99_floor_visuals/env_base99_floor_visuals_root_top3d.tscn`**，v001/v002/v003 三代删除。`loft_floor_finish` 因父目录不同（`env_base99_floor_visuals/loft_floor_finish/` 与 `env_base99_loft_floor_finish/`）不构成冲突，两代均保留。

**引用改写（`preload` 是编译期解析，必须与本批同批完成）**：**23 个文件 / 46 处路径**

| 位置 | 文件 | 处数 |
|---|---|---|
| `src/world3d/` | `DungeonRoom3D.gd`、`TowerDescent3D.gd`、`TowerFloorStage3D.gd` | 8（与预备调研一致） |
| `tests/verification/` | `verify_base99_*.gd` 10 + `audit_base99_v022_lighting.gd` 1 + 其余 5（`verify_base_facility_interaction_zones` / `verify_base_overhaul_flow` / `verify_common_floor_tile_components_v004` / `verify_rollup_reimport` / `verify_scene_facility_shared_palette`） | 26 |
| `assets/art/` | `environments/tower_zones/base/runtime/zone_base.tscn`(9)、`props/dungeon_3d/qa/probe_door_leaf_reference.gd`(2)、`environments/tower_zones/battle/source/common_components/v003/qa/probe_floor_tile_components.gd`(1) | 12 |
| `tools/asset_pipeline/` | `validate_base99_corner_wrapper.gd` | 2 |

基建同批：`tools/asset_pipeline/deversion_batch.py` 新增 `b3` 批定义（+127/−17，含两级/三级两条规则与上述两处冲突策略）；`_scratch/scan_batch_debt.py` 精简（+4/−28）。

**新增护栏（后续每批都应跑）**：`_scratch/b3_staged_closure.py` —— 直接读**暂存索引 blob**（`git ls-files --cached` + `git show :<path>`），把 B3 根内 195 个暂存文本文件的 `res://` 引用逐个解析到规范化路径（含 `..` 解析），断言目标存在于索引。**结果：悬空引用 0**（生成物 `.godot/`、源资产 `source/`、`.blend` 按契约豁免）。同族：`_scratch/b3_ref_keep_check.py`（保留代与存活引用所指代一致：333 处引用 0 冲突）、`_scratch/b3_closure_check.py`（删除闭包内 0 引用指向待删版本）。**全仓版**：`_scratch/index_refs_scan.py` —— 用 `git ls-files -s` 取 blob SHA 再 `git cat-file --batch` 批量读 **2417 个**索引文本文件，覆盖 `.gd/.tscn/.tres/.import`（引擎加载期解析，计入失败）与 `.py/.md/...`（人工参考）；识别「目录路径引用」与 `source/`、`.blend`、`outputs/` 豁免；**核心断言 = 悬空引用中命中 B3 根者必须为 0** → `B3_DANGLING=0`（其余 31 条为既有欠账：根级 `_demo_components.tscn`、5 个退役 `scenes/*.tscn`、以及 `verify_3d_only_project_structure.gd` 里**故意断言不存在**的旧场景路径）。

⭐ **该全仓扫描当场揪出 1 处真漏改**（正是计划文档第 262 行记的「资产侧 `.gd` 不在 P4 门禁口径内」噪声）：`assets/art/environments/tower_zones/battle/source/common_components/v003/qa/probe_floor_tile_components.gd:36` 的 `REFERENCE_L_CORNER` 仍指向已改名的 `..._corner_l_5m_root_top3d_v005.tscn`。B1 期间靠 `probe_floor_tile_components.gd` 暴露过一次，B2 顺手补过，本批再次复现 —— **说明把 P4 引用扫描口径扩到 `assets/art/**/*.gd` 是必要的（该决定仍待主人拍板，见第 262 行）**。已随本批改为 `..._root_top3d.tscn`。

**台账（`assets/registry`，外科式 XML 补丁，就地写）**：共 **77 格 = 75 + 2**。
- 只改**运行路径列**：`3D-场景通用` C/D **34** 格、`3D-设施` C/D **14** 格、`资产主表` O 列 **27** 格（含 `corner_l_5m` 冲突解到 `_collision_top3d.tscn`）。
- 收尾 2 格：`资产主表` D65/D66 的「目录（18 个 GLB）」`inlineStr` 形式 —— 去目录层 `_vNNN`、保留全角括号说明。
- **历史列一律不动**：逐格复验定位，剩余 63 个非 `source` 的 B3 带版本单元格**全部**落在他处 —— `3D-设施!P` 6 格、`资产主表!P` 11 格、`资产主表!Y` 46 格；**路径列（C/D/E/O）残留 = 0**。
- 保真：zip 29 条目集合不变，仅 `sheet2` / `sheet10` / `sheet11` 三个成员变化；dimension / mergeCell / dataValidation / row / c 计数不变；写前 `shutil.copy2` 备份 `.bak_b3_deversion` + `.bak_b3_deversion_followup`。
- `assets/art/asset_import_manifest_v001.json` **零改动**（该文件登记的是**源版本事实**，属契约豁免 —— 不去版本）。

⚠️ **一次事故与回滚（重要教训）**：初版台账补丁脚本做了**整文件无差别子串替换**，误改了台账 P/Y 历史列与 `asset_import_manifest_v001.json` 的版本事实列（违反「版本号只允许存在于 `source/` / manifest / 台账 O 列 / Prefab `metadata/asset_version`」契约）。复验残留 token 时发现（台账 17 + manifest 13），**立即按备份逐字节还原（sha 与备份逐字节一致），零损失**；重写为「只改运行路径列」范式后才落盘。→ **结论：台账补丁必须白名单化（sheet + 列 + 期望旧值），禁止全文替换。**

⚠️ **B2 缺陷 1 在本批复现并被兜住**：本批 92 个 `.glb.import` 由 Godot 重建后属**未暂存改动**，而暂存区里它们仍保留 `git mv` 时的旧内容（`source_file=` 指向**已被删除**的 `_vNNN.glb`）—— 与 B2 完全同形。提交前用 `git diff --name-only` 逐项核对并 `git add`，已将 92 个 `.import` 的暂存 blob 对齐为去版本后的 `source_file` / `dest_files`。**`git status` 在本仓仍会漏报（B2 结论继续有效）。**

**欠账快照缩表**：文件 **1058 → 615**（还清 B3 的 443）、目录 13、备份 1、gd 引用 **50 → 42**、tscn 引用 **635 → 242**；`check_asset_runtime_naming.py` exit 0（0 新增违规）。

**验收**

- 专属探针：`probe_safe_room_v007_integration` → `SAFE_ROOM_V007_INTEGRATION_OK`（经 `run_verification_suite.sh scene`，非 headless）；`probe_tower_palette_visible` → `TOWER_PALETTE_VISIBLE_OK`（`--headless --script res://assets/art/props/dungeon_3d/qa/probe_tower_palette_visible.gd`）。
- `run_verification_suite.sh aggregate core` → `count=68 failed=6`，6 项**全部 ⊆ 2026-09-12 审计 §5 基线**（该基线实测 **61 场景 / 12 非零**）：`verify_3d_enemy_behavior_flow`(1)、`verify_3d_melee_feedback_flow`(1)、`verify_base_fixture_glow`(143，断言后无法退出 → 180s 超时)、`verify_base_world_flow`(1)、`verify_3d_performance_budget`(1)、`verify_graphics_settings_ui_flow`(1)。**非本批引入。**
- **4 个基线红项转绿**（本批净收益）：`BASE99_STRUCTURAL_ASSET_INTEGRATION_OK`、`BASE99_WALL_CONTENT_V021_OK`、`BASE99_REMAINING_FACILITIES_V021_OK`、`SCENE_FACILITY_SHARED_PALETTE_OK`（`glbs=104 materials=849 shared_texture=1 lossless_no_mipmap=1 legacy_exempt=2`）。
- 门禁：`check_asset_runtime_naming.py` exit 0；`check_asset_registry.py --scope structure` = **38**（等于基线，无新增）；`check_documentation_contracts.py` issues `[]`；`_scratch/b3_staged_closure.py` 悬空 **0**；`_scratch/index_refs_scan.py` → `B3_DANGLING=0`（全仓 2417 个索引文本文件）。

**残留**：B3 根内门禁口径 **0 欠账**；`source/` 侧 3 个 `*.png.import<digits>.tmp` 备份残留按预备约定留 **B9**。台账剩余 63 个历史列 token 为**有意保留**（P=关联文件清单、Y=变更日志，是记录不是路径）。


### B6 执行记录（2026-09-17，已完成）

**范围**：`assets/art/vfx/combat_3d` + `vfx/environment_3d` + `vfx/visibility_3d` + `ui/inventory_3d` + `ui/pause_3d` + `environments/training_range_3d`。与 B1–B3 共用 `src/world3d/DungeonRoom3D.gd`，按 §4.1 串行约束紧随 B3 执行。

**形状与 B1–B3 完全不同 —— 本批是「纯改名批」**

- 欠账 14 个，**全部是 `.tscn`，没有一个 `.glb`**；六套件内**无版本目录**、无冗余代次。
- 14 个场景全部是「唯一版本」（仅 `_v001`）→ **0 删除**。
- 目录布局属命名规范 L153 承认的「**非标准三件套布局**」：资产直接放在套件根，不在 `components/` + `runtime/` 下。
- 门禁口径内的运行资产后缀只有 `.glb` / `.tscn`（`RUN_ASSET_SUFFIX`）；`.png`/`.jpg`/`.tres`/`.json` 上的 `_vNNN` **全仓系统性存在 646 个**（B4 rooftop、B5 weapons 各有整代预览图）—— 这是项目**刻意的口径收窄**。故 B6 **不碰 `.png`**（2 个 `*_v001.png` 预览图保留）。若要去掉需先改命名契约，属独立决策。

**改名（步骤②）**：`tools/asset_pipeline/deversion_batch.py` 新增 `b6` 批次定义，`b6 --plan` 通过 `check()`（源存在 / 目标不冲突 / 全部被 git 跟踪），`b6 --apply-renames` 执行。

- 13 个 `R100`（逐字节纯改名）+ 1 个 `R095`（dust 场景，因同时修了 UID）。
- 明细：`vfx/combat_3d` × 8（`vfx_combat_kit` / `damage_number` / `explosion` / `heal_number` / `impact` / `melee_impact` / `melee_slash` / `muzzle_flash`）、`vfx/environment_3d` × 2（`base99_dust_particles` / `hazard_field`）、`vfx/visibility_3d` × 1（`player_flashlight`）、`ui/inventory_3d` × 1（`ui_item_model_icon_root`）、`ui/pause_3d` × 1（`ui_pause_overlay_screen`）、`environments/training_range_3d` × 1（`env_training_range_kit_top3d`）。
- 改名工具报告 **0 处内部 `ext_resource` 改写** —— 符合预期，这些场景的 `ext_resource` 都指向 `src/**/*.gd`，不指向 B6 资产自身。

**顺带修复：陈旧 external UID**

`vfx_base99_dust_particles_root_top3d.tscn` 引用的调色板 uid 为 `uid://c6amwgnoml5yf`，而全仓唯一 `assets/art/vfx/textures/glow_32.png` 的真实 uid 是 `uid://duehsq4qikpex`；旧 uid 仅被此一处引用 → 判为陈旧错 uid。按 bytes 就地改写（CRLF 保真、长度不变）后 Godot 不再回退文本路径。

**引用改写（步骤③④）**：`b6 --fix-code-refs` → **21 文件 / 28 处**，与独立清点的引用面完全吻合。

- `src/**/*.gd` × 12、`tests/verification/*.gd` × 4、`scenes/*.tscn` × 4、`assets/art/environments/base_facility_3d/**/*.tscn` × 1。
- 含串行耦合点 `src/world3d/DungeonRoom3D.gd`。
- 计划文档原列「`.gd` 引用 18」漏了 `src/combat3d/WeaponModel3D.gd:14`（它引用 `vfx_combat_kit_root_top3d_v001.tscn`），实扫时补齐。
- `.py` 侧 4 处带版本引用为**设计内残留**（工具与门禁都刻意排除 `.py` 历史导入脚本）。

**步骤⑤ Godot `--import`**：0 ERROR。**未触发调色板陷阱** —— `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` 的 `detect_3d/compress_to` 仍为 **0**、文件零改动（B6 无 `.glb`，故无 `.import` 重建，无 B2 缺陷 1 的 `.import` 陈旧问题）。

**步骤⑥ 验收**

- `run_verification_suite.sh aggregate core` → `count=68 failed=6`，6 项与 B3 完全同一组、**全部 ⊆ 2026-09-12 审计 §5 基线**：`verify_3d_enemy_behavior_flow`(1)、`verify_3d_melee_feedback_flow`(1)、`verify_base_fixture_glow`(143)、`verify_base_world_flow`(1)、`verify_3d_performance_budget`(1)、`verify_graphics_settings_ui_flow`(1)。**非本批引入。**
- B6 主题覆盖已确认：`verify_vfx_pool_lifecycle`、`verify_3d_melee_combat_flow`、`verify_training_range_3d_flow`、`verify_3d_inventory_weapon_flow`、`verify_weapon_attachment_inventory_flow`、`verify_tactical_inventory_minimap_flow`、`verify_pause_game_save_reset_flow`、`verify_3d_flashlight_charge_flow`、`verify_monster_ai_light_effects` 均在 68 集合内。
- 日志 `Cannot open file` / `Failed loading resource` / `No loader found` = **0**；提及六套件的行只有场景标题，无错误。
- 本批改过的 4 个 verifier 中，`verify_graphics_settings_ui_flow`、`verify_pause_game_save_reset_flow` 在集合内；`verify_base99_dust_vfx`、`verify_base99_updates_v022` 属**既有 6 个「无 `.tscn` 场景」孤儿 verifier**（本批之前即如此，非本批造成），已逐路径核验其 6 个 `res://` 资源全部存在（`load()` 为运行时解析，无编译期风险）。

**步骤⑦ 台账回填 + 缩表**

- 台账 xlsx 经 `_scratch/patch_ledger_b6_deversion.py` 外科式白名单补丁落盘：**3 个成员 / 17 格**（`3D-场景通用!C` 1 + `3D-特效!D` 10 + `资产主表!O` 6）。
- 保真：zip 条目 **29 → 29**（集合不变）；内容变化仅 `sheet2`（资产主表）/ `sheet10`（3D-场景通用）/ `sheet17`（3D-特效）三个目标成员；`sharedStrings.xml` 零改动。
- 路径列（C/D/O）带版本残留 **0**；剩余 7 个带版本 token 全在 `3D-特效!Q`（「已实装；Prefab=… + 脚本=…」实现说明散文列）+ 1 个在 `资产主表!Y145`（变更日志）——**记录列按白名单有意保留，同 B3 对 P/Y 的处置**。
- `check_asset_runtime_naming.py --update-debt` 缩表：文件 **615 → 601**（−14）、目录 13、备份 1、gd 引用 **42 → 24**、tscn 引用 **242 → 236**（−6，= 4 个 scenes + 1 个 B3 资产场景 + 1 处）；门禁 exit 0。

**步骤⑧ 提交**：单独原子提交（详见提交信息）。

**基础设施修正**

- `tools/asset_pipeline/deversion_batch.py`：新增 `b6` 批次定义。
- `scripts/check_asset_runtime_naming.py`：**文档串与实现不一致** —— 实现扫的是整个 `assets/art/**`（仅 `source/` 豁免），原文只写 `components/`、`runtime/`。B6 的「非标准三件套布局」正是暴露此不一致的批，已修正文档串。
- `_scratch/index_refs_scan.py`：由 B3 专用（单一 `B3_ROOT`）**泛化为全部已去版本化批次根**（B1/B2/B3/B6 共 15 个根），逐根给出悬空归属。

**验收门禁**：`check_asset_runtime_naming.py` exit 0；`check_asset_registry.py --scope structure` = **38**（等于基线）；`check_documentation_contracts.py` issues `[]`；`_scratch/index_refs_scan.py` → B6 根悬空 **0**。

**与 B3 的差异要点**：B3 是「改名 + 删除 + 三级目录」的重批（443）；B6 是**纯改名批**（14），无删除、无目录动作、无 `.glb`/`.import` 重建 —— 因此 B2 缺陷 1（`.import` 暂存陈旧）在本批**不会出现**，暂存完整性只需核对 14 R + 23 M + A。

### B4 执行记录（2026-09-17，已完成）

**范围**：`assets/art/environments/rooftop_shelter_3d`（311 欠账 / 无 `.gd` 耦合 / 自带 `verify_rooftop_shelter_asset_contract`）。

**形状 —— 与 B1 / B2 / B3 / B6 都不同的「扁平 runtime + 多代并存」批**

- `runtime/` 是**扁平布局**（不是 `components/` + `runtime/` 三件套），且多代同名资产并存：
  `50m_game` v003–v011（6 代）、`90x80m_game` v012–v016（5 代）、`90x80m_root_top3d.tscn` v012–v016（5 代）、
  `facilities` v017/v019/v021（3 代）、`facilities_root_top3d.tscn` v017/v019（2 代），
  另有 **`layout_v016/` 与 `layout_v017/` 两套并行的 69 件组件目录**。
- 工具原有的 `collapse` / `keep_version` / `superseded` 三种模式**无法表达「整代退役、一份不留」**，
  故为 `deversion_batch.py` 新增第 4 种模式 **`obsolete_globs`（整代淘汰）**，并让 `--apply-renames`
  跳过未跟踪旁文件（否则会把构建产物误当改名源）。

**两处人工裁决（2026-09-17 拍板）**

1. **死岛随批删除**：`layout_v016/**`(138) + `90x80m_game` v012–v016(10) + `90x80m_root_top3d` v012–v016(5)
   —— 除彼此与 `reports/*.json` 历史记录外**零外部引用**；删除前用 `_scratch/b4_preflight.py` 做「真·悬空 = 0」预检。
2. **命名归属**：规范名归**当前在用代**，旧代加 `_genNNN` 后缀 —— `..._facilities.glb` ← **v021**
   （真运行时 `tower_zones/rooftop/runtime/zone_rooftop.tscn:3` 指向它）、`..._facilities_gen017.glb` ← v017、
   `..._facilities_gen019.glb` ← v019；场景侧 `..._facilities_root_top3d.tscn` ← v017（契约代，
   被 `verify_rooftop_shelter_asset_contract.gd` 与 repair 工具认）、`..._root_top3d_gen019.tscn` ← v019。
   `runtime/layout_v017/` 目录一并去版本为 `runtime/layout/`。

**⚠️ 一处口径自我纠正：50m 代不是死岛**

初判把 `50m_game` v003–v011 当作「被 90x80m 整体取代、无消费者的代」整代删。收尾核账时发现
**`资产主表!O300` 是 50m 场景在权威台账里的唯一运行文件登记（M300 = v011、K300 = 已完成、P1）** ——
即它是有登记的正式资产，只是当前无场景引用。按核心纪律「绝不静默破坏被引用资产」，
已从 HEAD **原样恢复 v011 并改名为稳定名** `env_rooftop_shelter_50m_game.glb`
（sha 与 HEAD 逐字节相同），只删 v003–v010。源 `.blend`（29 MB）与 `reports/asset_manifest_v011.json` 始终完整保留。

**执行数据**

| 项 | 数量 | 说明 |
|---|---|---|
| 改名 | **145** | 73 `.glb`（全部 R100 逐字节）+ 70 `.glb.import`（Godot 重生成）+ 2 `.tscn`（R091 / R099，含内部 `ext_resource` 改写） |
| 删除 | **158** | `layout_v016/**` 138 + `90x80m_game` v012–v016 10 + `90x80m_root_top3d` v012–v016 5 + `50m_game` v003–v010 5 |
| 外部引用改写 | **3 文件 / 4 处** | `zone_rooftop.tscn`(1，真运行时入口) + `verify_rooftop_shelter_asset_contract.gd`(2) + `export_godot_rooftop_reference.gd`(1) |
| 套件内引用改写 | 69 处 | v017 场景 68 条 `layout_v017/components/*_v017.glb` → `layout/components/*.glb`；v019 场景 1 条 |
| `.gitignore` | 9 行 → 3 行 | 删 6 条退役 `!…` 白名单；改 3 条路径（`facilities_v017`→`_gen017`、`facilities_v021`→稳定名、`layout_v017/**`→`layout/**`） |
| 台账 | **2 格** | 白名单化补丁（只改运行路径列）：`3D-场景通用!D61`、`资产主表!O300`；`E`(source) / `P`(关联清单) 记录列按契约保留 |
| 缩表 | **601 → 290** | −311（B4 欠账全部还清）；tscn 引用 236 → 93 |

**验收**：`aggregate core` → `count=68 / failed=6`（**与 B3 / B6 完全同一组红项，⊆ 基线**）；
加载失败类 `Cannot open file` / `Failed loading resource` / `No loader found` = **0**；
两个 rooftop 契约场景 `verify_rooftop_shelter_asset_contract` / `verify_rooftop_32x32_contract`
在**最终状态**（含 50m 恢复之后）单跑均 **PASS**；
`_scratch/b4_index_imports.py` 断言 B4 根 70 个暂存 `.import`「索引 == 工作树」且 `source_file=` 全部指向存在文件（防 B2 缺陷 1）；
`_scratch/index_refs_scan.py` → **BATCH_DANGLING = 0**；三道门禁全绿（命名 exit 0 / 台账 38 = 基线 / 文档 issues `[]`）。

**两次踩到并兜住的坑**

1. **调色板陷阱在 `--import` 时被触发**：编辑器把 `设施低亮多巴胺色盘_10x10_512.png.import` 的
   `detect_3d/compress_to` 由 **0 改成 1**（会让所有 GLB 取色失真）。已 `git checkout --` 还原，
   sha1 与基线 `23d13998baa8b73524790220f88eb21614be722f` 一致。**B4 有 `.glb`，本坑必查**；
   第二次 `--import` 未再触发。
2. **49 个文件「无记录消失」**：`--apply-renames` 与 `--apply-deletes` 之间，工作区丢了一批文件
   （22 个 `layout_v016` 组件 + 27 个死岛），随后 `stage_roots()` 的 `git add -A` 把「工作区缺失」
   顺带暂存成删除，导致删除日志只报 116（实际 158）。已用三视图（HEAD / 索引 / 磁盘）逐字节核对：
   **内容级无损** —— `layout/` 与 HEAD 的 `layout_v017` 136 个文件逐字节一致（缺失 0 / 多出 0 / 内容不符 0），
   且 `git diff --cached -M` 把 33 对内容相同组件的改名源归给字典序在前的 v016 **只是展示假象**
   （修改前的 `b4_plan.txt` 证明 `collect()` 取的源 100% 是 v017）。
   **教训：本仓并行会话会抖动工作区，跨步骤的执行器不能把「工作区缺失」等同于「本步骤删除」。**

**遗留（按约定保留，非遗漏）**：`tools/asset_pipeline/repair_rooftop_v017_coordinate_contract.py`
（→ 旧 `..._facilities_root_top3d_v017.tscn`）与 `build_rooftop_v021_wrapper.py`（→ 旧 `..._root_top3d_v019.tscn` + `..._facilities_v019.glb`）
属 `.py` 一次性构建 / 修复脚本，`fix_code_refs` 刻意排除 `.py` 与 `docs/`（同 B3 / B6 先例），
其路径属**历史记录**；若要重跑须先更新路径。
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
