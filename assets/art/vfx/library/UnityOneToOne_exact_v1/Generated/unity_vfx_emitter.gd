extends Node3D
## One Unity particle system. Particle positions and velocities are stored in the
## emitter's local space. Gravity and collision are evaluated in world space.

const Math := preload("unity_vfx_math.gd")
const Draw := preload("unity_vfx_draw.gd")
const EPS := 0.000001

@export var source: Dictionary = {}
@export var source_mesh: Mesh
@export var main_texture: Texture2D
@export var trail_texture: Texture2D

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
var _world_gravity: Vector3
var _rng := RandomNumberGenerator.new()
var _drawer := Draw.new()
var _field: FastNoiseLite
var _sweep: PhysicsShapeQueryParameters3D
var _sphere: SphereShape3D
var _live: Array[Dictionary] = []
var _enabled := false
var _time := 0.0
var _start := 0.0
var _rate_credit := 0.0
var _rate_roll := 0.0
var _cycle := -1
var _burst_times: Array[Dictionary] = []
var _next_burst := 0
var _serial := 0
var _emitted_rate := 0
var _emitted_burst := 0
var _collision_hits := 0
var _noise_samples := 0
var _trail_births := 0
var _first_birth := -1.0
var _base_rotation: Quaternion
var _base_scale: Vector3
var _mesh_angles := false

func prepare(project_gravity: Vector3) -> void:
	_main = source.main
	_emission = source.emission
	_shape = source.shape
	_sheet = source.sheet
	_limit = source.limit_velocity
	_size = source.size_over_lifetime
	_color = source.color_over_lifetime
	_rotation = source.rotation_over_lifetime
	_noise = source.noise
	_trail = source.trails
	_collision = source.collision
	_world_gravity = project_gravity
	_base_rotation = quaternion
	_base_scale = scale
	_mesh_angles = source.renderer.get("render_mode") == "Mesh"
	_drawer.setup(self, source, source_mesh, main_texture, trail_texture)
	if bool(_noise.enabled):
		_field = FastNoiseLite.new()
		_field.noise_type = FastNoiseLite.TYPE_PERLIN
		_field.frequency = float(_noise.frequency)
		_field.fractal_type = FastNoiseLite.FRACTAL_NONE if int(_noise.octave_count) <= 1 else FastNoiseLite.FRACTAL_FBM
		_field.fractal_octaves = int(_noise.octave_count)
		_field.fractal_gain = float(_noise.octave_multiplier)
		_field.fractal_lacunarity = float(_noise.octave_scale)
	if bool(_collision.enabled):
		_sphere = SphereShape3D.new()
		_sweep = PhysicsShapeQueryParameters3D.new()
		_sweep.shape = _sphere
		_sweep.collision_mask = int(_collision.collides_with) & 0xffffffff
		_sweep.collide_with_areas = false
		_sweep.collide_with_bodies = true

func begin(seed_value: int) -> void:
	_rng.seed = seed_value if bool(_main.random_seed_is_auto) else int(_main.random_seed)
	if _field != null: _field.seed = int(_rng.seed & 0x7fffffff)
	_enabled = bool(source.active) and bool(_emission.enabled)
	_time = 0.0
	_start = maxf(0.0, Math.curve(_main.start_delay, 0.0, _rng.randf()))
	_rate_credit = 0.0
	_rate_roll = _rng.randf()
	_cycle = -1
	_serial = 0
	_emitted_rate = 0
	_emitted_burst = 0
	_collision_hits = 0
	_noise_samples = 0
	_trail_births = 0
	_first_birth = -1.0
	_live.clear()
	quaternion = _base_rotation
	scale = _base_scale
	_drawer.clear()

func stop(clear_now: bool) -> void:
	_enabled = false
	if clear_now:
		_live.clear()
		_drawer.clear()

func work_pending() -> bool:
	return _enabled or not _live.is_empty()

func update_emitter_rotation(elapsed: float, unity_degrees_per_second: Vector3) -> void:
	var angles := Math.axial(unity_degrees_per_second) * deg_to_rad(elapsed)
	quaternion = _base_rotation * Basis.from_euler(angles, EULER_ORDER_YXZ).get_rotation_quaternion()
	scale = _base_scale

