class_name CodeHUDGlyph
extends Control
## 纯代码 HUD 图标。避免 HUD 与命运卡依赖位图资源，并统一线宽、辉光与配色。

@export_enum("robot", "weapon", "reload", "dash", "shield", "interact", "pause", "currency", "battery")
var glyph_type := "robot":
	set(value):
		glyph_type = value
		queue_redraw()

@export var accent := Color(0.28, 0.92, 1.0):
	set(value):
		accent = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(kind: String, color: Color) -> void:
	glyph_type = kind
	accent = color
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var scale := minf(size.x, size.y) / 64.0
	if scale <= 0.0:
		return
	match glyph_type:
		"robot": _draw_robot(center, scale)
		"weapon": _draw_weapon(center, scale)
		"reload": _draw_reload(center, scale)
		"dash": _draw_dash(center, scale)
		"shield": _draw_shield(center, scale)
		"interact": _draw_interact(center, scale)
		"pause": _draw_pause(center, scale)
		"currency": _draw_currency(center, scale)
		"battery": _draw_battery(center, scale)
		_: _draw_interact(center, scale)


func _glow_line(from: Vector2, to: Vector2, width: float, color := Color(-1, -1, -1, -1)) -> void:
	var line_color := accent if color.r < 0.0 else color
	draw_line(from, to, Color(line_color, 0.14), width + 7.0, true)
	draw_line(from, to, Color(line_color, 0.30), width + 3.0, true)
	draw_line(from, to, line_color, width, true)


func _glow_polyline(points: PackedVector2Array, width: float, color := Color(-1, -1, -1, -1)) -> void:
	var line_color := accent if color.r < 0.0 else color
	draw_polyline(points, Color(line_color, 0.14), width + 7.0, true)
	draw_polyline(points, Color(line_color, 0.30), width + 3.0, true)
	draw_polyline(points, line_color, width, true)


func _draw_robot(center: Vector2, scale: float) -> void:
	var face := Rect2(center + Vector2(-20, -15) * scale, Vector2(40, 31) * scale)
	draw_style_box(_rounded_box(Color(0.74, 0.80, 0.84), Color(0.06, 0.09, 0.13), 6.0 * scale), face)
	draw_rect(Rect2(center + Vector2(-15, -10) * scale, Vector2(30, 19) * scale), Color(0.018, 0.028, 0.055), true)
	draw_circle(center + Vector2(-8, -1) * scale, 3.0 * scale, accent)
	draw_circle(center + Vector2(8, -1) * scale, 3.0 * scale, accent)
	draw_circle(center + Vector2(-8, -1) * scale, 7.0 * scale, Color(accent, 0.10))
	draw_circle(center + Vector2(8, -1) * scale, 7.0 * scale, Color(accent, 0.10))
	_glow_line(center + Vector2(0, -16) * scale, center + Vector2(0, -23) * scale, 1.4 * scale, Color(0.80, 0.90, 0.96))
	draw_circle(center + Vector2(0, -25) * scale, 2.2 * scale, accent)
	_glow_line(center + Vector2(-24, -7) * scale, center + Vector2(-24, 8) * scale, 2.5 * scale)
	_glow_line(center + Vector2(24, -7) * scale, center + Vector2(24, 8) * scale, 2.5 * scale)


func _draw_weapon(center: Vector2, scale: float) -> void:
	_glow_line(center + Vector2(-24, -3) * scale, center + Vector2(18, -3) * scale, 4.0 * scale)
	_glow_line(center + Vector2(8, -8) * scale, center + Vector2(27, -8) * scale, 3.0 * scale)
	_glow_line(center + Vector2(-16, -3) * scale, center + Vector2(-21, 6) * scale, 4.0 * scale)
	_glow_line(center + Vector2(2, 0) * scale, center + Vector2(7, 13) * scale, 5.0 * scale)
	draw_rect(Rect2(center + Vector2(-5, 0) * scale, Vector2(16, 7) * scale), Color(accent, 0.38), true)


func _draw_reload(center: Vector2, scale: float) -> void:
	draw_arc(center, 19.0 * scale, -2.45, 1.15, 28, Color(accent, 0.18), 7.0 * scale, true)
	draw_arc(center, 19.0 * scale, -2.45, 1.15, 28, accent, 2.4 * scale, true)
	var tip := center + Vector2.from_angle(1.15) * 19.0 * scale
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-8, -1) * scale, tip + Vector2(-2, -8) * scale,
	]), accent)
	_glow_line(center + Vector2(-6, -4) * scale, center + Vector2(7, -4) * scale, 3.0 * scale)
	_glow_line(center + Vector2(-4, 3) * scale, center + Vector2(5, 3) * scale, 3.0 * scale)


