extends Node
## 一次性探针：看「新游戏开场 = 98F 主人的办公室」这条路径实际装配成什么。
## 只打印运行时真值，不做断言；断言写进 verify_block00_floor98_assembly.gd。

const SEED := 990098


func _ready() -> void:
	await _probe("A_opening_on", true)
	await _probe("B_opening_off", false)
	print("PROBE_NEW_GAME_OPENING_DONE")
	get_tree().quit(0)


func _probe(tag: String, force_opening: bool) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	tower.force_new_game_opening_for_test = force_opening
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for index in range(8):
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout

	var player = tower.player
	var current_room_id := str(tower.get("_current_room_id"))
	print("PROBE[", tag, "] current_room_id=", current_room_id)
	print("PROBE[", tag, "] player_pos=", player.global_position)
	print("PROBE[", tag, "] generated=", str(tower.get("_generated_floor_indices")),
		" commit_reasons=", str(tower.get("_floor_plan_commit_reasons")))
	print("PROBE[", tag, "] loaded_floors=", str(tower.get("_loaded_floor_indices")),
		" floor_stages=", str((tower.get("_floor_stages") as Dictionary).keys()))
	print("PROBE[", tag, "] floor_rooms=", str(tower.get("_floor_room_ids")))
	print("PROBE[", tag, "] floor_label=", str(tower.room_label.text),
		" status=", str(tower.status_label.text))
	var room_by_id := tower.get("_room_by_id") as Dictionary
	for room_id in ["floor_01_entry", "floor_01_hub", "floor_01_main_02", "floor_01_exit"]:
		var room := room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("PROBE[", tag, "] room ", room_id, " = null")
			continue
		var dims := room.get_dimensions()
		print("PROBE[", tag, "] room ", room_id,
			" pos=", room.global_position,
			" dims=", dims,
			" type=", room.room_type,
			" authored=", room.authored_layout_room_id,
			" peaceful=", room.authored_layout_peaceful,
			" local_player=", room.to_local(player.global_position))

	# —— 楼层舞台权威表：名字 / floor_index / 世界 Y / 被挖的楼梯侧 ——
	var stages := tower.get("_floor_stages") as Dictionary
	for index in stages.keys():
		var stage = stages[index]
		if stage == null or not is_instance_valid(stage):
			print("PROBE[", tag, "] stage idx=", index, " = INVALID")
			continue
		print("PROBE[", tag, "] stage idx=", index,
			" name=", stage.name,
			" meta_index=", stage.get_meta("floor_index", -999),
			" world_y=%.3f" % stage.global_position.y,
			" stair_hole_sides=", str(stage.get("stair_hole_sides")))

	# —— 竖直边声明：谁声明了下行楼梯、在哪一侧 ——
	print("PROBE[", tag, "] declared_edges:")
	for declaration in tower.get("_declared_edges"):
		if str(declaration.get("kind", "")) != "vertical":
			continue
		var room_index := tower.get("_room_floor_index") as Dictionary
		print("PROBE[", tag, "]   vertical a=", declaration.get("a"),
			"(f", room_index.get(str(declaration.get("a")), -1), ")",
			" b=", declaration.get("b"),
			"(f", room_index.get(str(declaration.get("b")), -1), ")",
			" side=", declaration.get("side"))

	# 承重诊断：从房间中心正上方打一条向下的射线，看玩家脚下到底是什么、在哪一层。
	var space := tower.get_world_3d().direct_space_state
	var from := Vector3(-32.5, -24.0 + 3.0, 5.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -40.0, 0.0))
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	print("PROBE[", tag, "] ray_room_center from=", from, " hit=",
		str(hit.get("position", "MISS")), " collider=",
		str((hit.get("collider") as Node).get_path()) if hit.has("collider") else "-")

	# 逐列承重扫描：以主人的办公室真实足迹（pos -32.5,5 / dims 15x20）为准，
	# 1m 一格扫出「有楼板(W) / 别的碰撞(X) / 空(.)」的地图（行 = x，列 = z）。
	if tag == "A_opening_on":
		_scan_support(space, tag, room_by_id, "floor_01_exit", -7.0, 7.0, -9.0, 9.0)
		# 西侧下行通道：办公室西墙 x=-40 以西到楼梯井，看门后到底有没有落脚面。
		_scan_support_raw(space, tag, -50.0, -36.0, -4.0, 12.0)
		# 楼梯井细扫（1m，打名字）：确认下行落脚面到底从哪一行 z 开始。
		_scan_stairwell_detail(space, tag)
		_dump_stair_connector(tower, tag)
		await _probe_descent_route(tower, tag, player)

	# 静止判定：再等一段时间，看玩家是不是还在往下掉。
	for index in range(60):
		await get_tree().physics_frame
	print("PROBE[", tag, "] after_60_more_physics_frames player_pos=", player.global_position,
		" velocity=", player.velocity)

	remove_child(tower)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _scan_support(
	space: PhysicsDirectSpaceState3D,
	tag: String,
	room_by_id: Dictionary,
	room_id: String,
	x_from: float,
	x_to: float,
	z_from: float,
	z_to: float
) -> void:
	var room := room_by_id.get(room_id) as DungeonRoom3D
	print("PROBE[", tag, "] support_map room=", room_id,
		" pos=", room.global_position, " dims=", room.get_dimensions(),
		"（行 = 房间局部 x，列 = 房间局部 z）")
	_scan_support_raw(
		space, tag, room.global_position.x + x_from, room.global_position.x + x_to,
		room.global_position.z + z_from, room.global_position.z + z_to,
		room.global_position.y
	)


