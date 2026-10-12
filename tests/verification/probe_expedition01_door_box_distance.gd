extends Node
## 临时探针：量 room_01 / room_02 的**门**与**触发盒**在运行时真实几何下的相对位置，
## 并打印可走砖格矩阵（看清 L 形缺角），为「刷怪点离门太近，往里挪」提供数据依据。
##
## ⚠ 门节点可能是**跨房共享实体**（room_01 的 east 门 == room_02 的 west 门），
## 故门位一律用 `to_local(door.global_position)` 换算到**本房局部坐标系**，
## 再与 `spawn_placements[].center_m`（同为房局部）比较。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const ROOM_KEYS: Array[String] = ["room_01", "room_02"]

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	for value in tower._room_by_id.values():
		var room := value as DungeonRoom3D
		room.ensure_shell_built()
		room.ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("SEED=%d" % SEED_VALUE)
	for key in ROOM_KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("%s|MISSING" % key)
			continue
		_probe_room(key, room)
	print("PROBE_DONE")
	get_tree().quit(0)


func _probe_room(key: String, room: DungeonRoom3D) -> void:
	var dim := room.get_dimensions()
	print("\n## %s key=%s dim=%.1fx%.1f rot_y=%.1f tile_cells=%d" % [
		room.room_id, key, dim.x, dim.y, rad_to_deg(room.rotation.y),
		room._authored_tile_cells.size(),
	])
	print("   connection_ports:")
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		var pos := _vec2(port.get("position_m", []))
		print("      port %s -> %s  local=(%.1f, %.1f) side=%s lane=%.1f outward=%s" % [
			str(port.get("port_id", "")), str(port.get("target", "")),
			pos.x, pos.y, str(port.get("side", "")), float(port.get("lane_m", 0.0)),
			str(port.get("outward", [])),
		])
	print("   doors=%s targets=%s" % [str(room.doors), str(room.door_targets)])
	var door_points: Dictionary = {}
	for direction_value in room._door_nodes.keys():
		var direction := str(direction_value)
		var door := room._door_nodes[direction] as Node3D
		if door == null:
			continue
		var local := room.to_local(door.global_position)
		door_points[direction] = Vector2(local.x, local.z)
		print("   door[%s] LOCAL_IN_ROOM=(%.2f, %.2f) target=%s" % [
			direction, local.x, local.z, str(room.door_targets.get(direction, "")),
		])
	_print_tile_grid(room, dim)
	var placements := room.spawn_placements
	for index in range(placements.size()):
		var placement := placements[index] as Dictionary
		var box_id := str(placement.get("box", ""))
		var box := SpawnBoxCatalog.load_box(box_id)
		if box.is_empty():
			print("   box[%d] %s INVALID" % [index, box_id])
			continue
		var size := box.get("size_m", Vector2.ZERO) as Vector2
		var raw_size: Variant = placement.get("size_m", null)
		if raw_size is Array and (raw_size as Array).size() >= 2:
			size = Vector2(float((raw_size as Array)[0]), float((raw_size as Array)[1]))
		var rotation := float(placement.get("rotation_deg", 0.0))
		var spacing := float(box.get("min_spacing_m", 0.0))
		var recess := int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES))
		var center := _vec2(placement.get("center_m", []))
		var landed := room.resolve_spawn_box_center_local(
			center, size, 1, rotation, spacing, recess
		)
		var half := _aabb_half(size, rotation)
		print("   box[%d] %-18s size=%.0fx%.0f rot=%.0f declare=(%.1f, %.1f) landed=(%.1f, %.1f) drift=%.2f" % [
			index, box_id.replace("box_", ""), size.x, size.y, rotation,
			center.x, center.y, landed.x, landed.y, landed.distance_to(center),
		])
		var sorted_dirs: Array = door_points.keys()
		sorted_dirs.sort()
		for direction in sorted_dirs:
			var point: Vector2 = door_points[direction]
			print("      vs door[%-5s] center_dist=%5.2f  edge_dist=%5.2f  (%s)" % [
				str(direction), landed.distance_to(point),
				_point_aabb_distance(point, landed, half), _relative_side(landed, point),
			])


