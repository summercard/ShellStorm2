extends Node

## 一次性探针（业主 2026-10-22）：「支线场景的位置会飘逸。角色会跑到房间外面去。」
##
## 两个说法都要**量**出来，不能靠看：
##   ① 「位置飘逸」 —— 逐间打印支线房的世界中心 / 尺寸 / 壳转角 / 门位，
##      并给出**房间实际脚印**（地砖铺到的范围）与声明尺寸的差；
##   ② 「跑到房间外」 —— 把房间帧切成 1 m 网格，逐格判定三件事：
##        · 这一格**地砖**铺到了吗（美术地砖 AABB 覆盖）
##        · 这一格**承重板**铺到了吗（`SecretFloorSupport` 的 BoxShape 覆盖）
##        · 这一格在**房间轮廓内**吗（= 地砖判定，房间的可走区）
##      凡是「承重板实心、但地砖没铺」的格子，就是**玩家能走到的房间外**。
##      这些格子按位置分组打出来，业主说的「跑到外面」应该就是它们。
##
## 另外逐扇门检查：门洞中心那一格是不是在轮廓内。门开在凹口（房间外）时，
## 玩家一出门就站在虚空上，观感同样是「在房间外面飘」。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_secret_branch_footprint.tscn
##   SS2_PAIR=0 只查一条子图链。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
## 采样网格（m）。1 m 足够看出「30×25 的凹口」这个量级的问题。
const CELL_M := 2.0
## 判定「这一格有地砖」的容差：格心离地砖 AABB 至少这么近。
const FLOOR_EPS_M := 0.35
## 承重板厚度，与 `SecretBranch3D.BRANCH_FLOOR_SUPPORT_THICKNESS_M` 同值。
const SUPPORT_THICKNESS_M := 0.30
## 判「这是地砖」用：网格件本身的厚度上限（m）。
const MAX_FLOOR_THICKNESS_M := 0.8
## 判「这是地砖」用：顶面离房间地面（y=0）的允许偏差（m）。
const MAX_FLOOR_TOP_OFFSET_M := 0.4

var _branch: Node = null


func _ready() -> void:
	var want_pair := OS.get_environment("SS2_PAIR")
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)

	# 等到房间与子图都建好。子图在 bootstrap 之后，比主路晚。
	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			_branch = _find_branch(tower)
			if _branch != null:
				for _i in range(8):
					await get_tree().process_frame
				break

	if _branch == null:
		print("找不到 SecretBranch3D 节点")
		get_tree().quit(1)
		return

	print("")
	print("=== 支线脚印审计 ===")
	var roots: Array[Node3D] = []
	for child in _branch.get_children():
		var node := child as Node3D
		if node != null and str(node.name).begins_with("SecretBranch_"):
			if not want_pair.is_empty() and str(node.name) != "SecretBranch_%s" % want_pair:
				continue
			roots.append(node)
	if roots.is_empty():
		print("  没有 SecretBranch 根（本局没抽到支线？）")
		print("SECRET_BRANCH_FOOTPRINT_END")
		get_tree().quit(0)
		return

	var total_escape := 0
	for root in roots:
		total_escape += _audit_root(root)
	print("")
	if total_escape == 0:
		print("  ✅ 没有「承重板实心但地砖没铺」的格子 —— 玩家走不出房间轮廓")
	else:
		print("  🔴 共 %d 格「能站但已在房间外」 —— 这就是角色跑到房间外的来源" % total_escape)
	print("SECRET_BRANCH_FOOTPRINT_END")
	get_tree().quit(0)


func _find_branch(root: Node) -> Node:
	for node in root.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("SecretBranch3D.gd"):
			return node
	return null


func _audit_root(root: Node3D) -> int:
	var rooms: Array[DungeonRoom3D] = []
	for node in root.find_children("*", "", true, false):
		var room := node as DungeonRoom3D
		if room != null:
			rooms.append(room)
	rooms.sort_custom(func(a: DungeonRoom3D, b: DungeonRoom3D) -> bool:
		return a.global_position.x < b.global_position.x
	)
	print("")
	print("── %s：%d 间房 ──" % [root.name, rooms.size()])
	var support_body := root.get_node_or_null("SecretFloorSupport") as StaticBody3D
	var escape := 0
	for room in rooms:
		escape += _audit_room(room, support_body)
	return escape


