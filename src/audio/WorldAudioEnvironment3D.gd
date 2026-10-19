class_name WorldAudioEnvironment3D
extends Node3D
## Scene-owned listener acoustics, weather, birds, support-aware footsteps and
## real prop sources. The controller never writes gameplay or save state.

const PROFILES_PATH := "res://src/assets/audio/sfx/world_environment_profiles.json"
const CONTEXT = preload("res://src/audio/WorldAudioContext3D.gd")
var actor: CharacterBody3D
var world: Node3D
var profiles: Dictionary = {}
var _context: Dictionary = {"environment": "void", "surface": "concrete", "reverb": "dry"}
var _context_elapsed := 0.0
var _device_elapsed := 0.0
var _bird_remaining := 2.5
var _rng := RandomNumberGenerator.new()
var _devices: Dictionary = {}
var _wind: Node
var _wind_level := -80.0
var _headless_wind_requested := false
var _wind_active := false
var _wind_remaining := 3.0
var _bird_voice: Node
var _footstep_count := 0
var _bird_count := 0
var _active_device_count := 0
var _listener: AudioListener3D
var _started := false


func configure(scene: Node3D, player: CharacterBody3D) -> void:
	world = scene
	actor = player
	profiles = JSON.parse_string(FileAccess.get_file_as_string(PROFILES_PATH)) as Dictionary
	_rng.randomize()
	_started = true
	_listener = AudioListener3D.new()
	_listener.name = "PlayerAudioListener"
	add_child(_listener)
	global_position = actor.global_position + Vector3.UP * 0.9
	_listener.make_current()
	if actor.has_signal("audible_footstep_requested"):
		actor.connect("audible_footstep_requested", _on_footstep)
	get_tree().node_added.connect(_on_node_added)
	_scan(world)
	_context_elapsed = float(profiles.context_interval_seconds)
	_device_elapsed = float(profiles.device_interval_seconds)


func _physics_process(delta: float) -> void:
	if not _started or not is_instance_valid(actor) or not is_instance_valid(world):
		return
	global_position = actor.global_position + Vector3.UP * 0.9
	_context_elapsed += delta
	if _context_elapsed >= float(profiles.context_interval_seconds):
		_context_elapsed = 0.0
		apply_context(CONTEXT.resolve(actor, profiles))
	_update_wind(delta)
	_bird_remaining -= delta
	if _bird_remaining <= 0.0:
		if is_outdoors():
			play_outdoor_bird()
		_bird_remaining = _rng.randf_range(float(profiles.bird_interval_seconds[0]), float(profiles.bird_interval_seconds[1]))
	_device_elapsed += delta
	if _device_elapsed >= float(profiles.device_interval_seconds):
		_device_elapsed = 0.0
		update_devices()


func apply_context(context: Dictionary) -> void:
	var was_outside := is_outdoors()
	_context = context.duplicate()
	AudioManager.set_world_acoustics(str(_context.get("reverb", "dry")), self)
	if is_outdoors() and not was_outside:
		_bird_remaining = _rng.randf_range(2.0, 4.0)
		_wind_active = false
		_wind_remaining = _rng.randf_range(2.0, 5.0)
	if not is_outdoors():
		_wind_active = false
		_wind_level = -80.0
		_headless_wind_requested = false
		if is_instance_valid(_wind):
			AudioManager.stop_voice(_wind)
			_wind = null
	if not is_outdoors() and is_instance_valid(_bird_voice):
		AudioManager.stop_voice(_bird_voice)
		_bird_voice = null


func is_outdoors() -> bool:
	return str(_context.get("environment", "void")) in ["outdoor", "rooftop"]


func _update_wind(delta: float) -> void:
	if is_outdoors():
		_wind_remaining -= delta
		if _wind_remaining <= 0.0:
			_wind_active = not _wind_active
			var interval: Array = profiles.wind_gust_seconds if _wind_active else profiles.wind_quiet_seconds
			_wind_remaining = _rng.randf_range(float(interval[0]), float(interval[1]))
	var audible := is_outdoors() and _wind_active
	var target := float((profiles.get("wind_volume_db", {}) as Dictionary).get(str(_context.get("environment", "void")), -80.0)) if audible else -80.0
	_wind_level = move_toward(_wind_level, target, delta * 42.0)
	if audible and (not is_instance_valid(_wind) or _wind.is_queued_for_deletion()):
		if DisplayServer.get_name() != "headless" or not _headless_wind_requested:
			_wind = AudioManager.play_world_loop(str(profiles.wind_set), self, {"spatial_mode": "listener_2d", "volume_db": _wind_level, "mix_role": "outdoor_wind"})
			_headless_wind_requested = true
	if not audible:
		_headless_wind_requested = false
	if is_instance_valid(_wind):
		_wind.volume_db = _wind_level + linear_to_db(maxf(AudioManager.sfx_volume, 0.0001))
		if not audible and _wind_level <= -79.0:
			AudioManager.stop_voice(_wind)
			_wind = null


