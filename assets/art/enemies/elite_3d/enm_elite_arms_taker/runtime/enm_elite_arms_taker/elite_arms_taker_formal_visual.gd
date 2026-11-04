extends Node3D
## Pure presentation: one action context, one manual sample, no gameplay writes.
const HitFlash := preload("res://src/enemy3d/HitFlashMaterial3D.gd")
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")
const DEATH_DURATION := 4.6
const SIGNAL_MATERIAL := preload("res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/arms_taker_signal.gdshader")
const VISUAL_HEIGHT := 3.5
const LOOP_CLIPS := ["idle", "walk", "run"]
const RUN_ENTER_RATIO := 0.62
const RUN_EXIT_RATIO := 0.50
const STOP_SPEED := 0.08
const BLEND_DURATION := 0.12
const FLASH_DURATION := 0.12
const FOOT_BY_BIND := {"L_Foot": "L_Foot", "L_ToeBase": "L_Foot", "R_Foot": "R_Foot", "R_ToeBase": "R_Foot"}
# Backward travel of the supporting boot per unit of normalized phase, in
# prefab meters. Measured on the in-place v002 clips at 12 equally spaced phases.
const STRIDE_PROFILES := {
	"walk": [2.895, 3.306, 2.895, 3.355, 3.781, 3.603, 3.105, 2.827, 2.807, 3.741, 4.132, 3.437],
	"run": [2.852, 1.878, 1.231, 1.224, 1.743, 2.432, 2.470, 1.994, 1.797, 1.729, 2.614, 2.852],
}

class FootSamples:
	var weighted_points: PackedVector4Array
	var bind_ids: PackedInt32Array
	var vertex_ends: PackedInt32Array

# Fit to the solid center of each segment in the dominant joint's bind space.
# Recess the faces from the mesh silhouette, especially around cuffs and boot tips.
const HIT_VOLUMES := [
	{"bone": "Head", "center": Vector3(-0.007, 0.101, -0.027), "size": Vector3(0.215, 0.177, 0.182)},
	{"bone": "Spine02", "center": Vector3(0.003, 0.052, 0.002), "size": Vector3(0.156, 0.135, 0.112)},
	{"bone": "Spine01", "center": Vector3(0.005, 0.035, 0.004), "size": Vector3(0.143, 0.100, 0.111)},
	{"bone": "Waist", "center": Vector3(0.009, 0.018, 0.015), "size": Vector3(0.111, 0.108, 0.119)},
	{"bone": "L_Upperarm", "center": Vector3(0.004, 0.071, -0.012), "size": Vector3(0.063, 0.118, 0.051)},
	{"bone": "R_Upperarm", "center": Vector3(0.001, 0.071, -0.019), "size": Vector3(0.061, 0.120, 0.055)},
	{"bone": "L_Forearm", "center": Vector3(-0.002, 0.073, -0.010), "size": Vector3(0.054, 0.125, 0.060)},
	{"bone": "R_Forearm", "center": Vector3(0.001, 0.073, -0.018), "size": Vector3(0.054, 0.122, 0.060)},
	{"bone": "L_Hand", "center": Vector3(-0.013, 0.057, -0.005), "size": Vector3(0.044, 0.111, 0.058)},
	{"bone": "R_Hand", "center": Vector3(0.018, 0.064, -0.011), "size": Vector3(0.045, 0.123, 0.057)},
	{"bone": "L_Thigh", "center": Vector3(-0.007, 0.101, -0.015), "size": Vector3(0.086, 0.222, 0.093)},
	{"bone": "R_Thigh", "center": Vector3(0.011, 0.104, -0.022), "size": Vector3(0.083, 0.225, 0.094)},
	{"bone": "L_Calf", "center": Vector3(0.011, 0.146, -0.015), "size": Vector3(0.061, 0.252, 0.079)},
	{"bone": "R_Calf", "center": Vector3(0.004, 0.147, -0.015), "size": Vector3(0.057, 0.260, 0.082)},
	{"bone": "L_Foot", "center": Vector3(0.004, 0.046, 0.006), "size": Vector3(0.058, 0.142, 0.049)},
	{"bone": "R_Foot", "center": Vector3(0.007, 0.044, 0.005), "size": Vector3(0.058, 0.143, 0.049)},
]

