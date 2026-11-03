class_name ReactiveProp3D
extends Node3D
## Stateful furnishings. The room owns persistence; this instance owns transitions.
## World-space animation preserves authored nonuniform scales when a shelf tips.

signal state_changed(prop: ReactiveProp3D)

const RECEIVER = preload("res://src/world3d/ReactivePropHitReceiver3D.gd")
const FALL_SECONDS := 0.85
const MAX_BOOKS := 8
const BOOK_COLORS := [Color("665449"), Color("647064"), Color("805953"), Color("b1a080")]

@export_enum("bookcase", "planter", "furniture", "desktop", "lamp") var prop_kind := "bookcase"
@export var max_hp := 300
@export var collapse_damage := 50
@export var books_every_hits := 2
@export var consecutive_hits_to_fall := 10
@export var consecutive_hit_window := 1.25
@export var contents_drop_hits := 3

var supported_items: Array[ReactiveProp3D] = []
var supporting_furniture: ReactiveProp3D
var attached_lights: Array[Light3D] = []
var contents_released := false
var _drop_active := false
var _drop_elapsed := 0.0
var _drop_start := Vector3.ZERO
var _drop_target := Vector3.ZERO
const DROP_SECONDS := 0.7

var current_hp := 0
var state := "intact"
var hit_count := 0
var books_dropped := 0
var _combo := 0
var _last_hit_msec := -100000
var _spring := Vector3.ZERO
var _spring_speed := Vector3.ZERO
var _pivot: Node3D
var _visual: Node3D
var _receiver: StaticBody3D
var _body: StaticBody3D
var _box: AABB
var _base: Transform3D
var _fall_direction := Vector3.FORWARD
var _fall_time := 0.0
var _impact_done := false
var _debris: Array[Dictionary] = []


func _ready() -> void:
	# Older room instances serialized visual-only metadata over the prefab defaults.
	set_meta("collision_owner", "ReactiveProp3D")
	set_meta("collision_policy", "reactive_prop")
	set_meta("collision_shape_count", 1)
	current_hp = maxi(1, max_hp)
	_visual = get_node("Visual") as Node3D
	_box = _visual_bounds(_visual, _visual.transform)
	# Authored layouts carry an additional LayoutCollision. Retire it permanently:
	# room streaming enables shapes again, but cannot re-enable these layer-zero bodies.
	for value in find_children("*", "StaticBody3D", true, false):
		var old := value as StaticBody3D
		old.collision_layer = 0
		old.collision_mask = 0
	_pivot = Node3D.new()
	_pivot.name = "ReactionPivot"
	add_child(_pivot)
	_visual.reparent(_pivot, false)
	# One collider serves blocking and hits. Two coincident bodies would let a
	# piercing bullet damage the same furnishing twice.
	_body = _make_body()
	_receiver = _body
	add_to_group("reactive_prop_3d")
	set_physics_process(false)


