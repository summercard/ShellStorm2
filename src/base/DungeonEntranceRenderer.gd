class_name DungeonEntranceRenderer
extends Node2D
## Replaceable ruin/bunker facade for a wilderness dungeon entrance.

var entrance_color := Color(0.72, 0.34, 0.20, 1.0)
var active := false
var _time := 0.0


func configure(color: Color) -> void:
	entrance_color = color
	queue_redraw()


func set_active(value: bool) -> void:
	active = value
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := Vector2(0, -110)
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.30, 0.35))
	draw_circle(Vector2.ZERO, 145.0, Color(0.01, 0.01, 0.015, 0.62))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-158, -232, 316, 238), Color(0.045, 0.048, 0.052, 1.0), true)
	var shell := PackedVector2Array([
		Vector2(-146, -212), Vector2(-118, -250), Vector2(-48, -266),
		Vector2(12, -254), Vector2(66, -270), Vector2(132, -230),
		Vector2(146, -28), Vector2(-146, -28),
	])
	draw_colored_polygon(shell, Color(0.12, 0.125, 0.13, 1.0))
	draw_polyline(PackedVector2Array([shell[0], shell[1], shell[2], shell[3], shell[4], shell[5]]), Color(0.33, 0.34, 0.34, 0.72), 7.0, true)

	draw_rect(Rect2(-58, -154, 116, 126), Color(0.012, 0.018, 0.024, 1.0), true)
	draw_rect(Rect2(-48, -144, 96, 116), Color(entrance_color.darkened(0.74), 1.0), true)
	draw_rect(Rect2(-52, -158, 104, 9), Color(entrance_color, 0.82), true)
	draw_line(Vector2(-48, -110), Vector2(48, -110), Color(entrance_color, 0.18), 3.0)
	draw_line(Vector2(0, -144), Vector2(0, -31), Color(entrance_color, 0.16), 3.0)

	for x in [-118.0, -86.0, 86.0, 118.0]:
		draw_rect(Rect2(x - 9, -202, 18, 160), Color(0.070, 0.075, 0.078, 1.0), true)
		draw_line(Vector2(x, -194), Vector2(x, -55), Color(0.27, 0.28, 0.28, 0.45), 3.0)
	draw_polyline(PackedVector2Array([Vector2(-132, -192), Vector2(-100, -174), Vector2(-113, -129), Vector2(-86, -95)]), Color(0.30, 0.16, 0.08, 0.88), 6.0, true)
	draw_polyline(PackedVector2Array([Vector2(138, -185), Vector2(101, -158), Vector2(119, -112), Vector2(90, -76)]), Color(0.035, 0.04, 0.045, 0.94), 5.0, true)

	for side in [-1.0, 1.0]:
		var origin := Vector2(side * 92.0, -24.0)
		draw_line(origin, origin + Vector2(side * 45.0, 34.0), Color(0.12, 0.13, 0.13, 1.0), 12.0, true)
		for i in range(3):
			var y := -188.0 + i * 38.0
			draw_line(Vector2(side * 130.0, y), Vector2(side * 104.0, y + 17), Color(entrance_color, 0.56), 6.0, true)

	var lamp_energy := 0.54 + sin(_time * 2.2) * 0.08
	if fmod(_time + absf(global_position.x) * 0.001, 8.0) < 0.18:
		lamp_energy = 0.06
	for x in [-67.0, 67.0]:
		draw_circle(Vector2(x, -164), 6.0, Color(entrance_color, lamp_energy))
		draw_circle(Vector2(x, -164), 19.0, Color(entrance_color, lamp_energy * 0.12))
	if active:
		var pulse := 0.48 + sin(_time * 3.0) * 0.14
		draw_arc(center, 165.0, 0.20, PI - 0.20, 28, Color(entrance_color, pulse), 4.0, true)
