# 独立关卡出生安全房「退出战局」门：离场契约修正

> <span style="color:#777777">**[名称已更新｜2026-09-19]** 本文的门禁场景 `verify_rogue_map_segment_flow` 已随「远征关卡01」替换被删除，其断言组并入 `verify_expedition_level01_flow` 的 `_verify_expedition_exit_contract`；运行时节点名改为 `ExpeditionExitWarning`，场景为 `ExpeditionLevel01_3D.tscn`。**契约内容本身仍然有效**（保持不变）。见[远征关卡01制作记录](2026-09-19_expedition_level01_buildout.md)。</span>

日期：2026-09-19；记录ID：WORLD-ENTRY-EXIT-2026-09-19；功能ID：WORLD-ENTRY；工程版本：0.1.0。
设计依据与修订：用户设计（2026-09-19 复现路径补充），主设计见[关卡生成与爬楼](../05_技术施工_关卡生成与爬楼.md) §3.0、[存档结算与复活](../09_技术施工_存档结算与复活.md) §5.1 离场语义表。
代码基线：提交 `90fc00e6`；本次修复已提交（见文末"提交"节）。

## 变更与原因

**问题（用户报告）**

独立关卡内**重新上线**后回到 98F 安全房，在安全房按那扇门「返回」，结果落进一间**白色房间**，不会回到基地。

**复现与结论（探针实测）**

`probe_rogue_resume_exit_flow` 按用户路径逐步复现（提交到 95F → 把玩家留在战斗房 → 取行动快照 → 用快照做运行时恢复 → 在 98F 安全房按门）：

| 步骤 | 实测结果 | 判定 |
|---|---|---|
| 重新上线 | 落点 `start`，98F 安全房 15×15，门向 `["east","south"]`，美术 `art=v007 墙10/门墙2/地砖9/包17`，世界 65 间房 | **正常**，重新上线没有白盒问题 |
| 在安全房按门 | 提示 `[E] 退出战局`，交互 mode `configured_standalone_retreat`，但弹出的是**塔楼撤退框**（`HUD/InitialLoopRetreatWarning`，按钮「确认撤退 · 全部丢失」） | 文案与语义错位 |
| 确认后 | 房间表 **65 → 1**，`start` 消失、出现塔楼 `floor_01_entry`、无 `facility`，无任何返回契约，状态栏却写「已撤退至99F基地」；玩家被留在那间**无美术白盒房**，随身物品被清空却没有结算 | **缺陷**（即用户看到的白色房间） |

**根因**

`TowerDescent3D.perform_interaction()` 把 `configured_standalone_retreat` 直接接到了塔楼 98F 首门反向撤退的 `_show_initial_loop_retreat_warning()` → `_confirm_initial_loop_retreat()`，而后者靠 `_reset_initial_loop_world_after_retreat()` 按**塔楼 98F** 重建世界。独立关卡不生成 99F 基地房，`_room_by_id.get("facility")` 为 `null`，玩家不被传送、也没有场景切换，于是整张地图被换成塔楼形态的单一白盒房。

**最终行为（本次确立的口径）**

独立关卡出生安全房那扇门是**主动弃局**入口，物品契约与塔楼 98F 首门反向撤退**完全一致**（背包、装备枪、装备背包全部丢失；保险格按契约保留），差异只在落点：独立关卡没有 99F 基地房，必须登记 99F 出生契约后 `change_scene_to_file(return_scene_path)` 回正式基地场景。

本门在**两条入口**下都必须成立：刚传送进图按门；关卡内重新上线回到安全房后按门。

反向约束同样成立且不得混淆：**撤离信号塔与死亡**继续保留全部物品，**不得**改用这套清空物品（见 09 文档 §5.1、05 文档 §3.0.1）。

## 代码变更

| 文件 | 改动 |
|---|---|
| `src/world3d/TowerDescent3D.gd` | `perform_interaction()` 的 `configured_standalone_retreat` 改接新分支 `_show_standalone_exit_warning()`；新增独立副本专用确认弹窗（节点 `HUD/StandaloneExitWarning`）、`_cancel_standalone_exit()`、`_confirm_standalone_exit()`；新增 `_discard_run_carry_for_retreat()` 并把塔楼 `_confirm_initial_loop_retreat()` 改为共用它（两条路径一份物品契约，避免漂移）；`_has_exclusive_modal()` 与 `try_close_modal_for_pause()` 纳入新弹窗 |
| `src/core/GameEntryFlow.gd` | 新增 `REASON_ABORT_RETURN_99F := "abort_return_99f"`，区分「主动退出战局回基地」与成功返航/死亡返航 |
| `tests/verification/verify_rogue_map_segment_flow.gd` | 第 4 组改为断言 `HUD/StandaloneExitWarning` 且不得出现塔楼弹窗；新增第 6 组「退出战局门离场契约」，对**首次进入**与**重新上线**两条入口各跑一遍 |
| `scripts/run_verification_suite.sh` | `verify_rogue_map_segment_flow` 注册进 `core` 集合（补上此前登记的门禁缺口） |
| `tests/verification/probe_rogue_resume_exit_flow.gd/.tscn` | 新增一次性探针：按用户路径复现「重新上线 → 安全房 → 按返回门」 |

