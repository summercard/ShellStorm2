# -*- coding: utf-8 -*-
# 事务 1442：右摇杆瞄准辅助 + 响应曲线 —— 文档与记忆落位（CRLF 保真）
# 约定：读 bytes -> 解 CRLF 成 LF 做替换 -> 写回时统一 \r\n
import pathlib, re, sys

ROOT = pathlib.Path("I:/工作项目/shellstrom2/ShellStorm2")
MEM = pathlib.Path("I:/工作项目/shellstrom2/.workbuddy/memory")

def load(p):
    return p.read_bytes().decode("utf-8").replace("\r\n", "\n")

def save(p, text):
    p.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))

def sub1(text, anchor, repl, label):
    n = text.count(anchor)
    if n != 1:
        raise SystemExit("ANCHOR-FAIL %s count=%d" % (label, n))
    return text.replace(anchor, repl)

report = []

# ---------- 1) CHANGELOG 顶部新增条目 ----------
CL = ROOT / "docs/v0.1/development/CHANGELOG.md"
t = load(CL)

NEW_ENTRY = """## 2026-09-22｜右摇杆瞄准手感重做：瞄准辅助 + 响应曲线（业主选「2+1」）

**动机（业主指定）**：承接同日「左摇杆同控朝向改默认关」条目，业主确认「好，2+1调整一版」⇒ 采用候选方案 **2（瞄准辅助/磁吸）为主、1（响应曲线 + 幅度权威）为辅**。

**问题根因（复述同日勘察）**：`gamepad_aim_deadzone=0.20` 吃掉 20% 行程、`gamepad_aim_smoothing=0.35`（≈60ms 滞后）、`_update_aim()` **只取摇杆方向角、丢弃幅度**（无响应曲线）⇒ 死区边缘轻推也产生大角度偏转、且无法「轻推精瞄 / 重推快转」；摇杆边缘角度分辨率物理上限约 **1mm≈3~4°**；`aim_direction` 三用 ⇒ 瞄准精度 = 命中精度。

**改动 ①｜响应曲线 + 幅度权威**（`src/core/GamepadInput.gd`）：
- 新增纯函数 `resolve_aim_speed_scale(magnitude_after_deadzone)`：`shaped = clampf(t,0,1)^AIM_RESPONSE_EXPONENT(1.60)`，返回 `AIM_PRECISION_SPEED_SCALE(0.35) + (AIM_FLICK_SPEED_SCALE(1.60) − 0.35) × shaped`（`t=0` 刚出死区→精瞄端、`t=1` 推到底→甩枪端）。
- `_update_aim()` 的平滑率改为 `AIM_SMOOTHING_BASE_RATE × (1 − smoothing) × speed_scale`：**轻推慢转（精瞄）、重推快转（甩枪）**，把此前被丢弃的摇杆幅度重新纳入。
- 默认值再平衡（`InputSettingsManager.DEFAULT_SETTINGS`）：`gamepad_aim_deadzone 0.20 → 0.12`、`gamepad_aim_smoothing 0.35 → 0.15`（对应 `rate = 30 × 0.85 = 25.5`，滞后从 ≈60ms 降到 ≈40ms）。

**改动 ②｜瞄准辅助（磁吸，顶视角射击事实标准）**（新文件 `src/player3d/AimAssist3D.gd`，`class_name AimAssist3D`，`extends RefCounted` 纯静态）：
- `is_eligible(alive, illumination_state, distance, angle_deg, ...)`：**只吸附「存活 + 已照亮（非 `STATE_DARKNESS`）+ 射程内 + 锥内」**的敌人。硬约束：**绝不吸附黑暗中的敌人**（本项目敌人只在光照下可见，吸黑暗 = 透视挂）；已死、超射程（默认 26m）、锥外（默认 30° 扫描锥）一律不吸。
- `solve(aim_dir, candidates, options)`：取锥内**权重最大**的候选，`delta = clampf(angle_to, ±max_angle(默认 8°) × strength × weight)` —— **偏转有硬上限（不抢控制）**；无候选 / 强度 0 / 候选为空时原样返回，绝非「无脑吸附」。
- 权重 `_weight(...)` = `angle_factor² × distance_factor`（角度项取平方 ⇒ 偏好贴近瞄准轴的近敌）。
- `Player3D._collect_aim_assist_candidates()` 从 `enemy_3d` 分组收集候选（读 `current_hp` 与 `get_illumination_state()`），在 `_update_aim_from_mouse()` 的**移动端/手柄共用分支**对 `aim_dir_3d` 施加 `AimAssist3D.solve(...)` 后再赋给 `aim_direction`。

**开关与 UI**：新增 `InputSettings` 键 `gamepad_aim_assist`（**默认 `true`**）+ `is_aim_assist_enabled()`；ESC 暂停菜单「操作设置」页新增「瞄准辅助」`CheckButton`（节点 `Center/Panel/Margin/ControlsPage/AimAssist`）+ `PauseMenu3D._on_aim_assist_toggled()` 与同步（`L3B_IND` 类状态标签）。

**验收**（`verify_gamepad_input_flow`）：
- `_verify_aim_response_curve()`：精瞄端/甩枪端端点值、单调不减、中段必须「够慢」（低于线性中线）、越界与负值钳位。
- `_verify_aim_assist_solver()`：资格 5 条规则 + `solve` 空操作（无候选/强度 0/空数组）+ 锥外不吸 + 锥内偏转**有硬上限且非满偏** + 权重优先 + 距离衰减。
- `_verify_aim_assist_candidate_collection()`：**端到端**（真实 `Player3D` + `Enemy3D` 竞技场）A) 黑暗敌人 → 空候选；B) 太阳照亮 → 恰 1 候选、方向与距离(8.0m)正确；C) 关开关 → 空；D) 敌人在背后 → 空；E) 超射程(z=−40) → 空；F) 已死 → 空。
- **坑（新）**：`DirectionalLight3D` 默认朝 **−Z**，水平摆放时阳光射线从敌人射向太阳会被原点处的玩家挡住 ⇒ `sun_exposure_ratio` 恒 `0.0`、敌人一直停留黑暗态；**必须把太阳转成 `rotation_degrees=(−90,0,0)` 顶照**，才能造出「已照亮」样本。
- **反向对照 4 组**（`_scratch/gamepad_submenu/negctl_assist.py`）：`curve`（曲线失效）⇒ 5 红、`dark`（放行黑暗敌人）⇒ 1 红（「黑暗中的敌人进入了瞄准辅助候选」）、`cap`（去偏转上限）⇒ 2 红、`glue`（撤 `Player3D` 接线）⇒ 1 红；各自精准命中后还原复绿。
- 复绿：`GAMEPAD_INPUT_FLOW_OK`（`exit=0`）含新 OK 串「magnitude-authoritative aim response curve (slow precision / fast flick), aim assist pulls only lit living enemies within a hard deflection cap」。

**回归**：`verify_graphics_settings_ui_flow` / `verify_pause_game_save_reset_flow` / `verify_enemy_illumination_states` 三场景 `exit=0` + `*_OK`。**基线对照**：`verify_3d_enemy_behavior_flow` 报 7 条「Enemy damage does not create a 3D floating number」——把本次 5 个改动文件临时换成 `HEAD` 版重跑，**7 条错误逐字相同** ⇒ **既存红、非本次引入**（已记入已知基线红，非本特性回归）。

**未变更**：`aim_direction` 三用语义、`MobileInput` 触屏口径、键鼠路径、三档朝向机制与 `gamepad_left_stick_aim` 默认关、武器/弹药/伤害链路、账本。"""

