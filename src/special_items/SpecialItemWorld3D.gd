class_name SpecialItemWorld3D
extends Node3D
## Scene-owned damage/propagation authority. Visuals contain no collision or gameplay.
const TICK := 0.5
const MAX_OIL := 128
const MAX_FIRE := 16
const MAX_PROJECTILES := 16
const GRAVITY := 18.0
const GROUND_MASK := 1
const MODEL_SCENES := {
	SpecialItemCatalog.GRENADE: preload("res://assets/art/items_weapons/props/special_grenade/runtime/itm_special_grenade_ground_root_top3d.tscn"),
	SpecialItemCatalog.MOLOTOV: preload("res://assets/art/items_weapons/props/special_molotov/runtime/itm_special_molotov_ground_root_top3d.tscn"),
}
var projectiles: Array[Dictionary] = []
var oil: Array[Dictionary] = []
var fires: Array[Dictionary] = []
var clock := 0.0
var floor_number := -1
var _next_damage_tick := TICK
var _shape := SphereShape3D.new()
var _fire_voice: Node
var _last_ignite_cue := -1.0

func _ready() -> void:
	add_to_group("special_item_world_3d")

func _init() -> void:
	_shape.radius = 0.09

func _physics_process(delta: float) -> void:
	advance(delta)

func launch(definition: Dictionary, attacker: Node3D, forward: Vector3) -> bool:
	var content_id := str(definition.id)
	if not MODEL_SCENES.has(content_id):
		return false
	var reserved_fire := 0
	for projectile: Dictionary in projectiles:
		if str(projectile.definition.id) == SpecialItemCatalog.MOLOTOV:
			reserved_fire += 1
	if projectiles.size() >= MAX_PROJECTILES or (content_id == SpecialItemCatalog.MOLOTOV and fires.size() + reserved_fire >= MAX_FIRE):
		return false
	var body := (MODEL_SCENES[content_id] as PackedScene).instantiate() as Node3D
	add_child(body)
	body.global_position = attacker.global_position + Vector3.UP * 0.95 + forward * 0.35
	var visual := body.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale *= 1.6
	var time := float(definition.flight_time)
	var velocity := forward * float(definition.throw_distance) / time
	velocity.y = (0.5 * GRAVITY * time * time - 0.95) / time
	# The short release segment must also respect walls; a muzzle already beyond
	# a thin wall would otherwise bypass every subsequent sweep.
	var release_start := attacker.global_position + Vector3.UP * 0.95
	var release_query := PhysicsShapeQueryParameters3D.new()
	release_query.shape = _shape
	release_query.transform = Transform3D(Basis.IDENTITY, release_start)
	release_query.motion = forward * 0.35
	release_query.collision_mask = GROUND_MASK
	var release_fractions := get_world_3d().direct_space_state.cast_motion(release_query)
	if release_fractions.size() > 0 and float(release_fractions[0]) < 1.0:
		body.global_position = release_start + forward * 0.35 * float(release_fractions[0])
		velocity.x = 0.0
		velocity.z = 0.0
	projectiles.append({"node": body, "velocity": velocity, "definition": definition, "attacker": attacker, "age": 0.0})
	_cue("special.throw", body.global_position, -8.0)
	return true

func deposit_oil(at: Vector3, attacker: Node3D) -> Dictionary:
	if oil.size() >= MAX_OIL:
		return {"success": false, "reason": "world_capacity"}
	var hit := _ray(at + Vector3.UP * 0.35, at - Vector3.UP * 0.65)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.65:
		return {"success": false, "reason": "no_ground"}
	var point: Vector3 = hit.position
	# Prevent repeatedly painting the same patch by releasing/repressing or switching.
	for patch: Dictionary in oil:
		if (patch.position as Vector3).distance_to(point) < 0.4:
			return {"success": false, "reason": "already_oiled"}
	var definition := SpecialItemCatalog.get_item(SpecialItemCatalog.GASOLINE)
	var visual := _effect(VfxPool3D.FX01_SPECIAL_OIL, point + Vector3.UP * 0.025, float(definition.radius), 3600.0)
	var patch := {"position": point, "born": clock, "ignite_at": -1.0, "burn_until": -1.0, "visual": visual, "fire_visual": null, "attacker": attacker}
	oil.append(patch)
	return {"success": true, "position": point}

