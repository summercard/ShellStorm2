class_name PlayerAvatar3D
extends Node3D
## 胶囊防护体的模块化 3D 表现层。
## CharacterBody3D 负责移动/碰撞，VisualRoot 负责瞄准朝向，组件节点只负责状态动态。

@onready var visual_root: Node3D = $VisualRoot
@onready var body: Node3D = $VisualRoot/Body
@onready var head: Node3D = $VisualRoot/Head
@onready var scarf: Node3D = $VisualRoot/Scarf
@onready var hand: Node3D = $VisualRoot/Hand
@onready var weapon_socket: Marker3D = $VisualRoot/WeaponSocket
@onready var dash_trail: MeshInstance3D = $VisualRoot/StateVFX/DashTrail
@onready var lock_ring: MeshInstance3D = $VisualRoot/StateVFX/LockRing
@onready var low_health_ring: MeshInstance3D = $VisualRoot/StateVFX/LowHealthRing
@onready var reload_progress_root: Node3D = $ReloadProgress3D
@onready var reload_progress_track: MeshInstance3D = $ReloadProgress3D/Track
@onready var reload_progress_fill: MeshInstance3D = $ReloadProgress3D/Fill

var _player: Node = null
var _elapsed := 0.0
var _state := "idle"
var _base_positions: Dictionary = {}
var _base_scales: Dictionary = {}
var _base_colors: Dictionary = {}
var _materials: Dictionary = {}
var _locomotion_cycle := 0.0
var _moving_animation_active := false
var _reload_animation_active := false
var _reload_progress := 0.0
var _reload_offset := Vector3.ZERO
var _reload_rotation := Vector3.ZERO

const RELOAD_FILL_WIDTH := 1.06


func _ready() -> void:
	_player = _find_player()
	_base_positions = {
		"body": body.position,
		"head": head.position,
		"scarf": scarf.position,
		"hand": hand.position,
		"weapon_socket": weapon_socket.position,
	}
	_base_scales = {
		"body": body.scale,
		"head": head.scale,
		"scarf": scarf.scale,
		"hand": hand.scale,
	}
	_set_avatar_render_layer(2)
	_prepare_unique_materials()


func _process(delta: float) -> void:
	_elapsed += delta
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	_read_player_state()
	_update_orientation(delta)
	_update_state_motion(delta)
	_update_reload_progress_bar()
	_update_state_materials()


func get_component_snapshot() -> Dictionary:
	return {
		"is_3d": true,
		"state": _state,
		"component_count": 4,
		"components": ["body", "head", "scarf", "hand"],
		"has_weapon_socket": weapon_socket != null,
		"visible_hand_count": 1,
		"body_position": body.position,
		"head_position": head.position,
		"scarf_position": scarf.position,
		"hand_position": hand.position,
		"weapon_socket_position": weapon_socket.position,
		"body_scale": body.scale,
		"visual_yaw": visual_root.rotation.y,
		"moving_animation_active": _moving_animation_active,
		"locomotion_cycle": _locomotion_cycle,
		"moving_bob_amplitude": 0.10,
		"reload_animation_active": _reload_animation_active,
		"reload_progress": _reload_progress,
		"reload_offset": _reload_offset,
		"reload_rotation": _reload_rotation,
		"reload_bar_visible": reload_progress_root.visible,
		"reload_fill_scale_x": reload_progress_fill.scale.x,
		"reload_bar_outside_visual_root": reload_progress_root.get_parent() == self,
		"reload_bar_billboarded": (
			(reload_progress_track.get_active_material(0) as StandardMaterial3D).billboard_mode
			== BaseMaterial3D.BILLBOARD_ENABLED
		),
		"hand_socket_offset": weapon_socket.position - hand.position,
		"render_layer": 2,
		"dash_trail_visible": dash_trail.visible,
		"lock_ring_visible": lock_ring.visible,
		"low_health_ring_visible": low_health_ring.visible,
	}