func advance(dt_real: float) -> void:
	if not work_pending(): return
	var dt := dt_real * float(_main.simulation_speed)
	var previous := _time
	_time += dt
	var frame := global_transform
	var inverse := frame.affine_inverse()
	var local_gravity := inverse.basis * _world_gravity
	var still_alive: Array[Dictionary] = []
	for p: Dictionary in _live:
		_update_particle(p, dt, frame, inverse, local_gravity)
		if float(p.age) + EPS < float(p.life): still_alive.append(p)
	_live = still_alive
	if _enabled: _emit_between(previous, _time)

func sync_draw() -> void:
	var draw_items: Array = []
	for p: Dictionary in _live:
		var item := {"position": p.position + p.noise_offset, "velocity": p.velocity, "size": p.size,
			"angle": p.angle + p.noise_angle, "color": p.color, "frame": p.frame, "trail": []}
		var history: Array = p.history
		if history.size() >= 2:
			var points: Array = []
			for i in range(history.size()):
				var q: Dictionary = history[i]
				var along := 1.0 - float(i) / float(history.size() - 1)
				var width := maxf(0.0, Math.curve(_trail.width_over_trail, along, float(p.trail_roll), 1.0))
				if bool(_trail.size_affects_width): width *= absf(float(q.size))
				var tint := Math.color_at(_trail.color_over_trail, along, float(p.trail_roll))
				tint *= Math.color_at(_trail.color_over_lifetime, float(p.age) / float(p.life), float(p.trail_roll))
				if bool(_trail.inherit_particle_color): tint *= q.color
				points.append({"position": q.position, "time": q.time, "width": width, "color": tint})
			item.trail = points
		draw_items.append(item)
	_drawer.sync(draw_items, _time)

func _emit_between(t0: float, t1: float) -> void:
	var until := t1 - _start
	if until <= EPS: return
	var duration := float(_main.duration)
	var cursor := maxf(0.0, t0 - _start)
	var looping := bool(_main.loop)
	if not looping: until = minf(until, duration)
	while cursor + EPS < until:
		var cycle := floori((cursor + EPS) / duration) if looping else 0
		var cycle_start := float(cycle) * duration
		var end := minf(until, cycle_start + duration)
		if cycle != _cycle: _setup_cycle(cycle)
		var phase0 := maxf(0.0, cursor - cycle_start)
		var phase1 := end - cycle_start
		while _next_burst < _burst_times.size():
			var b: Dictionary = _burst_times[_next_burst]
			if float(b.time) >= phase1 - EPS: break
			_next_burst += 1
			if float(b.time) + EPS < phase0 or _rng.randf() >= float(b.probability): continue
			var count := maxi(0, floori(Math.curve(b.count, float(b.time) / duration, _rng.randf())))
			for i in range(count): _birth(float(b.time) / duration, i, count, true, _start + cycle_start + float(b.time))
		var rate := maxf(0.0, Math.curve(_emission.rate_over_time, phase1 / duration, _rate_roll))
		var amount := rate * maxf(0.0, phase1 - phase0)
		var available := _rate_credit + amount
		var count_due := floori(available + EPS)
		for i in range(count_due):
			var phase := minf(phase1, phase0 + maxf(0.0, (float(i + 1) - _rate_credit) / maxf(rate, EPS)))
			# In a non-looping system a particle at the exact right edge is outside
			# the emission window (measured in Lightning, where 20/s × 0.25 is 4).
			if not looping and phase >= duration - EPS: break
			_birth(phase / duration, 0, 0, false, _start + cycle_start + phase)
		_rate_credit = maxf(0.0, available - float(count_due))
		cursor = end
	if not looping and t1 >= _start + duration - EPS: _enabled = false

func _setup_cycle(cycle: int) -> void:
	_cycle = cycle
	_next_burst = 0
	_burst_times.clear()
	for burst: Dictionary in _emission.bursts:
		for i in range(int(burst.cycles)):
			var due := float(burst.time) + float(i) * float(burst.interval)
			if due < float(_main.duration):
				_burst_times.append({"time": due, "count": burst.count, "probability": burst.probability})
	_burst_times.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))