func add_fire(at: Vector3, radius: float, duration: float, damage: int, attacker: Node3D) -> bool:
	if fires.size() >= MAX_FIRE:
		return false
	var visual := _effect(VfxPool3D.FX01_SPECIAL_FIRE, at + Vector3.UP * 0.035, radius, duration)
	fires.append({"position": at, "radius": radius, "until": clock + duration, "damage": damage, "attacker": attacker, "visual": visual})
	_ignite_audio(at)
	return true

func advance(delta: float) -> void:
	# Substeps retain ordered ignition and exact five-second expiry during a long frame.
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining, minf(1.0 / 60.0, maxf(0.000001, _next_damage_tick - clock)))
		clock += step
		_step_projectiles(step)
		_step_fire_and_oil()
		if clock + 0.00001 >= _next_damage_tick:
			_damage_fire_tick()
			_next_damage_tick += TICK
		remaining -= step

func _step_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var body := projectile.node as Node3D
		var start := body.global_position
		var velocity: Vector3 = projectile.velocity
		var movement := velocity * delta + Vector3.DOWN * GRAVITY * delta * delta * 0.5
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _shape
		query.transform = Transform3D(Basis.IDENTITY, start)
		query.motion = movement
		query.collision_mask = GROUND_MASK
		var fractions := get_world_3d().direct_space_state.cast_motion(query)
		var fraction := float(fractions[0]) if fractions.size() > 0 else 1.0
		# Shape sweeps may ignore a body already touching at the beginning of a
		# step. A segment ray closes that exact-contact gap on thin walls.
		var segment_hit := _ray(start, start + movement)
		if not segment_hit.is_empty():
			fraction = minf(fraction, start.distance_to(segment_hit.position) / maxf(movement.length(), 0.00001))
		body.global_position = start + movement * fraction
		body.rotate_x(delta * 8.0)
		projectile.velocity = velocity + Vector3.DOWN * GRAVITY * delta
		projectile.age = float(projectile.age) + delta
		if fraction < 1.0:
			# Contact with a wall cancels horizontal travel, then the item falls and
			# detonates on the walking surface, rather than exploding in midair.
			query.transform.origin = start + movement * (float(fractions[1]) if fractions.size() > 1 else fraction) + movement.normalized() * 0.01
			query.motion = Vector3.ZERO
			var contact := get_world_3d().direct_space_state.get_rest_info(query)
			if not segment_hit.is_empty():
				contact = segment_hit
			if contact.is_empty():
				contact = _ray(start, body.global_position + movement.normalized() * 0.2)
			var normal: Vector3 = contact.get("normal", Vector3.UP)
			if normal.y >= 0.65:
				_detonate(projectile, body.global_position)
				body.queue_free()
				projectiles.remove_at(index)
			else:
				if not segment_hit.is_empty():
					body.global_position = (segment_hit.position as Vector3) + normal * 0.105
				else:
					body.global_position += normal * 0.025
				projectile.velocity = (projectile.velocity as Vector3).slide(normal)
		elif float(projectile.age) > 3.0:
			body.queue_free()
			projectiles.remove_at(index)

