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
const _PRISM_PRIMARY_BG_HOVER := Color(1.0, 1.0, 1.0, 1.0)
const _PRISM_PRIMARY_BG_PRESS := Color(0.780, 0.816, 0.867, 1.0)


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


func _on_resized() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_focus_blend = move_toward(_focus_blend, 1.0 if (_hover or has_focus()) and not disabled else 0.0, delta * 9.0)
	_press_blend = move_toward(_press_blend, 1.0 if _pressed and not disabled else 0.0, delta * 18.0)
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
func _draw_primary(rect: Rect2, focus: bool) -> void:
	var fill := _PRISM_PRIMARY_BG
	if disabled:
		fill = Color(0.60, 0.64, 0.69, 0.42)
	elif _pressed:
		fill = _PRISM_PRIMARY_BG_PRESS
	elif focus:
		fill = _PRISM_PRIMARY_BG_HOVER
	draw_rect(rect, fill, true)
	var text_col := _PRISM_INK
	if disabled:
		text_col = Color(_PRISM_INK.r, _PRISM_INK.g, _PRISM_INK.b, 0.45)
	_draw_label(rect, text_col, 4)


## 次行动：透明底 + 白字 + 四角 L 形括号（本风格的"选框"语言）。
func _draw_ghost(rect: Rect2, focus: bool, w: float, h: float) -> void:
	var line_a := 0.58 + 0.38 * _focus_blend
	if disabled:
		line_a *= 0.35
	var arm := minf(18.0, minf(h * 0.42, w * 0.16))
	var t := 2.0
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