func _visual_bounds(node: Node3D, chain: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = chain * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		if child is Node3D:
			var child_box := _visual_bounds(child, chain * (child as Node3D).transform)
			if child_box.size.length_squared() > 0.000001:
				result = result.merge(child_box) if found else child_box
				found = true
	return result


func _make_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "HitReceiver"
	body.set_script(RECEIVER)
	body.collision_layer = 4 if prop_kind in ["desktop", "lamp"] else 5
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = _box.size
	shape.shape = box
	shape.position = _box.get_center()
	body.add_child(shape)
	add_child(body)
	return body


func take_damage(amount: int, _critical := false, direction := Vector3.ZERO, _knockback := 0.0) -> void:
	if amount <= 0 or state in ["falling", "fallen", "broken", "dropping"]:
		return
	current_hp = maxi(0, current_hp - amount)
	hit_count += 1
	var now := Time.get_ticks_msec()
	_combo = _combo + 1 if now - _last_hit_msec <= consecutive_hit_window * 1000.0 else 1
	_last_hit_msec = now
	var planar := Vector3(direction.x, 0, direction.z)
	if planar.length_squared() < 0.001:
		planar = -global_basis.z
	planar = planar.normalized()
	var local := global_basis.orthonormalized().inverse() * planar
	_spring_speed += Vector3(local.z, 0, -local.x) * minf(2.4, 0.7 + amount * 0.012)
	_spring_speed = _spring_speed.limit_length(4.0)
	state = "shaking"
	set_physics_process(true)
	if prop_kind in ["furniture", "bookcase"]:
		for item in supported_items:
			if is_instance_valid(item):
				item.shake_from_support(planar, amount)
	if prop_kind in ["furniture", "bookcase"] and _combo >= maxi(2, contents_drop_hits):
		_release_contents(planar)
	if prop_kind == "bookcase":
		if hit_count % maxi(1, books_every_hits) == 0:
			_drop_books(mini(MAX_BOOKS, books_dropped + 2), false)
		if current_hp <= 0 or _combo >= maxi(2, consecutive_hits_to_fall):
			_begin_fall(planar)
	elif prop_kind == "planter":
		if current_hp <= 0:
			_break_pot(false)
	state_changed.emit(self)


func _begin_fall(direction: Vector3) -> void:
	state = "falling"
	# A shelf tips over its horizontal bottom edge, including oblique shots.
	var back_axis := global_basis.z.normalized()
	_fall_direction = back_axis * (1.0 if direction.dot(back_axis) > 0.01 else -1.0)
	_fall_time = 0.0
	_impact_done = false
	_spring = Vector3.ZERO
	_spring_speed = Vector3.ZERO
	_pivot.transform = Transform3D.IDENTITY
	_base = global_transform
	_pivot.top_level = true
	_pivot.global_transform = _base
	_receiver.set_deferred("collision_layer", 0)
	_body.set_deferred("collision_layer", 0)
	_drop_books(MAX_BOOKS, false)
	_release_contents(direction)


func _fall_pose(progress: float) -> Transform3D:
	var rotation_basis := Basis(Vector3.UP.cross(_fall_direction).normalized(), progress * PI * 0.5)
	var pivot := _base * Vector3(_box.get_center().x, _box.position.y, _box.get_center().z)
	var pose := Transform3D(rotation_basis * _base.basis, pivot + rotation_basis * (_base.origin - pivot))
	var lowest := INF
	for index in 8:
		lowest = minf(lowest, (pose * _box.get_endpoint(index)).y)
	pose.origin.y += pivot.y - lowest
	return pose


func get_landing_box() -> Dictionary:
	var pose := _fall_pose(1.0)
	var frame := Transform3D(_base.basis.orthonormalized(), _base.origin)
	var bounds := AABB()
	for index in 8:
		var point := frame.affine_inverse() * (pose * _box.get_endpoint(index))
		bounds = AABB(point, Vector3.ZERO) if index == 0 else bounds.expand(point)
	return {"frame": frame, "bounds": bounds}


func _physics_process(delta: float) -> void:
	if _drop_active:
		_drop_elapsed = minf(DROP_SECONDS, _drop_elapsed + delta)
		var progress := _drop_elapsed / DROP_SECONDS
		global_position = _drop_start.lerp(_drop_target, progress)
		global_position.y += sin(progress * PI) * 0.22
		_pivot.rotation = Vector3(progress * PI * 0.8, 0, sin(progress * PI) * 0.5)
		if progress >= 1.0:
			_drop_active = false
			_on_drop_landed()
		return
	if state == "falling":
		_fall_time = minf(FALL_SECONDS, _fall_time + delta)
		var progress := _fall_time / FALL_SECONDS
		_pivot.global_transform = _fall_pose(progress * progress)
		if progress >= 1.0:
			state = "fallen"
			_apply_impact()
			state_changed.emit(self)
	elif state == "shaking":
		_spring_speed += (-_spring * 170.0 - _spring_speed * 13.0) * delta
		_spring += _spring_speed * delta
		_spring = _spring.limit_length(0.14)
		_pivot.rotation = _spring
		if _spring.length_squared() + _spring_speed.length_squared() < 0.00001:
			_spring = Vector3.ZERO
			_spring_speed = Vector3.ZERO
			_pivot.rotation = Vector3.ZERO
			state = "intact"
	_update_debris(delta)
	if state not in ["falling", "shaking"] and not _debris_flying():
		set_physics_process(false)


func _apply_impact() -> void:
	if _impact_done:
		return
	_impact_done = true
	var landing := get_landing_box()
	var frame: Transform3D = landing.frame
	var bounds: AABB = landing.bounds
	_play_landing_feedback(frame * Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z),bounds)
	# Query the exact final oriented footprint, including a creature's collider edge.
	var shape := BoxShape3D.new()
	shape.size = Vector3(bounds.size.x, maxf(1.5, bounds.size.y), bounds.size.z)
	var center := bounds.get_center()
	center.y = bounds.position.y + shape.size.y * 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(frame.basis, frame * center)
	query.collision_mask = 5
	query.exclude = [_body.get_rid()]
	var seen := {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 256):
		var actor := hit.collider as CharacterBody3D
		if actor == null or seen.has(actor.get_instance_id()) or not actor.has_method("take_damage"):
			continue
		seen[actor.get_instance_id()] = true
		actor.call("take_damage", collapse_damage, false, _fall_direction)
		# Normal actor damage owns death animation, kill events, and rewards.
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or int(actor.get("current_hp")) <= 0:
			continue
		_eject_actor(actor, frame, bounds)
	# Wreckage keeps the same occupied footprint; it must never restore the upright box.
	_body.top_level = true
	_body.global_transform = query.transform
	var collider := _body.get_node("Shape") as CollisionShape3D
	collider.position = Vector3.ZERO
	var final_shape := BoxShape3D.new()
	final_shape.size = bounds.size
	collider.set_deferred("shape", final_shape)
	_body.global_position = frame * bounds.get_center()
	_body.set_deferred("collision_layer", 1)


