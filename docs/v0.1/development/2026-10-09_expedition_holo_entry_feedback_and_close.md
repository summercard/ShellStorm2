# 远征全息城市入口反馈与关闭时序

日期：2026-10-09。工程版本：0.1.0。FeatureID：WORLD-ENTRY / BASE-FACILITY。
来源：主人对远征情报室 3D 选关界面的两条调整要求。

## 需求原话

- 「鼠标移动上去后，关卡的图标放大的感觉要更大一些，并且边框要有个流光出来。鼠标挪开后就要复原。点击后要有个放大的弹性反馈。」
- 「用 esc 关闭这个窗口，会有个延迟。按下后要立刻播放关闭动画。」

## 一、悬停放大与边框流光

标记的世界比例与反馈强度集中到 `HologramCity3D` 顶部常量：`MARKER_SCALE 0.09`、`HOVER_SCALE 1.32`（原硬编码 1.09）、`PUNCH_SCALE 0.34`、`HOVER_RESPONSE 14.0`、`PUNCH_DECAY 5.0`、`BORDER_FLOW_SPEED 0.42`、`BORDER_WIDTH 0.05`。`face_markers` 不再直接判 `selected`，改用 `_process` 里以 `lerpf(…, 1 - exp(-14·delta))` 收敛的 `_hover` 数组，挪开即原路复原。

边框原来是四条各自独立的 `_line`（线宽 0.032）；改为顺时针四角连线，线宽提到 0.05 —— 原宽度在近景下只有一两像素，流光跑起来看不出光带。每条边按 `segment / perimeter` 写入 `arc_span`、按累计起点写入 `flow_offset`，四条合起来是一整圈相位连续的环流。新增 `hologram_frame.gdshader` 承担这套描边：常亮部分保持 `ALBEDO + EMISSION = 3 × tint`，与旧 `_material(color, 2.0)` 同当量，因此不悬停时外观不退化；`hover` 只抬高整体并叠加沿边跑动的拖尾亮头（`energy = 2.0 + 1.2 × hover + flow × 9.0`），光头约占周长三分之一并向后拖出长尾。

`_line` 返回值由 `void` 改为 `MeshInstance3D`，其余调用方沿用原写法不受影响。

## 二、点击弹性反馈

新增 `HologramCity3D.punch_marker(index)`：把该入口的 `_punch` 置满，随后按 5/s 衰减，放大效果为 `PUNCH_SCALE × _punch^0.7`，形成冲上去再回弹。

`change_scene_to_file` 会立刻接管画面，不留时间就只剩一帧脉冲，因此 `confirm_selection` 触发脉冲后，`_enter_level` 不再直接交接，而是设 `_state = "entering"` 与 `PUNCH_HOLD = 0.18` 秒倒计时，由 `_process` 递减到点后调用 `_commit_departure()`（原出发主体整体搬入）。出发链路本身一行未改。

## 三、Esc 关闭延迟的根因与修法

根因不是输入未送达（`_input` 里 `ui_cancel` 当帧就改了状态），而是 **opening 的进度映射被原样反向**：

- `eased = smoothstep(0, 0.55, _progress)` 在 `_progress ∈ [0.55, 1]` 被 clamp 到 1 ⇒ 按下后**相机静止 1.62 秒**；
- `deployment = clamp((_progress − 0.122727) / 0.65, 0, 1)` 在 `_progress > 0.772727` 恒为 1 ⇒ 按下后**楼群静止 0.82 秒**。

即按下 Esc 后有 0.82 秒画面完全不动，之后也只有缓慢的镜头位移 —— 这就是"按了没反应"的来源。

修法：`request_close()` 记录按下瞬间的 `_progress`、`_city.deployment` 与 `smoothstep(0, 0.55, _progress)`；closing 改用关闭自身归一化进度 `q = clamp(_progress / _close_from_progress, 0, 1)` 连续收敛 —— `eased = 按下值 × q^1.35`、`deployment = 按下值 × q^1.6`。指数 > 1 即起步快、收尾慢，按下当帧就有位移；起点恒等于按下时的真实状态，途中退出不跳变。

closing 的计时与释放条件（`_progress` 按 `delta / 3.6` 递减、归零即 `queue_free`）保持不变，因此开场早期取消依旧是快的（`verify_expedition_level01_flow` 只等 0.15 秒即要求释放，该路径不受影响）。

## 四、补修：光标移开就要复原（焦点与选中解耦）

主人复核后追加：「光标离开选中后就要回去变小，而不是选中另一个再变小」。

根因是**把"选中"直接当成悬停来源**：`_input` 里 `_selection` 只在 `_pick` 命中入口时被赋值，移开到空白时不复位；城市的放大、流光、标签高亮又全部读 `selected`。于是移开光标后入口一直保持放大，直到悬停到另一个入口才换人缩小。

修法是把**焦点**从选中项里拆出来：

