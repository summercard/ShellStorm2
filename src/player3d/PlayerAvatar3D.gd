class_name PlayerAvatar3D
extends Node3D
## 猫型玩家原型的模块化 3D 表现层。
## CharacterBody3D 负责移动/碰撞，VisualRoot 负责瞄准朝向，组件节点只负责状态动态。

@onready var visual_root: Node3D = $VisualRoot
@onready var body: Node3D = $VisualRoot/Body
@onready var head: Node3D = $VisualRoot/Head
@onready var scarf: Node3D = $VisualRoot/Scarf
@onready var hand: Node3D = $VisualRoot/Hand
@onready var feet: Node3D = $VisualRoot/Feet
@onready var foot_l: MeshInstance3D = $VisualRoot/Feet/FootL
@onready var foot_r: MeshInstance3D = $VisualRoot/Feet/FootR
@onready var tail_stub: MeshInstance3D = $VisualRoot/Body/TailStub
@onready var weapon_socket: Marker3D = $VisualRoot/WeaponSocket
@onready var dash_trail: MeshInstance3D = $VisualRoot/StateVFX/DashTrail
@onready var lock_ring: MeshInstance3D = $VisualRoot/StateVFX/LockRing
@onready var low_health_ring: MeshInstance3D = $VisualRoot/StateVFX/LowHealthRing
@onready var reload_progress_root: Node3D = $ReloadProgress3D
@onready var reload_progress_track: MeshInstance3D = $ReloadProgress3D/Track
@onready var reload_progress_fill: MeshInstance3D = $ReloadProgress3D/Fill

const DEFAULT_CUSTOMIZATION := {
	"body": "cat_orange",
	"head": "cat_orange",
	"hand": "cat_orange",
	"feet": "cat_orange",
	"hat": "none",
	"glasses": "none",
}
const CUSTOMIZATION_OPTIONS := {
	"body": ["cat_orange", "suit_olive", "suit_sand", "suit_cobalt"],
	"head": ["cat_orange", "sensor_olive", "visor_cyan", "plated_amber"],
	"hand": ["cat_orange", "grip_olive", "safety_orange", "gauntlet_teal"],
	"feet": ["cat_orange", "boot_sand", "boot_cobalt", "boot_teal"],
	"hat": ["none", "field_cap", "hard_hat", "sealed_hood"],
	"glasses": ["none", "mono_lens", "dual_goggles", "wide_visor"],
}
const BODY_COLORS := {
	"cat_orange": Color(0.96, 0.48, 0.10),
	"suit_olive": Color(0.46, 0.49, 0.31),
	"suit_sand": Color(0.66, 0.50, 0.30),
	"suit_cobalt": Color(0.20, 0.42, 0.56),
}
const HEAD_COLORS := {
	"cat_orange": Color(1.0, 0.56, 0.12),
	"sensor_olive": Color(0.56, 0.56, 0.30),
	"visor_cyan": Color(0.22, 0.52, 0.56),
	"plated_amber": Color(0.62, 0.39, 0.16),
}
const HAND_COLORS := {
	"cat_orange": Color(0.93, 0.40, 0.07),
	"grip_olive": Color(0.56, 0.51, 0.27),
	"safety_orange": Color(0.78, 0.29, 0.09),
	"gauntlet_teal": Color(0.10, 0.52, 0.50),
}
const FEET_COLORS := {
	"cat_orange": Color(0.88, 0.35, 0.055),
	"boot_sand": Color(0.54, 0.36, 0.19),
	"boot_cobalt": Color(0.13, 0.30, 0.44),
	"boot_teal": Color(0.07, 0.39, 0.38),
}

var _player: Node = null
var _elapsed := 0.0
var _state := "idle"
var _base_positions: Dictionary = {}
var _base_scales: Dictionary = {}
var _base_rotations: Dictionary = {}
var _base_colors: Dictionary = {}
var _materials: Dictionary = {}
var _locomotion_cycle := 0.0
var _moving_animation_active := false
var _reload_animation_active := false
var _reload_progress := 0.0
var _reload_offset := Vector3.ZERO
var _reload_rotation := Vector3.ZERO
var _firing_animation_active := false
var _fire_progress := 0.0
var _fire_intensity := 0.0
var _charging_animation_active := false
var _charge_progress := 0.0
var _knockback_animation_active := false
var _knockback_progress := 0.0
var _knockback_direction := Vector3.ZERO
var _action_offset := Vector3.ZERO
var _action_rotation := Vector3.ZERO
var _customization: Dictionary = DEFAULT_CUSTOMIZATION.duplicate()
var _wearable_root: Node3D = null
var _wearable_nodes: Dictionary = {}

