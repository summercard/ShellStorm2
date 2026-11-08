# 10:55 远征03进入缓存/预热审计

- **结论：资源预读有效，战斗预热未闭环。** `ExpeditionLoadingScreen._finish_loaded_scene()` 第536行调用 `_drain_warmup(target)` 没有 `await`，随后只等两个基础帧就 `release_loading_scene()`；玩家操作恢复与 VFX 队列排空并行。
- **预算还会提前截断**：deadline = `_loading_started_msec + 2000 + 700`。实测正式路径加载 12.2 s（冷缓存首次 24.8 s），预热启动时预算早已过期，循环只做第一个怪基类就 `break`，3 个基类只暖 1 个。
- 真渲染实测（RTX 3060 / Forward+ / `--disable-vsync` / 1280×720）：交接瞬间 `vfx_pending=9`（11 件白名单只完成 2 件），`WarmupAvatar_*` 已空；交接后 93 帧 p50 25 ms、p95 50 ms、max 77 ms，>33 ms 9 帧、>50 ms 5 帧，首 5 帧 48/77/27/30/39 ms。
- 其余缺口：首波整批同步实例化（`Dungeon3D._spawn_enemy_batch` 单帧循环，历史预热后仍 166 ms/10只）；Boss/精英表现首次才 `_cached_scene()`；SFX 首次 `_play_sound_set()` 同步 `load()`；VFX 仅 11 件白名单。hit-flash 常驻自发光修复本身有效，不依赖预热。
- 现有 `probe_expedition03_entry_chain` 只验场景/房间/落地，不验预热完成；`probe_expedition_loading_runtime` 仍选远征01。仓库当前无“开圈前 `has_pending_prewarm()==false`”断言。
- 环境修复：拉取 51 提交后 `.godot/global_script_class_cache.cfg` 仍是 11-02 旧版，首次运行大量 `Could not resolve class`。已用 `--headless --import` 重建（6m21s，744 资源重导入）；随后 `ENTRY03_CHAIN_OK rooms=30`。
- 本次临时审计探针已删除，非 `.import` 文件无新增改动。
