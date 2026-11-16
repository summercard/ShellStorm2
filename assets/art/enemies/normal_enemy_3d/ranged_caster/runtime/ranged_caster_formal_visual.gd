extends Node3D
## 警察僵尸2.5表现层：复用 ranged_caster 玩法，枪已融合在 RightHand 蒙皮网格中。
## 用 `preload` 而非裸类名，理由见 `melee_chaser_formal_visual.gd` 头注。
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
## 管线缓存挂在使用中的材质上：不留一份长命引用，这只怪一回收，
## 同变体的材质下次又要重编译（实测每只 100ms 量级）。见 keeper 头注。
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")
const DEATH_DURATION := 2.4
const VISUAL_HEIGHT := 1.857143
const CLIP_BY_STATE := {
	"dormant": "armed_idle", "idle": "armed_idle", "patrol": "walking_armed", "alert": "armed_idle",
	"chase": "running_armed", "search": "running_armed", "return": "running_armed",
	"telegraph": "shoot", "attack": "shoot", "recovery": "shoot",
	"stagger": "hurt", "dead": "dead",
}
const SOURCE := "police_zombie25_animation_v002"
const ASSET_VERSION := "v004"
const SOURCE_CLIPS := ["armed_idle", "walking_armed", "running_armed", "shoot"]
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _right_hand_bone := ""
var _head_bone := ""
var _embedded_gun_meshes: Array[String] = []
var _requested_clip := "armed_idle"
var _missing_clip := ""
var _state := "idle"
var _clip := "armed_idle"
var _sample := 0.0
var _clock := 0.0
var _hurt_time := 10.0
var _flash_time := 0.0
## 本帧实际水平速度（由 `Enemy3D` 用 `get_real_velocity()` 传入）。
var _locomotion_speed := 0.0
## 这只怪的满速，用来把实际速度换算成比例（见 `_locomotion_clip()`）。
var _base_speed := 0.0
## `_base_speed` 上一次被平滑的时刻（秒，取自 `_clock`）。见 `_smooth_base_speed()`。
var _base_speed_clock := 0.0
## 循环段归一化播放相位，跨段保留。见 `sync_state()`。
var _phase := 0.0
## 当前段长度（秒）。
var _clip_length := 1.0
## 当前段是否循环。
var _looping := false
## 进段时的标称速度，用于 `_playback_rate()`。
var _nominal_speed := 0.0
## 交叉淡化剩余时间（秒），> 0 时不 `seek()`。
var _blend_left := 0.0
## 本次受击是否允许播受击姿态。太阳伤害传 false。
var _hurt_pose_allowed := true
var _materials: Array[StandardMaterial3D] = []
## 闪白基线。见 `HitFlashMaterial3D` 头注：自发光开关是 shader 变体不是 uniform，
## 每翻一次要重建管线（实测 +80~100ms/次），闪白恰好每次受击翻两次 ⇒ 每打中一下卡一下。
var _flash_baseline: Array = []
const FLASH_DURATION := 0.12
## 受击姿态时长。旧值 0.8 s 且不判移动 ⇒ 追击中的怪边跑边播 hurt，读起来是滑步。
const HURT_POSE_DURATION := 0.28
## 超过这个水平速度只闪白、不播 hurt。见 `melee_chaser_formal_visual.gd` 同名字段。
const HURT_POSE_MAX_SPEED := 0.45
const HURT_POSE_STATES := ["idle", "alert", "patrol"]
## 走路 / 跑步分界（相对满速）。见 `_locomotion_clip()`。
const RUN_SPEED_RATIO := 0.62
## 退出跑步段的比值，与上者构成迟滞。同小僵尸。
const RUN_EXIT_RATIO := 0.50
## 归一化用的满速跟随实际速度的时间常数（秒）。与小僵尸同口径，
## 推导见 `melee_chaser_formal_visual.gd` 的 `_smooth_base_speed()`。
const BASE_SPEED_SMOOTH_SEC := 0.30
## 循环段播放速率上下限。同小僵尸 `_playback_rate()`。
const PLAYBACK_RATE_MIN := 0.25
const PLAYBACK_RATE_MAX := 2.0
## 循环移动段之间的交叉淡化时长（秒）。推导见
## `melee_chaser_formal_visual.gd` 的 `CLIP_BLEND_SEC`。
const CLIP_BLEND_SEC := 0.16
## 参与交叉淡化的段。攻击（`shoot`）有判定帧，不参与。
const BLENDABLE_CLIPS := ["armed_idle", "walking_armed", "running_armed"]

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "Security zombie AnimationPlayer missing")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# 手动相位驱动必须明确循环语义；shoot 的 48% 采样不循环。
	for clip_name in SOURCE_CLIPS:
		assert(_player.has_animation(clip_name), "警察僵尸缺少正式动画：%s" % clip_name)
		if _player.has_animation(clip_name):
			_player.get_animation(clip_name).loop_mode = Animation.LOOP_NONE if clip_name == "shoot" else Animation.LOOP_LINEAR
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	assert(_skeleton != null, "警察僵尸缺少骨架")
	_right_hand_bone = _find_bone_suffix("RightHand")
	_head_bone = _find_bone_suffix("Head")
	assert(not _right_hand_bone.is_empty() and _skeleton.find_bone(_right_hand_bone) >= 0, "警察僵尸缺少实际 RightHand 骨")
	assert(not _head_bone.is_empty() and _skeleton.find_bone(_head_bone) >= 0, "警察僵尸缺少实际 Head 骨")
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
				Keeper.pin(material)
	_flash_baseline = HitFlash.prepare(_materials)
	# 源中的枪与身体共用网格，记录真实蒙皮节点，不创建第二把枪或绑点。
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null or mesh.get_node_or_null(mesh.skeleton) != _skeleton:
			continue
		if _has_right_hand_geometry(mesh):
			_embedded_gun_meshes.append(str(get_path_to(mesh)))
	assert(not _embedded_gun_meshes.is_empty(), "警察僵尸缺少 RightHand 融合枪蒙皮节点")
	sync_state("idle", 0.0, 0.0, 0.38, 0.34)

