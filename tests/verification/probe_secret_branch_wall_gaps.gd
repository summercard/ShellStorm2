extends Node

## 支线隐藏房间「外围封闭性」探针（业主 2026-11-10）：
## 「远征01 的隐藏房间进去后，会有空出来的门，外围可以走出去并且掉落。」
##
## 以往的 A27~A30 只查「脚下实心 / 承重不出界 / 门洞在可走面上」，**没有一条查墙**。
## 本探针补这个缺：
##   · 把每间支线房的地砖轮廓切成 1 m 格，凡是「本格有砖、邻格无砖」的边都是**外围边**；
##   · 从该格中心朝外打水平射线（离地 0.5 / 1.3 / 2.4 m 三个高度，射程越过边缘 2 m）；
##   · 三个高度里**任何一个**没打到东西 ⇒ 这里有口子；
##   · 口子若落在本房某扇**真门**的 lane ± 门半宽内，属预期（那是门，门扇关着时会挡）；
##     否则就是「空出来的门」/ 缺墙，玩家能从这里走出房间。
##
## 另外报告：每间房声明的 doors、壳里烘焙的门墙件（`wall_door` 来源）落在哪一侧、
## 有没有被封，帮助定位是「废门洞没封」还是「门墙搬位后原位漏空」。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_secret_branch_wall_gaps.tscn
##   默认独立覆盖 12 个样本（四房型 × 东单门/西单门/双门），SS2_QUIET=1 省略逐口输出。
##   SS2_FULL_LEVEL=1 从正式远征场景检查；SS2_PAIR 过滤子图；SS2_BREAK_WALL=1 删除补墙作反向对照。
##   启动 Godot 前必须由外部隔离 APPDATA/LOCALAPPDATA，不能在 _ready 内才隔离。
## 退出码：0 无缺口；1 有缺口或找不到支线。成功行 `SECRET_BRANCH_WALL_GAPS_OK`。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 90.0
const CELL_M := 1.0
const FLOOR_EPS_M := 0.35
const MAX_FLOOR_THICKNESS_M := 0.8
const MAX_FLOOR_TOP_OFFSET_M := 0.4
## 射线高度（m）：膝 / 腰 / 头顶。三个都要被挡才算封死。
const RAY_HEIGHTS := [0.5, 1.3, 2.4]
## 射线越过地砖外缘的距离（m）。墙厚 0.3，壳墙居中在缘线或缘外 0.15，取 2 m 足够。
const RAY_REACH_M := 2.0
## 起点回缩 1.2m，避免射线起点陷入较厚墙皮而把已有墙误报成缺口。
const RAY_START_INSET_M := 1.2
## 判「口子在门 lane 内」的半宽（m）：门洞 2.2 m 宽 + 一格容差。
const DOOR_HALF_WIDTH_M := 1.6

var _branch: Node = null


func _ready() -> void:
	var want_pair := OS.get_environment("SS2_PAIR")
	var verbose := OS.get_environment("SS2_QUIET") != "1"
	if OS.get_environment("SS2_FULL_LEVEL") == "1":
		var scene := load(EXPEDITION_SCENE) as PackedScene
		var tower := scene.instantiate() as TowerDescent3D
		tower.test_mode = false
		add_child(tower)
		var waited := 0.0
		while waited < WAIT_LIMIT_S:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if not (tower.get("_records") as Array).is_empty():
				_branch = _find_branch(tower)
				if _branch != null:
					break
	else:
		var branch := SecretBranch3D.new()
		add_child(branch)
		_branch = branch
		branch.configure(Vector3.ZERO, 77001199, [], Callable(), Callable(), Callable(), {}, Callable(), null, Callable(), "expedition_01")
		for pair in range(3):
			var root := Node3D.new()
			root.name = "SecretBranch_%d" % pair
			branch.add_child(root)
			var templates := ["office_60x70", "corridor_45x40", "bridge_60x50", "extraction_25x25"]
			var sizes := [Vector2(30, 40), Vector2(45, 40), Vector2(60, 30), Vector2(25, 25)]
			for i in range(4):
				var doors: Array = (["east"] if pair == 0 else (["west"] if pair == 1 else ["west", "east"])) if i < 3 else []
				branch._spawn_branch_room(root, "probe_%d_%d" % [pair, i], Vector3(i * 100, 0, pair * 150), sizes[i], doors, {}, i, -7.5 if pair == 1 else 7.5, templates[i], false)
		if OS.get_environment("SS2_BREAK_WALL") == "1":
			var room := branch.get_node("SecretBranch_0/SecretRoom_probe_0_3") as DungeonRoom3D
			for node in room.find_children("*", "Node3D", true, false):
				if bool(node.get_meta("branch_reconciled_wall", false)):
					node.queue_free()
	for _i in range(4):
		await get_tree().physics_frame
	if _branch == null:
		print("找不到 SecretBranch3D 节点")
		print("SECRET_BRANCH_WALL_GAPS_FAILED no_branch")
		get_tree().quit(1)
		return

	var total_gaps := 0
	var total_rooms := 0
	for child in _branch.get_children():
		var root := child as Node3D
		if root == null or not str(root.name).begins_with("SecretBranch_"):
			continue
		if not want_pair.is_empty() and str(root.name) != "SecretBranch_%s" % want_pair:
			continue
		print("")
		print("── %s ──" % root.name)
		var rooms: Array[DungeonRoom3D] = []
		for node in root.find_children("*", "", true, false):
			var room := node as DungeonRoom3D
			if room != null:
				rooms.append(room)
		rooms.sort_custom(func(a: DungeonRoom3D, b: DungeonRoom3D) -> bool:
			return a.global_position.x < b.global_position.x
		)
		for room in rooms:
			total_rooms += 1
			total_gaps += _audit_room(room, verbose)
			total_gaps += audit_door_clearance(room)

	print("")
	if total_rooms == 0:
		print("SECRET_BRANCH_WALL_GAPS_FAILED no_rooms")
		get_tree().quit(1)
		return
	if total_gaps == 0:
		print("SECRET_BRANCH_WALL_GAPS_OK rooms=%d 外围无缺口" % total_rooms)
		get_tree().quit(0)
	else:
		print("SECRET_BRANCH_WALL_GAPS_FAILED gaps=%d rooms=%d" % [total_gaps, total_rooms])
		get_tree().quit(1)


