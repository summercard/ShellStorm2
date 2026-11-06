extends Node

const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")
const GATE_ID := "ENV-EXP03-BOSS-DOOR-RITUAL"
const FRAME_ID := "ENV-EXP03-MANOR-WALL-DOOR-BOSS"
const REWARD_ID := "ENV-EXP03-ROOM-REWARD-15X15"
const SMALL_SHOP_ID := "ENV-EXP03-ROOM-SHOP-20X15"
const ART_CONTRACT := preload("res://src/world3d/RoomArtLayoutContract.gd")
const ROOM_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms/"
const SEEDS := [77003244, 100990, 42, 123456, 7, 99, 2026, 31415, 55555, 808080,
	9173, 6060, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13]

var _failures := 0
var _checks := 0
var _flows := {}
var _shop_sizes := {}
var _seed := 0
var _passage_shapes_checked := {}


func _ready() -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	_verify_furnishing_sources()
	var shot_dir := OS.get_environment("SS_EXP03_SPECIAL_SHOT_DIR")
	var seeds := SEEDS if shot_dir.is_empty() else [SEEDS.front()]
	for seed in seeds:
		_seed = seed
		var tower := LEVEL.instantiate() as TowerDescent3D
		tower.set("test_mode", true)
		tower.set("run_seed_override", seed)
		add_child(tower)
		for frame in range(20):
			await get_tree().process_frame
		# Keep every inspected detail region active while querying distant rooms.
		# Normal camera streaming otherwise unloads their navigation on the next frame.
		tower.set_process(false)
		var rooms := tower.get("_room_by_id") as Dictionary
		for value in rooms.values():
			var room := value as DungeonRoom3D
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
		for frame in range(3):
			await get_tree().process_frame
			await get_tree().physics_frame
		NavigationServer3D.map_force_update(tower.get_world_3d().navigation_map)
		for room_id in ["n03", "n06"]:
			_check_passage(tower, rooms.get(room_id) as DungeonRoom3D, room_id)
		var floor_plan := (tower.get("_floor_plan_snapshots") as Dictionary).get(0, {}) as Dictionary
		var flow_id := str(floor_plan.get("flow_id", ""))
		_flows[flow_id] = true
		_check(not flow_id.is_empty(), "runtime must assemble a flow")
		var reward := _check_reward(rooms.get("reward_01") as DungeonRoom3D)
		_check_reward(rooms.get("reward_02") as DungeonRoom3D)
		var shop := rooms.get("shop") as DungeonRoom3D
		await _check_shop(tower, shop, flow_id)
		var gate := await _check_gate(rooms)
		if not shot_dir.is_empty() and seed == SEEDS.front() and gate != null and reward != null:
			await _capture(tower, rooms, reward, shop, gate, shot_dir)
			await _capture_passages(tower, rooms, shot_dir)
		print("SPECIAL_ROOM_SEED %d %s shop=%s" % [seed, flow_id, str(shop.get_dimensions()) if shop != null else "missing"])
		tower.queue_free()
		await get_tree().process_frame
	if shot_dir.is_empty():
		_check(_flows.size() == 6 and not _flows.has(""), "all six flows observed")
		_check(_shop_sizes.size() == 2, "both shop sizes observed")
	print("SPECIAL_ROOM_RELAYOUT %s checks=%d failures=%d flows=%d" % ["OK" if _failures == 0 else "FAIL", _checks, _failures, _flows.size()])
	get_tree().quit(0 if _failures == 0 else 1)


func _verify_furnishing_sources() -> void:
	var reward := (load(ROOM_DIR + "storage_15x15_94b04661833c_3e5f15.tscn") as PackedScene).instantiate() as Node3D
	var rug := reward.get_node_or_null("ArtComponents/AuthoredSalon/ChestRug") as Node3D
	_check(rug != null and Vector2(rug.position.x, rug.position.z).is_zero_approx(), "treasury rug centered")
	var rug_count := 0
	var sofa_count := 0
	for fixture in reward.find_children("*", "Node3D", true, false):
		var path := fixture.scene_file_path
		if not path.ends_with("_root_top3d.tscn"):
			continue
		rug_count += int(path.contains("/manor_rug_"))
		sofa_count += int(path.contains("/manor_sofa/"))
	_check(rug_count == 1 and sofa_count == 0, "treasury has one rug and no sofa")
	var wall_collections := reward.get_node_or_null("ArtComponents/WallCollections")
	_check(wall_collections != null and wall_collections.get_child_count() == 18, "treasury inherits safe-room wall collections")
	_check_furnishing_clearance(reward)
	reward.free()
	var shop := (load(ROOM_DIR + "merchant_20x15_327ac0ee6b3c_d77c54.tscn") as PackedScene).instantiate() as Node3D
	for node_name in ["WestCounter", "EastCounter", "WestBackStockShelf", "EastBackStockShelf", "WestWaitingBench", "EastWaitingBench", "QueueCarpet"]:
		_check(shop.has_node("ArtComponents/" + node_name), "shop fixture " + node_name)
	_check_furnishing_clearance(shop)
	shop.free()