const RELOAD_FILL_WIDTH := 1.06


func _ready() -> void:
	_player = _find_player()
	_base_positions = {
		"body": body.position,
		"head": head.position,
		"scarf": scarf.position,
		"hand": hand.position,
		"feet": feet.position,
		"foot_l": foot_l.position,
		"foot_r": foot_r.position,
		"weapon_socket": weapon_socket.position,
	}
	_base_scales = {
		"body": body.scale,
		"head": head.scale,
		"scarf": scarf.scale,
		"hand": hand.scale,
		"feet": feet.scale,
		"foot_l": foot_l.scale,
		"foot_r": foot_r.scale,
		"tail_stub": tail_stub.scale,
	}
	_base_rotations = {
		"body": body.rotation,
		"head": head.rotation,
		"scarf": scarf.rotation,
		"hand": hand.rotation,
		"feet": feet.rotation,
		"foot_l": foot_l.rotation,
		"foot_r": foot_r.rotation,
		"tail_stub": tail_stub.rotation,
		"weapon_socket": weapon_socket.rotation,
	}
	_set_avatar_render_layer(2)
	_prepare_unique_materials()
	_ensure_wearable_nodes()
	_apply_customization()


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
		"components": ["body", "head", "hand", "feet"],
		"subcomponents": ["eyes", "ears", "tail_stub", "hat", "glasses"],
		"customization": get_customization(),
		"wearable_count": _wearable_nodes.size(),
		"has_weapon_socket": weapon_socket != null,
		"visible_hand_count": 1,
		"visible_foot_count": 2,
		"eye_count": 2,
		"ear_count": 2,
		"tail_style": "round_stub",
		"body_position": body.position,
		"head_position": head.position,
		"scarf_position": scarf.position,
		"hand_position": hand.position,
		"feet_position": feet.position,
		"foot_l_position": foot_l.position,
		"foot_r_position": foot_r.position,
		"tail_rotation": tail_stub.rotation,
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
		"firing_animation_active": _firing_animation_active,
		"fire_progress": _fire_progress,
		"fire_intensity": _fire_intensity,
		"charging_animation_active": _charging_animation_active,
		"charge_progress": _charge_progress,
		"knockback_animation_active": _knockback_animation_active,
		"knockback_progress": _knockback_progress,
		"action_offset": _action_offset,
		"action_rotation": _action_rotation,
		"reload_bar_visible": reload_progress_root.visible,
		"reload_fill_scale_x": reload_progress_fill.scale.x,
		"reload_bar_outside_visual_root": reload_progress_root.get_parent() == self,
		"reload_bar_billboarded": (
			(reload_progress_track.get_active_material(0) as StandardMaterial3D).billboard_mode
			== BaseMaterial3D.BILLBOARD_ENABLED
		),
		"hand_socket_offset": weapon_socket.position - hand.position,
		"render_layer": 2,
		"avatar_shadow_caster_count": _get_avatar_shadow_caster_count(),
		"dash_trail_visible": dash_trail.visible,
		"lock_ring_visible": lock_ring.visible,
		"low_health_ring_visible": low_health_ring.visible,
	}


static func has_customization_variant(slot_id: String, variant_id: String) -> bool:
	return slot_id in CUSTOMIZATION_OPTIONS and variant_id in (CUSTOMIZATION_OPTIONS[slot_id] as Array)


func set_customization(loadout: Dictionary) -> void:
	for slot_id in DEFAULT_CUSTOMIZATION:
		var requested := str(loadout.get(slot_id, _customization.get(slot_id, DEFAULT_CUSTOMIZATION[slot_id])))
		if has_customization_variant(slot_id, requested):
			_customization[slot_id] = requested
	if is_inside_tree():
		_ensure_wearable_nodes()
		_apply_customization()


