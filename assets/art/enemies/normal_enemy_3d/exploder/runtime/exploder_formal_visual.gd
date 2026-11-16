extends Node3D
## 仅手动采样 move / explode；位移、爆炸、死亡回收均由 Enemy3D 拥有。

const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")
const DEATH_DURATION := 0.34
const VISUAL_HEIGHT := 1.15
const ANIMATION_FPS := 60
const MOVE_DURATION := 0.5
const EXPLODE_DURATION := 0.9
const FLASH_DURATION := 0.12
const MOTION_STATES := ["idle", "patrol", "alert", "chase", "search", "return"]
## 仅为步态标定速度：现行 exploder 基线 3.1 × 全局移速倍率 0.595。
## 不随受光后的 base_speed 缩小分母，否则实际减速时动画仍会全速播放。
@export var move_reference_speed := 1.8445

var _player: AnimationPlayer
var _visual: Node3D
var _visual_transform := Transform3D.IDENTITY
var _state := "idle"
var _clip := "move"
var _sample := 0.0
var _phase := 0.0
var _locomotion_speed := 0.0
var _base_speed := 0.0
var _flash_time := 0.0
var _active_explosion_committed := false
var _materials: Array[StandardMaterial3D] = []
var _flash_baseline: Array = []


func _ready() -> void:
	_visual = get_node("VisualGLB") as Node3D
	_visual_transform = _visual.transform
	_player = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(_player != null, "炸弹果缺少 AnimationPlayer")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.root_motion_track = NodePath("")
	_player.stop()
	# 独立化动画后只允许视觉变换/形变轨道，不执行方法、音频或其它玩法事件。
	var library := _player.get_animation_library("").duplicate() as AnimationLibrary
	_player.remove_animation_library("")
	_player.add_animation_library("", library)
	for clip_name in ["move", "explode"]:
		assert(_player.has_animation(clip_name), "炸弹果缺少动作：%s" % clip_name)
		var animation := _player.get_animation(clip_name).duplicate() as Animation
		var expected_duration := MOVE_DURATION if clip_name == "move" else EXPLODE_DURATION
		assert(
			absf(animation.length - expected_duration) <= 0.001,
			"炸弹果动作 %s 导入时长 %.6f，契约 %.3f（容差 0.001）" % [
				clip_name, animation.length, expected_duration,
			]
		)
		for index in range(animation.get_track_count() - 1, -1, -1):
			if animation.track_get_type(index) not in [
				Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
				Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE,
			]:
				animation.remove_track(index)
		animation.loop_mode = Animation.LOOP_LINEAR if clip_name == "move" else Animation.LOOP_NONE
		animation.step = 1.0 / float(ANIMATION_FPS)
		library.remove_animation(clip_name)
		library.add_animation(clip_name, animation)
	cache_materials()
	_sample_pose()


func cache_materials() -> void:
	if not _materials.is_empty():
		return
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index) as StandardMaterial3D
			assert(source != null, "炸弹果导入材质缺失")
			assert(source.albedo_texture != null, "炸弹果基础色贴图缺失，禁止白模接入")
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(index, material)
			_materials.append(material)
			Keeper.pin(material)
	_flash_baseline = HitFlash.prepare(_materials)


func _process(delta: float) -> void:
	if _state in MOTION_STATES and _locomotion_speed > 0.0:
		_phase = fposmod(_phase + delta * _playback_rate() / MOVE_DURATION, 1.0)
		_clip = "move"
		_sample = _phase * MOVE_DURATION
		_sample_pose()
	_flash_time = maxf(0.0, _flash_time - delta)
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)


## 状态通知先于下一次逐帧同步；主动自爆在死亡通知当帧收起视觉。
func on_state_changed(state: String, active_explosion_committed := false) -> void:
	_state = state
	_active_explosion_committed = active_explosion_committed
	if state == "dead":
		_locomotion_speed = 0.0
		_flash_time = 0.0
		HitFlash.restore(_flash_baseline)
		visible = not _active_explosion_committed


func sync_state(
	state: String, state_time: float, speed: float,
	telegraph_duration: float, _recovery_duration: float, base_speed := 0.0
) -> void:
	_state = state
	_locomotion_speed = maxf(0.0, speed)
	_base_speed = maxf(0.0, base_speed)
	match state:
		"idle", "patrol", "alert", "chase", "search", "return":
			_clip = "move"
			_sample = _phase * MOVE_DURATION
		"telegraph":
			_clip = "explode"
			_sample = EXPLODE_DURATION * clampf(state_time / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		"attack", "recovery":
			_clip = "explode"
			_sample = EXPLODE_DURATION
		"dead":
			# 普通击杀保留最后姿态与既有 0.34 秒回收窗口，不伪造死亡动作。
			_locomotion_speed = 0.0
			visible = not _active_explosion_committed
		"stagger", "death_warning":
			_locomotion_speed = 0.0
		"dormant":
			_locomotion_speed = 0.0
			_clip = "move"
			_sample = 0.0
		_:
			_locomotion_speed = 0.0
			_clip = "move"
			_sample = 0.0
	_sample_pose()


func _playback_rate() -> float:
	return _locomotion_speed / maxf(move_reference_speed, 0.001)


func _sample_pose() -> void:
	if _player == null:
		return
	_player.play(_clip)
	_player.seek(_sample, true)
	# 不允许导入根动画带走包装内的模型；骨骼根静止仍须由 GLB 源验收。
	_visual.transform = _visual_transform


func flash_hit(_play_hit_pose := true) -> void:
	if _state == "dead":
		return
	# 源只有两段，受击仅闪白，不借 explode 冒充 hurt。
	_flash_time = FLASH_DURATION


func get_presentation_snapshot() -> Dictionary:
	var bone_count := 0
	for node in find_children("*", "Skeleton3D", true, false):
		bone_count += (node as Skeleton3D).get_bone_count()
	return {
		"state": _state, "clip": _clip, "sample_time": _sample,
		"visual_height": VISUAL_HEIGHT, "death_duration": DEATH_DURATION,
		"animations": Array(_player.get_animation_list()) if _player != null else [],
		"animation_fps": ANIMATION_FPS,
		"move_duration": MOVE_DURATION, "explode_duration": EXPLODE_DURATION,
		"actual_move_duration": _player.get_animation("move").length if _player != null and _player.has_animation("move") else 0.0,
		"actual_explode_duration": _player.get_animation("explode").length if _player != null and _player.has_animation("explode") else 0.0,
		"bone_count": bone_count,
		"locomotion_speed": _locomotion_speed, "base_speed": _base_speed,
		"phase": _phase, "playback_rate": _playback_rate(),
		"move_reference_speed": move_reference_speed,
		"active_explosion_committed": _active_explosion_committed,
		"visual_visible": visible, "material_count": _materials.size(),
		"hurt_pose": false, "collision_owned": false,
		"procedural_pose": false, "root_motion": false,
	}
