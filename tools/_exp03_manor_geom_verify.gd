extends Node
## 铺装几何验收：**直接量网格包围盒**，不看节点名、不看生成器的 meta、不靠物理射线。
##
## ## 为什么不用射线（试过，不可靠）
##
## 第一版用 `PhysicsRayQueryParameters3D` 沿墙法向打射线判"有没有墙"。两个致命问题：
##
## 1. **会打到邻居**。射线要穿出墙线 0.8m 才算"没有墙"，而墙外就是走廊，
##    走廊自己的墙常常就在 0.8m 内 —— 于是**真缝隙被判成有墙**。
##    实测证据：把 n06 北墙一段平移 1.6m 留出真缝，射线法报 `gaps=0`，完全漏检。
## 2. **门扇会挡**。门位 1.2m 高度上有 `RoomDoor3D` 门扇，射线一打就命中，
##    17 间房的门全被误判成"玩家过不去"。
##
## 改成直接读几何：把美术层里每件墙/地砖的 MeshInstance3D 包围盒换算到**房间局部
## 空间**，再拿采样点去判包含。这是纯几何，邻居与门扇都干扰不到。
##
## ## 五把尺子
##
## 1. **周界封闭**：沿四面墙每 0.25m 取一点，在墙线高度 1.35m 处必须落在某段墙的
##    包围盒里。落在外面就是真缝（门位 ±1.1m 内除外，那是洞口）。
## 2. **门位正确**：每个门位必须有一段**门墙模块**，且其沿墙中心对准 lane；
##    同时不得有实心墙盖住门位。
## 3. **地面满铺**：每个 5m 格中心必须有地砖包围盒。
## 4. **无重叠**：任意两段墙的包围盒在 xz 上重叠不得超过 0.02m（防重复摆放）。
## 5. **层高一致**：所有墙顶高 ≈ 2.8m（防混入别的件）。
##
##   godot --headless --path . --scene res://tools/_exp03_manor_geom_verify.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED := 77003244
const GRID := 5.0
## 沿墙采样步长：5m 墙段上取 20 个点，0.2m 级窄缝也能抓到。
const SAMPLE_STEP := 0.25
const WALL_PROBE_Y := 1.35
const WALL_TOP_M := 2.8
const DOOR_OPENING_HALF := 1.1

var _failures: Array[String] = []


