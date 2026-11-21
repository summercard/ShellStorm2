extends Node3D

signal source_event(emitter: Node3D, event_type: String, world_position: Vector3, world_velocity: Vector3, color: Color, size: Vector3, angle: Vector3, lifetime: float)

const Math := preload("res://assets/art/vfx/library/UnityOneToOne_exact_v1/Generated/unity_vfx_math.gd")
const Draw := preload("library_draw.gd")
const CanvasCollision := preload("library_canvas_collision.gd")
const EPS := 0.000001
const PREWARM_STEP := 1.0 / 60.0

@export var component_key: String = ""
@export var source: Dictionary = {}
@export var source_mesh: Mesh
@export var source_meshes: Array[Mesh] = []
@export var main_texture: Texture2D
@export var trail_texture: Texture2D
@export var material_textures: Array[Texture2D] = []
@export var custom_simulation_node: Node3D
@export var collision_planes: Array[Node3D] = []

var _main: Dictionary
var _emission: Dictionary
var _shape: Dictionary
var _sheet: Dictionary
var _limit: Dictionary
var _size: Dictionary
var _color: Dictionary
var _rotation: Dictionary
var _noise: Dictionary
var _trail: Dictionary
var _collision: Dictionary
var _velocity: Dictionary
var _force: Dictionary
var _inherit: Dictionary
var _spin: Dictionary
var _sub: Dictionary
var _birth_events: bool
var _death_events: bool
var _collision_events: bool
var _manual_events: bool
var _space: String
var _scaling: String
var _mesh_mode: bool
var _mesh_count: int
var _mesh_indices: Array[int] = []
var _mesh_weights: Array[float] = []
var _duration: float
var _world_gravity: Vector3
var _drawer := Draw.new()
var _rng := RandomNumberGenerator.new()
var _field: FastNoiseLite
var _sphere: SphereShape3D
var _sweep: PhysicsShapeQueryParameters3D
var _live: Array[Dictionary] = []
var _live_by_id: Dictionary = {}
var _event_particle_id := -1
var _lingering: Array[Dictionary] = []
var _pending_sub: Array[Dictionary] = []
var _sub_streams: Array[Dictionary] = []
var _burst_times: Array[Dictionary] = []
var _next_burst := 0
var _enabled := false
var _warming := false
var _time := 0.0
var _start := 0.0
var _rate_credit := 0.0
var _distance_credit := 0.0
var _rate_roll := 0.0
var _distance_roll := 0.0
var _cycle := -1
var _serial := 0
var _emitted_rate := 0
var _emitted_burst := 0
var _emitted_distance := 0
var _emitted_sub := 0
var _collision_hits := 0
var _noise_samples := 0
var _trail_births := 0
var _first_birth := -1.0
var _previous_birth_frame: Transform3D
var _current_birth_frame: Transform3D
var _sim_frame: Transform3D
var _sim_inverse: Transform3D
var _step_from := 0.0
var _emitter_world_velocity := Vector3.ZERO
var _base_rotation: Quaternion
var _base_scale: Vector3

func prepare(project_gravity: Vector3) -> void:
	_main = source.get("main", {})
	_emission = source.get("emission", {})
	_shape = source.get("shape", {})
	_sheet = source.get("sheet", {})
	_limit = source.get("limit_velocity", {})
	_size = source.get("size_over_lifetime", {})
	_color = source.get("color_over_lifetime", {})
	_rotation = source.get("rotation_over_lifetime", {})
	_noise = source.get("noise", {})
	_trail = source.get("trails", {})
	_collision = source.get("collision", {})
	_velocity = source.get("velocity_over_lifetime", {})
	_force = source.get("force_over_lifetime", {})
	_inherit = source.get("inherit_velocity", {})
	_spin = source.get("rotation_by_speed", {})
	_sub = source.get("sub_emitters", {})
	_birth_events = _has_sub_type("Birth")
	_death_events = _has_sub_type("Death")
	_collision_events = _has_sub_type("Collision")
	_manual_events = _has_sub_type("Manual")
	_space = str(_main.get("simulation_space", "Local"))
	_scaling = str(_main.get("scaling_mode", "Hierarchy"))
	_duration = maxf(0.0001, float(_main.get("duration", 5.0)))
	_world_gravity = project_gravity
	_base_rotation = quaternion
	_base_scale = scale
	var renderer: Dictionary = source.get("renderer", {})
	_mesh_mode = renderer.get("render_mode") == "Mesh"
	var meshes: Array[Mesh] = source_meshes.duplicate()
	if meshes.is_empty() and source_mesh != null: meshes.append(source_mesh)
	_mesh_indices.clear()
	_mesh_weights.clear()
	var weights: Dictionary = {}
	if renderer.get("mesh_distribution") == "NonUniformRandom":
		for slot: Dictionary in renderer.get("mesh_slots", []):
			weights[int(slot.get("slot", 0))] = maxf(0.0, float(slot.get("weight", 1.0)))
	for i in range(meshes.size()):
		if meshes[i] == null: continue
		_mesh_indices.append(i)
		_mesh_weights.append(float(weights.get(i, 1.0)))
	_mesh_count = _mesh_indices.size()
	_drawer.setup_library(self, source, meshes, main_texture, trail_texture, material_textures)
	_make_bursts()
	_field = null
	if _on(_noise):
		_field = FastNoiseLite.new()
		_field.noise_type = FastNoiseLite.TYPE_PERLIN
		_field.frequency = float(_noise.get("frequency", 0.5))
		_field.fractal_type = FastNoiseLite.FRACTAL_NONE if int(_noise.get("octave_count", 1)) <= 1 else FastNoiseLite.FRACTAL_FBM
		_field.fractal_octaves = maxi(1, int(_noise.get("octave_count", 1)))
		_field.fractal_gain = float(_noise.get("octave_multiplier", 0.5))
		_field.fractal_lacunarity = float(_noise.get("octave_scale", 2.0))
	_sweep = null
	if _on(_collision) and _collision.get("type", "World") == "World" and _collision.get("mode", "Collision3D") == "Collision3D":
		_sphere = SphereShape3D.new()
		_sweep = PhysicsShapeQueryParameters3D.new()
		_sweep.shape = _sphere
		_sweep.collision_mask = int(_collision.get("collides_with", -1)) & 0xffffffff
		_sweep.margin = 0.00005

func plays_on_awake() -> bool:
	return bool(source.get("main", {}).get("play_on_awake", true))

