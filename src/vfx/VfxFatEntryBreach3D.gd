class_name VfxFatEntryBreach3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## 纯视觉入场：只操纵自有家具副本，不查询或改变房间物件及物理世界。

const DURATION := 3.65
const BURST_TIME := 0.40
const PIECE_COUNT := 5
var _pieces: Array[Node3D] = []
var _bounds: Array[AABB] = []
var _states: Array[Dictionary] = []
var _particles: Array[GPUParticles3D] = []
var _seed := 20261116
var _floor_y := 0.0
var _distance := 4.0
var _burst_fired := false
var _layout := "radial"

@onready var _library_burst: Node3D = $LibraryBurst

func _enter_tree() -> void:
	LibraryVfxAdapter3D.prepare_visual($LibraryBurst, false)

func _ready() -> void:
	for index in PIECE_COUNT:
		var pivot := get_node("Furniture/Piece%d" % index) as Node3D
		var visual := pivot.get_node("Visual") as Node3D
		var bounds := _visual_bounds(pivot)
		visual.position -= bounds.get_center()
		bounds.position -= bounds.get_center()
		for mesh in pivot.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pieces.append(pivot)
		_bounds.append(bounds)
	for node in find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		particles.process_material = particles.process_material.duplicate()
		_particles.append(particles)
		particles.emitting = false

func _visual_bounds(pivot: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var relative := pivot.global_transform.affine_inverse() * mesh.global_transform
		var transformed: AABB = relative * mesh.get_aabb()
		result = transformed if first else result.merge(transformed)
		first = false
	return result

func _on_activate(world_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = DURATION
	_follow = null
	_seed = int(context.get("seed", 20261116))
	_floor_y = float(context.get("floor_y", world_pos.y))
	_distance = maxf(0.0, float(context.get("landing_distance_m", 4.0)))
	_layout = str(context.get("layout", "radial"))
	var forward: Vector3 = context.get("forward", Vector3.FORWARD)
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	global_basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	global_position = Vector3(world_pos.x, _floor_y, world_pos.z)
	_burst_fired = false
	_states.clear()
	for index in _particles.size():
		var particles := _particles[index]
		particles.visible = true
		particles.use_fixed_seed = true
		particles.seed = 1 + int(_hash01(index, 90) * 2147483000.0)
		particles.emitting = false
		particles.restart(true)
		particles.emitting = false
		var material := particles.process_material as ParticleProcessMaterial
		material.scale_min = float(particles.get_meta("scale_min")) * effect_size
		material.scale_max = float(particles.get_meta("scale_max")) * effect_size
		material.initial_velocity_min = float(particles.get_meta("speed_min")) * effect_size
		material.initial_velocity_max = float(particles.get_meta("speed_max")) * effect_size
		material.gravity = Vector3(0, float(particles.get_meta("gravity_y")) * effect_size, 0)
		material.color = effect_color
		material.color.a *= float(particles.get_meta("opacity", 1.0))
	for index in PIECE_COUNT:
		# 固定五角间隔，桌柜长轴沿径向；seed只改变飞行，不破坏初始净空。
		var angle := TAU * float(index) / PIECE_COUNT
		var direction := Vector3(sin(angle), 0, -cos(angle))
		var start_radius := minf(1.56 * effect_size, _distance * 0.48)
		var push_radius := minf(start_radius + 0.16 * effect_size, _distance * 0.68)
		# Host给可用上限而非必须飞满；收紧最大扫掠，最低3.5m仍保留爆后至少1.5m。
		var end_radius := minf(_distance * lerpf(0.92, 1.0, _hash01(index, 2)), 3.25 * effect_size)
		_states.append({
			"direction": direction, "start": direction * start_radius,
			"push": direction * push_radius, "end": direction * end_radius,
			"launch": BURST_TIME + index * 0.022,
			"flight": lerpf(1.12, 1.42, _hash01(index, 3)),
			"arc": lerpf(1.8, 2.9, _hash01(index, 4)) * effect_size,
			"yaw": -angle if index == 0 or index == 3 else PI * 0.5 - angle,
			"spin": Vector3(lerpf(3.8, 6.5, _hash01(index, 5)), lerpf(-4.8, 4.8, _hash01(index, 6)), lerpf(2.8, 5.4, _hash01(index, 7))),
			"rest": Basis.from_euler(Vector3(PI * 0.5, angle, 0.15 * (index - 2))),
			"launched": false, "landed": false,
		})
		var paths: Array = context.get("piece_paths", [])
		if paths.size() == PIECE_COUNT:
			var path := paths[index] as Dictionary
			for key in ["start", "push", "end", "direction", "yaw"]:
				_states[index][key] = path[key]
		_pieces[index].visible = true
		_pieces[index].scale = Vector3.ONE * effect_size
	$BreachLight.visible = false
	$BreachLight.light_energy = 0.0
	$BreachLight.omni_range = 5.0 * effect_size
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:
	if elapsed >= BURST_TIME and not _burst_fired:
		_burst_fired = true
		_library_burst.position = Vector3(0, 1.65 * effect_size, 0)
		LibraryVfxAdapter3D.play_visual(_library_burst, effect_size, _seed)
	var flash := clampf(1.0 - (elapsed - BURST_TIME) / 0.23, 0, 1) if elapsed >= BURST_TIME else 0.0
	$BreachLight.light_energy = flash * 2.1
	$BreachLight.visible = flash > 0.0
	$BreachLight.position.y = 1.1 * effect_size
	var fade := 1.0 - smoothstep(2.75, 3.45, elapsed)
	for index in _pieces.size():
		var state: Dictionary = _states[index]
		var pivot := _pieces[index]
		var launch: float = state.launch
		var flight: float = state.flight
		var air_t := clampf((elapsed - launch) / flight, 0.0, 1.0)
		var air_time := clampf(elapsed - launch, 0.0, flight)
		var angles: Vector3 = Vector3(0, state.yaw, 0) + (state.spin as Vector3) * air_time
		var orientation := Basis.from_euler(angles)
		var point: Vector3
		var lift := 0.0
		if elapsed < launch:
			var push_t := smoothstep(0.0, BURST_TIME, elapsed)
			point = (state.start as Vector3).lerp(state.push, push_t)
			orientation = Basis.from_euler(Vector3(0.10 * sin(push_t * PI), state.yaw, -0.12 * push_t))
		else:
			if not state.launched:
				state.launched = true
				_fire(get_node("Trails/Flame%d" % index))
				_fire(get_node("Trails/Smoke%d" % index))
			point = (state.push as Vector3).lerp(state.end, air_t)
			lift = float(state.arc) * 4.0 * air_t * (1.0 - air_t)
			if air_t >= 1.0:
				if not state.landed:
					state.landed = true
					var dust := get_node("Impacts/Dust%d" % index) as GPUParticles3D
					dust.position = point + Vector3.UP * 0.12 * effect_size
					_fire(dust)
				var settle_t := clampf((elapsed - launch - flight) / 0.30, 0, 1)
				orientation = Basis(orientation.get_rotation_quaternion().slerp((state.rest as Basis).get_rotation_quaternion(), smoothstep(0, 1, settle_t)))
				lift = sin(settle_t * PI) * 0.22 * effect_size
				(get_node("Trails/Flame%d" % index) as GPUParticles3D).emitting = false
				if settle_t > 0.4:
					(get_node("Trails/Smoke%d" % index) as GPUParticles3D).emitting = false
		# 逐姿态支撑高度：翻滚和放平时都按实际视觉包络贴地，不用固定半高。
		var low := INF
		for corner in 8:
			low = minf(low, (orientation * _bounds[index].get_endpoint(corner)).y * effect_size)
		pivot.basis = orientation.scaled(Vector3.ONE * effect_size)
		pivot.position = point + Vector3.UP * (lift - low + 0.015 * effect_size)
		pivot.visible = fade > 0.0
		for mesh in pivot.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).transparency = 1.0 - fade
		(get_node("Trails/Flame%d" % index) as GPUParticles3D).position = pivot.position
		(get_node("Trails/Smoke%d" % index) as GPUParticles3D).position = pivot.position

func _fire(particles: GPUParticles3D) -> void:
	particles.restart(true)
	particles.emitting = true

func _on_lifetime_expired() -> void:
	LibraryVfxAdapter3D.stop_visual(_library_burst)
	for particles in _particles:
		particles.emitting = false
		particles.visible = false
		particles.restart(true)
		particles.emitting = false
	for piece in _pieces:
		piece.visible = false
	$BreachLight.light_energy = 0.0
	$BreachLight.visible = false
	_burst_fired = false

func _hash01(index: int, salt: int) -> float:
	var h := (_seed + index * 7919 + salt * 104729) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 100003) / 100003.0