anchor1 = "# 游戏设计文档 v0.1 变更记录\n\n## 2026-09-22｜「左摇杆同控朝向」改为默认关闭（保留能力）"
repl1 = "# 游戏设计文档 v0.1 变更记录\n\n" + NEW_ENTRY + "\n\n<br>\n## 2026-09-22｜「左摇杆同控朝向」改为默认关闭（保留能力）"
t = sub1(t, anchor1, repl1, "CHANGELOG-top")

anchor2 = "**未决（业主指定下一步）**：右摇杆瞄准手感（\"转向不够精确、无法瞄准\"）**尚未定方案**，待业主从候选方案中选择后再施工。已勘察的现状："
repl2 = "**后续（同日已施工）**：右摇杆瞄准手感（\"转向不够精确、无法瞄准\"）**已按业主选定方案落地**（瞄准辅助 + 响应曲线，见本文顶部「右摇杆瞄准手感重做」条目）。施工前勘察的现状："
t = sub1(t, anchor2, repl2, "CHANGELOG-unresolved")
save(CL, t)
report.append("CHANGELOG.md ok")

# ---------- 2) 03_技术施工_玩家与操作.md ----------
DOC = ROOT / "docs/v0.1/03_技术施工_玩家与操作.md"
t = load(DOC)

a3 = "| 瞄准/面朝向 | 鼠标 / 右摇杆（优先）/ 左摇杆（可选） | `aim(Vector2/Vector3)` | `dead` |"
r3 = "| 瞄准/面朝向 | 鼠标 / 右摇杆（优先）/ 左摇杆（可选） | `aim(Vector2/Vector3)`（可叠加瞄准辅助磁吸） | `dead` |"
t = sub1(t, a3, r3, "DOC-table-row")