func begin(seed_value: int, direct: bool = true) -> void:
	_rng.seed = seed_value if bool(_main.get("random_seed_is_auto", true)) else int(_main.get("random_seed", 0))
	if _field != null: _field.seed = int(_rng.seed & 0x7fffffff)
	_enabled = direct and bool(source.get("active", true)) and _on(_emission)
	_time = 0.0
	_start = maxf(0.0, _scalar(_main, "start_delay", 0.0, _rng.randf()))
	_rate_credit = 0.0
	_distance_credit = 0.0
	_rate_roll = _rng.randf()
	_distance_roll = _rng.randf()
	_cycle = -1
	_serial = 0
	_emitted_rate = 0
	_emitted_burst = 0
	_emitted_distance = 0
	_emitted_sub = 0
	_collision_hits = 0
	_noise_samples = 0
	_trail_births = 0
	_first_birth = -1.0
	_live.clear()
	_live_by_id.clear()
	_lingering.clear()
	_pending_sub.clear()
	_sub_streams.clear()
	quaternion = _base_rotation
	scale = _base_scale
	_current_birth_frame = _birth_frame()
	_previous_birth_frame = _current_birth_frame
	_refresh_sim_frame()
	_emitter_world_velocity = Vector3.ZERO
	_drawer.clear()
	if _enabled and bool(_main.get("loop", true)) and bool(_main.get("prewarm", false)):
		_warming = true
		_start = 0.0
		while _time < _duration - EPS:
			_step(minf(PREWARM_STEP, _duration - _time))
		_warming = false

func stop(clear_now: bool = false) -> void:
	_enabled = false
	_pending_sub.clear()
	_sub_streams.clear()
	if clear_now:
		_live.clear()
		_live_by_id.clear()
		_lingering.clear()
		_drawer.clear()

func work_pending() -> bool:
	return _enabled or not _live.is_empty() or not _lingering.is_empty() or not _pending_sub.is_empty() or not _sub_streams.is_empty()

func update_emitter_rotation(elapsed: float, unity_degrees_per_second: Vector3) -> void:
	var angles := Math.axial(unity_degrees_per_second) * deg_to_rad(elapsed)
	quaternion = _base_rotation * Basis.from_euler(angles, EULER_ORDER_YXZ).get_rotation_quaternion()
	scale = _base_scale

func advance(dt_real: float) -> void:
	var dt := maxf(0.0, dt_real * float(_main.get("simulation_speed", 1.0)))
	if dt_real <= EPS or dt <= EPS: return
	_previous_birth_frame = _current_birth_frame
	_current_birth_frame = _birth_frame()
	var transform_velocity := (_current_birth_frame.origin - _previous_birth_frame.origin) / dt_real
	_emitter_world_velocity = transform_velocity
	if _main.get("emitter_velocity_mode", "Transform") == "Rigidbody":
		var host: Node = get_parent()
		while host != null and not host is RigidBody3D and not host is CharacterBody3D:
			host = host.get_parent()
		if host is RigidBody3D: _emitter_world_velocity = host.linear_velocity
		elif host is CharacterBody3D: _emitter_world_velocity = host.get_real_velocity()
	_refresh_sim_frame()
	# 依赖目标在空闲时也刷新时钟及帧，避免再次触发时使用上次的坐标。
	_step(dt)

func _step(dt: float) -> void:
	_step_from = _time
	_time += dt
	var still_alive: Array[Dictionary] = []
	for p in _live:
		_update_particle(p, dt, _step_from)
		if float(p.age) + EPS < float(p.life): still_alive.append(p)
		else: _retire(p)
	_live = still_alive
	var still_visible: Array[Dictionary] = []
	for p in _lingering:
		_trim_trail(p, _time)
		if p.history.size() >= 2: still_visible.append(p)
	_lingering = still_visible
	if _enabled: _emit_between(_step_from, _time)
	_tick_sub_streams(dt)
	_flush_sub()

func _emit_between(t0: float, t1: float) -> void:
	var until := t1 - _start
	if until <= EPS: return
	var cursor := maxf(0.0, t0 - _start)
	var looping := bool(_main.get("loop", true))
	if not looping: until = minf(until, _duration)
	while cursor + EPS < until:
		var cycle := floori((cursor + EPS) / _duration) if looping else 0
		var base := float(cycle) * _duration
		var end := minf(until, base + _duration)
		if cycle != _cycle:
			_cycle = cycle
			_next_burst = 0
		var phase0 := maxf(0.0, cursor - base)
		var phase1 := end - base
		var absolute_start := _start + base
		while _next_burst < _burst_times.size():
			var b := _burst_times[_next_burst]
			if float(b.time) >= phase1 - EPS: break
			_next_burst += 1
			if float(b.time) + EPS < phase0 or _rng.randf() >= float(b.probability): continue
			var count := _burst_count(b.count, float(b.time) / _duration)
			for i in range(count): _birth(float(b.time) / _duration, i, count, "burst", absolute_start + float(b.time))
		var rate := maxf(0.0, _scalar(_emission, "rate_over_time", phase1 / _duration, _rate_roll))
		_rate_credit = _emit_credit(_rate_credit, rate, phase0, phase1, absolute_start, looping, "rate")
		if not _warming:
			var speed := _current_birth_frame.origin.distance_to(_previous_birth_frame.origin) / maxf(EPS, t1 - t0)
			var per_distance := maxf(0.0, _scalar(_emission, "rate_over_distance", phase1 / _duration, _distance_roll))
			_distance_credit = _emit_credit(_distance_credit, per_distance * speed, phase0, phase1, absolute_start, looping, "distance")
		cursor = end
	if not looping and t1 >= _start + _duration - EPS: _enabled = false

func _make_bursts() -> void:
	_burst_times.clear()
	for b: Dictionary in _emission.get("bursts", []):
		var start := maxf(0.0, float(b.time))
		var interval := maxf(0.0, float(b.get("interval", b.get("repeat_interval", 0.0))))
		var cycles := int(b.get("cycles", b.get("cycle_count", 1)))
		if cycles == 0: cycles = ceili((_duration - start) / interval) if interval > EPS else 1
		for i in range(cycles):
			var due := start + float(i) * interval
			if due >= _duration: break
			_burst_times.append({"time": due, "count": b.count, "probability": b.get("probability", 1.0)})
	_burst_times.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))