func _play_landing_feedback(point: Vector3, bounds: AABB) -> void:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	var size := clampf(bounds.size.x * 0.55,0.7,1.6)
	var frame: Transform3D = get_landing_box().frame
	var context := {"puff_offsets":[frame.basis * Vector3(-bounds.size.x*0.5,0,0),frame.basis * Vector3(bounds.size.x*0.5,0,0),frame.basis * Vector3(0,0,bounds.size.z*0.5)]}
	if pool != null:
		pool.acquire(VfxPool3D.FX01_BOOKCASE_LANDING_DUST,point,Color("8c785c"),size,context)
	else:
		var effect := VfxPool3D.create_unpooled(VfxPool3D.FX01_BOOKCASE_LANDING_DUST)
		get_parent().add_child(effect)
		effect.activate(point,Color("8c785c"),size,context)
	for value in get_tree().get_nodes_in_group("player_3d"):
		var player := value as Player3D
		if player == null or player.get_viewport().get_camera_3d() != player.camera:continue
		var distance := player.global_position.distance_to(point)
		if distance < 14.0:
			player.camera_feedback.request_environment_impact(1.0-distance/14.0)


func _actor_radius(actor: CharacterBody3D) -> float:
	var radius := 0.25
	for value in actor.find_children("*", "CollisionShape3D", true, false):
		var collider := value as CollisionShape3D
		if collider.disabled or collider.shape == null:
			continue
		var aabb := collider.global_transform * collider.shape.get_debug_mesh().get_aabb()
		radius = maxf(radius, maxf(aabb.size.x, aabb.size.z) * 0.5)
	return radius + 0.08


