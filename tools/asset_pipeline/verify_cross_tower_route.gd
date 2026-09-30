extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var tower: Node3D = load("res://scenes/TowerDescent3D.tscn").instantiate()
	tower.set("test_mode", true)
	# No minimap in this acceptance run; don't touch the user's editor or saves.
	var minimap := tower.get_node_or_null("HUD/DungeonMinimap3D")
	if minimap != null:
		minimap.process_mode = Node.PROCESS_MODE_DISABLED
		minimap.hide()
	root.add_child(tower)
	for _frame in range(30):
		await physics_frame
	var route := tower.get_node("Blocks/Rooftop/CrossTowerRoute") as Node3D
	var stage := tower.get_node("Blocks/Rooftop/Floor_100")
	check(is_equal_approx(float(stage.get("north_bridge_opening_x")), 20.0), "authorized north opening")
	check(int(stage.call("get_outer_straight_slot_count")) == 67, "exactly one of 68 parapet straight slots removed")
	var slot_found := false
	for slot: Transform3D in stage.call("get_outer_straight_slot_transforms"):
		if absf(slot.origin.x - 20.0) < 0.01 and slot.origin.z < -34:
			slot_found = true
	check(not slot_found, "opening has no parapet visual slot")
	check(route.get_node("Tower2").scale == Vector3.ONE, "tower2 unscaled")
	check(route.get_node("Tower3").scale == Vector3.ONE, "tower3 unscaled")
	check(route.get_node("Tower2").find_children("*", "CollisionShape3D", true, false).is_empty(), "tower2 inaccessible visual only")
	check(not route.get_node("Tower3/support/lower_rail_0").visible, "tower3 entry rail removed locally")
	check(route.find_children("*", "MultiMeshInstance3D", true, false).is_empty(), "route uses ordinary prefab instances only")
	var jib_count := 0
	for child in route.get_node("Bridge").get_children():
		if str(child.get_meta("asset_id", "")) == "ENV-OPENWORLD-TOWER02-CRANE-00-JIB":
			jib_count += 1
			check((child as Node3D).scale == Vector3.ONE, "crane jib remains native size")
	check(jib_count == 4, "two bridge spans use four original crane jib sections")
	var space := tower.get_world_3d().direct_space_state
	var opening_ray := PhysicsRayQueryParameters3D.create(Vector3(20, 0.4, -33), Vector3(20, 0.4, -37), 1)
	check(space.intersect_ray(opening_ray).is_empty(), "north opening collision clear")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(45, 2, -90), Vector3(45, -20, -90), 1)).is_empty(), "no support on lower tower2 roof")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10, 0.4, -33), Vector3(10, 0.4, -37), 1)).is_empty(), "neighboring main parapet still blocks")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20, 0.8, -50), Vector3(24.5, 0.8, -50), 1)).is_empty(), "bridge guard blocks sideways exit")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20, 0.4, -96.5), Vector3(25, 0.4, -98.5), 1)).is_empty(), "outer bend guard closes the angled joint")
	var waypoints: Array[Vector3] = [Vector3(20, 0, -30), Vector3(20, 0, -96.5), Vector3(-12, 0, -151.925626), Vector3(-12, 0, -161.925626)]
	for index in range(waypoints.size() - 1):
		var a := waypoints[index]
		var b := waypoints[index + 1]
		for sample in range(int(a.distance_to(b)) * 2 + 1):
			var point := a.lerp(b, float(sample) / float(int(a.distance_to(b)) * 2))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point - Vector3.UP, 1))
			check(not hit.is_empty() and absf(hit.get("position", Vector3.INF).y) < 0.02, "supported route sample %d/%d" % [index, sample])
	var player := tower.get("player") as Node3D
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		for body: CollisionObject3D in player.find_children("*", "CollisionObject3D", true, false):
			body.collision_layer = 0
		if player is CollisionObject3D:
			(player as CollisionObject3D).collision_layer = 0
	var walker := CharacterBody3D.new()
	walker.name = "RouteAcceptanceWalker"
	walker.collision_layer = 2
	walker.collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.5
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.75
	walker.add_child(shape)
	tower.add_child(walker)
	var guard_sweep := PhysicsShapeQueryParameters3D.new()
	guard_sweep.shape = capsule
	guard_sweep.collision_mask = 1
	guard_sweep.transform.origin = Vector3(20, 0.76, -96.5)
	guard_sweep.motion = Vector3(5, 0, -2)
	var fractions := space.cast_motion(guard_sweep)
	check(fractions.size() == 2 and fractions[0] < 0.9, "player capsule cannot escape outer bend")
	walker.global_position = waypoints[0] + Vector3.UP * 0.03
	for index in range(1, waypoints.size()):
		var reached := false
		for _frame in range(1800):
			await physics_frame
			var delta := waypoints[index] - walker.global_position
			delta.y = 0
			if delta.length() < 0.15:
				reached = true
				break
			var direction := delta.normalized()
			walker.velocity = direction * 12
			walker.velocity.y = -2
			walker.move_and_slide()
			if walker.global_position.y < -0.2:
				break
		check(reached, "capsule walks to waypoint %d: %s" % [index, walker.global_position])
	check(walker.global_position.y >= -0.02, "arrival aligned with main roof")
	if player != null:
		player.global_position = walker.global_position + Vector3.UP * 0.03
		player.process_mode = Node.PROCESS_MODE_INHERIT
		for _frame in range(10):
			await physics_frame
		check(player.global_position.distance_to(waypoints[-1]) < 0.3, "actual player remains on tower3 rooftop")
		check(int(tower.call("_runtime_current_floor_index")) == 0, "outside rooftop route retains 100F runtime ownership")
		player.process_mode = Node.PROCESS_MODE_DISABLED
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 1000)
		var env := (tower.get_node("WorldEnvironment") as WorldEnvironment).environment.duplicate() as Environment
		env.fog_enabled = false
		env.ambient_light_energy = 0.6
		(tower.get_node("WorldEnvironment") as WorldEnvironment).environment = env
		var cam := Camera3D.new()
		tower.add_child(cam)
		cam.global_position = Vector3(-150, 190, 75)
		cam.look_at(Vector3(0, -15, -95))
		cam.fov = 55
		cam.current = true
		cam.far = 700
		for _frame in range(15):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("res://assets/art/environments/open_world/runtime/cross_tower_route/qa_overview.png")
		cam.global_position = Vector3(36.5, 22, -9)
		cam.look_at(Vector3(20, 0, -44))
		for _frame in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/art/environments/open_world/runtime/cross_tower_route/qa_main_exit.png")
	var report := {"checks": checks, "failures": failures, "walker_position": walker.global_position, "renderer": DisplayServer.get_name(), "scene_sha256": FileAccess.get_sha256("res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn")}
	var output := FileAccess.open("res://assets/art/environments/open_world/runtime/cross_tower_route/acceptance.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ") + "\n")
	output.close()
	print("CROSS_TOWER_ROUTE_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