func _read_player_state() -> void:
	if _player == null:
		return
	if _player.has_method("get_presentation_state"):
		_state = str(_player.call("get_presentation_state"))
	if _player.has_method("get_reload_snapshot"):
		var reload_snapshot := _player.call("get_reload_snapshot") as Dictionary
		_reload_animation_active = bool(reload_snapshot.get("active", false)) and _state != "dead"
		_reload_progress = clampf(float(reload_snapshot.get("progress", 0.0)), 0.0, 1.0)
	else:
		_reload_animation_active = false
		_reload_progress = 0.0


func _update_orientation(delta: float) -> void:
	if _player == null:
		return
	var target_yaw := float(_player.get("aim_yaw"))
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, minf(1.0, delta * 16.0))


func _update_state_motion(delta: float) -> void:
	var bob := sin(_elapsed * TAU * 1.7) * 0.035
	var move_wave := sin(_elapsed * TAU * 1.1)
	var move_pulse := 0.0
	var target_position := Vector3.ZERO
	var target_scale := Vector3.ONE
	var target_roll := 0.0
	var body_scale_target: Vector3 = _base_scales["body"]
	var head_scale_target: Vector3 = _base_scales["head"]
	match _state:
		"moving":
			var planar_speed := 0.0
			if _player != null and _player.get("velocity") is Vector3:
				var player_velocity := _player.get("velocity") as Vector3
				planar_speed = Vector2(player_velocity.x, player_velocity.z).length()
			_locomotion_cycle = fmod(_locomotion_cycle + delta * lerpf(7.8, 11.2, clampf(planar_speed / 7.0, 0.0, 1.0)), TAU)
			move_wave = sin(_locomotion_cycle)
			move_pulse = absf(move_wave)
			bob = move_pulse * 0.10
			target_roll = move_wave * 0.052
			target_scale = Vector3(1.0 + move_pulse * 0.028, 1.0 - move_pulse * 0.025, 1.0 + move_pulse * 0.028)
			body_scale_target = _base_scales["body"] * Vector3(1.0 + move_pulse * 0.055, 1.0 - move_pulse * 0.075, 1.0 + move_pulse * 0.055)
			head_scale_target = _base_scales["head"] * Vector3(1.0 - move_pulse * 0.018, 1.0 + move_pulse * 0.022, 1.0 - move_pulse * 0.018)
		"dashing":
			bob = 0.0
			target_scale = Vector3(0.82, 0.82, 1.34)
			target_position = Vector3(0.0, -0.08, 0.0)
		"hurt":
			bob = sin(_elapsed * TAU * 11.0) * 0.055
			target_scale = Vector3(0.86, 1.12, 0.88)
			target_roll = sin(_elapsed * TAU * 13.0) * 0.09
		"locked":
			bob = sin(_elapsed * TAU * 0.8) * 0.012
			target_scale = Vector3(0.97, 0.97, 0.97)
		"dead":
			bob = 0.0
			target_position = Vector3(0.16, 0.36, 0.0)
			target_scale = Vector3(0.92, 0.76, 0.92)
			target_roll = 1.42
	_moving_animation_active = _state == "moving"
	var reload_arch := sin(_reload_progress * PI) if _reload_animation_active else 0.0
	var service_tick := sin(_reload_progress * TAU * 2.0) * reload_arch
	_reload_offset = Vector3(
		-reload_arch * 0.07,
		-reload_arch * 0.16 + service_tick * 0.025,
		reload_arch * 0.07
	)
	_reload_rotation = Vector3(
		reload_arch * 0.20,
		0.0,
		-reload_arch * 0.30 + service_tick * 0.055
	)

	visual_root.position = visual_root.position.lerp(target_position, minf(1.0, delta * 12.0))
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(1.0, delta * 14.0))
	visual_root.rotation.z = lerp_angle(visual_root.rotation.z, target_roll, minf(1.0, delta * 11.0))

	body.position = body.position.lerp(_base_positions["body"] + Vector3(0, bob, 0), minf(1.0, delta * 15.0))
	body.scale = body.scale.lerp(body_scale_target, minf(1.0, delta * 18.0))
	head.position = head.position.lerp(_base_positions["head"] + Vector3(0, bob * (0.46 if _state == "moving" else 0.62), 0), minf(1.0, delta * 17.0))
	head.scale = head.scale.lerp(head_scale_target, minf(1.0, delta * 16.0))
	scarf.position = scarf.position.lerp(_base_positions["scarf"] + Vector3(move_wave * (0.045 if _state == "moving" else 0.018), bob * 0.62, 0.02 + move_pulse * 0.035), minf(1.0, delta * 9.0))
	hand.position = hand.position.lerp(_base_positions["hand"] + Vector3(0, bob * 0.56, 0) + _reload_offset, minf(1.0, delta * 18.0))
	weapon_socket.position = weapon_socket.position.lerp(_base_positions["weapon_socket"] + Vector3(0, bob * 0.56, 0) + _reload_offset, minf(1.0, delta * 18.0))
	scarf.scale = scarf.scale.lerp(_base_scales["scarf"], minf(1.0, delta * 14.0))
	hand.scale = hand.scale.lerp(_base_scales["hand"], minf(1.0, delta * 14.0))
	# 手与枪械挂点始终使用同一换弹变换；3D 瞄准仍由整个 VisualRoot 绕 Y 轴完成。
	hand.rotation = hand.rotation.lerp(_reload_rotation, minf(1.0, delta * 20.0))
	weapon_socket.rotation = weapon_socket.rotation.lerp(_reload_rotation, minf(1.0, delta * 20.0))

	dash_trail.visible = _state == "dashing"
	dash_trail.scale.z = 1.0 + absf(sin(_elapsed * 18.0)) * 0.28
	lock_ring.visible = _state == "locked"
	lock_ring.rotation.y += delta * 1.7
	var low_health := bool(_player.call("is_low_health")) if _player != null and _player.has_method("is_low_health") else false
	low_health_ring.visible = low_health and _state != "dead"
	low_health_ring.scale = Vector3.ONE * (1.0 + sin(_elapsed * TAU * 2.1) * 0.06)


