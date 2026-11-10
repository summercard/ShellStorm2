# 2026-11-10 玩家血条战斗反馈四件（翻滚冷却环 / 受击震动 / 空槽底纹 / 回血补条）

> 业主四条同批，原话见[设计 r6](../design/对话与战斗信息呈现设计.md#玩家血条战斗反馈四件ui-hud-r62026-11-10)。
> 全部落在左上角 `PlayerStatusBlock` 这个簇里，因为四条讲的都是同一件事：
> **血条要能同时表达「我现在多少血」「这一下掉了/回了多少」「我现在能不能翻滚」**。

## 1. 落地清单

| # | 业主原话 | 落地 | 新文件 / 改动点 |
|---|---|---|---|
| ① | 翻滚冷却示意 hud，不用文字，图形或进度条 | `HudDashCooldownRing`（环形扫描 + 环心线框飞镖，冷却天蓝 / 就绪转白） | 新增 `src/ui/HudDashCooldownRing.gd` |
| ② | 受击后血条要有震动，很显眼 | `_tick_player_status_shake`：整个状态块位移 + 冲击放大 + 暖红染色，三层同时 | `src/world3d/Dungeon3D.gd` |
| ③ | 血条底部透明、看不见总量与扣血；加斜杆半透 + 横向位移底纹（灰、暗） | `HudHealthBarTrack`，并收口「空槽真源」（两层 ProgressBar 的 background 改全透明） | 新增 `src/ui/HudHealthBarTrack.gd` |
| ④ | 扣血有动画、加血没有，补一个同风格 | `HudHealthBarHeal`：白段在恢复区间上从旧值推到新值再淡出 | 新增 `src/ui/HudHealthBarHeal.gd` |

叠放次序固定为 **底纹 → 白段 → 红条 → 回血补条 → 读数 Label**。
`verify_player_hud_combat_feedback` 逐条钉住，其中底纹必须是 `get_index() == 0`、
补条必须排在红条之后 —— 次序错了不是"不好看"，是补条被红条整片盖掉。

## 2. 关键数值与推导

### ③ 底纹

```
线宽   = max(1, 条高 × 0.11)          # 条高 20.8 canvas px ⇒ 2.3 px
间距   = max(线宽×2, 条高 × 0.46)      # ≈ 9.6 px
流速   = 条高 × 0.55 / s              # ≈ 11.4 px/s
纹理内缩 = 线宽 × 0.75                 # 端点 y 先内缩，再与矩形求交
```

45° 线在端点处向外溢出约 `宽度 × 0.7`；血条无背板，溢出等于画在实景上。
v1 漏了内缩，真渲染截图里血条**上沿外**能数出一排斜纹尖 —— 由 `_draw` 的端点夹取修掉。

### ② 震动

```
offset(t) = ( sin(2π·26·t)·A_x , sin(2π·26·1.37·t + 1.7)·A_y ) × (1 − t/T)^1.6
A = (12, 6.5) 设计 px × HUD_UI_SCALE(0.8) = (9.6, 5.2) canvas px
T = 0.34 s   punch = 1 + 0.06×(1 − t/T)^3   tint = lerp(WHITE, (1,.58,.52), 0.55×decay)
```

- 两个频率 26 与 35.62 Hz 非整数倍 ⇒ 看不出规律往复。
- v1 的 `(9, 5)` 实拍几乎看不出来，按真渲染上调到 `(12, 6.5)`；同时补了染色 ——
  暗实景上单靠位移，"很显眼"这条做不到。
- 复位必须三项一起（`position` / `scale` / `modulate`）。只复位 position 会让状态块
  永久停在 1.06 倍大小与暖红色上，而这种错**不会报任何运行时错误**。

### ① 冷却环

```
外径 28 设计 px × 0.8 = 22.4 canvas px        线宽比 0.13 ⇒ 环带 1.46 px
落点 (30,140)..(58,168) 设计 px ⇒ canvas (24,112)..(46.4,134.4)
环心飞镖 宽 0.56R / 高 0.66R / 笔画 0.115R     三点均值恒为环心
```

位置按实测矩形校准（探针读数）：

| 邻居 | canvas rect | 与本环的间隙 |
|---|---|---|
| 电芯行 `FlashlightBatteryPanel` | y 92.2..106.6 | 5.4 px |
| 状态块下沿 | y 139.2 | 4.8 px |
| `SEED` 标签 | y 144 起 | 9.6 px |

v1 取 32 设计 px、y 从 134 起 ⇒ 环顶距电芯格 0.6 px（贴死），已按上表重取。

### ④ 补条

```
advance(p) = lerp(from, to, 1 − (1 − p)^2),  p = clamp(t / (0.40 × 0.62), 0, 1)
fade(t)    = 1                          t/T ≤ 0.55
           = 1 − (t/T − 0.55) / 0.45    之后线性到 0
play 门槛   to − from > 0.004            # 逐点回血不闪
```

## 3. 只读边界

- 生命真源仍是 `Player3D.current_hp` → `hp_bar.value`，**当帧到位**。补条不许缓动它：
  `verify_player_hud_combat_feedback` 里有一条 `actual_ratio` 必须立刻等于 0.85 的断言，
  就是防"让血条自己慢慢涨"这种看起来更平滑、实际在撒谎的写法。
- 冷却真源仍是 `Player3D.dash_cooldown_timer`；HUD 只连 `dash_cooldown_changed`。
  `Player3D` 本轮**零改动** —— 该信号早已存在、此前无人消费。
- 四件都不进存档、不进战斗日志、不参与伤害判定；回滚口径 = 删 HUD 上对应一个节点。

## 4. 验收

| 用例 | 类型 | 结果 |
|---|---|---|
| `verify_player_hud_combat_feedback` | core（新增，已注册） | `PLAYER_HUD_COMBAT_FEEDBACK_OK` exit 0 |
| `verify_reference_hud_fate_visual` | visual（回归） | `REFERENCE_HUD_FATE_VISUAL_OK` exit 0 |
| `verify_finite_ammo_flow` | core（回归） | `FINITE_AMMO_FLOW_OK` exit 0 |
| `verify_3d_reload_state_flow` | core（回归） | `3D_RELOAD_STATE_FLOW_OK` exit 0 |
| `capture_player_vitals_feedback` | visual 取证（窗口模式） | 5 张全屏 + 5 张左上 3× 放大图，全部 `err=0` |

`verify_reference_hud_fate_visual` 里加了一行 `_tick_player_vitals_fx(0.5)`：该用例会连续
调用三次治疗来验"治疗不留假白段"，新增的补条会停在半路、受击震动会停在未复位的位移上，
截图就不干净了。这个调用**只推视觉层**，不碰 `_tick_player_health_bar_delay` ——
截图里那段要给业主看的白段仍然在（已复核 OK）。

### 真渲染取证（`outputs/verification/`）

| 图 | 看什么 | 实测 |
|---|---|---|
| `player_vitals_feedback_1_track` | 空槽斜杆：是否够暗、是否越界 | 斜纹在条内、上沿无溢出；底缘 1px 弱白线成立 |
| `..._2_shake` | 受击：位移 + 放大 + 染色 + 白段 | offset `(8.88, −4.20)` canvas px、整簇偏暖、白段 0.40→0.55 |
| `..._3_heal` | 回血：白段从旧值推到新值 + 前沿竖线 | `lead=0.71`（from 0.40 / to 0.72），前沿竖线可见 |
| `..._4_dash_cd` | 冷却中：圆弧只填一部分、天蓝 | 40% 已恢复 ⇒ 弧从 12 点顺时针约 144°，`#4FA8FF` |
| `..._5_dash_ready` | 就绪：满圈转白 + 闪光 | 满圈近白，飞镖与环带分离清晰 |

带 `_zoom` 后缀的是左上状态块的 3× 放大图：全屏图里血条只有 176×21 px，
"斜杆够不够暗"在那个尺寸上判不了。

## 5. 本轮踩到的坑（都已在代码注释里留档）

1. **`draw_line` 会越界**：宽度沿法线两侧铺开，45° 线端点外溢约 `0.7×宽`。
   血条无背板 ⇒ 溢出即画在实景上。必须先把端点 y 内缩再与矩形求交。
2. **`clip_contents` 裁不了自身 `_draw`**：它只裁子节点。想靠"旋转矩形 + clip"画斜纹，
   结果一定是线头露在血条外面。
3. **容器会覆盖子节点 `position`**：震动只能做在 `_reference_hud_root` 的绝对锚定控件上，
   做在 `VBoxContainer` 里那一层等于白抖（被布局每帧写回）。
4. **`sin` 会过零**：拿「位移长度」判震动衰减，会在相位过零的帧误报"没衰减"（首版就这么误报）。
   改为单独暴露包络 `shake_decay` 给验收读。
5. **截冷却中状态不能只调 HUD 的槽函数**：下一物理帧会被 `dash_cooldown_changed` 用真值覆盖，
   截出来是一整圈白环。必须写玩家的 `dash_cooldown_timer` 再等物理帧。
6. **`HudDashCooldownRing.get_children()` 里不能有 `Label`**：主人明确要求"不要用文字提醒"，
   这条写成了断言（`find_children("*", "Label")` 必须为空），防以后有人顺手加个秒数。

## 6. 未做 / 风险

- **移动端未验**：`MobileInput` 没有冲刺按钮（历史上右下四个操作键已从 HUD 撤掉），
  触屏玩家目前只能走键盘/手柄的 Shift / B。冷却环在触屏上仍然是纯展示，不给点。
  若后续恢复移动端冲刺按钮，应当把它与这个环合并成同一个控件，不要再建第二个圆。
- **震动与"整个 HUD 一起晃"的边界**：当前只晃状态块，相机与世界不动。
  若业主后面要"挨打时镜头也抖"，那是 `PlayerCameraFeedback3D` 的职责，不要塞进这里。
- **底纹在纯白场景（天台地砖）上的可读性**未单独取证：alpha 0.34 的冷蓝底在亮背景上会变淡。
  真渲染那两张图都在暗房里拍的。
- **补条与"超出当前最大血量的过疗"**没有关系：`to_ratio` 已 `clamp(0,1)`，不会画出条外。