func play_outdoor_bird() -> void:
	if not is_outdoors() or not is_instance_valid(actor):
		return
	if is_instance_valid(_bird_voice) and not _bird_voice.is_queued_for_deletion():
		return
	var angle := _rng.randf_range(-PI, PI)
	var distance := _rng.randf_range(7.0, 14.0)
	var pos := actor.global_position + Vector3(cos(angle) * distance, _rng.randf_range(2.0, 4.0), sin(angle) * distance)
	_bird_count += 1
	_bird_voice = AudioManager.emit_event(str(profiles.bird_event), {"source_node": self, "source_position": pos, "max_distance": 40.0, "unit_size": 6.0, "volume_db": -1.5})


func _on_footstep() -> void:
	if not is_instance_valid(actor):
		return
	play_footstep(CONTEXT.resolve(actor, profiles))


func play_footstep(context: Dictionary) -> void:
	var surface := str(context.get("surface", "concrete"))
	var key := str((profiles.footsteps as Dictionary).get(surface, "footstep_concrete"))
	_footstep_count += 1
	AudioManager.play_world_one_shot(key, self, {"source_position": context.get("support_position", actor.global_position), "max_distance": 14.0, "unit_size": 2.0, "volume_db": 1.0})


func _scan(node: Node) -> void:
	_register_device(node)
	for child in node.get_children():
		_scan(child)


func _on_node_added(node: Node) -> void:
	if is_instance_valid(world) and world.is_ancestor_of(node):
		_register_device(node)


func _register_device(node: Node) -> void:
	if not node is Node3D:
		return
	var kind := str(node.get_meta("audio_device", ""))
	if kind.is_empty():
		kind = str((profiles.get("device_scenes", {}) as Dictionary).get(node.scene_file_path, ""))
	if kind.is_empty():
		var slug := str(node.get_meta("component_slug", node.get_meta("package_id", "")))
		if (profiles.get("devices", {}) as Dictionary).has(slug):
			kind = slug
	if not (profiles.get("devices", {}) as Dictionary).has(kind):
		return
	var id := node.get_instance_id()
	if not _devices.has(id):
		_devices[id] = {"node": weakref(node), "kind": kind, "voice": null}


func update_devices() -> void:
	var candidates: Array[Dictionary] = []
	for id in _devices.keys():
		var entry: Dictionary = _devices[id]
		var node := (entry.node as WeakRef).get_ref() as Node3D
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			_devices.erase(id)
			continue
		var spec: Dictionary = profiles.devices[entry.kind]
		var distance := actor.global_position.distance_to(node.global_position)
		if not node.is_visible_in_tree() or not bool(node.get_meta("audio_enabled", true)) or absf(actor.global_position.y - node.global_position.y) > 4.5 or distance > float(spec.max_distance):
			_stop_device(entry)
			continue
		candidates.append({"id": id, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	_active_device_count = 0
	for index in range(candidates.size()):
		var entry: Dictionary = _devices[candidates[index].id]
		if index >= int(profiles.device_voice_budget):
			_stop_device(entry)
			continue
		var node := (entry.node as WeakRef).get_ref() as Node3D
		var spec: Dictionary = profiles.devices[entry.kind]
		var occluded := _device_occluded(node)
		var voice: Node = entry.voice if is_instance_valid(entry.voice) else null
		if not is_instance_valid(voice) or voice.is_queued_for_deletion():
			voice = AudioManager.play_world_loop(str(spec.set), node, {"max_distance": float(spec.max_distance), "unit_size": float(spec.unit_size), "volume_db": float(spec.volume_db)})
			entry.voice = voice
		if is_instance_valid(voice):
			voice.volume_db = float(spec.volume_db) - (16.0 if occluded else 0.0) + linear_to_db(maxf(AudioManager.sfx_volume, 0.0001))
			voice.attenuation_filter_cutoff_hz = 1500.0 if occluded else 12000.0
		_active_device_count += 1


func _device_occluded(device: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, device.global_position + Vector3.UP * 0.45, 1, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var obstacle := hit.collider as Node
	return obstacle != device and not device.is_ancestor_of(obstacle)


func _stop_device(entry: Dictionary) -> void:
	var voice: Node = entry.voice if is_instance_valid(entry.voice) else null
	if is_instance_valid(voice):
		AudioManager.stop_voice(voice)
	entry.voice = null


func get_snapshot() -> Dictionary:
	return {"context": _context.duplicate(), "outside": is_outdoors(), "wind_level_db": _wind_level, "devices_registered": _devices.size(), "devices_active": _active_device_count, "footsteps": _footstep_count, "birds": _bird_count}


func _exit_tree() -> void:
	if not _started:
		return
	for entry in _devices.values():
		_stop_device(entry)
	if is_instance_valid(_wind):
		AudioManager.stop_voice(_wind)
	if is_instance_valid(_bird_voice):
		AudioManager.stop_voice(_bird_voice)
	AudioManager.release_world_acoustics(self)
