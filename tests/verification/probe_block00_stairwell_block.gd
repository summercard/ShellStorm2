extends Node
## 楼梯间阻塞取证 v2：99F 归航基地(安全区) → 98F 的竖直楼梯通道。
##
## 用户报告「在楼梯间被挡住」，并怀疑「新区块生成到 99 楼了」。本探针不猜，用四组事实回答：
##   Q1 是不是区块00 造成的？—— A/B：同一次运行里跑「区块00 开」与「区块00 关」
##      （`force_standard_floor_plan_for_test`），对比同一楼梯路径的碰撞命中集合。
##   Q2 区块00 的几何有没有爬进 99F（y ∈ [-12,0]）？—— 逐房量 art root 的世界包围范围。
##   Q3 到底是谁挡的？—— 每个命中点原样打出「采样坐标 + 命中体名 + 命中体 AABB」。
##   Q4 这是不是 99→98 独有的？—— 对照 Stair_A(100→99) 与 Stair_98_97(98→97)。
##
## 打印 PROBE_STAIR_BLOCK_DONE 结束；只报事实。

const FLOOR_NUMBER := 98
const SEED := 2818567602
const SAMPLE_STEP_M := 0.5
const SPHERE_RADIUS := 0.45
## 相邻楼层 y：100F=0 / 99F=-12 / 98F=-24 / 97F=-36（FLOOR_HEIGHT_M=12）。
const FLOOR_BAND := 12.0

var _lines: Array[String] = []


func _ready() -> void:
	_log("########## 楼梯间阻塞取证 v2 ##########")
	await _pass("区块00 开", false)
	await _pass("区块00 关", true)
	_finish()


func _finish() -> void:
	print("\n########## 楼梯间阻塞取证 v2 ##########")
	for line in _lines:
		print(line)
	print("PROBE_STAIR_BLOCK_DONE")
	get_tree().quit(0)


func _log(text: String) -> void:
	_lines.append(text)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _pass(label: String, standard_only: bool) -> void:
	_log("")
	_log("==================== 第 %s 轮 ====================" % label)
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	tower.force_standard_floor_plan_for_test = standard_only
	add_child(tower)
	await _settle()
	if not tower.generate_through_floor_for_test(FLOOR_NUMBER):
		_log("  生成到 %dF 失败" % FLOOR_NUMBER)
		tower.queue_free()
		await _settle()
		return
	await _settle()

	_dump_floor_band_check(tower)
	_dump_facade_boxes(tower)
	_dump_stair_paths(tower)

	tower.queue_free()
	await _settle()


## Q2：区块00 四个授权房间的几何世界范围，看是否落在 98F 层带内。
func _dump_floor_band_check(tower: Node) -> void:
	_log("  ---- Q2 授权房间几何的世界 Y 范围（98F 层带应为 [-24, -12]）----")
	var rooms := _collect_rooms(tower)
	var authored := 0
	for room in rooms:
		if not bool(room.get("authored_layout_shell")):
			continue
		authored += 1
		var art_root := room.get_node_or_null("AuthoredLayoutArtRoot")
		if art_root == null:
			_log("    [%s] 有 authored_layout_shell 但无 AuthoredLayoutArtRoot" % str(room.room_id))
			continue
		var bounds := _world_bounds(art_root)
		_log(
			"    [%s] room.position.y=%.3f 几何 y∈[%.3f, %.3f]  x∈[%.3f, %.3f]  z∈[%.3f, %.3f]"
			% [
				str(room.room_id),
				room.global_position.y,
				bounds[0].y, bounds[1].y,
				bounds[0].x, bounds[1].x,
				bounds[0].z, bounds[1].z,
			]
		)
		var band_lo := room.global_position.y - 0.5
		var band_hi := room.global_position.y + FLOOR_BAND - 0.5
		if bounds[1].y > band_hi:
			_log("      ⚠️ 几何顶部越过本层天花（%.3f > %.3f）" % [bounds[1].y, band_hi])
		if bounds[0].y < band_lo - 0.6:
			_log("      ⚠️ 几何底部穿到下层（%.3f < %.3f）" % [bounds[0].y, band_lo])
	if authored == 0:
		_log("    （本层没有授权房间 —— 正是区块00 关的那一轮）")


## Q3：天台立面环碰撞盒的实际 AABB。
func _dump_facade_boxes(tower: Node) -> void:
	_log("  ---- Q3 天台(Rooftop)立面/外墙碰撞盒 AABB ----")
	var rooftop := tower.get_node_or_null("Blocks/Rooftop")
	if rooftop == null:
		_log("    找不到 Blocks/Rooftop")
		return
	var found := 0
	for value in rooftop.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		if body == null:
			continue
		if not str(body.name).contains("FacadeBoundaryCollision"):
			continue
		found += 1
		var bounds := _static_body_bounds(body)
		_log(
			"    %s  x∈[%.3f, %.3f]  y∈[%.3f, %.3f]  z∈[%.3f, %.3f]"
			% [
				str(body.name),
				bounds[0].x, bounds[1].x,
				bounds[0].y, bounds[1].y,
				bounds[0].z, bounds[1].z,
			]
		)
	if found == 0:
		_log("    无 FacadeBoundaryCollision 节点")


