class_name PlayerAvatar3D
extends Node3D
## 玩家原型的模块化 3D 表现层。当前正式外观为 bunny01，旧猫型根场景保留作回退。
## CharacterBody3D 负责移动/碰撞，VisualRoot 负责瞄准朝向，组件节点只负责状态动态。

@onready var visual_root: Node3D = $VisualRoot
@onready var body: Node3D = _resolve_rig_node("VisualRoot/BunnyRig/BodyJoint", "VisualRoot/Body")
@onready var head: Node3D = _resolve_rig_node("VisualRoot/BunnyRig/HeadJoint", "VisualRoot/Head")
@onready var scarf: Node3D = $VisualRoot/Scarf
@onready var hand: Node3D = _resolve_rig_node("VisualRoot/BunnyRig/HandRoot", "VisualRoot/Hand")
@onready var feet: Node3D = _resolve_rig_node("VisualRoot/BunnyRig/FeetRoot", "VisualRoot/Feet")
@onready var foot_l: Node3D = _resolve_rig_node("VisualRoot/BunnyRig/FeetRoot/FootJointL", "VisualRoot/Feet/FootL")
@onready var foot_r: Node3D = _resolve_rig_node("VisualRoot/BunnyRig/FeetRoot/FootJointR", "VisualRoot/Feet/FootR")
@onready var ear_socket_l: Node3D = get_node_or_null("VisualRoot/BunnyRig/HeadJoint/Ears/EarSocketL") as Node3D
@onready var ear_socket_r: Node3D = get_node_or_null("VisualRoot/BunnyRig/HeadJoint/Ears/EarSocketR") as Node3D
@onready var bunny_head_model: Node3D = get_node_or_null("VisualRoot/BunnyRig/HeadJoint/Model") as Node3D
@onready var bunny_ears: Node3D = get_node_or_null("VisualRoot/BunnyRig/HeadJoint/Ears") as Node3D
@onready var chibi_anime_head: Node3D = get_node_or_null("VisualRoot/BunnyRig/HeadJoint/HeadAccessoryChibiAnime") as Node3D
@onready var bunny_hand_l: Node3D = get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointL") as Node3D
@onready var bunny_hand_r: Node3D = get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointR") as Node3D
@onready var bunny_hand_r_model: Node3D = get_node_or_null("VisualRoot/BunnyRig/HandRoot/HandJointR/Model") as Node3D
@onready var tail_stub: MeshInstance3D = $VisualRoot/Body/TailStub
@onready var weapon_socket: Marker3D = _resolve_rig_node("VisualRoot/BunnyRig/WeaponSocket", "VisualRoot/WeaponSocket") as Marker3D
@onready var stowed_weapon_socket_primary: Marker3D = _resolve_rig_node(
	"VisualRoot/BunnyRig/StowedWeaponSocketPrimary",
	"VisualRoot/StowedWeaponSocketPrimary"
) as Marker3D
@onready var stowed_weapon_socket_secondary: Marker3D = _resolve_rig_node(
	"VisualRoot/BunnyRig/StowedWeaponSocketSecondary",
	"VisualRoot/StowedWeaponSocketSecondary"
) as Marker3D
@onready var backpack_socket: Marker3D = _resolve_rig_node(
	"VisualRoot/BunnyRig/BackpackSocket",
	"VisualRoot/BackpackSocket"
) as Marker3D
@onready var lower_body_socket: Marker3D = _resolve_rig_node(
	"VisualRoot/BunnyRig/BodyJoint/LowerBodySocket",
	"VisualRoot/Body/LowerBodySocket"
) as Marker3D
@onready var dash_dust: GPUParticles3D = $VisualRoot/StateVFX/DashDustBurst
@onready var lock_ring: MeshInstance3D = $VisualRoot/StateVFX/LockRing
@onready var low_health_ring: MeshInstance3D = $VisualRoot/StateVFX/LowHealthRing
@onready var reload_progress_root: Node3D = $ReloadProgress3D
@onready var reload_progress_track: MeshInstance3D = $ReloadProgress3D/Track
@onready var reload_progress_fill: MeshInstance3D = $ReloadProgress3D/Fill

const DEFAULT_CUSTOMIZATION := {
	"body": "bunny_white",
	"head": "bunny_white",
	"hand": "bunny_white",
	"feet": "bunny_white",
	"hat": "bunny_ears",
	"glasses": "none",
}
const CHIBI_ANIME_HEAD_VARIANT := "chibi_anime"
const BUNNY_EARS_HAT_VARIANT := "bunny_ears"
const CUSTOMIZATION_OPTIONS := {
	"body": ["bunny_white", "cat_orange", "suit_olive", "suit_sand", "suit_cobalt"],
	"head": ["bunny_white", "cat_orange", "sensor_olive", "visor_cyan", "plated_amber", CHIBI_ANIME_HEAD_VARIANT],
	"hand": ["bunny_white", "cat_orange", "grip_olive", "safety_orange", "gauntlet_teal"],
	"feet": ["bunny_white", "cat_orange", "boot_sand", "boot_cobalt", "boot_teal"],
	"hat": [BUNNY_EARS_HAT_VARIANT, "none", "field_cap", "hard_hat", "sealed_hood"],
	"glasses": ["none", "mono_lens", "dual_goggles", "wide_visor"],
}
const BODY_COLORS := {
	"bunny_white": Color.WHITE,
	"cat_orange": Color(0.96, 0.48, 0.10),
	"suit_olive": Color(0.46, 0.49, 0.31),
	"suit_sand": Color(0.66, 0.50, 0.30),
	"suit_cobalt": Color(0.20, 0.42, 0.56),
}
const HEAD_COLORS := {
	"bunny_white": Color.WHITE,
	"cat_orange": Color(1.0, 0.56, 0.12),
	"sensor_olive": Color(0.56, 0.56, 0.30),
	"visor_cyan": Color(0.22, 0.52, 0.56),
	"plated_amber": Color(0.62, 0.39, 0.16),
}
const HAND_COLORS := {
	"bunny_white": Color.WHITE,
	"cat_orange": Color(0.93, 0.40, 0.07),
	"grip_olive": Color(0.56, 0.51, 0.27),
	"safety_orange": Color(0.78, 0.29, 0.09),
	"gauntlet_teal": Color(0.10, 0.52, 0.50),
}
const FEET_COLORS := {
	"bunny_white": Color.WHITE,
	"cat_orange": Color(0.88, 0.35, 0.055),
	"boot_sand": Color(0.54, 0.36, 0.19),
	"boot_cobalt": Color(0.13, 0.30, 0.44),
	"boot_teal": Color(0.07, 0.39, 0.38),
}

var _player: Node = null
var _elapsed := 0.0
var _state := "idle"
var _previous_state := "idle"
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
var _melee_animation_active := false
var _melee_phase := "ready"
var _melee_progress := 0.0
var _melee_combo_step := 0
var _melee_combo_count := 0
var _action_offset := Vector3.ZERO
var _action_rotation := Vector3.ZERO
var _dash_animation_progress := 1.0
var _hurt_animation_progress := 1.0
var _fall_animation_progress := 0.0
var _landing_animation_progress := 1.0
var _idle_animation_active := false
var _idle_cycle := 0.0
var _idle_breath := 0.0
var _idle_weight_shift := 0.0
var _idle_ear_flick := 0.0
var _weapon_grip_pose_active := false
var _weapon_pose_state := "unarmed"
var _weapon_pose_previous_state := "unarmed"
var _weapon_pose_transition_count := 0
var _weapon_class := "unarmed"
var _equipped_gun_id := ""
var _weapon_fire_style := "none"
var _active_grip_hand_count := 0
var _weapon_socket_pose_offset := Vector3.ZERO
var _weapon_socket_pose_rotation := Vector3.ZERO
var _customization: Dictionary = DEFAULT_CUSTOMIZATION.duplicate()
var _wearable_root: Node3D = null
var _wearable_nodes: Dictionary = {}

