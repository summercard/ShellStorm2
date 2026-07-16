class_name PlayerAvatarRenderer
extends Node2D
## 语义化玩家表现挂点。只读取 Player 状态，不改变碰撞、移动、武器或伤害数据。

const OUTLINE := Color("101a2b")
const ARMOR_DARK := Color("1c3853")
const ARMOR_MID := Color("3672a5")
const ARMOR_LIGHT := Color("7cc8ee")
const VISOR := Color("c5f5ff")
const ACCENT := Color("f0c55b")
const CRITICAL := Color("ff4d4d")
const SILENCED := Color("bc67ff")

var _player: Node = null
var _facing := Vector2.RIGHT
var _move_direction := Vector2.ZERO
var _pulse := 0.0
var _flash_color := Color.TRANSPARENT
var _flash_time := 0.0
var _state := "idle"
var _low_health := false
var _silenced := false


func _ready() -> void:
	z_index = 3
	_player = _find_player()


func _process(delta: float) -> void:
	_pulse += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player != null:
		if _player.has_method("get_aim_direction"):
			var direction: Vector2 = _player.call("get_aim_direction") as Vector2
			if direction.length_squared() > 0.0001:
				_facing = direction.normalized()
		if _player.has_method("get_presentation_state"):
			_state = str(_player.call("get_presentation_state"))
		if _player.has_method("is_low_health"):
			_low_health = bool(_player.call("is_low_health"))
		_silenced = bool(_player.get("_is_silenced"))
		var player_velocity = _player.get("velocity")
		if player_velocity is Vector2 and player_velocity.length_squared() > 25.0:
			_move_direction = player_velocity.normalized()
		else:
			_move_direction = Vector2.ZERO
	_update_state_transform(delta)
	queue_redraw()


func flash_damage() -> void:
	_flash_color = Color(1.0, 0.24, 0.2, 0.98)
	_flash_time = 0.16


func flash_heal() -> void:
	_flash_color = Color(0.3, 1.0, 0.65, 0.92)
	_flash_time = 0.2


func get_visual_state_snapshot() -> Dictionary:
	return {
		"state": _state,
		"low_health": _low_health,
		"silenced": _silenced,
		"flash_time": _flash_time,
		"scale": scale,
		"rotation": rotation,
	}


func _update_state_transform(delta: float) -> void:
	var target_position := Vector2.ZERO
	var target_rotation := 0.0
	var target_scale := Vector2.ONE
	match _state:
		"moving":
			target_rotation = _move_direction.x * 0.055
			target_scale = Vector2(1.03, 0.98)
		"dashing":
			target_rotation = _move_direction.angle() if _move_direction != Vector2.ZERO else 0.0
			target_scale = Vector2(1.3, 0.76)
		"hurt":
			target_position = Vector2(-_facing.x * 4.0, 2.0)
			target_rotation = -_facing.y * 0.12
			target_scale = Vector2(0.86, 1.13)
		"locked":
			target_position = Vector2(0, 1.5)
			target_scale = Vector2(0.96, 0.96)
		"dead":
			target_position = Vector2(5, 12)
			target_rotation = 1.28
			target_scale = Vector2(0.92, 0.7)
	position = position.lerp(target_position, minf(1.0, delta * 14.0))
	rotation = lerp_angle(rotation, target_rotation, minf(1.0, delta * (18.0 if _state == "dashing" else 10.0)))
	scale = scale.lerp(target_scale, minf(1.0, delta * 16.0))