pat = re.compile(r'<span style="color:#EF6C00">\*\*\[待定｜2026-09-22\] 右摇杆瞄准手感\*\*.*?</span>', re.DOTALL)
if len(pat.findall(t)) != 1:
    raise SystemExit("DOC-SPAN-FAIL")
NEW_SPAN = ('<span style="color:#2E7D32">**[已实装｜2026-09-22] 右摇杆瞄准手感：瞄准辅助 + 响应曲线（业主选「2+1」）。** '
            '承接同日「左摇杆同控朝向默认关」：业主确认采用**方案 2（瞄准辅助/磁吸）为主、方案 1（响应曲线 + 幅度权威）为辅**。'
            '**① 响应曲线 + 幅度权威**（`GamepadInput.resolve_aim_speed_scale`，纯函数）：`clampf(t,0,1)^1.60` 在 `0.35`（精瞄端）~`1.60`（甩枪端）之间插值，平滑率改为 `AIM_SMOOTHING_BASE_RATE × (1 − smoothing) × speed_scale` ⇒ '
            '**轻推慢转（精瞄）、重推快转（甩枪）**，把此前被 `_update_aim()` 丢弃的摇杆幅度重新纳入；默认值再平衡 `gamepad_aim_deadzone 0.20 → 0.12`、`gamepad_aim_smoothing 0.35 → 0.15`。'
            '**② 瞄准辅助（磁吸）**（新文件 `src/player3d/AimAssist3D.gd`，`class_name AimAssist3D`、`RefCounted` 纯静态）：`is_eligible` **只吸附「存活 + 已照亮（非 `STATE_DARKNESS`）+ 射程内 + 锥内」**的敌人（**绝不吸黑暗敌人**——本项目敌人只在光照下可见，吸黑暗 = 透视挂）；'
            '`solve` 偏转量 `clampf(±max_angle(默认 8°) × strength × weight)` **有硬上限、绝不抢走控制**，无候选/强度 0 时原样返回；权重 `angle_factor² × distance_factor`（偏好贴近瞄准轴的近敌）。'
            '`Player3D._collect_aim_assist_candidates()` 从 `enemy_3d` 分组收集候选，在**移动端/手柄共用分支**对 `aim_dir_3d` 施加后赋给 `aim_direction`。'
            '**开关**：`InputSettings` 键 `gamepad_aim_assist`（**默认 `true`**）+ `is_aim_assist_enabled()`，ESC「操作设置」页「瞄准辅助」`CheckButton`（节点 `Center/Panel/Margin/ControlsPage/AimAssist`）可关。'
            '验收见 `verify_gamepad_input_flow`（响应曲线 + 纯函数求解器 + 端到端候选收集 A–F），反向对照 4 组（曲线/放行黑暗/去上限/撤接线）各自精准命中后还原。</span>')
t = pat.sub(lambda m: NEW_SPAN, t)
save(DOC, t)
report.append("03_技术施工_玩家与操作.md ok")

