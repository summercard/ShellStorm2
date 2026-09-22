extends Control
## 启动页品牌图形：左侧白青色倾斜大标题「弹壳风暴」+ 品红「2」，
## 全部用 Control._draw 自绘（中文使用默认系统字体，无需外部字体资源）。

# Built-in TAU is used for circular accents.

var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var font := _font()
	if font == null:
		return
	var h := size.y
	if h <= 1.0:
		return
	var base := h * 0.47
	var shear := -0.18
	# 斜切（shear）：x' = x + shear * y，使标题向右上倾斜。
	var cyan_accent := Color(0.02, 0.82, 0.95, 0.16)
	draw_arc(Vector2(size.x * 0.46, h * 0.51), h * 0.57, -1.2, 3.9, 64, cyan_accent, 1.0, true)
	draw_set_transform(Vector2(size.x * 0.38, h * 0.25), -0.36, Vector2(0.56, 1.3))
	draw_circle(Vector2.ZERO, 22.0, cyan_accent)
	draw_set_transform(Vector2(size.x * 0.52, h * 0.23), 0.36, Vector2(0.56, 1.3))
	draw_circle(Vector2.ZERO, 22.0, cyan_accent)
	var m := Transform2D(Vector2(1.0, 0.0), Vector2(shear, 1.0), Vector2(28, 0))
	draw_set_transform_matrix(m)
	var cyan := Color(0.78, 0.97, 1.0, 1.0)
	var magenta := Color(1.0, 0.18, 0.62, 1.0)
	var title := "弹壳风暴"
	var two := "2"
	var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(base)).x
	var two_size := int(base * 1.50)
	var gap := base * 0.10
	var start_x := 8.0
	var baseline := h * 0.5 + base * 0.36
	# 呼吸微光（与按钮同频）
	var breath := 0.5 + 0.5 * sin(_t * 2.2)
	# 外发光多层叠加
	for i in range(3, 0, -1):
		var a := 0.10 * float(i) * (0.7 + 0.3 * breath)
		var off := Vector2(-float(i) * 1.5, 0.0)
		draw_string(font, Vector2(start_x, baseline) + off, title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(base), Color(cyan.r, cyan.g, cyan.b, a))
		draw_string(font, Vector2(start_x + title_w + gap, baseline) + off, two, HORIZONTAL_ALIGNMENT_LEFT, -1, two_size, Color(magenta.r, magenta.g, magenta.b, a))
	# 清晰本体
	draw_string(font, Vector2(start_x, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(base), cyan)
	draw_string(font, Vector2(start_x + title_w + gap, baseline), two, HORIZONTAL_ALIGNMENT_LEFT, -1, two_size, magenta)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_line(Vector2(6, h * 0.30), Vector2(18, h * 0.12), Color(0.05, 0.94, 1), 3, true)
	draw_line(Vector2(18, h * 0.12), Vector2(34, h * 0.12), Color(0.05, 0.94, 1), 3, true)
	draw_line(Vector2(size.x - 26, h * 0.84), Vector2(size.x - 8, h * 0.58), Color(0.05, 0.94, 1), 3, true)
	draw_line(Vector2(24, h * 0.77), Vector2(size.x * 0.68, h * 0.77), Color(0.02, 0.88, 0.98, 0.8), 2, true)

func _font() -> Font:
	var f := get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	return f
