extends Button
## 弹壳风暴 启动页霓虹切角按钮。
## 通过 Control._draw 自绘六边斜切形状、呼吸微光、流光、hover/焦点平移与按下反馈，
## 保留真实 Button 以兼容键盘 / 手柄焦点与 pressed 信号。

# 不声明 class_name：避免与项目内同名资源冲突，外部一律走 res:// 路径引用。

const NEON_CYAN := Color(0.20, 0.90, 1.0, 1.0)

@export var accent := NEON_CYAN
@export var chamfer := 16.0
@export var glow_strength := 1.0
@export var draw_gear := false
@export var label_text := "开始游戏 >>"

var _t := 0.0
var _hover := false
var _pressed := false
var _focus_blend := 0.0
var _press_blend := 0.0

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
	_t += delta
	_focus_blend = move_toward(_focus_blend, 1.0 if (_hover or has_focus()) and not disabled else 0.0, delta * 8.0)
	_press_blend = move_toward(_press_blend, 1.0 if _pressed and not disabled else 0.0, delta * 16.0)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return
	var ch := minf(chamfer, minf(h * 0.5, w * 0.5))
	var base := PackedVector2Array([
		Vector2(0.0, h * 0.5),
		Vector2(ch, 0.0),
		Vector2(w - ch, 0.0),
		Vector2(w, h * 0.5),
		Vector2(w - ch, h),
		Vector2(ch, h),
	])
	var focus := has_focus() or _hover
	var shift := Vector2(7.0 * _focus_blend, 0.0)
	var press := Vector2(2.0, 2.0) * _press_blend
	var pts := PackedVector2Array()
	for p in base:
		pts.append(p + shift + press)
	var breath := 0.5 + 0.5 * sin(_t * 2.2)
	var glow_a := (0.16 + 0.22 * breath) * glow_strength
	if focus:
		glow_a += 0.26
	if disabled:
		glow_a *= 0.35
	var center := Vector2(w * 0.5, h * 0.5) + shift + press
	# 外层呼吸光晕
	for i in range(3, 0, -1):
		var grow := float(i) * 2.2
		var gp := PackedVector2Array()
		for p in pts:
			gp.append(center + (p - center) * (1.0 + grow / maxf(w, 1.0)))
		_solid(gp, Color(accent.r, accent.g, accent.b, glow_a * 0.22 * float(i)))
	# 填充
	var fill := Color(0.012, 0.028, 0.045, 0.88)
	if focus:
		fill.a += 0.10
	if disabled:
		fill.a *= 0.5
	_solid(pts, fill)
	# 霓虹描边
	var border := Color(accent.r, accent.g, accent.b, clampf(0.6 + 0.35 * breath + (0.2 if focus else 0.0), 0.0, 1.0))
	if disabled:
		border.a *= 0.5
	var line := pts.duplicate()
	line.append(pts[0])
	draw_polyline(line, border, 2.0, true)
	# 流光：沿上边扫过的高亮线段
	_draw_flow(pts, focus)
	# 文字与图标
	_draw_label(shift + press, focus, breath)

func _draw_flow(pts: PackedVector2Array, focus: bool) -> void:
	var a := pts[1]
	var b := pts[2]
	var flow := fmod(_t * 0.35, 1.0)
	var head := a.lerp(b, flow)
	var tail_t := flow - 0.20
	var tail := a.lerp(b, clampf(tail_t, 0.0, 1.0))
	var alpha := 0.45 + 0.4 * float(focus)
	draw_line(tail, head, Color(0.85, 1.0, 1.0, alpha), 2.0)
	draw_circle(head, 1.8, Color(1.0, 1.0, 1.0, 0.75))

func _draw_label(off: Vector2, focus: bool, _breath: float) -> void:
	var font := _font()
	if font == null:
		return
	var fs := int(size.y * 0.42)
	var col := Color(0.86, 0.98, 1.0, 1.0)
	if focus:
		col = Color(1.0, 1.0, 1.0, 1.0)
	if disabled:
		col.a *= 0.5
	var cx := off.x + size.x * 0.5 - font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	var cy := off.y + size.y * 0.5 + fs * 0.34
	if draw_gear:
		_draw_gear(Vector2(size.x - 48.0, off.y + size.y * 0.5), fs * 0.36, accent)
	draw_string(font, Vector2(cx, cy), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_gear(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r, 0.0, TAU, 14, col, 2.0)
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var p1 := c + Vector2(cos(ang), sin(ang)) * r
		var p2 := c + Vector2(cos(ang), sin(ang)) * (r + r * 0.36)
		draw_line(p1, p2, col, 2.0)

func _solid(points: PackedVector2Array, col: Color) -> void:
	var cols := PackedColorArray()
	for _i in points.size():
		cols.append(col)
	draw_polygon(points, cols)

func _font() -> Font:
	var f := get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	return f
