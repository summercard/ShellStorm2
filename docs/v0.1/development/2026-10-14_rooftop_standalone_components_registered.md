# 场景账本登记 9 件天台独立组件（design_only，未制作）

日期：2026-10-14；记录ID：2026-10-14_rooftop_standalone_components_registered；功能ID：`ASSET-PIPELINE`（owner `LedgerIndex`，本记录同时挂在 `ASSET-ROOFTOP`）；工程版本：`0.1.0`（`project.godot` 未改）。

设计依据与修订：[天台参考组件库（新增「天台破损与废墟类独立组件」小节）](../design/rooftop_component_library.md)、[资产与内容规范](../10_资产与内容规范.md)（场景域 AssetID 前缀与运行文件名去版本化）。主人原话：「检查一下场景资产账单 帮我增加几个天台用的组件，作为场景单独的组件，先增加账单内容，标注为设计制作，我需要破掉的花圃 大约长6米 宽1.5米的，防御沙包 长7米宽2米，石块堆 3个变种 高度大概都是1-1.3米上下，大型的杂物堆 大概12米x10米的范围，破败的木箱 3套变种。」口径在动手前确认：**先入账、不制作**，制作状态记 `design_only`。

## 变更与原因

**`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`（9 条新行 + 聚合面）**

- 《资产主表》追加 9 行（行 929–937，末数据行 `928 → 937`）。共同字段：大类 `场景`、子类 `environment_module_3d`、逻辑ID源键 `rooftop_decor`、视角 `Blender Z-up / -Y`、**制作状态 `design_only`**、优先级 `P1`、版本 `v001`、来源 `用户设计`、负责人 `Codex`、更新时间序列号 `46309`（2026-10-14）；`源码/策划依据` 指向 `docs/v0.1/design/rooftop_component_library.md`。

| 行 | AssetID | 中文名 | 组件槽 | 规格 |
|---|---|---|---|---|
| 929 | `ENV-ROOFTOP-FLOWERBED-BROKEN` | 天台破损花圃 | `broken_flowerbed` | 约 6.0×1.5 m；残破花池+塌落土石 |
| 930 | `ENV-ROOFTOP-SANDBAG-BARRIER` | 天台防御沙包墙 | `sandbag_barrier` | 约 7.0×2.0 m；堆叠沙包掩体 |
| 931 | `ENV-ROOFTOP-RUBBLE-PILE-A` | 天台石块堆 A | `rubble_pile_a` | 高约 1.0~1.3 m |
| 932 | `ENV-ROOFTOP-RUBBLE-PILE-B` | 天台石块堆 B | `rubble_pile_b` | 高约 1.0~1.3 m |
| 933 | `ENV-ROOFTOP-RUBBLE-PILE-C` | 天台石块堆 C | `rubble_pile_c` | 高约 1.0~1.3 m |
| 934 | `ENV-ROOFTOP-DEBRIS-PILE-LARGE` | 天台大型杂物堆 | `debris_pile_large` | 约 12.0×10.0 m |
| 935 | `ENV-ROOFTOP-BROKEN-CRATE-A` | 天台破败木箱 A | `broken_crate_a` | 木箱 3 套变种之 A |
| 936 | `ENV-ROOFTOP-BROKEN-CRATE-B` | 天台破败木箱 B | `broken_crate_b` | 木箱 3 套变种之 B |
| 937 | `ENV-ROOFTOP-BROKEN-CRATE-C` | 天台破败木箱 C | `broken_crate_c` | 木箱 3 套变种之 C |

- 同步的写死区间（不改则总览公式/下拉失真）：`R`/`S` 派生列按权威函数逐行重算；《总览》12 格 `$928 → $937`；三张下拉 `C6:C872 / K6:K872 / L6:L872 → C6:C937 / K6:K937 / L6:L937`；`auto_filter` `A5:Y928 → A5:Y937`；《域变更日志》追加 `v0.1.36`。
- **三张 Prefab 分页（`3D-场景通用` / `3D-设施` / `3D-其他`）刻意不动**：铁律「一行 ＝ 一个实际存在的 `PackedScene`」，9 条尚无 Prefab；且它们属摘要锁死表，改动会被 `verify_ledger_split.py` 以 `moved_sheet_mutated` 拒绝。
- `ledger_index.json` **未改**：`scenes` 域的类别/前缀/分页结构未变。