func _detonate(projectile: Dictionary, at: Vector3) -> void:
	var definition := projectile.definition as Dictionary
	var attacker := projectile.attacker as Node3D if is_instance_valid(projectile.attacker) else null
	if str(definition.id) == SpecialItemCatalog.GRENADE:
		_cue("special.blast", at, -3.0)
		_effect(VfxPool3D.FX01_SPECIAL_BLAST, at, float(definition.radius), 0.65)
		for candidate: Node in get_tree().get_nodes_in_group("enemy_3d"):
			if _in_range(candidate, at, float(definition.radius)):
				_hit(candidate, int(definition.damage), at, attacker, false)
	else:
		_cue("special.glass", at, -5.0)
		var floor_hit := _ray(at + Vector3.UP * 0.2, at - Vector3.UP * 1.0)
		if not floor_hit.is_empty() and (floor_hit.normal as Vector3).y >= 0.65:
			add_fire(floor_hit.position, float(definition.radius), float(definition.duration), int(definition.damage_per_tick), attacker)

func _step_fire_and_oil() -> void:
	var definition := SpecialItemCatalog.get_item(SpecialItemCatalog.GASOLINE)
	for patch: Dictionary in oil:
		if float(patch.burn_until) > 0.0:
			continue
		if float(patch.ignite_at) < 0.0:
			# Existing interactive lamps publish actual gameplay fire patches in this group.
			for source: Node in get_tree().get_nodes_in_group("lamp_fire_patch_3d"):
				if source is Node3D and not source.is_queued_for_deletion() and _connected(patch.position, (source as Node3D).global_position, float(source.get("radius")) + float(definition.radius)):
					patch.ignite_at = clock
					break
			for fire: Dictionary in fires:
				if clock <= float(fire.until) and _connected(patch.position, fire.position, float(fire.radius) + float(definition.radius)):
					patch.ignite_at = clock
					break
			for source: Dictionary in oil:
				if source == patch or float(source.burn_until) <= clock:
					continue
				if _connected(patch.position, source.position, float(definition.radius) * 2.0):
					patch.ignite_at = clock + float(definition.spread_delay)
					break
		if float(patch.ignite_at) >= 0.0 and clock + 0.00001 >= float(patch.ignite_at):
			patch.burn_until = clock + float(definition.duration)
			patch.fire_visual = _effect(VfxPool3D.FX01_SPECIAL_FIRE, patch.position + Vector3.UP * 0.04, float(definition.radius), float(definition.duration))
			_ignite_audio(patch.position)
	# Tick the last boundary before expiry, then free visuals/state.
	for index in range(fires.size() - 1, -1, -1):
		if clock > float(fires[index].until) + 0.0001:
			_finish(fires[index].visual)
			fires.remove_at(index)
	for index in range(oil.size() - 1, -1, -1):
		var patch := oil[index]
		if (float(patch.burn_until) > 0.0 and clock > float(patch.burn_until) + 0.0001) or (float(patch.burn_until) < 0.0 and float(patch.ignite_at) < 0.0 and clock - float(patch.born) > float(definition.dry_duration)):
			_finish(patch.visual)
			_finish(patch.fire_visual)
			oil.remove_at(index)
	var burning_positions: Array[Vector3] = []
	for fire: Dictionary in fires:
		burning_positions.append(fire.position)
	for patch: Dictionary in oil:
		if float(patch.burn_until) > clock:
			burning_positions.append(patch.position)
	if burning_positions.is_empty():
		_stop_fire_audio()
	elif is_instance_valid(_fire_voice) and _fire_voice is Node3D:
		(_fire_voice as Node3D).global_position = burning_positions[0]

func _damage_fire_tick() -> void:
	var definition := SpecialItemCatalog.get_item(SpecialItemCatalog.GASOLINE)
	for candidate: Node in get_tree().get_nodes_in_group("enemy_3d"):
		var amount := 0
		var origin := Vector3.ZERO
		var attacker: Node3D = null
		for fire: Dictionary in fires:
			if clock <= float(fire.until) + 0.0001 and int(fire.damage) > amount and _in_range(candidate, fire.position, float(fire.radius)):
				amount = int(fire.damage)
				origin = fire.position
				attacker = fire.attacker as Node3D if is_instance_valid(fire.attacker) else null
		for patch: Dictionary in oil:
			if float(patch.burn_until) >= clock - 0.0001 and float(patch.burn_until) > 0.0 and int(definition.damage_per_tick) > amount and _in_range(candidate, patch.position, float(definition.radius)):
				amount = int(definition.damage_per_tick)
				origin = patch.position
				attacker = patch.attacker as Node3D if is_instance_valid(patch.attacker) else null
		if amount > 0:
			_hit(candidate, amount, origin, attacker, true)

