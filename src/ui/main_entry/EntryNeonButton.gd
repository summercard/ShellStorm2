extends Button
## 弹壳风暴 启动页按钮（棱镜线框版）。
## 通过 Control._draw 自绘，保留真实 Button 以兼容键盘 / 手柄焦点与 pressed 信号。
##
## 造型按《UI风格规范_棱镜线框》：
##   · role = "primary"（开始游戏）：**实心近白底 + 深墨字**，方角，无辉光无渐变；
##   · role = "ghost"  （设置）    ：**透明底 + 白字 + 四角 L 形括号**，悬停括号提亮。
## 旧版的六边斜切 + 呼吸霓虹光晕 + 流光扫线 + 齿轮装饰全部移除（规范 §11 反面清单）。

# 不声明 class_name：避免与项目内同名资源冲突，外部一律走 res:// 路径引用。

## "primary" = 实心近白主行动；"ghost" = 透明底四角括号次行动。
@export var role := "primary"
## 保留字段（旧场景属性）：本版不再使用冷却/光晕参数，留桩以免旧场景加载报错。
@export var chamfer := 16.0
@export var glow_strength := 1.0
@export var draw_gear := false
@export var label_text := "开始游戏"

var _hover := false
var _pressed := false
var _focus_blend := 0.0
var _press_blend := 0.0

const _PRISM_INK := Color(0.043, 0.071, 0.110, 1.0)
const _PRISM_TEXT := Color(0.949, 0.965, 0.984, 1.0)
const _PRISM_PRIMARY_BG := Color(0.949, 0.965, 0.984, 1.0)
## 主按钮的三级明度。
##
## ⚠️ 这里**故意让 hover 比常态暗**，与"悬停变亮"的直觉相反，原因是：
## 常态底 (0.949, 0.965, 0.984) 已经贴着纯白，提亮没有余量 ——
## 原来写 (1,1,1) 的悬停色，实测鼠标移上去 23064 个像素里**0 个变化**。
## 而 `present()` 会 `start_button.grab_focus()`，进门时按钮常驻 hover 色，
## 更把"悬停"这个状态整个吃掉。唯一有余量、且在深色背景上对比强烈的方向是压暗。
## 于是改成 常态 → hover 压一档 → pressed 再压一档，三级都可见。
const _PRISM_PRIMARY_BG_HOVER := Color(0.800, 0.831, 0.878, 1.0)
const _PRISM_PRIMARY_BG_PRESS := Color(0.612, 0.647, 0.706, 1.0)
## 主按钮的字距两档：常态 4 → 悬停/焦点 8。
## 这是规范 §5.1 给 `primary` 的"加大字距"，也是底色之外唯一还剩下的对比线索。
const _PRIMARY_LABEL_SPACING := 4
const _PRIMARY_LABEL_SPACING_HOVER := 8