## Q1 + Q4：沿每条竖直楼梯路径密集采样，逐点查碰撞；命中时打原样坐标与命中体 AABB。
func _dump_stair_paths(tower: Node) -> void:
	_log("  ---- Q1/Q4 竖直楼梯路径碰撞 ----")
	var corridors := tower.get("_corridor_by_edge") as Dictionary
	var space := get_viewport().world_3d.direct_space_state
	var entries: Array = corridors.keys()
	entries.sort()
	for edge_value in entries:
		var edge := str(edge_value)
		var connector := corridors[edge_value] as Node3D
		if connector == null:
			continue
		if not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		_log("    [%s] name=%s" % [edge, str(connector.name)])
		if space == null:
			_log("      取不到物理空间 —— 跳过")
			continue
		var points: Array = connector.get_meta("path_points", [])
		if points.size() < 2:
			_log("      path_points 不足")
			continue
		var samples := 0
		var blocked := 0
		var summary: Dictionary = {}
		for index in range(points.size() - 1):
			var start := points[index] as Vector3
			var end := points[index + 1] as Vector3
			var length := start.distance_to(end)
			var steps := maxi(1, int(ceil(length / SAMPLE_STEP_M)))
			for step in range(steps + 1):
				var sample := start.lerp(end, float(step) / float(steps))
				var probe_point := sample + Vector3(0, 0.9, 0)
				samples += 1
				var hits := _sphere_hits(space, probe_point)
				if hits.is_empty():
					continue
				blocked += 1
				for hit in hits:
					var key := str(hit["path"])
					if not summary.has(key):
						summary[key] = {"count": 0, "min": hit["min"], "max": hit["max"], "at": []}
					var record := summary[key] as Dictionary
					record["count"] = int(record["count"]) + 1
					record["min"] = (record["min"] as Vector3).min(hit["min"])
					record["max"] = (record["max"] as Vector3).max(hit["max"])
					var at: Array = record["at"]
					if at.size() < 3:
						at.append(
							"seg%d@%s" % [index, str(sample.snappedf(0.01))]
						)
		if samples == 0:
			_log("      哨兵：0 个采样点")
			continue
		_log("      采样 %d 点 / 命中 %d 点" % [samples, blocked])
		var keys: Array = summary.keys()
		keys.sort()
		for key_value in keys:
			var record := summary[key_value] as Dictionary
			_log("        %s × %d" % [str(key_value), int(record["count"])])
			_log(
				"            AABB x∈[%.3f, %.3f] y∈[%.3f, %.3f] z∈[%.3f, %.3f]"
				% [
					(record["min"] as Vector3).x, (record["max"] as Vector3).x,
					(record["min"] as Vector3).y, (record["max"] as Vector3).y,
					(record["min"] as Vector3).z, (record["max"] as Vector3).z,
				]
			)
			_log("            首批命中点 = %s" % str(record["at"]))


func _collect_rooms(tower: Node) -> Array:
	var out: Array = []
	for value in tower.find_children("*", "", true, false):
		if value is DungeonRoom3D:
			out.append(value)
	return out


func _world_bounds(root: Node3D) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var any := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var aabb := mesh.mesh.get_aabb()
		var corners := [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0, 0),
			aabb.position + Vector3(0, aabb.size.y, 0),
			aabb.position + Vector3(0, 0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
			aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
			aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
			aabb.position + aabb.size,
		]
		for corner_value in corners:
			var world := mesh.global_transform * (corner_value as Vector3)
			lo = lo.min(world)
			hi = hi.max(world)
			any = true
	if not any:
		var origin := root.global_position
		return [origin, origin]
	return [lo, hi]


func _static_body_bounds(body: StaticBody3D) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var any := false
	for value in body.find_children("*", "CollisionShape3D", true, false):
		var shape := value as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		var aabb := shape.shape.get_debug_mesh().get_aabb() if shape.shape.get_debug_mesh() != null else AABB()
		var half := aabb.size * 0.5
		var center := aabb.get_center()
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var local := center + Vector3(half.x * sx, half.y * sy, half.z * sz)
					var world := shape.global_transform * local
					lo = lo.min(world)
					hi = hi.max(world)
					any = true
	if not any:
		var origin := body.global_position
		return [origin, origin]
	return [lo, hi]


func _sphere_hits(space: PhysicsDirectSpaceState3D, point: Vector3) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = SPHERE_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), point)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var results := space.intersect_shape(params, 24)
	var out: Array = []
	var seen: Dictionary = {}
	for result_value in results:
		var result := result_value as Dictionary
		var collider := result.get("collider") as Node
		if collider == null:
			continue
		var path := _path_of(collider)
		if seen.has(path):
			continue
		seen[path] = true
		var bounds := [point, point]
		var body := collider as StaticBody3D
		if body != null:
			bounds = _static_body_bounds(body)
		out.append({"path": path, "min": bounds[0], "max": bounds[1]})
	return out


func _path_of(node: Node) -> String:
	var parts: Array[String] = []
	var cursor := node
	while cursor != null:
		parts.push_front(str(cursor.name))
		cursor = cursor.get_parent()
	return "/".join(parts)
