class_name PlayerAvatarRenderer
extends Node2D
## 胶囊防护体玩家的模块化像素渲染器。
## 只读取 Player 语义状态；移动、碰撞、伤害和武器数值完全不依赖本节点。

const HEAD_TEXTURE: Texture2D = preload("res://assets/art/characters/player/chr_player_capsule01/components/chr_player_capsule01_head_side_v001.png")
const BODY_TEXTURE: Texture2D = preload("res://assets/art/characters/player/chr_player_capsule01/components/chr_player_capsule01_body_side_v001.png")
const HAND_TEXTURE: Texture2D = preload("res://assets/art/characters/player/chr_player_capsule01/components/chr_player_capsule01_hand_r_side_v001.png")
const SCARF_TEXTURE: Texture2D = preload("res://assets/art/characters/player/chr_player_capsule01/components/chr_player_capsule01_scarf_side_v001.png")
const HAND_SOCKET_X := 19.0
const FACING_DEADZONE := 0.15

const CRITICAL := Color("ff4d4d")
const SILENCED := Color("bc67ff")
const DASH_COLOR := Color("7ce7ff")

var _player: Node = null
var _facing := Vector2.RIGHT
var _facing_sign := 1.0
var _move_direction := Vector2.ZERO
var _pulse := 0.0
var _flash_color := Color.TRANSPARENT
var _flash_time := 0.0
var _state := "idle"
var _low_health := false
var _silenced := false
var _invincible := false

var _component_root: Node2D
var _body_sprite: Sprite2D
var _scarf_sprite: Sprite2D
var _head_sprite: Sprite2D
var _hand_root: Node2D
var _hand_sprite: Sprite2D


func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player = _find_player()
	_build_component_nodes()


func _process(delta: float) -> void:
	_pulse += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	_read_player_state()
	_update_state_transform(delta)
	_update_component_animation(delta)
	_update_component_tint()
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
		"invincible": _invincible,
		"flash_time": _flash_time,
		"scale": scale,
		"rotation": rotation,
		"pixel_assets_loaded": _pixel_assets_loaded(),
		"component_count": 4,
		"components": ["body", "scarf", "head", "hand"],
		"visible_hand_count": 1,
		"facing_sign": _facing_sign,
		"hand_position": _hand_root.position if _hand_root != null else Vector2.ZERO,
		"hand_rotation": _hand_root.rotation if _hand_root != null else 0.0,
		"hand_flipped": _hand_sprite.flip_h if _hand_sprite != null else false,
		"hand_tracks_aim": false,
	}


func _build_component_nodes() -> void:
	_component_root = Node2D.new()
	_component_root.name = "PixelComponents"
	add_child(_component_root)

	_body_sprite = _add_sprite(_component_root, "Body", BODY_TEXTURE, 1)
	_scarf_sprite = _add_sprite(_component_root, "Scarf", SCARF_TEXTURE, 2)
	_head_sprite = _add_sprite(_component_root, "Head", HEAD_TEXTURE, 3)

	_hand_root = Node2D.new()
	_hand_root.name = "Hand"
	_hand_root.z_index = 5
	_component_root.add_child(_hand_root)
	_hand_sprite = _add_sprite(_hand_root, "Sprite", HAND_TEXTURE, 0)

	_body_sprite.position = Vector2(0, 7)
	_scarf_sprite.position = Vector2(0, -8)
	_head_sprite.position = Vector2(0, -19)
	_hand_root.position = Vector2(HAND_SOCKET_X, 0)


func _add_sprite(parent: Node2D, sprite_name: String, texture: Texture2D, layer: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = true
	sprite.z_index = layer
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)
	return sprite


func _read_player_state() -> void:
	if _player == null:
		return
	if _player.has_method("get_aim_direction"):
		var direction: Vector2 = _player.call("get_aim_direction") as Vector2
		if direction.length_squared() > 0.0001:
			_facing = direction.normalized()
	if _player.has_method("get_visual_facing_sign"):
		_facing_sign = float(_player.call("get_visual_facing_sign"))
	elif absf(_facing.x) > FACING_DEADZONE:
		_facing_sign = -1.0 if _facing.x < 0.0 else 1.0
	if _player.has_method("get_presentation_state"):
		_state = str(_player.call("get_presentation_state"))
	if _player.has_method("is_low_health"):
		_low_health = bool(_player.call("is_low_health"))
	_silenced = bool(_player.get("_is_silenced"))
	_invincible = bool(_player.get("is_invincible"))
	var player_velocity = _player.get("velocity")
	if player_velocity is Vector2 and player_velocity.length_squared() > 25.0:
		_move_direction = player_velocity.normalized()
	else:
		_move_direction = Vector2.ZERO


func _update_state_transform(delta: float) -> void:
	var target_position := Vector2.ZERO
	var target_rotation := 0.0
	var target_scale := Vector2.ONE
	match _state:
		"moving":
			target_rotation = _move_direction.x * 0.045
			target_scale = Vector2(1.03, 0.98)
		"dashing":
			target_rotation = _move_direction.x * 0.11
			target_scale = Vector2(1.26, 0.8)
		"hurt":
			target_position = Vector2(-_facing.x * 4.0, 2.0)
			target_rotation = -_facing.y * 0.12
			target_scale = Vector2(0.86, 1.13)
		"locked":
			target_position = Vector2(0, 1.5)
			target_scale = Vector2(0.96, 0.96)
		"dead":
			target_position = Vector2(5, 11)
			target_rotation = 1.18
			target_scale = Vector2(0.92, 0.72)
	position = position.lerp(target_position, minf(1.0, delta * 14.0))
	rotation = lerp_angle(rotation, target_rotation, minf(1.0, delta * 12.0))
	scale = scale.lerp(target_scale, minf(1.0, delta * 16.0))