const RELOAD_FILL_WIDTH := 1.06
const IDLE_LOOP_HZ := 0.42
const IDLE_LOOP_DURATION := 1.0 / IDLE_LOOP_HZ
const BUNNY_LINEAR_SCALE := 1.5 / 2.475
const SIDEARM_SOCKET_OFFSET := Vector3(0.24, -0.01, 0.0)
const SIDEARM_HOLD_SOCKET_OFFSET := Vector3(0.12, -0.23, -0.22)
const SIDEARM_HOLD_SOCKET_ROTATION := Vector3.ZERO
const SIDEARM_READY_HAND_L := Vector3(-0.24, 0.55, -0.58)
const SIDEARM_READY_ROTATION_L := Vector3(-0.08, -PI * 0.35, 0.18)
const SIDEARM_GRIP_HAND_R := Vector3(0.0, 0.65, -0.36)
const SIDEARM_GRIP_ROTATION_R := Vector3(-0.12, PI * 0.46, -0.18)
const LONGGUN_GRIP_HAND_L := Vector3(0.20, 0.52, -0.64)
const LONGGUN_GRIP_HAND_R := Vector3(0.0, 0.65, -0.36)
const LONGGUN_GRIP_ROTATION_L := Vector3(-0.10, -PI * 0.46, 0.24)
const LONGGUN_GRIP_ROTATION_R := Vector3(-0.16, PI * 0.46, -0.20)
const RIGHT_HAND_SPHERE_CENTER_LOCAL := Vector3(0.135996, -0.038999, -0.018441)
const RIGHT_HAND_PIVOT_CONTRACT := "palm_sphere_center_is_HandJointR_and_GripSocket"
const SIDEARM_GUNS := ["bp_pistol"]
const HEAVY_MELEE_WEAPONS := ["bp_baseball_bat", "bp_greatblade", "bp_waraxe"]
const WEAPON_POSE_STATES := [
	"unarmed",
	"sidearm_hold", "sidearm_run", "sidearm_fire", "sidearm_reload", "sidearm_charge",
	"longgun_hold", "longgun_run", "longgun_fire", "longgun_reload", "longgun_charge",
	"heavy_melee_hold", "heavy_melee_run", "heavy_melee_windup", "heavy_melee_active", "heavy_melee_recovery",
]
const WEAPON_ANIMATION_PROFILES := {
	"bp_pistol": {
		"fire_style": "sidearm_snap",
		"kick": 1.00,
		"pitch": 0.48,
		"roll": -0.16,
		"lift": 0.028,
	},
	"bp_shotgun": {
		"fire_style": "shotgun_heavy_pump",
		"kick": 1.48,
		"pitch": 0.30,
		"roll": 0.05,
		"lift": 0.045,
	},
	"bp_rifle": {
		"fire_style": "rifle_braced_burst",
		"kick": 0.82,
		"pitch": 0.20,
		"roll": 0.025,
		"lift": 0.020,
	},
	"bp_machinegun": {
		"fire_style": "machinegun_rattle",
		"kick": 0.68,
		"pitch": 0.16,
		"roll": -0.04,
		"lift": 0.018,
	},
	"bp_sniper": {
		"fire_style": "sniper_long_recoil",
		"kick": 1.62,
		"pitch": 0.34,
		"roll": 0.035,
		"lift": 0.050,
	},
	"bp_launcher": {
		"fire_style": "launcher_body_push",
		"kick": 1.82,
		"pitch": 0.25,
		"roll": 0.10,
		"lift": 0.060,
	},
	"bp_charge": {
		"fire_style": "charge_release",
		"kick": 1.22,
		"pitch": 0.38,
		"roll": -0.06,
		"lift": 0.040,
	},
}


func _resolve_rig_node(primary_path: NodePath, fallback_path: NodePath) -> Node3D:
	var primary := get_node_or_null(primary_path) as Node3D
	return primary if primary != null else get_node(fallback_path) as Node3D


func get_stowed_weapon_socket(weapon_slot_index: int) -> Marker3D:
	return (
		stowed_weapon_socket_primary
		if weapon_slot_index == 0
		else stowed_weapon_socket_secondary
	)


func get_backpack_socket() -> Marker3D:
	return backpack_socket


## 腰线以下的纯表现挂点。裙摆、腰甲和下身饰件只挂这里，不进入碰撞或玩法树。
func get_lower_body_socket() -> Marker3D:
	return lower_body_socket


func _motion_offset(value: Vector3) -> Vector3:
	return value * (BUNNY_LINEAR_SCALE if _is_bunny_avatar() else 1.0)


func _apply_bunny_attachment_scale() -> void:
	if not _is_bunny_avatar():
		return
	var held_weapon := weapon_socket.get_node_or_null("WeaponModel3D") as Node3D
	if held_weapon != null:
		var held_scale := 0.78 if held_weapon.get("weapon_kind") == "melee" else BUNNY_LINEAR_SCALE
		held_weapon.scale = Vector3.ONE * held_scale


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
	if ear_socket_l != null:
		_base_positions["ear_socket_l"] = ear_socket_l.position
		_base_rotations["ear_socket_l"] = ear_socket_l.rotation
	if ear_socket_r != null:
		_base_positions["ear_socket_r"] = ear_socket_r.position
		_base_rotations["ear_socket_r"] = ear_socket_r.rotation
	if bunny_hand_l != null:
		_base_positions["bunny_hand_l"] = bunny_hand_l.position
		_base_rotations["bunny_hand_l"] = bunny_hand_l.rotation
	if bunny_hand_r != null:
		_base_positions["bunny_hand_r"] = bunny_hand_r.position
		_base_rotations["bunny_hand_r"] = bunny_hand_r.rotation
	_set_avatar_render_layer(2)
	_prepare_unique_materials()
	_fix_left_ear_mirror_tangent_space()
	_ensure_wearable_nodes()
	if _is_bunny_avatar():
		reload_progress_root.scale = Vector3.ONE * BUNNY_LINEAR_SCALE
		if _wearable_root != null:
			_wearable_root.scale = Vector3.ONE * BUNNY_LINEAR_SCALE
		var state_vfx := get_node_or_null("VisualRoot/StateVFX") as Node3D
		if state_vfx != null:
			state_vfx.scale = Vector3.ONE * BUNNY_LINEAR_SCALE
		_apply_bunny_attachment_scale()
	_apply_customization()


func _process(delta: float) -> void:
	_elapsed += delta
	_apply_bunny_attachment_scale()
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	_read_player_state()
	_update_orientation(delta)
	_update_state_motion(delta)
	_update_reload_progress_bar()
	_update_state_materials()