# ---------- 3) MEMORY.md ----------
M = MEM / "MEMORY.md"
t = load(M)

a_m1 = "- 已知基线红：full_3d_game_flow（ranged_caster/节点预算）、tower_journey_polish（塔楼0层是天台，不是远征抛光砖）、tower_grid_component_alignment（走廊/tile计数）。新红必须基线对照。"
r_m1 = "- 已知基线红：full_3d_game_flow（ranged_caster/节点预算）、tower_journey_polish（塔楼0层是天台，不是远征抛光砖）、tower_grid_component_alignment（走廊/tile计数）、3d_enemy_behavior_flow（7 条「Enemy damage does not create a 3D floating number」，HEAD 基线对照逐字同红）。新红必须基线对照。"
t = sub1(t, a_m1, r_m1, "MEMORY-known-red")

a_m2 = "- **右摇杆瞄准手感待定（业主：转向不够精确、无法瞄准）**：`gamepad_aim_deadzone=0.20`、`gamepad_aim_smoothing=0.35`，且 `_update_aim()` 只取方向角、丢幅度（无响应曲线）。候选方案见 1425 事务；动瞄准即动弹道（`aim_direction` 三用）。"
r_m2 = "- **右摇杆瞄准手感（已实装「2+1」）**：响应曲线+幅度权威（`GamepadInput.resolve_aim_speed_scale`：`clamp(t)^1.60` 在 0.35 精瞄~1.60 甩枪间插值，轻推慢转/重推快转）+ 瞄准辅助磁吸（`AimAssist3D`，**只吸存活+已照亮+锥内+射程内**敌人、偏转硬上限 8° 不抢控制）；默认 `aim_deadzone=0.12`、`aim_smoothing=0.15`、`gamepad_aim_assist=true`（操作设置页可关）。动瞄准即动弹道（`aim_direction` 三用）。"
t = sub1(t, a_m2, r_m2, "MEMORY-aim-note")
save(M, t)
report.append("MEMORY.md ok")