var _player: AnimationPlayer
var _skeleton: Skeleton3D
@onready var _model_root: Node3D = $VisualGLB
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
var _signal_surfaces: Array[Dictionary] = []
var _head_index := -1
var _signal_active := false
var _screen_charge := 0.0
var _glitch := 0.0
var _foot_samples: Dictionary[String, FootSamples] = {}
var _sole_bind_bones: PackedInt32Array
var _sole_bind_poses: Array[Transform3D] = []
var _used_sole_binds: Dictionary[int, bool] = {}

func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null:
		push_error("elite_arms_taker: missing AnimationPlayer/Skeleton3D")
		return
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_make_in_place_library()
	_head_index = _skeleton.find_bone("Head")
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin != null and _foot_samples.is_empty():
			_cache_foot_samples(mesh)
		for index in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source != null:
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(index, material)
				_materials.append(material)
				Keeper.pin(material)
				var signal_material := ShaderMaterial.new()
				signal_material.shader = SIGNAL_MATERIAL
				signal_material.set_shader_parameter("base_texture", material.albedo_texture)
				signal_material.set_shader_parameter("normal_texture", material.normal_texture)
				signal_material.set_shader_parameter("surface_texture", material.roughness_texture)
				_signal_surfaces.append({"mesh": mesh, "surface": index, "base": material, "signal": signal_material})
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
	if STRIDE_PROFILES.has(_clip):
		_phase = fposmod(_phase + delta * _gait_phase_rate(), 1.0)
	HitFlash.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)


func _gait_phase_rate() -> float:
	var profile: Array = STRIDE_PROFILES[_clip]
	var index := _phase * profile.size()
	var start := mini(int(index), profile.size() - 1)
	var stride := lerpf(profile[start], profile[(start + 1) % profile.size()], index - start)
	return _speed / (stride * _actor_scale)


func sync_context(context: Dictionary, blend := true) -> void:
	if _player == null:
		return
	_state = str(context.get("state", "idle"))
	_speed = maxf(0.0, float(context.get("speed", 0.0)))
	_base_speed = maxf(0.01, float(context.get("base_speed", 1.0)))
	_actor_scale = maxf(0.01, float(context.get("actor_scale", 1.0)))
	_model_root.position.y = float(context.get("floor_offset", 0.0)) / global_basis.y.length()
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
	if bool(context.get("grounded", false)):
		var soles := _sample_foot_bottoms()
		if soles.size() == 2:
			var lowest := minf(soles["L_Foot"], soles["R_Foot"])
			var target_height := float(context["floor_height"]) - float(context["foot_inset"])
			_model_root.position.y += (target_height - lowest) / global_basis.y.length()
	_update_signal_material(float(context.get("glitch", 0.0)), float(context.get("screen_charge", 0.0)))

func _update_signal_material(glitch: float, charge: float) -> void:
	_glitch = glitch
	_screen_charge = charge
	var enabled := glitch > 0.001 or charge > 0.001
	if not enabled and not _signal_active:
		return
	for entry in _signal_surfaces:
		var mesh: MeshInstance3D = entry["mesh"]
		var material: ShaderMaterial = entry["signal"]
		if enabled:
			material.set_shader_parameter("glitch", glitch)
			material.set_shader_parameter("charge", charge)
		if enabled != _signal_active:
			mesh.set_surface_override_material(entry["surface"], material if enabled else entry["base"])
	_signal_active = enabled