## 打印可走砖格矩阵：行 = 局部 y 从大到小，列 = 局部 x 从小到大。
## `#` = 有可走地砖；`.` = 无（缺口 / 不可达）；`B` = 盒心所在格。
func _print_tile_grid(room: DungeonRoom3D, dim: Vector2) -> void:
	var cells: Dictionary = {}
	for cell_value in room._authored_tile_cells:
		var cell := _cell_xy(cell_value)
		cells[Vector2i(roundi(cell.x * 2.0), roundi(cell.y * 2.0))] = true
	if not room._authored_tile_cells.is_empty():
		print("   tile_cell_sample=%s typeof=%d" % [
			str(room._authored_tile_cells[0]), typeof(room._authored_tile_cells[0]),
		])
	var box_cells: Dictionary = {}
	for placement_value in room.spawn_placements:
		var placement := placement_value as Dictionary
		var center := _vec2(placement.get("center_m", []))
		box_cells[Vector2i(roundi(center.x * 2.0), roundi(center.y * 2.0))] = true
	print("   tile_grid (rows: y=+%.1f -> %.1f, cols: x=%.1f -> +%.1f)" % [
		dim.y * 0.5, -dim.y * 0.5, -dim.x * 0.5, dim.x * 0.5,
	])
	var row_count := int(round(dim.y / 5.0))
	var col_count := int(round(dim.x / 5.0))
	var row_mark := "-" if true else ""
	for row in range(row_count):
		var y := dim.y * 0.5 - 2.5 - float(row) * 5.0
		var line := "      y=%+6.1f |" % y
		for col in range(col_count):
			var x := -dim.x * 0.5 + 2.5 + float(col) * 5.0
			var key := Vector2i(roundi(x * 2.0), roundi(y * 2.0))
			if box_cells.has(key):
				line += " B"
			elif cells.has(key):
				line += " #"
			else:
				line += " ."
		print(line)
	print("      %s" % row_mark)


## 旋转后的 AABB 半宽/半深（只支持 0/90/180/270，与判据 K 同口径）。
func _aabb_half(size: Vector2, rotation_deg: float) -> Vector2:
	var normalized := fposmod(rotation_deg, 360.0)
	if absf(normalized - 90.0) < 1.0 or absf(normalized - 270.0) < 1.0:
		return Vector2(size.y * 0.5, size.x * 0.5)
	return Vector2(size.x * 0.5, size.y * 0.5)


## 点到轴对齐矩形的**最短距离**（点在内部时为 0）。
func _point_aabb_distance(point: Vector2, center: Vector2, half: Vector2) -> float:
	var delta := Vector2(
		maxf(absf(point.x - center.x) - half.x, 0.0),
		maxf(absf(point.y - center.y) - half.y, 0.0)
	)
	return delta.length()


## 门相对盒心的方位（只做粗分类，便于人读）。
func _relative_side(box_center: Vector2, door: Vector2) -> String:
	var delta := door - box_center
	var parts: Array[String] = []
	if absf(delta.x) >= 0.5:
		parts.append("+x" if delta.x > 0.0 else "-x")
	if absf(delta.y) >= 0.5:
		parts.append("+y" if delta.y > 0.0 else "-y")
	return " ".join(parts) if not parts.is_empty() else "same"


func _vec2(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO


## 砖格元素的坐标提取（不同来源可能是 Vector2 / Vector2i / Vector3 / Array）。
func _cell_xy(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Vector2i:
		var int_cell := value as Vector2i
		return Vector2(float(int_cell.x), float(int_cell.y))
	if value is Vector3:
		var vec3 := value as Vector3
		return Vector2(vec3.x, vec3.z)
	return _vec2(value)
