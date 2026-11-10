# 2026-11-10 全局节奏系数 PACE_SCALE = 0.85

> 业主原话：「我想让整体节奏变慢一点」。
> 明确选了 **C 全链路同比缩放** + **中等档（×0.85）**，而不是"只降玩家移速"。

## 0. 先回答业主问的那两个数

**翻滚（冲刺）的速度上限 = 16.5 m/s，而且全链路没有任何地方钳制它。**
`Player3DDashingState.physics_update` 直接把 `dash_direction × get_dash_speed()` 交给
`move_grounded`，后者只写 y 轴（重力 / 贴地），**不对 xz 做任何 clamp**。
所以 16.5 是真实速度，不是名义值。

真正限制翻滚的是三件事，都不是"速度"：

| 约束 | 值 | 来源 |
|---|---:|---|
| 时长 | 0.204 s | `DASH_DURATION` |
| 冷却 | 2.2 s（有效空窗 1.996 s） | `DASH_COOLDOWN`，起手帧起算 |
| 状态 | 只允许 `idle` / `moving` 起手 | `_begin_dash` |

另有两条旁路限制：`_electric_root_remaining > 0` 时 `_begin_dash` 直接返回 false 且速度清零
（电击禁锢）；`input_locked` 时冲刺状态立刻转 `locked`。

**一个实现与命名的错位（本轮没改，只记录）**：命运卡 `dash_distance_multiplier` 叫"距离"，
实际乘在**速度**上（`get_dash_speed`），时长不变 ⇒ 效果是瞬时更快、不是滚得更久。
那张"距离 +40%"卡：3.366 → 4.71 m。改名字会动到存档里的命运卡字段，不在本轮范围。

## 1. 为什么是"整体缩放"而不是"只降玩家"

只降玩家移速，敌人相对变快 ⇒ 玩家体感是**更紧、更难**，不是更慢。
2026-11-09 那次单点提速（`SPEED 4.5 → 5.7`）就是反例：它留下了两条静默漂移 ——
冲刺相对倍率 `3.67× → 2.90×`、敌弹从 `1.11×` 玩家步速掉到 `0.88×`。
本轮改为**单一系数 + 四处引用**，这类漂移不会再出现。

## 2. 落地：一个常量，四处乘

`src/framework/GameDesignConfig.gd`

```gdscript
const PACE_SCALE := 0.85
```

| # | 引用点 | 改前 | 改后 | 表达式 |
|---|---|---:|---:|---|
| 1 | `Player3D.SPEED` | 5.7 | **4.845** | `5.7 * GameDesignConfig.PACE_SCALE` |
| 2 | `Player3D.DASH_SPEED` | 16.5 | **14.025** | `16.5 * GameDesignConfig.PACE_SCALE` |
| 3 | `Enemy3D.GLOBAL_MOVE_SPEED_MULTIPLIER` | 0.70 | **0.595** | `0.70 * GameDesignConfig.PACE_SCALE` |
| 4 | 敌弹出生速度 | 5.0 / 6.5 / 3.5 | **4.25 / 5.525 / 2.975** | `profile.speed * GameDesignConfig.PACE_SCALE`（`_fire_projectile` 出生点一处） |
| 5 | `CharacterMotionLibrary3D.ANIMATION_RATE_MULTIPLIER` | 1.25 | **1.0625** | `1.25 * GameDesignConfig.PACE_SCALE` |
| 6 | `CharacterMotionLibrary3D.RUN_CLIP_RATE_SCALE` | 1.3 | **1.105** | `1.3 * GameDesignConfig.PACE_SCALE` |

敌弹为什么在**出生点**乘一次、而不是去改 `PROFILES` 里 30+ 处 `projectile_speed` 字面量：
逐条改必然漏，而且会把"5.0 基准 / 6.5 fast / 3.5 慢弹"这套**档位**概念打碎成一地魔数。
出生点乘一次 ⇒ 所有档位同比缩放、档间比例不变。

## 3. 落地实测值（探针读数，不是推算）

```
PACE_SCALE = 0.8500
SPEED           = 4.8450        持枪: sidearm 4.345 / longgun 4.045 / machinegun 3.745
DASH_SPEED      = 14.0250       DASH_DURATION 0.2040（未缩放）  DASH_COOLDOWN 2.2000（未缩放）
冲刺位移        = 2.8611 m      冲刺/常速倍率 = 2.8947 ×
ANIMATION_RATE  = 1.0625        RUN_CLIP 1.1050   跑动合计 1.1741
GLOBAL_MOVE_MULT = 0.5950
  melee_chaser    3.7000 ⇒ 2.2015 m/s
  ranged_caster   2.2500 ⇒ 1.3387 m/s
  ambusher        4.6500 ⇒ 2.7668 m/s
  egt_veteran_kin 3.7140 ⇒ 2.2098 m/s
敌弹 5.0 档 ⇒ 4.2500；相对玩家常速 4.2500 / 4.845 = 0.877 ×（未缩放前 5.0/5.7 = 0.877）
```