func _hit(candidate: Node, amount: int, origin: Vector3, attacker: Node3D, fire: bool) -> void:
	if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return
	var direction := ((candidate as Node3D).global_position - origin).normalized()
	if candidate.has_method("take_projectile_damage"):
		var tags: Array[String] = ["special_item", "fire" if fire else "explosion"]
		candidate.call("take_projectile_damage", amount, false, direction, tags, {"damage_element": "fire" if fire else "", "special_item": true}, attacker if is_instance_valid(attacker) else null)
	elif candidate.has_method("take_damage"):
		candidate.call("take_damage", amount, false, direction)

func _in_range(candidate: Node, at: Vector3, radius: float) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node3D or candidate.is_queued_for_deletion():
		return false
	return _connected((candidate as Node3D).global_position, at, radius)

func _connected(a: Vector3, b: Vector3, radius: float) -> bool:
	if absf(a.y - b.y) > 0.6:
		return false
	var horizontal := Vector2(a.x - b.x, a.z - b.z)
	return horizontal.length() <= radius and _ray(a + Vector3.UP * 0.25, b + Vector3.UP * 0.25).is_empty()

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if a.distance_squared_to(b) < 0.00001:
		return {}
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, GROUND_MASK))

func _effect(asset_id: StringName, at: Vector3, radius: float, duration: float) -> VfxEffectBase3D:
	var effect := VfxPool3D.create_unpooled(asset_id)
	if effect != null:
		add_child(effect)
		effect.activate(at, Color.WHITE, radius, {"duration": duration})
	return effect

func _finish(effect: Variant) -> void:
	if is_instance_valid(effect):
		(effect as VfxEffectBase3D).finish()

func clear() -> void:
	_stop_fire_audio()
	for child: Node in get_children():
		child.queue_free()
	projectiles.clear()
	oil.clear()
	fires.clear()
	_next_damage_tick = clock + TICK

func _cue(event_id: String, at: Vector3, volume_db: float) -> Node:
	return AudioManager.emit_event(event_id, {"source_node": self, "source_position": at, "volume_db": volume_db, "max_distance": 24.0, "unit_size": 4.0})

func _ignite_audio(at: Vector3) -> void:
	if clock - _last_ignite_cue >= 0.15:
		_cue("special.ignite", at, -9.0)
		_last_ignite_cue = clock
	if not is_instance_valid(_fire_voice):
		_fire_voice = _cue("special.fire_loop", at, -17.0)

func _stop_fire_audio() -> void:
	if is_instance_valid(_fire_voice):
		AudioManager.stop_voice(_fire_voice)
	_fire_voice = null


## Bullets test their actual traveled segment, clipped by world collision. Oil
## is gameplay data, never a blocking collider; existing projectile physics stays authoritative.
func ignite_bullet_segment(start: Vector3, end: Vector3) -> void:
	var a := Vector2(start.x, start.z)
	var b := Vector2(end.x, end.z)
	var segment := b - a
	var radius := float(SpecialItemCatalog.get_item(SpecialItemCatalog.GASOLINE).radius)
	for patch: Dictionary in oil:
		if float(patch.burn_until) > 0.0:
			continue
		var point: Vector3 = patch.position
		var t := clampf((Vector2(point.x,point.z)-a).dot(segment)/maxf(segment.length_squared(),0.000001),0.0,1.0)
		if absf(lerpf(start.y,end.y,t)-point.y) > 1.2:
			continue
		if (a+segment*t).distance_to(Vector2(point.x,point.z)) <= radius:
			patch.ignite_at = clock
	_step_fire_and_oil()
