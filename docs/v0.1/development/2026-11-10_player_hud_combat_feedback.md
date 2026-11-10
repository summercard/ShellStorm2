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

---

## 7. 第二轮：左侧放置与兔子剪影（同日）

> 业主原话：「翻滚提示放在那个位置也太难看见了，放到左下角来，图标换成兔子翻滚的其中一帧的白色剪影。」

### 7.1 位置：左上 → 左下角

| 项 | r6（首版） | r6.1（本轮） |
|---|---|---|
| 锚点 | 左上 `(0,0,0,0)`，挂在状态块内容列 | **左下 `(0,1,0,1)`** |
| 设计偏移 | `(30,140)..(58,168)` | `(18,-86)..(78,-26)`（距左 18、距底 26） |
| 外径 | 28 设计 px ⇒ 22.4 canvas | **60 设计 px ⇒ 48 canvas（2.14 倍）** |

尺寸不是拍的：业主红框在 1242×693 截图里是 `(11,627)..(64,676)`，按
`1280/1242 = 1.0306` 换算到 canvas 是 `(11.3,646.2)..(66.0,696.7)`，直径约 50 canvas px
⇒ 60 设计 px × 0.8 = 48 恰好落在框内。

**连带冲突与处理**：左下角原本是遭遇倒计时环的地盘（设计 `(40,-148)..(148,-40)`
⇒ canvas x 32..118 / y 602..688）。翻滚环是**常驻件**、倒计时环是**事件才出现**的临时件，
常驻件优先占角落 ⇒ 倒计时环右移 60 设计 px 到 `(100,-148)..(208,-40)`
（canvas x 80..166），与翻滚环右缘 62.4 留 17.6 px。这条做成了断言：

```
not dash_ring.get_global_rect().intersects(countdown_ring.get_global_rect())
```

光靠注释说明"记得别撞"，下一个人调数值时必然撞上；断言会在撞上的那一帧报红。

### 7.2 剪影：从真实角色身上量出来

**链路（不是手画图标）**

| 步 | 工具 | 产出 |
|---|---|---|
| 1 | `tools/_capture_dash_glyph.gd` | 玩家摆 `dashing` 姿态、按生产公式写翻滚角、只留角色 layer、白 unshaded、背景压黑，正交相机从 +X 侧拍 |
| 2 | 同上，18 个相位 | `outputs/verification/dash_glyph_p02..p70.png`（128×128 黑底白剪影）<br>**已清理**（一次跑 24 张、共约 3 MB，重跑工具即再生）；选定帧与其掩码已归档到 `outputs/dash_glyph_20261110/` |
| 3 | 人眼筛帧（按 HUD 实际图标尺寸看） | 选 `p18`（翻滚 31°） |
| 4 | `scripts/trace_dash_glyph.py` | 3× 放大 → 边界有向边行走 → RDP(eps 2.4) → 归一化 ⇒ 59 拐点 |
| 5 | `src/ui/HudDashGlyph.gd` | `static var DASH_GLYPH_POINTS`（`PackedVector2Array` 不是常量表达式，`const` 会解析失败） |

**为什么选 31°，不选更"翻滚"的帧**：把 18 帧在真实图标尺寸（44 px）下排成横向对照表看，
≥90°（p30 之后）时耳朵会与身体在剪影上并成一块，读数变成"一团白色"；
≤19° 又几乎是站立姿态，"在翻滚"表达不出来。31° 是唯一同时满足
"双耳分开 + 身体已收腿离地 + 举起的手可见"的相位。

**为什么是矢量不是位图**：`verify_reference_hud_fate_visual` 第 37 行断言
HUD 里 `TextureRect` 数量必须等于 3D 投影图标数量 —— 塞一张位图进去会让那条既有门禁报红。
顺带好处：任意尺寸清晰，换环直径不用重出图。本轮还把"环内不得出现 `TextureRect`"
写成了新断言，防以后有人图省事换回 PNG。

**抗锯齿**：`draw_colored_polygon` 没有 `antialiased` 参数，只填不描时 48 px 环里的
剪影边缘是一排明显台阶（首版实拍确认）。补一圈同色 `draw_polyline(..., antialiased = true)`
后台阶被半透明像素抹平。这是"填充 + 描边"两遍，不是两套形状。

**尺寸约束**：环带内缘半径 = `0.5 × (1 − 0.13) = 0.435` 直径；剪影按最长边铺满
⇒ 取 `GLYPH_FIT_RATIO = 0.66`，留 8% 余量。断言钉住「剪影尺寸 < 内缘直径」。

