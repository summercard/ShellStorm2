extends Node
## 使用正式房间碰撞、盒域编译与整房预选；输出实际落点和玩家通行网格供路径验收。
const SCENE = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const KEYS = ["room_01", "room_02", "room_05", "room_07", "room_08"]
class Compiler extends Dungeon3D:
	func _roll_box_count(spawn: Dictionary, _rng: RandomNumberGenerator) -> int:
		return int(spawn.get("count_max", 0))
	func _make_box_enemy(kind: String, _floor: int, _level: int, _room: DungeonRoom3D, _encounter: String = "") -> Dictionary:
		return {"type": kind}
const EXPECTED_COUNTS := {"room_01": 8, "room_02": 10, "room_05": 39, "room_07": 20, "room_08": 25}
var failures: Array[String] = []
var _query := PhysicsShapeQueryParameters3D.new()
var _excluded: Array[RID] = []
var _floor_rects := {}
func _ready() -> void:
	var app := OS.get_environment("APPDATA").replace("\\", "/")
	if not app.contains("shellstorm-verification") or app == OS.get_environment("LOCALAPPDATA").replace("\\", "/"):
		get_tree().quit(2)
		return
	BaseManager.data = BaseData.new()
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = int(OS.get_environment("EXP01_SEED")) if not OS.get_environment("EXP01_SEED").is_empty() else 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 120000
	while not tower._main_story_gameplay_started and not tower._expedition_bootstrap_failed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if tower._room_by_id.size() != 13 or tower._expedition_bootstrap_failed:
		print("EXP01_GEOMETRY_BOOT_FAILED")
		get_tree().quit(1)
		return
	tower.set_process(false)
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
	await get_tree().process_frame
	var compiler := Compiler.new()
	compiler.run_seed = tower.run_seed
	compiler.player = tower.player
	var report := {"seed": tower.run_seed, "rooms": []}
	for key in KEYS:
		var room := tower._room_by_id[key] as DungeonRoom3D
		room._prepare_safe_spawn_selection()
		var entries: Array[Dictionary] = []
		for index in room.spawn_placements.size():
			compiler._collect_box_stage_entries(room, room.spawn_placements, index, 1, 0, RandomNumberGenerator.new(), entries, true)
		if entries.size() != EXPECTED_COUNTS[key]:
			failures.append(key + ":最大编译数量漂移:" + str(entries.size()))
		var row := {"id": key, "dimensions": [room.get_dimensions().x, room.get_dimensions().y], "placements": room.spawn_placements, "boxes": [], "entries": entries.size(), "landings": [], "walkable": [], "walkable_edges": [], "walkable_floor_y": [], "production_floor_rejected": [], "graph_method": "physical_capsule_swept_v1"}
		for index in room.spawn_placements.size():
			var p := compiler._box_placement_at(room.spawn_placements, index)
			var box := SpawnBoxCatalog.resolve_placement_box(p)
			var need := 0
			for item in entries:
				if item.spawn_preplaced_box == index:
					need += 1
			var center := room.resolve_spawn_box_center_local(p.box_center, p.box_size, need, p.box_rotation, box.min_spacing_m, box.wall_recess_tiles, true)
			if center.distance_to(p.box_center) > 0.01:
				failures.append(key + ":盒心漂移:" + str(index))
			var angle := deg_to_rad(float(p.box_rotation))
			var pool := room._box_sample_points(center, p.box_size * 0.5, cos(angle), sin(angle), room._spawn_clearance())
			var world: Array[Vector3] = []
			for point in pool:
				world.append(room.to_global(point))
			var capacity := room.preplaced_points_in_box(world, 64, box.min_spacing_m, Vector3.INF, 0.0, [], tower.run_seed ^ key.hash() ^ index).size()
			if capacity < need:
				failures.append(key + ":盒容量不足:" + str(index))
			row.boxes.append({"index": index, "need": need, "capacity_no_player": capacity, "declared": [p.box_center.x, p.box_center.y], "resolved": [center.x, center.y]})
		for port_id in ["A", "B"]:
			var port := room.get_connection_port_by_id(port_id)
			var pos := room._placement_vec2(port.position_m) - room._placement_vec2(port.outward) * 3.5
			tower.player.global_position = room.to_global(Vector3(pos.x, 0.5, pos.y))
			var picked := compiler._preselect_preplaced_room(room, entries, true)
			var points: Array = []
			if picked.ok:
				if picked.positions.size() != entries.size():
					failures.append(key + ":预摆未全量返回")
				var occupied: Array[Vector3] = []
				for point: Vector3 in picked.positions:
					var local := room.to_local(point)
					points.append([local.x, local.z])
					if not room._safe_spawn_geometry_valid(point) or Vector2(local.x - pos.x, local.z - pos.y).length() < 6.0 - 0.001:
						failures.append(key + ":非法落点或不足6m")
					for previous in occupied:
						if point.distance_to(previous) < 1.7 - 0.001:
							failures.append(key + ":跨盒重叠")
					occupied.append(point)
			else:
				failures.append(key + ":" + port_id + ":" + str(picked))
			row.landings.append({"port": port_id, "player": [pos.x, pos.y], "ok": picked.ok, "points": points, "rejection": {} if picked.ok else picked})
		_sample_physical_graph(room, row)
		if key == "room_08":
			row["portal_checks"] = _verify_portals(room)
			row["courtyard_floor_debt"] = []
			for value in room.get_node("AuthoredLayoutArtRoot").get_children():
				var tile := value as Node3D
				if tile == null or str(tile.get_meta("slot_role", "")) != "floor_tile":
					continue
				var center := room.to_local(tile.global_position)
				center.y = 0.0
				var height := _floor_height(room, center)
				row.courtyard_floor_debt.append({"node": str(tile.name), "room_local_xz": [center.x, center.z], "physical_support": is_finite(height), "physical_floor_y": height if is_finite(height) else null, "production_floor_contains": room._spawn_floor_contains(center, 0.35)})
		report.rooms.append(row)
		print("EXP01_GEOMETRY_ROOM " + key + " entries=" + str(entries.size()) + " boxes=" + str(row.boxes) + " landings=" + str(row.landings.map(func(v): return {"port": v.port, "ok": v.ok, "count": v.points.size()})))
	compiler.free()
	report["failures"] = failures
	var output := FileAccess.open(OS.get_environment("EXP01_REPORT"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	for failure in failures:
		print("EXP01_GEOMETRY_FAIL " + failure)
	print("EXP01_GEOMETRY_DONE failures=" + str(failures.size()))
	tower.queue_free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _collect_dynamic(node: Node) -> void:
	if node is CollisionObject3D and not node is StaticBody3D:
		_excluded.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_dynamic(child)

func _authored_floor_contains(room: Node3D, point: Vector3) -> bool:
	var id := room.get_instance_id()
	if not _floor_rects.has(id):
		var rects: Array[Rect2] = []
		for value in room.get_node("AuthoredLayoutArtRoot").get_children():
			var tile := value as Node3D
			if tile == null or not tile.scene_file_path.contains("/floor_tile_5m/"):
				continue
			var center := room.to_local(tile.global_position)
			# 5m逻辑地砖拼缝由整层承重补齐；包含历史追加九砖，不借整层楼板填房外。
			rects.append(Rect2(Vector2(center.x, center.z) - Vector2.ONE * 2.5, Vector2.ONE * 5.0))
		_floor_rects[id] = rects
	var footprint := Rect2(Vector2(point.x - 0.35, point.z - 0.35), Vector2.ONE * 0.7)
	var remaining: Array[Rect2] = [footprint]
	for tile: Rect2 in _floor_rects[id]:
		var next: Array[Rect2] = []
		for piece in remaining:
			if not piece.intersects(tile):
				next.append(piece)
				continue
			var cut := piece.intersection(tile)
			for rect in [Rect2(piece.position, Vector2(cut.position.x - piece.position.x, piece.size.y)), Rect2(Vector2(cut.end.x, piece.position.y), Vector2(piece.end.x - cut.end.x, piece.size.y)), Rect2(Vector2(cut.position.x, piece.position.y), Vector2(cut.size.x, cut.position.y - piece.position.y)), Rect2(Vector2(cut.position.x, cut.end.y), Vector2(cut.size.x, piece.end.y - cut.end.y))]:
				if rect.size.x > 0.0001 and rect.size.y > 0.0001:
					next.append(rect)
		remaining = next
		if remaining.is_empty():
			return true
	return false

func _floor_height(room: Node3D, point: Vector3) -> float:
	# 独立物理地面支撑，不复用生产可达域；支持中庭历史加砖的低台阶。
	if not _authored_floor_contains(room, point):
		return INF
	var heights: Array[float] = []
	for offset in [Vector3.ZERO, Vector3(0.35, 0, 0), Vector3(-0.35, 0, 0), Vector3(0, 0, 0.35), Vector3(0, 0, -0.35)]:
		var ray := PhysicsRayQueryParameters3D.create(room.to_global(point + offset + Vector3.UP * 0.45), room.to_global(point + offset - Vector3.UP * 0.15), 1, _excluded)
		var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.9:
			return INF
		var height := room.to_local(hit.position).y
		if height < -0.08 or height > 0.3:
			return INF
		heights.append(height)
	if heights.max() - heights.min() > 0.2:
		return INF
	return heights.max()

func _set_capsule(room: Node3D, point: Vector3, motion := Vector3.ZERO) -> void:
	_query.transform = Transform3D(Basis.IDENTITY, room.to_global(point + Vector3.UP * 0.92))
	_query.motion = room.global_basis * motion

func _sample_physical_graph(room: DungeonRoom3D, row: Dictionary) -> void:
	var dim := room.get_dimensions()
	var cells := {}
	var space := room.get_world_3d().direct_space_state
	for ix in int(dim.x * 2):
		for iz in int(dim.y * 2):
			var point := Vector3(-dim.x * 0.5 + ix * 0.5 + 0.25, 0, -dim.y * 0.5 + iz * 0.5 + 0.25)
			var floor_y := _floor_height(room, point)
			if not is_finite(floor_y):
				continue
			point.y = floor_y
			_set_capsule(room, point)
			if not space.intersect_shape(_query, 64).is_empty():
				continue
			cells[Vector2i(ix, iz)] = point
			row.walkable.append([ix, iz])
			row.walkable_floor_y.append(floor_y)
			if not room._spawn_floor_contains(Vector3(point.x, 0, point.z), 0.35):
				row.production_floor_rejected.append([point.x, floor_y, point.z])
	for cell: Vector2i in cells:
		for direction in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next: Vector2i = cell + direction
			if not cells.has(next):
				continue
			var start: Vector3 = cells[cell]
			var finish: Vector3 = cells[next]
			# 两端及中点均有支撑；扫掠采用较高脚底，台阶落差另行限幅。
			var mid := (start + finish) * 0.5
			mid.y = 0.0
			if absf(start.y - finish.y) > 0.2 or not is_finite(_floor_height(room, mid)):
				continue
			start.y = maxf(start.y, finish.y)
			finish.y = start.y
			_set_capsule(room, start, finish - start)
			if space.cast_motion(_query)[0] >= 1.0:
				row.walkable_edges.append([cell.x, cell.y, next.x, next.y])

func _verify_portals(room: DungeonRoom3D) -> Array:
	var checks: Array = []
	var art := room.get_node("AuthoredLayoutArtRoot") as Node3D
	var space := room.get_world_3d().direct_space_state
	for suffix in ["WALL_Y_30_45", "WALL_X_35_REAR"]:
		var wrapper := art.get_node("ENV-EXPEDITION-L-CORRIDOR-" + suffix) as Node3D
		var portal := wrapper.get_node("PassagePortal") as Node3D
		var shapes := portal.find_children("*", "CollisionShape3D", true, false)
		var meshes := portal.find_children("*", "MeshInstance3D", true, false)
		var relative := portal.transform
		var old_axis := Vector3.BACK if suffix == "WALL_Y_30_45" else Vector3.RIGHT
		var endpoint_a := relative * Vector3(2.5, 0, 0)
		var endpoint_b := relative * Vector3(-2.5, 0, 0)
		# 双面门洞两端允许互换，但端点集合必须与原5m墙严格重合。
		var endpoints_match := (endpoint_a.distance_to(old_axis * 2.5) < 0.0001 and endpoint_b.distance_to(old_axis * -2.5) < 0.0001) or (endpoint_a.distance_to(old_axis * -2.5) < 0.0001 and endpoint_b.distance_to(old_axis * 2.5) < 0.0001)
		var record := {"slot": suffix, "portal_resource": portal.scene_file_path, "shape_count": shapes.size(), "mesh_count": meshes.size(), "legacy_collision_absent": wrapper.get_node_or_null("CollisionBody") == null, "endpoints_match": endpoints_match, "portal_local_transform": str(relative), "expected_axis": str(old_axis), "positive_endpoint": str(relative * Vector3(2.5, 0, 0)), "wall_height_m": portal.get_meta("wall_visual_height_m"), "door_clear_width_m": portal.get_meta("door_clear_width_m"), "door_clear_height_m": portal.get_meta("door_clear_height_m"), "sweeps": []}
		if not endpoints_match or not is_equal_approx(float(record.wall_height_m), 11.9) or not is_equal_approx(float(record.door_clear_width_m), 2.2) or not is_equal_approx(float(record.door_clear_height_m), 2.5):
			failures.append("room_08:" + suffix + ":端点/墙高/门洞尺寸不符")
		if shapes.size() != 3 or meshes.size() != 1 or not record.legacy_collision_absent or wrapper.get_child_count() != 1:
			failures.append("room_08:" + suffix + ":重复网格或旧墙碰撞残留")
		for along in [0.0, -0.7, 0.7, -1.8, 1.8]:
			var a := room.to_local(portal.to_global(Vector3(along, 0, -1.25)))
			var b := room.to_local(portal.to_global(Vector3(along, 0, 1.25)))
			var supported := true
			for i in 11:
				var sample := a.lerp(b, i / 10.0)
				sample.y = 0.0
				supported = supported and is_finite(_floor_height(room, sample))
			_set_capsule(room, a)
			var start_clear := space.intersect_shape(_query, 64).is_empty()
			_set_capsule(room, b)
			var finish_clear := space.intersect_shape(_query, 64).is_empty()
			_set_capsule(room, a, b - a)
			var fraction: float = space.cast_motion(_query)[0]
			var expected_clear := absf(along) < 1.0
			var passed := supported and start_clear and finish_clear and ((fraction >= 1.0) if expected_clear else (fraction < 1.0))
			if not passed:
				failures.append("room_08:" + suffix + ":门洞/门垛/支撑扫掠失败:" + str(along))
			record.sweeps.append({"along_m": along, "expected_clear": expected_clear, "supported": supported, "start_clear": start_clear, "finish_clear": finish_clear, "safe_fraction": fraction, "passed": passed})
		checks.append(record)
	return checks
