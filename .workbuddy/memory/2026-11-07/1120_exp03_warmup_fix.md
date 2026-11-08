# 1120 远征03 预热闭环修复（await + 预算口径 + 怪种预置）

2026-11-07 11:20

## 结论

上一次审计的三处缺陷里，两处已修并真渲染验证通过；第三处（首波整批生成）**未动**，仍是最主要的剩余顿帧。

## 改了什么

### 1. `scenes/ExpeditionLoadingScreen.gd`

- `_drain_warmup()` 改为 **返回 Dictionary 报告**，调用处 `var warmup_report: Dictionary = await _drain_warmup(target)`。
  不 await 时预热协程在恢复操作后继续跑，读取页已 `queue_free()` —— 等于把冷启动挪到玩家眼前。
- 报告写入 target meta：`loading_warmup_report` / `loading_warmup_completed`；未完成时 `push_warning`。
- 预算口径修两处（同一现象的两个原因）：
  - ① 原 `_loading_started_msec + 2000 + 700` ⇒ 预热在「装配完成 + 全黑」之后才启动，实测加载 12.2 s / 24.8 s，期限早已过期。
  - ② **首帧必然贵**：`_restore_world_render()` 后是关卡画面第一次真实渲染，实测 **2.15~2.44 s**（SDFGI/管线初始化）。这笔钱原本也在收尾帧付，计入预算 ⇒ 预热永远超时。
  - 现口径：`deadline` 在**首帧结束后**才建立，`WARMUP_EXTRA_BUDGET_MS := 2500`（真实预热量 0.33~0.66 s，一倍余量）。

### 2. `src/vfx/VfxPool3D.gd`

新增 `pending_prewarm_count()`。只给完成度报告/断言用 —— 只有 bool 时「剩 0 件」和「剩 9 件」都是 `true`。

### 3. `src/world3d/Dungeon3D.gd`（`_spawn_enemy_batch`）

入树前把 `enemy_kind` 预置成 `enemy_type`。原来 `_ready()` 先按默认 `melee_chaser` 建一套表现层，`configure_from_enemy_data()` 再拆掉重建 —— 同一只非小僵尸的怪白读一次盘 + 白编一次变体。不改时序：只在 `add_child()` 前写一个属性。

### 4. `tests/verification/probe_expedition03_entry_chain.gd`

等 `loading_warmup_report` 出现后断言 `completed == true`。
⚠ **headless 下 `skipped=true`，这条无牙**（无渲染管线可预热）；必须真渲染跑才是门禁。

## 实测（RTX 3060 / Forward+ / `--disable-vsync`）

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 预热完成 | 1/3 基类，VFX 剩 9 件 | 3/3 基类，VFX 0 件 |
| 预热帧数 | 1 | 12 |
| 真实预热量 | — | 332~661 ms（首帧另计 2.15 s） |
| 交接后 2.5 s p95 | 50 ms | **30.8 ms** |
| 超 33 ms 帧 | 9 / 93 | **5 / 94** |
| 交接后 max | 77 ms | 99.9 ms（首帧，非预热） |

`max` 变大是因为采集从第 3 帧起算，抓到了 `release_loading_scene` + `open_after_scene` 那一帧；预热相关长帧已消失。

## 验收

- `probe_expedition03_entry_chain`：headless OK；**真渲染 OK**（`completed=true, vfx_pending=0, kinds_done=3/3`）。
- `verify_3d_enemy_behavior_flow` OK、`verify_3d_melee_feedback_flow` OK。
- `probe_expedition03_playable` 红：`28 扇 slide 门板厚 ≥ 墙厚`。**既有红项**，`git stash` 对照跑同样 28 扇，与本次改动无关。

## 还没做

1. **首波整批同步生成**（`_spawn_enemy_batch` 无分帧预算）：预热后单只仍 ~18 ms，一房 10 只 = 一帧 166 ms。改法是把超出预算的条目走既有 `_queue_delayed_spawn()`（注意它 `maxf(0.05, delay)` 最小 50 ms，且存活账已在预约时记好）。**这会改变「怪什么时候出现」，属手感决策，未擅自改。**
2. Boss / 收租人精英的正式表现不在 3 个普通基类覆盖内，第一次出场才加载。
3. 首次枪声/命中声/Boss 音乐仍同步 `load()`。
4. `EnemyAvatar3D.configure()` 对同 kind 无早退，`configure_from_enemy_data` 里那次 `apply_profile` 仍会重建一次（现在是同资产、缓存命中，成本已低）。

## 统一范围（11:20 追加）

- **预热集合与关卡无关**：`EnemyAvatar3D.FORMAL_NORMAL_SCENES` 只有 3 个基类（melee_chaser / ranged_caster / fat_zombie03）有正式 GLB，其余基类是程序化外壳；全部 `egt_*` 经 `PROXY_ASSET_KIND` 借用这 3 个。所以 `EnemyWarmup.BASE_KINDS` 是通用集合，不是远征03 专用。新增"有正式 GLB 的普通怪基类"必须同步加进来，否则该怪种首现卡 460ms 且不报错。
- 真渲染实测三关同形：expedition_03 12 帧 / 661ms、expedition_01 12 帧 / 720ms、99 12 帧 / 339ms，均 11/11 VFX + 3/3 基类。**读取页 + 预热链路对任意关卡一致**。
- **唯一未统一**：基地四个地牢传送门（`BaseWorld3D._on_dungeon_entrance_activated()` / `_load_scene()`）直接 `change_scene_to_file` 到 `IronFrontier3D` / `RustFoundry3D` / `SporeDepths3D` / `AbyssArchive3D`。这四张场景根是 `scenes/Dungeon3D.tscn`（未挂 `TowerDescent3D.gd`），没有加载契约（无 `loading_scene_ready` 上报、无 `prepare_loading_render`、无装配期可见性保护）。`Dungeon3D._ready` 已有 `_uses_loading_frame_budget()` 分支（依赖 `IrisTransition.is_loading_scene(self)`，按 `scene_file_path` 匹配任意场景），所以补契约主要缺"完成上报 + 可见性/输入保护"两块。改动面覆盖 8 个场景基类，需独立一轮。

## 文档（已落）

- 新设计：`docs/v0.1/design/关卡进入与冷启动预热设计.md`（WORLD-ENTRY r1，写唯一进入通道、预热覆盖、预算口径、交接顺序、完成判据、失败降级、未覆盖项）。
- 新记录：`docs/v0.1/development/2026-11-07_loading_warmup_gate.md`。
- 已同步：`MODULE_INDEX.md` WORLD-ENTRY 行、`design/README.md` 表格、`development/CHANGELOG.md` 顶部、`feature_registry.json`（design_docs + development_records，`updated_at` → 2026-11-07）。
- ⚠️ `check_feature_traceability.py` 的 `registered_scenes` 正则只认 `verify_*`，**不能把 `probe_*` 写进 registry 的 verification**（会报 `verification scene is not registered`），probe 只能写在 MODULE_INDEX 的文字列。
- 文档检查：44 条 Broken link 全是既有（指向 `ShellStorm2-backup/` 与已删文件），新增两篇 0 断链；`FEATURE_TRACEABILITY_FAILED` 已清零。