func _check_furnishing_clearance(room: Node3D, ports: Array = []) -> void:
	var issues := ART_CONTRACT.furnishing_conflicts(room, ports)
	_check(issues.is_empty(), "%s door approaches clear: %s" % [room.get_meta("asset_id", room.name), str(issues)])


func _check_passage(tower: TowerDescent3D, room: DungeonRoom3D, room_id: String) -> void:
	if not _check(room != null, "passage exists " + room_id):
		return
	var dim := room.get_dimensions()
	_check(dim == (Vector2(40, 30) if room_id == "n03" else Vector2(30, 40)), "passage orientation " + room_id)
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if not _check(art != null and art.get_meta("traversal_route_width_m", 0.0) == 5.0, "passage art loaded " + room_id):
		return
	_check((room.get_meta("furnishing_navigation_polygons", []) as Array).size() > 50, "passage navigation follows individual furniture " + room_id)
	_check(not room.has_meta("walkable_navigation_polygons"), "furniture does not carve room ownership " + room_id)
	_check_furnishing_clearance(art, room.connection_ports)
	var bays := art.get_node("ArtComponents/PerimeterBays")
	_check(bays.get_child_count() >= 10, "unused wall bays remain closed " + room_id)
	var waves := tower.call("_spawn_box_waves", room, 0, 1) as Array
	_check(not waves.is_empty(), "passage retains monster wave " + room_id)
	for wave in waves:
		for config in wave:
			var point := room.to_local((config as Dictionary).get("spawn_position", Vector3.INF) as Vector3)
			_check(point.is_finite() and _on_passage_navigation(room, point), "enemy placed on passage " + room_id + " " + str(point))
	var first_gate := room.to_global(_port_inside(room.connection_ports.front(), dim))
	for port in room.connection_ports:
		var target := room.to_global(_port_inside(port, dim))
		var route := NavigationServer3D.map_get_path(room.get_world_3d().navigation_map, first_gate, target, true)
		if route.is_empty() or route[0].distance_to(first_gate) >= .1 or route[-1].distance_to(target) >= .1:
			print("PORT_ROUTE_DEBUG ", first_gate, " target=", target, " path=", route)
		_check(not route.is_empty() and route[0].distance_to(first_gate) < .1 and route[-1].distance_to(target) < .1, "actual doorway connects to main route " + room_id + " " + str(port.get("side")) + str(port.get("lane_m")))
	if _passage_shapes_checked.has(dim):
		return
	_passage_shapes_checked[dim] = true
	var path_start := room.to_global(_port_inside(room.connection_ports.front(), dim))
	var path_end := room.to_global(_port_inside(room.connection_ports.back(), dim))
	var navigation := NavigationServer3D.map_get_path(room.get_world_3d().navigation_map, path_start, path_end, false)
	print("PASSAGE_NAV ", dim, " path_points=", navigation.size())
	_check(navigation.size() >= 2, "passage navigation connects actual gates")
	for index in range(1, navigation.size()):
		var segment_start := navigation[index - 1]
		var segment_end := navigation[index]
		for sample in range(11):
			_check(_on_passage_navigation(room, room.to_local(segment_start.lerp(segment_end, sample / 10.0))), "navigation avoids furniture")
	var furnishings := art.get_node("ArtComponents/ReadingAlcoves")
	_check(furnishings.get_child_count() == 70, "passage retains four manor compositions, library spine and entry endcaps")
	_check(furnishings.has_node("Alcove_-1_-1_Rug") and furnishings.has_node("Alcove_1_-1_Sofa"), "passage rug seating combinations")
	var blocks: Array[Rect2] = []
	for value in art.find_children("*", "CollisionShape3D", true, false):
		var shape := value as CollisionShape3D
		var body := shape.get_parent() as StaticBody3D
		if shape.disabled or shape.shape == null or body == null or body.collision_layer & 1 == 0:
			continue
		if ART_CONTRACT.is_structure(art, shape):
			continue
		var bounds := room.global_transform.affine_inverse() * shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
		if bounds.end.y > .3:
			blocks.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)))
	var grid := {}
	var step := .2
	for ix in range(int(dim.x / step)):
		for iz in range(int(dim.y / step)):
			var point := Vector2(-dim.x * .5 + step * .5 + ix * step, -dim.y * .5 + step * .5 + iz * step)
			if absf(point.x) > dim.x * .5 - .45 or absf(point.y) > dim.y * .5 - .45:
				continue
			var blocked := false
			for rect in blocks:
				if rect.grow(.45).has_point(point):
					blocked = true
					break
			if not blocked:
				grid[Vector2i(ix, iz)] = point
	var entry := room.to_local(path_start)
	var start := Vector2i(roundi((entry.x + dim.x * .5 - step * .5) / step), roundi((entry.z + dim.y * .5 - step * .5) / step))
	if not _check(grid.has(start), "passage initial sample accessible"):
		return
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	var widest := 0.0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var point := grid[cell] as Vector2
		var radius := minf(dim.x * .5 - absf(point.x), dim.y * .5 - absf(point.y))
		for rect in blocks:
			var nearest := point.clamp(rect.position, rect.end)
			radius = minf(radius, point.distance_to(nearest))
		widest = maxf(widest, radius * 2)
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + delta
			if grid.has(neighbor) and not reached.has(neighbor):
				reached[neighbor] = true
				queue.append(neighbor)
	var width_upper_bound := widest + sqrt(2.0) * step
	_check(width_upper_bound <= 7.0, "passage open width %.3f m, including grid bound %.3f m" % [widest, width_upper_bound])
	for port in room.connection_ports:
		var side := str(port["side"])
		var lane := float(port["lane_m"])
		var point := Vector2(lane, -dim.y * .5 + 1.25) if side == "north" else Vector2(lane, dim.y * .5 - 1.25) if side == "south" else Vector2(-dim.x * .5 + 1.25, lane) if side == "west" else Vector2(dim.x * .5 - 1.25, lane)
		var cell := Vector2i(roundi((point.x + dim.x * .5 - step * .5) / step), roundi((point.y + dim.y * .5 - step * .5) / step))
		_check(reached.has(cell), "passage reaches legal gate %s %.1f" % [side, lane])
	for bay in bays.get_children():
		var rect := bay.get_meta("perimeter_bay_rect_m") as Array
		var point := Vector2((rect[0]+rect[2])*.5, (rect[1]+rect[3])*.5)
		var cell := Vector2i(roundi((point.x + dim.x * .5 - step * .5) / step), roundi((point.y + dim.y * .5 - step * .5) / step))
		_check(not reached.has(cell), "closed display bay cannot be entered " + str(bay.name))
	print("PASSAGE_PHYSICS ", dim, " accessible_cells=", reached.size(), " widest=", widest, " grid_upper_bound=", width_upper_bound, " furniture_shapes=", blocks.size())