func _eject_actor(actor: CharacterBody3D, frame: Transform3D, bounds: AABB) -> void:
	var point := frame.affine_inverse() * actor.global_position
	var margin := _actor_radius(actor)
	var candidates: Array[Vector3] = []
	# Try all four edges; blocked wall-side exits fall back to the next free edge.
	for axis in [0, 2]:
		for edge in [bounds.position[axis] - margin, bounds.end[axis] + margin]:
			var target := point
			target[axis] = edge
			candidates.append(frame * target)
	candidates.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(actor.global_position) < b.distance_squared_to(actor.global_position))
	for target in candidates:
		var motion := target - actor.global_position
		# test_move checks the whole sweep, so no teleport through walls/other creatures.
		if not actor.test_move(actor.global_transform, motion):
			actor.global_position = target
			actor.velocity = Vector3.ZERO
			return
	# A crowded edge may have a free position farther along it.
	for offset in [margin * 2.0, -margin * 2.0, margin * 4.0, -margin * 4.0]:
		for edge_index in candidates.size():
			var edge_point := frame.affine_inverse() * candidates[edge_index]
			var tangent := frame.basis.z if edge_point.x < bounds.position.x or edge_point.x > bounds.end.x else frame.basis.x
			var target: Vector3 = candidates[edge_index] + tangent * float(offset)
			if not actor.test_move(actor.global_transform, target - actor.global_position):
				actor.global_position = target
				actor.velocity = Vector3.ZERO
				return


func _drop_books(total: int, settled: bool) -> void:
	while books_dropped < total:
		var index := books_dropped
		books_dropped += 1
		var book := Node3D.new()
		book.name = "DroppedBook_%02d" % index
		var size := Vector3(0.16 + (index % 3) * 0.025, 0.055, 0.25)
		_add_mesh(book, size, Vector3.ZERO, BOOK_COLORS[index % BOOK_COLORS.size()])
		_add_mesh(book, size * Vector3(0.9, 0.72, 0.92), Vector3(0.008, 0.002, 0), Color("c6bd9e"))
		var start := Vector3(lerpf(_box.position.x, _box.end.x, (index + 1.0) / 9.0), _box.size.y * (0.35 + (index % 3) * 0.2), _box.end.z)
		var target := Vector3(start.x + sin(index * 2.4) * 0.35, _box.position.y + 0.04, _box.end.z + 0.4 + (index % 3) * 0.3)
		_add_debris(book, start, target, index, settled)


func _break_pot(settled: bool) -> void:
	state = "broken"
	_visual.visible = false
	_body.set_deferred("collision_layer", 0)
	_receiver.set_deferred("collision_layer", 0)
	if has_node("PotShard_0"):
		return
	for index in 5:
		var shard := Node3D.new()
		shard.name = "PotShard_%d" % index
		var mesh := MeshInstance3D.new()
		var wedge := PrismMesh.new()
		wedge.size = Vector3(0.16 + index * 0.018, 0.07, 0.22)
		mesh.mesh = wedge
		mesh.material_override = _material(Color("79543b") if index % 2 == 0 else Color("a17b56"))
		shard.add_child(mesh)
		var angle := index * TAU / 5.0
		var target := Vector3(cos(angle), 0, sin(angle)) * minf(0.7, _box.size.y * 0.45)
		target.y = _box.position.y + 0.045
		_add_debris(shard, Vector3(0, _box.size.y * 0.22, 0), target, index, settled)
	# Soil and fallen foliage make this read as a broken planted pot, not a vase.
	var remains := Node3D.new()
	remains.name = "PlantRemains"
	_add_mesh(remains, Vector3(0.32, 0.05, 0.30), Vector3(0, _box.position.y + 0.03, 0), Color("40382c"))
	for index in 3:
		_add_mesh(remains, Vector3(0.20, 0.025, 0.10), Vector3(0.08 * index - 0.1, _box.position.y + 0.07, 0.08 * (index % 2)), Color("435c40"))
	add_child(remains)


