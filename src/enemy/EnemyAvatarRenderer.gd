class_name EnemyAvatarRenderer
extends Node2D

## 六类基础怪物的可替换程序化渲染层。
## 本节点只读取 EnemyBase 状态，不参与伤害、AI、掉落或存档。

var _enemy: CharacterBody2D = null
var _shape_type: int = EnemyShape.ShapeType.CHASER
var _profile: Dictionary = EnemyShape.get_profile(EnemyShape.ShapeType.CHASER)
var _base_color := Color(0.9, 0.3, 0.25, 1.0)
var _external_scale := 1.0
var _time := 0.0
var _facing_angle := 0.0
var _hit_phase := 0.0
var _hit_direction := Vector2.ZERO
var _death_phase := 0.0
var _telegraph_kind := ""
var _telegraph_remaining := 0.0
var _telegraph_total := 0.0
var _telegraph_radius := 0.0


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D
	queue_redraw()


func configure(shape_type: int, color: Color, external_scale: float = 1.0) -> void:
	_shape_type = shape_type
	_profile = EnemyShape.get_profile(shape_type)
	_base_color = color
	_external_scale = maxf(0.45, external_scale)
	_apply_base_scale()
	queue_redraw()


func play_hit(is_crit: bool, hit_direction: Vector2 = Vector2.ZERO) -> void:
	_hit_phase = 1.35 if is_crit else 1.0
	_hit_direction = hit_direction.normalized()
	queue_redraw()


func play_telegraph(kind: String, duration: float, radius: float = 0.0) -> void:
	_telegraph_kind = kind
	_telegraph_total = maxf(0.05, duration)
	_telegraph_remaining = _telegraph_total
	_telegraph_radius = maxf(0.0, radius)
	queue_redraw()


func cancel_telegraph() -> void:
	_telegraph_kind = ""
	_telegraph_remaining = 0.0
	_telegraph_total = 0.0
	_telegraph_radius = 0.0
	queue_redraw()


func play_death() -> void:
	_death_phase = 1.0
	cancel_telegraph()
	queue_redraw()


func get_silhouette_signature() -> String:
	return str(_profile.get("silhouette", "unknown"))


func get_profile_snapshot() -> Dictionary:
	return _profile.duplicate(true)


func is_telegraphing() -> bool:
	return _telegraph_remaining > 0.0


func get_telegraph_kind() -> String:
	return _telegraph_kind


func get_hit_phase() -> float:
	return _hit_phase