func _on_passage_navigation(room: DungeonRoom3D, point: Vector3) -> bool:
	for polygon in room.get_meta("furnishing_navigation_polygons", []):
		var points := PackedVector2Array()
		for p in polygon:
			points.append(Vector2(p[0], p[2]))
		if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), points):
			return true
	return false


func _port_inside(port: Dictionary, dim: Vector2) -> Vector3:
	var lane := float(port.get("lane_m", 0.0))
	match str(port.get("side", "")):
		"north": return Vector3(lane, .08, -dim.y * .5 + 1.25)
		"south": return Vector3(lane, .08, dim.y * .5 - 1.25)
		"west": return Vector3(-dim.x * .5 + 1.25, .08, lane)
		_: return Vector3(dim.x * .5 - 1.25, .08, lane)


func _capture_passages(tower: TowerDescent3D, rooms: Dictionary, output: String) -> void:
	for world in tower.find_children("*", "WorldEnvironment", true, false):
		if world.environment != null:
			world.environment = world.environment.duplicate()
			world.environment.fog_enabled = false
			world.environment.volumetric_fog_enabled = false
	var camera := Camera3D.new()
	tower.add_child(camera)
	var light := OmniLight3D.new()
	light.light_energy = 10.0
	light.omni_range = 60.0
	light.omni_attenuation = .7
	light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	tower.add_child(light)
	for room_id in ["n03", "n06"]:
		var room := rooms[room_id] as DungeonRoom3D
		tower.player.global_position = room.global_position + Vector3(0, .1, -room.get_dimensions().y * .5 + 2.5)
		for frame in range(4):
			await get_tree().physics_frame
		room.set_room_light_on(true)
		light.global_position = room.global_position + Vector3(0, 8, 0)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 46.0
		camera.global_position = room.global_position + Vector3(0, 40, 0)
		camera.look_at(room.global_position, Vector3.FORWARD)
		camera.make_current()
		await _save_frame(output.path_join(room_id + "_top.png"), true)
		camera.global_position = room.global_position + Vector3(11, 37, 17)
		camera.look_at(room.global_position)
		await _save_frame(output.path_join(room_id + "_angle.png"), true)
	light.queue_free()
	camera.queue_free()


