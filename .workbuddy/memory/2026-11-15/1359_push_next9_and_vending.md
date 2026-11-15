# 1359 推送：九组件 v034 导入 + room_08 局内贩卖机

## 业主口述

> 「推送」

## 事实链（第四次「无待推送提交」）

接手时 `HEAD == origin/0.2 == ab4152d5`，**零待推送提交**：
`3e72dc27`（昨夜我提的记忆+九组件）被 `bf850456` 每日自动提交带走，
`ab4152d5`（十三组件导入）是另一会话提交后自己推的。

工作区压着 66 项 = 两条 2026-11-15 事务的成品，我提交成 `549940d4` 再推：
`ab4152d5..549940d4`，66 文件，LFS 上传 11 对象 5.6 MB。

## 「推送」在本仓库的实际含义

这个仓库有**每日自动提交**兜底，所以「推送」几乎总是遇到「没东西可推、但工作区有一堆成品」。
处理方式：**把工作区成品按事务提交，再推**。本次即如此，且提交信息里写明
「此前 ab4152d5 已推送第一步，本提交是随后完成、按推送指令补齐」——
因为 next9 记录自己写着「不追加第二次推送；未获另一次推送指令时不混入先前 checkpoint」，
这次的推送指令就是那个许可。

## 两条事务

① **九组件 v034**：door_wall / wall_t970_5m / wall_top_service / bridge_guardrail /
wall_t615_5m / equipment_rack / shelving / corner_guard / end_power
　合计 50148 → 6180 三角（−87.68%），预算 `T_after ≤ floor(T_before/5)`。
　OFFICE 的 shelving / corner_guard 源在工程内缺失，从
　`ShellStorm2-backup/2026-10-11_slimming` 归档 byte 复制回 art_source。

② **room_08 中庭贩卖机**：业主已自行重排 TSCN（阶梯/斜墙 + 9 块中庭地砖），
　本轮只加机器，复用远征03 链路。探针 23 条断言全过、`verify_run_merchant_integration` exit 0。

## 🔴 一个必须记住的教训：人工排除挡不住每日自动提交

昨夜我特意把 `work_cluster/export/v028~v031` 四个候选 blend **排除在提交外**
（理由：记录写明「候选、未导入、不回填 hash」，manifest 也没引用，会留下悬空状态）。

结果 `bf850456`（每日自动提交，32 项）**把它们全扫进去了** ——
`git ls-files 'art_source/**/work_cluster/export/*'` 现在能看到 4 个文件。

⇒ **只要工作区里留着不想要的文件，自动提交迟早会替你提交。** 「排除」不是持久状态，
真正的排除手段只有两种：删掉它，或写进 `.gitignore`。
这次同理，`_probe_loop.txt` / `override.cfg.disabled_20261109` /
`verify_main_story_boss_gate.report.json` 迟早会被扫进去。

## 并发

提交瞬间另一会话在写 `tools/_exp01_tri_scene_probe.{gd,tscn}`（13:58:27，我推送时冒出），
未纳入。这是第三次在同一仓库撞见并行会话，`git status` 前后 diff 是唯一可靠判据。

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=306** |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK** 289/13 未增 |
| `check_ledger_refs` | **OK** pending=0 allowed=2 dangling=0 |
| `sync_runtime_design_data --check` | 52 文件 **0 问题** |
| `check_documentation_contracts` | 11 条断链，全部既有 |
| `verify_ledger_split` | 红 **109**（未由本批账本改动新增） |

新增 .blend 全部走 LFS，已抽验 corner_guard v034 与回填原始源均为 lfs 指针。

## 遗留

- **room_08 足迹口径债**：`authored_layout_instances` 仍是 42 块，中庭 9 块只在 TSCN 里
  ⇒ 敌人不在中庭生成。修法两条都会动 13 房共用口径，**需业主裁定**。
- 三个产物文件仍在（外加新冒出的 tri_scene_probe）。