func _emit_credit(credit: float, rate: float, phase0: float, phase1: float, start: float, looping: bool, kind: String) -> float:
	if rate <= EPS: return credit
	var available := credit + rate * maxf(0.0, phase1 - phase0)
	var due := floori(available + EPS)
	for i in range(mini(due, _capacity_left())):
		var phase := minf(phase1, phase0 + maxf(0.0, (float(i + 1) - credit) / rate))
		if not looping and phase >= _duration - EPS: break
		_birth(phase / _duration, 0, 0, kind, start + phase)
	return maxf(0.0, available - float(due))

func trigger_sub(world_pos: Vector3, world_vel: Vector3, color: Color, size: Vector3, angle: Vector3, life: float, flags: int, parent_emitter: Node3D = null, parent_id: int = -1) -> void:
	if not bool(source.get("active", true)) or not _on(_emission): return
	var context := {"position": world_pos, "velocity": world_vel, "color": color, "size": size, "angle": angle, "life": life, "flags": flags}
	var delay := maxf(0.0, _scalar(_main, "start_delay", 0.0, _rng.randf()))
	if is_instance_valid(parent_emitter) and parent_id >= 0:
		var rate_curve: Dictionary = _emission.get("rate_over_time", {})
		var distance_curve: Dictionary = _emission.get("rate_over_distance", {})
		if _curve_can_emit(rate_curve) or _curve_can_emit(distance_curve):
			_sub_streams.append({"parent": parent_emitter, "id": parent_id, "age": -delay, "rate_roll": _rng.randf(),
				"distance_roll": _rng.randf(), "credit": 0.0, "context": context.duplicate()})
	for b in _burst_times:
		if _rng.randf() >= float(b.probability): continue
		var time_scale := maxf(EPS, life) / _duration if (flags & 16) != 0 else 1.0
		var phase := float(b.time) / _duration
		var count := _burst_count(b.count, phase)
		if count > 0: _pending_sub.append({"due": _time + delay + float(b.time) * time_scale, "phase": phase, "count": count, "context": context})
	_flush_sub()

func source_event_particle_id() -> int:
	return _event_particle_id

func tracked_particle(id: int) -> Dictionary:
	if not _live_by_id.has(id): return {}
	var p: Dictionary = _live_by_id[id]
	return {"position": _sim_frame * Vector3(p.position + p.noise_offset), "velocity": _sim_frame.basis * Vector3(p.velocity),
		"color": p.color, "size": p.size, "angle": p.angle, "life": maxf(0.0, float(p.life) - float(p.age))}

func _burst_count(curve: Dictionary, phase: float) -> int:
	# Unity's Burst ranges select among inclusive integer endpoints, not
	# floor(lerp(min,max,roll)); e.g. 0..1 must actually emit a particle.
	if curve.get("mode") == "TwoConstants":
		var a := int(float(curve.min))
		var b := int(float(curve.max))
		return maxi(0, _rng.randi_range(mini(a, b), maxi(a, b)))
	return maxi(0, int(Math.curve(curve, phase, _rng.randf())))

func _curve_can_emit(curve: Dictionary) -> bool:
	match str(curve.get("mode", "")):
		"Constant": return float(curve.constant) > 0.0
		"TwoConstants": return maxf(float(curve.min), float(curve.max)) > 0.0
		"Curve", "TwoCurves": return not is_zero_approx(float(curve.multiplier))
	return false

func _tick_sub_streams(dt: float) -> void:
	if _sub_streams.is_empty(): return
	var current := _sub_streams
	_sub_streams = []
	for stream in current:
		if not is_instance_valid(stream.parent): continue
		var latest: Dictionary = stream.parent.call("tracked_particle", int(stream.id))
		if latest.is_empty(): continue
		var prior := float(stream.age)
		stream.age = prior + dt
		var context: Dictionary = stream.context
		var old_position: Vector3 = context.position
		var position: Vector3 = latest.position
		if float(stream.age) > 0.0:
			var phase := fposmod(float(stream.age), _duration) / _duration if bool(_main.get("loop", true)) else clampf(float(stream.age) / _duration, 0.0, 1.0)
			var portion := clampf(float(stream.age) / dt, 0.0, 1.0)
			if not bool(_main.get("loop", true)): portion = clampf((minf(float(stream.age), _duration) - maxf(prior, 0.0)) / dt, 0.0, 1.0)
			var rate := maxf(0.0, _scalar(_emission, "rate_over_time", phase, float(stream.rate_roll)))
			var distance_rate := maxf(0.0, _scalar(_emission, "rate_over_distance", phase, float(stream.distance_roll)))
			var amount := portion * (rate * dt + distance_rate * old_position.distance_to(position))
			var available := float(stream.credit) + amount
			var count := floori(available + EPS)
			for i in range(mini(count, _capacity_left())):
				var fraction := clampf((float(i + 1) - float(stream.credit)) / maxf(EPS, amount), 0.0, 1.0)
				var birth_context := latest.duplicate()
				birth_context["flags"] = context.flags
				birth_context.position = old_position.lerp(position, fraction)
				_birth(phase, 0, 0, "sub", _step_from + dt * fraction, birth_context)
			stream.credit = maxf(0.0, available - count)
		latest["flags"] = context.flags
		stream.context = latest
		if bool(_main.get("loop", true)) or float(stream.age) < _duration: _sub_streams.append(stream)

func _flush_sub() -> void:
	if _pending_sub.is_empty(): return
	var scheduled := _pending_sub
	_pending_sub = []
	for b in scheduled:
		if float(b.due) > _time + EPS:
			_pending_sub.append(b)
			continue
		for i in range(mini(int(b.count), _capacity_left())): _birth(float(b.phase), i, int(b.count), "sub", float(b.due), b.context)

func trigger_manual() -> void:
	if not _manual_events: return
	for p in _live: _event("Manual", p)

func _capacity_left() -> int:
	return maxi(0, int(_main.get("max_particles", 1000)) - _live.size())

