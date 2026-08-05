class_name NeonFrameControl
extends Control
## 可复用的纯代码霓虹切角框。作为面板/卡面的装饰层，不接管鼠标输入。

@export var accent := Color(0.24, 0.88, 1.0):
	set(value):
		accent = value
		queue_redraw()
@export var corner_length := 16.0
@export var cut_size := 8.0
@export var glow_strength := 1.0
@export var scan_lines := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(color: Color, glow := 1.0, with_scan_lines := false) -> void:
	accent = color
	glow_strength = glow
	scan_lines = with_scan_lines
	queue_redraw()


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var path := PackedVector2Array([
		rect.position + Vector2(cut_size, 0),
		Vector2(rect.end.x - cut_size, rect.position.y),
		Vector2(rect.end.x, rect.position.y + cut_size),
		Vector2(rect.end.x, rect.end.y - cut_size),
		Vector2(rect.end.x - cut_size, rect.end.y),
		Vector2(rect.position.x + cut_size, rect.end.y),
		Vector2(rect.position.x, rect.end.y - cut_size),
		Vector2(rect.position.x, rect.position.y + cut_size),
		rect.position + Vector2(cut_size, 0),
	])
	draw_polyline(path, Color(accent, 0.08 * glow_strength), 10.0, true)
	draw_polyline(path, Color(accent, 0.22 * glow_strength), 5.0, true)
	draw_polyline(path, Color(accent, 0.82), 1.5, true)
	_draw_corners(rect)
	if scan_lines:
		for y in range(18, int(size.y - 10), 8):
			draw_line(Vector2(10, y), Vector2(size.x - 10, y), Color(accent, 0.025), 1.0)


func _draw_corners(rect: Rect2) -> void:
	var c := Color(accent, 0.98)
	var faint := Color(accent, 0.20 * glow_strength)
	var origins := [
		[rect.position + Vector2(cut_size + 3, 3), Vector2.RIGHT, Vector2.DOWN],
		[Vector2(rect.end.x - cut_size - 3, rect.position.y + 3), Vector2.LEFT, Vector2.DOWN],
		[Vector2(rect.position.x + cut_size + 3, rect.end.y - 3), Vector2.RIGHT, Vector2.UP],
		[rect.end - Vector2(cut_size + 3, 3), Vector2.LEFT, Vector2.UP],
	]
	for data in origins:
		var origin := data[0] as Vector2
		var horizontal := data[1] as Vector2
		var vertical := data[2] as Vector2
		draw_line(origin, origin + horizontal * corner_length, faint, 7.0, true)
		draw_line(origin, origin + vertical * corner_length, faint, 7.0, true)
		draw_line(origin, origin + horizontal * corner_length, c, 2.2, true)
		draw_line(origin, origin + vertical * corner_length, c, 2.2, true)