func _scan_support_raw(
	space: PhysicsDirectSpaceState3D,
	tag: String,
	x_from: float,
	x_to: float,
	z_from: float,
	z_to: float,
	floor_y: float = -24.0
) -> void:
	print("PROBE[", tag, "] scan x[%.1f,%.1f] z[%.1f,%.1f]" % [x_from, x_to, z_from, z_to])
	var x := x_from
	while x <= x_to + 0.001:
		var line := "PROBE[%s]   x=%+7.1f |" % [tag, x]
		var z := z_from
		while z <= z_to + 0.001:
			var world := Vector3(x, floor_y + 8.0, z)
			var probe_query := PhysicsRayQueryParameters3D.create(
				world, world + Vector3(0.0, -12.5, 0.0)
			)
			probe_query.collide_with_areas = false
			var probe_hit := space.intersect_ray(probe_query)
			var mark := "."
			if probe_hit.has("position"):
				var collider_path := str((probe_hit["collider"] as Node).get_path())
				mark = "W" if collider_path.contains("FloorSupport") else "X"
			line += mark
			z += 2.0
		print(line)
		x += 2.0


## 楼梯井细扫：1m 一格，命中就打节点名 —— 用来判「门后那一段有没有可走面」。
func _scan_stairwell_detail(space: PhysicsDirectSpaceState3D, tag: String) -> void:
	print("PROBE[", tag, "] stairwell_detail（x 行 / z 列，值为命中面世界 y 与该节点短名）")
	var z := -2.0
	while z <= 12.0:
		var line := "PROBE[%s]   z=%+5.1f |" % [tag, z]
		var x := -47.0
		while x <= -37.0:
			var world := Vector3(x, -20.0, z)
			var query := PhysicsRayQueryParameters3D.create(world, world + Vector3(0.0, -18.0, 0.0))
			query.collide_with_areas = false
			var hit := space.intersect_ray(query)
			if hit.has("position"):
				var position := hit["position"] as Vector3
				var collider := hit["collider"] as Node
				var short_name := str(collider.name) if collider != null else "?"
				line += " [%6.2f %s]" % [position.y, short_name]
			else:
				line += " [  --  空]"
			x += 1.0
		print(line)
		z += 1.0


## 竖直楼梯连接器自身的登记值：可走碰撞面有几个、被摆到哪里。
func _dump_stair_connector(tower: Node, tag: String) -> void:
	var stairs := tower.get_node_or_null("Blocks/Stairs")
	if stairs == null:
		print("PROBE[", tag, "] Blocks/Stairs 缺失")
		return
	for child in stairs.get_children():
		var connector := child as Node3D
		if connector == null:
			continue
		print("PROBE[", tag, "] connector ", connector.name,
			" pos=", connector.global_position,
			" edge=", str(connector.get_meta("edge_key", "-")),
			" vertical=", str(connector.get_meta("is_vertical_connector", false)),
			" upper_floor=", str(connector.get_meta("upper_floor_index", -1)),
			" lower_floor=", str(connector.get_meta("lower_floor_index", -1)),
			" walkable_surfaces=", str(connector.get_meta("walkable_collision_count", -1)),
			" enclosure=", str(connector.get_meta("enclosure_collision_count", -1)))
		for visual_value in connector.get_children():
			var visual := visual_value as Node3D
			if visual == null:
				continue
			var bodies := visual.find_children("*", "CollisionObject3D", true, false)
			print("PROBE[", tag, "]    visual ", visual.name,
				" pos=", visual.global_position,
				" collision_objects=", bodies.size())
			for body_value in bodies:
				var body := body_value as CollisionObject3D
				if body == null or not (body is StaticBody3D):
					continue
				var shapes: Array[String] = []
				for shape_value in body.get_children():
					var collision := shape_value as CollisionShape3D
					if collision == null or collision.shape == null:
						continue
					shapes.append("%s(%s,layer=%d)" % [
						str(collision.name), collision.shape.get_class(), body.collision_layer
					])
				print("PROBE[", tag, "]      body ", body.name, " shapes=", str(shapes))


## 行为级判定：把玩家放到办公室西门外侧几处，看他是站住还是掉下去。
## 站住 = 西侧下行通道有落脚面；掉到 -36 = 直接摔进 97F。
func _probe_descent_route(tower: Node, tag: String, player: Node3D) -> void:
	var samples: Array[Vector3] = [
		Vector3(-41.5, -23.0, 2.5),
		Vector3(-43.0, -23.0, 2.5),
		Vector3(-45.0, -23.0, 2.5),
		Vector3(-45.0, -23.0, 8.0),
		Vector3(-48.0, -23.0, 12.0),
	]
	for sample in samples:
		tower.call("_on_room_entered", tower.get("_room_by_id").get("floor_01_exit"))
		player.global_position = sample
		player.velocity = Vector3.ZERO
		await _settle()
		var settled_1 := player.global_position
		for index in range(45):
			await get_tree().physics_frame
		print("PROBE[", tag, "] drop from ", sample, " -> ", settled_1,
			" then ", player.global_position, " velocity=", player.velocity)


func _settle() -> void:
	for index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