func _process(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	var speed_ratio := clampf(_enemy.velocity.length() / maxf(1.0, float(_enemy.get("speed"))), 0.0, 1.8)
	_time += delta * (float(_profile.get("gait_frequency", 3.0)) * (0.45 + speed_ratio * 0.75))
	if _hit_phase > 0.0:
		_hit_phase = maxf(0.0, _hit_phase - delta * 7.0)
	if _death_phase > 0.0:
		_death_phase = maxf(0.0, _death_phase - delta * 2.8)
	if _telegraph_remaining > 0.0:
		_telegraph_remaining = maxf(0.0, _telegraph_remaining - delta)
		if _telegraph_remaining <= 0.0:
			_telegraph_kind = ""
			_telegraph_radius = 0.0

	_update_facing(delta)
	_update_body_motion(speed_ratio)
	queue_redraw()


func _update_facing(delta: float) -> void:
	var direction := _enemy.velocity.normalized()
	var player_ref = _enemy.get("player_ref")
	if _shape_type == EnemyShape.ShapeType.RANGED and player_ref is Node2D and is_instance_valid(player_ref):
		direction = (player_ref.global_position - _enemy.global_position).normalized()
	if direction.length_squared() > 0.01 and _shape_type != EnemyShape.ShapeType.SUMMONER:
		_facing_angle = lerp_angle(_facing_angle, direction.angle(), minf(1.0, delta * 10.0))
	rotation = _facing_angle


func _update_body_motion(speed_ratio: float) -> void:
	var base := float(_profile.get("visual_scale", 1.0)) * _external_scale
	var squash := sin(_time) * 0.035 * speed_ratio
	match _shape_type:
		EnemyShape.ShapeType.CHASER:
			position.y = absf(sin(_time)) * -2.8 * speed_ratio
			scale = Vector2(base * (1.0 + squash), base * (1.0 - squash))
		EnemyShape.ShapeType.RANGED:
			position.y = sin(_time * 0.72) * 4.0
			scale = Vector2(base * (1.0 - squash * 0.4), base * (1.0 + squash * 0.5))
		EnemyShape.ShapeType.SUMMONER:
			position.y = sin(_time * 0.48) * 3.0
			rotation = sin(_time * 0.18) * 0.06
			scale = Vector2.ONE * base * (1.0 + sin(_time * 0.55) * 0.025)
		EnemyShape.ShapeType.TANK:
			position.y = absf(sin(_time * 0.55)) * -1.4 * speed_ratio
			scale = Vector2(base * (1.0 + squash * 0.28), base * (1.0 - squash * 0.22))
		EnemyShape.ShapeType.BOMBER:
			var danger_rate := 1.0
			if bool(_enemy.get("_bomber_charging")):
				danger_rate = 2.8
			var pulse := sin(_time * danger_rate) * (0.05 if danger_rate > 1.0 else 0.025)
			position.y = absf(sin(_time * 0.75)) * -4.0 * speed_ratio
			scale = Vector2.ONE * base * (1.0 + pulse)
		EnemyShape.ShapeType.TRAPPER:
			var emerged := bool(_enemy.get("_triggered")) or bool(_enemy.get("_trapper_revealing"))
			position.y = 0.0 if emerged else 8.0
			scale = Vector2(base * (1.0 + squash * 0.4), base * (0.72 if not emerged else 1.0 - squash * 0.3))
	if _hit_phase > 0.0:
		var hit_strength := minf(1.0, _hit_phase)
		scale *= Vector2(0.84 + hit_strength * 0.04, 1.12 + hit_strength * 0.08)


func _apply_base_scale() -> void:
	var base := float(_profile.get("visual_scale", 1.0)) * _external_scale
	scale = Vector2.ONE * base


func _draw() -> void:
	var color := _current_color()
	var dark := color.darkened(0.55)
	var mid := color.darkened(0.24)
	var bright := color.lightened(0.22)
	var extent := float(_profile.get("visual_extent", 30.0)) / maxf(0.5, float(_profile.get("visual_scale", 1.0)))
	_draw_shadow(extent)
	match _shape_type:
		EnemyShape.ShapeType.CHASER:
			_draw_chaser(color, dark, bright)
		EnemyShape.ShapeType.RANGED:
			_draw_ranged(color, dark, bright)
		EnemyShape.ShapeType.SUMMONER:
			_draw_summoner(color, dark, mid, bright)
		EnemyShape.ShapeType.TANK:
			_draw_tank(color, dark, mid, bright)
		EnemyShape.ShapeType.BOMBER:
			_draw_bomber(color, dark, bright)
		EnemyShape.ShapeType.TRAPPER:
			_draw_trapper(color, dark, bright)
	_draw_status_rings(extent, bright)
	if _death_phase > 0.0:
		_draw_death_fragments(color, extent)


func _current_color() -> Color:
	if _enemy != null and is_instance_valid(_enemy):
		var source = _enemy.get_node_or_null("Shape") as Polygon2D
		if source != null:
			var color: Color = source.color
			color.r *= source.modulate.r
			color.g *= source.modulate.g
			color.b *= source.modulate.b
			color.a *= source.modulate.a
			return color
	return _base_color


func _draw_shadow(extent: float) -> void:
	var points := PackedVector2Array()
	for i in range(25):
		var angle := TAU * float(i) / 24.0
		points.append(Vector2(cos(angle) * extent * 0.76, sin(angle) * extent * 0.24 + extent * 0.62))
	draw_colored_polygon(points, Color(0.0, 0.015, 0.02, 0.68))


func _draw_chaser(color: Color, dark: Color, bright: Color) -> void:
	var stride := sin(_time) * 3.0
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		draw_line(Vector2(-10 + stride * side, side * 8), Vector2(-19 - stride * side, side * 15), dark, 5.0, true)
		draw_line(Vector2(8 - stride * side, side * 8), Vector2(2 + stride * side, side * 16), dark, 5.0, true)
	var body := PackedVector2Array([
		Vector2(-23, -12), Vector2(9, -14), Vector2(25, -8), Vector2(30, 0),
		Vector2(25, 8), Vector2(9, 14), Vector2(-23, 12), Vector2(-29, 0),
	])
	draw_colored_polygon(body, dark)
	draw_polyline(_closed(body), color, 4.0, true)
	var head := PackedVector2Array([Vector2(5, -12), Vector2(27, -8), Vector2(32, 0), Vector2(27, 8), Vector2(5, 12), Vector2(-1, 0)])
	draw_colored_polygon(head, color)
	draw_polyline(_closed(head), bright, 2.5, true)
	# 双獠牙与前向眼点让轮廓天生指向追击方向。
	for side in [-1.0, 1.0]:
		var tusk := PackedVector2Array([Vector2(23, side * 7), Vector2(37, side * 12), Vector2(29, side * 3)])
		draw_colored_polygon(tusk, Color(0.82, 0.84, 0.72))
	draw_circle(Vector2(20, -5), 2.7, Color(1.0, 0.78, 0.22))


func _draw_ranged(color: Color, dark: Color, bright: Color) -> void:
	var sway := sin(_time * 0.72) * 2.5
	draw_line(Vector2(-13, -1), Vector2(-22, 15 + sway), dark, 6.0, true)
	draw_line(Vector2(-6, 2), Vector2(-8, 20 - sway), dark, 6.0, true)
	draw_line(Vector2(-18, 16 + sway), Vector2(-28, 22), bright.darkened(0.25), 4.0, true)
	draw_line(Vector2(-8, 20 - sway), Vector2(1, 24), bright.darkened(0.25), 4.0, true)
	var cap := PackedVector2Array([
		Vector2(-24, -4), Vector2(-14, -18), Vector2(4, -21), Vector2(21, -13),
		Vector2(29, 0), Vector2(18, 11), Vector2(-3, 14), Vector2(-22, 7),
	])
	draw_colored_polygon(cap, dark)
	draw_polyline(_closed(cap), color, 4.0, true)
	# 三叶孢子炮口。
	for i in range(3):
		var angle := (float(i) - 1.0) * 0.48
		var dir := Vector2.RIGHT.rotated(angle)
		draw_line(Vector2(4, 0), dir * 25.0, color.lightened(float(i) * 0.05), 7.0, true)
		draw_circle(dir * 25.0, 4.2, bright)
	draw_circle(Vector2(4, 0), 8.0, Color(0.05, 0.08, 0.1))
	draw_circle(Vector2(5, 0), 4.0, bright)
	if _telegraph_kind.begins_with("ranged"):
		var phase := _telegraph_phase()
		draw_line(Vector2(12, 0), Vector2(72, 0), Color(bright.r, bright.g, bright.b, 0.2 + phase * 0.6), 2.0 + phase * 2.0, true)


func _draw_summoner(color: Color, dark: Color, mid: Color, bright: Color) -> void:
	var shell := EnemyShape.make_polygon(EnemyShape.ShapeType.TANK, 25.0)
	draw_colored_polygon(shell, dark)
	draw_polyline(_closed(shell), color, 4.5, true)
	var inner := EnemyShape.make_polygon(EnemyShape.ShapeType.TANK, 18.0)
	draw_colored_polygon(inner, mid)
	for row in [-1, 0, 1]:
		for column in [-1, 0, 1]:
			if abs(row) + abs(column) > 1:
				continue
			var hole := Vector2(column * 9.0, row * 8.0)
			draw_circle(hole, 4.4, Color(0.035, 0.045, 0.04))
			draw_arc(hole, 4.4, 0.0, TAU, 18, bright.darkened(0.32), 1.5, true)
	var orbit_speed := 1.0 + (2.0 if _telegraph_kind == "summon" else 0.0)
	for i in range(3):
		var angle := _time * 0.32 * orbit_speed + TAU * float(i) / 3.0
		var satellite := Vector2.from_angle(angle) * 34.0
		draw_circle(satellite, 5.5, dark)
		draw_circle(satellite, 3.2, bright)


func _draw_tank(color: Color, dark: Color, mid: Color, bright: Color) -> void:
	var stomp := sin(_time * 0.55) * 2.0
	for side in [-1.0, 1.0]:
		draw_line(Vector2(-12 + stomp * side, side * 15), Vector2(-20 - stomp * side, side * 25), dark, 9.0, true)
		draw_line(Vector2(8 - stomp * side, side * 15), Vector2(3 + stomp * side, side * 27), dark, 9.0, true)
	var shell := PackedVector2Array([
		Vector2(-31, -19), Vector2(-10, -28), Vector2(18, -24), Vector2(31, -13),
		Vector2(34, 13), Vector2(18, 24), Vector2(-10, 28), Vector2(-31, 19), Vector2(-38, 0),
	])
	draw_colored_polygon(shell, dark)
	draw_polyline(_closed(shell), color, 5.0, true)
	var inner := PackedVector2Array([Vector2(-22, -14), Vector2(4, -21), Vector2(22, -12), Vector2(24, 12), Vector2(4, 20), Vector2(-22, 14), Vector2(-29, 0)])
	draw_colored_polygon(inner, mid)
	draw_polyline(_closed(inner), color.lightened(0.08), 3.0, true)
	# 前缘盾板拥有独立的方形剪影。
	var shield := PackedVector2Array([Vector2(20, -24), Vector2(38, -18), Vector2(42, 0), Vector2(38, 18), Vector2(20, 24), Vector2(13, 0)])
	draw_colored_polygon(shield, Color(0.075, 0.11, 0.14))
	draw_polyline(_closed(shield), bright, 4.0, true)
	draw_line(Vector2(25, -12), Vector2(25, 12), color, 3.0, true)
	draw_circle(Vector2(-9, -6), 3.0, Color(1.0, 0.72, 0.22))


func _draw_bomber(color: Color, dark: Color, bright: Color) -> void:
	draw_circle(Vector2.ZERO, 25.0, dark)
	draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 48, color, 5.0, true)
	draw_circle(Vector2(-4, -3), 17.0, color.darkened(0.18))
	# 不对称瘿包与裂纹传达膀胀、即将破裂。
	draw_circle(Vector2(-18, -14), 7.0, mid_color(dark, color))
	draw_circle(Vector2(-21, 11), 5.0, mid_color(dark, color))
	for angle in [-1.5, -0.45, 0.48, 1.42, 2.5]:
		var start := Vector2.from_angle(angle) * 7.0
		var end := Vector2.from_angle(angle) * 20.0
		draw_line(start, end, bright.darkened(0.12), 2.2, true)
	draw_circle(Vector2(3, 0), 7.0 + sin(_time * 1.4) * 1.0, Color(1.0, 0.72, 0.15))
	draw_circle(Vector2(3, 0), 3.4, Color(1.0, 0.94, 0.58))


