extends Node3D
## 表现单向消费 Enemy3D 状态，位移和命中始终归玩法层。
## 用 `preload` 而非裸类名，理由见 `melee_chaser_formal_visual.gd` 头注。
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
## 管线缓存挂在使用中的材质上：不留一份长命引用，这只怪一回收，
## 同变体的材质下次又要重编译（实测每只 100ms 量级）。见 keeper 头注。
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")
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
## 满速，用来把当前速度换算成比例（走还是跑）。
var _base_speed := 0.0
var _light_time := 1.0
var _flash_time := 0.0
var _event := ""
var _event_time := 0.0
## 事件开始时的 `state_time`。事件进度取「_process 计时」与「state_time 增量」的最大值。
##
## 为什么要两条时钟：`_event_time` 只在 `_process` 里涨，而 `sync_state` 是
## `Enemy3D._process` 调进来的 —— 正常运行时两条同步。但**冻结帧 / 探针 / 暂停**时
## `_process` 可能不跑，而调用方仍在按状态推进 `state_time`，
## 于是事件永远停在第一帧（实测：探针里胖子永远卡在 `move_start`，看起来"不会跑步"）。
var _event_anchor := 0.0
## 本次受击是否允许播受击姿态。太阳伤害传 false —— 它每秒结算一次，
## 反复播 hit_light 会让"被晒"读成"被连续射击"。
var _hurt_pose_allowed := true
var _heading := 0.0
var _blend_time := 1.0
var _previous_pose: Array[Transform3D] = []
var _materials: Array[StandardMaterial3D] = []
var _meshes: Array[MeshInstance3D] = []
## 闪白基线。见 `HitFlashMaterial3D` 头注：自发光开关是 shader 变体不是 uniform，
## 每翻一次要重建管线（实测 +80~100ms/次），闪白恰好每次受击翻两次 ⇒ 每打中一下卡一下。
var _flash_baseline: Array = []
const FLASH_DURATION := 0.12

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
				Keeper.pin(material)
	_flash_baseline = HitFlash.prepare(_materials)
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
	# 只推能量，不碰 `emission_enabled`。
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

func sync_state(
	state: String, state_time: float, speed: float,
	telegraph_duration: float, recovery_duration: float, base_speed := 0.0
) -> void:
	if _player == null:
		return
	if base_speed > 0.0:
		_base_speed = base_speed
	if state != _state:
		_previous_pose.clear()
		for bone in _skeleton.get_bone_count():
			_previous_pose.append(_skeleton.get_bone_pose(bone))
		_blend_time = 0.0
		_event = ""
		_event_time = 0.0
		_event_anchor = state_time
		_locomotion_phase = 0.0
		if _state == "dormant" and state == "idle":
			_event = "awaken"
			_event_anchor = state_time
		elif state == "patrol":
			_event = "move_start"
			_event_anchor = state_time
		elif _state == "patrol" and state == "idle":
			_event = "move_stop"
			_event_anchor = state_time
	var yaw_change := wrapf(global_rotation.y - _heading, -PI, PI)
	if state == "idle" and _event.is_empty() and absf(yaw_change) > 0.25:
		_event = "turn_l" if yaw_change > 0.0 else "turn_r"
		_event_time = 0.0
		_event_anchor = state_time
		_heading = global_rotation.y
	elif state != "idle":
		_heading = global_rotation.y
	_state = state
	_speed = maxf(0.0, speed)
	# 按实际速度改判走路/跑步，理由见 `melee_chaser_formal_visual.gd` 的 `_locomotion_clip()`：
	# 复刻怪的突进 / 逃跑靠外推位移，`ai_state` 可能仍是 patrol / idle，
	# 只按状态名给段就会"高速移动却播走路"。
	_clip = _locomotion_clip(str(CLIP_BY_STATE.get(state, "idle")))
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
		# 取两条时钟的较大者：`_process` 停摆时（冻结 / 探针）仍能被 `state_time` 推完。
		var event_progress := maxf(_event_time, maxf(0.0, state_time - _event_anchor))
		if event_progress < _player.get_animation(_event).length:
			_clip = _event
			_sample = event_progress
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
	if (
		_hurt_pose_allowed
		and _light_time < 0.3
		and _speed <= HURT_POSE_MAX_SPEED
		and state in ["idle", "alert", "patrol"]
	):
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

## 按实际速度在 walking / running 之间改判。与另两只同口径（见小僵尸同名函数）。
func _locomotion_clip(clip: String) -> String:
	var ratio := _speed_ratio()
	if ratio < 0.0:
		return clip
	if clip == "walking":
		return "running" if ratio >= RUN_SPEED_RATIO else clip
	if clip == "idle" and _state in ["idle", "patrol"]:
		if ratio >= RUN_SPEED_RATIO:
			return "running"
		if ratio >= RUN_SPEED_RATIO * 0.5:
			return "walking"
	return clip


func _speed_ratio() -> float:
	if _base_speed > 0.01:
		return _speed / _base_speed
	if _speed <= 0.01:
		return 0.0
	return _speed / 1.4


## 闪白一定给；受击姿态（上半身 hit_light 混合）由 `play_hit_pose` 决定。
##
## 胖子是"只混上半身"的，理论上腿还在跑主段，但它仍然**不能边跑边抽**：
## 半个身子被打一下、下半身照旧跑步，读起来是"卡了两帧"，比整段 hurt 更像故障。
## 所以它也走和小僵尸同一套闸门：允许 + 站定才演。
const HURT_POSE_MAX_SPEED := 0.45
## 走路 / 跑步分界（相对满速）。与其他两只同口径。
const RUN_SPEED_RATIO := 0.62
func flash_hit(play_hit_pose := true) -> void:
	if _state == "dead":
		return
	_flash_time = FLASH_DURATION
	_hurt_pose_allowed = play_hit_pose
	if play_hit_pose:
		_light_time = 0.0

func get_presentation_snapshot() -> Dictionary:
	return {"state":_state, "clip":_clip, "sample_time":_sample,
		"visual_height":VISUAL_HEIGHT, "death_duration":DEATH_DURATION,
		"animations":Array(_player.get_animation_list()) if _player != null else [],
		"source":"blender_model_v003_animation_v008", "collision_owned":false,
		"procedural_pose":false,
		# 判据必须带上 `_hurt_pose_allowed` 与速度闸门：`_light_time` 是 _process 推的计时器，
		# 太阳伤害把它置 0 又被闸门拦下时，若只看计时器会永远报"正在受击" ——
		# 那是把"没播"报成"播了"，比遗漏更难查。
		"hit_light_active": _hurt_pose_allowed and _light_time < 0.3 and _speed <= HURT_POSE_MAX_SPEED,
		"hurt_pose_allowed": _hurt_pose_allowed,
		"locomotion_speed": _speed,
		"supplemental_event":_event}