func _birth(phase: float, ordinal: int, ordered_count: int, burst: bool, due: float) -> void:
	if _live.size() >= int(_main.max_particles): return
	var life := Math.curve(_main.start_lifetime, phase, _rng.randf())
	if life <= EPS: return
	var location := _sample_shape(ordinal, ordered_count)
	var direction: Vector3 = location[1]
	var speed := Math.curve(_main.start_speed, phase, _rng.randf())
	var initial_size := Vector3.ONE
	if bool(_main.start_size3_d):
		initial_size = Vector3(Math.curve(_main.start_size_x, phase, _rng.randf()), Math.curve(_main.start_size_y, phase, _rng.randf()), Math.curve(_main.start_size_z, phase, _rng.randf()))
	else:
		initial_size *= Math.curve(_main.start_size, phase, _rng.randf(), 1.0)
	var initial_angle := Vector3.ZERO
	if bool(_main.start_rotation3_d):
		initial_angle = Vector3(Math.curve(_main.start_rotation_x, phase, _rng.randf()), Math.curve(_main.start_rotation_y, phase, _rng.randf()), Math.curve(_main.start_rotation_z, phase, _rng.randf()))
	else: initial_angle.z = Math.curve(_main.start_rotation, phase, _rng.randf())
	if float(_main.flip_rotation) > 0.0 and _rng.randf() < float(_main.flip_rotation): initial_angle *= -1.0
	initial_angle = _particle_axes(initial_angle)
	var birth_color := Math.color_at(_main.start_color, phase, _rng.randf())
	var trail_roll := _rng.randf()
	var spawn_velocity := direction * speed
	var p := {"id": _serial, "age": 0.0, "life": life, "born": due, "spawn_phase": phase, "position": location[0], "velocity": spawn_velocity,
		"spawn_position": location[0], "spawn_velocity": spawn_velocity,
		"initial_size": initial_size, "initial_color": birth_color, "angle": initial_angle, "size": initial_size, "color": birth_color,
		"size_roll": Vector3(_rng.randf(), _rng.randf(), _rng.randf()), "rotation_roll": Vector3(_rng.randf(), _rng.randf(), _rng.randf()), "color_roll": _rng.randf(),
		"gravity_roll": _rng.randf(), "limit_roll": _rng.randf(), "sheet_roll": _rng.randf(), "start_frame_roll": _rng.randf(), "frame": 0,
		"trail_enabled": bool(_trail.enabled) and trail_roll < float(_trail.get("ratio", 0.0)), "trail_roll": _rng.randf(), "history": [],
		"noise_seed": Vector3(_rng.randf_range(0.0, 100.0), _rng.randf_range(0.0, 100.0), _rng.randf_range(0.0, 100.0)), "noise_offset": Vector3.ZERO, "noise_angle": Vector3.ZERO}
	_serial += 1
	if burst: _emitted_burst += 1
	else: _emitted_rate += 1
	if _first_birth < 0.0: _first_birth = due
	if p.trail_enabled: _trail_births += 1
	_apply_lifetime(p, 0.0, 0.0)
	if p.trail_enabled: _trail_point(p, due)
	# New particles emitted partway through a tick carry their proper fractional age.
	var remaining := maxf(0.0, _time - due)
	if remaining > EPS:
		var frame := global_transform
		var inverse := frame.affine_inverse()
		_update_particle(p, remaining, frame, inverse, inverse.basis * _world_gravity)
	if float(p.age) + EPS < life: _live.append(p)

func _sample_shape(index: int, count: int) -> Array:
	if not bool(_shape.enabled): return [Vector3.ZERO, Vector3.FORWARD]
	var unit := _rng.randf()
	if _shape.arc_mode == "BurstSpread" and count > 1: unit = float(index) / float(count)
	var theta := deg_to_rad(float(_shape.arc)) * unit
	var radial := Vector3(cos(theta), sin(theta), 0.0)
	var radius := float(_shape.radius)
	var inner := radius * (1.0 - float(_shape.radius_thickness))
	var direction := radial
	var point := radial
	match str(_shape.shape_type):
		"Sphere":
			var z := _rng.randf_range(-1.0, 1.0)
			var sphere_r := sqrt(maxf(0.0, 1.0 - z*z))
			direction = radial * sphere_r + Vector3.BACK * z
			point = direction * pow(lerpf(inner*inner*inner, radius*radius*radius, _rng.randf()), 1.0 / 3.0)
		"Circle":
			point *= sqrt(lerpf(inner*inner, radius*radius, _rng.randf()))
		"Cone", "ConeVolume":
			var weight := sqrt(lerpf(pow(1.0 - float(_shape.radius_thickness), 2), 1.0, _rng.randf()))
			direction = (Vector3.BACK + radial * (tan(deg_to_rad(float(_shape.angle))) * weight)).normalized()
			point *= radius * weight
			if str(_shape.shape_type) == "ConeVolume": point += direction * float(_shape.length) * _rng.randf()
	# Shape.euler uses Unity's documented Z → X → Y order.
	var shape_angles := Math.vec(_shape.rotation) * (PI / 180.0)
	var basis := Basis.from_euler(shape_angles, EULER_ORDER_YXZ)
	point = basis * (point * Math.vec(_shape.scale)) + Math.vec(_shape.position)
	direction = (basis * direction).normalized()
	if float(_shape.spherical_direction_amount) > 0.0 and not point.is_zero_approx():
		direction = direction.lerp(point.normalized(), float(_shape.spherical_direction_amount)).normalized()
	if float(_shape.random_direction_amount) > 0.0:
		direction = direction.lerp(_random_unit(), float(_shape.random_direction_amount)).normalized()
	if float(_shape.random_position_amount) > 0.0: point += _random_unit() * _rng.randf() * float(_shape.random_position_amount)
	return [Math.polar(point), Math.polar(direction)]

