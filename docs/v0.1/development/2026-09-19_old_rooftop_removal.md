# 旧聚落天台资产整体移除

日期：2026-09-19；工程版本：0.1.0；功能：`ASSET-ROOFTOP` / `WORLD-BLOCKS`；代码基线：`e1f6f3b` 及当前工作区。回滚锚点：`git tag pre-old-rooftop-removal`（HEAD `73e3fac6`，分支 `0.1.2`）。

来源：用户指令「先把旧的那套删除 然后看护栏和地砖 用的是否是prefab」。前序状态见 [天台运行设施清空](2026-09-17_rooftop_facilities_removed.md)——**那次只摘掉运行引用，资产本体还在仓库里**；本次把本体一并删除。

## 1. 删除范围

| 目录 | 文件 | 体积 | 性质 |
| --- | ---: | ---: | --- |
| `assets/art/environments/rooftop_shelter_3d/` | 329 | 609 MB | 旧聚落天台：Blender 源 v021 + 68 个 layout 组件 GLB + 包装场景 + 预览图 / 报告 / 对比参考 |
| `assets/art/environments/rooftop_shelter_diorama_3d/` | 45 | 83 MB | 微缩景观 v001–v003，**全项目零引用** |
| `source/art/blender/environments_v01/rooftop_shelter_50m/` | 15 | 57 MB | 最早 50m 制作源 + 空组件骨架（4 个分类目录下只有 README） |
| **合计** | **389** | **749 MB** | |

同时删除的专用件：

- `assets/art/environments/tower_zones/rooftop/runtime/zone_rooftop.tscn`（唯一的运行时 PackedScene 入口）
- `src/world3d/RooftopAmbience3D.gd`（唯一消费者是上面那个 tscn，删后成孤儿）
- `tests/verification/verify_rooftop_shelter_asset_contract.gd` / `.tscn`（专门验证这套资产）
- `tools/asset_pipeline/build_rooftop_shelter_diorama.py`、`build_rooftop_v021_wrapper.py`、`repair_rooftop_v017_coordinate_contract.py`

## 2. 连带引用清理

| 位置 | 处理 |
| --- | --- |
| `.gitignore` 第 7–9 行 | 删掉 3 条指向本资产的 `!*.glb.import` 例外 |
| `verify_tower_level_blocks.gd` | 摘掉 `zone_rooftop.tscn` 存在性断言，改为注释说明 Rooftop 无 PackedScene 入口 |
| `scripts/classify_asset_repository.py:107` | 删掉 `/rooftop_shelter_3d/ → ENV-ROOFTOP-SHELTER-50M-3D` 分支 |
| `tools/asset_pipeline/export_godot_rooftop_reference.gd` | **保留**（导出的是 Godot 原生 100F 对照，与旧资产无关）；输出路径改到新建的 `tower_zones/rooftop/references/` |
| `tools/asset_pipeline/build_rooftop_shelter.py` | **保留**并加头部说明：`build_british_corner_bookshop.py` 靠 `exec` 复用它的通用构建函数，删掉会连带弄坏英伦街角书店（该资产仍活跃，24 文件） |
| `tower_zones/rooftop/README.md` | 重写：说明当前无 PackedScene 入口、旧资产已移除、现行替代与回滚锚点 |
| `docs/v0.1/05.1_关卡区块设计.md` | 目录树加注（`runtime/` 为空、新增 `references/`）、区块表 Rooftop 行改为「无 PackedScene 入口」、正文两处「Rooftop 与 Base 的源保留」改为「Base」 |

**不改**（历史记录，改了就是篡改产出记录）：`docs/v0.1/development/` 下既有批次记录、`docs/v0.1/CHANGELOG` 旧条目、`docs/v0.1/audits/evidence/` 取证快照、`outputs/verification/` 日志，以及天台参考组件库 `reference_components/v00{1,2}/qa/` 里登记 v021 源 SHA-256 的验收证据（源移除后不再可复算，保留原样用于回溯）。

## 3. 台账

场景账本 `assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`：

- 《资产主表》整行删除 `ENV-ROOFTOP-SHELTER-50M-3D`（原 117 行）、`ENV-ROOFTOP-SHELTER-90X80`（原 118 行）
- 《3D-场景通用》整行删除 `ENV-ROOFTOP-SHELTER-90X80`（原 61 行）
- 解除 `ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY` 的「变体父ID」（原指向已删的 `ENV-ROOFTOP-SHELTER-90X80`），新参考组件库自此为独立顶层库

删行脚本 `_scratch/remove_old_rooftop_rows.py`；派生列公式 / DV / 条件格式 / autofilter / 总览跨度一律 `import split_asset_ledger`（项目约定的唯一公式定义处），**不另抄一份**。

**顺带修复**：原账本 236 行派生列公式是畸形写入（单元格存了 `==LOWER(...)`，多一个等号，Excel 里是 `#NAME?` 级错误），本次重建后转为 `=LOWER(...)` 正确形态。

## 4. 验收

| 检查 | 改动前 | 改动后 | 结论 |
| --- | ---: | ---: | --- |
| `check_asset_registry.py` issue 总数 | 539 | **65** | 无任何一类增加 |
| ├ `dedupe_key_formula_wrong` | 236 | **0** | 修好 |
| ├ `dedupe_result_formula_wrong` | 236 | **0** | 修好 |
| ├ `invalid_status` | 6 | 5 | −1 |
| ├ `path_not_found` | 26 | 25 | −1 |
| └ `sha_mismatch` | 35 | 35 | 持平 |
| 资产条目数 | 425 | **423** | 恰好 −2 |
| `verify_ledger_split.py` failure_count | 475 | **8** | 其中 4 项为本次主动删除的直接后果（2×`asset_lost` + `moved_sheet_mutated` 3D-场景通用 + `row_content_mutated` 参考组件库解除父ID），另 4 项既有（塔楼门墙/L 墙角内容变更、`ENV-TOWER-DOOR-LEAF-5M` 不在 2026-09-18 基线内） |

⚠️ `verify_ledger_split.py` 是**拆分无损回归守卫**（基线 `ledger_split_baseline.json` 抓于 2026-09-18），没有「已知移除」白名单——任何后续主动增删资产都会让它报警。本次 `missing = 2` 正是被删的这两个 AssetID，属如实反映而非回归。若要让该守卫重新全绿，需要给它加白名单机制（**本次未做**）。

细节见 `CHANGELOG.md` 当日条目。

## 5. 未执行项

- 未接入天台参考组件库（`reference_components/v002/`，44 包）到运行时；未导出 GLB、未生成 PackedScene、未做碰撞 / 通行 / 性能验收
- 未处理 `verify_ledger_split` 的白名单机制（见上）
- 未清理 `.godot/` 导入缓存里的历史条目（下次 `--import` 自愈）
- 未做全量验证套件（`run_verification_suite.sh`）回归