func get_component_snapshot() -> Dictionary:
	var is_bunny := _is_bunny_avatar()
	var authored_height_m := 1.5 if is_bunny else 1.65
	var runtime_scale_multiplier := scale.y
	return {
		"is_3d": true,
		"avatar_profile": "bunny01" if is_bunny else "capsule_cat",
		"assembly_version": "v006" if is_bunny else "v001",
		"rig_type": "rigid_node_skeleton" if is_bunny else "legacy_component_nodes",
		"component_space": "pivot_local" if is_bunny else "scene_local",
		"rig_joint_count": 8 if is_bunny else 0,
		"state": _state,
		"component_count": 4,
		"components": ["body", "head", "hand", "feet"],
		"subcomponents": ["ear_accessories", "ear_sockets", "hat", "glasses", "lower_body_socket"],
		"customization": get_customization(),
		"customization_material_counts": _get_customization_material_counts(),
		"customization_material_colors": _get_customization_material_colors(),
		"chibi_anime_head_available": chibi_anime_head != null,
		"chibi_anime_head_visible": chibi_anime_head != null and chibi_anime_head.visible,
		"base_bunny_head_visible": bunny_head_model != null and bunny_head_model.visible,
		"base_bunny_ears_visible": bunny_ears != null and bunny_ears.visible,
		"wearable_count": _wearable_nodes.size(),
		"has_weapon_socket": weapon_socket != null,
		"has_lower_body_socket": lower_body_socket != null,
		"lower_body_socket_path": str(lower_body_socket.get_path()) if lower_body_socket != null else "",
		"lower_body_socket_position": lower_body_socket.position if lower_body_socket != null else Vector3.ZERO,
		"lower_body_socket_global_position": lower_body_socket.global_position if lower_body_socket != null else Vector3.ZERO,
		"lower_body_socket_parent_is_body": lower_body_socket != null and lower_body_socket.get_parent() == body,
		"visible_hand_count": 2 if is_bunny else 1,
		"visible_foot_count": 2,
		"eye_count": 0 if is_bunny else 2,
		"ear_count": 2,
		"ear_socket_count": 2 if is_bunny else 0,
		"ears_parented_to_head": is_bunny,
		"tail_style": "none" if is_bunny else "round_stub",
		"independent_foot_animation": true,
		"independent_hand_animation": is_bunny,
		"authored_scale_m": authored_height_m,
		"runtime_scale_multiplier": runtime_scale_multiplier,
		"full_visual_height_m": authored_height_m * runtime_scale_multiplier,
		"linear_scale_from_v004": BUNNY_LINEAR_SCALE if is_bunny else 1.0,
		"authored_forward_correction_degrees": 90 if is_bunny else 0,
		"raw_forward_blender": "+X" if is_bunny else "",
		"runtime_forward_godot": "-Z" if is_bunny else "",
		"forward_contract_pass": is_bunny,
		"body_position": body.position,
		"head_position": head.position,
		"scarf_position": scarf.position,
		"hand_position": hand.position,
		"feet_position": feet.position,
		"foot_l_position": foot_l.position,
		"foot_r_position": foot_r.position,
		"tail_rotation": tail_stub.rotation,
		"weapon_socket_position": weapon_socket.position,
		"weapon_socket_rotation": weapon_socket.rotation,
		"body_scale": body.scale,
		"head_rotation": head.rotation,
		"foot_l_rotation": foot_l.rotation,
		"foot_r_rotation": foot_r.rotation,
		"visual_scale": visual_root.scale,
		"visual_yaw": visual_root.rotation.y,
		"visual_pitch": visual_root.rotation.x,
		"moving_animation_active": _moving_animation_active,
		"locomotion_cycle": _locomotion_cycle,
		"moving_bob_amplitude": 0.10 * (BUNNY_LINEAR_SCALE if is_bunny else 1.0),
		"idle_animation_active": _idle_animation_active,
		"idle_state_machine_owned": true,
		"idle_cycle": _idle_cycle,
		"idle_breath": _idle_breath,
		"idle_weight_shift": _idle_weight_shift,
		"idle_ear_flick": _idle_ear_flick,
		"idle_loop_duration_s": IDLE_LOOP_DURATION,
		"dash_roll_active": _state == "dashing",
		"dash_roll_progress": _dash_animation_progress,
		"hurt_keyframe_active": _state == "hurt",
		"hurt_animation_progress": _hurt_animation_progress,
		"fall_animation_active": _state == "falling",
		"fall_animation_progress": _fall_animation_progress,
		"landing_animation_active": _state == "landing",
		"landing_animation_progress": _landing_animation_progress,
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
		"melee_animation_active": _melee_animation_active,
		"melee_phase": _melee_phase,
		"melee_progress": _melee_progress,
		"melee_combo_step": _melee_combo_step,
		"melee_combo_count": _melee_combo_count,
		"action_offset": _action_offset,
		"action_rotation": _action_rotation,
		"reload_bar_visible": reload_progress_root.visible,
		"reload_fill_scale_x": reload_progress_fill.scale.x,
		"reload_bar_outside_visual_root": reload_progress_root.get_parent() == self,
		"reload_bar_billboarded": (
			(reload_progress_track.get_active_material(0) as StandardMaterial3D).billboard_mode
			== BaseMaterial3D.BILLBOARD_ENABLED
		),
		"weapon_grip_pose_active": _weapon_grip_pose_active,
		"weapon_pose_state": _weapon_pose_state,
		"weapon_pose_previous_state": _weapon_pose_previous_state,
		"weapon_pose_transition_count": _weapon_pose_transition_count,
		"weapon_class": _weapon_class,
		"equipped_gun_id": _equipped_gun_id,
		"weapon_fire_style": _weapon_fire_style,
		"active_grip_hand_count": _active_grip_hand_count,
		"right_hand_pivot_contract": RIGHT_HAND_PIVOT_CONTRACT,
		"right_hand_sphere_center_local": RIGHT_HAND_SPHERE_CENTER_LOCAL,
		"right_hand_model_pivot_offset": bunny_hand_r_model.position if bunny_hand_r_model != null else Vector3.ZERO,
		"right_hand_sphere_to_joint_global_distance": (
			bunny_hand_r_model.to_global(RIGHT_HAND_SPHERE_CENTER_LOCAL).distance_to(bunny_hand_r.global_position)
			if bunny_hand_r_model != null and bunny_hand_r != null else 999.0
		),
		"right_hand_sphere_to_grip_global_distance": (
			bunny_hand_r_model.to_global(RIGHT_HAND_SPHERE_CENTER_LOCAL).distance_to(weapon_socket.global_position)
			if bunny_hand_r_model != null and weapon_socket != null else 999.0
		),
		"hand_l_rotation": bunny_hand_l.rotation if bunny_hand_l != null else Vector3.ZERO,
		"hand_r_rotation": bunny_hand_r.rotation if bunny_hand_r != null else Vector3.ZERO,
		"ear_l_rotation": ear_socket_l.rotation if ear_socket_l != null else Vector3.ZERO,
		"ear_r_rotation": ear_socket_r.rotation if ear_socket_r != null else Vector3.ZERO,
		"hand_l_position": bunny_hand_l.position if bunny_hand_l != null else Vector3.ZERO,
		"hand_r_position": bunny_hand_r.position if bunny_hand_r != null else Vector3.ZERO,
		"hand_l_to_socket_distance": bunny_hand_l.position.distance_to(weapon_socket.position) if bunny_hand_l != null else 999.0,
		"hand_r_to_socket_distance": bunny_hand_r.position.distance_to(weapon_socket.position) if bunny_hand_r != null else 999.0,
		"hand_l_to_socket_global_distance": bunny_hand_l.global_position.distance_to(weapon_socket.global_position) if bunny_hand_l != null else 999.0,
		"hand_r_to_socket_global_distance": bunny_hand_r.global_position.distance_to(weapon_socket.global_position) if bunny_hand_r != null else 999.0,
		"hand_socket_offset": weapon_socket.position - hand.position,
		"model_collision_shape_count": visual_root.find_children("*", "CollisionShape3D", true, false).size(),
		"model_collision_object_count": visual_root.find_children("*", "CollisionObject3D", true, false).size(),
		"render_layer": 2,
		"avatar_shadow_caster_count": _get_avatar_shadow_caster_count(),
		"dash_dust_emitting": _state == "dashing",
		"lock_ring_visible": lock_ring.visible,
		"low_health_ring_visible": low_health_ring.visible,
	}


func _is_bunny_avatar() -> bool:
	return bunny_head_model != null and bunny_ears != null and bunny_hand_l != null and bunny_hand_r != null


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
	var next_state := _state
	if _player.has_method("get_presentation_state"):
		next_state = str(_player.call("get_presentation_state"))
	if next_state != _state:
		_previous_state = _state
		_state = next_state
		if _state == "dashing":
			_dash_animation_progress = 0.0
			if dash_dust != null:
				dash_dust.restart()
		if _state == "hurt":
			_hurt_animation_progress = 0.0
		if _state == "falling":
			_fall_animation_progress = 0.0
		if _state == "landing":
			_landing_animation_progress = 0.0
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
		_melee_animation_active = bool(action_snapshot.get("melee_active", false)) and _state != "dead"
		_melee_phase = str(action_snapshot.get("melee_phase", "ready"))
		_melee_progress = clampf(float(action_snapshot.get("melee_progress", 0.0)), 0.0, 1.0)
		_melee_combo_step = int(action_snapshot.get("melee_combo_step", 0))
		_melee_combo_count = int(action_snapshot.get("melee_combo_count", 0))
	else:
		_firing_animation_active = false
		_charging_animation_active = false
		_knockback_animation_active = false
		_melee_animation_active = false
		_melee_phase = "ready"
		_melee_progress = 0.0
		_melee_combo_step = 0
	_refresh_weapon_pose_state()


func _refresh_weapon_pose_state() -> void:
	var weapon_snapshot: Dictionary = {}
	if _player != null and _player.has_method("get_weapon_snapshot"):
		weapon_snapshot = _player.call("get_weapon_snapshot") as Dictionary
	_equipped_gun_id = str(weapon_snapshot.get("gun_id", ""))
	var has_weapon := not _equipped_gun_id.is_empty() and weapon_socket.get_child_count() > 0 and _state != "dead"
	_weapon_class = (
		"heavy_melee" if _equipped_gun_id in HEAVY_MELEE_WEAPONS
		else "sidearm" if _equipped_gun_id in SIDEARM_GUNS
		else "longgun" if has_weapon
		else "unarmed"
	)
	var profile := _get_weapon_animation_profile()
	_weapon_fire_style = str(profile.get("fire_style", "none")) if has_weapon else "none"
	_active_grip_hand_count = 1 if _weapon_class == "sidearm" else (2 if _weapon_class in ["longgun", "heavy_melee"] else 0)
	_weapon_grip_pose_active = has_weapon
	var next_pose_state := "unarmed"
	if has_weapon:
		var prefix := _weapon_class
		if _weapon_class == "heavy_melee" and _melee_animation_active:
			next_pose_state = "%s_%s" % [prefix, _melee_phase]
		elif _reload_animation_active:
			next_pose_state = "%s_reload" % prefix
		elif _firing_animation_active:
			next_pose_state = "%s_fire" % prefix
		elif _charging_animation_active:
			next_pose_state = "%s_charge" % prefix
		elif _state == "moving":
			next_pose_state = "%s_run" % prefix
		else:
			next_pose_state = "%s_hold" % prefix
	_transition_weapon_pose_state(next_pose_state)


func _transition_weapon_pose_state(next_state: String) -> void:
	if next_state not in WEAPON_POSE_STATES:
		push_warning("Rejected invalid Bunny weapon pose state: %s" % next_state)
		return
	if next_state == _weapon_pose_state:
		return
	_weapon_pose_previous_state = _weapon_pose_state
	_weapon_pose_state = next_state
	_weapon_pose_transition_count += 1


func _get_weapon_animation_profile() -> Dictionary:
	return (WEAPON_ANIMATION_PROFILES.get(
		_equipped_gun_id,
		WEAPON_ANIMATION_PROFILES["bp_rifle"]
	) as Dictionary)


func _update_orientation(delta: float) -> void:
	if _player == null:
		return
	var target_yaw := float(_player.get("aim_yaw"))
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, minf(1.0, delta * 16.0))