func _add_mesh(root: Node3D, size: Vector3, location: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = location
	mesh.material_override = _material(color)
	root.add_child(mesh)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _add_debris(node: Node3D, start: Vector3, target: Vector3, index: int, settled: bool) -> void:
	add_child(node)
	node.position = target if settled else start
	node.rotation.y = index * 1.37
	_debris.append({"node": node, "start": start, "end": target, "time": 1.0 if settled else 0.0, "spin": index * 1.37})


func _update_debris(delta: float) -> void:
	for item in _debris:
		if float(item.time) >= 1.0:
			continue
		item.time = minf(1.0, float(item.time) + delta / 0.75)
		var t: float = item.time
		var node: Node3D = item.node
		node.position = (item.start as Vector3).lerp(item.end, t)
		node.position.y += sin(t * PI) * 0.45
		node.rotation = Vector3(sin(t * PI) * 2.0, float(item.spin) + t * TAU, sin(t * PI) * 0.7)


func _debris_flying() -> bool:
	for item in _debris:
		if float(item.time) < 1.0:
			return true
	return false


func export_prop_state() -> Dictionary:
	return {"hp": current_hp, "state": state, "hits": hit_count, "books": books_dropped,
		"fall_direction": [_fall_direction.x, 0.0, _fall_direction.z],
		"contents_released": contents_released, "drop_active": _drop_active,
		"drop_elapsed": _drop_elapsed, "drop_start": [_drop_start.x, _drop_start.y, _drop_start.z],
		"drop_target": [_drop_target.x, _drop_target.y, _drop_target.z],
		"pose": _serialize_pose()}


func restore_prop_state(data: Dictionary) -> void:
	_restore_pose(data)
	contents_released = bool(data.get("contents_released", false))
	current_hp = clampi(int(data.get("hp", max_hp)), 0, maxi(1, max_hp))
	hit_count = maxi(0, int(data.get("hits", 0)))
	_drop_books(clampi(int(data.get("books", 0)), 0, MAX_BOOKS), true)
	var wanted := str(data.get("state", "intact"))
	if bool(data.get("drop_active", false)) and not _drop_active:
		_drop_start = _array_vector(data.get("drop_start", []))
		_drop_target = _array_vector(data.get("drop_target", []))
		_drop_elapsed = clampf(float(data.get("drop_elapsed", 0.0)), 0, DROP_SECONDS)
		_drop_active = true
		state = "dropping"
		_body.set_deferred("collision_layer", 0)
		_disable_attached_lights()
		set_physics_process(true)
		return
	if wanted == "dropped":
		state = "dropped"
		_set_dropped_pose()
		return
	if wanted in ["falling", "fallen"] and state != "fallen":
		var direction: Array = data.get("fall_direction", [0.0, 0.0, -1.0])
		var planar := Vector3(float(direction[0]), 0, float(direction[2]))
		_drop_books(MAX_BOOKS, true)
		_begin_fall(planar.normalized() if planar.length_squared() > 0.001 else Vector3.FORWARD)
		state = "fallen"
		_pivot.global_transform = _fall_pose(1.0)
		# Restoring progress must never inflict damage a second time.
		_impact_done = true
		var landing := get_landing_box()
		var frame: Transform3D = landing.frame
		var bounds: AABB = landing.bounds
		_body.top_level = true
		_body.global_transform = Transform3D(frame.basis, frame * bounds.get_center())
		(_body.get_node("Shape") as CollisionShape3D).position = Vector3.ZERO
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		(_body.get_node("Shape") as CollisionShape3D).set_deferred("shape", shape)
		_body.set_deferred("collision_layer", 1)
	elif wanted == "broken" and state != "broken":
		_break_pot(true)


## A support hit is visual feedback only: no damage, hit count, or lamp explosion.
func shake_from_support(direction: Vector3, amount: int) -> void:
	if state not in ["intact", "shaking"] or _drop_active:
		return
	var local := global_basis.orthonormalized().inverse() * direction
	_spring_speed += Vector3(local.z, 0, -local.x) * minf(2.2, 1.0 + amount * 0.01)
	_spring_speed = _spring_speed.limit_length(4.0)
	state = "shaking"
	set_physics_process(true)


func _release_contents(direction: Vector3) -> void:
	if contents_released:
		return
	contents_released = true
	for item in supported_items:
		if is_instance_valid(item):
			item.begin_drop(self, direction)


func begin_drop(support: ReactiveProp3D, direction: Vector3) -> void:
	if _drop_active or state in ["broken", "burning", "spent", "dropped"]:
		return
	_drop_start = global_position
	var box := support._box
	var point := support.to_local(global_position)
	var edges: Array[Vector3] = []
	var margin := maxf(_box.size.x * global_basis.x.length(), _box.size.z * global_basis.z.length()) * 0.6 + 0.15
	for axis in [0, 2]:
		for sign_value in [-1.0, 1.0]:
			var target := point
			target[axis] = (box.position[axis] if sign_value < 0 else box.end[axis]) + sign_value * margin / support.global_basis[axis].length()
			target.y = point.y
			edges.append(support.to_global(target))
	edges.sort_custom(func(a: Vector3, b: Vector3): return (a - global_position).normalized().dot(direction) > (b - global_position).normalized().dot(direction))
	_drop_target = edges[0]
	for candidate in edges:
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.15, candidate + Vector3.UP * 0.15, 1)
		query.exclude = [support._body.get_rid(), _body.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_drop_target = candidate
			break
	_drop_target.y = _floor_y_at(_drop_target, support._body.get_rid())
	_drop_active = true
	_drop_elapsed = 0.0
	state = "dropping"
	_body.set_deferred("collision_layer", 0)
	_disable_attached_lights()
	set_physics_process(true)
	state_changed.emit(self)


func _floor_y_at(point: Vector3, excluded: RID) -> float:
	var fallback := global_position.y
	if is_instance_valid(supporting_furniture):
		fallback = supporting_furniture.to_global(Vector3(0, supporting_furniture._box.position.y, 0)).y
	else:
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor is DungeonRoom3D:
				fallback = (ancestor as Node3D).global_position.y + 0.1
				break
			ancestor = ancestor.get_parent()
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, point.y + 0.1, point.z), Vector3(point.x, fallback - 8.0, point.z), 1)
	query.exclude = [excluded, _body.get_rid()]
	for attempt in 8:
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		if hit.collider is StaticBody3D:
			return (hit.position as Vector3).y
		query.exclude = query.exclude + [hit.rid]
	return fallback


