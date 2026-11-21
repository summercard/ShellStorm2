extends Node3D

const MAX_STEP := 1.0 / 60.0
const EMITTER_METHODS := [&"prepare", &"begin", &"advance", &"sync_draw", &"work_pending", &"stop", &"debug_state", &"trigger_sub"]

@export var auto_play: bool = true
@export var source_id: String = ""
@export var source_sha256: String = ""
@export var source_gravity: Vector3 = Vector3.ZERO
@export var source_gravity_2d: Vector2 = Vector2.ZERO
@export var components: Array[Dictionary] = []
@export var source_prefab: String = ""

var _emitters: Array[Node3D] = []
var _by_key: Dictionary = {}
var _routes: Dictionary = {}
var _referenced: Dictionary = {}
var _events: Array[Dictionary] = []
var _ancestry := PackedStringArray()
var _routing_rng := RandomNumberGenerator.new()
var _pitch_rng := RandomNumberGenerator.new()
var _sub_calls: int = 0
var _sub_counts: Dictionary = {}
var _audio: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _rotations: Array[Dictionary] = []
var _audio_calls: int = 0
var _elapsed: float = 0.0
var _started: bool = false
var _running: bool = false


func _ready() -> void:
	set_physics_process(false)
	_collect_emitters(self)
	_build_routes()
	_bind_components()
	if auto_play:
		_play(-1, true)


func play_exact(seed: int = -1) -> void:
	if is_node_ready():
		_play(seed, false)


func _play(seed: int, awake_only: bool) -> void:
	var seed_base := int(randi()) if seed < 0 else seed
	stop_exact(true)
	_elapsed = 0.0
	_started = true
	_running = true
	_sub_calls = 0
	_sub_counts.clear()
	_routing_rng.seed = seed_base ^ 0x5a104e71
	_pitch_rng.seed = seed_base ^ 0x3a5519bf
	for row: Dictionary in _rotations:
		var target: Node3D = row.target
		if row.has("base"):
			target.quaternion = row.base
		else:
			row.base = target.quaternion
	for i: int in range(_emitters.size()):
		var emitter: Node3D = _emitters[i]
		var data: Dictionary = emitter.get("source")
		var awake := bool(_dict(data.get("main")).get("play_on_awake", true))
		var key := str(emitter.get("component_key"))
		# Unity suppresses autonomous emission for a linked sub-emitter, even
		# with Play On Awake enabled (measured on Birth/Death and source prefabs).
		var direct := bool(data.get("active", true)) and not _referenced.has(key) and (awake or not awake_only)
		emitter.call("begin", seed_base + i * 607, direct)
	_flush_events()
	for row: Dictionary in _audio:
		_start_audio(row)
	for row: Dictionary in _lights:
		var target: Light3D = row.target
		row.state = "active" if row.enabled else "disabled"
		row.faded = false
		target.light_energy = row.intensity if row.enabled else 0.0
		target.visible = row.enabled
	_sync_emitters()
	_running = _has_work()
	set_physics_process(_running)


func stop_exact(clear_particles: bool = false) -> void:
	_started = false
	_events.clear()
	for emitter: Node3D in _emitters:
		emitter.call("stop", clear_particles)
	for row: Dictionary in _audio:
		row.target.stop()
	for row: Dictionary in _lights:
		row.target.hide()
		row.target.light_energy = 0.0
		row.state = "stopped"
	if clear_particles:
		_sync_emitters()
		_running = false
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	advance_exact(delta)


func advance_exact(dt: float) -> void:
	if not _running or not is_finite(dt) or dt <= 0.0:
		return
	var left := dt
	while left > 0.0000001 and _running:
		var step := minf(left, MAX_STEP)
		_elapsed += step
		if _started:
			_tick_rotation(step)
			_tick_lights()
		for emitter: Node3D in _emitters:
			emitter.call("advance", step)
		_flush_events()
		_running = _has_work()
		left -= step
	_sync_emitters()
	if not _running:
		set_physics_process(false)


