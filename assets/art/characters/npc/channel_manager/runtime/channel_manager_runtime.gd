class_name ChannelManagerRuntime
extends Node3D
## Performance only. The host owns dialogue, placement, and gameplay effects.
signal runtime_state_changed(previous: String, current: String)
signal skill_result_locked(card: String)
signal release_started
signal release_finished

const FRAMES := {"sleep": 96, "activate": 60, "active_idle": 120, "talk_normal": 48, "talk_happy": 48, "talk_angry": 48, "talk_scheme": 48, "skill_windup": 34, "skill_lock": 14, "skill_release": 22}
const NEXT := {"sleep": ["activate"], "activate": ["active_idle"], "active_idle": ["talk_normal", "talk_happy", "talk_angry", "talk_scheme", "skill_windup"], "talk_normal": ["active_idle", "skill_windup"], "talk_happy": ["active_idle", "skill_windup"], "talk_angry": ["active_idle", "skill_windup"], "talk_scheme": ["active_idle", "skill_windup"], "skill_windup": ["skill_lock", "active_idle"], "skill_lock": ["skill_release", "active_idle"], "skill_release": ["active_idle"]}
const DEFAULT := [0, 1, 2, 3, 4, 5, 2, 6, 7, 8, 9, 10, 11]
const CARDS := {"识别": 6, "监听": 9, "中继": 10}
const COLORS := {"识别": Color("#f4f5ff"), "监听": Color("#a572ed"), "中继": Color("#468be2")}
# 北向 CRT 屏幕（screen_mounts 9-13，法线为 -Z）是裂隙发射端；不再从南向 1 号屏幕发射。
const RELEASE_SCREEN_INDEX := 8
const RELEASE_BEAM_LENGTH_M := 14.6
const MODEL = preload("../components/chr_npc_channel_manager.glb")
const ATLAS = preload("../components/crt_channels_atlas.png")
const MOUNTS = preload("../components/screen_mounts.json")
const SCREEN = preload("channel_manager_screen.gdshader")
const PALETTE = preload("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")

@export var observer_path: NodePath
@export var auto_activate := true
@export var rng_seed := 0
## Optional host override: keeps the reel/lock portion running for a longer bespoke skill beat.
@export var skill_windup_duration_override := 0.0
@export var skill_lock_duration_override := 0.0
var _fsm := StateMachine.new()
var _rng := RandomNumberGenerator.new()
var _player: AnimationPlayer
var _rig: Skeleton3D
var _observer: Node3D
var _mounts: Array
var _screens: Array[Dictionary] = []
var _leds: Array[StandardMaterial3D] = []
var _beam: MeshInstance3D
var _halo: MeshInstance3D
var _ready_ok := false
var _result := ""
var _talk_length := 0.0
var _cue_sent := false
var _clock := 0.0

func _ready() -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	var model := MODEL.instantiate()
	add_child(model)
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_rig = skeletons[0] as Skeleton3D
	_mounts = MOUNTS.data.get("screens", [])
	if _player == null or _rig == null or _mounts.size() != 13:
		push_error("ChannelManager: incomplete rig or mount contract")
		return
	for key: String in FRAMES:
		if not _player.has_animation(key) or absf(_player.get_animation(key).length - float(FRAMES[key]) / 24.0) > 0.045:
			push_error("ChannelManager: invalid or missing clip " + key)
			return
	for i in range(13):
		var mesh := model.find_child("CRT_%02d_Screen" % (i + 1), true, false) as MeshInstance3D
		var joint := _rig.find_bone(_mounts[i]["bone"])
		if mesh == null or joint < 0:
			push_error("ChannelManager: missing screen or bone " + str(i + 1))
			return
		var mat := ShaderMaterial.new()
		mat.shader = SCREEN
		mat.set_shader_parameter("atlas_texture", ATLAS)
		mesh.material_override = mat
		_screens.append({"mat": mat, "joint": joint, "inv_rest": _rig.get_bone_global_rest(joint).affine_inverse(), "slot": DEFAULT[i], "target": DEFAULT[i], "wait": _next_wait(), "snow": 0.0, "eye": false, "aim": false, "gaze": Vector2.ZERO})
	_bind_palette(model)
	_beam = _make_beam(0.065, Color(1.0, 0.72, 0.99), false)
	_halo = _make_beam(0.19, Color(0.65, 0.27, 1.0, 0.30), true)
	add_child(_fsm)
	_fsm.owner_node = self
	for key: String in FRAMES:
		_fsm.register(key, State.new())
	_fsm.configure_transition_map(NEXT)
	_fsm.state_changed.connect(_state_entered)
	if not observer_path.is_empty():
		_observer = get_node_or_null(observer_path) as Node3D
	_ready_ok = true
	_fsm.start("sleep")
	_draw_screens(0.0)