func get_presentation_snapshot() -> Dictionary:
	var transforms: Array[Transform3D] = []
	var landed := 0
	var lowest := INF
	var budget := 0
	var trajectories: Array[Dictionary] = []
	for index in _pieces.size():
		transforms.append(_pieces[index].global_transform)
		if _states.size() > index:
			var state: Dictionary = _states[index]
			var start: Vector3 = global_transform * (state.start as Vector3)
			var push: Vector3 = global_transform * (state.push as Vector3)
			var end: Vector3 = global_transform * (state.end as Vector3)
			var actual := _pieces[index].global_position - start
			actual.y = 0.0
			trajectories.append({"index":index, "start":start, "push":push, "end":end,
				"direction":(global_basis * (state.direction as Vector3)).normalized(),
				"horizontal_displacement_m":actual.length(),
				"post_push_distance_m":Vector2(end.x-push.x,end.z-push.z).length()})
		if _states.size() > index and _states[index].landed:
			landed += 1
		for corner in 8:
			lowest = minf(lowest, (_pieces[index].global_transform * _bounds[index].get_endpoint(corner)).y)
	for particles in _particles:
		budget += particles.amount
	return {"asset_id": get_meta("asset_id"), "asset_version": get_meta("asset_version"),
		"piece_count": _pieces.size(), "transforms": transforms, "bounds": _bounds, "trajectories": trajectories,
		"landed_count": landed, "lowest_y": lowest, "floor_y": _floor_y,
		"landing_distance_m": _distance, "layout": _layout, "seed": _seed, "particle_budget": budget,
		"active": _active, "elapsed": _elapsed, "burst_fired": _burst_fired}