## ghost 悬停/按下时的淡白底。
## 数值直接沿用 `UIStyleFactory.make_prism_button_style("ghost")` 的 bg（0.12 / 0.24）——
## 本按钮只是把 StyleBox 换成了自绘，交互口径不该另立一套。
const _GHOST_HOVER_FILL_A := 0.12
const _GHOST_PRESS_FILL_A := 0.24
## 悬停时括号加粗的终值（正常 2.0 → 悬停 3.0）。
## 只提亮不够：括号本身只有 2px，从 0.58 提到 0.96 的视觉差在中远景下读不出来，
## 加粗一格才是"这个框选中了"的确定信号。
const _GHOST_ARM_THICKNESS_HOVER := 3.0


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	text = ""
	# 用全透明 StyleBox 覆盖任意主题 / 工厂样式，保证只显示自绘图形。
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(0)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, empty)
	if has_theme_color_override("font_color"):
		remove_theme_color_override("font_color")
	resized.connect(_on_resized)
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	button_down.connect(func(): _pressed = true; queue_redraw())
	button_up.connect(func(): _pressed = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	# 弹性缩放 + ui_hover / ui_click 音效：走项目统一的那套按钮反馈，
	# 不在这里另连 mouse_entered 播音效（会和 UIFX 重复、且音量口径不一）。
	UIStyleFactory.attach_button_feedback(self)


func _on_resized() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var prev_focus := _focus_blend
	var prev_press := _press_blend
	_focus_blend = move_toward(_focus_blend, 1.0 if (_hover or has_focus()) and not disabled else 0.0, delta * 9.0)
	_press_blend = move_toward(_press_blend, 1.0 if _pressed and not disabled else 0.0, delta * 18.0)
	# 只在过渡中重绘：稳定态每帧重绘纯属浪费（自绘控件没有别的失效来源）。
	if not is_equal_approx(prev_focus, _focus_blend) or not is_equal_approx(prev_press, _press_blend):
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	var offset := Vector2(1.0, 1.0) * _press_blend
	var rect := Rect2(Vector2(1.0, 1.0) + offset, Vector2(w - 2.0, h - 2.0))
	var focus := has_focus() or _hover
	if role == "primary":
		_draw_primary(rect, focus)
	else:
		_draw_ghost(rect, focus, w, h)


## 主行动：实心近白底 + 深墨字。无描边、无圆角、无光晕。
##
## ⚠️ 底色的 hover/press 只认**鼠标**，不认键盘焦点：
## `present()` 进门就 `start_button.grab_focus()`，若焦点也换底色，
## 那按钮从第一帧起就常驻"悬停色"，鼠标移上去照样零变化（这正是原来的 bug 之一）。
## 键盘焦点改由字距表达，与鼠标悬停共用同一条线索，互不抢占。
##
## 悬停 = 底色压一档 + 字距 4 → 8；按下 = 再压一档。
## 为什么不是"提亮"：常态底已贴纯白，没有提亮余量（见三级明度注释）。
func _draw_primary(rect: Rect2, focus: bool) -> void:
	var hover_t := clampf(_focus_blend, 0.0, 1.0) if not disabled else 0.0
	var fill := _PRISM_PRIMARY_BG
	if disabled:
		fill = Color(0.60, 0.64, 0.69, 0.42)
	elif _pressed:
		fill = _PRISM_PRIMARY_BG_PRESS
	elif _hover:
		fill = _PRISM_PRIMARY_BG_HOVER
	draw_rect(rect, fill, true)
	# 字距认鼠标悬停 + 键盘焦点（两者同权：键盘操作也需要"选中"可见）。
	var spacing := _PRIMARY_LABEL_SPACING
	if hover_t > 0.01:
		spacing = _PRIMARY_LABEL_SPACING_HOVER
	var text_col := _PRISM_INK
	if disabled:
		text_col = Color(_PRISM_INK.r, _PRISM_INK.g, _PRISM_INK.b, 0.45)
	_draw_label(rect, text_col, spacing)


## 次行动：透明底 + 白字 + 四角 L 形括号（本风格的"选框"语言）。
## 悬停 = 括号提亮 + 加粗 + 一层极淡白底；按下 = 白底加深（沿用 ghost StyleBox 的 0.12 / 0.24 口径）。
## 只提亮不改粗是不够的：2px 细线从 0.58 到 0.96 的亮度差在中远景里读不出来。
func _draw_ghost(rect: Rect2, focus: bool, w: float, h: float) -> void:
	var hover_t := _focus_blend
	var press_t := _press_blend
	var line_a := 0.58 + 0.42 * hover_t
	if disabled:
		line_a *= 0.35
	if not disabled:
		var fill_a := lerpf(_GHOST_HOVER_FILL_A * hover_t, _GHOST_PRESS_FILL_A, press_t)
		if fill_a > 0.002:
			draw_rect(rect, Color(1.0, 1.0, 1.0, fill_a), true)
	var arm := minf(18.0, minf(h * 0.42, w * 0.16))
	var t := lerpf(2.0, _GHOST_ARM_THICKNESS_HOVER, hover_t)
	var col := Color(1.0, 1.0, 1.0, clampf(line_a, 0.0, 1.0))
	var lt := rect.position
	var rb := rect.position + rect.size
	# 四角各由一条横臂 + 一条竖臂组成（L 形），边线中段留空 —— 这是本风格的"选框"。
	var arms := [
		Rect2(lt, Vector2(arm, t)),
		Rect2(lt, Vector2(t, arm)),
		Rect2(Vector2(rb.x - arm, lt.y), Vector2(arm, t)),
		Rect2(Vector2(rb.x - t, lt.y), Vector2(t, arm)),
		Rect2(Vector2(lt.x, rb.y - t), Vector2(arm, t)),
		Rect2(Vector2(lt.x, rb.y - arm), Vector2(t, arm)),
		Rect2(Vector2(rb.x - arm, rb.y - t), Vector2(arm, t)),
		Rect2(Vector2(rb.x - t, rb.y - arm), Vector2(t, arm)),
	]
	for arm_rect in arms:
		draw_rect(arm_rect, col, true)
	var text_col := Color(1.0, 1.0, 1.0, 1.0) if focus else _PRISM_TEXT
	if disabled:
		text_col = Color(_PRISM_TEXT.r, _PRISM_TEXT.g, _PRISM_TEXT.b, 0.45)
	_draw_label(rect, text_col, 5)


func _draw_label(rect: Rect2, col: Color, spacing: int) -> void:
	var font := UIStyleFactory.make_prism_font(spacing)
	if font == null:
		font = _font()
	if font == null:
		return
	var fs := int(size.y * 0.40)
	var center := rect.position + rect.size * 0.5
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var origin := Vector2(center.x - text_size.x * 0.5, center.y + fs * 0.34)
	draw_string(font, origin, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _font() -> Font:
	var f := get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	return f