# ---------- 4) 事务文件 ----------
TX = MEM / "2026-09-22/1442_右摇杆瞄准辅助与响应曲线.md"
TX_CONTENT = """# 右摇杆瞄准辅助 + 响应曲线（业主选「2+1」）

> 事务时间：2026-09-22 14:42 · 类型：**功能落地（新系统 + 代码 + UI + 验收 + 反向对照）** · 状态：**已验收，未提交**

## 业主原话

> 「好，2+1调整一版」（承接上一条：「原来的那个，转向不够精确，无法瞄准，参考一些顶视角游戏的右摇杆操作」）

即采用候选 **方案 2（瞄准辅助/磁吸）为主、方案 1（响应曲线 + 幅度权威）为辅**。

## 一、响应曲线 + 幅度权威（改动最小，先治"轻推也猛转"）

`src/core/GamepadInput.gd`：

- 新常量：`AIM_PRECISION_SPEED_SCALE := 0.35`、`AIM_FLICK_SPEED_SCALE := 1.60`、`AIM_RESPONSE_EXPONENT := 1.60`。
- 新纯函数 `resolve_aim_speed_scale(magnitude_after_deadzone)`：`shaped = pow(clampf(t,0,1), 1.60)`；`return 0.35 + (1.60 − 0.35) × shaped`。
- `_update_aim()` 的 `rate` 从 `AIM_SMOOTHING_BASE_RATE × (1 − smoothing)` 改为再乘 `speed_scale`：**死区边缘轻推 ⇒ 慢速精调；推到底 ⇒ 1.6× 快速甩枪**。这把此前被整段丢弃的「摇杆幅度」信息重新变成控制力。

`src/core/InputSettingsManager.gd` 默认值再平衡：

| 键 | 旧 | 新 |
|---|---|---|
| `gamepad_aim_deadzone` | 0.20 | **0.12** |
| `gamepad_aim_smoothing` | 0.35 | **0.15** |

（`rate = 30 × (1−0.15) = 25.5` ⇒ 时间常数从 ≈3.6 帧≈60ms 降到 ≈2.5 帧≈40ms；`get_aim_deadzone()/get_aim_smoothing()` 回落值同步。）

## 二、瞄准辅助（新系统，治"打不准"）

新文件 `src/player3d/AimAssist3D.gd`（`class_name AimAssist3D`、`extends RefCounted`、纯静态函数，**不持有任何状态**）：

- 常量：`DEFAULT_CONE_DEG=20`（吸附锥）、`DEFAULT_MAX_ANGLE_DEG=8`（单帧最大偏转）、`DEFAULT_NEAR_RANGE=4`、`DEFAULT_FAR_RANGE=26`、`DEFAULT_STRENGTH=1.0`、`DEFAULT_SCAN_RANGE=26`、`DEFAULT_SCAN_CONE_DEG=30`。
- `is_eligible(alive, illumination_state, distance, angle_deg, scan_range, scan_cone_deg)`：**四条硬规则** —— ① 必须存活；② **`illumination_state != STATE_DARKNESS`**；③ `0 < distance ≤ scan_range`；④ `angle_deg ≤ scan_cone_deg`。
- `solve(aim_dir, candidates, options)`：把 `aim_dir` 投到水平面求 `flat_aim`；无候选/`strength≤0` ⇒ 原样返回；否则遍历取 `_weight` 最大者，算目标方位角与 `flat_aim` 的夹角 `angle_to`，`delta = clampf(angle_to, −limit, +limit)`（`limit = deg_to_rad(8°) × strength × best_weight`），把 `flat_aim` 旋转 `delta` 后回填。**偏转带硬上限 ⇒ 不会把准星从玩家手里抢走**。
- `_weight(angle, cone_rad, distance, near_range, far_range)`：`angle_factor² × distance_factor`（角度项平方 ⇒ 强偏好贴近瞄准轴的近敌；越远权重线性衰减）。

`src/player3d/Player3D.gd`：

- 新增 `const ENEMY_GROUP := "enemy_3d"`（旧的扫描范围/锥常量下沉进 `AimAssist3D`）。
- 新增 `_collect_aim_assist_candidates(aim_dir) -> Array[Dictionary]`：`is_aim_assist_enabled()` 为假 ⇒ 返回空；否则遍历 `get_tree().get_nodes_in_group(ENEMY_GROUP)`，对每个 `Enemy3D` 算 `to_enemy/distance/direction/angle_deg`，调 `AimAssist3D.is_eligible(enemy.current_hp > 0, enemy.get_illumination_state(), distance, angle_deg)`，通过则 append `{KEY_DIRECTION, KEY_DISTANCE}`。
- `_update_aim_from_mouse()` 的移动端/手柄分支里，在赋 `aim_direction` 之前插入 `aim_dir_3d = AimAssist3D.solve(aim_dir_3d, _collect_aim_assist_candidates(aim_dir_3d))`。

### 为什么「只吸已照亮」是硬约束（不是可调项）

本项目敌人**只在光照下可见**（`EnemyIllumination3D` 三态）。若允许吸附黑暗敌人，玩家会获得「看不到却准星自己吸上去」的能力 = **透视挂**，直接破坏本作「用手电/环境光揭示敌人」的核心玩法与伏击怪设计。故写死。

## 三、开关与 UI

- `InputSettings` 新键 `gamepad_aim_assist`（**默认 `true`**）+ `is_aim_assist_enabled()`。
- `ui_pause_overlay_screen.tscn` 在「瞄准平滑」行与「左摇杆同控朝向」之间插入 `AimAssist` `CheckButton`，文案「瞄准辅助\\n摇杆瞄准时，准星被视野内已照亮的敌人轻微吸引（偏转有上限，不会抢走控制）」。两个滑条默认值同步 0.12 / 0.15。
- `PauseMenu3D`：`_setup_input_controls` 接 `_on_aim_assist_toggled`，`_sync_input_controls` 回填 `button_pressed`。

## 四、验收与反向对照

`tests/verification/verify_gamepad_input_flow.gd` 新增三块：

1. `_verify_aim_response_curve`：`resolve_aim_speed_scale` 端点（0→0.35、1→1.60）、单调不减、中点必须「够慢」（低于线性插值中线）、越界>1 与负值钳位。
2. `_verify_aim_assist_solver`：资格 5 条规则（存活/照亮/距离/角度/边界）、`solve` 三种空操作、锥外不吸、**锥内偏转有上限且非满偏**（偏转 < 目标夹角，证明是"吸"不是"锁"）、权重优先、距离衰减。
3. `_verify_aim_assist_candidate_collection`（**端到端**，真 `Player3D` + `Enemy3D` 竞技场）：A 黑暗→空 / B 太阳照亮→恰 1 且方向、距离 8.0m 正确 / C 关开关→空 / D 背后→空 / E 超射程 z=−40→空 / F 已死→空。

**反向对照 4 组**（`_scratch/gamepad_submenu/negctl_assist.py`）：

| 组 | 注入 | 命中红数 |
|---|---|---|
| `curve` | 曲线退化为常数 | 5 红 |
| `dark` | `is_eligible` 放行 `STATE_DARKNESS` | 1 红（「黑暗中的敌人进入了瞄准辅助候选」） |
| `cap` | 去掉 `delta` 的 clamp | 2 红 |
| `glue` | 撤掉 `Player3D` 的 `AimAssist3D.solve` 接线 | 1 红 |

各自精准命中后还原，`GAMEPAD_INPUT_FLOW_OK`（`exit=0`）复绿。

## 五、其它

- **回归**：graphics / pause / enemy_illumination 三场景 `exit=0` + `*_OK`。
- **基线对照（重要）**：`verify_3d_enemy_behavior_flow` 报 **7 条**「Enemy damage does not create a 3D floating number」（7 类普通怪各一）。为归因，把本次 5 个改动文件（GamepadInput / InputSettingsManager / Player3D / PauseMenu3D / ui_pause_overlay_screen.tscn）临时换成 `git show HEAD:` 版本重跑 ⇒ **7 条错误逐字相同** ⇒ **既存红、与本特性无关**（已记进 `MEMORY.md` 已知基线红）。换回后 `GAMEPAD_INPUT_FLOW_OK` 复绿。
- **新 class_name 导入**：`AimAssist3D` 新建后须跑一次 `--headless --path . --import` 刷 `.godot/global_script_class_cache.cfg`（实测 `grep -c AimAssist3D` = 2，无 SCRIPT/Parse 错误）。

## 坑

- **端点用例的光照陷阱**：`DirectionalLight3D` 的默认朝向是 **−Z**。把太阳水平摆在敌人与玩家之间时，从敌人朝太阳打射线会**被原点处的玩家挡住** ⇒ `sun_exposure_ratio` 恒 `0.0`、敌人一直停黑暗态，用例 B 永远拿不到样本。修法：`sun.rotation_degrees = Vector3(−90, 0, 0)`（顶照）。
- **候选用例设计**：第一版把目标放在 `straight` 的 90° 外侧（锥外）却期望被吸附 ⇒ 假红。改为 `Vector3(sin(10°),0,−cos(10°))`（锥内 10°）并加「偏转必须 < 目标夹角」的断言，才同时证明"吸得到"与"有上限"。
- **类型推断禁令**：`candidate.get(KEY_DIRECTION)` 返回 Variant ⇒ 必须 `var raw_direction: Variant = ...` 显式标注，否则本项目把「类型由 Variant 推断」当硬 Parse Error。

## 未提交

`src/player3d/AimAssist3D.gd`（新增）、`src/core/GamepadInput.gd`、`src/core/InputSettingsManager.gd`、`src/player3d/Player3D.gd`、`src/ui/PauseMenu3D.gd`、`assets/art/ui/pause_3d/ui_pause_overlay_screen.tscn`、`tests/verification/verify_gamepad_input_flow.gd` + 2 文档（CHANGELOG / 03），**均未 commit**。
"""
TX.parent.mkdir(parents=True, exist_ok=True)
save(TX, TX_CONTENT)
report.append("transaction file ok")