func _birth(phase: float, ordinal: int, ordered_count: int, kind: String, due: float, context: Dictionary = {}) -> void:
	if _capacity_left() == 0: return
	var life := _scalar(_main, "start_lifetime", phase, _rng.randf(), 5.0)
	var flags := int(context.get("flags", 0))
	if (flags & 8) != 0: life *= maxf(0.0, float(context.life))
	if life <= EPS: return
	var sample := _sample_shape(ordinal, ordered_count, phase, due)
	var point: Vector3 = sample[0]
	var direction: Vector3 = sample[1]
	var spawn := _current_birth_frame
	if not _warming and _time > _step_from + EPS:
		spawn = _previous_birth_frame.interpolate_with(_current_birth_frame, clampf((due - _step_from) / (_time - _step_from), 0.0, 1.0))
	if not context.is_empty(): spawn.origin = context.position
	var visual := _visual_basis(spawn)
	var from_world := _sim_inverse.basis
	var spawn_dir := from_world * (visual * direction)
	var spawn_velocity := spawn_dir * _scalar(_main, "start_speed", phase, _rng.randf(), 5.0)
	var inherit_roll := _rng.randf()
	if _space != "Local" and _on(_inherit) and _inherit.get("mode", "Initial") == "Initial":
		var emitter_v: Vector3 = context.get("velocity", _emitter_world_velocity)
		spawn_velocity += from_world * emitter_v * _scalar(_inherit, "curve", phase, inherit_roll, 1.0)
	var initial_size := Vector3.ONE
	if bool(_main.get("start_size3d", _main.get("start_size_3d", false))):
		initial_size = _vector(_main, "start_size_", phase, _roll3(), 1.0)
	else: initial_size *= _scalar(_main, "start_size", phase, _rng.randf(), 1.0)
	var initial_angle := Vector3.ZERO
	if bool(_main.get("start_rotation3d", _main.get("start_rotation_3d", false))):
		initial_angle = _vector(_main, "start_rotation_", phase, _roll3())
	else: initial_angle.z = _scalar(_main, "start_rotation", phase, _rng.randf())
	if float(_main.get("flip_rotation", 0.0)) > 0.0 and _rng.randf() < float(_main.flip_rotation): initial_angle *= -1.0
	initial_angle = _particle_axes(initial_angle)
	if (flags & 4) != 0: initial_angle += Vector3(context.angle)
	var tint := Math.color_at(_main.get("start_color", {}), phase, _rng.randf())
	if (flags & 1) != 0: tint *= Color(context.color)
	if (flags & 2) != 0: initial_size *= Vector3(context.size)
	var trail_on := _on(_trail) and _rng.randf() < float(_trail.get("ratio", 1.0))
	var position := _sim_inverse * (spawn * point)
	var p := {"id": _serial, "age": 0.0, "life": life, "born": due, "spawn_phase": phase, "position": position, "velocity": spawn_velocity,
		"base_velocity": spawn_velocity, "spawn_position": position, "spawn_velocity": spawn_velocity, "angle": initial_angle,
		"initial_size": initial_size, "size": initial_size, "initial_color": tint, "color": tint, "visual": from_world * visual,
		"gravity_roll": _rng.randf(), "limit_roll": _rng.randf(), "velocity_roll": _roll3(), "orbital_roll": _roll3(), "offset_roll": _roll3(),
		"radial_roll": _rng.randf(), "speed_roll": _rng.randf(), "force_roll": _roll3(), "inherit_roll": inherit_roll,
		"size_roll": _roll3(), "rotation_roll": _roll3(), "spin_roll": _roll3(), "color_roll": _rng.randf(),
		"sheet_roll": _rng.randf(), "start_frame_roll": _rng.randf(), "row_roll": _rng.randf(), "frame": 0, "mesh_index": _pick_mesh(),
		"trail_enabled": trail_on, "trail_roll": _rng.randf(), "history": [],
		"noise_roll": _roll3(), "noise_seed": _roll3() * 100.0, "noise_offset": Vector3.ZERO, "noise_angle": Vector3.ZERO,
		"collision_roll": _roll3()}
	_serial += 1
	match kind:
		"burst": _emitted_burst += 1
		"distance": _emitted_distance += 1
		"sub": _emitted_sub += 1
		_: _emitted_rate += 1
	if _first_birth < 0.0: _first_birth = due
	if trail_on: _trail_births += 1
	_apply_lifetime(p, 0.0, 0.0)
	if trail_on: _trail_point(p, due)
	if _birth_events: _event("Birth", p)
	var remainder := maxf(0.0, _time - due)
	if remainder > EPS: _update_particle(p, remainder, due)
	if float(p.age) + EPS < life:
		_live.append(p)
		if _birth_events: _live_by_id[int(p.id)] = p
	else: _retire(p)

func _sample_shape(index: int, count: int, phase: float, due: float) -> Array:
	if not _on(_shape): return [Vector3.ZERO, Vector3.FORWARD]
	var kind := str(_shape.get("shape_type", _shape.get("type", "Sphere")))
	var unit := _shape_parameter("arc", index, count, phase, due)
	var theta := deg_to_rad(float(_shape.get("arc", 360.0))) * unit
	var radial := Vector3(cos(theta), sin(theta), 0.0)
	var radius := maxf(0.0, float(_shape.get("radius", 1.0)))
	var lower := 1.0 - clampf(float(_shape.get("radius_thickness", 1.0)), 0.0, 1.0)
	var sample := _shape_parameter("radius", index, count, phase, due)
	var point := Vector3.ZERO
	var direction := Vector3.BACK
	match kind:
		"Sphere", "SphereShell", "Hemisphere", "HemisphereShell":
			var z := _rng.randf() if kind.begins_with("Hemisphere") else _rng.randf_range(-1.0, 1.0)
			direction = radial * sqrt(maxf(0.0, 1.0 - z * z)) + Vector3.BACK * z
			point = direction * radius * (1.0 if kind.ends_with("Shell") else pow(lerpf(lower * lower * lower, 1.0, sample), 1.0 / 3.0))
		"Circle", "CircleEdge":
			direction = radial
			point = radial * radius * (1.0 if kind == "CircleEdge" else sqrt(lerpf(lower * lower, 1.0, sample)))
		"Cone", "ConeShell", "ConeVolume", "ConeVolumeShell":
			var weight := 1.0 if kind.ends_with("Shell") else sqrt(lerpf(lower * lower, 1.0, sample))
			var slope := tan(deg_to_rad(clampf(float(_shape.get("angle", 0.0)), 0.0, 89.99)))
			direction = (Vector3.BACK + radial * slope * weight).normalized()
			var depth := 0.0
			if kind.begins_with("ConeVolume"):
				var length := maxf(0.0, float(_shape.get("length", 0.0)))
				if slope > EPS and length > EPS:
					var outer := radius + slope * length
					depth = (pow(lerpf(radius * radius * radius, outer * outer * outer, _rng.randf()), 1.0 / 3.0) - radius) / slope
				else: depth = length * _rng.randf()
			point = radial * (radius + depth * slope) * weight + Vector3.BACK * depth
		"Box", "BoxShell", "BoxEdge", "Rectangle":
			point = _roll3() - Vector3.ONE * 0.5
			if kind == "Rectangle": point.z = 0.0
			if kind == "BoxShell" or kind == "BoxEdge":
				var axis := _rng.randi_range(0, 2)
				var thickness := _vec(_shape.get("box_thickness", []), Vector3.ZERO).clamp(Vector3.ZERO, Vector3.ONE)
				point[axis] = signf(point[axis]) * (0.5 - _rng.randf() * thickness[axis] * 0.5)
				if kind == "BoxEdge":
					axis = (axis + _rng.randi_range(1, 2)) % 3
					point[axis] = signf(point[axis]) * (0.5 - _rng.randf() * thickness[axis] * 0.5)
		"SingleSidedEdge", "Edge":
			point.x = lerpf(-radius, radius, sample)
	var basis := Basis.from_euler(_vec(_shape.get("rotation", []), Vector3.ZERO) * (PI / 180.0), EULER_ORDER_YXZ)
	var offset := basis * (point * _vec(_shape.get("scale", []), Vector3.ONE))
	direction = (basis * direction).normalized()
	var spherical := clampf(float(_shape.get("spherical_direction_amount", 0.0)), 0.0, 1.0)
	if spherical > EPS and not offset.is_zero_approx(): direction = direction.lerp(offset.normalized(), spherical).normalized()
	var random_direction := clampf(float(_shape.get("random_direction_amount", 0.0)), 0.0, 1.0)
	if random_direction > EPS: direction = direction.lerp(_random_unit(), random_direction).normalized()
	var random_position := maxf(0.0, float(_shape.get("random_position_amount", 0.0)))
	if random_position > EPS: offset += (_roll3() * 2.0 - Vector3.ONE) * random_position
	return [Math.polar(offset + _vec(_shape.get("position", []), Vector3.ZERO)), Math.polar(direction)]

