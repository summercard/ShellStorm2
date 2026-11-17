extends Node3D
## 旧 fat_zombie03 玩法与新 fat_zombie21 视觉之间的单向适配器。
## 采样导入动作、支撑骨世界锚定及材质反馈；状态、根位移、碰撞、伤害与死亡计时归 Enemy3D。

const VfxPool3D = preload("res://src/vfx/VfxPool3D.gd")
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
const CLIP_BY_STATE := {
	"dormant": "idle", "idle": "idle", "patrol": "walking", "alert": "idle",
	"chase": "running", "search": "running", "return": "running",
	"telegraph": "attack", "attack": "attack", "recovery": "attack",
	"stagger": "idle", "dead": "idle"
}
const SOURCE_FPS := 60.0
const ATTACK_CONTACT_FRAME := 78.0
const FLASH_DURATION := 0.12
const WARNING_PEAK_ENERGY := 0.35
const WARNING_EMISSION_COLOR := Color(0.32, 0.55, 0.10)
const GAIT_REFERENCE_SCALE := 2.7557166
const GAIT_STRIDES := {"walking": 0.6, "running": 0.72}
const MOVEMENT_STATES := ["patrol", "chase", "search", "return"]

const CONTACT_GROUPS := {
	"Lfoot": ["L_Calf", "L_CalfTwist01", "L_CalfTwist02", "L_Foot", "L_ToeBase"],
	"Rfoot": ["R_Calf", "R_CalfTwist01", "R_CalfTwist02", "R_Foot", "R_ToeBase"],
	"Lhand": ["L_Forearm", "L_ForearmTwist01", "L_ForearmTwist02", "L_Hand"],
	"Rhand": ["R_Forearm", "R_ForearmTwist01", "R_ForearmTwist02", "R_Hand"]
}

var _skeleton: Skeleton3D
var _contact_bones: Dictionary = {}
var _contact_anchors: Dictionary = {}
var _source_poses: Array[Transform3D] = []
var _gait_unwrapped := 0.0
var _switch_poses: Array[Transform3D] = []
var _switch_time := 0.0
var _release: Dictionary = {}

var _gait_phase := 0.0
var _gait_stride := 0.0
var _travel_distance := 0.0
var _frame_distance := 0.0
var _position_anchor := Vector3.ZERO
var _anchor_valid := false
var _motion_root: Node3D
var _visual_glb: Node3D

var _player: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _flash_baseline: Array = []
var _flash_time := 0.0
var _warning_progress := 0.0
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _attack_visual_frame := 0.0
var _slam_fx_fired := false
var _slam_fx_count := 0
var _event := ""
var _event_anchor := 0.0

func _clear_contacts() -> void:
	_contact_anchors.clear()
	_release.clear()
	_switch_poses.clear()

func _exit_tree() -> void:
	_anchor_valid = false
	_clear_contacts()

func _ready() -> void:
	_visual_glb = get_node("VisualGLB") as Node3D
	_motion_root = get_parent() as Node3D
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is CharacterBody3D:
			_motion_root = ancestor as Node3D
			break
		ancestor = ancestor.get_parent()
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "胖子僵尸2.1缺少 AnimationPlayer")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	assert(_skeleton != null)
	for group in CONTACT_GROUPS:
		var bones: Array[int] = []
		for name in CONTACT_GROUPS[group]:
			var index := _skeleton.find_bone(name)
			assert(index >= 0, "缺少支撑骨: " + name)
			bones.append(index)
		# 原骨索引是父先子后；显式按深度排序以兼容导入顺序。
		bones.sort_custom(func(a: int, b: int) -> bool: return _bone_depth(a) < _bone_depth(b))
		_contact_bones[group] = bones
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, material)
				_materials.append(material)
	_flash_baseline = HitFlash.prepare(_materials)
	sync_state("idle", 0.0, 0.0, 1.2, 1.3, 0.0)

func _process(delta: float) -> void:
	if _state in ["dormant", "death_warning"]:
		return
	_flash_time = maxf(0.0, _flash_time - delta)
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

