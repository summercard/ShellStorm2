---
name: godot-verification-suite-triage
description: 诊断并修复 Godot 验收套件（run_verification_suite.sh + check_verification_log.py）的日志门禁失败——exit 3（意外引擎错误）与 exit 4（退出时资源泄漏）。用于「套件跑出红项 / 场景 exit 3 或 4 / resources still in use at exit / ObjectDB instances leaked / 判某红项是回归还是既有 / 要不要加 expected_errors 白名单」这类问题。不用于资产制作、也不用于正常通过时的收尾。
agent_created: true
---

# Godot 验收套件门禁失败：定性 → 定位 → 修复

## 铁律

1. **不看裸退出码**。本机 safe-delete 守卫会拦下套件 EXIT trap 的 `rm -rf` 临时工作区并**覆盖退出码**，表现为打印 `VERIFICATION_SUITE_OK` 却 `EXIT=1`。**只看 `VERIFICATION_SUITE_OK` / `VERIFICATION_SUITE_FAILED` / `FAILED_SCENE <名>:<码>` 行。**
2. **不手搓 Godot 命令行跑验证场景**。`visual`/`renderer` 名单里的场景去掉 `--headless` 会挂死等 viewport 纹理（曾空转烧 40 分钟）。一律 `bash scripts/run_verification_suite.sh scene <名>`，它会在 `is_renderer_scene` 命中时自动切非 headless。
3. **`git status` 在本仓不可信**（曾漏报 16/17 处索引-工作区差异）。**暂存完整性一律用 `git diff --name-only`**。

## 退出码语义（`scripts/check_verification_log.py`）

读日志逐行，命中 `SCRIPT ERROR:` 或 `(^|\s)ERROR:` 的行才计入：

| 命中内容 | 返回 | 含义 |
|---|---|---|
| 白名单 `tests/verification/expected_errors/<场景>.txt` 里的正则 | 跳过 | 预期错误 |
| `resources still in use at exit` / `ObjectDB instances leaked at exit` | **4** | 资源泄漏 |
| 其他任意 `ERROR:` / `SCRIPT ERROR:` | **3** | 意外引擎错误 |

`run_scene()` 的判定链：headless 跑 `verify_scene_preflight.gd`（2=装载失败、3=preflight 日志有意外错误）→ 跑场景本体（`scene_result`）→ 判日志（`log_result`）。**当 `scene_result==0 && log_result!=0` 时返回 `log_result`**，所以「场景自己 exit 0、日志有 ERROR」会表现为 exit 3 或 4。

> ⚠️ 只有 `ERROR:` 前缀的 `ObjectDB instances leaked at exit` 才算；`WARNING: ObjectDB instances leaked at exit` 不计入。

## 决策树

```
FAILED_SCENE x:3  → 是「预期错误没声明」还是「真 bug」？
   ├─ 该 ERROR 是本测试**刻意**触发的（例如测试故意传非法 id 断言被拒绝，
   │  被调用方用 push_error 报出）→ 加白名单文件，见下节
   └─ 否则 → 真 bug，修代码

FAILED_SCENE x:4  → 资源泄漏，走「泄漏定位」
```

### 加白名单的正确姿势

`tests/verification/expected_errors/<场景>.txt`，一行一个 **Python 正则**，`#` 开头是注释：

```
# 说明这是哪个测试的哪一项刻意触发的
ERROR: \[MusicManager\] music_id 未注册
```

- 文件编码 UTF-8、无 BOM、CRLF（与同目录既有文件一致）。
- **正则里的 `[` 必须转义**：`[MusicManager]` 会被当成字符类，静默匹配不到。
- 匹配的只是那一行；断言本身失败仍走 `get_tree().quit(1)`，不会被掩盖。
- 先确认这不是本次改动引入的：`git stash push -- <改动文件>` 后在 HEAD 上复跑，同样的 exit 码即既有问题。

## 泄漏定位（exit 4）

**第一步：判归属。** 若多个不相关场景的泄漏签名**恒为同一句 `2 resources still in use at exit`**（数值不随场景加载的资产变化），那必是 **autoload / 全局单例级**，不是资产。若泄漏数值随场景变化，才往资产方向查。

**第二步：看漏了什么。** 套件只报条数。加 `--verbose` 取证的做法是**复制套件脚本**，只在两处场景分支（`is_renderer_scene` 的 if/else）加 `--verbose --scene`，然后走套件自身的隔离工作区跑：

```bash
cp scripts/run_verification_suite.sh /tmp/_tmp_verbose_suite.sh
# 在两条分支的 godot 命令行里插入 --verbose
GODOT_BIN="<godot_console.exe>" bash /tmp/_tmp_verbose_suite.sh scene <场景名> 2>&1 | grep "still in use"
```

日志会出现 `Resource still in use: <res://路径> (类型)`。

**第三步：判「时序相关」还是「确定性」。** 同一场景连跑 5–6 次统计泄漏次数。偶发即时序相关——这类**不能靠加 `stop()` 解决**，要顺着「谁在退出前后还动了它」查。

**第四步：区分「真回归」与「既有」。**

```bash
git stash push -- <改动文件>          # 回到 HEAD
bash scripts/run_verification_suite.sh scene <场景名>
git stash pop
```

两边同码即既有。另可用审计基线 `docs/v0.1/audits/evidence/core_results.json` 对 `aggregate core` 做集合比较：**判据是「当前红项集合 ⊆ 基线红项集合」，不是「core 全绿」**——本仓 core 从来不是全绿。

## 已知修复约定：headless 不真播

**先例**：`src/core/AudioManager.gd:72`

```gdscript
# Headless validation不创建播放器，但仍可通过 validate_runtime_assets() 校验文件。
if DisplayServer.get_name() == "headless":
    return
```

套件对**非渲染场景**一律加 `--headless`，而这些场景只断言状态、不校验声音。所以在 headless 下跳过真实播放是**仓库认可的写法**，不是绕过测试。

`MusicManager` 的已落地版本（`docs/v0.1/development/2026-09-17_music_manager_headless_exit_leak.md`）：

- `_exit_tree()`：kill tween → `stop()` + `stream = null` → 清状态 → 回收运行期补建的 AudioBus。
- `_shutting_down` 标志：**在 `play()` 和 `_play_track()` 两处都要守卫**，因为 `_on_stream_finished` 的循环重播会绕过 `play()` 直接进 `_play_track()`。
- `_play_track()` 在 headless 下**不 `load()`、不播放**，只落状态字段并发变更信号 → 副作用是 headless 下 `is_playing()` 恒 `false`，判「在放哪首」必须用 `get_current_music_id()`。

> 关键教训：**`stop()` + `stream = null` 压不住 Ogg 回放对象**（`AudioStreamPlaybackOggVorbis` / `OggPacketSequence` 在解码收尾阶段无法确定性释放）。真正的解法是**根本不在 headless 里加载它**。

## 收尾

1. 跑 `aggregate core` 复验，确认泄漏行归零且**红项集合 ⊆ 基线**。
2. 跑静态门禁：`python3 scripts/check_asset_runtime_naming.py --quiet`、`python3 scripts/check_asset_registry.py --scope structure`（需 venv python + openpyxl，且在 `/tmp` 下跑）、`check_documentation_contracts.py`。
3. 删掉临时脚本，`git diff --name-only` 应为空。
4. 提交信息里写清：症状 → 根因（含被排除的可能性）→ 修法 → 逐场景验收 → 相对基线的红项集合比较。
5. **同步记忆**：若本次推翻/补全了旧结论，改 `MEMORY-playbooks.md` 里的原条目（别只追加）。