func _random_unit() -> Vector3:
	var z := _rng.randf_range(-1.0, 1.0)
	var theta := _rng.randf_range(0.0, TAU)
	var radial := sqrt(maxf(0.0, 1.0 - z*z))
	return Vector3(cos(theta) * radial, sin(theta) * radial, z)

func _update_particle(p: Dictionary, dt: float, world: Transform3D, inverse: Transform3D, local_gravity: Vector3) -> void:
	p.age = float(p.age) + dt
	var age := clampf(float(p.age) / float(p.life), 0.0, 1.0)
	var v: Vector3 = p.velocity
	v += local_gravity * Math.curve(_main.gravity_modifier, age, float(p.gravity_roll)) * dt
	if bool(_limit.enabled):
		var speed := Math.curve(_limit.limit, age, float(p.limit_roll))
		v = Math.limit_speed(v, maxf(0.0, speed), float(_limit.dampen), dt)
		var drag := Math.curve(_limit.drag, age, float(p.limit_roll))
		if drag > 0.0:
			if bool(_limit.multiply_drag_by_particle_size): drag *= absf(float(p.size.x))
			if bool(_limit.multiply_drag_by_particle_velocity): drag *= v.length()
			v *= exp(-drag * dt)
	var displacement := v * dt
	if _sweep != null:
		var outcome := _propagate_collision(p, world, inverse, v, dt, age)
		displacement = outcome[0]
		v = outcome[1]
	p.position += displacement
	p.velocity = v
	_apply_lifetime(p, clampf(float(p.age) / float(p.life), 0.0, 1.0), dt)
	if bool(p.trail_enabled): _trail_point(p, _time)

func _apply_lifetime(p: Dictionary, age: float, dt: float) -> void:
	var sized: Vector3 = p.initial_size
	if bool(_size.enabled):
		var seed: Vector3 = p.size_roll
		if bool(_size.separate_axes):
			sized *= Vector3(Math.curve(_size.x, age, seed.x, 1.0), Math.curve(_size.y, age, seed.y, 1.0), Math.curve(_size.z, age, seed.z, 1.0))
		else: sized *= Math.curve(_size.size, age, seed.x, 1.0)
	p.size = sized
	var color: Color = p.initial_color
	if bool(_color.enabled): color *= Math.color_at(_color.color, age, float(p.color_roll))
	p.color = color
	if bool(_rotation.enabled) and dt > 0.0:
		var seed: Vector3 = p.rotation_roll
		var rate := Vector3(0.0, 0.0, Math.curve(_rotation.z, age, seed.z))
		if bool(_rotation.separate_axes):
			rate.x = Math.curve(_rotation.x, age, seed.x)
			rate.y = Math.curve(_rotation.y, age, seed.y)
		p.angle += _particle_axes(rate) * dt
	p.frame = Math.sheet_slot(_sheet, age, float(p.sheet_roll), float(p.start_frame_roll))
	if _field != null:
		var coord: Vector3 = p.noise_seed + p.position + Vector3.ONE * float(p.age) * Math.curve(_noise.scroll_speed, age, 0.5)
		var amount := Math.curve(_noise.strength, age, float(p.limit_roll))
		var v := Vector3(_field.get_noise_3dv(coord), _field.get_noise_3dv(coord + Vector3(11.2, 23.3, 37.4)), _field.get_noise_3dv(coord + Vector3(43.7, 67.2, 89.9)))
		if not bool(_noise.damping): amount *= maxf(float(_noise.frequency), EPS)
		p.noise_offset = v * amount * Math.curve(_noise.position_amount, age, 0.5)
		p.noise_angle = v * amount * Math.curve(_noise.rotation_amount, age, 0.5)
		p.size *= maxf(0.0, 1.0 + v.x * amount * Math.curve(_noise.size_amount, age, 0.5))
		_noise_samples += 1

