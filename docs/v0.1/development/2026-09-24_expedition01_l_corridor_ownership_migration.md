# 远征01 L 型走廊归属迁移（battle → expedition）

- 功能定位：`ASSET-PIPELINE`。业主 2026-09-24 裁决：L 型走廊归属远征关卡01。本次只改归属、命名、目录结构与账本登记，不修改走廊几何、材质、门状态机、关卡生成或任何玩法代码。
- 动机（业主）：「L 型走廊要归属到远征01地图，修改文件夹和账本还有命名。」
- 裁决依据：`01-battle-room-type-art-authoring` 明确「远征白盒必须为 `expedition`」（局内战局通常为 `battle`）。该 Skill 的房间种类清单（SAFE / COMMON / BOSS / EXTRACTION）不含 `L_CORRIDOR`，属 Skill 未覆盖的新房间种类，因此按「源文件实际服务区块」判定归属；`blender-game-prop-standard` 只约束 Blender 集合命名，不约束文件名，命名沿用远征同区块既有的「房型_主题_尺寸_版本」范式。

## 归属变更

| 项 | 迁移前 | 迁移后 |
|---|---|---|
| 目录 | `assets/art/environments/tower_zones/battle/source/room_types/l_corridor/` | `assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/` |
| `block_id` | `battle` | `expedition` |
| 资产 ID | `ENV-BATTLE-L-CORRIDOR-TYPE` | `ENV-EXPEDITION-L01-L-CORRIDOR` |
| `floor_range` | `battle level 01 / unassigned instance` | `expedition 01 / unassigned instance` |
| 组件包 ID 前缀 | `ENV-BATTLE-LCORRIDOR-*` | `ENV-EXPEDITION-L-CORRIDOR-*` |

battle 侧不留副本，`tower_zones/battle/source/room_types/` 随迁后为空。

## 命名与内部结构统一（对齐远征 Boss 房范式）

| 项 | 迁移前 | 迁移后 |
|---|---|---|
| 源文件 | `l_corridor_room_type_v001/v002/v003.blend` | `L型走廊种类_数据连廊_45x35m_v001/v002.blend`、`L型走廊种类_数据连廊_45x40m_v003.blend` |
| 组件包目录 | `component_packages_v001/v002/v003/` | `component_packages/`（去版本后缀） |
| 分类目录 | `facility/` | `facilities/`（对齐 Boss 房复数口径） |
| 渲染图 | 散放在版本目录根（v001 4 张、v002/v003 各 7 张，共 18 张） | 收进 `renders/` |
| 共享件引用 | `ENV-BATTLE-COMMON-WALL-STANDARD-5M` 等 5 个旧 ID | `ENV-SHARED-GENERIC-*`（shared 库现有正本 ID） |

尺寸进文件名是按各版本实际值取的：v001/v002 为 10m 宽走廊、外包络 45×35m；v003 拓宽为 15m、外包络 45×40m。同区块 `Boss房种类_故障数据库_50x40m_v002.blend` 因两版尺寸相同才没有这个差异。

共享件 ID 的更正依据是 `tower_zones/shared/source/common_components/v001/component_catalog.json`：该库已把 `ENV-BATTLE-COMMON-*` 抽出并改号为 `ENV-SHARED-GENERIC-*`，旧的 battle ID 只保留为 `source_package_id` 历史来源。走廊 manifest 原引用的是过期 ID，属本次一并修正。

## 仍存在的跨区块引用（有意保留）

`v003/widen_l_corridor_v003.py` 的 `COMMON` 常量仍指向 `tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend`。该文件真实存在，是走廊共用件的**造型来源**；改路径会让重建脚本指向不存在的文件。脚本内已加注释说明「造型取自 battle 库、运行时引用统一走 shared 库的 `ENV-SHARED-GENERIC-*`」。

## 账本登记

- 《资产主表》第 242 行 `ENV-EXPEDITION-L01-L-CORRIDOR`；《3D-场景通用》第 148 行对齐行；《总览》A6/C6/E6/G6 与 B10..C13 区间由 `$241` 扩到 `$242`；《域变更日志》第 19 行 `v0.1.13`。
- 派生列 R/S 由 `split_asset_ledger` 的唯一真源公式重算，236 行 S 列区间同步到新末行，未写字面量。
- 顺带修正上一行的遗留：《资产主表》DV 此前只到 `C6:C240`，未覆盖第 241 行，本次扩到 `C6:C242`（K/L 两列同样处理）。
- 无损基线 `assets/registry/ledger_split_baseline.json` 同步：新增该 AssetID 的行指纹，`asset_count` 410→411，重算 9 域并集的列摘要与 `3D-场景通用` 专表摘要。备份 `.bak_before_l_corridor_expedition`。

## 验证

- `godot --headless --path . --import` 退出 0；21 个 `.import` 全部按新路径重新生成，旧路径 `.import` 已清除。
- 三个源全部可加载：`LOAD_OK`，节点数 1105 / 1399 / 1660，根节点名与文件名一致；旧 `res://…/battle/…/l_corridor_room_type_v003.blend` 路径 `ResourceLoader.exists()` 为 false。
- `tools/asset_pipeline/verify_ledger_split.py` → `LEDGER_SPLIT_VERIFY_OK assets=411 ledgers=9`，`failure_count=0`、`column_digest_drift=[]`。
- `scripts/check_asset_registry.py --scope structure` → `ASSET_REGISTRY_CHECK_OK scope=structure assets=411 ledgers=9`，`issue_counts={}`。
- `scripts/check_asset_registry.py --scope full` 报 204 项 `sha_mismatch`，**不含本次任何路径**（既有 CRLF 行尾导致的 SHA 漂移，属已登记的历史债务）。
- 全仓库检索确认：`src/`、`scenes/`、`tests/`、`data/` 对 l_corridor 资产**零引用**，迁移无运行时风险；仅 `docs/` 有三份 2026-09-23 的历史产出记录，按历史事实保留不改。

## 未执行

- 未修改走廊几何、材质、PaletteUV、门位与设施布置；未导出 GLB、未生成碰撞或 PackedScene、未接入 Godot 运行场景。
- 远征01 版图（`source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json`）与白盒目录**仍无走廊席位与走廊白模**，尺寸和门位沿用参考图推定值。接入前需远征白盒补走廊白模，届时需重新核对门连接。
- 未改 Skill 内的房间种类清单；`L_CORRIDOR` 是否登记为正式房间种类由业主决定。
- 未动 `_scratch/entry_cinematic_project/` 下的整份镜像副本（非仓库正本）。
