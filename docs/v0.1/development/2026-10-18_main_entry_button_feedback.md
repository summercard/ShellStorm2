# 启动页按钮交互反馈补齐

日期：2026-10-18
范围：`scenes/ui/MainEntryScreen3D.tscn` 的 `StartButton` / `SettingsButton`
主实现：`src/ui/main_entry/EntryNeonButton.gd`、`src/ui/UIStyleFactory.gd`

## 问题

启动页两个按钮鼠标悬停无任何视觉变化，点击也无反馈。

## 根因（实测，非推测）

用 `tools/verify_entry_button_feedback.gd` 在真实主场景里逐态截图像素比对，得到修复前的数字：

| 状态 | 按钮区域内变化像素 | 最大色差 |
| --- | --- | --- |
| StartButton hover | **0 / 23064** | 1 |
| StartButton press | 22248 / 23064 | 244 |
| SettingsButton hover | 992 / 23064 | 88 |
| SettingsButton press | 1406 / 23064 | 230 |

三条独立缺陷：

1. **primary 的 hover 色没有提亮余量。**
   `_PRISM_PRIMARY_BG_HOVER = (1,1,1)`，而常态底已经是 `(0.949, 0.965, 0.984)` ——
   提亮 1.3%，在 sRGB 上不足 1 级，等于没变。

2. **`present()` 无条件 `start_button.grab_focus()`，把焦点画成"悬停"。**
   `_draw_primary` 里 `elif focus: fill = HOVER`，焦点即 hover 色。
   于是按钮从第一帧起就常驻悬停色，鼠标再移上去必然零变化。
   这条是"0 个像素"的真正主因，比第 1 条更致命。

3. **两个按钮完全没接项目的统一反馈。**
   `EntryNeonButton._ready()` 只连了自绘状态，没有 `UIFX.attach_button_press`
   （弹性缩放）也没有 `ui_hover` / `ui_click` 音效。其余所有按钮都经
   `UIStyleFactory` 拿到这两样，唯独这两个自绘按钮漏了。

## 改动

### 1. `UIStyleFactory`：把按钮反馈提成单一入口

新增 `attach_button_feedback(btn, hover_scale, pressed_scale)`，收拢
「UIFX 缩放 + `ui_hover`/`ui_click` 音效 + 未入树时挂 `ready`」这三件事。
`apply_prism_button` 改为调用它（仍传 1.014 / 0.988）；`apply_button_style`
也改为调用它，但**显式传 `UIFX.DEFAULT_HOVER_SCALE` / `DEFAULT_PRESSED_SCALE`**
（1.05 / 0.95）—— 那两个值原本是 `UIFX.attach_button_press` 的默认参数，
提及时提成命名常量，语义不变、老按钮手感一字不动。

### 2. `EntryNeonButton`

- `_ready()` 末尾接 `UIStyleFactory.attach_button_feedback(self)`。
- **primary 三级明度改为"压"而不是"提"**：
  `常态 (0.949, 0.965, 0.984)` → `hover (0.800, 0.831, 0.878)` → `press (0.612, 0.647, 0.706)`。
  理由见根因 1/2：白色没有提亮空间，只有压暗方向有余量，且这块白坐在深色背景上，
  压一档的对比比提亮强一个数量级。
- **底色只认鼠标，不认键盘焦点**：`elif _hover:` 替代 `elif focus:`。
  键盘焦点改由字距表达（4 → 8，规范 §5.1 给 `primary` 的"加大字距"），
  鼠标悬停同时吃到字距，两条线索不互相抢占。
- **ghost 悬停/按下补齐可辨识度**：
  括号亮度 0.58 → 1.0、**边框 2px → 3px**、叠一层 0.12 白底；按下白底加深到 0.24。
  数值取自 `make_prism_button_style("ghost")`，不另立一套。原来只提亮 0.38 一档，
  2px 细线的亮度差在中远景里读不出来。
- `_process` 只在过渡中 `queue_redraw()`，稳定态不再每帧重绘。

## 验收

`godot --path . -s tools/verify_entry_button_feedback.gd`（真实渲染器）：

```
start   enter -> scale=(1.014, 1.014) (expect 1.014)
start   exit  -> scale=(1.0, 1.0)     (expect 1.000)
set     enter -> scale=(1.014, 1.014) (expect 1.014)
set     down  -> scale=(0.988, 0.988) (expect 0.988)
StartButton audio_bound=true uifx=true
SettingsButton audio_bound=true uifx=true
settings_open=true overlay_visible=true
```

修复后像素比对（同一脚本强制三态拍照）：

| 状态 | 变化像素 | 最大色差 |
| --- | --- | --- |
| StartButton hover | 21368 / 23064 | 52 |
| StartButton press | 22244 / 23064 | 231 |
| SettingsButton hover | 22200 / 23064 | 231 |
| SettingsButton press | 22265 / 23064 | 231 |

证据图：`outputs/verify_entry_{normal,start_hover,start_press,settings_hover,settings_press}.png`

既有验收未回归：`verify_expedition_resume_entry`（真实渲染器）→
`EXPEDITION_RESUME_ENTRY_OK`。

## 未处理（留档，不在本次范围）

`src/ui/UIPalette.gd` 的 `PRISM_PRIMARY_BG_HOVER` 仍是 `(1,1,1)`。
走 `make_prism_button_style("primary")` 的所有按钮（各菜单的确认/主行动钮）
有同样的"悬停提亮不足 1 级"问题。但那一改动会影响全部界面的观感与既有截图基线，
本次只修用户指定的启动页两个按钮，全局口径待单独决策。