func _draw() -> void:
	var bob := _state_bob()
	_draw_dash_streaks(bob)
	# 接地阴影与状态位移分层，确保任意程序地面都能读出脚点。
	draw_set_transform(Vector2(0.0, 18.0 + bob), 0.0, Vector2(1.4, 0.42))
	draw_circle(Vector2.ZERO, 18.0, Color(0.01, 0.02, 0.045, 0.5 if _state != "dashing" else 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_boots(bob)
	_draw_power_pack(bob)
	_draw_suit(bob)
	_draw_helmet(bob)

	if _state != "dead":
		draw_circle(_facing.rotated(-rotation) * 18.0 + Vector2(0, bob), 2.5, ACCENT)
	_draw_state_overlays(bob)


func _state_bob() -> float:
	match _state:
		"moving": return absf(sin(_pulse * TAU * 5.4)) * -2.2
		"dashing": return 0.0
		"hurt": return sin(_pulse * TAU * 10.0) * 1.4
		"locked": return sin(_pulse * TAU * 0.9) * 0.35
		"dead": return 0.0
		_: return sin(_pulse * TAU * 1.8) * 0.8


func _draw_dash_streaks(bob: float) -> void:
	if _state != "dashing":
		return
	var phase := fmod(_pulse * 8.0, 1.0)
	for i in range(4):
		var y := (float(i) - 1.5) * 7.0
		var length := 30.0 + float(i % 2) * 13.0 + phase * 8.0
		draw_line(Vector2(-10, y + bob), Vector2(-length, y + bob), Color(0.28, 0.86, 1.0, 0.5 - float(i) * 0.07), 3.5 - float(i) * 0.45, true)


func _draw_boots(bob: float) -> void:
	var gait: float = sin(_pulse * TAU * 5.4) if _state == "moving" else 0.0
	for side: float in [-1.0, 1.0]:
		var x: float = -6.0 + side * gait * 3.0
		var y: float = 17.0 + bob + side * gait * 1.8
		draw_rect(Rect2(x - 4.5, y - 2.0, 9.0, 7.0), OUTLINE, true)
		draw_rect(Rect2(x - 3.0, y - 1.0, 6.0, 4.5), ARMOR_DARK, true)
		if _state == "moving":
			draw_line(Vector2(x - 5.0, y + 6.0), Vector2(x - 11.0 - absf(gait) * 4.0, y + 7.0), Color(0.28, 0.68, 0.78, 0.35), 1.5, true)


func _draw_power_pack(bob: float) -> void:
	draw_circle(Vector2(-12.0, 7.0 + bob), 8.0, OUTLINE)
	draw_circle(Vector2(-12.0, 7.0 + bob), 5.8, ARMOR_DARK)
	var exhaust := Color(0.25, 0.9, 1.0, 0.95 if _state == "dashing" else 0.72)
	draw_circle(Vector2(-14.0, 8.0 + bob), 2.5 if _state == "dashing" else 2.0, exhaust)
	draw_circle(Vector2(-8.0, 8.0 + bob), 2.0 if _state == "dashing" else 1.5, exhaust.darkened(0.08))


func _draw_suit(bob: float) -> void:
	var suit := PackedVector2Array([
		Vector2(-15, -4 + bob), Vector2(-10, -16 + bob), Vector2(8, -16 + bob),
		Vector2(16, -5 + bob), Vector2(14, 15 + bob), Vector2(6, 21 + bob),
		Vector2(-9, 19 + bob), Vector2(-17, 10 + bob),
	])
	draw_colored_polygon(suit, OUTLINE)
	var inner_color := ARMOR_MID.darkened(0.28) if _state == "locked" else ARMOR_MID
	var inner_suit := PackedVector2Array([
		Vector2(-12, -3 + bob), Vector2(-8, -13 + bob), Vector2(6, -13 + bob),
		Vector2(12, -4 + bob), Vector2(10, 12 + bob), Vector2(4, 17 + bob),
		Vector2(-7, 16 + bob), Vector2(-13, 8 + bob),
	])
	draw_colored_polygon(inner_suit, inner_color)
	draw_rect(Rect2(-8, 2 + bob, 16, 9), ARMOR_LIGHT.darkened(0.24 if _state == "locked" else 0.0), true)
	draw_rect(Rect2(-6, 4 + bob, 12, 5), Color(0.15, 0.34, 0.53, 1.0), true)
	var core_color := CRITICAL if _low_health else ACCENT
	var core_radius := 2.1 + (sin(_pulse * TAU * 2.4) * 0.7 if _low_health else 0.0)
	draw_circle(Vector2(0, 6.5 + bob), core_radius, core_color)


func _draw_helmet(bob: float) -> void:
	var local_facing_angle := _facing.angle() - rotation
	draw_set_transform(Vector2(-1.0, -16.0 + bob), local_facing_angle, Vector2.ONE)
	draw_circle(Vector2.ZERO, 13.0, OUTLINE)
	draw_circle(Vector2.ZERO, 10.6, ARMOR_LIGHT.darkened(0.32 if _state == "locked" else 0.0))
	var visor_color := Color(0.04, 0.075, 0.09) if _state == "dead" else VISOR
	draw_circle(Vector2(3.0, 0.0), 8.0, visor_color)
	draw_circle(Vector2(5.0, -1.2), 5.7, Color(0.08, 0.22, 0.34, 1.0) if _state != "dead" else Color(0.025, 0.035, 0.04))
	if _state != "dead":
		draw_line(Vector2(1.0, -7.3), Vector2(7.0, -7.3), Color(0.82, 0.98, 1.0, 0.9), 1.2, true)
	if _silenced:
		for y in [-5.0, 0.0, 5.0]:
			var jitter := sin(_pulse * 38.0 + y) * 3.0
			draw_line(Vector2(-5 + jitter, y), Vector2(12 + jitter, y), Color(SILENCED.r, SILENCED.g, SILENCED.b, 0.62), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_state_overlays(bob: float) -> void:
	if _low_health and _state != "dead":
		var warning_alpha := 0.28 + (sin(_pulse * TAU * 2.2) * 0.5 + 0.5) * 0.28
		draw_arc(Vector2(0, bob), 27.0, 0.0, TAU, 48, Color(CRITICAL.r, CRITICAL.g, CRITICAL.b, warning_alpha), 2.0, true)
	if _state == "locked":
		draw_arc(Vector2(0, 4 + bob), 25.0, -PI * 0.9, PI * 0.15, 32, Color(0.95, 0.72, 0.25, 0.55), 2.0, true)
		draw_arc(Vector2(0, 4 + bob), 25.0, PI * 0.1, PI * 1.15, 32, Color(0.95, 0.72, 0.25, 0.28), 2.0, true)
	if _silenced and _state != "dead":
		var jam_alpha := 0.24 + absf(sin(_pulse * 12.0)) * 0.28
		draw_arc(Vector2(0, bob), 30.0, 0.3, PI * 1.6, 32, Color(SILENCED.r, SILENCED.g, SILENCED.b, jam_alpha), 2.0, true)
	if _flash_time > 0.0:
		draw_circle(Vector2(0, bob), 25.0, Color(_flash_color, clampf(_flash_time / 0.16, 0.0, 1.0)))


func _find_player() -> Node:
	var node: Node = get_parent()
	for _i in 4:
		if node == null:
			return null
		if node.is_in_group("player") and node.has_method("get_aim_direction"):
			return node
		node = node.get_parent()
	return null
