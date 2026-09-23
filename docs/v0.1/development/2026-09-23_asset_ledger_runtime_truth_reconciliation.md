# 资产账本运行时真源对账（2026-09-23）

## 裁决原则

1. 当前游戏实际接入并运行的正式资产优先于旧账本路径、版本与哈希。
2. 同一物理资产被多个功能复用时，只保留一个主登记；节点槽位、配置能力与功能用途写入契约或备注，不再伪装成多份资产。
3. 自动贩卖机统一使用 `assets/art/props/base_world_3d/runtime/vending_machine/prp_base_vending_machine_root_top3d.tscn`；旧程序网格 prefab 删除。

## 本轮处理

- 24 条旧版本运行时路径按现有稳定去版本路径完成迁移；同类存量旧路径一并按同一规则校正。
- 199 条 SHA 漂移按当前工程正式文件重新登记；没有用当前文件覆盖来源不明的外部资产。
- 连续爬塔 5 个白盒组件改为 `程序占位 / P2`，保留设计源，待玩法重新开放时恢复专项验收。
- 角色节点槽位、DIY 配置槽、VFX/UI 共用场景与旧 UI 身份等 17 条重复物理登记合并，资产主登记总数从 426 降为 409。
- 天台 v002 Blender 主库因被 47 个组件包、运行时元数据和制作脚本共同追溯，保留历史中文源文件名例外；下次主库升版时再迁移英文规范名。
- 分账基线改为 2026-09-23 当前运行时真源快照；媒体域门禁同步为 UI 16、音效 48、音乐 9。

## 自动贩卖机

- `scenes/BaseWorld3D.tscn` 已切换为正式 runtime prefab。
- `verify_base_shop_save_flow` 改为验证 `Visual/ImportedModel`、`base_vending` 功能身份及 v003 Blender 来源。
- 已删除 `assets/art/props/base_world_3d/prp_base_vending_machine_root_top3d.tscn` 旧程序网格场景。

## 验收

| 验收项 | 结果 |
|---|---|
| `python3 scripts/check_asset_registry.py --scope structure` | PASS，409 条，0 issue |
| `python3 scripts/check_asset_registry.py --scope full` | PASS，409 条，0 issue |
| `python3 tools/asset_pipeline/verify_ledger_split.py` | PASS，missing/extra/drift 均为 0 |
| `python3 scripts/check_media_asset_domains.py` | PASS，73 条媒体资产 |
| `python3 scripts/check_documentation_contracts.py` | PASS，0 issue |
| `python3 scripts/check_asset_runtime_naming.py` | PASS（存量欠账快照仍在，但无新增） |
| `run_verification_suite.sh batch verify_base_vending_visual verify_base_shop_save_flow` | PASS，2/2；存档损坏与 stale writer 为用例预期故障 |

## 可重复执行入口

`python3 tools/asset_pipeline/reconcile_runtime_truth_ledger.py`

该脚本负责稳定路径迁移、共享登记合并、SHA 刷新、分账总览公式重算、总目录数量同步和当前基线重建。
