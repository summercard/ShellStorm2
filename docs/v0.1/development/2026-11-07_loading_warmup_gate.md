# 进入期冷启动预热闭环（读取页等待 + 预算口径）

日期：2026-11-07
功能ID：**WORLD-ENTRY**（子契约见[关卡进入与冷启动预热设计](../design/关卡进入与冷启动预热设计.md) r1）
代码基线：`2a1a1aa66`（origin/0.1.2）

## 1. 问题

读取页的 `_drain_warmup()` 没有闭环，两处口径错误叠在一起：

1. **调用不等**：`_finish_loaded_scene()` 调 `_drain_warmup(target)` 不加 `await`，紧接着只等 2 个基础帧就 `release_loading_scene()` 恢复操作、`open_after_scene()` 开圈。预热协程在玩家已能动、读取页已 `queue_free()` 之后继续跑。
2. **预算恒过期**：期限写成 `_loading_started_msec + MIN_LOADING_SCREEN_SECONDS + 700 ms`。而预热是在「装配完成 → 全黑覆盖」之后才启动，实测两局加载 12.2 s / 24.8 s，期限早已过去。
3. **首帧记账错误**：`_restore_world_render()` 之后是关卡画面第一次真实渲染（SDFGI/管线初始化），实测 2.15~2.70 s。这笔代价由 `_wait_for_basic_scene_ready()` 的收尾帧承担，与预热量无关，但被算进了预热预算。

三者共同的结果：预热循环只做完第一个怪基类就 `break`，11 件战斗特效剩 9 件漏进开圈后的战斗里逐帧编译。

## 2. 改动

| 文件 | 改动 |
|---|---|
| `scenes/ExpeditionLoadingScreen.gd` | `_drain_warmup()` 返回完成度报告，调用处 `await`；预算改为「首帧结束后起算 2500 ms」；报告写入目标场景 meta |
| `src/vfx/VfxPool3D.gd` | 新增 `pending_prewarm_count()`，供完成度报告与断言使用 |
| `src/world3d/Dungeon3D.gd` | `_spawn_enemy_batch()` 在 `add_child()` 前把 `enemy_kind` 预置为 `enemy_type`，去掉「先按默认 `melee_chaser` 建一套表现层再拆掉重建」的重复 |
| `tests/verification/probe_expedition03_entry_chain.gd` | 等 `loading_warmup_report` 出现后断言 `completed == true` |

`_drain_warmup()` 报告字段：`completed` / `skipped` / `vfx_total` / `vfx_pending` / `kinds_done` / `kinds_total` / `frames` / `first_frame_ms` / `elapsed_ms` / `warmup_ms` / `truncated`。

## 3. 验证

真渲染（RTX 3060 / Forward+ / `--disable-vsync` / 1280×720）：

| 关卡 | 预热帧数 | VFX | 怪基类 | 首帧 | 预热量 | 结论 |
|---|---:|---|---|---:|---:|---|
| expedition_03 | 12 | 11/11 排空 | 3/3 | 2151 ms | 661 ms | completed |
| expedition_01 | 12 | 11/11 排空 | 3/3 | 2697 ms | 720 ms | completed |
| 99 | 12 | 11/11 排空 | 3/3 | 2272 ms | 339 ms | completed |

三张关卡走同一个读取页、同一套预热集合与判据，读数同形 ⇒ 该机制与关卡无关。

修复前后 2.5 秒窗口帧时间（expedition_03，真渲染）：

| 指标 | 修复前 | 修复后 |
|---|---:|---:|
| 帧数 | 93 | 94 |
| p50 | 25 ms | 24.5 ms |
| p95 | 50 ms | 30.8 ms |
| 超 33 ms 帧 | 9 | 5 |
| 最大 | 77 ms | 99.9 ms（`release_loading_scene` + 开圈那一帧，非预热） |

门禁结果：

- `probe_expedition03_entry_chain`：headless 通过（预热 `skipped`，30 房、玩家落地）；真渲染通过（`completed=true`）。
- `verify_3d_enemy_behavior_flow`：通过。
- `verify_3d_melee_feedback_flow`：通过。
- `probe_expedition03_playable`：红 —— `28 扇 slide 门板厚 ≥ 墙厚 0.28m`。**既有红项**：`git stash` 掉本轮源码改动后原样复现 28 扇，与本轮无关。

## 4. 遗留

1. **基地四个地牢传送门未走读取页**：`BaseWorld3D._on_dungeon_entrance_activated()` / `_load_scene()` 直接 `change_scene_to_file`，目标是 `IronFrontier3D` / `RustFoundry3D` / `SporeDepths3D` / `AbyssArchive3D`。这四张场景根为 `scenes/Dungeon3D.tscn`，没有加载契约（无 `loading_scene_ready` 上报、无 `prepare_loading_render`、无装配期可见性保护）。要统一必须先给 `Dungeon3D` 补契约；它是八个关卡场景的基类，需独立一轮施工与回归。
2. **首波整批同帧生成**：`_spawn_enemy_batch()` 无分帧预算，预热后单只约 18 ms，一房 10 只 ≈ 166 ms。可行改法是复用既有 `_queue_delayed_spawn()`，但其最小延迟为 50 ms（`maxf(0.05, delay_sec)`），会改变「怪什么时候出现」，属手感决策。
3. **Boss / 收租人精英正式表现未预热**：`BossContentCatalog.presentation_scene` 首次出场才读盘。expedition_01 与 99 均配置了 `boss_content_id = boss_monitor002`。
4. **首次枪声 / 命中声 / Boss 音乐**仍同步 `load()`。
5. `EnemyAvatar3D.configure()` 对同 kind 无早退，`configure_from_enemy_data()` 里那次 `apply_profile()` 仍会重建一次；预置怪种后已是同资产、缓存命中，成本低，未再优化。