**关键点：冲刺/常速倍率 2.895× 与敌弹相对速度 0.877× 在缩放前后完全一致** —— 这就是"等比"的判据。

## 4. 刻意不乘的量（乘了就不是等比）

| 项 | 为什么不乘 |
|---|---|
| `DASH_DURATION` / `DASH_COOLDOWN` | 无敌帧与闪避窗口的载体，是"节拍"不是"速度" |
| 敌人 `telegraph` / `recovery` / `cooldown` | 同上：可躲性窗口 |
| 换弹 `reload_time` / 射速 `fire_rate` | DPS 上限与节奏锚，属另一个决策 |
| `WEAPON_FAMILY_MOVE_PENALTY`（0.5 / 0.8 / 1.1） | 它是四档之间的**差值**；乘上去会把 4.845/4.345/4.045/3.745 压成几乎一样快，梯度消失 |
| `Global.HITSTOP_*` 命中停顿 | 打击感的时间锚，跟着缩放会让每一枪变钝 |
| `AIR_CONTROL_ACCEL_MPS2` / `GRAVITY_MPS2` | 空中手感与坠落时间；本轮只动"地面节奏" |

## 5. 为什么不用 `Engine.time_scale`

`src/core/Global.gd` 已经用它做命中停顿（`time_scale = 0.0` 若干帧），再做全局缩放会互相踩；
而且 HUD 计时、遭遇倒计时、BGM、动画采样全吃 `delta`，一起拖慢会连带出一堆非预期行为。
用 `PACE_SCALE` 只动"速度类数值"，`delta` 本身保持真实。

## 6. 同步的断言与工具（防漂移）

| 位置 | 原写法 | 现写法 | 理由 |
|---|---|---|---|
| `verify_player3d_directional_motion.gd:161` | `is_equal_approx(motion.playback_rate, 1.25)` | 与 `CharacterMotionLibrary3D.ANIMATION_RATE_MULTIPLIER` 比较 | 抄死 1.25 的话，下次调 PACE 会报"功能坏了"，实际只是口径变了 |
| `tools/_egt_dodgeability_probe.gd` | `PLAYER_SPEED := 5.7`（手抄） | `Player3D.SPEED` / `Player3D.DASH_DURATION`（引用） | 手抄必然忘记同步，忘了就让"可躲性"结论静默失准 |
| 同上，弹速 | 直接读 profile | `× GameDesignConfig.PACE_SCALE` | 与 `_fire_projectile` 同一口径，否则算的是"原速弹" |
| `verify_3d_enemy_behavior_flow.gd:78` | 已引用 `Enemy3D.GLOBAL_MOVE_SPEED_MULTIPLIER` | 不动 | 本来就是符号式，自动跟随 |
| `verify_fate_character_completion.gd` | 已引用 `Player3D.SPEED` / `DASH_SPEED` | 不动 | 同上 |

## 7. 验收

| 用例 | 结果 |
|---|---|
| `verify_3d_enemy_behavior_flow` | `3D_ENEMY_BEHAVIOR_FLOW_OK` exit 0 |
| `verify_player3d_directional_motion` | `BUNNY_DIRECTIONAL_MOTION_OK checks=1789` exit 0（改断言后） |
| `verify_enemy_attack_stance` | `ENEMY_ATTACK_STANCE_OK checks=35` exit 0 |
| `verify_enemy_action_recovery` | `ENEMY_ACTION_RECOVERY_OK checks=3278` exit 0 |
| `verify_player_hud_combat_feedback` | `PLAYER_HUD_COMBAT_FEEDBACK_OK` exit 0（冷却环吃 `get_dash_cooldown_duration`，未缩放下行为不变） |
| `verify_3d_reload_state_flow` | `3D_RELOAD_STATE_FLOW_OK` exit 0 |
| 常量核对探针（临时，已删） | 见 §3 读数，与公式逐项吻合 |

**未跑 / 既有红项，单列**：

- `verify_fate_character_completion`：`checks=130`，失败项是
  `启动前隔离APPDATA` / `启动前隔离LOCALAPPDATA` / `失败不消耗命运槽`。
  前两条是该用例要求特定 APPDATA 契约（我这台机器上 Git Bash 传不进 Windows Godot），
  第三条是隔离未生效导致命运槽状态不干净。**速度类断言（隐者移速 / 冲刺距离 / 冲刺无敌）
  全部通过**，与本改动相关的部分无红项。
- `verify_dungeon_wave_intermission`：exit 1，失败项是"后续波落点失败仍推进/假清房/丢失队列"。
  该文件对 `speed` 的引用数为 **0**，与本次改动无关（属既有的刷怪落点/清房逻辑）。
- **真机手感未验**：0.85 是业主指定的第一档，跑图感受需他自己确认；如果觉得还不够慢，
  下一个候选是 0.80（`1/0.8 = 1.25` 倍时间）。

## 8. 回滚

改一个数字：`GameDesignConfig.PACE_SCALE = 1.0` 即完全回到本轮之前的状态
（5.7 / 16.5 / 0.70 / 原速弹 / 1.25 / 1.3），**不需要逐处还原**。
这是把它做成单一系数的主要理由之一。