func _shape_parameter(prefix: String, index: int, count: int, phase: float, due: float) -> float:
	var unit := _rng.randf()
	var mode := str(_shape.get(prefix + "_mode", "Random"))
	var speed := _scalar(_shape, prefix + "_speed", phase, 0.5, 1.0)
	match mode:
		"BurstSpread":
			if count > 0: unit = float(index) / float(count)
		"Loop": unit = fposmod(maxf(0.0, due - _start) * speed, 1.0)
		"PingPong": unit = pingpong(maxf(0.0, due - _start) * speed, 1.0)
	var spread := clampf(float(_shape.get(prefix + "_spread", 0.0)), 0.0, 1.0)
	if spread > EPS: unit = floorf(unit / spread + EPS) * spread
	return unit

func _random_unit() -> Vector3:
	var z := _rng.randf_range(-1.0, 1.0)
	var theta := _rng.randf_range(0.0, TAU)
	var r := sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(cos(theta) * r, sin(theta) * r, z)

func _update_particle(p: Dictionary, dt: float, tick_start: float) -> void:
	dt = minf(dt, maxf(0.0, float(p.life) - float(p.age)))
	if dt <= EPS: return
	p.age = float(p.age) + dt
	var age := clampf(float(p.age) / float(p.life), 0.0, 1.0)
	var acceleration := _sim_inverse.basis * _world_gravity * _scalar(_main, "gravity_modifier", age, float(p.gravity_roll))
	if _on(_force):
		var roll: Vector3 = _roll3() if bool(_force.get("randomized", false)) else p.force_roll
		acceleration += _module_basis(_force) * Math.polar(_vector(_force, "", age, roll))
	var base: Vector3 = p.base_velocity + acceleration * dt
	var additive := Vector3.ZERO
	var modifier := 1.0
	if _on(_velocity):
		var axes := _module_basis(_velocity)
		additive += axes * Math.polar(_vector(_velocity, "", age, p.velocity_roll))
		var orbital := Math.axial(_vector(_velocity, "orbital_", age, p.orbital_roll))
		var offset := Math.polar(_vector(_velocity, "orbital_offset_", age, p.offset_roll))
		var radial := _scalar(_velocity, "radial", age, float(p.radial_roll))
		if (not orbital.is_zero_approx() or absf(radial) > EPS) and absf(axes.determinant()) > EPS:
			var pivot := _sim_inverse * _current_birth_frame.origin
			var relative: Vector3 = axes.inverse() * (p.position - pivot) - offset
			var orbit_delta := Basis.from_euler(orbital * dt, EULER_ORDER_YXZ) * relative - relative
			additive += axes * (orbit_delta / dt + relative.normalized() * radial)
		modifier = _scalar(_velocity, "speed_modifier", age, float(p.speed_roll), 1.0)
	if _space != "Local" and _on(_inherit) and _inherit.get("mode", "Initial") == "Current":
		additive += _sim_inverse.basis * _emitter_world_velocity * _scalar(_inherit, "curve", age, float(p.inherit_roll), 1.0)
	var motion := (base + additive) * modifier
	if _on(_limit):
		var limited := _limited_velocity(p, motion, age, dt)
		if absf(modifier) > EPS: base += (limited - motion) / modifier
		motion = limited
	var delta := motion * dt
	if _on(_collision) and is_inside_tree():
		var result := _collide(p, motion, dt, age)
		delta = result[0]
		var outgoing: Vector3 = result[1]
		if absf(modifier) > EPS: base += (outgoing - motion) / modifier
		motion = outgoing
	p.position += delta
	p.velocity = motion
	p.base_velocity = base
	_apply_lifetime(p, clampf(float(p.age) / float(p.life), 0.0, 1.0), dt)
	if bool(p.trail_enabled): _trail_point(p, tick_start + dt)

func _limited_velocity(p: Dictionary, motion: Vector3, age: float, dt: float) -> Vector3:
	var roll := float(p.limit_roll)
	var weight := float(_limit.get("dampen", 0.0))
	if bool(_limit.get("separate_axes", false)):
		var axes := _module_basis(_limit)
		var limits := _vector(_limit, "limit_", age, Vector3.ONE * roll).abs()
		var components := axes.inverse() * motion
		for i in range(3):
			components[i] = Math.limit_speed(Vector3(components[i], 0.0, 0.0), limits[i], weight, dt).x
		motion = axes * components
	else:
		motion = Math.limit_speed(motion, maxf(0.0, _scalar(_limit, "limit", age, roll)), weight, dt)
	var drag := _scalar(_limit, "drag", age, roll)
	if drag > 0.0:
		if bool(_limit.get("multiply_drag_by_particle_size", false)): drag *= absf(float(p.size.x))
		if bool(_limit.get("multiply_drag_by_particle_velocity", false)): drag *= motion.length()
		motion *= exp(-drag * dt)
	return motion

