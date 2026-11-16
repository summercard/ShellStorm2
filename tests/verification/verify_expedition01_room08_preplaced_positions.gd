extends "res://tests/verification/verify_expedition01_combat_geometry.gd"
## 正式08房多站位容量：真实胶囊图取合法点，调用正式编译及整房预选，不替换生产算法。
func _ready() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("shellstorm-verification"):
		get_tree().quit(2)
		return
	BaseManager.data = BaseData.new()
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = int(OS.get_environment("EXP01_SEED")) if not OS.get_environment("EXP01_SEED").is_empty() else 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 150000
	while not tower._main_story_gameplay_started and not tower._expedition_bootstrap_failed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if tower._expedition_bootstrap_failed or not tower._main_story_gameplay_started:
		print("ROOM08_POSITIONS_BOOT_FAILED")
		get_tree().quit(3)
		return
	tower.set_process(false)
	tower.set_physics_process(false)
	tower.player.set_process(false)
	tower.player.set_physics_process(false)
	tower.get_node("ActiveEnemies").process_mode = Node.PROCESS_MODE_DISABLED
	for value in tower._room_by_id.values():
		value.ensure_shell_built()
		value.ensure_detail_built()
	_collect_dynamic(tower)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_query.shape = capsule
	_query.collision_mask = 1
	_query.collide_with_areas = false
	_query.exclude = _excluded
	_query.margin = 0.001
	await get_tree().physics_frame
	await get_tree().physics_frame
	var room := tower._room_by_id["room_08"] as DungeonRoom3D
	room._prepare_safe_spawn_selection()
	var row := {"id": "room_08", "dimensions": [room.get_dimensions().x, room.get_dimensions().y], "walkable": [], "walkable_edges": [], "walkable_floor_y": [], "production_floor_rejected": []}
	_sample_physical_graph(room, row)
	var cells := {}
	var neighbours := {}
	var dim := room.get_dimensions()
	for i in row.walkable.size():
		var c: Array = row.walkable[i]
		var key := Vector2i(c[0], c[1])
		cells[key] = Vector3(-dim.x * 0.5 + key.x * 0.5 + 0.25, row.walkable_floor_y[i], -dim.y * 0.5 + key.y * 0.5 + 0.25)
		neighbours[key] = []
	for edge: Array in row.walkable_edges:
		var a := Vector2i(edge[0], edge[1])
		var b := Vector2i(edge[2], edge[3])
		neighbours[a].append(b)
		neighbours[b].append(a)
	var requested := []
	for port_id in ["A", "B"]:
		var port := room.get_connection_port_by_id(port_id)
		var p := room._placement_vec2(port.position_m) - room._placement_vec2(port.outward) * 3.5
		requested.append({"label": "entry_" + port_id, "point": Vector3(p.x, 0, p.y)})
	var art := room.get_node("AuthoredLayoutArtRoot") as Node3D
	for suffix in ["WALL_Y_30_45", "WALL_X_35_REAR"]:
		var portal := art.get_node("ENV-EXPEDITION-L-CORRIDOR-" + suffix + "/PassagePortal") as Node3D
		requested.append({"label": suffix, "point": room.to_local(portal.global_position)})
	for p in [Vector3(0, 0, 0), Vector3(2.5, 0, -2.5), Vector3(7.5, 0, -2.5), Vector3(15, 0, 3.752136)]:
		requested.append({"label": "courtyard_or_visual_" + str(p), "point": p})
	var anchors := []
	for req: Dictionary in requested:
		var closest := Vector2i.ZERO
		var distance := INF
		for key: Vector2i in cells:
			var v: Vector3 = cells[key]
			var d := Vector2(v.x - req.point.x, v.z - req.point.z).length_squared()
			if d < distance:
				distance = d
				closest = key
		anchors.append(closest)
		req["sample"] = closest
		req["shift_m"] = sqrt(distance)
	var samples := {}
	for i in requested.size():
		samples[anchors[i]] = requested[i].label
	var routes := []
	for goal: Vector2i in anchors.slice(1):
		var route := _route(anchors[0], goal, neighbours)
		if route.is_empty():
			failures.append("入口到目标物理图不连通:" + str(goal))
		var coordinates := []
		for i in route.size():
			coordinates.append([cells[route[i]].x, cells[route[i]].z])
			if i % 6 == 0:
				samples[route[i]] = "route_" + str(routes.size()) + "_" + str(i)
		routes.append(coordinates)
	# 额外覆盖各条走廊和中庭可达格，约3米网格；不只测原盒外的方便点。
	var reachable := _reachable(anchors[0], neighbours)
	for key: Vector2i in reachable:
		if key.x % 6 == 0 and key.y % 6 == 0:
			samples[key] = "reachable_grid"
	# 门洞原始中心与渲染probe原站位另测精确坐标，不能只以最近网格替代。
	var excluded_exact := []
	for i in requested.size():
		var p: Vector3 = requested[i].point
		p.y = _floor_height(room, p)
		if not is_finite(p.y):
			failures.append("精确锚点无物理支撑:" + str(requested[i].label))
			continue
		_set_capsule(room, p)
		if not room.get_world_3d().direct_space_state.intersect_shape(_query, 64).is_empty():
			if i < 4 or i == 7:
				failures.append("必验精确锚点胶囊非法:" + str(requested[i].label))
			excluded_exact.append({"label": requested[i].label, "reason": "精确点胶囊碰撞；邻近合法图点仍验"})
			continue
		var exact_key := Vector2i(-100 - i, -100)
		cells[exact_key] = p
		samples[exact_key] = "exact_" + str(requested[i].label)
	var waves := tower._spawn_box_waves(room, 1, 2)
	var entries: Array[Dictionary] = []
	if waves.size() == 1:
		entries.assign(waves[0])
	if entries.size() != 25:
		failures.append("正式编译数量非25:" + str(entries.size()))
	var report := {"seed": tower.run_seed, "compiled": entries.size(), "placements": room.spawn_placements, "requests": requested, "routes": routes, "sample_count": samples.size(), "reachable_cells": reachable.size(), "excluded_exact": excluded_exact, "samples": [], "failed": 0, "success": 0, "candidates": [], "real_commit": {}}
	for i in room.spawn_placements.size():
		var points := []
		for entry in entries:
			if entry.spawn_preplaced_box == i:
				for point: Vector3 in entry.spawn_safe_candidates:
					var p := room.to_local(point)
					points.append([p.x, p.z])
				break
		report.candidates.append({"box": i, "points": points})
	for key: Vector2i in samples:
		var p: Vector3 = cells[key]
		tower.player.global_position = room.to_global(p + Vector3.UP * 0.05)
		var selected := tower._preselect_preplaced_room(room, entries, true)
		var points := []
		var minimum := INF
		if selected.ok:
			var occupied: Array[Vector3] = []
			for point: Vector3 in selected.positions:
				var local := room.to_local(point)
				minimum = minf(minimum, Vector2(local.x - p.x, local.z - p.z).length())
				if not room._safe_spawn_geometry_valid(point):
					failures.append("生产落点非法")
				for prior in occupied:
					if point.distance_to(prior) < 1.7 - 0.001:
						failures.append("跨盒不足1.7m")
				occupied.append(point)
				points.append([local.x, local.z])
			if points.size() != 25 or minimum < 6.0 - 0.001:
				failures.append("数量/6m门槛失败")
			report.success += 1
		else:
			report.failed += 1
			print("ROOM08_POSITION_REJECT " + str(p) + " " + str(selected))
		report.samples.append({"label": samples[key], "player": [p.x, p.y, p.z], "ok": selected.ok, "count": points.size(), "minimum_player_m": minimum if selected.ok else null, "points": points, "rejection": {} if selected.ok else selected})
	if report.failed > 0:
		failures.append("合法可达站位预选失败:" + str(report.failed))
	# 全部预选通过后才提交一次真实入房，避免基线预期失败污染生产状态。
	if report.failed == 0 and not anchors.is_empty():
		var p: Vector3 = cells[anchors[4]]
		tower.player.global_position = room.to_global(p + Vector3.UP * 0.05)
		tower.force_enter_room_for_test("room_08")
		var actual: Array = tower._enemy_nodes_by_room.get("room_08", [])
		report.real_commit = {"count": actual.size(), "blocked": tower._room_spawn_blocked.has("room_08"), "delayed": tower._pending_delayed_spawn_count("room_08"), "reserved": tower._reserved_spawn_count("room_08")}
		if actual.size() != 25 or report.real_commit.blocked or report.real_commit.delayed != 0 or report.real_commit.reserved != 0:
			failures.append("中庭真实提交未全量成功")
	report["failures"] = failures
	var output := FileAccess.open(OS.get_environment("EXP01_REPORT"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("ROOM08_POSITIONS_DONE samples=%d success=%d failed=%d real_commit=%s failures=%s" % [samples.size(), report.success, report.failed, report.real_commit, failures])
	tower.queue_free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _reachable(start: Vector2i, neighbours: Dictionary) -> Dictionary:
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for n: Vector2i in neighbours.get(c, []):
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen

func _route(start: Vector2i, goal: Vector2i, neighbours: Dictionary) -> Array:
	var parent := {start: start}
	var queue := [start]
	var index := 0
	while index < queue.size() and not parent.has(goal):
		var c: Vector2i = queue[index]
		index += 1
		for n: Vector2i in neighbours.get(c, []):
			if not parent.has(n):
				parent[n] = c
				queue.append(n)
	if not parent.has(goal):
		return []
	var route := [goal]
	while route.back() != start:
		route.append(parent[route.back()])
	route.reverse()
	return route