func _update_state_motion(delta: float) -> void:
	var linear_scale := BUNNY_LINEAR_SCALE if _is_bunny_avatar() else 1.0
	var bob := 0.0
	var move_wave := 0.0
	var move_pulse := 0.0
	var dash_arch := 0.0
	var hurt_arch := 0.0
	var hurt_overshoot := 0.0
	var fall_arch := 0.0
	var landing_arch := 0.0
	var target_position := Vector3.ZERO
	var target_scale := Vector3.ONE
	var target_roll := 0.0
	var body_scale_target: Vector3 = _base_scales["body"]
	var head_scale_target: Vector3 = _base_scales["head"]
	_idle_animation_active = _state == "idle"
	_idle_breath = 0.0
	_idle_weight_shift = 0.0
	_idle_ear_flick = 0.0
	match _state:
		"idle":
			# 正式站立循环：约 2.38 秒一次呼吸，重心换脚采用半速错相。
			# 它由八态状态机的 idle 唯一驱动，移动输入出现后本帧立即退出。
			_idle_cycle = fmod(_idle_cycle + delta * TAU * IDLE_LOOP_HZ, TAU)
			_idle_breath = sin(_idle_cycle)
			_idle_weight_shift = sin(_idle_cycle * 0.5 - PI * 0.25)
			_idle_ear_flick = pow(maxf(0.0, sin(_elapsed * TAU * 0.18 + 1.10)), 12.0)
			bob = _idle_breath * 0.024
			target_position = Vector3(_idle_weight_shift * 0.014, _idle_breath * 0.008, 0.0)
			target_roll = _idle_weight_shift * 0.018
			target_scale = Vector3(
				1.0 + _idle_breath * 0.012,
				1.0 - _idle_breath * 0.018,
				1.0 + _idle_breath * 0.010
			)
			body_scale_target = _base_scales["body"] * Vector3(
				1.0 + _idle_breath * 0.026,
				1.0 - _idle_breath * 0.036,
				1.0 + _idle_breath * 0.022
			)
			head_scale_target = _base_scales["head"] * Vector3(
				1.0 - _idle_breath * 0.010,
				1.0 + _idle_breath * 0.014,
				1.0 - _idle_breath * 0.008
			)
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
			var dash_duration := 0.18
			if _player != null and _player.has_method("get_dash_duration"):
				dash_duration = maxf(0.01, float(_player.call("get_dash_duration")))
			# 动画播放速度比位移低 30%：动画周期 = dash_duration * 1.3，
			# 实际冲刺 0.204s 时只跑完 1/1.3 ≈ 77% 的旋转帧，
			# 视觉上角色翻滚明显慢于位移，比"身位始终贴末尾"更耐看。
			var dash_animation_duration := dash_duration * 1.3
			_dash_animation_progress = clampf(
				_dash_animation_progress + delta / dash_animation_duration, 0.0, 1.0
			)
			dash_arch = sin(_dash_animation_progress * PI)
			var dash_angle := _dash_animation_progress * TAU
			var roll_pivot_height := 1.2375
			bob = 0.0
			target_scale = Vector3(
				lerpf(0.78, 0.68, dash_arch),
				lerpf(0.78, 0.62, dash_arch),
				lerpf(1.36, 1.55, dash_arch)
			)
			# VisualRoot 原点在脚底。同步补偿旋转中心到角色半高，让整只兔子绕身体
			# 中心翻滚，避免 90°/180° 时头身钻入地面而只剩手脚和枪。
			target_position = Vector3(
				0.0,
				roll_pivot_height * (1.0 - cos(dash_angle)) + dash_arch * 0.08,
				-roll_pivot_height * sin(dash_angle) - dash_arch * 0.08
			)
		"hurt":
			var hurt_duration := 0.30
			if _player != null and _player.has_method("get_hurt_recovery_duration"):
				hurt_duration = maxf(0.14, float(_player.call("get_hurt_recovery_duration")))
			_hurt_animation_progress = clampf(_hurt_animation_progress + delta / hurt_duration, 0.0, 1.0)
			hurt_arch = sin(_hurt_animation_progress * PI)
			hurt_overshoot = sin(_hurt_animation_progress * TAU) * (1.0 - _hurt_animation_progress)
			bob = hurt_overshoot * 0.11
			target_scale = Vector3(
				1.0 + hurt_arch * 0.24,
				1.0 - hurt_arch * 0.34,
				1.0 + hurt_arch * 0.15
			)
			target_position = Vector3(hurt_overshoot * 0.12, hurt_arch * 0.12, hurt_arch * 0.10)
			target_roll = hurt_overshoot * 0.34
		"falling":
			_fall_animation_progress += delta
			var fall_speed_ratio := 0.35
			if _player != null and _player.has_method("get_fall_speed_ratio"):
				fall_speed_ratio = float(_player.call("get_fall_speed_ratio"))
			fall_arch = clampf(
				1.0 - exp(-_fall_animation_progress * 7.0),
				0.0,
				1.0
			) * lerpf(0.55, 1.0, fall_speed_ratio)
			target_position = Vector3(0.0, 0.05, 0.04) * fall_arch
			target_scale = Vector3(
				1.0 - fall_arch * 0.08,
				1.0 + fall_arch * 0.13,
				1.0 - fall_arch * 0.06
			)
			body_scale_target = _base_scales["body"] * Vector3(
				1.0 - fall_arch * 0.07,
				1.0 + fall_arch * 0.15,
				1.0 - fall_arch * 0.05
			)
			head_scale_target = _base_scales["head"] * Vector3(
				1.0 + fall_arch * 0.025,
				1.0 - fall_arch * 0.035,
				1.0 + fall_arch * 0.025
			)
		"landing":
			var landing_duration := 0.18
			if _player != null and _player.has_method("get_landing_duration"):
				landing_duration = maxf(0.01, float(_player.call("get_landing_duration")))
			_landing_animation_progress = clampf(
				_landing_animation_progress + delta / landing_duration,
				0.0,
				1.0
			)
			landing_arch = sin(_landing_animation_progress * PI)
			target_position = Vector3(0.0, -landing_arch * 0.10, 0.03 * landing_arch)
			target_scale = Vector3(
				1.0 + landing_arch * 0.22,
				1.0 - landing_arch * 0.30,
				1.0 + landing_arch * 0.18
			)
			body_scale_target = _base_scales["body"] * Vector3(
				1.0 + landing_arch * 0.25,
				1.0 - landing_arch * 0.35,
				1.0 + landing_arch * 0.20
			)
			head_scale_target = _base_scales["head"] * Vector3(
				1.0 + landing_arch * 0.08,
				1.0 - landing_arch * 0.10,
				1.0 + landing_arch * 0.08
			)
		"locked":
			bob = sin(_elapsed * TAU * 0.8) * 0.012
			target_scale = Vector3(0.97, 0.97, 0.97)
		"dead":
			var death_progress := 1.0
			if _player != null and _player.has_method("get_death_animation_progress"):
				death_progress = float(_player.call("get_death_animation_progress"))
			var launch_phase := clampf(death_progress / 0.38, 0.0, 1.0)
			var bounce_phase := clampf((death_progress - 0.38) / 0.28, 0.0, 1.0)
			var settle_phase := clampf((death_progress - 0.66) / 0.34, 0.0, 1.0)
			var launch_arch := sin(launch_phase * PI)
			var bounce_arch := sin(bounce_phase * PI) if death_progress >= 0.38 else 0.0
			bob = 0.0
			target_position = Vector3(
				0.14 * smoothstep(0.0, 1.0, death_progress),
				launch_arch * 0.20 + bounce_arch * 0.08 + 0.12 * settle_phase,
				0.10 * launch_arch
			)
			target_scale = Vector3(
				1.0 + launch_arch * 0.08 + bounce_arch * 0.10,
				1.0 - bounce_arch * 0.24 - settle_phase * 0.22,
				1.0 + bounce_arch * 0.08 - settle_phase * 0.08
			)
			target_roll = lerpf(0.0, 1.50, smoothstep(0.08, 0.88, death_progress))
	bob *= linear_scale
	target_position *= linear_scale
	_moving_animation_active = _state == "moving"
	var reload_arch := sin(_reload_progress * PI) if _reload_animation_active else 0.0
	var service_tick := sin(_reload_progress * TAU * 2.0) * reload_arch
	_reload_offset = Vector3(
		-reload_arch * 0.07,
		-reload_arch * 0.16 + service_tick * 0.025,
		reload_arch * 0.07
	) * linear_scale
	_reload_rotation = Vector3(
		reload_arch * 0.20,
		0.0,
		-reload_arch * 0.30 + service_tick * 0.055
	)
	var fire_arch := sin(_fire_progress * PI) * _fire_intensity if _firing_animation_active else 0.0
	var charge_wave := sin(_elapsed * TAU * 2.4) * 0.5 + 0.5
	var charge_arch := _charge_progress * (0.72 + charge_wave * 0.28) if _charging_animation_active else 0.0
	var knockback_arch := sin(_knockback_progress * PI) if _knockback_animation_active else 0.0
	var weapon_profile := _get_weapon_animation_profile()
	var weapon_kick := float(weapon_profile.get("kick", 1.0))
	var weapon_pitch := float(weapon_profile.get("pitch", 0.24))
	var weapon_roll := float(weapon_profile.get("roll", 0.0))
	var weapon_lift := float(weapon_profile.get("lift", 0.026))
	_weapon_socket_pose_offset = SIDEARM_SOCKET_OFFSET if _weapon_class == "sidearm" else Vector3.ZERO
	_weapon_socket_pose_rotation = Vector3.ZERO
	match _weapon_pose_state:
		"sidearm_hold":
			# 待机保持低位警戒位置，但枪管 -Z 轴始终与真实 aim_direction 同向。
			# 呼吸只做平移，禁止再次给整把枪叠加俯仰/偏航/侧滚。
			_weapon_socket_pose_offset += SIDEARM_HOLD_SOCKET_OFFSET + Vector3(
				_idle_weight_shift * 0.008,
				_idle_breath * 0.010,
				-_idle_breath * 0.006
			)
			_weapon_socket_pose_rotation = SIDEARM_HOLD_SOCKET_ROTATION
		"longgun_hold":
			_weapon_socket_pose_offset += Vector3(
				_idle_weight_shift * 0.006,
				_idle_breath * 0.008,
				-_idle_breath * 0.005
			)
			_weapon_socket_pose_rotation = Vector3(
				-_idle_breath * 0.014,
				0.0,
				-_idle_weight_shift * 0.014
			)
		"sidearm_run":
			_weapon_socket_pose_offset += Vector3(move_wave * 0.025, move_pulse * 0.060, move_pulse * 0.035)
			_weapon_socket_pose_rotation = Vector3(-0.08 + move_pulse * 0.13, move_wave * 0.035, -move_wave * 0.10)
		"longgun_run":
			_weapon_socket_pose_offset += Vector3(0.0, move_pulse * 0.035, 0.075 + move_pulse * 0.020)
			_weapon_socket_pose_rotation = Vector3(0.10 + move_pulse * 0.045, 0.0, -move_wave * 0.045)
		"sidearm_reload":
			_weapon_socket_pose_rotation = Vector3(0.06, 0.0, -0.08)
		"longgun_reload":
			_weapon_socket_pose_rotation = Vector3(0.04, 0.0, -0.04)
		"heavy_melee_hold":
			_weapon_socket_pose_offset += Vector3(0.0, -0.05, 0.12)
			_weapon_socket_pose_rotation = Vector3(-0.18, 0.0, 0.10)
		"heavy_melee_run":
			_weapon_socket_pose_offset += Vector3(0.0, -0.03 + move_pulse * 0.04, 0.17)
			_weapon_socket_pose_rotation = Vector3(-0.26 + move_pulse * 0.08, 0.0, -move_wave * 0.06)
		"heavy_melee_windup":
			var windup_sign := -1.0 if _melee_combo_step == 1 else 1.0
			_weapon_socket_pose_offset += Vector3(windup_sign * 0.16 * _melee_progress, 0.05, 0.12)
			_weapon_socket_pose_rotation = (
				Vector3(-1.02 * _melee_progress, 0.0, 0.0)
				if _melee_combo_step == 3
				else Vector3(-0.16, windup_sign * 1.12 * _melee_progress, windup_sign * 0.34 * _melee_progress)
			)
		"heavy_melee_active":
			var swing_sign := -1.0 if _melee_combo_step == 1 else 1.0
			var sweep := lerpf(-1.0, 1.0, smoothstep(0.0, 1.0, _melee_progress))
			_weapon_socket_pose_offset += Vector3(-swing_sign * sweep * 0.20, 0.08, -0.03)
			_weapon_socket_pose_rotation = (
				Vector3(lerpf(-1.02, 0.82, _melee_progress), 0.0, 0.0)
				if _melee_combo_step == 3
				else Vector3(-0.12, swing_sign * sweep * 1.32, swing_sign * sweep * 0.40)
			)
		"heavy_melee_recovery":
			var recovery_weight := 1.0 - smoothstep(0.0, 1.0, _melee_progress)
			_weapon_socket_pose_offset += Vector3(0.0, 0.02, 0.10 * recovery_weight)
			_weapon_socket_pose_rotation = Vector3(0.28 * recovery_weight, 0.0, -0.16 * recovery_weight)
	_weapon_socket_pose_offset *= linear_scale
	var local_knockback := Vector3.ZERO
	if _knockback_animation_active and _knockback_direction.length_squared() > 0.001:
		local_knockback = visual_root.global_basis.inverse() * _knockback_direction
		local_knockback.y = 0.0
		local_knockback = local_knockback.normalized()
	_action_offset = Vector3(
		-fire_arch * weapon_roll * 0.08 + local_knockback.x * knockback_arch * 0.052,
		fire_arch * weapon_lift - charge_arch * 0.032 + knockback_arch * 0.026,
		fire_arch * 0.105 * weapon_kick + charge_arch * 0.052 + local_knockback.z * knockback_arch * 0.052
	) * linear_scale
	_action_rotation = Vector3(
		fire_arch * weapon_pitch + charge_arch * 0.10,
		charge_arch * 0.06,
		fire_arch * weapon_roll + local_knockback.x * knockback_arch * 0.18
	)
	if _melee_animation_active:
		var melee_body_arch := sin(_melee_progress * PI)
		var melee_side := -1.0 if _melee_combo_step == 1 else 1.0
		target_position += Vector3(-melee_side * melee_body_arch * 0.08, -melee_body_arch * 0.03, 0.04) * linear_scale
		target_roll += melee_side * melee_body_arch * (0.16 if _melee_combo_step < 3 else 0.06)
		body_scale_target *= Vector3(1.0 + melee_body_arch * 0.05, 1.0 - melee_body_arch * 0.04, 1.0 + melee_body_arch * 0.03)
	if _firing_animation_active:
		target_position += Vector3(0.0, -fire_arch * 0.018, fire_arch * 0.045) * linear_scale
		target_scale *= Vector3(1.0 + fire_arch * 0.055, 1.0 - fire_arch * 0.075, 1.0 - fire_arch * 0.035)
		body_scale_target *= Vector3(1.0 + fire_arch * 0.045, 1.0 - fire_arch * 0.08, 1.0 - fire_arch * 0.025)
	if _charging_animation_active:
		target_position += Vector3(0.0, -charge_arch * 0.026, 0.0) * linear_scale
		target_scale *= Vector3(1.0 - charge_arch * 0.035, 1.0 - charge_arch * 0.055, 1.0 - charge_arch * 0.035)
	if _knockback_animation_active:
		target_position += (
			local_knockback * knockback_arch * 0.16
			+ Vector3(0.0, knockback_arch * 0.045, 0.0)
		) * linear_scale
		target_scale *= Vector3(1.0 + knockback_arch * 0.10, 1.0 - knockback_arch * 0.13, 1.0 + knockback_arch * 0.07)
		target_roll += local_knockback.x * knockback_arch * 0.18

	visual_root.position = visual_root.position.lerp(target_position, minf(1.0, delta * 15.0))
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(1.0, delta * 17.0))
	# Godot 本地 -Z 是角色正前方；绕本地 X 轴完成一次前滚。直接写入完整相位，
	# 避免 lerp_angle 将 2π 当作零而吞掉整圈翻滚。
	visual_root.rotation.x = smoothstep(0.0, 1.0, _dash_animation_progress) * TAU if _state == "dashing" else 0.0
	visual_root.rotation.z = lerp_angle(visual_root.rotation.z, target_roll, minf(1.0, delta * 11.0))

	body.position = body.position.lerp(
		_base_positions["body"] + Vector3(
			_idle_weight_shift * 0.018 * linear_scale,
			bob - (fire_arch * 0.016 + charge_arch * 0.018 + hurt_arch * 0.04) * linear_scale,
			hurt_arch * 0.035 * linear_scale
		),
		minf(1.0, delta * 18.0)
	)
	body.scale = body.scale.lerp(body_scale_target * Vector3(1.0 + hurt_arch * 0.12, 1.0 - hurt_arch * 0.18, 1.0 + hurt_arch * 0.08), minf(1.0, delta * 21.0))
	body.rotation = body.rotation.lerp(_base_rotations["body"] + Vector3(-hurt_arch * 0.28, 0.0, -move_wave * 0.034 + _idle_weight_shift * 0.026 + fire_arch * 0.035 + hurt_overshoot * 0.22), minf(1.0, delta * 17.0))
	head.position = head.position.lerp(
		_base_positions["head"] + Vector3(
			(-_idle_weight_shift * 0.010 + hurt_overshoot * 0.05) * linear_scale,
			bob * (0.46 if _state == "moving" else 0.62)
				+ (-fire_arch * 0.012 + hurt_arch * 0.10) * linear_scale,
			(fire_arch * 0.018 + hurt_arch * 0.09) * linear_scale
		),
		minf(1.0, delta * 19.0)
	)
	head.scale = head.scale.lerp(head_scale_target * Vector3(1.0 - hurt_arch * 0.06, 1.0 + hurt_arch * 0.10, 1.0 - hurt_arch * 0.06), minf(1.0, delta * 19.0))
	head.rotation = head.rotation.lerp(_base_rotations["head"] + Vector3(_idle_breath * 0.014 + fire_arch * 0.035 + hurt_arch * 0.46, 0.0, -_idle_weight_shift * 0.038 + move_wave * 0.048 - knockback_arch * local_knockback.x * 0.11 - hurt_overshoot * 0.38), minf(1.0, delta * 18.0))
	scarf.position = scarf.position.lerp(
		_base_positions["scarf"] + Vector3(
			move_wave * (0.045 if _state == "moving" else 0.018) * linear_scale,
			bob * 0.62,
			(0.02 + move_pulse * 0.035) * linear_scale
		),
		minf(1.0, delta * 9.0)
	)
	scarf.rotation = scarf.rotation.lerp(_base_rotations["scarf"] + Vector3(move_wave * 0.06, 0.0, -move_wave * 0.08 - fire_arch * 0.04), minf(1.0, delta * 8.0))
	feet.position = feet.position.lerp(_base_positions["feet"] + Vector3(0.0, bob * 0.18, 0.0), minf(1.0, delta * 18.0))
	feet.rotation = feet.rotation.lerp(_base_rotations["feet"] + Vector3(0.0, 0.0, -move_wave * 0.022 + _idle_weight_shift * 0.010), minf(1.0, delta * 16.0))
	var left_step := (maxf(0.0, move_wave) * 0.105 if _state == "moving" else 0.0) * linear_scale
	var right_step := (maxf(0.0, -move_wave) * 0.105 if _state == "moving" else 0.0) * linear_scale
	var idle_left_lift := maxf(0.0, -_idle_weight_shift) * 0.008 * linear_scale
	var idle_right_lift := maxf(0.0, _idle_weight_shift) * 0.008 * linear_scale
	foot_l.position = foot_l.position.lerp(
		_base_positions["foot_l"] + Vector3(
			(-_idle_weight_shift * 0.006 - hurt_arch * 0.08) * linear_scale,
			left_step + idle_left_lift + (hurt_arch * 0.18 + fall_arch * 0.16) * linear_scale,
			-left_step * 0.34 + (hurt_arch * 0.10 + fall_arch * 0.12) * linear_scale
		),
		minf(1.0, delta * 22.0)
	)
	foot_r.position = foot_r.position.lerp(
		_base_positions["foot_r"] + Vector3(
			(-_idle_weight_shift * 0.006 + hurt_arch * 0.08) * linear_scale,
			right_step + idle_right_lift + (hurt_arch * 0.12 + fall_arch * 0.16) * linear_scale,
			-right_step * 0.34 + (hurt_arch * 0.06 + fall_arch * 0.12) * linear_scale
		),
		minf(1.0, delta * 22.0)
	)
	foot_l.rotation = foot_l.rotation.lerp(_base_rotations["foot_l"] + Vector3(-move_wave * 0.18 - hurt_arch * 0.52, 0.0, move_wave * 0.035 + hurt_arch * 0.20), minf(1.0, delta * 20.0))
	foot_r.rotation = foot_r.rotation.lerp(_base_rotations["foot_r"] + Vector3(move_wave * 0.18 - hurt_arch * 0.38, 0.0, move_wave * 0.035 - hurt_arch * 0.16), minf(1.0, delta * 20.0))
	var tail_wag := sin(_elapsed * TAU * (2.0 if _state == "moving" else 0.75))
	tail_stub.rotation = tail_stub.rotation.lerp(_base_rotations["tail_stub"] + Vector3(0.0, tail_wag * (0.18 if _state == "moving" else 0.055), tail_wag * 0.045), minf(1.0, delta * 10.0))
	tail_stub.scale = tail_stub.scale.lerp(_base_scales["tail_stub"] * Vector3(1.0 + move_pulse * 0.04, 1.0 - move_pulse * 0.025, 1.0 + move_pulse * 0.04), minf(1.0, delta * 15.0))
	# HandRoot 只承载共同的移动起伏；武器后坐和换弹位移由握持手分别跟随。
	# 这样手枪的左手不会被右手的枪械后坐牵着走，长枪双手仍能共同锁住枪身。
	hand.position = hand.position.lerp(_base_positions["hand"] + Vector3(0, bob * 0.56, 0), minf(1.0, delta * 18.0))
	weapon_socket.position = weapon_socket.position.lerp(
		_base_positions["weapon_socket"] + _weapon_socket_pose_offset
		+ Vector3(0, bob * 0.56, 0) + _reload_offset + _action_offset,
		minf(1.0, delta * 18.0)
	)
	scarf.scale = scarf.scale.lerp(_base_scales["scarf"], minf(1.0, delta * 14.0))
	feet.scale = feet.scale.lerp(_base_scales["feet"] * Vector3(1.0 + move_pulse * 0.035, 1.0 - move_pulse * 0.025, 1.0 + move_pulse * 0.045), minf(1.0, delta * 17.0))
	foot_l.scale = foot_l.scale.lerp(_base_scales["foot_l"] * Vector3(1.0 + maxf(0.0, _idle_weight_shift) * 0.020, 1.0 - maxf(0.0, _idle_weight_shift) * 0.025, 1.0), minf(1.0, delta * 18.0))
	foot_r.scale = foot_r.scale.lerp(_base_scales["foot_r"] * Vector3(1.0 + maxf(0.0, -_idle_weight_shift) * 0.020, 1.0 - maxf(0.0, -_idle_weight_shift) * 0.025, 1.0), minf(1.0, delta * 18.0))
	var grip_squeeze := fire_arch * 0.13 + charge_arch * 0.06 + move_pulse * 0.025
	hand.scale = hand.scale.lerp(_base_scales["hand"] * Vector3(1.0 + grip_squeeze, 1.0 - grip_squeeze * 0.45, 1.0 - grip_squeeze * 0.22), minf(1.0, delta * 16.0))
	# 3D 瞄准由整个 VisualRoot 绕 Y 轴完成；HandRoot 不继承武器旋转，
	# 单手/双手握持的跟随量由每只手的独立关键姿势决定。
	hand.rotation = hand.rotation.lerp(_base_rotations["hand"], minf(1.0, delta * 20.0))
	# 子弹方向由 aim_direction 唯一决定；开火时枪身只沿枪轴后坐，不再旋转离开射线。
	# 换弹和蓄力仍保留原有服务角度，近战也继续使用动作子状态机旋转。
	var weapon_action_rotation := _action_rotation
	if _firing_animation_active and _weapon_class in ["sidearm", "longgun"]:
		weapon_action_rotation = Vector3.ZERO
	weapon_socket.rotation = weapon_socket.rotation.lerp(
		_base_rotations["weapon_socket"] + _weapon_socket_pose_rotation + _reload_rotation + weapon_action_rotation,
		minf(1.0, delta * 20.0)
	)
	_animate_bunny_accessories(
		delta,
		move_wave,
		move_pulse,
		fire_arch,
		charge_arch,
		knockback_arch,
		fall_arch,
		landing_arch
	)

	# DashDustBurst 是 one-shot burst：状态机进入 dashing 时通过 restart() 触发一次；
	# lifetime 0.55s 比 dash 持续时间长 0.34s，整段冲刺都能看见尘雾散开。
	# 不在 _process 里每帧重写 emitting，否则会持续重置 burst。
	lock_ring.visible = _state == "locked"
	lock_ring.rotation.y += delta * 1.7
	var low_health := bool(_player.call("is_low_health")) if _player != null and _player.has_method("is_low_health") else false
	low_health_ring.visible = low_health and _state != "dead"
	low_health_ring.scale = Vector3.ONE * (1.0 + sin(_elapsed * TAU * 2.1) * 0.06)


