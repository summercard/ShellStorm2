class_name BaseFacilityRenderer
extends Node2D
## Replaceable code-native facade for a base facility. Gameplay remains on the
## Area2D parent; this node only renders the battered shelter and focus state.

var facade_color := Color(0.28, 0.55, 0.78, 1.0)
var active := false
var _time := 0.0


func configure(color: Color) -> void:
	facade_color = color
	queue_redraw()


func set_active(value: bool) -> void:
	active = value
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if active:
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 58), 0.0, Vector2(1.22, 0.36))
	draw_circle(Vector2.ZERO, 105.0, Color(0.01, 0.015, 0.02, 0.52))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-120, -72, 240, 148), Color(0.055, 0.065, 0.075, 1.0), true)
	draw_rect(Rect2(-114, -66, 228, 136), Color(0.13, 0.15, 0.16, 1.0), true)

	var roof := PackedVector2Array([
		Vector2(-126, -70), Vector2(-84, -92), Vector2(38, -88),
		Vector2(82, -75), Vector2(125, -78), Vector2(112, -58), Vector2(-116, -55),
	])
	draw_colored_polygon(roof, Color(0.085, 0.095, 0.10, 1.0))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[4]]), Color(0.30, 0.33, 0.34, 0.72), 4.0, true)

	draw_rect(Rect2(-38, -22, 76, 92), Color(0.025, 0.034, 0.042, 1.0), true)
	draw_rect(Rect2(-31, -15, 62, 85), Color(facade_color.darkened(0.60), 1.0), true)
	draw_line(Vector2(0, -12), Vector2(0, 68), Color(0.36, 0.39, 0.40, 0.55), 3.0)
	draw_rect(Rect2(-78, -48, 156, 26), Color(0.025, 0.035, 0.045, 0.96), true)
	draw_rect(Rect2(-72, -43, 144, 4), Color(facade_color, 0.72), true)
	for x in [-93.0, 83.0]:
		draw_rect(Rect2(x, -15, 14, 48), Color(0.055, 0.06, 0.065, 1.0), true)
		for y in range(-10, 28, 9):
			draw_line(Vector2(x + 2, y), Vector2(x + 12, y), Color(0.28, 0.29, 0.28, 0.56), 2.0)
	draw_polyline(PackedVector2Array([Vector2(-110, -46), Vector2(-84, 8), Vector2(-100, 62)]), Color(0.04, 0.045, 0.05, 0.9), 4.0, true)

	for i in range(5):
		var x := -106.0 + i * 18.0
		draw_line(Vector2(x, 56), Vector2(x + 14, 68), Color(0.50, 0.31, 0.10, 0.56), 5.0, true)
	var lamp_alpha := 0.72 + sin(_time * 2.4) * 0.08
	draw_circle(Vector2(66, -34), 5.0, Color(facade_color, lamp_alpha))
	draw_circle(Vector2(66, -34), 13.0, Color(facade_color, 0.10))
	if active:
		var pulse := 0.58 + sin(_time * 3.5) * 0.12
		draw_rect(Rect2(-124, -80, 248, 158), Color(facade_color, pulse), false, 3.0)