## A32：只排除可开门扇；门墙/家具/旧壳仍参与阻挡，不能用节点数量代替可通行。
static func audit_door_clearance(room: DungeonRoom3D) -> int:
	var excluded: Array[RID] = []
	for value in room.find_children("*", "StaticBody3D", true, false):
		if value is RoomDoor3D:
			excluded.append((value as RoomDoor3D).get_rid())
	var failures := 0
	var half := room.get_dimensions() * 0.5
	for side_value in room.doors:
		var side := str(side_value)
		var lane := float(room.get_meta("wall_door_lane_%s" % side, 0.0))
		var normal := Vector3.RIGHT if side == "east" else Vector3.LEFT
		var point := Vector3(half.x if side == "east" else -half.x, 0, lane)
		for height in [0.5, 1.3, 2.2]:
			for offset in [-0.65, 0.0, 0.65]:
				var p := point + Vector3(0, float(height), float(offset))
				var query := PhysicsRayQueryParameters3D.create(room.to_global(p - normal * 1.1), room.to_global(p + normal * 1.1), 1, excluded)
				query.collide_with_areas = false
				var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty():
					failures += 1
					print("A32_BLOCKED %s %s height=%.1f offset=%.2f collider=%s" % [room.room_id, side, height, offset, str((hit.collider as Node).get_path())])
	return failures


func _find_branch(root: Node) -> Node:
	for node in root.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("SecretBranch3D.gd"):
			return node
	return null


