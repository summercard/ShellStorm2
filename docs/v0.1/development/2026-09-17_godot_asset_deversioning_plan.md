# Godot 侧资产替换去版本化 —— 执行计划

日期：2026-09-17；记录ID：待补；工程版本：0.1.0；状态：**执行中 —— P1、P2 已完成（2026-09-17），P3 未开始**。
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

## 4. 执行阶段（共 6 个）

| 阶段 | 改动点 | 完成判据 |
|---|---|---|
| **P1 规则层** ✅ 已完成（2026-09-17，见下「P1 执行记录」） | ① `godot-model-asset-import-standard` 的 L32/L46/L63、§版本与引用替换、目录模板改为「覆盖既定路径、路径不含版本」；用户级 `~/.workbuddy/skills/` 与工程 `skills_drafts/` 两份逐字节同步。② `assets/art/3D模型资产目录与命名规范.md` L10–11 目录模板去 `_v###`，§坐标与替换契约补「Godot 侧路径恒定、GLB 不含版本」。③ `docs/v0.1/10_资产与内容规范.md:5` 删去「运行时可保留按批次递增的 v021–v024 组件版本」 | 两份 skill diff 为空；`python3 scripts/check_documentation_contracts.py` 通过 |
| **P2 工具层** ✅ 已完成（2026-09-17，见下「P2 执行记录」） | ① 战局区块 `source/**/qa/export_*.py`、`build_*_prefabs_*.py`：`VERSION` 只写 manifest 与节点 meta，不进路径；v006/v007 平行脚本合并为一份带版本参数的脚本。② `tools/asset_pipeline/generate_runtime_scenes.py:43`、`export_split_facilities_and_seating.py:107-129`、`update_character_registry.mjs` 同步。③ manifest 与节点 meta 写入改为必填校验 | 同一输入连跑两次，输出路径集合与 mtime 不变；`git status` 无新增带版本路径；抽 1 件资产确认 manifest + meta 均记录了版本 |
| **P3 运行时层** | ① `DungeonRoom3D.gd`：`SAFE_ROOM_ART_VERSION` 退出路径拼接（L1007–1013 改为 `<slug>/<slug>_root_top3d.tscn`），5 条 L97–109 preload 去 `_v004`；版本降级为纯元数据。② `TowerDescent3D.gd:7-34`、`TowerFloorStage3D.gd:31-46` 及其余带版本引用的 `.gd`（共 22 个文件 / 109 行）改为去版本路径 | `bash scripts/run_verification_suite.sh core` 全绿；`probe_safe_room_v007_integration` → `SAFE_ROOM_V007_INTEGRATION_OK`；`probe_tower_palette_visible` → `TOWER_PALETTE_VISIBLE_OK` |
| **P4 门禁** | 新增 `scripts/check_asset_runtime_naming.py`：扫描 `assets/art/**/{components,runtime}/**`，出现 `_v\d\d\d\.(glb\|tscn)` 文件名或 `components|runtime/**/v\d\d\d/` 目录即失败（`source/**` 豁免）。存量未清前挂**精确路径欠账清单**（同 `LEGACY_PALETTE_EXEMPT_GLBS` 先例），双向断言：清单内路径消失要缩表、新出现的带版本路径立刻报错。接入 `AGENTS.md` 交付前检查与 `run_verification_suite.sh core` | 新增一件带版本资产即报错；欠账表清零后删除豁免机制 |
| **P5 台账回填（第一批）** | `3D-场景通用`（外科式 XML 补丁，备份 `*.xlsx.bak_deversioning`）：<br>① r86/r87（SAFE-ENTRY/EXIT）C 列现值 `.../runtime/entry_safe_room/v007/*/*_root_top3d_v007.tscn（17 包）；墙/地/门引用 .../runtime/common_components/*_root_top3d_v004.tscn`，D 列现值 `.../components/entry_safe_room/v007/*/*_visual_top3d_v007.glb（17 包）` → 去 `v007/` 目录与 `_v007`/`_v004` 后缀，括号与分号说明文字结构保留。<br>② r92–r96（5 个 `ENV-BATTLE-COMMON-*`）C/D 列现值含 `_v004` → 去版本。<br>③ O 列保留现有版本事实（r86/r87=v007，r92–r96=v004）不动 | `python3 scripts/check_asset_registry.py --scope structure` 相对基线（既有 37 项）**新增为 0**；AssetID、状态、尺寸列不变 |
| **P6 存量清理（全仓，最后）** | ① 先跑 `check_asset_runtime_naming.py` 出**全量清单**（818 个文件 + 9 个版本目录 + 207 处 tscn 引用），按套件拆分。② 顺序：空版本目录 → 同资产 `_v003`/`_v004` 冗余簇 → 孤儿 GLB（如 `components/entry_safe_room/v006` 24 件）→ 稳定命名重命名（GLB + tscn 一起去版本，脚本批量处理 `.import`/`.uid` 与全部引用）→ `.bak_*`。③ 每批 ≤10 项，每批单独提交、单独跑套件；每批同步缩 P4 欠账表并回填对应台账行 | 每批：引用扫描为 0、`run_verification_suite.sh core` 通过、`git status` 仅剩预期删除/重命名；全部完成后 `check_asset_runtime_naming.py` 判绿且欠账表为空 |

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



回滚：每阶段与 P6 每批次以独立提交交付；不使用工作区备份文件。

风险提示：P6 的「稳定命名重命名」是唯一会同时触及 818 个文件、207 处场景引用与 `.import`/`.uid` 的动作，必须脚本化 + 分批，禁止手工逐个改。

## 5. P6 存量清单（首轮，战局区块已实测）

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

基线备注：`check_asset_registry.py --scope structure` 在基线即有 37 项问题（424–428 行状态与总览公式），只判「是否新增」；`check_verification_log.py` 会把 `resources still in use at exit` 记为泄漏并返回 4，本仓库塔楼相关场景基线即有 2 处，退出码 4 不等于回归。

## 7. 不在本次范围

- `source/**` 的 Blender 版本历史策略（美术侧继续保留 v02/v03 后缀）。
- 资产内容本身的任何改动：本计划只改路径、命名、引用与登记。
- `assets/art/shared/`（色盘等非版本化资产）。
