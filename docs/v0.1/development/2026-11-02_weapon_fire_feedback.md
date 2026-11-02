# 2026-11-02 枪械开火反馈：后坐回弹 + 弹性压扁（两轮返工）

> 功能 ID：`WEAPON-COMBAT`｜工程版本 `0.1.0`（`project.godot` 未改）｜代码基线：工作区
> 设计依据：[04 §11.4 枪械开火表现](../04_技术施工_战斗与局内成长.md)（本轮写入）
> 相关：[14.6 §3.3 硬规则 2](../14.6_特效系统与制作规范.md)（枪口花火必须跟 `muzzle`）

## 1. 两轮反馈与返工原因

| 轮次 | 业主原话 | 我的实现 | 结果 |
|---|---|---|---|
| 一 | 「增加枪开枪的时候的向后弹一下 然后扩大压缩的动画，让枪更加有反馈」 | `punch=0.09`、`kick=0.115`、指数衰减 | **看不见** |
| 二 | 「目前没有看到变化，是不是动画速度太快了？我希望的是一个由弹性压扁然后弹回去的动画」 | 按实测像素重定幅值与时长，压扁改欠阻尼弹簧 | 见 §3 实测 |

**第一版失败不是速度问题，是量纲问题。** 我先用探针在实战相机（43°/−52°/1920×1080）下量了枪口→枪根的屏幕长度 = **15.8 px**。那么第一版的压扁 `0.09 × 0.62 × 15.8 ≈ 0.9 px`、位移 2 px、压扁相位 30~60 ms —— 不到一个像素、两三帧就没了，调多慢都看不见。

这条教训写进设计正文（§11.4.1）：**任何「枪身视觉反馈」的定值必须先实测屏幕像素，不能凭物体空间的感觉给数。**

## 2. 最终实现

落地 `src/combat3d/WeaponModel3D.gd`：

- 常量 `GUN_FIRE_FEEDBACK`（9 枪 × `kick_m/hz/punch/punch_hz/roll`）、`DEFAULT_FIRE_FEEDBACK`、
  `RECOIL_DAMPING=0.42`、`PUNCH_DAMPING=0.50`、`PUNCH_AXIAL_RATIO=0.62`、
  `RECOIL_MAX_INTEGRATION_STEP=1/240`。
- 状态 `_recoil/_recoil_velocity/_recoil_hz/_punch/_punch_velocity/_punch_peak/_punch_hz/_punch_roll`。
- 函数 `_tick_fire_feedback()`、`_integrate_spring()`（两个通道共用）、`_apply_fire_feedback()`、`_reset_fire_feedback()`。
- `_fire_now()` 原 `_recoil = 0.16 if ... else 0.09` → `_apply_fire_feedback()`。
- `_process()` 写 `_visual_root.scale` 与 `rotation.z` 的压扁侧倾；停机条件补判速度与压扁；停机写回纯 fate 基准。
- `get_snapshot()` 新增 `recoil_offset / recoil_velocity / recoil_hz / visual_punch /
  visual_punch_velocity / visual_punch_peak / visual_punch_hz / visual_punch_roll / fire_feedback_id`。

**两条定值下界（由实测反推，不是拍脑袋）**：

- `punch ≥ 0.31` ⇐ `punch × 0.62 × 15.8 px ≥ 3 px`（低于 3 px 动态画面里抓不到）。
- `punch_hz ≤ 10` ⇐ 半周期 `1/(2·punch_hz) ≥ 50 ms = 3 帧 @60fps`。

**连射语义 = 刷新而非累加**：`punch = max(punch, peak)`。旧「累加 + 封顶」实测算下来方向是反的 —— 机枪 12 发/秒每 83 ms 衰减到 20.9%，稳态只有 `0.695 × peak`，连射比单发还弱。刷新语义上界恒为 `peak`，不可能鼓成气球。