func _update_reload_progress_bar() -> void:
	var visible := _reload_animation_active and _state != "dead"
	reload_progress_root.visible = visible
	if not visible:
		reload_progress_fill.scale.x = 0.0
		reload_progress_fill.position.x = -RELOAD_FILL_WIDTH * 0.5
		return
	reload_progress_fill.scale.x = _reload_progress
	# 缩放围绕中心进行，因此同步平移可让左边缘固定。
	reload_progress_fill.position.x = -RELOAD_FILL_WIDTH * 0.5 * (1.0 - _reload_progress)


func _set_avatar_render_layer(layer_mask: int) -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).layers = layer_mask


func _update_state_materials() -> void:
	var tint := Color.WHITE
	if _state == "locked":
		tint = Color(0.64, 0.68, 0.72)
	elif _state == "dead":
		tint = Color(0.34, 0.37, 0.40)
	elif _state == "hurt":
		var flash := 0.55 + (sin(_elapsed * 46.0) * 0.5 + 0.5) * 0.45
		tint = Color(1.0, flash * 0.45, flash * 0.38)
	elif _player != null and bool(_player.get("is_invincible")) and fmod(_elapsed, 0.13) < 0.055:
		tint = Color(0.58, 0.94, 1.0)
	for key in _materials:
		var material := _materials[key] as StandardMaterial3D
		var base: Color = _base_colors[key]
		material.albedo_color = Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)


func _prepare_unique_materials() -> void:
	for path in [
		"VisualRoot/Body/BodyShell",
		"VisualRoot/Body/ChestPanel",
		"VisualRoot/Head/HeadShell",
		"VisualRoot/Head/Sensor",
		"VisualRoot/Scarf/Collar",
		"VisualRoot/Scarf/Tail",
		"VisualRoot/Hand/Glove",
		"VisualRoot/WeaponSocket/Weapon",
	]:
		var mesh_instance := get_node_or_null(path) as MeshInstance3D
		if mesh_instance == null:
			continue
		var source := mesh_instance.get_active_material(0) as StandardMaterial3D
		if source == null:
			continue
		var material := source.duplicate() as StandardMaterial3D
		mesh_instance.material_override = material
		_materials[path] = material
		_base_colors[path] = material.albedo_color


func _find_player() -> Node:
	var node := get_parent()
	for _index in range(5):
		if node == null:
			return null
		if node.is_in_group("player") and node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null
