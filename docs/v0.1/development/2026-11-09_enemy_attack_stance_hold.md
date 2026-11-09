# 怪物攻击姿态站住：进前摇即刹停，打完再走

日期：2026-11-09；功能：MONSTER-AI / COMBAT3D（`src/enemy3d/Enemy3D.gd`）；工程版本：0.1.0（`project.godot` 未动）。
设计依据：[怪物设计 §T2.9.2](../design/怪物设计.md)（本轮改写）、[远征关卡03设计 · 行动节奏行](../design/远征关卡03设计.md)、[远征03专项工作链路 M3](../19_远征03专项工作链路.md)（本轮改写）。
代码基线：工作区（分支 `0.2`，未提交）。
关联：[收招状态机改写](2026-11-06_verification_registry_backfill.md)、[远征03受光抽搐/寻路/攻击修正](2026-11-02_enemy_ai_light_motion.md)。

业主：「怪物在攻击玩家的时候，会一边攻击一边移动，这样看起来非常不舒服。我需要怪物攻击的时候停下来，攻击后在进行移动……应该是进入攻击范围后，直接进行攻击，此时是停下的，攻击完成后，继续行动。」

---

## 一、病灶：三个"攻击中还在走"的来源

改造前，从"进射程"到"再起步"之间共有三条通路会让身体继续平移，三条都**写在注释里当作设计**：

| # | 来源 | 旧口径 | 表现 |
|---|---|---|---|
| 1 | 复刻怪前摇 `_tick_egt_windup()` | 保留 **35%** 步速"边举枪边踱半步" | 前摇 0.10~0.26 s 全程滑行 |
| 2 | 塔楼老怪前摇 | `_brake_planar(delta × 18)`，3.7 m/s 需 0.21 s / 0.38 m 才停 | 0.38 s 前摇里前一半在滑 |
| 3 | 排期连发 `_pending_volleys` | 收招只看时长（0.08~0.18 s），最后一发可能 0.36 s 后才离膛 | 已回 `chase` 走起来，枪口还在吐子弹 |

另有两条**同症状的旁路**：枪精灵（`wander`）在 `_tick_egt_state()` 里每帧把移动写进 `_external_velocity`（前摇里照写 ⇒ 举着枪继续飘）；枪歌者中断逃跑同理。

---

## 二、改法

### 2.1 一个常量、一个函数、一个判据

```
ATTACK_STANCE_BRAKE_MPS2 = 55          # a = v²/(2s)：s=0.125 m（≈ 四分之一身位）、v=3.7 ⇒ 54.8
_tick_attack_stance(delta):
    外推有效 → velocity = _external_velocity      # 外力照常生效
    否则     → _brake_planar(delta × 55)          # 自己站住
_is_attack_stance() → ai_state in ["telegraph","attack"]
```

- 3.7 m/s（`melee_chaser`）0.067 s / 0.125 m 停住；4.86 m/s（`egt_blobulin`）0.088 s / 0.216 m。
- `telegraph` 分支不再分复刻怪/老怪两条路，`_tick_egt_windup()` 与 `EGT_WINDUP_SPEED_RATIO` 一并删除（全仓已无引用）。
- `attack` 帧本来就不提交位移（只调 `_perform_attack`），保持不变。

### 2.2 外力不被吞

前摇里挨近战击退/牵引时，`_tick_attack_stance()` **赋值**而非叠加 —— 叠加是这仓反复踩过的
稳态放大器（恒定外推每帧加一次，实测 5.0 m/s 一帧变 9.7）。改造前复刻怪前摇把外力乘 0.35，
实测击退 5.0 只跑出 3.3；现在原值 5.0。

### 2.3 自主动位移在攻击姿态里不写

- 枪精灵游荡、逃跑型、枪歌者中断：写 `_external_velocity` 前先问 `_is_attack_stance()`。
- 进 `telegraph` 时清掉已有的自主动指令（`_external_timer` 是 0.12 s 的刷新式计时，
  不清的话前摇头 0.12 s 会把上一帧的游荡指令当成外力照用）。
- **例外**：链枪手 `orbit` 的"边转链边压上来"是招式本身（2 秒持续攻击），不拦，已在设计页写明。

### 2.4 连发没打完不退出收招

`recovery` 退出条件从 `_state_time >= _recovery_duration()` 改为
`_state_time >= _recovery_duration() and _pending_volleys.is_empty()`。