func _particle_axes(unity_angles: Vector3) -> Vector3:
	# BakeMesh: Mesh matrices use normal Unity Z-X-Y Euler angles (then
	# reflect Z into Godot); Billboard's positive roll turns clockwise.
	var reflected := Math.axial(unity_angles)
	return reflected if _mesh_angles else -reflected

func _trail_point(p: Dictionary, now: float) -> void:
	var trail: Array = p.history
	var keep := maxf(0.0, Math.curve(_trail.lifetime, float(p.age) / float(p.life), float(p.trail_roll)))
	if bool(_trail.size_affects_lifetime): keep *= absf(float(p.size.x))
	while not trail.is_empty() and now - float(trail[0].time) > keep + EPS: trail.pop_front()
	var at: Vector3 = p.position + p.noise_offset
	if trail.is_empty() or at.distance_to(trail[-1].position) >= float(_trail.min_vertex_distance):
		trail.append({"position": at, "time": now, "size": float(p.size.x), "color": p.color})

func _propagate_collision(p: Dictionary, world: Transform3D, inverse: Transform3D, v: Vector3, dt: float, age: float) -> Array:
	var space := get_world_3d().direct_space_state
	if space == null or v.length_squared() * dt * dt <= 1.0e-12: return [v * dt, v]
	var world_start: Vector3 = world * p.position
	var world_velocity := world.basis * v
	var motion := world_velocity * dt
	var size: Vector3 = (world.basis.get_scale() * p.size).abs()
	_sphere.radius = maxf(0.0001, maxf(size.x, maxf(size.y, size.z)) * float(_collision.radius_scale) * 0.5)
	_sweep.margin = 0.00005
	_sweep.transform = Transform3D(Basis.IDENTITY, world_start)
	_sweep.motion = motion
	var fractions := space.cast_motion(_sweep)
	if fractions.size() != 2 or (fractions[0] >= 1.0 and fractions[1] >= 1.0): return [v * dt, v]
	_sweep.transform.origin = world_start + motion * float(fractions[1]) + motion.normalized() * 0.00012
	_sweep.motion = Vector3.ZERO
	var info := space.get_rest_info(_sweep)
	if info.is_empty():
		var ray := PhysicsRayQueryParameters3D.create(world_start, world_start + motion + motion.normalized() * _sphere.radius, _sweep.collision_mask)
		info = space.intersect_ray(ray)
	if info.is_empty(): return [v * dt, v]
	var normal: Vector3 = info.normal
	if world_velocity.dot(normal) >= 0.0: return [v * dt, v]
	_collision_hits += 1
	var post := Math.collision_velocity(world_velocity, normal, Math.curve(_collision.dampen, age, 0.5), Math.curve(_collision.bounce, age, 0.5))
	p.age += float(p.life) * Math.curve(_collision.lifetime_loss, age, 0.5)
	var magnitude := post.length()
	if magnitude < float(_collision.min_kill_speed) or magnitude > float(_collision.max_kill_speed): p.age = p.life
	var safe := float(fractions[0])
	var displacement := motion * safe + normal * 0.00012 + post * dt * (1.0 - safe)
	return [inverse.basis * displacement, inverse.basis * post]

func debug_state(include_particles := false) -> Dictionary:
	var draw := _drawer.debug_state()
	var out := {"emitting": _enabled, "local_space": _main.simulation_space, "delay": _start, "loop": _main.loop,
		"gravity": _world_gravity * Math.curve(_main.gravity_modifier, 0.0, 0.5), "elapsed": _time, "first_birth": _first_birth,
		"rate_births": _emitted_rate, "burst_births": _emitted_burst, "live": _live.size(), "collision_hits": _collision_hits,
		"trail_births": _trail_births, "trail_segments": draw.trail_segments, "noise_samples": _noise_samples,
		"drawn": draw.visible_count, "gpu_frame_slots": draw.frame_slots}
	if include_particles: out["particles"] = _live.duplicate(true)
	return out
