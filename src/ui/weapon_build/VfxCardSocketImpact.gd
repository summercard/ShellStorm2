extends Control

## 独立界面特效：整板短闪、枪身与落巢局部脉冲及方块散射，不接收输入。
var _progress := 1.0
var _origin := Vector2.ZERO
var _weapon_anchor := Vector2.INF
var _reduced := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func play(origin: Vector2, reduced_motion := false, weapon_anchor: Vector2 = Vector2.INF) -> void:
	_origin = origin
	_weapon_anchor = weapon_anchor
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
	# 整板只短闪；不再画贯穿高度的扫描线或包含底边的整板描框。
	var impact := pow(1.0 - _progress, 3.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.83, 1.0, impact * (0.06 if _reduced else 0.23)))
	if _reduced:
		return
	# 能量仅在枪身出口与落巢附近横向传递，不横穿其他卡面、文字和弹种模块。
	if _weapon_anchor.is_finite():
		var departure := minf(_progress * 2.0, 1.0)
		var weapon_head := _weapon_anchor + Vector2(lerpf(0.0, 30.0, departure), 0)
		var departure_tint := Color(tint, alpha * (1.0 - departure))
		draw_line(weapon_head - Vector2(18, 0), weapon_head, departure_tint, 3.0, true)
	var arrival := clampf((_progress - 0.18) / 0.82, 0.0, 1.0)
	var socket_head := _origin - Vector2(lerpf(30.0, 0.0, arrival), 0)
	draw_line(socket_head - Vector2(12, 0), socket_head, tint, 3.0, true)
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