func _apply_lifetime(p: Dictionary, age: float, dt: float) -> void:
	var sized: Vector3 = p.initial_size
	if _on(_size):
		if bool(_size.get("separate_axes", false)): sized *= _vector(_size, "", age, p.size_roll, 1.0)
		else: sized *= _scalar(_size, "size", age, float(p.size_roll.x), 1.0)
	p.size = sized
	var tint: Color = p.initial_color
	if _on(_color): tint *= Math.color_at(_color.get("color", {}), age, float(p.color_roll))
	p.color = tint
	var speed := (_sim_frame.basis * Vector3(p.velocity)).length()
	if dt > 0.0:
		var turn := Vector3.ZERO
		if _on(_rotation): turn += _angular_rate(_rotation, age, p.rotation_roll)
		if _on(_spin): turn += _angular_rate(_spin, _range01(_spin.get("range", [0.0, 1.0]), speed), p.spin_roll)
		p.angle += _particle_axes(turn) * dt
	p.frame = _sheet_slot(p, age, speed)
	if _field != null: _apply_noise(p, age)

func _angular_rate(module: Dictionary, input: float, roll: Vector3) -> Vector3:
	if bool(module.get("separate_axes", false)): return _vector(module, "", input, roll)
	return Vector3(0.0, 0.0, _scalar(module, "z", input, roll.z))

func _sheet_slot(p: Dictionary, age: float, speed: float) -> int:
	if not _on(_sheet): return 0
	var tiles: Array = _sheet.get("tiles", [_sheet.get("num_tiles_x", 1), _sheet.get("num_tiles_y", 1)])
	var columns := maxi(1, int(tiles[0]))
	var rows := maxi(1, int(tiles[1]))
	var single: bool = _sheet.get("animation", "WholeSheet") == "SingleRow"
	var count := columns if single else columns * rows
	var start := _scalar(_sheet, "start_frame", 0.0, float(p.start_frame_roll)) * count
	var frame := start
	var time := age
	match str(_sheet.get("time_mode", "Lifetime")):
		"FPS": frame += float(p.age) * maxf(0.0, float(_sheet.get("fps", 30.0)))
		"Speed": time = _range01(_sheet.get("speed_range", [0.0, 1.0]), speed)
	if _sheet.get("time_mode", "Lifetime") != "FPS":
		frame += _scalar(_sheet, "frame_over_time", time, float(p.sheet_roll)) * float(_sheet.get("cycles", _sheet.get("cycle_count", 1))) * count
	var row := 0
	if single:
		match str(_sheet.get("row_mode", "Custom")):
			"Random": row = mini(rows - 1, floori(float(p.row_roll) * rows))
			"MeshIndex": row = posmod(int(p.mesh_index), rows)
			_: row = clampi(int(_sheet.get("row_index", 0)), 0, rows - 1)
	return row * columns + posmod(floori(frame + 0.0000001), count)

func _apply_noise(p: Dictionary, age: float) -> void:
	var elapsed := float(p.age)
	var coord: Vector3 = p.noise_seed + p.position + Vector3.ONE * elapsed * _scalar(_noise, "scroll_speed", age, 0.5)
	var wave := Vector3(_field.get_noise_3dv(coord), _field.get_noise_3dv(coord + Vector3(11.2, 23.3, 37.4)), _field.get_noise_3dv(coord + Vector3(43.7, 67.2, 89.9)))
	var split := bool(_noise.get("separate_axes", false))
	var roll: Vector3 = p.noise_roll
	if bool(_noise.get("remap_enabled", false)):
		for i in range(3):
			var key := ["remap_x", "remap_y", "remap_z"][i] as String if split else "remap"
			wave[i] = _scalar(_noise, key, clampf(wave[i] * 0.5 + 0.5, 0.0, 1.0), roll[i], wave[i])
	var strength := _vector(_noise, "strength_", age, roll) if split else Vector3.ONE * _scalar(_noise, "strength", age, roll.x)
	if not bool(_noise.get("damping", true)): strength *= maxf(float(_noise.get("frequency", 0.5)), EPS)
	var amount := wave * strength
	p.noise_offset = amount * _scalar(_noise, "position_amount", age, 0.5, 1.0)
	p.noise_angle = amount * _scalar(_noise, "rotation_amount", age, 0.5)
	p.size *= maxf(0.0, 1.0 + amount.x * _scalar(_noise, "size_amount", age, 0.5))
	_noise_samples += 1

func _collide(p: Dictionary, velocity: Vector3, dt: float, age: float) -> Array:
	var world_velocity := _sim_frame.basis * velocity
	var motion := world_velocity * dt
	if motion.length_squared() <= 1.0e-12: return [velocity * dt, velocity]
	var start: Vector3 = _sim_frame * p.position
	var visual: Basis = _sim_frame.basis * p.visual
	var size: Vector3 = (_axis_lengths(visual) * p.size).abs()
	var radius := maxf(0.0001, maxf(size.x, maxf(size.y, size.z)) * float(_collision.get("radius_scale", 1.0)) * 0.5)
	var hit: Dictionary = {}
	if _collision.get("type", "World") == "Planes":
		for plane in collision_planes:
			if not is_instance_valid(plane): continue
			var normal := plane.global_basis.y.normalized()
			var travel := motion.dot(normal)
			if travel >= -EPS: continue
			var distance := (start - plane.global_position).dot(normal)
			if distance < -radius: continue
			var fraction := maxf(0.0, (radius - distance) / travel)
			if fraction <= 1.0 and fraction < float(hit.get("fraction", INF)):
				hit = {"fraction": fraction, "normal": normal}
	elif _collision.get("mode", "Collision3D") == "Collision2D":
		hit = CanvasCollision.hit(self, start, motion, radius, int(_collision.get("collides_with", -1)), bool(_collision.get("enable_dynamic_colliders", true)))
	elif _sweep != null:
		var space := get_world_3d().direct_space_state
		if space != null: hit = _world_hit(space, start, motion, radius)
	if hit.is_empty(): return [velocity * dt, velocity]
	var normal: Vector3 = hit.normal
	if world_velocity.dot(normal) >= 0.0: return [velocity * dt, velocity]
	_collision_hits += 1
	var fraction := float(hit.fraction)
	var roll: Vector3 = p.collision_roll
	var outgoing := Math.collision_velocity(world_velocity, normal, clampf(_scalar(_collision, "dampen", age, roll.x), 0.0, 1.0), clampf(_scalar(_collision, "bounce", age, roll.y), 0.0, 1.0))
	p.age += float(p.life) * clampf(_scalar(_collision, "lifetime_loss", age, roll.z), 0.0, 1.0)
	var speed := outgoing.length()
	if speed < float(_collision.get("min_kill_speed", 0.0)) or speed > float(_collision.get("max_kill_speed", INF)): p.age = p.life
	if _collision_events:
		_emit_event("Collision", p, start + motion * fraction - normal * radius, outgoing)
	var tail := outgoing * dt * (1.0 - fraction) if float(p.age) + EPS < float(p.life) else Vector3.ZERO
	return [_sim_inverse.basis * (motion * fraction + normal * 0.00012 + tail), _sim_inverse.basis * outgoing]