func get_customization() -> Dictionary:
	return _customization.duplicate()


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
	if _player.has_method("get_action_snapshot"):
		var action_snapshot := _player.call("get_action_snapshot") as Dictionary
		_firing_animation_active = bool(action_snapshot.get("firing", false)) and _state != "dead"
		_fire_progress = clampf(float(action_snapshot.get("fire_progress", 0.0)), 0.0, 1.0)
		_fire_intensity = maxf(0.0, float(action_snapshot.get("fire_intensity", 0.0)))
		_charging_animation_active = bool(action_snapshot.get("charging", false)) and _state != "dead"
		_charge_progress = clampf(float(action_snapshot.get("charge_progress", 0.0)), 0.0, 1.0)
		_knockback_animation_active = bool(action_snapshot.get("knockback", false)) and _state != "dead"
		_knockback_progress = clampf(float(action_snapshot.get("knockback_progress", 0.0)), 0.0, 1.0)
		_knockback_direction = action_snapshot.get("knockback_direction", Vector3.ZERO) as Vector3
	else:
		_firing_animation_active = false
		_charging_animation_active = false
		_knockback_animation_active = false


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
	var fire_arch := sin(_fire_progress * PI) * _fire_intensity if _firing_animation_active else 0.0
	var charge_wave := sin(_elapsed * TAU * 2.4) * 0.5 + 0.5
	var charge_arch := _charge_progress * (0.72 + charge_wave * 0.28) if _charging_animation_active else 0.0
	var knockback_arch := sin(_knockback_progress * PI) if _knockback_animation_active else 0.0
	var local_knockback := Vector3.ZERO
	if _knockback_animation_active and _knockback_direction.length_squared() > 0.001:
		local_knockback = visual_root.global_basis.inverse() * _knockback_direction
		local_knockback.y = 0.0
		local_knockback = local_knockback.normalized()
	_action_offset = Vector3(
		-fire_arch * 0.018 + local_knockback.x * knockback_arch * 0.052,
		-fire_arch * 0.026 - charge_arch * 0.032 + knockback_arch * 0.026,
		fire_arch * 0.105 + charge_arch * 0.052 + local_knockback.z * knockback_arch * 0.052
	)
	_action_rotation = Vector3(
		-fire_arch * 0.24 + charge_arch * 0.10,
		charge_arch * 0.06,
		local_knockback.x * knockback_arch * 0.18
	)
	if _firing_animation_active:
		target_position += Vector3(0.0, -fire_arch * 0.018, fire_arch * 0.045)
		target_scale *= Vector3(1.0 + fire_arch * 0.055, 1.0 - fire_arch * 0.075, 1.0 - fire_arch * 0.035)
		body_scale_target *= Vector3(1.0 + fire_arch * 0.045, 1.0 - fire_arch * 0.08, 1.0 - fire_arch * 0.025)
	if _charging_animation_active:
		target_position += Vector3(0.0, -charge_arch * 0.026, 0.0)
		target_scale *= Vector3(1.0 - charge_arch * 0.035, 1.0 - charge_arch * 0.055, 1.0 - charge_arch * 0.035)
	if _knockback_animation_active:
		target_position += local_knockback * knockback_arch * 0.16 + Vector3(0.0, knockback_arch * 0.045, 0.0)
		target_scale *= Vector3(1.0 + knockback_arch * 0.10, 1.0 - knockback_arch * 0.13, 1.0 + knockback_arch * 0.07)
		target_roll += local_knockback.x * knockback_arch * 0.18

	visual_root.position = visual_root.position.lerp(target_position, minf(1.0, delta * 12.0))
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(1.0, delta * 14.0))
	visual_root.rotation.z = lerp_angle(visual_root.rotation.z, target_roll, minf(1.0, delta * 11.0))

	body.position = body.position.lerp(_base_positions["body"] + Vector3(0, bob - fire_arch * 0.016 - charge_arch * 0.018, 0), minf(1.0, delta * 15.0))
	body.scale = body.scale.lerp(body_scale_target, minf(1.0, delta * 18.0))
	body.rotation = body.rotation.lerp(_base_rotations["body"] + Vector3(0.0, 0.0, -move_wave * 0.034 + fire_arch * 0.035), minf(1.0, delta * 13.0))
	head.position = head.position.lerp(_base_positions["head"] + Vector3(0, bob * (0.46 if _state == "moving" else 0.62) - fire_arch * 0.012, fire_arch * 0.018), minf(1.0, delta * 17.0))
	head.scale = head.scale.lerp(head_scale_target, minf(1.0, delta * 16.0))
	head.rotation = head.rotation.lerp(_base_rotations["head"] + Vector3(fire_arch * 0.035, 0.0, move_wave * 0.048 - knockback_arch * local_knockback.x * 0.11), minf(1.0, delta * 14.0))
	scarf.position = scarf.position.lerp(_base_positions["scarf"] + Vector3(move_wave * (0.045 if _state == "moving" else 0.018), bob * 0.62, 0.02 + move_pulse * 0.035), minf(1.0, delta * 9.0))
	scarf.rotation = scarf.rotation.lerp(_base_rotations["scarf"] + Vector3(move_wave * 0.06, 0.0, -move_wave * 0.08 - fire_arch * 0.04), minf(1.0, delta * 8.0))
	feet.position = feet.position.lerp(_base_positions["feet"] + Vector3(0.0, bob * 0.18, 0.0), minf(1.0, delta * 18.0))
	feet.rotation = feet.rotation.lerp(_base_rotations["feet"] + Vector3(0.0, 0.0, -move_wave * 0.022), minf(1.0, delta * 16.0))
	var left_step := maxf(0.0, move_wave) * 0.105 if _state == "moving" else 0.0
	var right_step := maxf(0.0, -move_wave) * 0.105 if _state == "moving" else 0.0
	foot_l.position = foot_l.position.lerp(_base_positions["foot_l"] + Vector3(0.0, left_step, -left_step * 0.34), minf(1.0, delta * 22.0))
	foot_r.position = foot_r.position.lerp(_base_positions["foot_r"] + Vector3(0.0, right_step, -right_step * 0.34), minf(1.0, delta * 22.0))
	foot_l.rotation = foot_l.rotation.lerp(_base_rotations["foot_l"] + Vector3(-move_wave * 0.18, 0.0, move_wave * 0.035), minf(1.0, delta * 20.0))
	foot_r.rotation = foot_r.rotation.lerp(_base_rotations["foot_r"] + Vector3(move_wave * 0.18, 0.0, move_wave * 0.035), minf(1.0, delta * 20.0))
	var tail_wag := sin(_elapsed * TAU * (2.0 if _state == "moving" else 0.75))
	tail_stub.rotation = tail_stub.rotation.lerp(_base_rotations["tail_stub"] + Vector3(0.0, tail_wag * (0.18 if _state == "moving" else 0.055), tail_wag * 0.045), minf(1.0, delta * 10.0))
	tail_stub.scale = tail_stub.scale.lerp(_base_scales["tail_stub"] * Vector3(1.0 + move_pulse * 0.04, 1.0 - move_pulse * 0.025, 1.0 + move_pulse * 0.04), minf(1.0, delta * 15.0))
	hand.position = hand.position.lerp(_base_positions["hand"] + Vector3(0, bob * 0.56, 0) + _reload_offset + _action_offset, minf(1.0, delta * 18.0))
	weapon_socket.position = weapon_socket.position.lerp(_base_positions["weapon_socket"] + Vector3(0, bob * 0.56, 0) + _reload_offset + _action_offset, minf(1.0, delta * 18.0))
	scarf.scale = scarf.scale.lerp(_base_scales["scarf"], minf(1.0, delta * 14.0))
	feet.scale = feet.scale.lerp(_base_scales["feet"] * Vector3(1.0 + move_pulse * 0.035, 1.0 - move_pulse * 0.025, 1.0 + move_pulse * 0.045), minf(1.0, delta * 17.0))
	foot_l.scale = foot_l.scale.lerp(_base_scales["foot_l"], minf(1.0, delta * 18.0))
	foot_r.scale = foot_r.scale.lerp(_base_scales["foot_r"], minf(1.0, delta * 18.0))
	var grip_squeeze := fire_arch * 0.13 + charge_arch * 0.06 + move_pulse * 0.025
	hand.scale = hand.scale.lerp(_base_scales["hand"] * Vector3(1.0 + grip_squeeze, 1.0 - grip_squeeze * 0.45, 1.0 - grip_squeeze * 0.22), minf(1.0, delta * 16.0))
	# 手与枪械挂点始终使用同一动作变换；3D 瞄准仍由整个 VisualRoot 绕 Y 轴完成。
	hand.rotation = hand.rotation.lerp(_base_rotations["hand"] + _reload_rotation + _action_rotation, minf(1.0, delta * 20.0))
	weapon_socket.rotation = weapon_socket.rotation.lerp(_base_rotations["weapon_socket"] + _reload_rotation + _action_rotation, minf(1.0, delta * 20.0))

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