- `HologramCity3D.selected` 重命名为 `focus`（-1 = 无），它才是放大/流光/标签高亮的唯一来源。
- `RogueMapSelectMenu` 新增 `_focus`；`_input` 的鼠标移动分支现在**无条件**更新焦点 —— `_pick` 返回 0/1 时同时更新选中项与焦点，返回 2（返回标识）或 -1（空白）时只把焦点置 -1。
- `_selection` 的语义收窄为"Enter/A 的确认目标"，移开时故意保留，因此"把鼠标挪到一边再按 Enter"仍有目标。
- 键盘与手柄方向切换统一走新增的 `_shift_selection()`，把焦点一起带过去 —— 否则光标停在空白后按键看不出选中了谁。

二者之所以不能合并成一个变量：选中项**必须**在移开时保留，焦点**必须**在移开时清空，两个需求方向相反。

## 同步资产与文档

- 新增 `assets/art/ui/expedition_city/hologram_frame.gdshader`。
- `assets/art/ui/expedition_city/README.md`：文件表补该着色器，追加 r4 段。
- `assets/art/ui/expedition_city/asset_manifest.json`：`visual_revision` r3 → r4，新增 `interaction_feedback` 参数块。
- `docs/v0.1/design/远征全息城市交互设计.md`：新增「入口反馈与关闭时序（r4）」。

## 验证

对照实验（同一台机器、同一 Godot 4.6.3、同一场景序列）：

| 探针读数（按下关闭后 0.06s） | 改动前（HEAD） | 改动后 |
| --- | --- | --- |
| 楼群 `deployment` | 1.000000 → **1.000000** | 1.000000 → **0.970535** |
| 镜头位移（m） | **0.000000** | **0.194507** |

左列就是"按下 Esc 没反应"的直接读数：按下后楼群与镜头都完全不动；右列证明关闭已在按下当帧起播。

- 新增探针 `tests/verification/probe_holo_entry_feedback`（不经 `Input.parse_input_event`，直接把事件喂给 `_input` 的确定性路径），输出 `HOLOGRAM_ENTRY_FEEDBACK_OK hover=1.32 punch=0.34 borders=4 focus_decoupled=true close_immediate=true`，退出 0。除原有四项外，新增断言：光标移开后 `_focus == -1` 而 `_selection` 保留、悬停强度归零、尺寸与静止态一致、`_pick` 对空白取样点确实返回 -1（保证断言前提成立）。比值断言改用相对容差 —— 收敛式插值不会精确落在目标值上，用 `is_equal_approx` 会测成浮点而不是行为。
- 实机读数（同机位三态连拍）：静止 `0.0900` → 悬停 `0.1188`（比值 **1.320**）→ 光标移回空白 `0.0900`（比值 **1.000**），末态 `focus=-1 selection=0`。截图 `_scratch/holo_leave_rest_a.png` / `_hover_b.png` / `_back_c.png`。
- 实机读数：静止态标记比例 0.0902、悬停态 0.1188，比值 **1.317**（`HOVER_SCALE = 1.32`，探针容差内一致）。
- 实机截图 `_scratch/holo_entry_rest.png` 与 `_scratch/holo_entry_hover.png`（同机位连拍，menu 的 `_selection` 从 -1 切到 0）：悬停侧边框明显加粗变亮，且左边缘与下沿出现连成一片的亮带（流光），静止侧为均匀暗描边。- 自带 `verify_expedition_hologram_city`：本机**改动前后同样**报 `hover input failed`（合成鼠标事件与 `await get_tree().process_frame` 的派发时序），改动前另有 7 条连锁失败（点击路由、Enter、手柄方向、手柄确认、取消未进入 closing、菜单未释放、镜头/HUD 未恢复），改动后只剩前两条。即本次改动没有引入新的失败项；该场景的输入段在本机不可作为判定依据，判定改用上面的探针与 A/B 对照。
- 导入与运行日志无 `SCRIPT ERROR` / `ERROR` / `SHADER ERROR`，新着色器编译通过。

## 已知的既有环境问题（非本次引入）

- `verify_expedition_hologram_city` 的输入断言在本机不稳定：同一份代码连跑两次，失败项在 1～2 条之间浮动，且改动前的版本失败更多 —— 属合成输入派发时序问题。
- `run_verification_suite.sh` 的导入门禁在本次运行中被主工程根目录的残留 `_godot_appdata_nar025_r2` 绊倒（`ERROR: Cannot go into subdir '_godot_appdata_nar025_r2'`），在 import 阶段即以 `VERIFICATION_IMPORT_LOG_FAILED` 退出，未进入场景段。该目录随后已不在盘上，主工程 `--import` 复跑 0 错误；本次因此改用「就绪缓存 + 隔离 APPDATA + 直接跑场景」的方式验收。残留 `_scratch/.verify_ws/shellstorm-verification.*` 工作区（每份约 5 GB）当前有 10 个未清，与本次改动无关。

## 限制

- 悬停倍率与流光速度按"明显可辨"取初值，未做美术终验。
- punch 的 0.18 秒展示窗口会让出发比点击晚 0.18 秒 —— 这是让反馈可见的代价，出发链路本身未动。若要求"点击即切场景"，把 `PUNCH_HOLD` 置 0 即退化为原行为。
