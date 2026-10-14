# 天台（100F）BGM 关闭：用开关停播，不删曲目与资产

日期：2026-10-14；记录ID：2026-10-14_rooftop_bgm_disabled；功能ID：`AUDIO-MUSIC`（owner `AudioManager / MusicManager`）；工程版本：`0.1.0`（`project.godot` 未改）。

设计依据：[音乐播放清单](../design/音乐播放清单.md) §1/§2、[音乐系统与配乐资产](../14.8_音乐系统与配乐资产.md)。主人原话：「天台的bgm去掉 不要播放，先使用给关闭的功能 不要删除代码和资产」。口径：**只关声音，不删任何东西** —— 曲目条目、A/B 两版 OGG 资产与触发调用原地保留，随时可开回。

## 变更与原因

**`src/world3d/TowerAtmosphere3D.gd`（新增开关 + 屋顶分支门控）**

- 新增导出开关 `rooftop_music_enabled`，默认 `false`，与既有 `background_music_enabled` 并列、语义互不重叠：
  - `background_music_enabled` = **整场景静音**（远征关卡用，拦掉本场景全部 `MusicManager` 播放，含 Boss 房 `push_and_play()`）；
  - `rooftop_music_enabled` = **只门控 100F 天台这一首** `rooftop_relax`，其余楼层分派逻辑一字不动。
- `_update_music_for_floor()` 的 `rooftop` 分支由「无条件 `mgr.play("rooftop_relax")`」改为按开关分派：

```gdscript
if rooftop:
    if rooftop_music_enabled:
        mgr.play("rooftop_relax")   # 原调用保留，未被删除
    else:
        mgr.stop()                  # 关闭时显式清掉上一场景残留曲目
    return
```

- **为什么关闭分支必须显式 `stop()` 而不是靠 `play()` 返回 false**：`MusicManager` 是 autoload，跨场景不重置。从天台入口（`ROOFTOP_LOGOUT_SPAWN`，100F）进入时，上一场景的 `base_passion` / `descent_suspense` 仍挂着；只「不播新曲」会让旧曲继续响到天台，等于没关。
- 未触及 `MusicCatalog`：`rooftop_relax` 条目、A/B 两版 OGG 路径与 `res://assets/audio/music/rooftop_relax/` 资产全部原样保留，`_pick_track` / A/B 随机 / 循环语义不变。

**`tests/verification/verify_base99_radio.gd`（断言随契约更新）**

- 原断言「离开99F后天台音乐未恢复」期望 `get_current_music_id() == "rooftop_relax"`，与新契约矛盾。改为断言**没有任何当前曲目**：

```gdscript
_assert(failures, MusicManager == null or MusicManager.get_current_music_id().is_empty(),
        "离开99F后天台不应播放任何BGM")
```

- 该用例的其余部分（radio 离楼关灯、音频停止、返楼不自动恢复）未改：radio 走自己的 `AudioStreamPlayer3D`，不经 `MusicManager`，本次开关对它无影响。

**文档面**

- `docs/v0.1/design/音乐播放清单.md`：§1 表格 `rooftop_relax` 行播放条件标注「2026-10-14 起暂不播放」；§2「不播放背景音乐的场景」新增 100F 天台一行（写明是开关关闭而非下线、以及关闭时清残留）；§3 使用规则新增第 6 条说明两个开关的分工；更新日期 → 2026-10-14。
- `docs/v0.1/MODULE_INDEX.md` 的 `AUDIO-MUSIC` 行状态栏追加本次变更说明。
- `docs/v0.1/feature_registry.json`：本记录挂入 `AUDIO-MUSIC` 的 `development_records`；`updated_at → 2026-10-14`。

### 兼容性影响

- 塔楼其余楼层（下塔 `descent_suspense`、Boss 层 `boss_intense`、99F 收音机本地曲）行为逐字不变。
- 远征关卡静音仍由 `background_music_enabled=false` 承担，优先级高于本开关；远征判定的触发点（`TowerDescent3D._install_atmosphere()` 在 `add_child` 前 `set`）未动。
- 游戏音量设置、`Music` 总线、`AudioManager` 的 SFX 链路无关。
- **存档格式零影响**（本次不碰任何持久化字段）。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志证据 |
|---|---|---|---|
| `godot --path <隔离壳>/project --scene res://tests/verification/verify_base99_radio.tscn --resolution 1280x720` | 独立项目壳（junction 链接主工程）+ 唯一 `user://`；NVIDIA RTX 4060 Ti / Vulkan Forward+ | **0（全绿）** | `BASE99_RADIO_OK: prefab, bounds contract, battery cabinet placement, dispatched mouse input, off-A-B-off, Music bus, fixed looping tracks, floor music exclusion` |
| `check_verification_log.py <上述日志>`（套件同款日志门禁） | 同一日志 | **0** | 无未登记脚本错误、无资源泄漏判定 |
| `run_verification_suite.sh scene verify_base99_radio` | —— | **未跑通（既有阻塞，非本次引入）** | `RUNTIME_DESIGN_DATA_PROJECTION_FAILED`：`sync_runtime_design_data.py --check` 报 `data/level_plans/expedition_01/room_templates/boss_50x40.json` 投影漂移 + `projection manifest drift`；工作区里 `art_source/design/whitebox/tower_zones/expedition_01/.../level_plan.json` 等为**既有**未提交改动，与本次改动无因果关系 |
| `check_documentation_contracts.py` | python 3.13.14，无运行时 | 3 条**既有**红项 | `CHANGELOG.md:587` 断链、6 个未注册验证场景、媒体域 `ui row count: expected 16, got 18`；本次新增的记录文件与链接**未被判问题** |

- 说明：`verify_base99_radio` 属 `visual_scenes`，套件会以**真实渲染器**运行；以 `--headless` 直跑会因鼠标射线在无窗口下失效而产生 5 条与本次无关的红项（已实测确认），因此本项目验收一律取真渲染结果。
- **未跑**全量 `smoke/core/full`：套件被上表第 3 行的既有投影漂移挡在入场检查处，任何场景都进不去。

## 遗留与状态更新

- **恢复路径**：把 `TowerAtmosphere3D.rooftop_music_enabled` 置 `true`（或在 `.tscn` 上勾选）即恢复天台 BGM，无需改任何其它代码或补资产。
- `AUDIO-MUSIC` 状态保持 `partial`（本次是可逆的产品口径调整，不提升完成度）。
- 未提交（改动留在工作区）。