func _update_component_animation(delta: float) -> void:
	if _component_root == null:
		return
	var bob := _state_bob()
	var face_left := _facing_sign < 0.0
	_head_sprite.flip_h = face_left
	_body_sprite.flip_h = face_left
	_scarf_sprite.flip_h = face_left
	_hand_sprite.flip_h = face_left

	var body_target := Vector2(0, 7 + bob)
	var head_target := Vector2(0, -19 + bob * 0.65)
	var scarf_target := Vector2(-_facing_sign * 2.0, -8 + bob * 0.82)
	var hand_wave := sin(_pulse * TAU * (4.6 if _state == "moving" else 1.8))
	# 握持手随身体朝向在左右两个固定插槽间镜像换边，但不读取准星角度连续旋转。
	# X 直接切换，避免翻身时手穿过身体；Y 只保留轻微整体呼吸。
	var hand_target := Vector2(HAND_SOCKET_X * _facing_sign, bob * 0.55)

	_body_sprite.position = _body_sprite.position.lerp(body_target, minf(1.0, delta * 14.0))
	_head_sprite.position = _head_sprite.position.lerp(head_target, minf(1.0, delta * 16.0))
	_scarf_sprite.position = _scarf_sprite.position.lerp(scarf_target, minf(1.0, delta * 11.0))
	_scarf_sprite.rotation = lerp_angle(_scarf_sprite.rotation, -_facing.y * 0.16 + hand_wave * 0.025, minf(1.0, delta * 8.0))
	_hand_root.position = Vector2(hand_target.x, lerpf(_hand_root.position.y, hand_target.y, minf(1.0, delta * 18.0)))
	_hand_root.rotation = lerp_angle(_hand_root.rotation, 0.0, minf(1.0, delta * 20.0))


func _update_component_tint() -> void:
	var tint := Color.WHITE
	if _state == "locked":
		tint = Color(0.72, 0.76, 0.8, 1.0)
	elif _state == "dead":
		tint = Color(0.42, 0.46, 0.5, 0.92)
	elif _flash_time > 0.0:
		tint = Color(_flash_color, clampf(_flash_time / 0.16, 0.0, 1.0))
	elif _invincible and fmod(_pulse, 0.14) < 0.045:
		tint = Color(1.0, 1.0, 1.0, 0.52)
	for sprite in [_body_sprite, _scarf_sprite, _head_sprite, _hand_sprite]:
		if sprite != null:
			(sprite as Sprite2D).modulate = tint


func _state_bob() -> float:
	match _state:
		"moving": return absf(sin(_pulse * TAU * 5.4)) * -2.0
		"dashing": return 0.0
		"hurt": return sin(_pulse * TAU * 10.0) * 1.4
		"locked": return sin(_pulse * TAU * 0.9) * 0.3
		"dead": return 0.0
		_: return sin(_pulse * TAU * 1.8) * 0.75


func _draw() -> void:
	_draw_dash_streaks()
	draw_set_transform(Vector2(0.0, 24.0), 0.0, Vector2(1.45, 0.42))
	draw_circle(Vector2.ZERO, 17.0, Color(0.01, 0.02, 0.045, 0.5 if _state != "dashing" else 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_state_overlays()


func _draw_dash_streaks() -> void:
	if _state != "dashing":
		return
	var perpendicular := _facing.orthogonal()
	for i in range(4):
		var side := (float(i) - 1.5) * 6.0
		var start := -_facing * 8.0 + perpendicular * side
		var finish := start - _facing * (24.0 + float(i % 2) * 10.0)
		draw_line(start, finish, Color(DASH_COLOR.r, DASH_COLOR.g, DASH_COLOR.b, 0.48 - float(i) * 0.07), 3.0 - float(i) * 0.4, true)


func _draw_state_overlays() -> void:
	if _low_health and _state != "dead":
		var warning_alpha := 0.25 + (sin(_pulse * TAU * 2.2) * 0.5 + 0.5) * 0.3
		draw_arc(Vector2(0, 2), 29.0, 0.0, TAU, 48, Color(CRITICAL.r, CRITICAL.g, CRITICAL.b, warning_alpha), 2.0, true)
	if _state == "locked":
		draw_arc(Vector2(0, 5), 27.0, -PI * 0.9, PI * 0.15, 32, Color(0.95, 0.72, 0.25, 0.55), 2.0, true)
	if _silenced and _state != "dead":
		var jam_alpha := 0.24 + absf(sin(_pulse * 12.0)) * 0.28
		draw_arc(Vector2.ZERO, 31.0, 0.3, PI * 1.6, 32, Color(SILENCED.r, SILENCED.g, SILENCED.b, jam_alpha), 2.0, true)


func _pixel_assets_loaded() -> bool:
	return HEAD_TEXTURE != null and BODY_TEXTURE != null and HAND_TEXTURE != null and SCARF_TEXTURE != null


func _find_player() -> Node:
	var node: Node = get_parent()
	for _i in 5:
		if node == null:
			return null
		if node.is_in_group("player") and node.has_method("get_aim_direction"):
			return node
		node = node.get_parent()
	return null