func _animate_bunny_accessories(
	delta: float,
	move_wave: float,
	move_pulse: float,
	fire_arch: float,
	charge_arch: float,
	knockback_arch: float,
	fall_arch: float,
	landing_arch: float
) -> void:
	if not _is_bunny_avatar():
		return
	# 兔耳承担动作的预备、跟随和收束；冲刺和受击使用明显的关键姿势，
	# 待机与移动保留较短滞后，避免持续软塌或漂浮。
	var ear_l_target: Vector3 = _base_rotations["ear_socket_l"]
	var ear_r_target: Vector3 = _base_rotations["ear_socket_r"]
	var ear_l_offset := Vector3(sin(_elapsed * TAU * 0.85) * 0.032, 0.0, 0.018)
	var ear_r_offset := Vector3(sin(_elapsed * TAU * 0.85 + 0.65) * 0.028, 0.0, -0.014)
	var ear_l_position: Vector3 = _base_positions["ear_socket_l"]
	var ear_r_position: Vector3 = _base_positions["ear_socket_r"]
	if _state == "idle":
		# 待机时双耳错相呼吸，偶发的单耳轻弹打破机械循环。
		ear_l_offset += Vector3(-_idle_breath * 0.038 + _idle_ear_flick * 0.15, _idle_weight_shift * 0.018, _idle_weight_shift * 0.030)
		ear_r_offset += Vector3(-_idle_breath * 0.030 - _idle_ear_flick * 0.055, -_idle_weight_shift * 0.014, -_idle_weight_shift * 0.024)
		ear_l_position += _motion_offset(Vector3(0.0, _idle_breath * 0.008, 0.0))
		ear_r_position += _motion_offset(Vector3(0.0, _idle_breath * 0.006, 0.0))
	elif _state == "moving":
		ear_l_offset += Vector3(-move_pulse * 0.18, move_wave * 0.035, move_wave * 0.08)
		ear_r_offset += Vector3(-move_pulse * 0.15, -move_wave * 0.030, -move_wave * 0.07)
		ear_l_position += _motion_offset(Vector3(0.0, move_pulse * 0.018, 0.0))
		ear_r_position += _motion_offset(Vector3(0.0, move_pulse * 0.014, 0.0))
	elif _state == "dashing":
		var dash_tuck := sin(_dash_animation_progress * PI)
		ear_l_offset += Vector3(-0.62 * dash_tuck, 0.08, 0.24)
		ear_r_offset += Vector3(-0.58 * dash_tuck, -0.08, -0.22)
	elif _state == "hurt":
		var hurt_snap := sin(_hurt_animation_progress * PI)
		var hurt_whip := sin(_hurt_animation_progress * TAU) * (1.0 - _hurt_animation_progress)
		ear_l_offset += Vector3(-0.68 * hurt_snap, 0.18 * hurt_whip, 0.34)
		ear_r_offset += Vector3(-0.62 * hurt_snap, -0.16 * hurt_whip, -0.30)
	elif _state == "falling":
		ear_l_offset += Vector3(-0.52 * fall_arch, 0.07, 0.18)
		ear_r_offset += Vector3(-0.48 * fall_arch, -0.07, -0.18)
	elif _state == "landing":
		ear_l_offset += Vector3(-0.38 * landing_arch, 0.10, 0.24)
		ear_r_offset += Vector3(-0.35 * landing_arch, -0.10, -0.22)
	elif _state == "locked":
		ear_l_offset += Vector3(-0.22, 0.0, 0.08)
		ear_r_offset += Vector3(-0.22, 0.0, -0.08)
	elif _state == "dead":
		ear_l_offset += Vector3(0.36, 0.18, 0.76)
		ear_r_offset += Vector3(0.30, -0.16, -0.68)
	ear_l_offset += Vector3(-fire_arch * 0.13 - charge_arch * 0.08, knockback_arch * 0.05, fire_arch * 0.04)
	ear_r_offset += Vector3(-fire_arch * 0.11 - charge_arch * 0.08, -knockback_arch * 0.05, -fire_arch * 0.04)
	ear_socket_l.position = ear_socket_l.position.lerp(ear_l_position, minf(1.0, delta * 18.0))
	ear_socket_r.position = ear_socket_r.position.lerp(ear_r_position, minf(1.0, delta * 18.0))
	ear_socket_l.rotation = ear_socket_l.rotation.lerp(ear_l_target + ear_l_offset, minf(1.0, delta * 15.0))
	ear_socket_r.rotation = ear_socket_r.rotation.lerp(ear_r_target + ear_r_offset, minf(1.0, delta * 15.0))

	# 右手模型在根场景中做了枢轴校正：大球中心就是 HandJointR；持枪时
	# HandJointR 再与枪械 GripSocket 精确重合。圆环只表示近端腕部造型，
	# 不再作为右手骨骼轴心。手枪只让右手握持，左手保持自由；长枪右手握把、左手托护木。
	# 根场景热重载的单帧中手部子节点可能尚未完成实例化；此时保留耳朵动作并跳过该帧手部细节。
	if bunny_hand_l == null or bunny_hand_r == null or not _base_positions.has("bunny_hand_l") or not _base_positions.has("bunny_hand_r"):
		_weapon_grip_pose_active = false
		_active_grip_hand_count = 0
		return
	var left_hand_target: Vector3 = _base_positions["bunny_hand_l"]
	var right_hand_target: Vector3 = _base_positions["bunny_hand_r"]
	var left_hand_rot: Vector3 = _base_rotations["bunny_hand_l"]
	var right_hand_rot: Vector3 = _base_rotations["bunny_hand_r"]
	var weapon_follow_offset := _weapon_socket_pose_offset + _reload_offset + _action_offset
	var weapon_follow_rotation := _weapon_socket_pose_rotation + _reload_rotation + _action_rotation
	if _firing_animation_active and _weapon_class in ["sidearm", "longgun"]:
		weapon_follow_rotation = _weapon_socket_pose_rotation + _reload_rotation
	if _weapon_class == "sidearm" and _weapon_grip_pose_active:
		right_hand_target = _motion_offset(SIDEARM_GRIP_HAND_R) + weapon_follow_offset
		right_hand_rot += SIDEARM_GRIP_ROTATION_R + weapon_follow_rotation
		# 手枪仍是右手单握；待机时自由左手前伸到胸前警戒位，不再垂在身体正下方。
		if _state == "idle":
			left_hand_target = _motion_offset(SIDEARM_READY_HAND_L) + _motion_offset(Vector3(
				-_idle_weight_shift * 0.010,
				_idle_breath * 0.010,
				_idle_weight_shift * 0.022
			))
			left_hand_rot += SIDEARM_READY_ROTATION_L + Vector3(
				_idle_breath * 0.022,
				0.0,
				-_idle_weight_shift * 0.045
			)
		elif _state == "moving":
			left_hand_target += _motion_offset(Vector3(-move_wave * 0.025, move_pulse * 0.045, move_wave * 0.19))
			left_hand_rot += Vector3(-move_wave * 0.62, 0.0, move_wave * 0.10)
			right_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.018, -move_wave * 0.022))
			right_hand_rot.z -= move_wave * 0.055
	elif _weapon_class == "longgun" and _weapon_grip_pose_active:
		left_hand_target = _motion_offset(LONGGUN_GRIP_HAND_L) + weapon_follow_offset
		right_hand_target = _motion_offset(LONGGUN_GRIP_HAND_R) + weapon_follow_offset
		left_hand_rot += LONGGUN_GRIP_ROTATION_L + weapon_follow_rotation
		right_hand_rot += LONGGUN_GRIP_ROTATION_R + weapon_follow_rotation
		if _state == "moving":
			# 长枪跑步保持双手锁定，枪身收向胸前，只留紧凑有力的上下脉冲。
			left_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.018, move_wave * 0.018))
			right_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.014, move_wave * 0.018))
			left_hand_rot.z -= move_wave * 0.035
			right_hand_rot.z -= move_wave * 0.035
	elif _weapon_class == "heavy_melee" and _weapon_grip_pose_active:
		# 大型近战双手沿长柄前后分开，整体跟随武器动作子状态机的挥砍姿势。
		left_hand_target = _motion_offset(Vector3(0.12, 0.54, -0.67)) + weapon_follow_offset
		right_hand_target = _motion_offset(Vector3(0.12, 0.55, -0.45)) + weapon_follow_offset
		left_hand_rot += LONGGUN_GRIP_ROTATION_L + weapon_follow_rotation + Vector3(0.08, 0.0, -0.08)
		right_hand_rot += LONGGUN_GRIP_ROTATION_R + weapon_follow_rotation + Vector3(0.10, 0.0, 0.06)
		if _state == "moving" and not _melee_animation_active:
			left_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.020, move_wave * 0.020))
			right_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.016, move_wave * 0.020))
	elif _state == "moving":
		left_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.035, move_wave * 0.16))
		right_hand_target += _motion_offset(Vector3(0.0, move_pulse * 0.030, -move_wave * 0.16))
		left_hand_rot.x -= move_wave * 0.56
		right_hand_rot.x += move_wave * 0.56
	if _firing_animation_active and _weapon_grip_pose_active:
		if _weapon_class == "sidearm":
			# 手枪使用单腕快速上挑；左手完全不继承枪械后坐。
			right_hand_target += _motion_offset(Vector3(fire_arch * 0.018, fire_arch * 0.030, fire_arch * 0.020))
			right_hand_rot += Vector3(fire_arch * 0.20, 0.0, -fire_arch * 0.12)
		else:
			# 长枪由双手和躯干共同吃后坐，腕部只做较小的刚性回弹。
			left_hand_target.z += fire_arch * 0.030 * BUNNY_LINEAR_SCALE
			right_hand_target.z += fire_arch * 0.030 * BUNNY_LINEAR_SCALE
			left_hand_rot.x += fire_arch * 0.08
			right_hand_rot.x += fire_arch * 0.10
	if _charging_animation_active:
		if _weapon_class == "longgun":
			left_hand_target += _motion_offset(Vector3(0.0, -charge_arch * 0.04, charge_arch * 0.08))
			right_hand_target += _motion_offset(Vector3(0.0, -charge_arch * 0.03, charge_arch * 0.06))
			left_hand_rot.x -= charge_arch * 0.20
			right_hand_rot.x -= charge_arch * 0.16
	if _reload_animation_active:
		var reload_arch := sin(_reload_progress * PI)
		var reload_tick := sin(_reload_progress * TAU * 2.0) * reload_arch
		if _weapon_class == "longgun":
			# 长枪左手离开护木完成服务动作；右手继续压住握把。
			left_hand_target += _motion_offset(Vector3(-reload_arch * 0.19, reload_arch * 0.13, reload_arch * 0.18 + reload_tick * 0.055))
			left_hand_rot += Vector3(reload_arch * 0.36, -reload_arch * 0.18, reload_arch * 0.52)
		else:
			# 手枪仍保持右手单手持枪，左手只做近身取弹动作，不进入握持计数。
			left_hand_target += _motion_offset(Vector3(reload_arch * 0.12, reload_arch * 0.15, -reload_arch * 0.14 + reload_tick * 0.035))
			left_hand_rot += Vector3(-reload_arch * 0.30, 0.0, -reload_arch * 0.34)
		right_hand_target += _motion_offset(Vector3(0.0, -reload_arch * 0.02, reload_arch * 0.02))
		right_hand_rot.x += reload_arch * 0.12
	if _state == "hurt":
		var hurt_snap := sin(_hurt_animation_progress * PI)
		left_hand_target += _motion_offset(Vector3(-hurt_snap * 0.09, hurt_snap * 0.08, hurt_snap * 0.05))
		right_hand_target += _motion_offset(Vector3(hurt_snap * 0.07, hurt_snap * 0.05, hurt_snap * 0.04))
		left_hand_rot.z += hurt_snap * 0.34
		right_hand_rot.z -= hurt_snap * 0.30
	bunny_hand_l.position = bunny_hand_l.position.lerp(left_hand_target, minf(1.0, delta * 22.0))
	if _weapon_grip_pose_active and _weapon_class in ["sidearm", "longgun"]:
		# HandRoot 与 WeaponSocket 分属兄弟层级；每帧将真实握把全局坐标换算回
		# HandRoot 局部空间，可避免各自动画插值造成掌球与握把短暂分离。
		bunny_hand_r.position = hand.to_local(weapon_socket.global_position)
	else:
		bunny_hand_r.position = bunny_hand_r.position.lerp(right_hand_target, minf(1.0, delta * 22.0))
	bunny_hand_l.rotation = bunny_hand_l.rotation.lerp(left_hand_rot, minf(1.0, delta * 21.0))
	bunny_hand_r.rotation = bunny_hand_r.rotation.lerp(right_hand_rot, minf(1.0, delta * 21.0))


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
	# 将原角色里的兔耳节点迁移到帽子槽位；保留原耳 socket 引用，动画继续驱动同一对挂点。
	if bunny_ears != null:
		bunny_ears.name = "HatBunnyEars"
		bunny_ears.reparent(_wearable_root, false)
		# Wearables 根为统一角色缩放；兔耳原本已在角色表现层下，抵消这一次额外缩放，
		# 保持原 HeadJoint 锚点高度和耳朵尺寸，不让耳朵缩回头部。
		bunny_ears.scale = Vector3.ONE / BUNNY_LINEAR_SCALE
		_wearable_nodes["hat_bunny_ears"] = bunny_ears
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
	var uses_chibi_anime_head: bool = (
		_is_bunny_avatar()
		and _customization["head"] == CHIBI_ANIME_HEAD_VARIANT
	)
	if _is_bunny_avatar():
		_set_slot_base_color("body", BODY_COLORS[_customization["body"]])
		if not uses_chibi_anime_head:
			_set_slot_base_color("head", HEAD_COLORS[_customization["head"]])
		_set_slot_base_color("hand", HAND_COLORS[_customization["hand"]])
		_set_slot_base_color("feet", FEET_COLORS[_customization["feet"]])
	else:
		var fallback_head_color := HEAD_COLORS.get(
			_customization["head"],
			HEAD_COLORS[DEFAULT_CUSTOMIZATION["head"]]
		) as Color
		_set_base_color("VisualRoot/Body/BodyShell", BODY_COLORS[_customization["body"]])
		_set_base_color("VisualRoot/Body/BellyPatch", BODY_COLORS[_customization["body"]].lightened(0.24))
		_set_base_color("VisualRoot/Body/TailStub", BODY_COLORS[_customization["body"]].darkened(0.06))
		_set_base_color("VisualRoot/Head/HeadShell", fallback_head_color)
		_set_base_color("VisualRoot/Head/Ears/EarL", fallback_head_color.darkened(0.04))
		_set_base_color("VisualRoot/Head/Ears/EarR", fallback_head_color.darkened(0.04))
		_set_base_color("VisualRoot/Hand/Glove", HAND_COLORS[_customization["hand"]])
		_set_base_color("VisualRoot/Feet/FootL", FEET_COLORS[_customization["feet"]])
		_set_base_color("VisualRoot/Feet/FootR", FEET_COLORS[_customization["feet"]])
	if bunny_head_model != null:
		bunny_head_model.visible = not uses_chibi_anime_head
	if bunny_ears != null:
		bunny_ears.visible = false
	if chibi_anime_head != null:
		chibi_anime_head.visible = uses_chibi_anime_head
	for wearable_id in _wearable_nodes:
		if wearable_id.ends_with("_none"):
			continue
		var wearable := _wearable_nodes[wearable_id] as Node3D
		var selected_hat := str(_customization["hat"])
		if selected_hat == "none" and _is_bunny_avatar():
			selected_hat = BUNNY_EARS_HAT_VARIANT
		var is_selected_hat: bool = wearable_id == "hat_%s" % selected_hat
		var is_selected_glasses: bool = wearable_id == "glasses_%s" % _customization["glasses"]
		# 女仆头与兔耳帽是两个独立表现槽位；其它帽子/眼镜仍避免穿插。
		wearable.visible = (
			is_selected_hat and (not uses_chibi_anime_head or selected_hat == BUNNY_EARS_HAT_VARIANT)
			or is_selected_glasses and not uses_chibi_anime_head
		)