func _check_reward(room: DungeonRoom3D) -> DungeonRoom3D:
	if not _check(room != null, "reward room exists"):
		return null
	_check(room.get_dimensions() == Vector2(15, 15), "%s 15×15" % room.room_id)
	_check(room.authored_layout_peaceful, "%s remains peaceful" % room.room_id)
	var art := room.get_node_or_null("AuthoredLayoutArtRoot")
	_check(art != null and art.get_meta("asset_id", "") == REWARD_ID, "%s compact art loaded" % room.room_id)
	var chests := room.get_treasure_chests()
	if _check(chests.size() == 1, "%s one chest" % room.room_id):
		var local := room.to_local(chests[0].global_position)
		_check(Vector2(local.x, local.z).length() < 0.05, "%s chest centered" % room.room_id)
	return room


func _check_shop(tower: TowerDescent3D, room: DungeonRoom3D, flow_id: String) -> void:
	if not _check(room != null, "shop exists"):
		return
	var size := room.get_dimensions()
	var large := flow_id in ["flow_02", "flow_04"]
	_shop_sizes[size] = true
	_check(size == (Vector2(30, 40) if large else Vector2(20, 15)), "shop size by flow")
	var art := room.get_node_or_null("AuthoredLayoutArtRoot")
	_check(art != null and (large or art.get_meta("asset_id", "") == SMALL_SHOP_ID), "shop art loaded")
	var station := room.get_service_station("merchant")
	if not _check(station != null and room.authored_layout_peaceful, "merchant remains present and peaceful"):
		return
	var player := tower.get("player") as Player3D
	if not _check(player != null, "merchant interaction has a player"):
		return
	player.global_position = station.global_position + Vector3(0, 0.1, 1.0)
	for frame in range(3):
		await get_tree().physics_frame
	_check(not station.get_interaction_candidate(player).is_empty(), "merchant interaction can be reached")