`_confirm_standalone_exit()` 的关键顺序：`_completed = true` → 清空随身物品 → `unregister_runtime_checkpoint_provider(self, false)` → `clear_active_run_checkpoint("standalone_retreat")` → 登记 `REASON_ABORT_RETURN_99F` + `SPAWN_BASE_99F` → 0.8s 后切场景。先摘运行时提供者，避免场景卸载把已放弃的战局再写回检查点。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志 |
|---|---|---|---|
| `probe_rogue_resume_exit_flow`（修复前） | headless，`test_mode`，只读 | 重新上线正常落回 `start`+v007；按门弹塔楼撤退框；确认后 65 → 1 间白盒房，无返回契约 | `_scratch/probe_rogue_resume_exit_flow.log` |
| `probe_rogue_resume_exit_flow`（修复后） | 同上 | 按门弹 `StandaloneExitWarning`、塔楼框 `false`；确认后房间仍 65、含 `start`、无 `floor_01_entry`/`facility`；契约 `abort_return_99f/base_99f` | 同上 |
| `verify_rogue_map_segment_flow` | headless | `ROGUE_MAP_SEGMENT_FLOW_OK`（含两条入口的退出门契约断言） | `_scratch/v_rogue.log` |
| **反证**：分支临时改回 `_show_initial_loop_retreat_warning()` | 同上 | 失败 3 项，且**两条入口都失败**：`独立图出生门交互后缺少独立副本退出确认弹窗`、`退出契约检查(首次进入)未打开独立副本退出弹窗`、`退出契约检查(重新上线后)未打开独立副本退出弹窗` | 终端输出 |
| `verify_arrival_gate_floor_bundle_flow` / `verify_game_entry_flow` / `verify_tower_extraction_return_flow` / `verify_unified_player_interaction_flow` / `verify_tower_runtime_restart_restore` / `verify_pause_game_save_reset_flow` | headless | 六项全 `*_OK`（塔楼撤退与续局契约未受影响） | 终端输出 |
| `bash scripts/run_verification_suite.sh core`（带 `GODOT_BIN`） | headless，隔离工程目录 | **未能跑完**：收尾删除 Temp 隔离目录时被本机批量删除守卫拦下（`SAFE_DELETE_BULK_CONFIRM_REQUIRED`，97 文件）。本轮改用"逐场景直跑 + grep 结论"口径 | `_scratch/suite_core_rogue_exit_fix.log` |
| 行尾检查（`grep -c $'\r$'` 对比总行数） | 工作区，只读 | 本次改动的 `.gd/.tscn/.md/.sh` 全部 CRLF 纯 | 终端输出 |

## 遗留与状态更新

1. **待设计（本轮未动）**：独立关卡**单层化**与**撤离房间/撤离信号塔**仍为 2026-09-18 新设计、尚未施工。本次只修弃局出口。
2. **观察（本轮未动）**：`Dungeon3D._request_return_entry_context()` 会为返回 `BaseWorld3D.tscn` 的独立关卡离场登记 `GameEntryFlow` 入口契约，但**消费方只有 `TowerDescent3D`**，`BaseWorld3D` 不消费，因此该 pending 契约会滞留到本进程内下一次塔楼加载。死亡/成功返航路径本就如此，本次未引入新类别。
3. **本机验收口径**：套件无法在沙箱内跑到底（见上表），已把「逐场景直跑」记入项目长期约定。
4. **提交**：本次修复以独立提交落地，仅包含上述文件；提交前工作区曾发生一次并发提交导致的未提交改动丢失（见"风险"）。
5. **风险提示（本轮实际发生）**：上一版修复曾因另一会话提交 `90fc00e6 房间修改方案备份` 而整份丢失（未提交文件被清、`TowerDescent3D.gd` 回到 HEAD）。此类跨会话并发写同一工作区时，未提交改动不构成交付；本类修复必须尽早提交。