func _audit_room(room: DungeonRoom3D, verbose: bool) -> int:
	var dims := room.get_dimensions()
	var tiles := _floor_tiles(room)
	var lanes := _door_lanes(room)
	print("  房间 %-12s %.0f×%.0f  doors=%s  lanes=%s  砖=%d" % [
		str(room.room_id), dims.x, dims.y, str(room.doors), str(lanes), tiles.size(),
	])
	_print_baked_door_pieces(room)
	if OS.get_environment("SS2_DUMP") in [str(room.room_id), "all"]:
		_dump_room(room)
	if tiles.is_empty():
		print("    （没量到地砖，无法审计）")
		return 1

	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var columns := int(round(dims.x / CELL_M))
	var rows := int(round(dims.y / CELL_M))
	var space := room.get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	for value in room.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		var ancestor := body.get_parent()
		var structural := false
		while ancestor != null and ancestor != room:
			if ancestor is Node3D:
				var source := (ancestor as Node3D).scene_file_path.get_file()
				if source.ends_with(".tscn"):
					structural = source.begins_with("wall") or source.contains("corner") or source.contains("guardrail") or source.contains("platform_edge") or source.contains("door_wall")
					break
			ancestor = ancestor.get_parent()
		if not structural:
			excluded.append(body.get_rid())
	var to_world := room.global_transform
	var gaps: Array[Dictionary] = []
	var door_pass := 0
	# 四个方向：(dx, dz, 侧名)。侧名按房间帧：-z=north，+z=south，+x=east，-x=west。
	var dirs := [
		[Vector2(0, -1), "north"],
		[Vector2(0, 1), "south"],
		[Vector2(1, 0), "east"],
		[Vector2(-1, 0), "west"],
	]
	for row in range(rows):
		for column in range(columns):
			var local_x := -half_x + (float(column) + 0.5) * CELL_M
			var local_z := -half_z + (float(row) + 0.5) * CELL_M
			if not _has_floor(tiles, local_x, local_z):
				continue
			for entry in dirs:
				var dir := entry[0] as Vector2
				var side := str(entry[1])
				var nx := local_x + dir.x * CELL_M
				var nz := local_z + dir.y * CELL_M
				if _has_floor(tiles, nx, nz):
					continue
				# 外围边：本格有砖、这个方向的邻格没有。
				var open_heights: Array[float] = []
				var blockers: Array[String] = []
				for height in RAY_HEIGHTS:
					# 桥坑护栏约 1.9m，头顶通透不是可走出的门洞；外墙仍查三个高度。
					var at_outer := absf(absf(local_x) - half_x) < 1.0 if side in ["east", "west"] else absf(absf(local_z) - half_z) < 1.0
					if not at_outer and float(height) > 1.9:
						continue
					var from_local := Vector3(
						local_x - dir.x * RAY_START_INSET_M + dir.x * (CELL_M * 0.5 - 0.1),
						float(height),
						local_z - dir.y * RAY_START_INSET_M + dir.y * (CELL_M * 0.5 - 0.1)
					)
					var to_local := Vector3(
						local_x + dir.x * (CELL_M * 0.5 + RAY_REACH_M),
						float(height),
						local_z + dir.y * (CELL_M * 0.5 + RAY_REACH_M)
					)
					var query := PhysicsRayQueryParameters3D.create(
						to_world * from_local, to_world * to_local
					)
					query.collision_mask = 1
					query.exclude = excluded
					query.collide_with_areas = false
					var hit := space.intersect_ray(query)
					if hit.is_empty():
						open_heights.append(float(height))
					else:
						var collider := hit.get("collider") as Node
						blockers.append(str(collider.name) if collider != null else "?")
				if open_heights.is_empty():
					continue
				var along := local_x if side in ["north", "south"] else local_z
				var in_door := false
				var outer_plane := absf(absf(local_x) - half_x) < 1.0 if side in ["east", "west"] else absf(absf(local_z) - half_z) < 1.0
				if lanes.has(side) and outer_plane:
					in_door = absf(along - float(lanes[side])) <= DOOR_HALF_WIDTH_M
				if in_door:
					door_pass += 1
					continue
				gaps.append({
					"side": side, "along": along, "x": local_x, "z": local_z,
					"open": open_heights,
				})
	if gaps.is_empty():
		print("    PASS 外围封闭（门洞内放行 %d 条射线）" % door_pass)
		return 0
	print("    FAIL 外围缺口 %d 条射线（门洞内放行 %d）：%s" % [
		gaps.size(), door_pass, _summarize(gaps),
	])
	if verbose:
		for gap in gaps:
			print("      · %s along=%+.1f 局部=(%.1f, %.1f) 空高度=%s" % [
				str(gap["side"]), float(gap["along"]), float(gap["x"]), float(gap["z"]),
				str(gap["open"]),
			])
	return gaps.size()


## 把缺口按「侧 + 沿墙区间」归并成一行行摘要。
func _summarize(gaps: Array[Dictionary]) -> String:
	var by_side := {}
	for gap in gaps:
		var side := str(gap["side"])
		if not by_side.has(side):
			by_side[side] = []
		(by_side[side] as Array).append(float(gap["along"]))
	var parts: Array[String] = []
	for side in by_side.keys():
		var values := by_side[side] as Array
		values.sort()
		parts.append("%s[%.1f~%.1f ×%d]" % [
			str(side), float(values[0]), float(values[values.size() - 1]), values.size(),
		])
	return "、".join(parts)


## 壳里还在场的「门墙件」落在哪一侧：定位「废门洞没封」。
func _print_baked_door_pieces(room: DungeonRoom3D) -> void:
	var texts: Array[String] = []
	for node in room.find_children("*", "Node3D", true, false):
		var piece := node as Node3D
		if piece == null or piece.scene_file_path.is_empty():
			continue
		var source := piece.scene_file_path
		if not (source.contains("wall_door") or source.contains("door_wall")):
			continue
		var local := room.global_transform.affine_inverse() * piece.global_position
		texts.append("%s@(%.1f,%.1f)" % [str(piece.name), local.x, local.z])
	if texts.is_empty():
		print("    壳内门墙件：无")
	else:
		print("    壳内门墙件：%s" % "、".join(texts))