func _has_right_hand_geometry(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null:
		return false
	var hand_binds: Array[int] = []
	for bind in range(mesh.skin.get_bind_count()):
		var bone_name := str(mesh.skin.get_bind_name(bind))
		if bone_name == _right_hand_bone or (bone_name.is_empty() and mesh.skin.get_bind_bone(bind) == _skeleton.find_bone(_right_hand_bone)):
			hand_binds.append(bind)
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in range(bones.size()):
			if bones[index] in hand_binds and weights[index] > 0.99:
				return true
	return false

func _find_bone_suffix(suffix: String) -> String:
	if _skeleton != null:
		for index in range(_skeleton.get_bone_count()):
			var bone_name := str(_skeleton.get_bone_name(index))
			if bone_name.ends_with(suffix):
				return bone_name
	return ""

## 原贴图黄色双瞳射线标定→正式导入mixamorig_Head静止骨空间；不复用旧脸配方。
func get_eye_socket_spec() -> Dictionary:
	return {
		"bone_name": _head_bone,
		"bone_offsets": [Vector3(0.192476571, 0.085421562, 0.064594924), Vector3(0.156983733, 0.086167336, -0.135981619)],
		"radius": 0.02152794,
		"calibration": "police_zombie25_texture_pupil_raycast_v004",
	}

func _process(delta: float) -> void:
	_clock += delta
	_hurt_time += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	# 循环段相位按「实际速度 ÷ 该段标称速度」推进。同小僵尸，见其 `_process()`。
	# 淡化期强制 1×，让相位与引擎自播位置保持一致。
	if _blend_left > 0.0:
		_blend_left = maxf(0.0, _blend_left - delta)
		# 淡化期由引擎推进，同小僵尸。
		if _player != null:
			_player.advance(delta)
		if _clip_length > 0.0:
			_phase = fposmod(_player.current_animation_position / _clip_length, 1.0)
	elif _looping and _clip_length > 0.0:
		var rate := _playback_rate()
		_phase = fmod(_phase + delta * rate / _clip_length, 1.0)
	# 只推能量，不碰 `emission_enabled`。
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

func sync_state(
	state: String, state_time: float, speed: float,
	telegraph_duration: float, recovery_duration: float, base_speed := 0.0
) -> void:
	_state = state
	_locomotion_speed = absf(speed)
	_smooth_base_speed(base_speed)
	var previous_clip := _clip
	_requested_clip = _locomotion_clip(str(CLIP_BY_STATE.get(state, "armed_idle")), previous_clip)
	# 受击仍闪白；只有源中真实存在的 hurt 才能插姿态。
	if (
		_hurt_pose_allowed
		and _hurt_time < HURT_POSE_DURATION
		and _locomotion_speed <= HURT_POSE_MAX_SPEED
		and state in HURT_POSE_STATES
	):
		_requested_clip = "hurt"
	_missing_clip = ""
	_clip = _requested_clip
	if _player == null:
		return
	if not _player.has_animation(_clip):
		_missing_clip = _clip
		_clip = "armed_idle"
	# 最终取动画前也检查兜底段；损坏资源不得空取动画。
	if not _player.has_animation(_clip):
		_looping = false
		_blend_left = 0.0
		return
	var anim := _player.get_animation(_clip)
	var length := maxf(anim.length, 0.001)
	_looping = anim.loop_mode != Animation.LOOP_NONE
	if _clip != previous_clip:
		_nominal_speed = maxf(_locomotion_speed, 0.001)
	# 归一化相位跨段保留，理由与推导见 `melee_chaser_formal_visual.gd` 的 `sync_state()`。
	var sample := 0.0
	if _looping:
		sample = _phase * length
		if state == "dormant":
			sample = 0.0
			_phase = 0.0
	else:
		match state:
			"telegraph": sample = length * 0.48 * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			"attack": sample = length * 0.48
			"recovery": sample = length * lerpf(0.48, 1.0, clampf(state_time / maxf(recovery_duration, 0.001), 0.0, 1.0))
			"stagger": sample = length * clampf(state_time / 0.16, 0.0, 1.0)
			"dead": sample = minf(state_time, length)
			_: sample = 0.0
		_phase = clampf(sample / length, 0.0, 1.0)
	if _clip == "hurt" and state in HURT_POSE_STATES:
		_looping = false
		sample = minf(_hurt_time, length)
		_phase = clampf(sample / length, 0.0, 1.0)
	# 缺少 hurt/dead 时只钉住真实 armed_idle 的第 0 帧，不伪造受击或倒地。
	if not _missing_clip.is_empty():
		_looping = false
		sample = 0.0
		_phase = 0.0
		_blend_left = 0.0
		_player.stop()
	_sample = sample
	_clip_length = length
	# 交叉淡化，同小僵尸：`play(name, blend)` 把当前姿势淡入新段，
	# 实测把换段当帧的骨骼跳变从 35~60° 压到 0.0°。
	var blend := _missing_clip.is_empty() and _clip != previous_clip and previous_clip in BLENDABLE_CLIPS and _clip in BLENDABLE_CLIPS
	if blend:
		_blend_left = CLIP_BLEND_SEC
		_phase = 0.0
		_sample = 0.0
		_player.play(_clip, CLIP_BLEND_SEC)
	elif _clip != previous_clip or _blend_left <= 0.0:
		_blend_left = 0.0
		# play + seek 必须成对：MANUAL 回调模式下单独 seek 不驱动骨架。同小僵尸。
		_player.play(_clip)
		_player.seek(_sample, true)

## 按实际速度在走路/跑步之间改判，理由与 `melee_chaser_formal_visual.gd` 逐字相同：
## 复刻怪的突进 / 逃跑 / 游荡都靠外推位移，`ai_state` 可能仍是 patrol 甚至 idle，
## 只按状态名给段就会"高速移动却播走路 / 站立"。
## 迟滞也同口径：已是跑步段时要掉到 `RUN_EXIT_RATIO` 以下才退回走路。
func _locomotion_clip(clip: String, previous: String) -> String:
	var ratio := _speed_ratio()
	if ratio < 0.0:
		return clip
	var running_now := previous.contains("running")
	if clip == "walking_armed":
		if running_now:
			return "walking_armed" if ratio < RUN_EXIT_RATIO else "running_armed"
		return "running_armed" if ratio >= RUN_SPEED_RATIO else clip
	if clip == "armed_idle" and _state in ["idle", "patrol"]:
		if running_now:
			return "running_armed" if ratio >= RUN_EXIT_RATIO else "walking_armed"
		if ratio >= RUN_SPEED_RATIO:
			return "running_armed"
		if ratio >= RUN_SPEED_RATIO * 0.5:
			return "walking_armed"
	return clip


## 循环段播放速率 = 实际速度 ÷ 进段时的标称速度。同小僵尸，见其 `_playback_rate()`。
func _playback_rate() -> float:
	if _nominal_speed <= 0.01:
		return 1.0
	return clampf(_locomotion_speed / _nominal_speed, PLAYBACK_RATE_MIN, PLAYBACK_RATE_MAX)


func _speed_ratio() -> float:
	if _base_speed > 0.01:
		return _locomotion_speed / _base_speed
	if _locomotion_speed <= 0.01:
		return 0.0
	return _locomotion_speed / 1.4


## 满速跟随实际速度一起衰减 —— 与 `melee_chaser_formal_visual.gd` 同口径。
##
## 手电照到会让 `get_effective_move_speed()` **阶跃**乘 0.40，而真实速度是指数衰减；
## 分母不跟着平滑的话，比值会在光扫到的 0.13~0.5 s 内冲过 0.62 阈值再落回，
## 段名翻两次、每次硬拽 34~83° 的骨骼姿势 —— 业主报的"走路抽一下"。
## 稳态读数与改前完全一致（被照着的巡逻仍比值 0.32，被照着的追击仍 1.0）。
func _smooth_base_speed(base_speed: float) -> void:
	if base_speed <= 0.0:
		return
	if _base_speed <= 0.0:
		_base_speed = base_speed
		_base_speed_clock = _clock
		return
	var step := clampf(_clock - _base_speed_clock, 0.0, 0.25)
	_base_speed_clock = _clock
	if step <= 0.0:
		return
	var weight := 1.0 - exp(-step / BASE_SPEED_SMOOTH_SEC)
	_base_speed = lerpf(_base_speed, base_speed, weight)


func flash_hit(play_hit_pose := true) -> void:
	if _state == "dead":
		return
	_flash_time = FLASH_DURATION
	if play_hit_pose:
		_hurt_pose_allowed = true
		_hurt_time = 0.0
	else:
		_hurt_pose_allowed = false

func get_presentation_snapshot() -> Dictionary:
	var clips := {}
	if _player != null:
		for clip_name in _player.get_animation_list():
			var animation := _player.get_animation(clip_name)
			clips[str(clip_name)] = {"length": animation.length, "loop_mode": animation.loop_mode}
	var textures: Array = []
	for material in _materials:
		if material.albedo_texture != null:
			textures.append({"path": material.albedo_texture.resource_path,
				"size": material.albedo_texture.get_size()})
	var model := get_node_or_null("VisualGLB")
	return {"state": _state, "clip": _clip, "sample_time": _sample,
		"visual_height": VISUAL_HEIGHT, "death_duration": DEATH_DURATION,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"source": SOURCE, "asset_version": ASSET_VERSION,
		"model_scene": model.scene_file_path if model != null else "",
		"clip_specs": clips, "albedo_textures": textures,
		"collision_owned": false, "procedural_pose": false,
		"shotgun_visual": not _embedded_gun_meshes.is_empty(),
		"shotgun_embedded": not _embedded_gun_meshes.is_empty(),
		"shotgun_mesh_paths": _embedded_gun_meshes.duplicate(),
		"shotgun_bone": _right_hand_bone, "head_bone": _head_bone,
		"bone_count": _skeleton.get_bone_count() if _skeleton != null else 0,
		"requested_clip": _requested_clip, "missing_clip": _missing_clip,
		"missing_clip_fallback": "armed_idle@0" if not _missing_clip.is_empty() else "",
		"missing_clips": ["hurt", "dead"].filter(func(clip_name): return _player == null or not _player.has_animation(clip_name)),
		"looping": _looping, "blend_left": _blend_left,
		"flash_time": _flash_time,
		"hurt_pose_allowed": _hurt_pose_allowed,
		"hurt_pose": _clip == "hurt",
		"hurt_time": _hurt_time,
		"locomotion_speed": _locomotion_speed,
		"base_speed": _base_speed,
		"speed_ratio": _speed_ratio(),
		"phase": _phase,
		"playback_rate": _playback_rate()}
