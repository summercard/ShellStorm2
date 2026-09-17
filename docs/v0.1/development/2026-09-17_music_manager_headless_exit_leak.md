# 音乐系统退出资源泄漏与 headless 播放约定

日期：2026-09-17；工程版本：0.1.0；功能：AUDIO-MUSIC；代码基线：7d41a29及当前工作区。

来源：验收套件长期把 `verify_base_facility_framework` 等场景判为资源泄漏（exit 4），用户要求修掉。主契约为[音乐系统与配乐资产](../14.8_音乐系统与配乐资产.md) §4.1。

## 症状

- 基线 `docs/v0.1/audits/evidence/core_results.json`（2026-09-12，61 项）中 9 个 core 场景带 `ERROR: 2~6 resources still in use at exit`。
- `scripts/check_verification_log.py` 对该行返回 4；`run_verification_suite.sh` 在 `scene_result==0 && log_result!=0` 时取 `log_result`，于是这些场景由 exit 0 变成 exit 4。
- 泄漏条数恒为偶数，且随播放曲目数增长：播 1 首 = 2，`verify_music_system` 播 3 首 = 6。

## 根因

三件事叠加，不是"补一个 `stop()`"就能解决：

1. **autoload 先于当前场景退出树**。`BaseWorld3D._start_base_music_with_delay()` 用 `await get_tree().create_timer(0.1).timeout` 再 `play("base_passion")`。该协程若恰在 `MusicManager._exit_tree()` 之后恢复，会把 `stream` 重新挂回播放器；引擎紧接着释放播放器，`AudioServer` 仍持有该 `AudioStreamOggVorbis` 及其 `OggPacketSequence`。
2. **`stop()` + `stream = null` 压不住 Ogg 回放对象**。补上 `_exit_tree()` 清理后 `verify_door_passability` 变干净，但 `verify_base_facility_framework` 仍偶发泄漏（6 次里 2 次）。插桩对比证明泄漏运行与干净运行的 `_exit_tree` / `play()` 轨迹完全相同——即不存在晚到的 `play()`，泄漏来自 `AudioStreamPlaybackOggVorbis` 在 Ogg 解码收尾阶段无法被确定性释放。反向验证：去掉"运行期 Music 总线回收"后仍 6 次里 4 次泄漏 → 与总线无关，纯粹是 Ogg 回放对象。
3. **headless 下本就不需要真播**。验收套件对非渲染场景一律加 `--headless`，这些场景只断言状态，不校验声音。

## 变更

- `src/audio/MusicManager.gd`
  - 新增 `_exit_tree()`：kill tween → `stop()` + `stream = null` → 清状态 → 若 `Music` 总线是本类运行期补建的（项目无 `AudioBusLayout`），`AudioServer.remove_bus()` 收回，避免留下孤立 StringName。
  - 新增 `_shutting_down` 标志：`play()` 与 `_play_track()` 两处守卫。后者必须守，因为 `_on_stream_finished` 的循环重播会绕过 `play()` 直接进 `_play_track()`。
  - 新增 headless 早退：`_play_track()` 在 `DisplayServer.get_name() == "headless"` 时只落 `_current_music_id` / `_current_track_path` 并发 `music_changed`，不 `load()`、不播放。与 `src/core/AudioManager.gd:72` 的既有写法一致。
- `tests/verification/expected_errors/verify_music_system.txt`（新增）：把第 6 项 `play("__nonexistent__")` 触发的 `push_error` 声明为预期错误，否则日志门禁判 exit 3（该失败在 HEAD 版就存在，与本次修复无关）。
- `docs/v0.1/14.8_音乐系统与配乐资产.md`：新增 §4.1 记录退出约定与 headless 约定；§6、§7 补相应注意。

## 影响面

- **headless（验收套件）**：不产生回放对象，泄漏源消失。副作用是 `is_playing()` 在 headless 下恒为 `false`；现有测试全部走 `get_current_music_id()`，不受影响。
- **真实运行（渲染场景）**：`DisplayServer.get_name()` 非 `"headless"`，加载与播放路径不变。

## 验收

- `verify_music_system`：HEAD 版报 `6 resources still in use at exit`（exit 3）；修复后打印 `MUSIC_SYSTEM_OK`、无泄漏、exit 0。
- `verify_base_facility_framework` / `verify_door_passability` / `verify_tower_descent_flow`：各连跑 3 次，均 exit 0、0 泄漏。
- 渲染场景 `verify_tower_descent_visual`（非 headless，真播）：exit 0、无泄漏。
- `verify_base_world_3d_visual` 仍 exit 1（`Base visual scene does not contain the expected nine remaining catalog facilities`）：用 stash 回到 HEAD 复现同样结果，属既有失败，与本次无关。

## 局限

- 本修复只保证 headless 下不泄漏；真实运行时若在退出链路上仍有 Ogg 播放，理论上仍可能触发同类泄漏，但进程退出由窗口关闭驱动、时序不同，未在本次范围内复现。
- **全量复跑**：`bash scripts/run_verification_suite.sh aggregate core`（修复后）= **68 场景 / 6 红 / `ERROR: N resources still in use at exit` 0 条**（仅 1 条非 ERROR 级的 `WARNING: ObjectDB instances leaked at exit`）。6 红全部 ⊆ 2026-09-12 基线 12 红（无新增），且比 B2 复跑的 16 红**正好少掉 10 项纯泄漏**。静态门禁：命名 exit 0（欠账 1058，未变）、文档契约 `issues: []`、台账 `issues=38`（基线值）。