## 诊断：列出房内所有带碰撞的盒子（房间局部坐标）与有场景来源的墙/角件。
func _dump_room(room: DungeonRoom3D) -> void:
	var inv := room.global_transform.affine_inverse()
	for node in room.find_children("*", "Node3D", true, false):
		var piece := node as Node3D
		if piece.scene_file_path.is_empty():
			continue
		var f := piece.scene_file_path.get_file()
		if f.contains("floor"):
			continue
		var local := inv * piece.global_position
		print("      [件] %s  %s  parent=%s  局部=(%.1f,%.1f,%.1f) rotY=%.0f" % [
			str(piece.name), f, str(piece.get_parent().name), local.x, local.y, local.z,
			rad_to_deg((inv.basis * piece.global_transform.basis).get_euler().y),
		])
	for value in room.find_children("*", "CollisionShape3D", true, false):
		var shape := value as CollisionShape3D
		var box := shape.shape as BoxShape3D
		if box == null or shape.disabled:
			continue
		var body := shape.get_parent() as CollisionObject3D
		if body == null:
			continue
		var c := inv * shape.global_position
		var basis := inv.basis * shape.global_transform.basis
		var size := (basis * box.size).abs()
		if size.y < 1.0:
			continue
		print("      [碰撞] %s/%s layer=%d 中心=(%.1f,%.1f,%.1f) 尺寸=(%.1f,%.1f,%.1f)" % [
			str(body.get_parent().name), str(body.name), body.collision_layer,
			c.x, c.y, c.z, size.x, size.y, size.z,
		])


func _door_lanes(room: DungeonRoom3D) -> Dictionary:
	var lanes := {}
	for side in ["north", "south", "east", "west"]:
		if not room.doors.has(side):
			continue
		lanes[side] = float(room.get_meta(
			"tower_wall_door_offset_%s" % side,
			room.get_meta("wall_door_lane_%s" % side, 0.0)
		))
	return lanes


func _floor_tiles(room: DungeonRoom3D) -> Array[AABB]:
	var out: Array[AABB] = []
	var to_local := room.global_transform.affine_inverse()
	var room_y := room.global_position.y
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not _visible_chain(mesh, room):
			continue
		var world := _world_aabb(mesh)
		if world.size.y > MAX_FLOOR_THICKNESS_M:
			continue
		var top_y := world.position.y + world.size.y - room_y
		if absf(top_y) > MAX_FLOOR_TOP_OFFSET_M:
			continue
		# 与产品侧同一口径：压条/缝条不是砖。
		if world.size.x * world.size.z < 4.0:
			continue
		var local_min := to_local * world.position
		var local_max := to_local * (world.position + world.size)
		out.append(AABB(
			Vector3(minf(local_min.x, local_max.x), 0.0, minf(local_min.z, local_max.z)),
			Vector3(absf(local_max.x - local_min.x), 1.0, absf(local_max.z - local_min.z))
		))
	return out


## 建房那一刻整棵支线树可能还没入树，`is_visible_in_tree()` 不可靠；沿父链看 visible。
func _visible_chain(node: Node, stop: Node) -> bool:
	var probe: Node = node
	while probe != null and probe != stop:
		if probe is Node3D and not (probe as Node3D).visible:
			return false
		if bool(probe.get_meta("editor_preview_only", false)):
			return false
		probe = probe.get_parent()
	return true


func _has_floor(tiles: Array[AABB], local_x: float, local_z: float) -> bool:
	for tile in tiles:
		var inside_x := (
			local_x >= tile.position.x - FLOOR_EPS_M
			and local_x <= tile.position.x + tile.size.x + FLOOR_EPS_M
		)
		var inside_z := (
			local_z >= tile.position.z - FLOOR_EPS_M
			and local_z <= tile.position.z + tile.size.z + FLOOR_EPS_M
		)
		if inside_x and inside_z:
			return true
	return false


func _world_aabb(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var xform := mesh.global_transform
	var box := AABB()
	var first := true
	for index in range(8):
		var corner := local.position + Vector3(
			local.size.x if (index & 1) else 0.0,
			local.size.y if (index & 2) else 0.0,
			local.size.z if (index & 4) else 0.0,
		)
		var point := xform * corner
		if first:
			box = AABB(point, Vector3.ZERO)
			first = false
		else:
			box = box.expand(point)
	return box