func _ensure_wearable_nodes() -> void:
	if _wearable_root != null and is_instance_valid(_wearable_root):
		return
	_wearable_root = Node3D.new()
	_wearable_root.name = "Wearables"
	head.add_child(_wearable_root)
	_wearable_nodes["hat_none"] = _wearable_root
	_wearable_nodes["hat_field_cap"] = _create_field_cap()
	_wearable_nodes["hat_hard_hat"] = _create_hard_hat()
	_wearable_nodes["hat_sealed_hood"] = _create_sealed_hood()
	_wearable_nodes["glasses_none"] = _wearable_root
	_wearable_nodes["glasses_mono_lens"] = _create_mono_lens()
	_wearable_nodes["glasses_dual_goggles"] = _create_dual_goggles()
	_wearable_nodes["glasses_wide_visor"] = _create_wide_visor()
	for wearable_id in _wearable_nodes:
		if wearable_id.ends_with("_none"):
			continue
		var wearable := _wearable_nodes[wearable_id] as Node3D
		if wearable.get_parent() == null:
			_wearable_root.add_child(wearable)
		_set_node_render_layer(wearable, 2)


func _apply_customization() -> void:
	if _materials.is_empty():
		return
	_set_base_color("VisualRoot/Body/BodyShell", BODY_COLORS[_customization["body"]])
	_set_base_color("VisualRoot/Body/BellyPatch", BODY_COLORS[_customization["body"]].lightened(0.24))
	_set_base_color("VisualRoot/Body/TailStub", BODY_COLORS[_customization["body"]].darkened(0.06))
	_set_base_color("VisualRoot/Head/HeadShell", HEAD_COLORS[_customization["head"]])
	_set_base_color("VisualRoot/Head/Ears/EarL", HEAD_COLORS[_customization["head"]].darkened(0.04))
	_set_base_color("VisualRoot/Head/Ears/EarR", HEAD_COLORS[_customization["head"]].darkened(0.04))
	_set_base_color("VisualRoot/Hand/Glove", HAND_COLORS[_customization["hand"]])
	_set_base_color("VisualRoot/Feet/FootL", FEET_COLORS[_customization["feet"]])
	_set_base_color("VisualRoot/Feet/FootR", FEET_COLORS[_customization["feet"]])
	for wearable_id in _wearable_nodes:
		if wearable_id.ends_with("_none"):
			continue
		var wearable := _wearable_nodes[wearable_id] as Node3D
		wearable.visible = wearable_id == "hat_%s" % _customization["hat"] or wearable_id == "glasses_%s" % _customization["glasses"]