冷却在**出手帧**就起算，所以攻击频率不变；变的只是"收招期间不走"。蓝霰弹两段最极端
（主段 5 发 + 追随段 4 发 ⇒ 收招顺延到约 1.0 s），老兵小子 4 连发顺延到约 0.36 s。

---

## 三、验证

新增 `tests/verification/verify_enemy_attack_stance.{gd,tscn}`（已登记 `core`）。
判据取 `velocity` 而不是位置差：位置差在本仓夹具里已被证明不可靠
（体块 `scale` 会把 `move_and_slide` 实际位移放大数倍，见 `verify_enemy_action_recovery` 的 raw_peak NOTE）。

| 段 | 钉住的事实 | 旧实现结果 |
|---|---|---|
| A | 满速进前摇后 `v/a` 帧内刹到 ≤0.05 m/s，且刹停后不再起速；到点出手 | **红 6 项**（老怪 9~11 帧 vs 预算 5 帧；复刻怪始终不归零） |
| B | 追击仍逼近；进射程仍出手（"不要改到打不到人"） | 绿（未削弱） |
| C | 前摇里击退 5.0 m/s 原样生效 | **红 2 项**（3.32 / 3.34） |
| D | 排期连发没打完不退出收招 | **红 2 项**（0.13 s 就走、剩 1 发在空中） |
| E | 枪精灵进前摇后不再游荡 | **红 1 项**（刹停后仍 5.97 m/s） |

| 命令 | 环境 | 结果 |
|---|---|---|
| `godot --headless --scene verify_enemy_attack_stance.tscn` | 真实 `_physics_process`，无存档 | 退出 0，`ENEMY_ATTACK_STANCE_OK checks=35 notes=0` |
| 同上，`git stash` 掉本轮 `Enemy3D.gd` 后重跑（反向验证） | 同上 | 退出 1，上表 11 条红 —— 判据确实咬住旧行为，不是自证 |
| `verify_enemy_action_recovery` | 同上 | 退出 0，`checks=3278 notes=8`（收招时长表逐只未变） |
| `verify_3d_enemy_behavior_flow` | 同上 | 退出 0，0 条 ERROR |
| `verify_enemy_light_motion_regression` | 同上 | 退出 0，0 条 ERROR |
| `check_verification_registry.py` | — | 退出 0，`scenes=288` |
| `check_level_decoupling.py` | — | 退出 0，7 个通用容器零违规 |
| `check_documentation_contracts.py` | — | 15 条既有断链 + `openpyxl` 缺失（环境既有），本轮新增文档无新断链 |

预期故障：无（本用例不注入故障）。
非预期脚本错误：无。
未执行项：真实渲染画面复核（本轮为逻辑与状态机判据，未做像素级"看起来是否舒服"的取证）；
`full` 套件未整跑。

---

## 四、既有红项（与本轮无关，改前改后逐字一致）

| 项 | 证据 |
|---|---|
| `verify_monster_ai_system_complete` 退出 1：`Attack token budget is not exactly 2 melee + 2 ranged: 1/0`、`Released melee token was not reusable` | 用 `git stash` 掉本轮改动后重跑，**同样两条、同样数值** ⇒ 存量问题，属该用例自身的令牌预算夹具 |
| `check_documentation_contracts.py` 的 15 条断链 | 全部落在 2026-10 及更早的记录里，改前改后一致 |
| `check_media_asset_domains.py` 的 `ModuleNotFoundError: openpyxl` | 本机解释器缺包 |

---

## 五、口径备忘

1. **"停下来"不等于"刹不住"**：刹车预算按 `v/a` 帧数判，不按米数判 —— 米数会被体块缩放污染。
2. **不许为了绿放宽阈值**：A 段预算由 55 m/s² 直接推出，改这个常量必须同步改设计页公式。
3. **`_recovery_duration()` 没有变**：连发顺延挂在状态机退出条件上，不动时长函数 ——
   那个函数同时是表现层动画相位的分母，动了会让收招姿势抖动。
4. 链枪手 `orbit`、抓握大师 `dive`、自爆族 `leap`、近战突进（`melee_chaser` 7.2 / `ambusher` 9.4 m/s）
   都是**招式本身的位移**，不在本轮"自主行走"范围内，一律保留。