func _audit_room(room: DungeonRoom3D, support_body: StaticBody3D) -> int:
	var dims := room.get_dimensions()
	var center := room.global_position
	var art := _art_root(room)
	var art_deg := rad_to_deg(art.rotation.y) if art != null else 0.0
	print("")
	print("  房间 %-14s 世界=(%8.2f, %8.2f)  尺寸=%.0f×%.0f  壳转=%+.0f°  门=%s" % [
		str(room.room_id), center.x, center.z, dims.x, dims.y, art_deg, str(room.doors),
	])

	# 地砖（房间帧 AABB 集合）与门位
	var tiles := _floor_tiles(room)
	var lanes := _door_lanes(room)
	if tiles.is_empty():
		print("    （一件地砖都没量到 —— 壳没建或美术缺失）")
		return 0

	var tile_bounds := _merge_bounds(tiles)
	print("    地砖脚印：x %.1f~%.1f（%.1f）  z %.1f~%.1f（%.1f）  块数=%d" % [
		tile_bounds.position.x, tile_bounds.end.x, tile_bounds.size.x,
		tile_bounds.position.z, tile_bounds.end.z, tile_bounds.size.z, tiles.size(),
	])
	# ⚠️ 这里**不要**去调产品侧的 `_shared_shell_footprint()` 做交叉核对：
	# 它会离树实例化一份壳场景，在探针里调用会把进程拖到超时（实测 150 s 被杀）。
	# 判「门洞在不在砖上」用**房间帧实测地砖**就够了 —— 那才是渲染出来的真值。
	print("    房间声明：x %.1f~%.1f（%.1f）  z %.1f~%.1f（%.1f）" % [
		-dims.x * 0.5, dims.x * 0.5, dims.x, -dims.y * 0.5, dims.y * 0.5, dims.y,
	])
	for side in lanes.keys():
		print("    门 %-5s lane=%+.1f → 世界 (%8.2f, %8.2f)" % [
			str(side), float(lanes[side]),
			center.x + (dims.x * 0.5 if side == "east" else -dims.x * 0.5 if side == "west" else float(lanes[side])),
			center.z + (dims.y * 0.5 if side == "south" else -dims.y * 0.5 if side == "north" else float(lanes[side])),
		])

	# 逐格：地砖 / 承重板 / 轮廓
	var columns := int(round(dims.x / CELL_M))
	var rows := int(round(dims.y / CELL_M))
	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	var escape_cells: Array[Vector2] = []
	var grid: Array[String] = []
	for row in range(rows):
		var line := ""
		for column in range(columns):
			var local_x := -half_x + (float(column) + 0.5) * CELL_M
			var local_z := -half_z + (float(row) + 0.5) * CELL_M
			var has_tile := _has_floor(tiles, local_x, local_z)
			var has_support := _has_support(support_body, center + Vector3(local_x, 0.0, local_z))
			if has_tile:
				line += "#"
			elif has_support:
				line += "!"
				escape_cells.append(Vector2(local_x, local_z))
			else:
				line += "."
		grid.append(line)

	print("    俯视（# 地砖   ! 只有承重板=能站但房间外   . 虚空）：")
	for line in grid:
		print("      %s" % line)
	# 逐格对账：把「产品侧承重盒覆盖」与「探针侧地砖覆盖」并排，找出差在哪一格。
	if OS.get_environment("SS2_DEBUG_CELLS") == "1":
		print("    逐格对账（地砖/承重）：")
		for row in range(rows):
			var line := ""
			for column in range(columns):
				var local_x := -half_x + (float(column) + 0.5) * CELL_M
				var local_z := -half_z + (float(row) + 0.5) * CELL_M
				var has_tile := _has_floor(tiles, local_x, local_z)
				var has_support := _has_support(support_body, center + Vector3(local_x, 0.0, local_z))
				if has_tile and has_support:
					line += "A"
				elif has_tile:
					line += "t"
				elif has_support:
					line += "s"
				else:
					line += "."
			print("      %s" % line)
		print("      A=地砖+承重  t=只有地砖(会掉)  s=只有承重(能走出房间)  .=都没有")

	# 门洞是否落在轮廓内
	for side in lanes.keys():
		var lane := float(lanes[side])
		var probe := Vector2.ZERO
		match str(side):
			"north": probe = Vector2(lane, -half_z)
			"south": probe = Vector2(lane, half_z)
			"east": probe = Vector2(half_x, lane)
			_: probe = Vector2(-half_x, lane)
		var on_floor := _has_floor(tiles, probe.x, probe.y)
		print("    门 %-5s 洞口在轮廓内：%s" % [str(side), "是" if on_floor else "**否（开在房间外）**"])

	# 门位扫描：哪些槽位能让**本房所有门**都落在真实脚印上。
	#
	# 子图链沿 X 串联、两门必须同轴（lane 相同），所以只有「交集」里的槽位可用。
	# ⚠️ 槽位不能随便取 5 m 整数：模板 `wall_lane_table` 的东西向槽是 **2.5 m 一档**
	# （corridor_45x40 = [-12.5,-7.5,-2.5,2.5,7.5,12.5]）。设计规范要求门位落在模板槽上，
	# 所以这里按 2.5 m 扫，与模板同粒度。
	if not lanes.is_empty():
		var legal: Array[float] = []
		var span := dims.y
		var slot := -floorf(span * 0.5 / 2.5) * 2.5
		while slot <= span * 0.5 + 0.01:
			var ok := true
			for side in lanes.keys():
				var probe := Vector2.ZERO
				match str(side):
					"north": probe = Vector2(slot, -half_z)
					"south": probe = Vector2(slot, half_z)
					"east": probe = Vector2(half_x, slot)
					_: probe = Vector2(-half_x, slot)
				if not _has_floor(tiles, probe.x, probe.y):
					ok = false
					break
			if ok:
				legal.append(slot)
			slot += 2.5
		if legal.is_empty():
			print("    🔴 没有任何 2.5 m 槽位能让所有门都落在真实脚印上 —— 这个壳不适合东西串联")
		else:
			var texts: Array[String] = []
			for value in legal:
				texts.append("%+.1f" % value)
			var current: Array[String] = []
			for side in lanes.keys():
				current.append("%s=%+.1f" % [str(side), float(lanes[side])])
			print("    可用门位槽：%s（当前 %s）" % ["、".join(texts), "、".join(current)])

	if not escape_cells.is_empty():
		print("    🔴 能站但房间外 %d 格（%d m²）：%s" % [
			escape_cells.size(), int(escape_cells.size() * CELL_M * CELL_M),
			_describe_region(escape_cells, half_x, half_z),
		])
	return escape_cells.size()


