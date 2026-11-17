extends Control

var segments: Array[Dictionary] = []
var _phase := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_segments(value: Array[Dictionary]) -> void:
	segments = value
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	_phase = fmod(_phase + delta * 0.45, 1.0)
	queue_redraw()

func _draw() -> void:
	for segment: Dictionary in segments:
		# 首段仍保留在原槽序查询中，实际只由 Board 根层绘制一次。
		if not bool(segment.get("render", true)):
			continue
		var points: PackedVector2Array = segment["points"]
		if points.size() < 2:
			continue
		var active := bool(segment["active"])
		if active:
			draw_polyline(points, Color(0.31, 0.66, 1.0, 0.16), 6.0, true)
		draw_polyline(points, Color(0.53, 0.78, 1.0, 0.80) if active else Color(0.65, 0.73, 0.84, 0.23), 1.5 if active else 1.0, true)
		for endpoint in [points[0], points[points.size() - 1]]:
			draw_rect(Rect2(endpoint - Vector2(2, 2), Vector2(4, 4)), UIPalette.PRISM_ACCENT if active else UIPalette.PRISM_LINE_SOFT)
		if not active or bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
			continue
		var total := 0.0
		for i in range(1, points.size()):
			total += points[i - 1].distance_to(points[i])
		var cursor := _phase * total
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var length := a.distance_to(b)
			if cursor <= length:
				var direction := (b - a).normalized()
				var head := a + direction * cursor
				var tail := head - direction * minf(cursor, 18.0)
				draw_line(tail, head, Color(0.45, 0.77, 1.0, 0.24), 7.0, true)
				draw_line(tail, head, Color(0.78, 0.94, 1.0, 1.0), 2.5, true)
				break
			cursor -= length
