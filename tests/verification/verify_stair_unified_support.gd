extends Node3D

func _ready() -> void:
	var factory := TowerDescent3D.new()
	var support := Node3D.new()
	add_child(support)
	factory.call("_add_unified_stair_support", support, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK)
	factory.call("_add_stair_segment", support, Vector3(11.501,0,3.1203), Vector3(11.501,-6,18.1203), 2)
	factory.call("_add_stair_segment", support, Vector3(3.501,-6,18.1203), Vector3(3.501,-12,3.1203), 6)
	factory.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var failures: Array[String] = []
	var lower_camera_query := PhysicsRayQueryParameters3D.create(Vector3(3.501,-5.0,10.6203), Vector3(3.501,-13.0,10.6203), GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY)
	if get_world_3d().direct_space_state.intersect_ray(lower_camera_query).is_empty():
		failures.append("lower flight camera slab is missing")
	var upper_camera_query := PhysicsRayQueryParameters3D.create(Vector3(11.501,1.0,10.6203), Vector3(11.501,-7.0,10.6203), GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY)
	if not get_world_3d().direct_space_state.intersect_ray(upper_camera_query).is_empty():
		failures.append("upper/north flight still owns camera collision")
	var guard_count := 0
	var guard_rids: Array[RID] = []
	for body_value in support.find_children("*", "StaticBody3D", true, false):
		var guard := body_value as StaticBody3D
		if guard != null and bool(guard.get_meta("stair_guard_collision", false)):
			guard_count += 1
			guard_rids.append(guard.get_rid())
	if guard_count != 6:
		failures.append("expected 6 railing blockers, got %d" % guard_count)
	var guard_queries := [
		PhysicsRayQueryParameters3D.create(Vector3(3.501,-8.4,10.6203), Vector3(-0.5,-8.4,10.6203), 1),
		PhysicsRayQueryParameters3D.create(Vector3(11.501,-2.4,10.6203), Vector3(15.5,-2.4,10.6203), 1),
		PhysicsRayQueryParameters3D.create(Vector3(4.0,0.6,2.5), Vector3(4.0,0.6,4.0), 1),
		PhysicsRayQueryParameters3D.create(Vector3(14.65,0.6,2.5), Vector3(14.65,0.6,4.0), 1),
		PhysicsRayQueryParameters3D.create(Vector3(9.351,0.6,2.9), Vector3(9.351,0.6,3.5), 1),
		PhysicsRayQueryParameters3D.create(Vector3(13.651,0.6,2.9), Vector3(13.651,0.6,3.5), 1),
	]
	for query_index in range(guard_queries.size()):
		var guard_hit := get_world_3d().direct_space_state.intersect_ray(guard_queries[query_index])
		if guard_hit.is_empty() or not bool((guard_hit.collider as Node).get_meta("stair_guard_collision", false)):
			failures.append("railing blocker ray %d did not hit a stair guard" % query_index)
	var landing_passage_query := PhysicsRayQueryParameters3D.create(Vector3(11.501,0.6,2.5), Vector3(11.501,0.6,4.0), 1)
	var landing_passage_hit := get_world_3d().direct_space_state.intersect_ray(landing_passage_query)
	if not landing_passage_hit.is_empty() and bool((landing_passage_hit.collider as Node).get_meta("stair_guard_collision", false)):
		failures.append("upper landing stair entrance is blocked by railing collision")
	for passage_x in [9.75, 13.25]:
		var edge_passage_query := PhysicsRayQueryParameters3D.create(Vector3(passage_x,0.6,2.5), Vector3(passage_x,0.6,4.0), 1)
		var edge_passage_hit := get_world_3d().direct_space_state.intersect_ray(edge_passage_query)
		if not edge_passage_hit.is_empty() and bool((edge_passage_hit.collider as Node).get_meta("stair_guard_collision", false)):
			failures.append("upper landing usable stair width is blocked at x=%.2f" % passage_x)
	var samples := 0
	# 全宽平台、两跑坡面及每条接缝附近都必须连续命中同一个承重体。
	for xi in range(1, 150):
		var x := xi * 0.1
		for zi in range(-24, 275):
			var z := zi * 0.1
			var heights: Array[float] = []
			if z <= TowerGeometry3D.STAIR_RUN_START_M:
				heights = [0.0, -12.0]
			elif z >= TowerGeometry3D.STAIR_RUN_END_M:
				heights = [-6.0]
			elif absf(x - TowerGeometry3D.STAIR_UPPER_LANE_OFFSET_M) < 2.99:
				heights = [-6.0 * (z - TowerGeometry3D.STAIR_RUN_START_M) / 15.0]
			elif absf(x - TowerGeometry3D.STAIR_LOWER_LANE_OFFSET_M) < 2.99:
				heights = [-12.0 + 6.0 * (z - TowerGeometry3D.STAIR_RUN_START_M) / 15.0]
			for y in heights:
				var query := PhysicsRayQueryParameters3D.create(Vector3(x,y+0.1,z), Vector3(x,y-0.1,z), 1)
				query.exclude = guard_rids
				var hit := get_world_3d().direct_space_state.intersect_ray(query)
				samples += 1
				if hit.is_empty() or absf(hit.position.y - y) > 0.001:
					if failures.size() < 10:
						failures.append("support gap at %s" % Vector3(x,y,z))
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	actor.floor_snap_length = 0.4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.43
	capsule.height = 1.8
	var actor_shape := CollisionShape3D.new()
	actor_shape.shape = capsule
	actor_shape.position.y = 0.9
	actor.add_child(actor_shape)
	add_child(actor)
	# 转向点留在平台护栏内侧；护栏中心位于 z=21.0071，角色胶囊不应穿到其中心线。
	var route: Array[Vector3] = [Vector3(11.501,0,0), Vector3(11.501,0,3.1203), Vector3(11.501,-6,18.1203), Vector3(11.501,-6,21.0071), Vector3(3.501,-6,21.0071), Vector3(3.501,-6,18.1203), Vector3(3.501,-12,3.1203), Vector3(3.501,-12,0)]
	Engine.time_scale = 6.0
	for direction in range(2):
		if direction == 1:
			route.reverse()
		actor.position = route[0] + Vector3.UP * 0.03
		actor.velocity = Vector3.ZERO
		for target in route.slice(1):
			var reached := false
			for frame in range(900):
				await get_tree().physics_frame
				var offset: Vector3 = target - actor.position
				var planar := Vector3(offset.x,0,offset.z)
				if planar.length() < 0.18 and absf(offset.y) < 0.15:
					reached = true
					break
				actor.velocity.x = planar.normalized().x * 3.0
				actor.velocity.z = planar.normalized().z * 3.0
				actor.velocity.y -= 24.0 * get_physics_process_delta_time()
				actor.move_and_slide()
			if not reached:
				failures.append("walk stalled direction=%d target=%s actual=%s" % [direction,target,actor.position])
				break
	Engine.time_scale = 1.0
	actor.queue_free()
	support.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print("STAIR_UNIFIED_SUPPORT samples=%d failures=%d" % [samples, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