func set_observer(target: Node3D) -> void:
	_observer = target

func get_state_name() -> String:
	return _fsm.current_state_name

func activate() -> bool:
	return _ready_ok and get_state_name() == "sleep" and _fsm.transition_to("activate")

func begin_talk(emotion: String, duration := 2.0) -> bool:
	var clip := "talk_" + emotion
	if get_state_name() != "active_idle" or not FRAMES.has(clip) or not is_finite(duration):
		return false
	_talk_length = clampf(duration, 0.25, 30.0)
	return _fsm.transition_to(clip)

func end_talk() -> bool:
	return get_state_name().begins_with("talk_") and _fsm.transition_to("active_idle")

func trigger_skill(card := "") -> bool:
	var state := get_state_name()
	if (state != "active_idle" and not state.begins_with("talk_")) or (not card.is_empty() and not CARDS.has(card)):
		return false
	_result = card if not card.is_empty() else str(CARDS.keys()[_rng.randi_range(0, 2)])
	return _fsm.transition_to("skill_windup")

func cancel_skill() -> bool:
	if get_state_name() not in ["skill_windup", "skill_lock"]:
		return false
	_result = ""
	return _fsm.transition_to("active_idle")

func get_snapshot() -> Dictionary:
	var displays: Array[Dictionary] = []
	for row in _screens:
		var mat: ShaderMaterial = row.mat
		displays.append({"slot": mat.get_shader_parameter("atlas_slot"), "mode": mat.get_shader_parameter("mode"), "card_color": mat.get_shader_parameter("card_color"), "snow": mat.get_shader_parameter("snow_amount"), "gaze": row.gaze, "eye_aim": row.eye})
	return {"ready": _ready_ok, "state": get_state_name(), "elapsed": _fsm.state_elapsed, "result": _result, "displays": displays, "beam_visible": is_instance_valid(_beam) and _beam.visible, "bone_count": _rig.get_bone_count() if is_instance_valid(_rig) else 0}

func _process(delta: float) -> void:
	step_presentation(delta)

func _state_seconds(state: String) -> float:
	if state == "skill_windup" and skill_windup_duration_override > 0.0:
		return skill_windup_duration_override
	if state == "skill_lock" and skill_lock_duration_override > 0.0:
		return skill_lock_duration_override
	return float(FRAMES[state]) / 24.0

func step_presentation(delta: float) -> void:
	if not _ready_ok or not is_finite(delta) or delta < 0.0:
		return
	_clock = fmod(_clock + delta, 3600.0)
	if auto_activate and get_state_name() == "sleep" and is_instance_valid(_observer):
		var d := _observer.global_position - global_position
		if Vector2(d.x, d.z).length_squared() <= 36.0:
			activate()
	_fsm.physics_update(delta)
	var state := get_state_name()
	var t := _fsm.state_elapsed
	if state in ["activate", "skill_windup", "skill_lock", "skill_release"] and t + 0.0001 >= _state_seconds(state):
		if state == "skill_release":
			_release_cue()
			_result = ""
			_fsm.transition_to("active_idle")
			release_finished.emit()
		else:
			_fsm.transition_to({"activate": "active_idle", "skill_windup": "skill_lock", "skill_lock": "skill_release"}[state])
	elif state.begins_with("talk_") and t >= _talk_length:
		end_talk()
	_draw_screens(delta)