func debug_exact(include_particles: bool = false) -> Dictionary:
	var layers: Dictionary = {}
	for emitter: Node3D in _emitters:
		layers[str(emitter.get("component_key"))] = emitter.call("debug_state", include_particles)
	var audio: Dictionary = {}
	var audio_playing := false
	for row: Dictionary in _audio:
		var playing := bool(row.target.playing)
		audio_playing = audio_playing or playing
		audio[row.key] = {"play_calls": row.calls, "playing": playing, "enabled": row.enabled,
			"volume": row.volume, "pitch": row.pitch, "loop": row.loop, "spatial": row.target is AudioStreamPlayer3D,
			"has_stream": row.target.stream != null, "unsupported_pitch": row.pitch <= 0.0}
	var lights: Dictionary = {}
	var light_exists := false
	var light_energy := 0.0
	for row: Dictionary in _lights:
		var exists: bool = row.state == "active" or row.state == "disabled"
		var target: Light3D = row.target
		var visible := target.is_visible_in_tree()
		light_exists = light_exists or exists
		if visible:
			light_energy += target.light_energy
		lights[row.key] = {"exists": exists, "visible": visible, "energy": target.light_energy, "state": row.state,
			"type": row.type, "source_intensity": row.intensity,
			"range": target.omni_range if target is OmniLight3D else (target.spot_range if target is SpotLight3D else 0.0),
			"spot_angle": target.spot_angle if target is SpotLight3D else 0.0}
	return {"source_id": source_id, "source_prefab": source_prefab, "source_sha256": source_sha256,
		"elapsed": _elapsed, "running": _running, "started": _started, "layers": layers,
		"audio_play_calls": _audio_calls, "audio_playing": audio_playing, "audio": audio,
		"light_exists": light_exists, "light_energy": light_energy, "lights": lights,
		"sub_trigger_calls": _sub_calls, "sub_triggers": _sub_counts.duplicate(true), "sub_only_keys": _referenced.keys()}