func _on_drop_landed() -> void:
	_pivot.rotation = Vector3.ZERO
	if prop_kind == "planter":
		current_hp = 0
		_break_pot(false)
	else:
		state = "dropped"
		_set_dropped_pose()
	state_changed.emit(self)


func _set_dropped_pose() -> void:
	_body.set_deferred("collision_layer", 0)
	_pivot.rotation = Vector3(PI * 0.5, 0, 0.12)
	_pivot.position.y = -(_pivot.transform * _box).position.y


func _disable_attached_lights() -> void:
	for light in attached_lights:
		if is_instance_valid(light):
			light.set_meta("reactive_light_disabled", true)
			light.visible = false
			light.light_energy = 0.0


func _serialize_pose() -> Array:
	var pose := global_transform
	return [pose.basis.x.x, pose.basis.x.y, pose.basis.x.z,
		pose.basis.y.x, pose.basis.y.y, pose.basis.y.z,
		pose.basis.z.x, pose.basis.z.y, pose.basis.z.z,
		pose.origin.x, pose.origin.y, pose.origin.z]


func _restore_pose(data: Dictionary) -> void:
	var values: Array = data.get("pose", [])
	if values.size() == 12:
		global_transform = Transform3D(Basis(Vector3(values[0], values[1], values[2]),
			Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8])),
			Vector3(values[9], values[10], values[11]))


func _array_vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2]) if values.size() == 3 else global_position
