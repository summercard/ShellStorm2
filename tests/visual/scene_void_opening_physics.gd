extends Node3D

const VOID := preload("res://assets/art/vfx/environment_3d/void_erosion/runtime/vfx_env_void_erosion_root_top3d.tscn")
const PLAYER := preload("res://scenes/Player3D.tscn")

var _failures: PackedStringArray = []
var _checks := 0


func _ready() -> void:
	var floor := _add_box(Vector3(0.0, -0.15, 0.0), Vector3(16.0, 0.3, 12.0))
	var original := floor.shape
	var lower := _add_box(Vector3(0.0, -3.15, 0.0), Vector3(16.0, 0.3, 12.0))
	var wall := _add_box(Vector3(0.0, 0.9, -1.0), Vector3(8.0, 1.8, 0.18))
	var disabled := _add_box(Vector3(0.0, -0.45, 0.0), Vector3(9.0, 0.2, 8.0))
	disabled.disabled = true
	var effect := _add_void(Vector3.ZERO, Vector3(4.0, 2.3, 4.0))
	await _settle()
	_check(not effect.remove_collision_in_void and _floor_at(0.0) == floor.get_parent(), "default preserves shared floor")

	effect.remove_collision_in_void = true
	await _settle()
	_check(_floor_at(0.0) == lower.get_parent(), "hole removes collision down to the next floor")
	_check(_floor_at(-3.0) == floor.get_parent(), "outside is still supported by the original body")
	_check(_ray(Vector3(0, 0.6, 0), Vector3(0, 0.6, -1.5)) == null, "wall inside the opening has no collision")
	_check(_ray(Vector3(3, 0.6, 0), Vector3(3, 0.6, -1.5)) == wall.get_parent(), "wall outside the opening still blocks")
	_check(_ray(Vector3(3, -0.32, 0), Vector3(3, -1, 0)) == null, "rebuild leaves disabled owners disabled")

	var player := PLAYER.instantiate() as Player3D
	player.position = Vector3(-3.3, 0.04, 0.5)
	add_child(player)
	for frame in 18:
		await _settle()
	_check(player.is_on_floor(), "player can stand outside the opening")
	Input.action_press("move_right")
	var fell := false
	var landed := false
	var lowest := player.position.y
	for frame in 130:
		await _settle()
		var state := player.get_state_machine_state()
		lowest = minf(lowest, player.position.y)
		if state == "falling":
			fell = true
			Input.action_release("move_right")
		if fell and state == "landing":
			landed = true
			break
	Input.action_release("move_right")
	_check(fell and lowest < -0.5, "real player enters Falling and descends")
	_check(landed and absf(player.position.y + 3.0) < 0.15, "real player enters Landing on lower floor")
	print("VOID_PHYSICS_PLAYER falling=%s landing=%s lowest_y=%.3f" % [fell, landed, lowest])
	player.queue_free()

	effect.progress = 0.45
	await _settle()
	_check(_floor_at(0.0) == lower.get_parent() and _floor_at(1.5) == floor.get_parent(), "partially open extent preserves ground outside it")
	effect.progress = 0.0
	await _settle()
	_check(_floor_at(0.0) == floor.get_parent() and _owner_has_original(floor, original), "animation closure restores source shape")

	effect.progress = 1.0
	var another := _add_void(Vector3(2.75, 0, 0), Vector3(3, 2.3, 4))
	another.remove_collision_in_void = true
	await _settle()
	_check(_floor_at(0.0) == lower.get_parent() and _floor_at(3.7) == lower.get_parent(), "both openings cut the same floor")
	effect.remove_collision_in_void = false
	await _settle()
	_check(_floor_at(0.0) == floor.get_parent() and _floor_at(3.7) == lower.get_parent(), "turning off one overlap keeps the other opening")
	another.queue_free()
	await _settle()
	await _settle()
	_check(_owner_has_original(floor, original) and _floor_at(3.7) == floor.get_parent(), "removing last effect restores original owner shape")

	# Without a lower floor, Player3D still uses the project's existing recovery.
	lower.get_parent().queue_free()
	effect.remove_collision_in_void = true
	var recovery_player := PLAYER.instantiate() as Player3D
	recovery_player.position = Vector3(-3.3, 0.04, 0.5)
	add_child(recovery_player)
	for frame in 18:
		await _settle()
	Input.action_press("move_right")
	var recovered := false
	for frame in 160:
		await _settle()
		if recovery_player.get_state_machine_state() == "falling":
			Input.action_release("move_right")
		if int(recovery_player.get_vertical_physics_snapshot().fall_recovery_count) > 0:
			recovered = true
			break
	Input.action_release("move_right")
	var safe_position: Vector3 = recovery_player.get_vertical_physics_snapshot().safe_ground_position
	var returned_to_anchor := recovery_player.position.distance_to(safe_position) < 0.15
	for frame in 20:
		await _settle()
	_check(recovered and returned_to_anchor and recovery_player.is_on_floor(), "pit with no lower floor returns player to stable safe ground")
	print("VOID_PHYSICS_RECOVERY recovered=%s grounded=%s position=%s anchor=%s" % [
		recovered, recovery_player.is_on_floor(), recovery_player.position, safe_position,
	])
	recovery_player.queue_free()

	var triangle_shape := ConcavePolygonShape3D.new()
	triangle_shape.set_faces(PackedVector3Array([
		Vector3(-4, 0, -3), Vector3(4, 0, -3), Vector3(4, 0, 3),
		Vector3(-4, 0, -3), Vector3(4, 0, 3), Vector3(-4, 0, 3),
	]))
	triangle_shape.backface_collision = true
	var triangle := _add_shape(Vector3(0, 0.15, 8), triangle_shape)
	var collision_paths: Array[NodePath] = [effect.get_path_to(triangle.get_parent())]
	effect.collision_roots = collision_paths
	effect.position.z = 8.0
	effect.rotation.y = PI * 0.25
	effect.progress = 1.0
	effect.remove_collision_in_void = true
	await _settle()
	_check(_floor_at(0.0, 8.0) == null, "rotated aperture clips a concave collision mesh")
	_check(_floor_at(1.9, 9.9) == triangle.get_parent(), "rotated aperture retains the corner of its broadphase bounds")
	effect.enabled = false
	await _settle()
	_check(_floor_at(0.0, 8.0) == triangle.get_parent() and _owner_has_original(triangle, triangle_shape), "effect disable restores original concave shape")

	for failure in _failures:
		print("VOID_PHYSICS_FAIL ", failure)
	print("VOID_PHYSICS_RESULT passed=%s checks=%d" % ["true" if _failures.is_empty() else "false", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _add_void(center: Vector3, size: Vector3) -> Node3D:
	var effect := VOID.instantiate() as Node3D
	effect.strict_box_bounds = true
	effect.position = center
	effect.box_size = size
	add_child(effect)
	return effect


func _add_box(center: Vector3, size: Vector3) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return _add_shape(center, box)


func _add_shape(center: Vector3, shape: Shape3D) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.position = center
	var source := CollisionShape3D.new()
	source.shape = shape
	body.add_child(source)
	add_child(body)
	return source


func _owner_has_original(source: CollisionShape3D, original: Shape3D) -> bool:
	var body := source.get_parent() as StaticBody3D
	var owner_id := body.get_shape_owners()[0]
	return (body.shape_owner_get_owner(owner_id) == source and body.shape_owner_get_shape_count(owner_id) == 1
			and body.shape_owner_get_shape(owner_id, 0) == original and source.shape == original)


func _floor_at(x: float, z := 0.0) -> Object:
	return _ray(Vector3(x, 0.4, z), Vector3(x, -4, z))


func _ray(from: Vector3, to: Vector3) -> Object:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider")


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