func _set_base_color(material_path: String, color: Color) -> void:
	if not _materials.has(material_path):
		return
	_base_colors[material_path] = color
	(_materials[material_path] as StandardMaterial3D).albedo_color = color


func _set_slot_base_color(slot_id: String, color: Color) -> void:
	var prefix := "bunny_slot/%s/" % slot_id
	for material_key in _materials:
		if not str(material_key).begins_with(prefix):
			continue
		_base_colors[material_key] = color
		(_materials[material_key] as StandardMaterial3D).albedo_color = color


func _get_customization_material_counts() -> Dictionary:
	var counts := {"body": 0, "head": 0, "hand": 0, "feet": 0}
	for material_key in _materials:
		for slot_id in counts:
			if str(material_key).begins_with("bunny_slot/%s/" % slot_id):
				counts[slot_id] = int(counts[slot_id]) + 1
	return counts


func _get_customization_material_colors() -> Dictionary:
	var colors := {}
	for slot_id in ["body", "head", "hand", "feet"]:
		var prefix := "bunny_slot/%s/" % slot_id
		for material_key in _base_colors:
			if str(material_key).begins_with(prefix):
				colors[slot_id] = _base_colors[material_key]
				break
	return colors


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
	# 玩家网格保留外部灯光投影能力。玩家随身三盏灯通过 light_cull_mask
	# 避开角色层，因此不会产生手电自身阴影；太阳和房间灯仍能投射角色阴影。
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _fix_left_ear_mirror_tangent_space() -> void:
	# 左耳用 scale = (-1, 1, 1) 复用右耳 GLB。负行列式变换会改变切线空间
	# 的手性；顶点法线本身会由逆转置矩阵正确变换，不能再额外取反。这里只把
	# tangent.w 反号，让法线贴图使用正确的副切线方向，并保留原 surface 材质。
	var ear_socket := ear_socket_l
	if ear_socket == null:
		return
	var ear_root := ear_socket.get_node_or_null("EarAccessory")
	if ear_root == null:
		return
	for child in ear_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		_flip_mirror_mesh_tangent_handedness(mi)
		_disable_ear_backface_culling(mi)