func _draw_dash(center: Vector2, scale: float) -> void:
	var runner := accent
	draw_circle(center + Vector2(5, -16) * scale, 4.5 * scale, runner)
	_glow_line(center + Vector2(1, -9) * scale, center + Vector2(-7, 5) * scale, 4.0 * scale, runner)
	_glow_line(center + Vector2(-5, -3) * scale, center + Vector2(10, 1) * scale, 3.0 * scale, runner)
	_glow_line(center + Vector2(-6, 5) * scale, center + Vector2(-18, 17) * scale, 4.0 * scale, runner)
	_glow_line(center + Vector2(-5, 5) * scale, center + Vector2(12, 16) * scale, 4.0 * scale, runner)
	_glow_line(center + Vector2(-27, -2) * scale, center + Vector2(-16, -2) * scale, 1.6 * scale, Color(accent, 0.72))
	_glow_line(center + Vector2(-24, 6) * scale, center + Vector2(-14, 6) * scale, 1.6 * scale, Color(accent, 0.72))


func _draw_shield(center: Vector2, scale: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -24) * scale,
		center + Vector2(19, -16) * scale,
		center + Vector2(16, 9) * scale,
		center + Vector2(0, 24) * scale,
		center + Vector2(-16, 9) * scale,
		center + Vector2(-19, -16) * scale,
		center + Vector2(0, -24) * scale,
	])
	draw_colored_polygon(points, Color(accent, 0.12))
	_glow_polyline(points, 2.4 * scale)
	_glow_line(center + Vector2(0, -16) * scale, center + Vector2(0, 14) * scale, 1.5 * scale, Color(accent, 0.72))


func _draw_interact(center: Vector2, scale: float) -> void:
	var outer := PackedVector2Array([
		center + Vector2(0, -23) * scale,
		center + Vector2(23, 0) * scale,
		center + Vector2(0, 23) * scale,
		center + Vector2(-23, 0) * scale,
		center + Vector2(0, -23) * scale,
	])
	_glow_polyline(outer, 2.4 * scale)
	draw_circle(center, 6.0 * scale, Color(accent, 0.22))
	draw_circle(center, 2.8 * scale, accent)


func _draw_pause(center: Vector2, scale: float) -> void:
	_glow_line(center + Vector2(-7, -17) * scale, center + Vector2(-7, 17) * scale, 5.0 * scale)
	_glow_line(center + Vector2(7, -17) * scale, center + Vector2(7, 17) * scale, 5.0 * scale)


func _draw_currency(center: Vector2, scale: float) -> void:
	draw_arc(center, 20.0 * scale, 0.0, TAU, 6, Color(accent, 0.18), 8.0 * scale, true)
	draw_arc(center, 20.0 * scale, 0.0, TAU, 6, accent, 2.6 * scale, true)
	_glow_line(center + Vector2(-4, -12) * scale, center + Vector2(4, 12) * scale, 3.2 * scale)
	_glow_line(center + Vector2(5, -12) * scale, center + Vector2(-4, 12) * scale, 3.2 * scale)


func _rounded_box(border: Color, background: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(maxi(1, int(round(radius * 0.25))))
	style.set_corner_radius_all(maxi(1, int(round(radius))))
	return style


func _draw_battery(center: Vector2, scale: float) -> void:
	var body := Rect2(center + Vector2(-12, -16) * scale, Vector2(24, 30) * scale)
	draw_rect(body, Color(accent, 0.18), true)
	_glow_polyline(PackedVector2Array([
		body.position,
		body.position + Vector2(body.size.x, 0),
		body.position + Vector2(body.size.x, body.size.y),
		body.position + Vector2(0, body.size.y),
		body.position,
	]), 2.0 * scale)
	var cap := Rect2(center + Vector2(-4, -22) * scale, Vector2(8, 5) * scale)
	draw_rect(cap, accent, true)
	# 内部进度横线,2 段表示高电量档
	_glow_line(center + Vector2(-9, -7) * scale, center + Vector2(9, -7) * scale, 1.4 * scale, Color(accent, 0.65))
	_glow_line(center + Vector2(-9, 0) * scale, center + Vector2(9, 0) * scale, 1.4 * scale, Color(accent, 0.55))
	_glow_line(center + Vector2(-9, 7) * scale, center + Vector2(9, 7) * scale, 1.4 * scale, Color(accent, 0.45))