**颜色**：业主说的是"**白色**剪影"，所以两种状态都白（冷却 alpha 0.58 / 就绪 0.94）。
状态色只由外圈那道弧承担（天蓝 → 近白）。首版曾让剪影跟着弧变蓝，与"白色剪影"不符。

### 7.3 本轮踩到的坑

1. **"真冲刺一次再冻住"抓不到翻滚姿态**：冲刺 0.204 s、动画周期 0.265 s，状态机在
   `progress ≈ 0.77` 就退回 idle，`rotation.x` 被 `_update_state_motion` 末尾那句
   `else 0.0` 清掉 —— 而 `_dash_animation_progress` 还停在旧值。于是"冻在 0.37"截出来的
   是**一只站着的兔子**。改成直接钉 `_state = "dashing"` 并按目标相位收敛姿态。
2. **只保留最大连通块会切掉手**：兔子翻滚帧的两只手/脚在剪影上是分离的小块。
   首版描边只取最长环 ⇒ 剪影上凭空少一块，看起来像被切掉一角。改成输出全部轮廓
   （`DASH_GLYPH_POLYGONS` 起，最终因该帧四肢实际连通而仍是单块，但工具已支持多块）。
3. **`class_name` 依赖全局类缓存**：`HudDashGlyph` 一开始注册了 `class_name`，
   结果在纯命令行（没跑过编辑器）下报 `Could not find type "HudDashGlyph"` ——
   那份缓存要编辑器跑一次才更新。改成 `preload` 引用，删掉 `class_name`。
4. **`PackedVector2Array(...)` 不是常量表达式**：`const` 会直接解析失败，改 `static var`。
5. **`draw_colored_polygon` 不抗锯齿**：见 7.2，补 `draw_polyline(antialiased)`。

### 7.4 验收（第二轮）

| 用例 | 结果 |
|---|---|
| `verify_player_hud_combat_feedback`（断言已改写） | `PLAYER_HUD_COMBAT_FEEDBACK_OK` exit 0 |
| `verify_reference_hud_fate_visual`（含 HUD 禁裸位图那条） | `REFERENCE_HUD_FATE_VISUAL_OK` exit 0 |
| `verify_encounter_trigger_room_flow`（倒计时环右移后） | `ENCOUNTER_TRIGGER_ROOM_OK samples=91` exit 0 |
| `verify_finite_ammo_flow` / `verify_3d_reload_state_flow` | 均 exit 0 |
| `capture_player_vitals_feedback` | 5 全屏 + 5 张左上 3× + **5 张左下 8×**，全部 err=0 |

新增断言（全部在 `verify_player_hud_combat_feedback`）：

- 环贴屏幕左下角：`rect.x ≤ 屏宽 × 0.08` 且 `rect.end.y ≥ 屏高 × 0.94`；
- 直径 ≥ 40 canvas px（业主嫌小的回归钉子）；
- 与 `EncounterCountdownRing` **不相交**；
- 环内无 `TextureRect`（禁位图）；
- 剪影拐点 ≥ 12（形状不是退化成的几根线段）；
- 剪影尺寸 < 环带内缘直径（不压环带）。

### 7.5 取证文件

- `outputs/verification/player_vitals_feedback_4_dash_cd_dash.png` —— 冷却中（40% 已恢复）8× 特写
- `outputs/verification/player_vitals_feedback_5_dash_ready_dash.png` —— 就绪（满圈 + 闪光）8× 特写
- `outputs/dash_glyph_20261110/` —— 剪影取材归档：选定帧原始剪影 + 掩码、18 相位横向对照表
  （`sheet44.png`）、5 帧净空比对（`candidates.png`）

### 7.6 未做 / 风险（第二轮）

- **移动端仍未验**，同上。
- **剪影小尺寸的极限**：48 canvas px 下认得出兔子；若业主后续要求缩回 30 px 左右，
  这个形状会退化成"带两只耳朵的团"，届时应换 45°~60° 那一类身体更舒展的帧重做，
  而不是简单缩小。
- **倒计时环右移**只做了"两者不相交"的几何断言 + 倒计时行为回归，
  **没有重出** `capture_encounter_countdown_ring` 的两张对比图 —— 位置变了但外观没变，
  若要看它现在在左下角长什么样，得重跑那个 capture。
