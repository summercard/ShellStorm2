# Godot 侧资产替换去版本化 —— 执行计划

日期：2026-09-17；记录ID：待补；工程版本：0.1.0；状态：**计划，尚未执行**。
依据：`assets/art/3D模型资产目录与命名规范.md` §Blender 到 Godot 的更新流程（L126–133）。
基线：commit `b8af6fd`。
作用域：`assets/art/**` 的 Godot 运行资产（`components/` + `runtime/`）与 `src/**/*.gd` 的引用路径；`source/**` 的 Blender 历史版本保留策略**不变**。
索引动作（`development/README.md`、`CHANGELOG.md`）在交付步执行，本文件现已登记。

## 1. 问题

替换资产时 Godot 侧路径随版本漂移：源文件的 vNNN 被复制进运行资产的目录名与文件名，导致同一逻辑资产出现多份、台账与代码引用随之改动。四条根因：

| # | 层 | 根因 | 证据 |
|---|---|---|---|
| A | 规范 | 导入 skill 规定「替换=新建版本」，与命名规范「替换=覆盖既定路径」相反；执行导入时只加载 skill | `godot-model-asset-import-standard/SKILL.md` L32/L46/L63 vs 命名规范 L126–133 |
| B | 工具 | 版本号是脚本常量，直接拼进目录名与文件名；qa 脚本一版一份 | 全仓 18 个 `^VERSION = "v0NN"`；`source/entry_safe_room/v007/qa/export_packages_v007.py:47-48,144`、`build_package_prefabs_v007.py:43,156`；`tools/asset_pipeline/generate_runtime_scenes.py:43`；同目录另有平行的 `*_v006.py` |
| C | 运行时 | 版本号进 `preload` 常量与路径拼接 | `src/world3d/DungeonRoom3D.gd:75,97-109,1007-1013`；`TowerDescent3D.gd:7-34`；`TowerFloorStage3D.gd:31-46`；src 共 109 行 / 22 个 `.gd` |
| D | 台账 | O 列一格需同时表达源 / GLB / Prefab 三个版本 | 命名规范 L76；`assets/art/asset_import_manifest_v001.json` 顶层键即版本名（`*_v021_optimized_packages` / `*_v022_updates` / `*_v023_stair_bed`） |

已发生的代价（战局区块实测）：`runtime/entry_safe_room/` 存在 v003/v004/v005/v007 四个目录，前三个为空；`components/common_components/` 5 组 `_v003` 与 `_v004` 并存；`components/entry_safe_room/v006` 24 个 GLB 无任何 runtime；战局区块 `.bak_*` 18 个。

反例（证明不必如此）：`generate_runtime_scenes.py` 的包装场景名恒定、GLB 路径由 manifest 提供；塔楼 4 件替换时 prefab 保持 `_v001`、只换被引用的 GLB 版本。

## 2. 目标规则

- **N1 路径恒定**：Godot 运行资产路径不含版本号、不含版本目录。
  `components/<套件>/<slug>/<slug>_visual_top3d.glb`、`runtime/<套件>/<slug>/<slug>_root_top3d.tscn`。
- **N2 替换即覆盖**：替换 = 覆盖同路径同名文件；不新建目录、不新建文件；`.import` 与 `.uid` 原样保留。
- **N3 版本号落点**：仅允许出现在 `source/**` 的 Blender 文件名与目录、`asset_manifest.json`、台账 O 列、Prefab 根节点 `metadata/asset_version`。
- **N4 代码无版本**：`src/**/*.gd` 不得出现 `_v0NN` 形式的资产路径。
- **N5 回滚靠 git**：工作区不并存旧版；确需临存时用 `.bak_<用途>` 且当次清理。
- **N6 不变量**：原 `_v###` 名下的 AssetID、尺寸、原点契约、碰撞归属、资产元数据一律不变。

## 3. 待确认决策

| 编号 | 决策点 | 选项 | 建议 |
|---|---|---|---|
| D1 | GLB 是否一并去版本 | A：GLB 与 tscn 都去版本；B：GLB 留版本后缀、tscn 与代码恒定 | **A**。与「往 Godot 内替换资产不升版」一致；B 仍会留下双份 GLB。代价是旧版不再并存，回滚依赖 git |
| D2 | 存量清理范围 | A：先战局区块，base99/塔楼另立一轮；B：全仓一次性对齐 | **A**。base99/塔楼现有 `_v002/_v004/_v006` 是逐件独立版本号，需单独盘点，混在一轮会放大回归面 |

## 4. 执行阶段