## 3. 实测（`tools/probe_weapon_fire_feedback.tscn`，1920×1080，实战相机）

| 项 | 数值 |
|---|---|
| 静息枪身屏幕长度 | **15.8 px** |
| 压扁峰值（手枪 `punch=0.62`） | **6.4 px**，缩短 **9.4 px / −59%** |
| 压扁衰减到峰值 10% 的耗时 | **100 ms ≈ 6 帧 @60fps** |
| 近景 6 帧 | 压扁 → 回正 → 拉长（punch −0.075）→ 回正，形状肉眼可辨 |

探针输出两段：实战相机下的**客观像素数字**（不产图，不受裁切坐标影响），以及近景 6 帧拼图供人眼复核形变**形状**。近景镜头不代表实战尺度，尺度一律看数字。

## 4. 验证结果

| 命令/场景 | 环境 | 结果 | 说明 |
|---|---|---|---|
| `verify_weapon_fire_feedback`（`core_scenes`） | headless，`APPDATA` 指向工程外临时目录 | **通过，465 断言** | 九枪定值、过冲曲线、压扁→拉长包络、可见性下限、弹道隔离、连射刷新/不累加/是脉动、分档序 |
| `tools/probe_weapon_fire_feedback.tscn` | Forward+ 真实渲染 | 通过 | 见 §3 数值与拼图 |
| `verify_starting_weapon_contract` | headless | 通过 | 出厂枪身份/射程/接线未受影响 |
| `verify_bullet_vfx_profiles` | headless | 通过（samples=69） | 端到端真开火路径未受影响 |
| `verify_3d_fate_weapon_flow` | headless | 通过 | 命运 `visual_local_scale` 仍为纯 fate 基准 |
| `verify_player3d_weapon_pose_collision_flow` | headless | 通过 | 手动 `set("_recoil", x)` 摆位的举枪水平断言仍成立 |

**未执行**：完整 `core` 套件、移动端、不同分辨率下的观感复看。

**返工过程中被测试抓住的两个真问题**（保留记录，别忘）：

1. 机枪/喷壶原给 `punch=0.28/0.26`，低于可见下限 0.31 ⇒ 12 发/秒下仍然看不清。已抬到 0.36/0.34。
2. 霰弹回弹到静止需 0.600 s，超过最初写的 0.55 s 阈值。核对后确认它没跨发（霰弹 1.2 发/秒 = 0.833 s 间隔），是阈值定得太紧 —— 改成 0.71 s，并注明判据来源。

## 5. 遗留

- **观感仍需业主实机确认**。调法已收敛成两个旋钮：太弱 → 抬 `punch`（下界 0.31，越大越扁）；太快 → 降 `punch_hz`（上界 10，越小越慢）。两个方向都有门禁兜着，不会调回「看不见」。
- 恶魔命运 `uncontrolled_recoil_scale` 仍只乘位移、不乘压扁（保留原语义，未扩大改动面）。
- 手枪 `punch=0.62` 时横向 ×1.62、轴向 ×0.38，枪会短暂变成接近方形的团块。这是刻意的卡通风 squash；若实机觉得过头，降到 0.45 左右（仍有 4.4 px 变化，过门禁）。

## 6. 环境事实（不是本次改动引入）

工作区有并发进程周期性对已跟踪文件做 `git checkout`，本次 `WeaponModel3D.gd` 与
`run_verification_suite.sh` 被回滚过多次。所有改动已 `git add` 进索引，并固化成可重放脚本
（`../work_tmp/apply_fire_feedback*.py`、`sync_test_v4.py`、`sync_docs_v4.py`）。

另：跑回归时 `src/world3d/Dungeon3D.gd` 有另一处在途改动引用了未定义的 `pickup_delay_after_spawn`，
导致脚本链整体编译失败。已用 `git show HEAD:` 临时还原跑完回归后原样写回（备份 `../work_tmp/Dungeon3D.wip.gd`）。