func _world_hit(space: PhysicsDirectSpaceState3D, start: Vector3, motion: Vector3, radius: float) -> Dictionary:
	_sphere.radius = radius
	var exclude: Array[RID] = []
	var dynamic := bool(_collision.get("enable_dynamic_colliders", true))
	var nudge := minf(0.00012, radius * 0.2)
	var forward := motion.normalized()
	var attempts := 1 if dynamic else maxi(1, int(_collision.get("max_collision_shapes", 256)))
	for i in range(attempts):
		_sweep.exclude = exclude
		_sweep.transform = Transform3D(Basis.IDENTITY, start)
		_sweep.motion = motion
		var fractions := space.cast_motion(_sweep)
		if fractions.size() != 2 or (fractions[0] >= 1.0 and fractions[1] >= 1.0): return {}
		_sweep.transform.origin = start + motion * float(fractions[1]) + forward * nudge
		_sweep.motion = Vector3.ZERO
		var info := space.get_rest_info(_sweep)
		if info.is_empty():
			var ray := PhysicsRayQueryParameters3D.create(start, start + motion + forward * radius, _sweep.collision_mask, exclude)
			info = space.intersect_ray(ray)
		if info.is_empty(): return {}
		if not dynamic:
			var collider := instance_from_id(int(info.get("collider_id", 0)))
			if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D:
				exclude.append(info.rid)
				continue
		return {"fraction": fractions[0], "normal": info.normal}
	return {}

func _trail_point(p: Dictionary, now: float) -> void:
	var history: Array = p.history
	_trim_trail(p, now)
	var at: Vector3 = p.position + p.noise_offset
	if bool(_trail.get("world_space", false)): at = _sim_frame * at
	if history.is_empty() or at.distance_to(history[-1].position) >= maxf(EPS, float(_trail.get("min_vertex_distance", 0.1))):
		history.append({"position": at, "time": now, "size": absf(float(p.size.x)), "color": p.color})

func _trim_trail(p: Dictionary, now: float) -> void:
	var history: Array = p.history
	var keep := maxf(0.0, _scalar(_trail, "lifetime", clampf(float(p.age) / float(p.life), 0.0, 1.0), float(p.trail_roll), 1.0))
	if bool(_trail.get("size_affects_lifetime", false)): keep *= absf(float(p.size.x))
	while not history.is_empty() and now - float(history[0].time) > keep + EPS: history.pop_front()

func _retire(p: Dictionary) -> void:
	_live_by_id.erase(int(p.id))
	if _death_events: _event("Death", p)
	if bool(p.trail_enabled) and not bool(_trail.get("die_with_particles", true)) and p.history.size() >= 2:
		_lingering.append(p)

func _trail_points(p: Dictionary, draw_inverse: Transform3D) -> Array:
	var points: Array = []
	var history: Array = p.history
	if history.size() < 2: return points
	var age := clampf(float(p.age) / float(p.life), 0.0, 1.0)
	var roll := float(p.trail_roll)
	var by_age := Math.color_at(_trail.get("color_over_lifetime", {}), age, roll)
	var conversion := draw_inverse if bool(_trail.get("world_space", false)) else draw_inverse * _sim_frame
	for i in range(history.size()):
		var q: Dictionary = history[i]
		var along := 1.0 - float(i) / float(history.size() - 1)
		var width := maxf(0.0, _scalar(_trail, "width_over_trail", along, roll, 1.0))
		if bool(_trail.get("size_affects_width", true)): width *= float(q.size)
		var tint := Math.color_at(_trail.get("color_over_trail", {}), along, roll) * by_age
		if bool(_trail.get("inherit_particle_color", true)): tint *= q.color
		points.append({"position": conversion * Vector3(q.position), "time": q.time, "width": width, "color": tint})
	return points

func sync_draw() -> void:
	_refresh_sim_frame()
	var anchor := _node_transform(self)
	if absf(anchor.basis.determinant()) <= 1.0e-18:
		_drawer.clear()
		return
	var inverse := anchor.affine_inverse()
	var to_draw := inverse * _sim_frame
	var draw_items: Array = []
	var ribbon_mode: bool = _trail.get("mode", "PerParticle") == "Ribbon"
	for p in _live:
		var visual: Basis = to_draw.basis * p.visual
		var angle: Vector3 = p.angle + p.noise_angle
		var size: Vector3 = p.size
		var particle_basis := visual * Basis.from_euler(angle, EULER_ORDER_YXZ) * Basis.from_scale(size)
		draw_items.append({"id": p.id, "age": p.age, "born": p.born, "position": to_draw * Vector3(p.position + p.noise_offset),
			"velocity": to_draw.basis * Vector3(p.velocity), "size": size * _axis_lengths(visual), "angle": angle,
			"basis_override": particle_basis, "color": p.color, "frame": p.frame, "mesh_slot": p.mesh_index,
			"trail": [] if ribbon_mode else _trail_points(p, inverse)})
	if ribbon_mode:
		_append_ribbons(draw_items, to_draw)
	else:
		for p in _lingering:
			draw_items.append({"trail_only": true, "trail": _trail_points(p, inverse)})
	_drawer.sync(draw_items, _time)

func _append_ribbons(draw_items: Array, to_draw: Transform3D) -> void:
	var count := clampi(int(_trail.get("ribbon_count", 1)), 1, maxi(1, _live.size()))
	var ribbons: Array[Array] = []
	for i in range(count): ribbons.append([])
	for p in _live:
		if bool(p.trail_enabled): ribbons[posmod(int(p.id), count)].append(p)
	for ribbon in ribbons:
		var points: Array = []
		if ribbon.size() < 2: continue
		for i in range(ribbon.size()):
			var p: Dictionary = ribbon[i]
			var age := clampf(float(p.age) / float(p.life), 0.0, 1.0)
			var along := 1.0 - float(i) / float(ribbon.size() - 1)
			var roll := float(p.trail_roll)
			var width := maxf(0.0, _scalar(_trail, "width_over_trail", along, roll, 1.0))
			if bool(_trail.get("size_affects_width", true)): width *= absf(float(p.size.x))
			var tint := Math.color_at(_trail.get("color_over_trail", {}), along, roll) * Math.color_at(_trail.get("color_over_lifetime", {}), age, roll)
			if bool(_trail.get("inherit_particle_color", true)): tint *= p.color
			points.append({"position": to_draw * Vector3(p.position + p.noise_offset), "time": p.born, "width": width, "color": tint})
		draw_items.append({"trail_only": true, "trail": points})