func _state_entered(previous: String, current: String) -> void:
	var clip := _player.get_animation(current)
	clip.loop_mode = Animation.LOOP_LINEAR if current in ["sleep", "active_idle"] or current.begins_with("talk_") else Animation.LOOP_NONE
	_player.play(current, 0.12 if current.begins_with("talk_") or (current == "active_idle" and previous != "activate") else 0.0)
	_player.advance(0.0)
	if current == "skill_lock":
		skill_result_locked.emit(_result)
	if current == "skill_release":
		_cue_sent = false
	if current == "active_idle":
		for row in _screens:
			row.snow = 0.0; row.wait = _next_wait(); row.eye = false; row.aim = false
	runtime_state_changed.emit(previous, current)

func _next_wait() -> float:
	return _rng.randf_range(1.8, 4.2)

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _socket(i: int) -> Transform3D:
	var joint: int = _screens[i].joint
	var d: Transform3D = _rig.global_transform * _rig.get_bone_global_pose(joint) * _screens[i].inv_rest
	var m: Dictionary = _mounts[i]
	var n := (d.basis * _vec(m.normal)).normalized()
	var r := (d.basis * _vec(m.right)).normalized()
	return Transform3D(Basis(r, n.cross(r).normalized(), n), d * _vec(m.center))

func _update_idle(i: int, dt: float) -> void:
	var row := _screens[i]
	var aim := false
	var desired := Vector2.ZERO
	if is_instance_valid(_observer):
		var ts := _socket(i)
		var offset := _observer.global_position - ts.origin
		var flat := Vector2(offset.x, offset.z)
		var face := Vector2(ts.basis.z.x, ts.basis.z.z).normalized()
		aim = flat.length_squared() > 0.0001 and flat.length_squared() <= 36.0 and face.dot(flat.normalized()) >= 0.7071067
		if aim:
			var direction := offset.normalized()
			desired = Vector2(clampf(ts.basis.x.dot(direction) * 0.26, -0.16, 0.16), clampf(-ts.basis.y.dot(direction) * 0.25, -0.10, 0.10))
	row.gaze = (row.gaze as Vector2).lerp(desired, 1.0 - exp(-12.0 * dt))
	if aim != row.aim:
		row.aim = aim; row.snow = 0.28; row.target = row.slot
	elif row.snow <= 0.0 and not aim:
		row.wait -= dt
		if row.wait <= 0.0:
			row.target = (row.slot + _rng.randi_range(1, 11)) % 12
			row.snow = 0.28; row.wait = _next_wait()
	if row.snow > 0.0:
		row.snow = maxf(0.0, row.snow - dt)
		if row.snow <= 0.14:
			row.eye = row.aim; row.slot = row.target