func sync_state(
	state: String, state_time: float, _speed: float,
	telegraph_duration: float, recovery_duration: float, _base_speed := 0.0
) -> void:
	if _player == null or not is_inside_tree():
		_anchor_valid = false
		_clear_contacts()
		return
	var previous_clip := _clip
	var previous_poses: Array[Transform3D] = []
	if state in MOVEMENT_STATES and _state in MOVEMENT_STATES:
		for bone in _skeleton.get_bone_count():
			previous_poses.append(_skeleton.get_bone_pose(bone))
	else:
		_clear_contacts()
	if _state == "death_warning" and state != "death_warning":
		position = Vector3.ZERO
		rotation.z = 0.0
		HitFlash.restore(_flash_baseline)
	if state != _state:
		_event = ""
		_event_anchor = state_time
		if _state == "patrol" and state == "idle":
			_event = "move_stop"
	_state = state
	_clip = str(CLIP_BY_STATE.get(state, "idle"))
	var length := _player.get_animation(_clip).length
	var contact := ATTACK_CONTACT_FRAME / SOURCE_FPS
	_frame_distance = 0.0
	if is_inside_tree() and is_instance_valid(_motion_root):
		var current := _motion_root.global_position
		if _anchor_valid:
			var displacement := current - _position_anchor
			displacement.y = 0.0
			_frame_distance = displacement.length()
		_position_anchor = current
		_anchor_valid = state not in ["dead", "death_warning"]
	else:
		_anchor_valid = false
	if state in MOVEMENT_STATES:
		# global_basis 包含 Enemy3D 基础体型与强化倍率；旋转不改变标量。
		var actual_scale := _visual_glb.global_basis.get_scale().abs()
		_gait_stride = float(GAIT_STRIDES[_clip]) * (actual_scale.x + actual_scale.z) * 0.5 / GAIT_REFERENCE_SCALE
		# 大跨度视作瞬移，只更新锚点，不把传送距离变成步数。
		if _frame_distance > maxf(1.0, _gait_stride * 2.0):
			_frame_distance = 0.0
			_clear_contacts()
		var phase_step := _frame_distance / maxf(_gait_stride, 0.000001)
		if phase_step >= 1.0:
			_clear_contacts()
		_gait_unwrapped += phase_step
		_gait_phase = fposmod(_gait_unwrapped, 1.0)
		_travel_distance += _frame_distance
		_event = ""
	elif _frame_distance > 0.000001:
		_event = ""
	match state:
		"telegraph":
			# 将源 F0..F78 映射到原玩法前摇，不改变 1.2 秒伤害边界。
			_sample = contact * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		"attack":
			_sample = contact
		"recovery":
			_sample = lerpf(contact, length, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
		"patrol", "chase", "search", "return":
			_sample = _gait_phase * length
		"dormant", "stagger", "dead", "death_warning":
			_sample = 0.0
		_:
			_sample = fmod(maxf(0.0, state_time), length)
	if not _event.is_empty():
		var progress := maxf(0.0, state_time - _event_anchor)
		if progress < _player.get_animation(_event).length:
			_clip = _event
			_sample = progress
		else:
			_event = ""
	# 先还原上一采样的源局部pose，防止稀疏曲线未写到的分量累积锁脚补偿。
	for bone in _source_poses.size():
		_skeleton.set_bone_pose(bone, _source_poses[bone])
	_player.play(_clip)
	_player.seek(_sample, true)
	_player.advance(0.0)
	_source_poses.clear()
	for bone in _skeleton.get_bone_count():
		_source_poses.append(_skeleton.get_bone_pose(bone))
		if state in MOVEMENT_STATES:
			_skeleton.set_bone_pose_scale(bone, Vector3.ONE)
	if state in MOVEMENT_STATES:
		if previous_clip != _clip and not previous_poses.is_empty():
			# previous_poses已含上帧锁锚；切换时不能再次叠加旧的离地纠偏。
			_release.clear()
			_switch_poses = previous_poses
			_switch_time = _gait_unwrapped
		if not _switch_poses.is_empty():
			var mix := smoothstep(0.0, 0.08, _gait_unwrapped - _switch_time)
			for bone in _skeleton.get_bone_count():
				var target_pose := _source_poses[bone]
				target_pose.basis = target_pose.basis.orthonormalized()
				_skeleton.set_bone_pose(bone, _switch_poses[bone].interpolate_with(target_pose, mix))
			if mix >= 1.0:
				_switch_poses.clear()
		var body := _motion_root as CharacterBody3D
		if body != null and not body.is_on_floor() and absf(body.velocity.y) > 0.01:
			_clear_contacts()
		else:
			_lock_contacts()
	_attack_visual_frame = _sample * SOURCE_FPS if state in ["telegraph", "attack", "recovery"] else 0.0
	if state not in ["telegraph", "attack", "recovery"]:
		_slam_fx_fired = false
	elif state == "telegraph" and state_time <= 0.001:
		_slam_fx_fired = false
	elif state in ["attack", "recovery"] and not _slam_fx_fired and _sample >= contact - 0.00001:
		_fire_slam_fx()

func _bone_depth(bone: int) -> int:
	var depth := 0
	while bone >= 0:
		depth += 1
		bone = _skeleton.get_bone_parent(bone)
	return depth

func _lock_contacts() -> void:
	_skeleton.force_update_all_bone_transforms()
	var skeleton_world := _skeleton.global_transform
	var world_inverse := skeleton_world.affine_inverse()
	# 所有组都从尚未修改的同一pose快照计算，不能读到别组刚写入的姿态。
	var original: Array[Transform3D] = []
	for bone in _skeleton.get_bone_count():
		original.append(skeleton_world * _skeleton.get_bone_global_pose(bone))
	var duty := 0.60 if _clip == "walking" else 0.61
	for group in _contact_bones:
		var offset := 0.5 if group in ["Rfoot", "Lhand"] else 0.0
		var local_phase := fposmod(_gait_unwrapped + offset, 1.0)
		var segment := int(floor(_gait_unwrapped + offset))
		var bones: Array = _contact_bones[group]
		var reference: Transform3D = original[bones[-1]]
		var rigid := Transform3D(reference.basis.orthonormalized(), reference.origin)
		var delta := Transform3D.IDENTITY
		if local_phase < duty:
			if not _contact_anchors.has(group) or int(_contact_anchors[group].segment) != segment:
				_contact_anchors[group] = {"segment": segment, "world": rigid}
			delta = _contact_anchors[group].world * rigid.affine_inverse()
			_release[group] = {"delta": delta, "phase": _gait_unwrapped}
		else:
			_contact_anchors.erase(group)
			# 只在离地后消退上次刚体纠偏，防止解除世界锚时弹回；不延长plant窗口。
			if _release.has(group):
				var mix := smoothstep(0.0, 0.12, _gait_unwrapped - float(_release[group].phase))
				delta = _release[group].delta.interpolate_with(Transform3D.IDENTITY, mix)
				if mix >= 1.0:
					_release.erase(group)
		for bone in bones:
			_skeleton.set_bone_global_pose(bone, world_inverse * delta * original[bone])
	_skeleton.force_update_all_bone_transforms()

func flash_hit(_play_hit_pose := true) -> void:
	# 当前源无 hurt/hit_light，保留闪白，不伪造全身或局部受击动作。
	if _state not in ["dead", "death_warning"]:
		_flash_time = FLASH_DURATION
		HitFlash.apply(_materials, _flash_baseline, 1.0)

func sync_death_warning(elapsed: float, duration: float) -> void:
	if _player == null:
		return
	_anchor_valid = false
	_clear_contacts()
	for bone in _source_poses.size():
		_skeleton.set_bone_pose(bone, _source_poses[bone])
	_frame_distance = 0.0
	_state = "death_warning"
	_clip = "idle"
	_sample = 0.0
	_flash_time = 0.0
	_warning_progress = clampf(elapsed / maxf(0.001, duration), 0.0, 1.0)
	_player.play("idle")
	_player.seek(0.0, true)
	_player.advance(0.0)
	position = Vector3(sin(elapsed * 93.0) * 0.035, 0.0, sin(elapsed * 117.0) * 0.025)
	rotation.z = sin(elapsed * 105.0) * 0.018
	for entry in _flash_baseline:
		var record := entry as Dictionary
		var material := record["material"] as StandardMaterial3D
		material.emission = WARNING_EMISSION_COLOR
		var energy := float(record["energy"]) + WARNING_PEAK_ENERGY * _warning_progress * _warning_progress
		material.emission_energy_multiplier = energy
		record["written"] = energy

func _fire_slam_fx() -> void:
	_slam_fx_fired = true
	_slam_fx_count += 1
	var pools := get_tree().get_nodes_in_group("vfx_pool_3d")
	if pools.is_empty() or not pools[0] is VfxPool3D:
		return
	var pool := pools[0] as VfxPool3D
	pool.acquire(VfxPool3D.FX01_FAT_ZOMBIE_SLAM, global_position, Color.WHITE, 1.0, {"floor_y": global_position.y})

func get_attack_visual_frame() -> float:
	return _attack_visual_frame

func get_presentation_snapshot() -> Dictionary:
	return {
		"state": _state, "clip": _clip, "sample_time": _sample,
		"source_fps": SOURCE_FPS, "source_attack_frame": _attack_visual_frame,
		"asset_id": "ENM-NORMAL-FAT-ZOMBIE21", "asset_version": "v007",
		"gait_phase": _gait_phase, "gait_stride_m": _gait_stride,
		"travel_distance_m": _travel_distance, "frame_distance_m": _frame_distance,
		"bones": 41, "vertices": 597, "vertex_groups": 29,
		"procedural_pose": _state in MOVEMENT_STATES, "contact_lock": _contact_anchors.keys(),
		"contact_segments": _contact_anchors.duplicate(true), "collision_owned": false, "damage_owner": "Enemy3D",
		"slam_fx_asset_id": "VFX-FAT-ZOMBIE-SLAM-3D",
		"slam_fx_trigger_frame": ATTACK_CONTACT_FRAME, "slam_fx_count": _slam_fx_count,
		"hit_light_active": false, "flash_time": _flash_time,
		"warning_progress": _warning_progress, "supplemental_event": _event,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"unavailable_clips": ["hurt", "dead", "awaken", "alert", "turn_l", "turn_r", "hit_light"]
	}