| 阶段 | 改动点 | 完成判据 |
|---|---|---|
| **P1 规则层** | ① `godot-model-asset-import-standard` 的 L32/L46/L63、§版本与引用替换、目录模板改为「覆盖既定路径、路径不含版本」；用户级 `~/.workbuddy/skills/` 与工程 `skills_drafts/` 两份逐字节同步。② `assets/art/3D模型资产目录与命名规范.md` L10–11 目录模板去 `_v###`，§坐标与替换契约补「Godot 侧路径恒定」。③ `docs/v0.1/10_资产与内容规范.md:5` 删去「运行时可保留按批次递增的 v021–v024 组件版本」 | 两份 skill diff 为空；`python3 scripts/check_documentation_contracts.py` 通过 |
| **P2 工具层** | ① 战局区块 `source/**/qa/export_*.py`、`build_*_prefabs_*.py`：`VERSION` 只写 manifest 与节点 meta，不进路径；v006/v007 两份平行脚本合并为一份带版本参数的脚本。② `tools/asset_pipeline/generate_runtime_scenes.py:43`、`export_split_facilities_and_seating.py:107-129`、`update_character_registry.mjs` 同步 | 同一输入连跑两次，输出路径集合与 mtime 不变；`git status` 无新增带版本路径 |
| **P3 运行时层** | ① `DungeonRoom3D.gd`：`SAFE_ROOM_ART_VERSION` 退出路径拼接（L1007–1013 改为 `<slug>/<slug>_root_top3d.tscn`），5 条 L97–109 preload 去 `_v004`；版本降级为纯元数据。② `TowerDescent3D.gd:7-34`、`TowerFloorStage3D.gd:31-46` 及其余带版本引用的 `.gd`（共 22 个文件 / 109 行）改为去版本路径 | `bash scripts/run_verification_suite.sh core` 全绿；`probe_safe_room_v007_integration` → `SAFE_ROOM_V007_INTEGRATION_OK`；`probe_tower_palette_visible` → `TOWER_PALETTE_VISIBLE_OK` |
| **P4 存量清理** | 按 §5 清单分批删除；每批 ≤10 项，删前逐项确认引用数为 0（`src/**`+`*.tscn`+`*.json`） | 清单各项删除后 `git status` 仅剩预期删除；P3 验收复跑通过 |
| **P5 门禁** | ① 新增 `scripts/check_asset_runtime_naming.py`：扫描 `assets/art/**/{components,runtime}/**`，出现 `_v\d\d\d\.(glb\|tscn)` 文件名或 `runtime/**/v\d\d\d/` 目录即失败（`source/**` 豁免）；② 接入 `AGENTS.md` 交付前检查与 `run_verification_suite.sh core` | 门禁对当前工作区判失败（存量未清前），清理后转绿；对 `source/**` 不误报 |
| **P6 台账回填** | `3D-场景通用`（就地板本，外科式 XML 补丁，备份 `*.xlsx.bak_deversioning`）：<br>① r86/r87（SAFE-ENTRY/EXIT）C 列现值 `.../runtime/entry_safe_room/v007/*/*_root_top3d_v007.tscn（17 包）；墙/地/门引用 .../runtime/common_components/*_root_top3d_v004.tscn`，D 列现值 `.../components/entry_safe_room/v007/*/*_visual_top3d_v007.glb（17 包）` → 去掉 `v007/` 目录与 `_v007`/`_v004` 后缀，括号与分号说明文字结构保留。<br>② r92–r96（5 个 `ENV-BATTLE-COMMON-*`）C/D 列现值含 `_v004` → 去版本。③ O 列保留现有版本事实（r86/r87=v007，r92–r96=v004）不动 | `python3 scripts/check_asset_registry.py --scope structure` 相对基线（既有 37 项）**新增为 0**；回填后 AssetID、状态、尺寸列不变 |

回滚：每阶段以独立提交交付；P4 删除前先落到 git 提交，回滚用 `git revert` / `git checkout`，不使用工作区备份文件。

## 5. 存量清理清单（战局区块，实测 2026-09-17）

| 位置 | 内容 | 引用状态 |
|---|---|---|
| `runtime/entry_safe_room/v003`、`v004`、`v005` | 空目录（0 个 `.tscn`） | 无 |
| `components/entry_safe_room/v003`、`v004`、`v005` | 空目录（0 个 `.glb`） | 无 |
| `components/entry_safe_room/v006` | 24 个 GLB | 无 runtime、无代码/场景引用；仅 v004 组件元数据 `carries_room_art_from` 提及 `source/entry_safe_room/v006`（源侧，保留） |
| `components|runtime/common_components/` 的 5 组 `_v003` | wall_standard_5m、wall_door_5m、door_5m、floor_tile_r01_c01、floor_tile_r01_c02 的 GLB/tscn | src 只 preload `_v004`；`_v003` 仅被自身 tscn 的 `ext_resource` 与 `source/common_components/v003/` 的 manifest/catalog 引用 |
| 战局区块 `.bak_*` 18 个 | `*.glb.import.bak_pre_palette` 8、`*.tscn.bak_pre_generate` 5、源侧备份 5 | 备份，非运行资产 |

清理顺序：先删空目录 → 再删 `_v003` 冗余簇 → 再删 v006 孤儿 GLB → 最后删 `.bak_*`。删除一律走 git 提交留痕，不使用系统回收站。

## 6. 验收命令

```bash
export GODOT_BIN="I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
bash scripts/run_verification_suite.sh core
bash scripts/run_verification_suite.sh scene probe_safe_room_v007_integration
bash scripts/run_verification_suite.sh scene verify_tower_grid_component_alignment
python3 scripts/check_documentation_contracts.py
python3 scripts/check_asset_registry.py --scope structure
```

基线备注：`check_asset_registry.py --scope structure` 在基线即有 37 项问题（424–428 行状态与总览公式），只判「是否新增」；`check_verification_log.py` 会把 `resources still in use at exit` 记为泄漏并返回 4，本仓库塔楼相关场景基线即有 2 处，退出码 4 不等于回归。

## 7. 不在本次范围

- `source/**` 的 Blender 版本历史策略（美术侧继续保留 v02/v03 后缀）。
- base99 与塔楼资产（`env_base99_*`、`prp_tower_*`）的去版本化与存量清理。
- 厂房/室内装饰类资产、武器、道具、角色、敌人、特效整链。
- 资产内容本身的任何改动：本计划只改路径、命名、引用与登记。
