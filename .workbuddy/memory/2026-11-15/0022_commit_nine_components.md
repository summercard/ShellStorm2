# 0022 提交：远征01 九组件 v029 导入 + 房05后战斗压力

## 业主口述

> 「提交一下」（只提交，不推送）

## 提交

`3e72dc27` — **60 文件 / +669 −133**，`origin/0.2` 仍是 `172d32de`（本地 ahead 1）。

两条 2026-11-14 事务，都不是本会话写的：

| # | 事务 | 落点 |
|---|---|---|
| ① | 九组件 v029 优化导入 | 9 件 GLB + Prefab 同路径替换、场景账本四独立行 M/T/V/Y + 四条 3D 分页 O/P、baseline 七条资产、floor_detail_b 补 asset_manifest |
| ② | 房05后战斗压力 | room_05 保留 31 只转折房不堆量；小僵尸移速 −30%、后期数量 +30% |

## 一个关键核验（值得复用）

**LFS 指针里的 oid 可以直接和 asset_manifest 的 optimized_sha256 对账。**
抽了 filing_run v029：

```
git cat-file -p HEAD:...export/v029/filing_run_optimized_v029.blend | head -2
→ oid sha256:46bf676adc1eed1116b160a2330394903c0f7fa0bf602bb5560f4076101fe13a
```

manifest 里 `optimized_sha256` 正是 `46bf…fe13a` ⇒ 落盘的确实是清单登记的那份优化母版，
不是随手存的另一个版本。以后核资产导入，这条比看文件大小靠谱。

## 我做的排除（有意，非遗漏）

`work_cluster/export/v028~v031` 四个 blend **没提交**。理由：

1. 开发记录明写 v031 是「8162 三角、减面 50.012% 的**候选**，未导入、不升版、
   不回填其正式资产 hash」；
2. 它的 `asset_manifest.json` 本轮未改 ⇒ 提交会留下「有优化母版、无清单引用」的悬空状态；
3. AGENTS.md：临时导出与 QA 走工程外目录。

需要入库时单独授权、单独一条提交。

九件的 **v028 与 v029 都提交了** —— export 目录历来保留多版本
（`git ls-files` 里 base_facility_layout 就有 v017/v021/v022 并存），不是只留最新。

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=306** |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK** 289/13 未增 |
| `sync_runtime_design_data --check` | 52 文件 **0 问题** |
| `check_documentation_contracts` | 11 条断链，全部既有 |
| `verify_ledger_split` | 红 **109**（本批动了账本，但未新增失败） |

## 遗留

三个产物文件第七轮仍未处理：`_probe_loop.txt`、`override.cfg.disabled_20261109`、
`verify_main_story_boss_gate.report.json`。
