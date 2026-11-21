extends Node3D
## Public API preserved for all seven exact_v1 scenes. Each source layer has
## its own emission timeline and lives under its existing node name.

const Emitter := preload("Generated/unity_vfx_emitter.gd")
const Math := preload("Generated/unity_vfx_math.gd")
const MAX_STEP := 1.0 / 60.0

@export var auto_play := true
@export var source_id := ""
@export var source_sha256 := ""
@export var source_gravity := Vector3.ZERO
@export var components: Array[Dictionary] = []

var _emitters: Array[Emitter] = []
var _audio: AudioStreamPlayer
var _sound_data: Dictionary = {}
var _light: OmniLight3D
var _light_data: Dictionary = {}
var _fade: Dictionary = {}
var _rotation_target: Emitter
var _rotation_rate := Vector3.ZERO
var _started := false
var _running := false
var _elapsed := 0.0
var _played_audio := 0

func _ready() -> void:
	set_physics_process(false)
	for child: Node in get_children():
		var emitter := child as Emitter
		if emitter != null:
			emitter.prepare(source_gravity)
			_emitters.append(emitter)
	_audio = get_node_or_null("UnityAudioSource") as AudioStreamPlayer
	for spec: Dictionary in components:
		if not bool(spec.enabled): continue
		match String(spec.type):
			"AudioSource": _sound_data = spec
			"Light": _light_data = spec
			"ETFXLightFade": _fade = spec
			"ETFXRotation":
				_rotation_target = get_node_or_null(NodePath(String(spec.path))) as Emitter
				_rotation_rate = Math.vec(spec.degrees_per_second)
	if auto_play:
		play_exact()

func play_exact(seed_value: int = -1) -> void:
	if not is_node_ready(): return
	var seed_base := randi() if seed_value < 0 else seed_value
	_elapsed = 0.0
	_started = true
	_running = true
	for index in range(_emitters.size()):
		_emitters[index].begin(seed_base + 607 * index)
	if _audio != null and not _sound_data.is_empty() and bool(_sound_data.play_on_awake):
		_audio.stop()
		_audio.play()
		_played_audio += 1
	_setup_light()
	set_physics_process(true)

func stop_exact(clear_particles := false) -> void:
	_started = false
	for emitter: Emitter in _emitters: emitter.stop(clear_particles)
	if _audio != null: _audio.stop()
	if is_instance_valid(_light): _release_light()
	if clear_particles:
		_running = false
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	advance_exact(delta)

# Also used by the functional probe, so it exercises the same simulation
# as normal playback. Call with auto physics processing disabled to step manually.
func advance_exact(dt: float) -> void:
	if not _running or dt <= 0.0: return
	var left := dt
	var more := true
	while left > 0.0000001 and more:
		var step := minf(left, MAX_STEP)
		_elapsed += step
		if _rotation_target != null and _started:
			_rotation_target.update_emitter_rotation(_elapsed, _rotation_rate)
		more = false
		for emitter: Emitter in _emitters:
			emitter.advance(step)
			more = emitter.work_pending() or more
		_tick_light()
		left -= step
	for emitter: Emitter in _emitters: emitter.sync_draw()
	if not more and not is_instance_valid(_light):
		_running = false
		set_physics_process(false)

func debug_exact(include_particles := false) -> Dictionary:
	var layers: Dictionary = {}
	for emitter: Emitter in _emitters:
		layers[String(emitter.name)] = emitter.debug_state(include_particles)
	return {"source_id": source_id, "elapsed": _elapsed, "running": _running, "layers": layers,
		"audio_play_calls": _played_audio, "audio_playing": _audio != null and _audio.playing,
		"light_exists": is_instance_valid(_light), "light_energy": _light.light_energy if is_instance_valid(_light) else 0.0}

func _setup_light() -> void:
	if is_instance_valid(_light): _release_light()
	if _light_data.is_empty(): return
	_light = OmniLight3D.new()
	_light.name = "UnityPointLight"
	_light.light_color = Math.rgba(_light_data.color)
	_light.light_energy = float(_light_data.intensity)
	_light.light_indirect_energy = float(_light_data.bounce_intensity)
	_light.omni_range = float(_light_data.range)
	_light.shadow_enabled = bool(_light_data.shadows)
	_light.light_cull_mask = int(_light_data.culling_mask) & 0xffffffff
	var owner_path: String = _light_data.path
	var anchor := get_node_or_null(NodePath(owner_path)) if not owner_path.is_empty() else self
	anchor.add_child(_light)

func _tick_light() -> void:
	if not is_instance_valid(_light) or _fade.is_empty(): return
	var t := clampf(_elapsed / maxf(float(_fade.fade_seconds), 0.000001), 0.0, 1.0)
	_light.light_energy = float(_light_data.intensity) * (1.0 - t)
	if t >= 1.0 - 1.0e-6:
		match String(_fade.on_life_end):
			"Destroy": _release_light()
			"Disable": _light.hide()

func _release_light() -> void:
	_light.hide()
	_light.get_parent().remove_child(_light)
	_light.queue_free()
	_light = null