func _event(kind: String, p: Dictionary) -> void:
	_emit_event(kind, p, _sim_frame * Vector3(p.position + p.noise_offset), _sim_frame.basis * Vector3(p.velocity))

func _emit_event(kind: String, p: Dictionary, world_pos: Vector3, world_vel: Vector3) -> void:
	var lifetime := maxf(0.0, float(p.life) - float(p.age))
	var previous_id := _event_particle_id
	_event_particle_id = int(p.id)
	source_event.emit(self, kind, world_pos, world_vel, p.color, p.size, p.angle, lifetime)
	_event_particle_id = previous_id

func _has_sub_type(kind: String) -> bool:
	if not _on(_sub): return false
	for row: Dictionary in _sub.get("entries", []):
		if str(row.get("type", "")).nocasecmp_to(kind) == 0: return true
	return false

func _refresh_sim_frame() -> void:
	_sim_frame = Transform3D.IDENTITY
	if _space == "Local": _sim_frame = _visual_frame(_node_transform(self))
	elif _space == "Custom" and is_instance_valid(custom_simulation_node): _sim_frame = _node_transform(custom_simulation_node)
	if absf(_sim_frame.basis.determinant()) <= 1.0e-18: _sim_frame.basis = _rotation_basis(_sim_frame.basis)
	_sim_inverse = _sim_frame.affine_inverse()

func _birth_frame() -> Transform3D:
	var current := _node_transform(self)
	if _scaling == "Local": return _visual_frame(current)
	return current

func _visual_frame(frame: Transform3D) -> Transform3D:
	return Transform3D(_visual_basis(frame), frame.origin)

func _visual_basis(frame: Transform3D) -> Basis:
	match _scaling:
		"Local":
			var host := get_parent_node_3d()
			var authored_scale := host.scale * scale if host != null and host.has_meta("unity_node_key") else scale
			return _rotation_basis(frame.basis) * Basis.from_scale(authored_scale)
		"Shape": return _rotation_basis(frame.basis)
	return frame.basis

func _module_basis(module: Dictionary) -> Basis:
	if module.get("space", "Local") == "World": return _sim_inverse.basis
	return _sim_inverse.basis * _visual_basis(_current_birth_frame)

func _node_transform(node: Node3D) -> Transform3D:
	return node.global_transform if node.is_inside_tree() else node.transform

func _rotation_basis(basis: Basis) -> Basis:
	if absf(basis.determinant()) <= 1.0e-18: return Basis.IDENTITY
	var rotation := basis.orthonormalized()
	return rotation.scaled(-Vector3.ONE) if rotation.determinant() < 0.0 else rotation

func _axis_lengths(basis: Basis) -> Vector3:
	return Vector3(basis.x.length(), basis.y.length(), basis.z.length())

func _particle_axes(unity_angles: Vector3) -> Vector3:
	var reflected := Math.axial(unity_angles)
	return reflected if _mesh_mode else -reflected

func _pick_mesh() -> int:
	if _mesh_count == 0: return 0
	if _mesh_count == 1: return _mesh_indices[0]
	var total := 0.0
	for weight in _mesh_weights: total += weight
	if total > EPS:
		var draw := _rng.randf() * total
		for i in range(_mesh_count):
			if _mesh_weights[i] <= 0.0: continue
			draw -= _mesh_weights[i]
			if draw <= 0.0: return _mesh_indices[i]
	return _mesh_indices[_rng.randi_range(0, _mesh_count - 1)]

func _on(module: Dictionary) -> bool:
	return bool(module.get("enabled", false))

func _roll3() -> Vector3:
	return Vector3(_rng.randf(), _rng.randf(), _rng.randf())

func _scalar(module: Dictionary, key: String, time: float, roll: float, fallback: float = 0.0) -> float:
	return Math.curve(module.get(key, {}), time, roll, fallback)

func _vector(module: Dictionary, prefix: String, time: float, roll: Vector3, fallback: float = 0.0) -> Vector3:
	return Vector3(_scalar(module, prefix + "x", time, roll.x, fallback), _scalar(module, prefix + "y", time, roll.y, fallback), _scalar(module, prefix + "z", time, roll.z, fallback))

func _vec(value: Array, fallback: Vector3) -> Vector3:
	return Math.vec(value) if value.size() >= 3 else fallback

func _range01(limits: Array, speed: float) -> float:
	var from := float(limits[0])
	var to := float(limits[1])
	return clampf(inverse_lerp(from, to, speed), 0.0, 1.0) if absf(to - from) > EPS else 0.0

func debug_state(include_particles: bool = false) -> Dictionary:
	var draw := _drawer.debug_state()
	var out := {"emitting": _enabled, "local_space": _space, "scaling_mode": _scaling, "delay": _start,
		"loop": bool(_main.get("loop", true)), "play_on_awake": plays_on_awake(),
		"gravity": _world_gravity * _scalar(_main, "gravity_modifier", 0.0, 0.5), "elapsed": _time, "first_birth": _first_birth,
		"rate_births": _emitted_rate, "burst_births": _emitted_burst, "distance_births": _emitted_distance, "sub_births": _emitted_sub,
		"live": _live.size(), "collision_hits": _collision_hits, "noise_samples": _noise_samples, "trail_births": _trail_births,
		"lingering_trails": _lingering.size(), "trail_segments": draw.get("trail_segments", 0), "drawn": draw.get("visible_count", 0),
		"gpu_frame_slots": draw.get("frame_slots", []), "emitter_velocity": _emitter_world_velocity,
		"render_limitations": draw.get("limitations", []), "render_materials": draw.get("material_slots", [])}
	if include_particles:
		var copied := _live.duplicate(true)
		for p: Dictionary in copied:
			p["world_position"] = _sim_frame * Vector3(p.position + p.noise_offset)
			p["world_velocity"] = _sim_frame.basis * Vector3(p.velocity)
		out["particles"] = copied
	return out
