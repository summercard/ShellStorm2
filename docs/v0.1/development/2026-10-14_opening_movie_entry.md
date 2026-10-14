# 全新存档开场影片接入（loading → 影片 → 无缝进游戏）

日期：2026-10-14；记录ID：2026-10-14_opening_movie_entry；功能ID：ENTRY-AVATAR；工程版本：0.1.0。
设计依据与修订：[主页面与角色换装 §1.1/§1.2](../16_技术施工_主页面与角色换装.md)（ENTRY-AVATAR r3）；代码基线：当前工作区（提交前标记工作区）；登记条目：[0.2-ENTRY-001](../../v0.2/PLAN.md)。

## 变更与原因

业主诉求（原话）：

> C:\Users\zhuangmenghong\Downloads 下有个mv的文件，帮我做成游戏开场动画，如果是新存档，游戏loading后，将会播放这个动画，然后无缝衔接开场，就是进入游戏，不用进入主页菜单。 如果有存档的就照旧。更新到设计文档中。

**最终行为**：全新存档 → `StartupLoadingScreen`（loading）→ `OpeningMovieScreen3D`（20.06 s 开场影片）→ 渐黑交接 → 直接站在 98F 主人的办公室，开始主线开场 01。已有存档 → 照旧 `MainEntryScreen3D` 主页菜单。全程不切场景、不复制角色、不读写存档。

### 「全新存档」在这份工程里的准确定义（读代码得出，非本轮新造）

判据是 `BaseData.tutorial_completed == false`（且无 runtime 快照）。**「教程完成」的触发点是走进 99F 基地**（`BaseManager.mark_tutorial_completed()`，理由 `tutorial_completed_on_99f_entry`）。因此边界是：

| 存档形态 | 重新上线看到 |
|---|---|
| 从未开始 | 开场影片 |
| 已到 98F、**尚未下到 99F**（新手期未结束） | 开场影片**再放一次** |
| 已到过 99F 基地（教程完成） | 主页菜单 |

中间那一档是**有意保留**的：98F 正是影片要无缝接进的那间屋子，新手期重开就该从头来过；这与工程既有的「98F 办公室开局」判据逐字同源。本轮未新增任何存档字段，故不存在迁移与旧档甄别。

### 代码变更

| 文件 | 变更 |
|---|---|
| `src/ui/main_entry/OpeningMovieScreen3D.gd` | **新增**。`CanvasLayer` 覆盖层：全屏 `.ogv` 播放、16:9 letterbox、锁输入、隐藏 HUD、任意键/鼠标/手柄跳过、两段渐黑收口、`transition_finished` 单发、`_exit_tree()` 幂等收口。 |
| `scenes/ui/OpeningMovieScreen3D.tscn` | **新增**。场景壳，仅挂脚本（UI 全在代码里自绘，与 `MainEntryScreen3D` 同风格）。 |
| `src/world3d/TowerDescent3D.gd` | 新增 `OPENING_MOVIE_SCREEN_SCENE` 常量、`_should_play_opening_movie()`、`_main_entry_overlay_scene()`、`is_opening_movie_active()`；`_install_main_entry_screen()` 由写死主页改为二选一。`_main_entry_screen` 变量名与类型**未动**（既有验收直接读该字段）。 |
| `scenes/StartupLoadingScreen.gd` | 同步 `change_scene_to_file()` → 后台 `load_threaded_request(..., true)` + `change_scene_to_packed()`；进度条读真实进度（与最短展示时间取大、单调不减）；阶段文案由按时间分段改为按进度分段；预加载失败退回同步切换。 |
| `assets/movie/opening_mv.ogv` | **新增**运行资产（Theora+Vorbis，854×480→30fps，10.9 MB）。 |
| `art_source/movie/opening/opening_mv_source_v001.mp4` | **新增**源归档（24.1 MB，不入包）。 |
| `tests/verification/verify_opening_movie_entry_flow.{gd,tscn}` | **新增**验收：影片资产存在且非空 / 入口分流判定 / headless 自我交接；全程 `BaseManager.save_path` 重定向到探针路径，不动真实档。 |
| `scripts/run_verification_suite.sh` | `verify_opening_movie_entry_flow` 登记进 `core_scenes`。 |

### 两条关键约束（均已钉进代码注释与设计文档）

1. **headless 下 `load()` 一个 `.ogv` 会让整个 Godot 进程挂死** —— 不报错、不返回，只能超时杀掉（`ResourceLoader.exists()` 正常，只有真正解码时才卡）。故影片层在 `test_mode / headless` 下**连 `VideoStreamPlayer` 节点都不创建**，直接自我交接；`_install_main_entry_screen()` 原有早退继续生效。
2. **Windows 上只有部分 FFmpeg 构建能产出可播的 Theora**。Godot 论坛已确认「gyan.dev 构建的 Theora 编码器是坏的，产出的视频是垃圾」。本轮实测命中：ffmpeg 自解自产的 `.ogv` 即报 `error in unpack_block_qpis`，Godot 里表现为整屏彩虹噪点（画面结构尚在、颜色全错）。**该症状与 `-q:v` 质量（4/5/6/7/8/10 全试过）、分辨率是否 16 倍数（848/864/854/1280 全试过）均无关**，是编码器本身的问题；换 BtbN 构建后同一命令一次编出正常画面。

### 兼容性

