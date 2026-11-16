extends Control

## 独立界面特效：单次整体扫描脉冲与方块散射，不接收输入。
var _progress := 1.0
var _origin := Vector2.ZERO
var _reduced := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func play(origin: Vector2, reduced_motion := false) -> void:
	_origin = origin
	_reduced = reduced_motion
	_progress = 0.0
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_set_progress, 0.0, 1.0, 0.12 if reduced_motion else 0.48)
	await tween.finished

func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()

func _draw() -> void:
	if _progress >= 1.0:
		return
	var alpha := (1.0 - _progress) * 0.65
	var tint := Color(0.64, 0.91, 1.0, alpha)
	# 成功落巢先给整板一次有力短闪，随后扫描衰减；不移动布局或改变命中区。
	var impact := pow(1.0 - _progress, 3.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.83, 1.0, impact * (0.06 if _reduced else 0.23)))
	if not _reduced:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0.78, 0.95, 1.0, impact * 0.92), false, 2.0)
	var scan := size.x * _progress
	draw_line(Vector2(scan, 0), Vector2(scan, size.y), tint, 3.0)
	if _reduced:
		return
	var radius := lerpf(4.0, 66.0, 1.0 - pow(1.0 - _progress, 3.0))
	for i in 20:
		var angle := TAU * float(i) / 20.0
		var direction := Vector2(cos(angle), sin(angle))
		var point := _origin + direction * radius * (0.72 + float(i % 3) * 0.19)
		var width := 2.0 + float(i % 3)
		draw_rect(Rect2(point - Vector2.ONE * width * 0.5, Vector2.ONE * width), tint)
	var half := Vector2(23, 31) * (1.0 + _progress * 0.5)
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var corner := _origin + half * Vector2(sign_x, sign_y)
			draw_line(corner, corner - Vector2(sign_x * 10, 0), tint, 1.5)
			draw_line(corner, corner - Vector2(0, sign_y * 10), tint, 1.5)