## 把「逃逸格」按象限归成一句话：哪一角/哪一边。
func _describe_region(cells: Array[Vector2], half_x: float, half_z: float) -> String:
	var east := 0
	var west := 0
	var north := 0
	var south := 0
	for cell in cells:
		if cell.x > 0.5:
			east += 1
		elif cell.x < -0.5:
			west += 1
		if cell.y > 0.5:
			south += 1
		elif cell.y < -0.5:
			north += 1
	var parts: Array[String] = []
	if east > west * 2:
		parts.append("偏东")
	elif west > east * 2:
		parts.append("偏西")
	if south > north * 2:
		parts.append("偏南")
	elif north > south * 2:
		parts.append("偏北")
	var xs: Array[float] = []
	var zs: Array[float] = []
	for cell in cells:
		xs.append(cell.x)
		zs.append(cell.y)
	xs.sort()
	zs.sort()
	var head := "、".join(parts) if not parts.is_empty() else "散布"
	return "%s；x %.1f~%.1f  z %.1f~%.1f" % [
		head, xs[0], xs[xs.size() - 1], zs[0], zs[zs.size() - 1],
	]


func _art_root(room: DungeonRoom3D) -> Node3D:
	for child in room.get_children():
		if child is Node3D and str(child.name) in ["AuthoredLayoutArtRoot", "SafeRoomArtRoot"]:
			return child as Node3D
	return null


## 地砖 = **水平薄片且顶面贴地**的网格件。
##
## 为什么不按名字筛：子图的共享壳是**嵌套子场景**（`f00_secret_shared_corridor_45x40`
## 里只有一个 `Room01` 实例），真正的 `TILE_R00_C00` 在更深的层级，靠实例根名字
## 一律拿不到（实测一件都量不到）。几何判据不依赖命名，也不会把墙（11.9 m 高）
## 或家具（比 0.8 m 厚）算进来。
func _floor_tiles(room: DungeonRoom3D) -> Array[AABB]:
	var out: Array[AABB] = []
	var to_local := room.global_transform.affine_inverse()
	var room_y := room.global_position.y
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree():
			continue
		var world := _world_aabb(mesh)
		if world.size.y > MAX_FLOOR_THICKNESS_M:
			continue
		var top_y := world.position.y + world.size.y - room_y
		if absf(top_y) > MAX_FLOOR_TOP_OFFSET_M:
			continue
		var local_min := to_local * world.position
		var local_max := to_local * (world.position + world.size)
		out.append(AABB(
			Vector3(minf(local_min.x, local_max.x), 0.0, minf(local_min.z, local_max.z)),
			Vector3(absf(local_max.x - local_min.x), 1.0, absf(local_max.z - local_min.z))
		))
	return out


## ⚠️ GDScript 没有反斜杠续行 —— 长条件一律用括号跨行（写成 `\` 会让整份脚本解析失败，
## 而场景根是裸 Node、`_ready` 不存在 ⇒ 探针不跑也不退出，看着像卡死）。
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


func _has_support(body: StaticBody3D, world_point: Vector3) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var box := shape_node.shape as BoxShape3D
		if box == null:
			continue
		var center := shape_node.global_position
		var half := box.size * 0.5
		if absf(world_point.x - center.x) <= half.x and absf(world_point.z - center.z) <= half.z:
			return true
	return false


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


func _merge_bounds(boxes: Array[AABB]) -> AABB:
	var result := boxes[0]
	for index in range(1, boxes.size()):
		result = result.merge(boxes[index])
	return result


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
