extends Node3D
## Pure presentation: one action context, one manual sample, no gameplay writes.
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")
const DEATH_DURATION := 4.6
const VISUAL_HEIGHT := 3.5
const LOOP_CLIPS := ["idle", "walk", "run"]
const RUN_ENTER_RATIO := 0.62
const RUN_EXIT_RATIO := 0.50
const STOP_SPEED := 0.08
const BLEND_DURATION := 0.12
const FLASH_DURATION := 0.12

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _state := "idle"
var _clip := "idle"
var _sample := 0.0
var _clock := 0.0
var _phase := 0.0
var _speed := 0.0
var _base_speed := 1.0
var _actor_scale := 1.0
var _blend_elapsed := 1.0
var _previous_pose: Array[Transform3D] = []
var _stride_lengths: Dictionary = {}
var _flash_time := 0.0
var _materials: Array[StandardMaterial3D] = []
var _flash_baseline: Array = []

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null:
		push_error("elite_arms_taker: missing AnimationPlayer/Skeleton3D")
		return
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_make_in_place_library()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for index in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
				Keeper.pin(material)
	_flash_baseline = HitFlash.prepare(_materials)
	sync_context({"state":"idle", "action_id":"idle", "time":0.0}, false)

func _make_in_place_library() -> void:
	# Duplicate before editing: imported resources and other instances remain unchanged.
	for library_name in _player.get_animation_library_list():
		var library := _player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		_player.remove_animation_library(library_name)
		_player.add_animation_library(library_name, library)
	for clip in _player.get_animation_list():
		var animation := _player.get_animation(clip)
		if str(clip) in ["walk", "run"]:
			for track in animation.get_track_count():
				if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
					continue
				var path := animation.track_get_path(track)
				if path.get_subname_count() == 0 or str(path.get_subname(0)) != "Hip":
					continue
				var count := animation.track_get_key_count(track)
				if count < 2:
					continue
				var first: Vector3 = animation.track_get_key_value(track, 0)
				var last: Vector3 = animation.track_get_key_value(track, count - 1)
				var drift := last - first
				var parent := _skeleton.get_bone_parent(_skeleton.find_bone("Hip"))
				var parent_basis := _skeleton.get_bone_global_rest(parent).basis
				var model_basis := global_basis.inverse() * _skeleton.global_basis
				_stride_lengths[str(clip)] = (model_basis * parent_basis * drift).length()
				var start := animation.track_get_key_time(track, 0)
				var duration := animation.track_get_key_time(track, count - 1) - start
				for key in count:
					var value: Vector3 = animation.track_get_key_value(track, key)
					var progress := (animation.track_get_key_time(track, key) - start) / maxf(0.001, duration)
					animation.track_set_key_value(track, key, value - drift * progress)
		animation.loop_mode = Animation.LOOP_LINEAR if str(clip) in LOOP_CLIPS else Animation.LOOP_NONE

func _process(delta: float) -> void:
	_clock += delta
	_blend_elapsed += delta
	_flash_time = maxf(0.0, _flash_time - delta)
	if _clip in ["walk", "run"]:
		var stride := float(_stride_lengths.get(_clip, 1.0)) * _actor_scale
		_phase = fposmod(_phase + delta * _speed / maxf(0.01, stride), 1.0)
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)

func sync_context(context: Dictionary, blend := true) -> void:
	if _player == null:
		return
	_state = str(context.get("state", "idle"))
	_speed = maxf(0.0, float(context.get("speed", 0.0)))
	_base_speed = maxf(0.01, float(context.get("base_speed", 1.0)))
	_actor_scale = maxf(0.01, float(context.get("actor_scale", 1.0)))
	var next_clip := str(context.get("action_id", "idle"))
	if next_clip == "locomotion":
		next_clip = _locomotion_clip()
	if not _player.has_animation(next_clip):
		push_warning("elite_arms_taker: missing clip '%s', using idle" % next_clip)
		next_clip = "idle"
	if next_clip != _clip:
		_previous_pose.clear()
		if blend and _state != "dead":
			for bone in _skeleton.get_bone_count():
				_previous_pose.append(_skeleton.get_bone_pose(bone))
		_blend_elapsed = 0.0
	_clip = next_clip
	var length := _player.get_animation(_clip).length
	if _clip in ["walk", "run"]:
		_sample = _phase * length
	elif _clip == "idle":
		_sample = fposmod(_clock, maxf(0.001, length))
	else:
		_sample = clampf(float(context.get("time", 0.0)), 0.0, length)
	# Never mix advance() and seek(). The action controller owns non-loop time.
	_player.play(_clip)
	_player.seek(_sample, true)
	_player.speed_scale = 1.0
	if blend and _blend_elapsed < BLEND_DURATION and not _previous_pose.is_empty():
		var weight := smoothstep(0.0, BLEND_DURATION, _blend_elapsed)
		for bone in mini(_previous_pose.size(), _skeleton.get_bone_count()):
			var pose := _previous_pose[bone].interpolate_with(_skeleton.get_bone_pose(bone), weight)
			_skeleton.set_bone_pose_position(bone, pose.origin)
			_skeleton.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())
			_skeleton.set_bone_pose_scale(bone, pose.basis.get_scale())
	else:
		_previous_pose.clear()

func _locomotion_clip() -> String:
	if _speed <= STOP_SPEED:
		return "idle"
	var ratio := _speed / _base_speed
	if ratio >= RUN_ENTER_RATIO:
		return "run"
	if ratio <= RUN_EXIT_RATIO:
		return "walk"
	return _clip if _clip in ["walk", "run"] else "walk"

## Compatibility for asset previews; formal runtime uses sync_context exclusively.
func sync_state(state: String, state_time: float, speed: float, telegraph_duration: float, recovery_duration: float, base_speed := 0.0) -> void:
	var action := "idle"
	var time := state_time
	if state in ["patrol", "chase", "search", "return"]:
		action = "locomotion"
	elif state in ["telegraph", "attack", "recovery"]:
		action = "attack_light"
		if state == "telegraph":
			time = 40.0 / 30.0 * clampf(state_time / maxf(0.001, telegraph_duration), 0.0, 1.0)
		elif state == "attack":
			time += 40.0 / 30.0
		else:
			time = lerpf(44.0 / 30.0, 80.0 / 30.0, clampf(state_time / maxf(0.001, recovery_duration), 0.0, 1.0))
	elif state == "stagger":
		action = "hit"
	elif state == "dead":
		action = "death"
	sync_context({"state":state, "action_id":action, "time":time, "speed":speed, "base_speed":base_speed})

func flash_hit(_play_hit_pose := true) -> void:
	# Hurt poses are selected only by the authoritative stagger state.
	_flash_time = FLASH_DURATION

func get_presentation_snapshot() -> Dictionary:
	return {"asset_id":"ENM-ELITE-ARMS-TAKER-3D", "version":"v001", "content_id":"elite_arms_taker",
		"state":_state, "clip":_clip, "clip_time":_sample, "phase":_phase,
		"looping":_clip in LOOP_CLIPS, "playback_speed":1.0,
		"clip_count":_player.get_animation_list().size() if _player != null else 0,
		"bone_count":_skeleton.get_bone_count() if _skeleton != null else 0,
		"procedural_pose":false, "death_duration":DEATH_DURATION, "stride_lengths":_stride_lengths.duplicate(),
		"in_place":_stride_lengths.size() == 2, "sampler":"context_manual_seek", "source_forward":"+Z", "godot_forward":"-Z"}