func _collect_emitters(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Node3D and child.has_signal("source_event") and _is_emitter(child):
			var key := str(child.get("component_key"))
			if not key.is_empty() and not _by_key.has(key):
				var data: Dictionary = child.get("source")
				var gravity := source_gravity
				if _enum_name(_dict(data.get("main")).get("gravity_source", "Physics3D")) == "physics2d":
					gravity = Vector3(source_gravity_2d.x, source_gravity_2d.y, 0.0)
				child.call("prepare", gravity)
				child.connect("source_event", _on_source_event)
				_emitters.append(child as Node3D)
				_by_key[key] = child
		_collect_emitters(child)


func _is_emitter(node: Node) -> bool:
	for method: StringName in EMITTER_METHODS:
		if not node.has_method(method):
			return false
	return true


func _build_routes() -> void:
	for emitter: Node3D in _emitters:
		var key := str(emitter.get("component_key"))
		var source: Dictionary = emitter.get("source")
		var data := _dict(source.get("sub_emitters"))
		var entries: Variant = data.get("entries", [])
		if not entries is Array:
			continue
		var by_type: Dictionary = {}
		for value: Variant in entries:
			var entry := _dict(value)
			var target_key := str(_dict(entry.get("system")).get("component_key", ""))
			if not _by_key.has(target_key) or not bool(data.get("enabled", false)) or not bool(source.get("active", true)):
				continue
			_referenced[target_key] = true
			var receiver: Node3D = _by_key[target_key]
			if not bool(_dict(receiver.get("source")).get("active", true)):
				continue
			var event_type := str(entry.get("type", "")).to_lower()
			if not by_type.has(event_type):
				by_type[event_type] = []
			by_type[event_type].append({"target_key": target_key, "target": receiver,
				"probability": clampf(float(entry.get("probability", 1.0)), 0.0, 1.0),
				"flags": int(entry.get("inherit_flags_value", 0))})
		if not by_type.is_empty():
			_routes[key] = by_type


func _on_source_event(emitter: Node3D, event_type: String, world_position: Vector3, world_velocity: Vector3,
		color: Color, size: Vector3, angle: Vector3, lifetime: float) -> void:
	if not _started:
		return
	var key := str(emitter.get("component_key"))
	var kind := event_type.to_lower()
	if not _routes.has(key) or not _routes[key].has(kind) or _ancestry.has(key):
		return
	var path := _ancestry.duplicate()
	path.append(key)
	var parent_id := -1
	if kind == "birth" and emitter.has_method("source_event_particle_id"):
		parent_id = int(emitter.call("source_event_particle_id"))
	_events.append({"kind": kind, "routes": _routes[key][kind], "path": path, "emitter": emitter, "parent_id": parent_id,
		"position": world_position, "velocity": world_velocity, "color": color,
		"size": size, "angle": angle, "lifetime": lifetime})
	if not _running:
		# 一次性效果结束后，手动事件仍可唤醒子层，直到显式停止。
		_running = true
		_flush_events()
		_sync_emitters()
		_running = _has_work()
		set_physics_process(_running)


func _flush_events() -> void:
	# 等所有层完成当前步再派发，避免层顺序改变新生粒子的第一帧年龄。
	var cursor := 0
	while _started and cursor < _events.size():
		var event: Dictionary = _events[cursor]
		cursor += 1
		_ancestry = event.path
		for route: Dictionary in event.routes:
			var probability: float = route.probability
			if _ancestry.has(route.target_key) or probability <= 0.0:
				continue
			if probability < 1.0 and _routing_rng.randf() >= probability:
				continue
			if int(event.parent_id) >= 0 and route.target.has_method("tracked_particle"):
				route.target.call("trigger_sub", event.position, event.velocity, event.color, event.size,
					event.angle, event.lifetime, route.flags, event.emitter, event.parent_id)
			else:
				route.target.call("trigger_sub", event.position, event.velocity, event.color, event.size,
					event.angle, event.lifetime, route.flags)
			_sub_calls += 1
			var counts: Dictionary = _sub_counts.get_or_add(route.target_key, {})
			counts[event.kind] = int(counts.get(event.kind, 0)) + 1
	_ancestry.clear()
	_events.clear()


func _sync_emitters() -> void:
	for emitter: Node3D in _emitters:
		emitter.call("sync_draw")


func _has_work() -> bool:
	for emitter: Node3D in _emitters:
		if bool(emitter.call("work_pending")):
			return true
	if not _started:
		return false
	for row: Dictionary in _rotations:
		if not row.rate.is_zero_approx():
			return true
	for row: Dictionary in _lights:
		if row.state == "active" and row.has("fade_seconds") and not row.faded:
			return true
	return false


func _bind_components() -> void:
	var audio_by_anchor: Dictionary = {}
	var lights_by_anchor: Dictionary = {}
	for i: int in range(components.size()):
		var spec: Dictionary = components[i]
		var kind := str(spec.get("type", "")).get_slice(".", str(spec.get("type", "")).get_slice_count(".") - 1)
		var node: Node = _component_node(spec.get("node", "."))
		var target: Node = _component_node(spec.get("target", null))
		var key := str(spec.get("component_key", "%s:%s:%d" % [spec.get("node", "."), kind, i]))
		var enabled := bool(spec.get("active", true)) and bool(spec.get("enabled", true))
		match kind:
			"AudioSource":
				if target is AudioStreamPlayer or target is AudioStreamPlayer3D or target is AudioStreamPlayer2D:
					var row := _bind_audio(spec, target, key, enabled)
					_audio.append(row)
					if node != null and not audio_by_anchor.has(node):
						audio_by_anchor[node] = row
			"Light":
				if target is Light3D:
					var row := _bind_light(spec, target as Light3D, key, enabled)
					_lights.append(row)
					if node != null and not lights_by_anchor.has(node):
						lights_by_anchor[node] = row
			"ETFXRotation":
				if enabled and node is Node3D:
					var fields := _dict(spec.get("serialized"))
					var rate := _vec3(spec.get("degrees_per_second", fields.get("rotateVector")))
					var space := _enum_name(spec.get("space", fields.get("rotateSpace", "Local")))
					_rotations.append({"target": node, "rate": Vector3(-rate.x, -rate.y, rate.z), "world": space == "world"})
	for spec: Dictionary in components:
		if not bool(spec.get("active", true)) or not bool(spec.get("enabled", true)):
			continue
		var kind := str(spec.get("type", "")).get_slice(".", str(spec.get("type", "")).get_slice_count(".") - 1)
		var node: Node = _component_node(spec.get("node", "."))
		var explicit_target: Node = _component_node(spec.get("target", null))
		var fields := _dict(spec.get("serialized"))
		match kind:
			"ETFXPitchRandomizer":
				var row := _find_bound(_audio, explicit_target, _dict(audio_by_anchor.get(node)))
				if not row.is_empty():
					row.pitch_factors.append(float(spec.get("random_percent", fields.get("randomPercent", 10.0))) / 100.0)
			"ETFXLightFade":
				var row := _find_bound(_lights, explicit_target, _dict(lights_by_anchor.get(node)))
				if not row.is_empty():
					row.fade_seconds = float(spec.get("fade_seconds", fields.get("life", 0.2)))
					row.fade_end = _enum_name(spec.get("on_life_end", fields.get("onLifeEnd", "Destroy")))


func _bind_audio(spec: Dictionary, target: Node, key: String, enabled: bool) -> Dictionary:
	target.set("autoplay", false)
	target.call("stop")
	var stream: AudioStream = target.get("stream")
	var loop := bool(spec.get("loop", false))
	if stream is AudioStreamWAV:
		if (stream.loop_mode != AudioStreamWAV.LOOP_DISABLED) != loop:
			var copy := stream.duplicate() as AudioStreamWAV
			copy.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
			if loop:
				copy.loop_begin = 0
				copy.loop_end = roundi(copy.get_length() * copy.mix_rate)
			target.set("stream", copy)
	elif stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		if bool(stream.get("loop")) != loop:
			var copy := stream.duplicate() as AudioStream
			copy.set("loop", loop)
			target.set("stream", copy)
	if target is AudioStreamPlayer3D:
		target.unit_size = maxf(0.001, float(spec.get("min_distance", target.unit_size)))
		target.max_distance = maxf(0.0, float(spec.get("max_distance", target.max_distance)))
		if float(spec.get("doppler_level", 0.0)) == 0.0:
			target.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	return {"target": target, "key": key, "enabled": enabled, "calls": 0,
		"volume": clampf(float(spec.get("volume", 1.0)), 0.0, 1.0), "mute": bool(spec.get("mute", false)),
		"base_pitch": float(spec.get("pitch", 1.0)), "pitch": float(spec.get("pitch", 1.0)), "pitch_factors": [],
		"play_on_awake": bool(spec.get("play_on_awake", true)), "loop": loop}


func _start_audio(row: Dictionary) -> void:
	var target: Node = row.target
	var volume: float = 0.0 if row.mute else row.volume
	var pitch: float = row.base_pitch
	if row.enabled:
		for fraction: float in row.pitch_factors:
			pitch *= 1.0 + _pitch_rng.randf_range(-fraction, fraction)
	row.pitch = pitch
	target.set("volume_db", linear_to_db(maxf(volume, 0.000001)))
	# Godot 播放器不支持零速或倒放，不把它转换成正速播放。
	if pitch > 0.0:
		target.set("pitch_scale", pitch)
		if row.enabled and row.play_on_awake and target.get("stream") != null:
			target.call("play")
			row.calls += 1
			_audio_calls += 1


func _bind_light(spec: Dictionary, target: Light3D, key: String, enabled: bool) -> Dictionary:
	var raw_color: Variant = spec.get("color", Color.WHITE)
	if raw_color is Color:
		target.light_color = raw_color
	elif raw_color is Array and raw_color.size() >= 3:
		target.light_color = Color(float(raw_color[0]), float(raw_color[1]), float(raw_color[2]))
	var intensity := maxf(0.0, float(spec.get("intensity", target.light_energy)))
	target.light_energy = 0.0
	target.light_indirect_energy = float(spec.get("bounce_intensity", target.light_indirect_energy))
	target.light_cull_mask = int(spec.get("culling_mask", target.light_cull_mask)) & 0xffffffff
	if spec.has("shadows"):
		var shadows := _enum_name(spec.shadows)
		target.shadow_enabled = shadows != "none" and shadows != "0" and shadows != "false"
	if spec.has("shadow_strength"):
		target.shadow_opacity = float(spec.shadow_strength)
	if spec.has("shadow_bias"):
		target.shadow_bias = float(spec.shadow_bias)
	if spec.has("shadow_normal_bias"):
		target.shadow_normal_bias = float(spec.shadow_normal_bias)
	if target is OmniLight3D:
		target.omni_range = maxf(0.001, float(spec.get("range", target.omni_range)))
	elif target is SpotLight3D:
		target.spot_range = maxf(0.001, float(spec.get("range", target.spot_range)))
		if spec.has("spot_angle"):
			target.spot_angle = clampf(float(spec.spot_angle) * 0.5, 0.01, 89.99)
	target.hide()
	return {"target": target, "key": key, "enabled": enabled, "intensity": intensity,
		"type": _enum_name(spec.get("light_type", "Spot" if target is SpotLight3D else "Point")),
		"state": "idle", "faded": false}


func _tick_lights() -> void:
	for row: Dictionary in _lights:
		if row.state != "active" or not row.has("fade_seconds") or row.faded:
			continue
		var light: Light3D = row.target
		var seconds: float = row.fade_seconds
		var amount := 1.0 if is_zero_approx(seconds) else _elapsed / seconds
		light.light_energy = maxf(0.0, row.intensity * (1.0 - amount))
		if light.light_energy <= 0.000001:
			light.light_energy = 0.0
			row.faded = true
			match str(row.fade_end):
				"disable":
					row.state = "disabled"
					light.hide()
				"destroy":
					# 保留场景绑定供下一次播放，当前轮该光源不再有效。
					row.state = "destroyed"
					light.hide()


func _tick_rotation(dt: float) -> void:
	for row: Dictionary in _rotations:
		var target: Node3D = row.target
		var rate: Vector3 = row.rate
		var delta := Basis.from_euler(rate * deg_to_rad(dt), EULER_ORDER_YXZ).get_rotation_quaternion()
		if row.world:
			var parent_rotation := Quaternion.IDENTITY
			var parent := target.get_parent_node_3d()
			if not target.top_level:
				while parent != null:
					parent_rotation = parent.quaternion * parent_rotation
					if parent.top_level:
						break
					parent = parent.get_parent_node_3d()
			target.quaternion = (parent_rotation.inverse() * delta * parent_rotation * target.quaternion).normalized()
		else:
			target.quaternion = (target.quaternion * delta).normalized()


func _component_node(value: Variant) -> Node:
	if value == null:
		return null
	var path := str(value)
	return self if path.is_empty() else get_node_or_null(NodePath(path))


func _find_bound(rows: Array[Dictionary], target: Node, fallback: Dictionary) -> Dictionary:
	if target != null:
		for row: Dictionary in rows:
			if row.target == target:
				return row
	return fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _enum_name(value: Variant) -> String:
	return str(value.get("name", "") if value is Dictionary else value).to_lower()


static func _vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