func _draw_trapper(color: Color, dark: Color, bright: Color) -> void:
	var emerged := true
	if _enemy != null:
		emerged = bool(_enemy.get("_triggered")) or bool(_enemy.get("_trapper_revealing"))
	var mound := PackedVector2Array([Vector2(-31, 13), Vector2(-23, 1), Vector2(-7, -5), Vector2(10, -4), Vector2(28, 5), Vector2(34, 13)])
	draw_colored_polygon(mound, Color(0.07, 0.065, 0.055))
	draw_polyline(mound, color.darkened(0.38), 4.0, true)
	var rise := 0.0 if emerged else 9.0
	for i in range(3):
		var x := -13.0 + float(i) * 14.0
		var height := 27.0 + (8.0 if i == 1 else 0.0)
		var spike := PackedVector2Array([Vector2(x - 8, 8), Vector2(x + 2, -height + rise), Vector2(x + 9, 8)])
		draw_colored_polygon(spike, dark)
		draw_polyline(_closed(spike), color if emerged else color.darkened(0.42), 3.0, true)
	if emerged:
		draw_circle(Vector2(-3, 2), 6.0, Color(0.035, 0.04, 0.035))
		draw_circle(Vector2(-2, 1), 2.8, bright)


func _draw_status_rings(extent: float, bright: Color) -> void:
	if _enemy != null and bool(_enemy.get("_is_elite")):
		draw_arc(Vector2.ZERO, extent * 1.02, 0.0, TAU, 48, Color(1.0, 0.76, 0.2, 0.62), 2.5, true)
	if _telegraph_remaining <= 0.0:
		return
	var phase := _telegraph_phase()
	var pulse := 0.55 + sin(_time * 3.0) * 0.2
	var warning := Color(1.0, 0.28, 0.12, pulse)
	var radius := extent * (1.18 + phase * 0.12)
	if _telegraph_radius > 0.0:
		radius = _telegraph_radius / maxf(0.5, scale.x)
	draw_arc(Vector2.ZERO, radius, -PI * 0.92, PI * 0.92, 72, warning, 2.5 + phase * 2.0, true)
	draw_arc(Vector2.ZERO, extent * (0.82 + phase * 0.18), 0.0, TAU, 40, Color(bright.r, bright.g, bright.b, 0.28 + phase * 0.5), 2.0, true)


func _draw_death_fragments(color: Color, extent: float) -> void:
	var spread := (1.0 - _death_phase) * extent * 1.4
	for i in range(7):
		var angle := TAU * float(i) / 7.0 + 0.2
		var pos := Vector2.from_angle(angle) * spread
		draw_circle(pos, 2.0 + float(i % 3), Color(color.r, color.g, color.b, _death_phase))


func _telegraph_phase() -> float:
	if _telegraph_total <= 0.0:
		return 0.0
	return 1.0 - clampf(_telegraph_remaining / _telegraph_total, 0.0, 1.0)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func mid_color(a: Color, b: Color) -> Color:
	return a.lerp(b, 0.45)