func _check_gate(rooms: Dictionary) -> RoomDoor3D:
	var boss := rooms.get("boss") as DungeonRoom3D
	if not _check(boss != null, "arena exists"):
		return null
	var boss_ports: Array[Dictionary] = []
	for value in boss.connection_ports:
		var port := value as Dictionary
		if not str(port.get("door_visual_scene", "")).is_empty():
			boss_ports.append(port)
	if not _check(boss_ports.size() == 1, "only the arena entry is special"):
		return null
	var port := boss_ports[0]
	var peer := rooms.get(str(port.get("target_room_id", ""))) as DungeonRoom3D
	if not _check(peer != null and peer.room_id != "exit", "special gate faces the approach"):
		return null
	var peer_port := peer.get_connection_port_towards("boss")
	_check(float(port.get("door_width_m", 0)) == 3.0 and float(peer_port.get("door_width_m", 0)) == 3.0, "both sides declare 3.0 m")
	for room in [boss, peer]:
		var frames := 0
		for node in room.find_children("DoorWall_*", "Node3D", true, false):
			if node.get_meta("asset_id", "") == FRAME_ID:
				frames += 1
		_check(frames == 1, "%s special door frame loaded once" % room.room_id)
	var gate := boss.get_door_node_towards(peer.room_id)
	if not _check(gate != null and gate == peer.get_door_node_towards("boss"), "one shared gate leaf"):
		return null
	_check(gate.get_snapshot().get("visual_asset_id") == GATE_ID, "steel panel visual loaded")
	gate.set_proximity_target(null)
	gate.set_open(false, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_gate_ray(gate, 1.25).get("collider") == gate, "closed gate blocks at x=1.25 m")
	gate.set_open(true, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for lateral in [-1.25, 0.0, 1.25]:
		_check(_gate_ray(gate, lateral).is_empty(), "open gate clears x=%.2f m" % lateral)
	_check(not _gate_ray(gate, 1.65).is_empty(), "pier blocks beside opening")
	return gate


func _gate_ray(gate: RoomDoor3D, lateral: float) -> Dictionary:
	var base := gate.to_global(Vector3(lateral, 0.8, 0))
	var delta := gate.global_basis.z * 0.75
	var query := PhysicsRayQueryParameters3D.create(base - delta, base + delta, 1)
	return gate.get_world_3d().direct_space_state.intersect_ray(query)


func _capture(tower: TowerDescent3D, rooms: Dictionary, reward: DungeonRoom3D,
		shop: DungeonRoom3D, gate: RoomDoor3D, output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var camera := Camera3D.new()
	tower.add_child(camera)
	var review_light := OmniLight3D.new()
	review_light.light_color = Color(1.0, 0.9, 0.78)
	review_light.light_energy = 3.0
	review_light.omni_range = 24.0
	review_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	tower.add_child(review_light)
	var player := tower.get("player") as Player3D
	for layer in tower.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).hide()
	for room in [reward, shop]:
		player.global_position = room.global_position + Vector3(0, 0.1, 4)
		for frame in range(6):
			await get_tree().physics_frame
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
		if room == reward:
			_check(not room.get_treasure_chests().is_empty(), "treasury chest present in captured room")
		room.set_room_light_on(true)
		review_light.light_energy = 10.0 if room == shop else 3.5
		review_light.global_position = room.global_position + Vector3(0, 5.5, 1)
		var view_wall := tower.get("_flow_view_wall_root") as Node3D
		if view_wall != null:
			view_wall.hide()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 22.0
		camera.global_position = room.global_position + Vector3(0, 17.0, 0)
		camera.look_at(room.global_position, Vector3.FORWARD)
		camera.make_current()
		await _save_frame(output.path_join("%s.png" % room.room_id), true)
		camera.global_position = room.global_position + Vector3(3.5, 16, 6)
		camera.look_at(room.global_position)
		await _save_frame(output.path_join("%s_angle.png" % room.room_id), true)
	var boss := rooms["boss"] as DungeonRoom3D
	var inward := gate.global_basis.z
	if inward.dot(boss.global_position - gate.global_position) > 0.0:
		inward = -inward
	player.global_position = gate.global_position + inward * 4.3 + Vector3.UP * 0.1
	for frame in range(6):
		await get_tree().physics_frame
	var current_room := rooms.get(tower.get("_current_room_id")) as DungeonRoom3D
	if current_room != null:
		current_room.set_room_light_on(true)
	review_light.light_energy = 0.8
	review_light.global_position = gate.global_position + inward * 3.2 + Vector3.UP * 2.4
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 51.0
	camera.global_position = gate.global_position + inward * 5.0 + Vector3.UP * 2.9
	camera.look_at(gate.global_position + Vector3.UP * 1.7)
	camera.make_current()
	gate.set_proximity_target(null)
	gate.set_open(false, true)
	await _save_frame(output.path_join("boss_gate_closed.png"))
	gate.set_open(true, true)
	await _save_frame(output.path_join("boss_gate_open.png"))
	camera.queue_free()
	review_light.queue_free()


func _save_frame(path: String, reveal_room := false) -> void:
	for frame in range(3):
		await get_tree().process_frame
	if reveal_room:
		for wall in find_children("FlowViewWalls*", "Node3D", true, false):
			(wall as Node3D).hide()
	for node in find_children("*", "Label3D", true, false):
		(node as Label3D).hide()
	for node in find_children("SpeechBubble*", "Node3D", true, false):
		(node as Node3D).hide()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "saved %s" % path.get_file())


func _check(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("SPECIAL_ROOM_FAIL seed=%d %s" % [_seed, message])
	return ok