- 判据 `_should_play_opening_movie()` **复用** `_should_open_new_game_in_master_office()`，零新增存档字段，零迁移。
- 与 `REASON_RUNTIME_RESTORE` 入口天然互斥（该入口要求存在 runtime 快照，而新档判据要求**没有**快照）⇒ 续档重进永不重播。
- 预加载失败退回同步切换，不新增失败态。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `verify_opening_movie_entry_flow` | headless；`save_path` 重定向至 `user://opening_movie_entry_probe.json` | **通过**（`OPENING_MOVIE_ENTRY_OK`） | 资源存在、分流六例、headless 交接断言全绿 |
| `verify_game_entry_flow` | headless | **通过**（`GAME_ENTRY_FLOW_OK`） | 入口意图生命周期与死亡返回回归未破 |
| `probe_opening_movie_visual`（一次性探针，未入套件） | **真实窗口**（Vulkan / RTX 4060 Ti）；`project.godot` 临时指向隔离 user 目录 `ShellStorm2OpeningMovieProbe`，用后精确还原（sha256 一致） | **通过** | 抽帧 0.8/3/8/15/20.5 s + 交接后各存 PNG；`started=true`、`movie_ended` at 20.5 s、`transition_finished` at **21.72 s**（= 20.06 影片 + 0.35 保留 + 0.45 压黑 + 0.70 淡出，逐段吻合）。抽帧人眼复核：3 s / 8 s / 15 s 画面清晰正确、右下角「按任意键跳过」可见；20.5 s 为影片自身结尾黑场（此时跳过提示仍在 ⇒ 渐黑未开始，符合 0.35 s 保留设计） |
| `probe_opening_movie_e2e`（一次性探针，未入套件） | **真实窗口**；隔离 user 目录 `ShellStorm2E2EFreshSaveProbe` **清空至全新存档** | **通过** | 全链日志：`E2E_MOVIE_APPEARED t=1.39` → `E2E_TOWER_PRESENT t=1.39` → `E2E_MOVIE_GONE t=22.95` → `E2E_SHOT 06_gameplay`；截图（工程外）`ShellStorm2-work/probes/opening_movie_e2e/evidence/06_gameplay_t24.0.png` 实测 HUD 显示「98层 探索区 警戒区」「塔楼种子 769263162」「区域已肃清 · 直接开启下一扇门」「2075-01-01 09:28」，**主页菜单未出现** —— 即 loading → 影片 → 98F 办公室的完整链路真的连通；同目录 `00_startup_t0.1.png`（loading 页）与 `01_movie_t4.0.png`（影片）为前后阶段证据 |
| `probe_movie_variants`（根因定位用，**已删除**） | 真实窗口 | 用于定位 FFmpeg 编码器缺陷 | 848×480 / 864×480 / 1280×720 三档在 gyan.dev 构建下**全部**呈现彩虹噪点，且 `-q:v 4/5/6/7/8/10` 六档全试均报 `unpack_block_qpis`；换 BtbN 构建后**同一命令**码流自解 0 错误、画面正常 ⇒ 与分辨率对齐、质量参数无关 |
| `python3 scripts/check_verification_registry.py` | — | 未通过（**预先存在**，与本轮无关） | 6 个既有 `verify_*` 未登记：`verify_base99_radio_sound`、`verify_base99_swivel_chairs`、`verify_environment_bird_flocks`、`verify_expedition01_spawn_ramp`、`verify_expedition_resume_entry`、`verify_pushable_base_chairs`；本轮新增的 `verify_opening_movie_entry_flow` 已登记且不在缺失列表中 |
| `verify_new_save_handoff` | headless | 未通过（**预先存在**，已用 `git stash` 回退本轮改动复现同样 5 条红项） | 红项集中在「拾取后枪进入主武器槽」等武器拾取链，与入口分流无关 |
| 普通启动对照（`godot --path .`） | 真实窗口；隔离 user 目录 | **通过**（0 警告 / 0 崩溃） | ⚠️ 期间发现并修掉一处**本轮自造回归**：`load_threaded_request(..., use_sub_threads = true)` 会让主场景里 5 个 floor 实例化子场景在 `change_scene_to_packed()` 阶段报 `Node './floor_01' was modified from inside an instance, but it has vanished` 并**段错误**（回退本轮改动后基线零警告零崩溃）。改 `use_sub_threads = false`（只做主线程后台加载）后回归消失 —— 已把该结论写进 `StartupLoadingScreen.gd` 注释 |

## 遗留与状态更新

- **待主人过目**：影片实际观感（节奏、是否要单独的音量档、跳过提示文案位置）。
- **待真机确认**：`StartupLoadingScreen` 后台预加载在**主人真实存档**（玩法进度较深、启动 8～12 秒）下的收益 —— 本轮只在**全新**隔离档上验证了链路与时序，新档启动快、没有复现出原来的长冻结。请在自己那份档上启动一次，看进度条是否还是停在 100% 冻住十几秒。
- **未执行**：`smoke/core/full` 全量套件未跑；本轮只跑了与本改动直接相关的用例。
- **探针使用须知**：`tests/verification/probe_opening_movie_visual.{gd,tscn}` 与 `probe_opening_movie_e2e.{gd,tscn}`（配 `_e2e_capture.gd`）是**手动**探针，不进套件。它们要真窗口运行，且**必须先把 `project.godot` 临时指向隔离 user 目录**（加 `config/use_custom_user_dir=true` + `config/custom_user_dir_name="..."`，用后精确还原）—— 否则会读写主人真实档。注意自定义 user 目录落在 `%APPDATA%\<name>`，**不在** `%APPDATA%\Godot\app_userdata\` 下。
- **状态更新**：`MODULE_INDEX` 的 `ENTRY-AVATAR` 行验收入口补 `verify_opening_movie_entry_flow`；`docs/v0.2/PLAN.md` 新增 `0.2-ENTRY-001`（状态：已验收）。
- **性能**：影片解码期间的真实帧率未单独测量；影片仅 20 s 且为一次性播放，未列入性能回归。
