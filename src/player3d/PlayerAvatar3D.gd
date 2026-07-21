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

var _player: Node = null
var _elapsed := 0.0
var _state := "idle"
var _base_positions: Dictionary = {}
var _base_colors: Dictionary = {}
var _materials: Dictionary = {}


func _ready() -> void:
	_player = _find_player()
	_base_positions = {
		"body": body.position,
		"head": head.position,
		"scarf": scarf.position,
		"hand": hand.position,
		"weapon_socket": weapon_socket.position,
	}
	_prepare_unique_materials()


func _process(delta: float) -> void:
	_elapsed += delta
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	_read_player_state()
	_update_orientation(delta)
	_update_state_motion(delta)
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
		"visual_yaw": visual_root.rotation.y,
		"dash_trail_visible": dash_trail.visible,
		"lock_ring_visible": lock_ring.visible,
		"low_health_ring_visible": low_health_ring.visible,
	}


func _read_player_state() -> void:
	if _player == null:
		return
	if _player.has_method("get_presentation_state"):
		_state = str(_player.call("get_presentation_state"))


func _update_orientation(delta: float) -> void:
	if _player == null:
		return
	var target_yaw := float(_player.get("aim_yaw"))
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, minf(1.0, delta * 16.0))


func _update_state_motion(delta: float) -> void:
	var bob := sin(_elapsed * TAU * 1.7) * 0.035
	var move_wave := sin(_elapsed * TAU * 5.0)
	var target_position := Vector3.ZERO
	var target_scale := Vector3.ONE
	var target_roll := 0.0
	match _state:
		"moving":
			bob = absf(move_wave) * 0.08
			target_roll = move_wave * 0.035
			target_scale = Vector3(1.03, 0.98, 1.03)
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

	visual_root.position = visual_root.position.lerp(target_position, minf(1.0, delta * 12.0))
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(1.0, delta * 14.0))
	visual_root.rotation.z = lerp_angle(visual_root.rotation.z, target_roll, minf(1.0, delta * 11.0))

	body.position = body.position.lerp(_base_positions["body"] + Vector3(0, bob, 0), minf(1.0, delta * 15.0))
	head.position = head.position.lerp(_base_positions["head"] + Vector3(0, bob * 0.62, 0), minf(1.0, delta * 17.0))
	scarf.position = scarf.position.lerp(_base_positions["scarf"] + Vector3(move_wave * 0.018, bob * 0.72, 0.02), minf(1.0, delta * 11.0))
	hand.position = hand.position.lerp(_base_positions["hand"] + Vector3(0, bob * 0.56, 0), minf(1.0, delta * 18.0))
	weapon_socket.position = weapon_socket.position.lerp(_base_positions["weapon_socket"] + Vector3(0, bob * 0.56, 0), minf(1.0, delta * 18.0))
	# 手与枪械挂点始终保持身体局部关系；3D 瞄准由整个 VisualRoot 绕 Y 轴完成。
	hand.rotation = Vector3.ZERO
	weapon_socket.rotation = Vector3.ZERO

	dash_trail.visible = _state == "dashing"
	dash_trail.scale.z = 1.0 + absf(sin(_elapsed * 18.0)) * 0.28
	lock_ring.visible = _state == "locked"
	lock_ring.rotation.y += delta * 1.7
	var low_health := bool(_player.call("is_low_health")) if _player != null and _player.has_method("is_low_health") else false
	low_health_ring.visible = low_health and _state != "dead"
	low_health_ring.scale = Vector3.ONE * (1.0 + sin(_elapsed * TAU * 2.1) * 0.06)


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