func _set_base_color(material_path: String, color: Color) -> void:
	if not _materials.has(material_path):
		return
	_base_colors[material_path] = color
	(_materials[material_path] as StandardMaterial3D).albedo_color = color


func _create_field_cap() -> Node3D:
	var root := Node3D.new()
	root.name = "HatFieldCap"
	root.position = Vector3(0.0, 0.40, 0.0)
	_add_wearable_mesh(root, "Crown", _cylinder_mesh(0.48, 0.51, 0.16), Color(0.12, 0.20, 0.22))
	_add_wearable_mesh(root, "Brim", _box_mesh(Vector3(0.66, 0.06, 0.30)), Color(0.10, 0.16, 0.18), Vector3(0.0, -0.08, -0.42))
	return root


func _create_hard_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "HatHardHat"
	root.position = Vector3(0.0, 0.37, 0.0)
	var shell := _add_wearable_mesh(root, "Shell", _sphere_mesh(0.54, 0.42), Color(0.92, 0.53, 0.08))
	shell.scale = Vector3(1.0, 0.72, 1.0)
	_add_wearable_mesh(root, "Lamp", _sphere_mesh(0.08, 0.10), Color(1.0, 0.86, 0.35), Vector3(0.0, 0.02, -0.51), true)
	return root


func _create_sealed_hood() -> Node3D:
	var root := Node3D.new()
	root.name = "HatSealedHood"
	root.position = Vector3(0.0, 0.03, 0.04)
	var hood := _add_wearable_mesh(root, "Hood", _sphere_mesh(0.56, 1.0), Color(0.13, 0.18, 0.26))
	hood.scale = Vector3(1.08, 1.08, 1.08)
	hood.position.z = 0.08
	return root