func get_screen_emitter_position() -> Vector3:
	if _head_index < 0:
		return global_position + Vector3.UP * (VISUAL_HEIGHT * 0.8 * global_basis.y.length())
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_index)
	return head * Vector3(0.018, 0.203, -0.022)

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
	var playback_speed := 1.0
	if STRIDE_PROFILES.has(_clip):
		playback_speed = _gait_phase_rate() * _player.get_animation(_clip).length
	return {"asset_id":"ENM-ELITE-ARMS-TAKER-3D", "version":get_meta("asset_version", ""), "content_id":"elite_arms_taker",
		"state":_state, "clip":_clip, "clip_time":_sample, "phase":_phase,
		"looping":_clip in LOOP_CLIPS, "playback_speed":playback_speed,
		"clip_count":_player.get_animation_list().size() if _player != null else 0,
		"bone_count":_skeleton.get_bone_count() if _skeleton != null else 0,
		"procedural_pose":false, "death_duration":DEATH_DURATION, "stride_lengths":_stride_lengths.duplicate(),
		"in_place":_stride_lengths.size() == 2, "sampler":"context_manual_seek", "source_forward":"+Z", "godot_forward":"-Z",
		"screen_charge":_screen_charge, "glitch":_glitch, "signal_material_active":_signal_active}


func get_hit_volume_spec() -> Array:
	return HIT_VOLUMES


func hit_volume_transforms() -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if _skeleton == null:
		return transforms
	var foot_bottoms := _sample_foot_bottoms()
	for spec in HIT_VOLUMES:
		var index := _skeleton.find_bone(spec["bone"])
		if index < 0:
			return []
		var bone_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(index)
		var hit_transform := bone_transform.translated_local(spec["center"])
		if foot_bottoms.has(spec["bone"]):
			var basis := hit_transform.basis
			var half_height := Vector3(absf(basis.x.y), absf(basis.y.y), absf(basis.z.y)).dot(spec["size"]) * 0.5
			hit_transform.origin.y = foot_bottoms[spec["bone"]] + half_height
		transforms.append(hit_transform)
	return transforms


## Cache the actual boot vertices and their skin weights. The toe joint can
## flex independently of the ankle, so an ankle offset alone cannot align soles.
func _cache_foot_samples(model: MeshInstance3D) -> void:
	var skin := model.skin
	var foot_names: Array[String] = []
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		_sole_bind_bones.append(_skeleton.find_bone(bone_name))
		_sole_bind_poses.append(skin.get_bind_pose(bind))
		foot_names.append(FOOT_BY_BIND.get(bone_name, ""))
	_foot_samples["L_Foot"] = FootSamples.new()
	_foot_samples["R_Foot"] = FootSamples.new()
	for surface in model.mesh.get_surface_count():
		var arrays := model.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or weights.is_empty():
			continue
		@warning_ignore("integer_division")
		var influence_count := weights.size() / vertices.size()
		for vertex in vertices.size():
			var start := vertex * influence_count
			var strongest := start
			for influence in range(start + 1, start + influence_count):
				if weights[influence] > weights[strongest]:
					strongest = influence
			var sample := _foot_samples.get(foot_names[binds[strongest]]) as FootSamples
			if sample == null:
				continue
			var point := vertices[vertex]
			for influence in range(start, start + influence_count):
				var weight := weights[influence]
				if weight <= 0.0:
					continue
				var bind := binds[influence]
				_used_sole_binds[bind] = true
				sample.bind_ids.append(bind)
				sample.weighted_points.append(Vector4(point.x, point.y, point.z, 1.0) * weight)
			sample.vertex_ends.append(sample.bind_ids.size())


func _sample_foot_bottoms() -> Dictionary[String, float]:
	var bottoms: Dictionary[String, float] = {}
	var skin_rows := PackedVector4Array()
	skin_rows.resize(_sole_bind_poses.size())
	var world := _skeleton.global_transform
	for bind in _used_sole_binds:
		var transform := world * _skeleton.get_bone_global_pose(_sole_bind_bones[bind]) * _sole_bind_poses[bind]
		skin_rows[bind] = Vector4(transform.basis.x.y, transform.basis.y.y, transform.basis.z.y, transform.origin.y)
	for foot in _foot_samples:
		var sample := _foot_samples[foot]
		var start := 0
		var lowest := INF
		for end in sample.vertex_ends:
			var height := 0.0
			for influence in range(start, end):
				height += skin_rows[sample.bind_ids[influence]].dot(sample.weighted_points[influence])
			lowest = minf(lowest, height)
			start = end
		if is_finite(lowest):
			bottoms[foot] = lowest
	return bottoms
