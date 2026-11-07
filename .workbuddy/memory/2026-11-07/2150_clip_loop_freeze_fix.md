# 21:50 跑步动作定格修复（GLB 循环标记丢失）

**事务**：主人报「跑步动作会留在最后一帧，不是重复的」。查明并修复。

## 根因
GLB 导入无 post-import 脚本 ⇒ **128 段 Animation 全是 `LOOP_NONE`** ⇒ `AnimationPlayer.play()` 播完**定格末帧**。其中 73/75 段本该循环（idle/moving/walking 及全部持枪运动分支）。跑步剪辑 0.708s，播完即停。

**真源**：老通道 Blender 采样库 JSON 里每段带显式 `loop` 布尔（75 true / 53 false），**GLB 导入不带这个信息**。

## 修法
`ClipMotionLibrary3D._apply_loop_flags()`：`bind()` 里、**任何 play() 之前**，从 JSON 抄 `loop` 到 `Animation.loop_mode`。读不到库**不改**并上报 `loop_source`，不静默成功。
实测 0→75 段 LOOP_LINEAR，与 JSON 比对 128 段零不一致。

## 判据设计（新门禁核心）
**标记对 ≠ 播放路径真循环**（seek 钉帧 / speed_scale=0 / 淡化打断都能定格，而 loop_mode 仍读 LOOP_LINEAR）。判据必须跨真帧看骨骼周期回归：
- 活性：摆幅 > 0.002 m（抓"骨架没被驱动"，实测严格 0）
- 回归性：一周期后离起点 < 0.045 m（抓"定格末帧"）
- 反向对照：一次性剪辑追加一周期后漂移 < 0.045（抓"被误设全员循环"）

**阈值来源**：0.002 照待机定（sidearm_idle 实测 0.0038，本是呼吸级微动）；0.045 因采样是离散帧、一周期结束点不可能正好落在起始相位（walking 实测 0.0271），而定格偏差是整段动作幅度量级（0.3m+），差一个数量级。

**判据有效性经反向验证**：临时禁用 `_apply_loop_flags()` ⇒ `sidearm_idle` + 三个 `*_moving_forward` 摆幅立刻 0.0000 报红，**精确复现主人报告**；恢复后 16/16 全绿。

## 两个 API 踩坑（记忆里那条"别信像冻结的读数"的新实例）
1. **`get_bone_pose_position()` 是静止姿态**（rest pose），动画播什么都不变 ⇒ 首版摆幅恒 0.0000，差点把「没循环」误判成「读不到动作」。必须 `get_bone_global_pose().origin`。
2. **`AnimationPlayer` 靠引擎帧推进**。紧循环手调 `avatar._process()` 只重跑运动库采样，AnimationPlayer 时间一步没走 ⇒ 骨骼永远同姿态。必须 `await get_tree().process_frame`。
3. `Vector3` 没有 `is_infinite()`（那是 float 的）；用 `not is_finite()`。哨兵用 `Vector3(INF,INF,INF)`，**别返回 null/Variant** —— 会把后续类型推断拖成 Variant，而本工程告警即错误会直接拒编译。

## 交付
- **新正式用例** `tests/verification/verify_player3d_clip_loop_behavior.tscn`（16 项），已登记进 `scripts/run_verification_suite.sh` 的 `core_scenes` + `MODULE_INDEX.md` 的 `PLAYER-STATE` 行。
  ⚠ **新增用例必须同时改这两处**，否则 `check_documentation_contracts.py` 报 `unregistered`。
- 标记审计（互补，非替代）：`tools/ss2_clip_loop_audit.tscn` —— 它走**真实装配路径**才有意义；直接 instantiate 裸 GLB 拿到的是未修补的引擎默认值，会报假红。
- 验收记录已补：`docs/v0.1/development/2026-11-07_player_avatar_clip_swap_acceptance.md` 第 ⑤/⑤-b 节。

## 回归
修复专项 19/19、判活 2/2、循环行为 16/16、标记审计 2/2 —— 全绿，前序修复无退化。