**`assets/registry/ledger_split_baseline.json`（无损基线）**

- 按「基线＝当前真相」口径为 9 个新 ID 补录 `{v: _row_digest, c: 场景, d: scenes}`；`asset_count 1232 → 1241`、`category_counts.场景 760 → 769`；23 个内容列并集指纹刷新；`sheet_digests` 逐项不变。⛔ 未跑 `split_asset_ledger.py --baseline-only`（该开关会清空基线）。

**文档面**

- `docs/v0.1/design/rooftop_component_library.md` 新增「天台破损与废墟类独立组件（2026-10-14 登记，仅账单）」小节（ID/规格/变体/边界），使账本 `源码/策划依据` 列的引用成立。
- `docs/v0.1/MODULE_INDEX.md` 的 `ASSET-ROOFTOP` 行状态栏追加本次登记的日期说明。
- `docs/v0.1/feature_registry.json`：本记录挂入 `ASSET-PIPELINE` 与 `ASSET-ROOFTOP` 的 `development_records`；`updated_at → 2026-10-14`。

### 兼容性影响

- 既有 923 行（行 6–928）除 `S` 列区间随末行扩到 `$R$6:$R$937` 外**逐格不变**；未新增任何 `assets/art` 运行文件，运行时不改一行代码。
- 9 条为排产入口，`design_only` 不进运行池（`DOCUMENTATION_STANDARD` §4；道具账本 `ITM-EQUIPMENT-BACKPACK-3D` 为先例）。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志证据 |
|---|---|---|---|
| `check_asset_registry.py --scope structure` | venv python + openpyxl，无运行时 | **0** | `ASSET_REGISTRY_CHECK_OK scope=structure assets=1241 ledgers=9`，`issue_counts {}` |
| `verify_ledger_split.py` | 同上 | **0** | `LEDGER_SPLIT_VERIFY_OK assets=1241 ledgers=9 baseline=2026-10-14`，`column_digest_drift []` |
| `check_asset_registry.py --scope full --ledger scenes` | 同上 | **1** | 755 条红项**全部**落在既有行 50–278，**无一命中 929–937** |
| 新行实读（`scripts/blender/xlsx_read.py`） | 零依赖读取器 | 通过 | 929–937 的 AssetID/中文名/制作状态 `design_only`/规格逐条回读一致 |
| 改前副本逐格反向对照 | 备份 `before_edits/` | 通过 | 差异面＝总览 12 格 + 资产主表（S 列区间 + 9 新行）+ 变更日志 1 行；其余 sheet 0 差异 |

- 未跑 `check_asset_runtime_naming.py` 之外的引擎内验收（本次无可运行表现）；未跑真实渲染；未跑全量 `smoke/core/full`。

### 预期故障与未执行

- **预期故障（既有，非本次引入）**：`--scope full --ledger scenes` 的 755 条红项属既有场景行债务；运行时命名门禁报 `bunny01 v022/v023/v024` 等带版本（既有）；账本引用 `pending=1`（`restore_openworld_tower_ledger.py`，既有）；文档契约的断链与「UI 期望16实际18」属既有项——本次未新增任何 `assets/art` 文件，与这些红项无因果关系。
- **未执行**：未建 Blender 源 / GLB / Prefab / `catalog` 条目；未渲染；未接入装饰布局；未提交（改动留在工作区）。

## 遗留与状态更新

- **状态更新**：场景账本资产条数 `923 → 932`（含既有插入行，末行为 937）；基线资产总数 `1232 → 1241`；`category_counts.场景 760 → 769`。`ASSET-ROOFTOP` 状态保持 `source_only`（本次只登记设计件、未产源）；`ASSET-PIPELINE` 保持 `partial`（持续维护，非完成度提升）。
- **9 条仍为 `design_only`**：制成动作需先落地 Blender 源与 `catalog` 条目 → 导出 GLB → 固定镜头渲染验收 → 登记 Prefab（`3D-场景通用` 分页）→ 回填 `O` 列路径与 `T` 列 SHA-256 → 推进 `K` 列到「已完成」。本次**不**把「已登记排产入口」等同于「组件已完成」。
- **回滚路径**：`.xlsx` / `ledger_split_baseline.json` 的改动前副本存于 `.workbuddy/backup/20261014_rooftop_components/before_edits/`，重放脚本为同目录 `apply_rooftop_components.py` 与 `apply_rooftop_baseline.py`。