func _draw_screens(dt: float) -> void:
	var state := get_state_name()
	var t := _fsm.state_elapsed
	for i in range(13):
		var row := _screens[i]
		var mode := 0
		var slot: int = row.slot
		var next_slot := 0
		var snow := 0.04
		var bright := 1.0
		var phase := 0.0
		var openness := 1.0
		var tint := Color.WHITE
		match state:
			"sleep":
				mode = 1; snow = 1.0; bright = 0.24
			"activate":
				var a := 0.18 if i == 0 else 0.54 + float(i - 1) * 0.088
				var lit := smoothstep(a, a + 0.22, t)
				mode = 2 if i in [0, 2, 6] else 0
				snow = 1.0 - 0.95 * lit; bright = lerpf(0.24, 1.15, lit); openness = maxf(lit, 0.022)
			"active_idle":
				_update_idle(i, dt)
				slot = row.slot; mode = 2 if row.eye or slot == 2 else 0
				if row.snow > 0.0:
					snow = smoothstep(0.0, 0.75, 1.0 - absf(row.snow - 0.14) / 0.14)
			"skill_windup":
				if t < 0.46:
					mode = 3; bright = 0.57 + 0.50 * (0.5 + 0.5 * cos(TAU * 2.0 * t)); snow = 0.05
				else:
					mode = 4
					var p := clampf((t - 0.46) / (_state_seconds("skill_windup") - 0.46), 0.0, 1.0)
					var wheel := 11.0 * (1.0 - pow(1.0 - p, 1.6)) + i * 0.12
					slot = (int(floor(wheel)) + i * 5) % 12; next_slot = (slot + 1) % 12; phase = fposmod(wheel, 1.0); snow = 0.1
			"skill_lock", "skill_release":
				mode = 5; slot = CARDS.get(_result, 6); tint = COLORS.get(_result, COLORS["识别"]); snow = 0.0
				bright = 1.03 + (0.40 * exp(-t * 14.0) if state == "skill_lock" else 0.0)
			_:
				if state.begins_with("talk_"):
					mode = {"talk_normal": 6, "talk_happy": 7, "talk_angry": 8, "talk_scheme": 9}[state]
					slot = {6: 4, 7: 5, 8: 3, 9: 1}[mode] if i in [0, 2, 4, 5, 7] else (1 if slot == 2 else slot)
		var mat: ShaderMaterial = row.mat
		mat.set_shader_parameter("mode", mode); mat.set_shader_parameter("atlas_slot", slot); mat.set_shader_parameter("next_slot", next_slot)
		mat.set_shader_parameter("brightness", bright); mat.set_shader_parameter("snow_amount", snow)
		mat.set_shader_parameter("eye_offset", row.gaze if row.eye else Vector2.ZERO); mat.set_shader_parameter("openness", openness)
		mat.set_shader_parameter("roll", phase); mat.set_shader_parameter("card_color", tint)
		mat.set_shader_parameter("signal_clock", _clock + (i * 0.09 if mode >= 6 else 0.0))
	for led in _leds:
		led.emission_energy_multiplier = 0.03 if state == "sleep" else (smoothstep(0.3, 1.65, t) if state == "activate" else 1.0)
	var beam_on := state == "skill_release" and t >= 5.0 / 24.0 and t < 14.0 / 24.0
	_beam.visible = beam_on; _halo.visible = beam_on
	if beam_on:
		# 直接使用北面 CRT 屏幕的 socket；该组的法线为 -Z，目标是北墙，不是 NPC 南侧。
		var ts := _socket(RELEASE_SCREEN_INDEX)
		var p := clampf((t - 5.0 / 24.0) / (9.0 / 24.0), 0.0, 1.0)
		var length := RELEASE_BEAM_LENGTH_M * smoothstep(0.0, 0.23, p)
		_beam.global_transform = Transform3D(ts.basis.scaled_local(Vector3(1.0, 1.0, maxf(0.002, length))), ts.origin + ts.basis.z * (length * 0.5 + 0.02))
		_halo.global_transform = _beam.global_transform
		_release_cue()

func _release_cue() -> void:
	if not _cue_sent:
		_cue_sent = true
		release_started.emit()

func _bind_palette(node: Node) -> void:
	if node is MeshInstance3D and not str(node.name).ends_with("_Screen"):
		for j in range(node.mesh.get_surface_count()):
			var imported := node.mesh.surface_get_material(j) as StandardMaterial3D
			if imported == null:
				continue
			var m := imported.duplicate() as StandardMaterial3D
			m.albedo_color = Color.WHITE; m.albedo_texture = PALETTE; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			if str(node.name).ends_with("_LED"):
				m.emission_enabled = true; m.emission_texture = PALETTE; m.emission = Color.BLACK; _leds.append(m)
			node.set_surface_override_material(j, m)
	for child in node.get_children():
		_bind_palette(child)

func _make_beam(width: float, color: Color, halo: bool) -> MeshInstance3D:
	var ob := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, 1.0); ob.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = color
	if halo:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.emission_enabled = true; m.emission = Color("#f078ff"); m.emission_energy_multiplier = 3.5
	ob.material_override = m; ob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$ReleaseBeam.add_child(ob); ob.hide()
	return ob
