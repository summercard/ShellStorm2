extends Node3D
## 表现单向消费 Enemy3D 状态，位移和命中始终归玩法层。
const DEATH_DURATION := 2.6
const VISUAL_HEIGHT := 3.142857
const CLIP_BY_STATE := {
	"dormant":"idle", "idle":"idle", "patrol":"walking", "alert":"alert",
	"chase":"running", "search":"running", "return":"running",
	"telegraph":"attack", "attack":"attack", "recovery":"attack",
	"stagger":"hurt", "dead":"dead",
}
const UPPER_BONES := ["Waist", "Spine01", "Spine02", "Neck", "Head", "HeadTop_End"]
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _clock := 0.0
var _locomotion_phase := 0.0
var _speed := 0.0
var _light_time := 1.0
var _flash_time := 0.0
var _event := ""
var _event_time := 0.0
var _heading := 0.0
var _blend_time := 1.0
var _previous_pose: Array[Transform3D] = []
var _materials: Array[StandardMaterial3D] = []
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	assert(_player != null and _skeleton != null, "Fat zombie skeleton/player missing")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_heading = global_rotation.y
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_meshes.append(mesh)
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
	sync_state("idle", 0.0, 0.0, 1.2, 1.3)

func _process(delta: float) -> void:
	if _state == "dormant":
		return
	_clock += delta
	_light_time += delta
	_event_time += delta
	_blend_time += delta
	_locomotion_phase += delta * _speed / (0.3 if _state == "patrol" else 0.6)
	_flash_time = maxf(0.0, _flash_time - delta)
	for material in _materials:
		material.emission_enabled = _flash_time > 0.0
		material.emission = Color(1.0, 0.65, 0.45)
		material.emission_energy_multiplier = 0.6 * _flash_time / 0.12

func sync_state(state: String, state_time: float, speed: float, telegraph_duration: float, recovery_duration: float) -> void:
	if _player == null:
		return
	if state != _state:
		_previous_pose.clear()
		for bone in _skeleton.get_bone_count():
			_previous_pose.append(_skeleton.get_bone_pose(bone))
		_blend_time = 0.0
		_event = ""
		_event_time = 0.0
		_locomotion_phase = 0.0
		if _state == "dormant" and state == "idle":
			_event = "awaken"
		elif state == "patrol":
			_event = "move_start"
		elif _state == "patrol" and state == "idle":
			_event = "move_stop"
	var yaw_change := wrapf(global_rotation.y - _heading, -PI, PI)
	if state == "idle" and _event.is_empty() and absf(yaw_change) > 0.25:
		_event = "turn_l" if yaw_change > 0.0 else "turn_r"
		_event_time = 0.0
		_heading = global_rotation.y
	elif state != "idle":
		_heading = global_rotation.y
	_state = state
	_speed = maxf(0.0, speed)
	_clip = str(CLIP_BY_STATE.get(state, "idle"))
	var length := _player.get_animation(_clip).length
	_sample = fmod(_clock, length)
	if state in ["patrol", "chase", "search", "return"]:
		_sample = fmod(maxf(0.0, _locomotion_phase - (0.4 if state == "patrol" else 0.0)), length)
	match state:
		"dormant": _sample = 0.0
		"alert": _sample = minf(state_time, length)
		"telegraph": _sample = 1.2 * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		"attack": _sample = 1.2
		"recovery": _sample = lerpf(1.2, 2.5, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
		"stagger", "dead": _sample = minf(state_time, length)
	if not _event.is_empty():
		if _event_time < _player.get_animation(_event).length:
			_clip = _event
			_sample = _event_time
		else:
			_event = ""
	# 所有非死亡状态先清理形变，防止复用实例残留压扁肚子。
	if state != "dead":
		for mesh in _meshes:
			var key := mesh.find_blend_shape_by_name("BellyGroundCompression")
			if key >= 0:
				mesh.set_blend_shape_value(key, 0.0)
	_player.play(_clip)
	_player.seek(_sample, true)
	if _blend_time < 0.1 and state_time < 0.1 and state not in ["dormant", "attack", "recovery"]:
		var weight := clampf(_blend_time / 0.1, 0.0, 1.0)
		for bone in _previous_pose.size():
			var sampled := _skeleton.get_bone_pose(bone)
			var blended := _previous_pose[bone].interpolate_with(sampled, weight)
			_skeleton.set_bone_pose_position(bone, blended.origin)
			_skeleton.set_bone_pose_rotation(bone, blended.basis.get_rotation_quaternion())
	if _light_time < 0.3 and state not in ["dormant", "dead", "stagger", "telegraph", "attack", "recovery"]:
		_apply_upper_hit()

func _apply_upper_hit() -> void:
	# 局部替换：仅混合导入的上半身旋转，腿/根/形变继续使用主动作。
	var full_pose: Array[Transform3D] = []
	for bone in _skeleton.get_bone_count():
		full_pose.append(_skeleton.get_bone_pose(bone))
	var base: Dictionary = {}
	for bone_name in UPPER_BONES:
		var bone := _skeleton.find_bone(bone_name)
		if bone >= 0:
			base[bone] = _skeleton.get_bone_pose_rotation(bone)
	_player.play("hit_light")
	_player.seek(_light_time, true)
	var upper: Dictionary = {}
	for bone in base:
		upper[bone] = _skeleton.get_bone_pose_rotation(bone)
	# 恢复混合后的基础姿势，仅覆盖允许的上半身骨骼。
	_player.play(_clip)
	_player.seek(_sample, true)
	for bone in full_pose.size():
		_skeleton.set_bone_pose_position(bone, full_pose[bone].origin)
		_skeleton.set_bone_pose_rotation(bone, full_pose[bone].basis.get_rotation_quaternion())
	var weight := minf(1.0, minf(_light_time / 0.04, (0.3 - _light_time) / 0.08))
	for bone in base:
		_skeleton.set_bone_pose_rotation(bone, (base[bone] as Quaternion).slerp(upper[bone], weight))

func flash_hit() -> void:
	if _state != "dead":
		_light_time = 0.0
		_flash_time = 0.12

func get_presentation_snapshot() -> Dictionary:
	return {"state":_state, "clip":_clip, "sample_time":_sample,
		"visual_height":VISUAL_HEIGHT, "death_duration":DEATH_DURATION,
		"animations":Array(_player.get_animation_list()) if _player != null else [],
		"source":"blender_model_v003_animation_v008", "collision_owned":false,
		"procedural_pose":false, "hit_light_active":_light_time < 0.3,
		"supplemental_event":_event}