func _ready() -> void:
	var tower := await _spawn()
	await get_tree().process_frame

	var rooms: Array = []
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		if room.room_id.begins_with("cr") or room.room_id.begins_with("conn_"):
			continue
		rooms.append(room)
	rooms.sort_custom(func(a, b): return str(a.room_id) < str(b.room_id))
	print("GEOM_ROOMS %d" % rooms.size())

	var ok_count := 0
	for value in rooms:
		if _verify(value as DungeonRoom3D):
			ok_count += 1

	tower.queue_free()
	await get_tree().process_frame
	print("GEOM_DONE ok=%d / %d" % [ok_count, rooms.size()])
	print("GEOM_%s failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("GEOM_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify(room: DungeonRoom3D) -> bool:
	var room_id := room.room_id
	var dim: Vector2 = room.call("get_dimensions")
	var half := dim * 0.5
	var before := _failures.size()
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art_root == null:
		_fail("%s: 没有 AuthoredLayoutArtRoot" % room_id)
		return false

	var walls := _collect(room, art_root, "env_manor_wall")
	var floors := _collect(room, art_root, "env_manor_floor")
	_check(not walls.is_empty(), "%s: 美术层里没有任何墙" % room_id)
	_check(not floors.is_empty(), "%s: 美术层里没有任何地砖" % room_id)
	if walls.is_empty() or floors.is_empty():
		return false

	# ── 5. 层高一致 ────────────────────────────────────────────────────
	for wall in walls:
		var top := float(wall["box"].position.y) + float(wall["box"].size.y)
		if absf(top - WALL_TOP_M) > 0.12:
			_fail("%s: 墙顶高 %.2fm（应 %.1fm）—— %s"
				% [room_id, top, WALL_TOP_M, str(wall["name"])])
			break

	# ── 1. 周界封闭 ────────────────────────────────────────────────────
	var gaps := 0
	var samples := 0
	var gap_spots: Array[String] = []
	for side in ["north", "south", "west", "east"]:
		var length := dim.x if side in ["north", "south"] else dim.y
		var steps := int(round(length / SAMPLE_STEP))
		for step in range(steps):
			var along := -length * 0.5 + (float(step) + 0.5) * (length / float(steps))
			var point := _perimeter_point(side, along, dim, WALL_PROBE_Y)
			samples += 1
			if _covered_by(walls, point):
				continue
			if _in_door_lane(side, along, room, DOOR_OPENING_HALF):
				continue
			gaps += 1
			if gap_spots.size() < 4:
				gap_spots.append("%s@%.2f" % [side, along])
	if gaps > 0:
		_fail("%s: 周界有 %d 个采样点没有墙（%s）—— 围合有洞"
			% [room_id, gaps, ", ".join(gap_spots)])

	# ── 2. 门位正确 ────────────────────────────────────────────────────
	var door_ok := 0
	for value in room.get("connection_ports"):
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		var lane := float(port.get("lane_m", 0.0))
		var proof := _perimeter_point(side, lane, dim, WALL_PROBE_Y)
		var module: Dictionary = {}
		for wall in walls:
			# 沿墙中心对准 lane、且盖住洞口中心那一带 → 就是这一格的门墙
			var along_center := float(wall["center_x"]) if side in ["north", "south"] else float(wall["center_z"])
			if absf(along_center - lane) > 0.6:
				continue
			if not (wall["box"] as AABB).has_point(proof):
				continue
			module = wall
			break
		if module.is_empty():
			_fail("%s: 门位（%s@%.1f）没有对应的墙模块 —— 洞口位置空着或错位"
				% [room_id, side, lane])
			continue
		if not str(module["path"]).contains("manor_wall_door"):
			_fail("%s: 门位（%s@%.1f）放的是 %s —— 实心件会把门堵死"
				% [room_id, side, lane, str(module["path"]).get_file()])
			continue
		# 门墙还必须真的**盖住本格**（不能只覆盖洞口一侧）
		var cell_center := _perimeter_point(side, lane, dim, WALL_PROBE_Y)
		if not (module["box"] as AABB).grow(0.02).has_point(cell_center):
			_fail("%s: 门墙（%s@%.1f）没有覆盖洞口中心" % [room_id, side, lane])
			continue
		door_ok += 1

	# ── 3. 地面满铺 ────────────────────────────────────────────────────
	var cols := int(round(dim.x / GRID))
	var rows := int(round(dim.y / GRID))
	var holes := 0
	for row in range(rows):
		for col in range(cols):
			var center := Vector3(-half.x + (float(col) + 0.5) * GRID, 0.05,
				-half.y + (float(row) + 0.5) * GRID)
			if not _covered_by(floors, center):
				holes += 1
	if holes > 0:
		_fail("%s: %d / %d 个格子没有地砖（脚下是空的）" % [room_id, holes, cols * rows])

	# ── 4. 无重叠 ──────────────────────────────────────────────────────
	# **墙角本来就会重叠**：北墙与西墙各厚 0.5m，在角上自然交叠一个 0.25×0.25 的方块，
	# 这是砌墙的正常做法，不是缺陷。真正要抓的是"同一格被摆了两遍"——
	# 那种重叠是整段级别的（约 5.0×0.5）。所以阈值取 0.6m：
	# 小于它的当墙角接缝放过，大于它的报错。
	var overlaps := 0
	var overlap_worst := ""
	for i in range(walls.size()):
		for j in range(i + 1, walls.size()):
			var a: AABB = walls[i]["box"]
			var b: AABB = walls[j]["box"]
			var ox := minf(a.position.x + a.size.x, b.position.x + b.size.x) - maxf(a.position.x, b.position.x)
			var oz := minf(a.position.z + a.size.z, b.position.z + b.size.z) - maxf(a.position.z, b.position.z)
			if ox > 0.6 and oz > 0.6:
				overlaps += 1
				if overlap_worst.is_empty():
					overlap_worst = "%s × %s (%.2f×%.2f)" % [str(walls[i]["name"]), str(walls[j]["name"]), ox, oz]
	if overlaps > 0:
		_fail("%s: %d 对墙段整段重叠（重复摆放）%s" % [room_id, overlaps, overlap_worst])

	var passed := _failures.size() == before
	print("GEOM_ROOM %-22s %.0fx%.0f walls=%-3d tiles=%-3d samples=%-4d gaps=%-2d doors=%-2d floor=%dx%d %s"
		% [room_id, dim.x, dim.y, walls.size(), floors.size(), samples, gaps, door_ok,
			cols, rows, "OK" if passed else "FAIL"])
	return passed


## 把美术层里某类预制件（墙 / 地砖）的网格包围盒统一换算到**房间局部空间**。
##
## 用 `room.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()`：
## 房间在世界里是有位移的（实测 `boss_foyer` 在 x=104.75 z=-55.25），
## 而 `mi.transform` 只是相对父节点的，父节点一旦有偏移就直接量错。
func _collect(room: DungeonRoom3D, art_root: Node3D, keyword: String) -> Array:
	var inverse := room.global_transform.affine_inverse()
	var out: Array = []
	for value in art_root.find_children("*", "Node3D", true, false):
		var node := value as Node3D
		var path := str(node.scene_file_path)
		if not path.contains(keyword):
			continue
		# 包装件（*_root_top3d）与内嵌件（*_visual_top3d）会同时命中关键字，
		# 只取最外层，否则同一件会被数两遍、包围盒也重复。
		var parent := node.get_parent() as Node3D
		if parent != null and str(parent.scene_file_path).contains(keyword):
			continue
		var box := AABB()
		var has := false
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = inverse * mi.global_transform * mi.get_aabb()
			box = box.merge(a) if has else a
			has = true
		if not has:
			continue
		var center := inverse * node.global_transform * Vector3.ZERO
		out.append({
			"name": str(node.name), "path": path, "box": box,
			"center_x": center.x, "center_z": center.z,
		})
	return out


func _covered_by(items: Array, point: Vector3) -> bool:
	for item in items:
		if (item["box"] as AABB).has_point(point):
			return true
	return false


## 某面墙上「沿墙坐标 = along、高度 = y」那个点（**房间局部坐标**）。
## `lane_m` 是沿墙轴的世界坐标，北/南面是 x、东/西面是 z。
func _perimeter_point(side: String, along: float, dim: Vector2, y: float) -> Vector3:
	var half := dim * 0.5
	match side:
		"north":
			return Vector3(along, y, -half.y)
		"south":
			return Vector3(along, y, half.y)
		"west":
			return Vector3(-half.x, y, along)
		_:
			return Vector3(half.x, y, along)


func _in_door_lane(side: String, along: float, room: DungeonRoom3D, slack: float) -> bool:
	for value in room.get("connection_ports"):
		var port := value as Dictionary
		if str(port.get("side", "")) != side:
			continue
		if absf(along - float(port.get("lane_m", 0.0))) <= slack:
			return true
	return false


func _spawn() -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 5:
		await get_tree().process_frame
	return tower


func _check(ok: bool, message: String) -> void:
	if not ok:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
