extends Node3D


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var connector := (tower.get("_corridor_by_edge") as Dictionary).values().filter(
		func(node: Node) -> bool: return node.name == "Stair_B"
	).front() as Node3D
	connector.visible = true
	connector.process_mode = Node.PROCESS_MODE_INHERIT
	tower.call("_set_connector_collision_enabled", connector, true, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var failures: Array[String] = []
	for z in [0.10, 1.0, 2.5, 4.0, 4.9]:
		var actor := CharacterBody3D.new()
		actor.collision_layer = 2
		actor.collision_mask = 1
		actor.floor_snap_length = 0.4
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.34
		capsule.height = 1.5
		var actor_shape := CollisionShape3D.new()
		actor_shape.shape = capsule
		actor_shape.position.y = 0.75
		actor.add_child(actor_shape)
		add_child(actor)
		actor.position = Vector3(34.0, -11.97, z)
		var hit_names: Array[String] = []
		for frame in range(240):
			await get_tree().physics_frame
			actor.velocity = Vector3(3.0, actor.velocity.y - 24.0 * get_physics_process_delta_time(), 0.0)
			actor.move_and_slide()
			for collision_index in range(actor.get_slide_collision_count()):
				var collider := actor.get_slide_collision(collision_index).get_collider() as Node
				if collider != null and not collider.name in hit_names:
					hit_names.append(collider.name)
			if actor.position.x >= 36.2:
				break
		if actor.position.x < 36.2:
			failures.append("Stair_B upper entry movement blocked at z=%.2f x=%.3f by %s" % [z, actor.position.x, ",".join(hit_names)])
		actor.queue_free()
		await get_tree().process_frame
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var stair := connector_value as Node3D
		if stair == null or stair.name not in ["Stair_A", "Stair_B"]:
			continue
		stair.visible = true
		stair.process_mode = Node.PROCESS_MODE_INHERIT
		tower.call("_set_connector_collision_enabled", stair, true, false)
		await get_tree().physics_frame
		var points := stair.get_meta("path_points", []) as Array
		for segment_index in [2, 6]:
			for side_sign in [-1.0, 1.0]:
				for run_ratio in [0.03, 0.5, 0.97]:
					var guard_failure := await _cross_guard(
						stair.name,
						points[segment_index] as Vector3,
						points[segment_index + 1] as Vector3,
						side_sign,
						run_ratio
					)
					if not guard_failure.is_empty():
						failures.append(guard_failure)
	tower.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print("STAIR_ENTRY_CLEARANCE failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _cross_guard(
	stair_name: String, start: Vector3, end: Vector3, side_sign: float, run_ratio: float
) -> String:
	var planar := Vector3(end.x - start.x, 0.0, end.z - start.z)
	var perpendicular := Vector3(-planar.z, 0.0, planar.x).normalized() * side_sign
	var midpoint := start.lerp(end, run_ratio)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.floor_snap_length = 0.4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.5
	var actor_shape := CollisionShape3D.new()
	actor_shape.shape = capsule
	actor_shape.position.y = 0.75
	actor.add_child(actor_shape)
	add_child(actor)
	actor.position = midpoint + Vector3.UP * 0.03
	var guard_hit := false
	for frame in range(180):
		await get_tree().physics_frame
		actor.velocity = perpendicular * 3.0
		actor.velocity.y -= 24.0 * get_physics_process_delta_time()
		actor.move_and_slide()
		for collision_index in range(actor.get_slide_collision_count()):
			var collider := actor.get_slide_collision(collision_index).get_collider() as Node
			if collider != null and bool(collider.get_meta("stair_guard_collision", false)):
				guard_hit = true
	var crossed_distance := (actor.position - midpoint).dot(perpendicular)
	actor.queue_free()
	await get_tree().process_frame
	if crossed_distance > 1.82:
		return "%s segment %s ratio %.2f side %.0f crossed railing by %.3fm" % [stair_name, start, run_ratio, side_sign, crossed_distance]
	if not guard_hit:
		return "%s segment %s ratio %.2f side %.0f did not collide with railing body" % [stair_name, start, run_ratio, side_sign]
	return ""