# ---------- 5) _INDEX.md 插入行 ----------
IDX = MEM / "2026-09-22/_INDEX.md"
t = load(IDX)
a_idx = "| 14:39 | [远征关卡01 掉落表与产出物设计核查](1439_远征关卡01掉落表与产出物设计核查.md)"
SUMMARY = ("业主选定「2+1」⇒ 实装右摇杆瞄准手感重做。**① 响应曲线+幅度权威**（`GamepadInput.resolve_aim_speed_scale`：`clampf(t,0,1)^1.60` 在 `0.35`(精瞄)~`1.60`(甩枪) 间插值，平滑率 `× speed_scale` ⇒ 轻推慢转/重推快转，把被丢弃的摇杆幅度重新纳入）；默认再平衡 `gamepad_aim_deadzone 0.20→0.12`、`gamepad_aim_smoothing 0.35→0.15`。"
           "**② 瞄准辅助磁吸**（新 `src/player3d/AimAssist3D.gd`，`class_name`/RefCounted 纯静态）：`is_eligible` **只吸存活 + 已照亮(非 STATE_DARKNESS) + 射程内 + 锥内**（硬约束：绝不吸黑暗敌人＝防透视挂）、`solve` 偏转 `clampf(±max 8°×strength×weight)` **有硬上限不抢控制**、`weight=angle_factor²×distance_factor`；`Player3D._collect_aim_assist_candidates()` 从 `enemy_3d` 组收集、在移动端/手柄共用分支对 `aim_dir_3d` 施加后赋 `aim_direction`。"
           "**开关**：`InputSettings.gamepad_aim_assist` 默认 true + `is_aim_assist_enabled()`，ESC 操作设置页新增「瞄准辅助」CheckButton + `PauseMenu3D._on_aim_assist_toggled()`。"
           "**验收**：`verify_gamepad_input_flow` 增 `_verify_aim_response_curve`（端点/单调/中点够慢/钳位）、`_verify_aim_assist_solver`（资格 5 规则+solve 空操作+锥外不吸+锥内偏转有上限且非满偏+权重优先+距离衰减）、`_verify_aim_assist_candidate_collection`（端到端真实 Player3D+Enemy3D 竞技场 A–F：黑暗→空 / 照亮→恰 1 且方向距离 8.0m 正确 / 关开关→空 / 背后→空 / 超射程 40m→空 / 已死→空）。"
           "**坑**：`DirectionalLight3D` 默认朝 −Z，水平摆太阳被玩家挡住 ⇒ `sun_exposure_ratio` 恒 0、敌人恒黑暗，须 `rotation_degrees=(-90,0,0)` 顶照才有「已照亮」样本；锥外目标用例首版设计错致假红，改正并加「偏转<目标夹角」断言。"
           "**反向对照 4 组**（`negctl_assist.py`）：`curve`⇒5 红、`dark`⇒1 红、`cap`⇒2 红、`glue`(Player3D 接线)⇒1 红，各自命中后还原。复绿 `GAMEPAD_INPUT_FLOW_OK` exit=0；回归 graphics/pause/enemy_illumination 三场景 exit=0。"
           "**基线对照**：`verify_3d_enemy_behavior_flow` 7 条 floating-number 红 —— 5 文件换 HEAD 版重跑**逐字同红** ⇒ 既存红、非本次引入（已入已知基线红）。**未提交**。")
row = "| 14:42 | [右摇杆瞄准辅助 + 响应曲线（业主选「2+1」）](1442_右摇杆瞄准辅助与响应曲线.md) | **功能落地（新系统 + 代码 + UI + 验收 + 反向对照）** | " + SUMMARY + " |\n"
t = sub1(t, a_idx, row + a_idx, "INDEX-row")
save(IDX, t)
report.append("_INDEX.md ok")

# ---------- CRLF 复检 ----------
print("\n".join(report))
print("--- CRLF check ---")
for p in [CL, DOC, M, TX, IDX]:
    b = p.read_bytes()
    lf = b.count(b"\n"); crlf = b.count(b"\r\n"); crcrlf = b.count(b"\r\r\n")
    ok = (lf - crlf) == 0 and crcrlf == 0
    print(("OK " if ok else "BAD") + " crlf=%d lone_lf=%d crcrlf=%d  %s" % (crlf, lf - crlf, crcrlf, p.name))