func _create_mono_lens() -> Node3D:
	var root := Node3D.new()
	root.name = "GlassesMonoLens"
	root.position = Vector3(-0.16, 0.05, -0.48)
	_add_wearable_mesh(root, "Lens", _sphere_mesh(0.17, 0.08), Color(0.20, 0.90, 1.0), Vector3.ZERO, true)
	return root


func _create_dual_goggles() -> Node3D:
	var root := Node3D.new()
	root.name = "GlassesDualGoggles"
	root.position = Vector3(0.0, 0.04, -0.48)
	_add_wearable_mesh(root, "LeftLens", _sphere_mesh(0.16, 0.07), Color(0.74, 0.22, 0.92), Vector3(-0.18, 0.0, 0.0), true)
	_add_wearable_mesh(root, "RightLens", _sphere_mesh(0.16, 0.07), Color(0.74, 0.22, 0.92), Vector3(0.18, 0.0, 0.0), true)
	_add_wearable_mesh(root, "Bridge", _box_mesh(Vector3(0.18, 0.045, 0.05)), Color(0.08, 0.06, 0.12))
	return root


func _create_wide_visor() -> Node3D:
	var root := Node3D.new()
	root.name = "GlassesWideVisor"
	root.position = Vector3(0.0, 0.04, -0.50)
	_add_wearable_mesh(root, "Visor", _box_mesh(Vector3(0.72, 0.19, 0.07)), Color(0.18, 0.68, 0.88), Vector3.ZERO, true)
	return root


func _add_wearable_mesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color, position := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = position
	# 配件只接收角色前方柔光：不向场景、头壳或同组配件投射阴影，
	# 也不参与 GI，避免安全帽/护目镜遮住角色自身的灯光表现。
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.material_override = _wearable_material(color, emissive)
	parent.add_child(node)
	var material_key := "Wearables/%s/%s" % [parent.name, node_name]
	_materials[material_key] = node.material_override as StandardMaterial3D
	_base_colors[material_key] = color
	return node


func _wearable_material(color: Color, emissive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.32
	material.roughness = 0.48
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.4
	return material


func _sphere_mesh(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 16
	return mesh


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _set_node_render_layer(root: Node, layer_mask: int) -> void:
	for mesh_instance in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_instance as MeshInstance3D
		mesh.layers = layer_mask
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _set_avatar_render_layer(layer_mask: int) -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		# 角色只接收 AvatarFrontFill，绝不能让头、身、手、脚彼此投射阴影。
		# 这也覆盖之后导入的 GLB 网格，避免正式模型带回 Blender 的默认投影设置。
		mesh.layers = layer_mask
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _get_avatar_shadow_caster_count() -> int:
	var count := 0
	for child in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			count += 1
	return count


func _update_state_materials() -> void:
	var tint := Color.WHITE
	if _state == "locked":
		tint = Color(0.64, 0.68, 0.72)
	elif _state == "dead":
		tint = Color(0.34, 0.37, 0.40)
	elif _state == "hurt":
		var flash := 0.55 + (sin(_elapsed * 46.0) * 0.5 + 0.5) * 0.45
		tint = Color(1.0, flash * 0.45, flash * 0.38)
	elif _firing_animation_active:
		tint = Color(1.0, 0.88, 0.66)
	elif _charging_animation_active:
		tint = Color(0.78, 0.72, 1.0)
	elif _player != null and bool(_player.get("is_invincible")) and fmod(_elapsed, 0.13) < 0.055:
		tint = Color(0.58, 0.94, 1.0)
	for key in _materials:
		var material := _materials[key] as StandardMaterial3D
		var base: Color = _base_colors[key]
		material.albedo_color = Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)


func _prepare_unique_materials() -> void:
	for path in [
		"VisualRoot/Body/BodyShell",
		"VisualRoot/Body/BellyPatch",
		"VisualRoot/Body/TailStub",
		"VisualRoot/Head/HeadShell",
		"VisualRoot/Head/Eyes/EyeL",
		"VisualRoot/Head/Eyes/EyeR",
		"VisualRoot/Head/Ears/EarL",
		"VisualRoot/Head/Ears/EarL/Inner",
		"VisualRoot/Head/Ears/EarR",
		"VisualRoot/Head/Ears/EarR/Inner",
		"VisualRoot/Scarf/Collar",
		"VisualRoot/Scarf/Tail",
		"VisualRoot/Hand/Glove",
		"VisualRoot/Feet/FootL",
		"VisualRoot/Feet/FootR",
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