func _flip_mirror_mesh_tangent_handedness(mi: MeshInstance3D) -> void:
	var source := mi.mesh
	if source == null or not (source is ArrayMesh):
		return
	var src := source as ArrayMesh
	var rebuilt := ArrayMesh.new()
	var tangents_touched := false
	for surface_index in range(src.get_surface_count()):
		var arrays: Array = src.surface_get_arrays(surface_index)
		if arrays == null or arrays.is_empty():
			continue
		var tangents := arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		if tangents != null and tangents.size() >= 4 and tangents.size() % 4 == 0:
			var corrected := tangents.duplicate()
			for tangent_w_index in range(3, corrected.size(), 4):
				corrected[tangent_w_index] = -corrected[tangent_w_index]
			arrays[Mesh.ARRAY_TANGENT] = corrected
			tangents_touched = true
		var rebuilt_surface_index := rebuilt.get_surface_count()
		rebuilt.add_surface_from_arrays(
			src.surface_get_primitive_type(surface_index),
			arrays
		)
		rebuilt.surface_set_material(rebuilt_surface_index, src.surface_get_material(surface_index))
		rebuilt.surface_set_name(rebuilt_surface_index, src.surface_get_name(surface_index))
	if tangents_touched:
		mi.mesh = rebuilt


func _disable_ear_backface_culling(mi: MeshInstance3D) -> void:
	var material := mi.material_override
	if material == null:
		material = mi.get_active_material(0)
	if material is StandardMaterial3D:
		var std_mat := material as StandardMaterial3D
		if mi.material_override == null:
			std_mat = std_mat.duplicate() as StandardMaterial3D
			mi.material_override = std_mat
		std_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _set_avatar_render_layer(layer_mask: int) -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		# 角色位于layer 2；随身灯避开该层，太阳和房间灯仍可投射角色阴影。
		mesh.layers = layer_mask
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	if _is_bunny_avatar():
		_register_bunny_slot_materials("body", body)
		_register_bunny_slot_materials("head", head)
		_register_bunny_slot_materials("hand", hand)
		_register_bunny_slot_materials("feet", feet)


func _register_bunny_slot_materials(slot_id: String, slot_root: Node) -> void:
	for child in slot_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			mesh_instance.set_surface_override_material(surface_index, material)
			var material_key := "bunny_slot/%s/%s/%d" % [slot_id, str(mesh_instance.get_path()), surface_index]
			if slot_id == "head" and str(mesh_instance.get_path()).contains("HeadAccessoryChibiAnime"):
				material_key = "bunny_head_accessory/authored/%s/%d" % [str(mesh_instance.get_path()), surface_index]
			_materials[material_key] = material
			_base_colors[material_key] = material.albedo_color


func _find_player() -> Node:
	var node := get_parent()
	for _index in range(5):
		if node == null:
			return null
		if node.is_in_group("player") and node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null
