extends Node
## 探针：入口安全房「四角 L 型墙角」在四种门向组合下的整房旋转一致性。
##
## 为什么需要它：四角 L 件按**世界角位**摆放（见 DungeonRoom3D._spawn_safe_room_corners），
## 「L 角 id ↔ 摆放位置 ↔ 旋转角」是一条跨函数、跨子系统的隐形契约。传错 id、或漏掉
## 整房旋转的置换环，任何几何校验都看不出来 —— 房间照样有 4 个角、4 段中段墙、9 块地砖，
## 但 L 的两条臂会悬在没有墙的那条边上、四条边各留一段缺口。
## 本探针把四角 L 件 + 中段墙的包围盒投影到四条边线上，要求四条边「±half 区间被铺满」，
## 把它变成一条会失败的断言。
##
## 同时守住塔楼口径：安全房不开四角 L 时仍是 12 段直墙（见 probe_safe_room_v007_integration）。
## 只读，不改任何运行内容。

const DOOR_COMBINATIONS: Array = [
	["east", "south"],
	["west", "south"],
	["east", "north"],
	["west", "north"],
]
const SIDES: Array[String] = ["north", "south", "west", "east"]
const TOLERANCE_M := 0.05
const CORNER_ASSET_ID := "ENV-TOWER-CORNER-L-5M"
const SOLID_WALL_ASSET_ID := "ENV-BATTLE-COMMON-WALL-STANDARD-5M"
const DOOR_WALL_ASSET_ID := "ENV-BATTLE-COMMON-WALL-DOOR-5M"

var failures: Array[String] = []


func _ready() -> void:
	print("=== 探针：安全房四角 L 型墙角 × 四种门向组合 ===")
	for combination in DOOR_COMBINATIONS:
		var doors: Array[String] = []
		for value in combination:
			doors.append(str(value))
		await _probe_room(doors)
	print("")
	if failures.is_empty():
		print("SAFE_ROOM_CORNER_L_ROTATION_OK")
	else:
		print("SAFE_ROOM_CORNER_L_ROTATION_FAIL: %d" % failures.size())
		for failure in failures:
			print("  - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _probe_room(doors: Array[String]) -> void:
	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": "probe_corner_l_%s" % "_".join(doors),
		"room_type": "STAIR_LOBBY",
		"size_class": "tower_cell",
		"doors": doors,
		"door_targets": {doors[0]: "probe_a", doors[1]: "probe_b"},
		"seed": 4242,
		"custom_dimensions": Vector2(15.0, 15.0),
		"tower_module_shell": true,
		"safe_room_corner_l": true,
	})
	add_child(room)
	room.ensure_shell_built()
	var half := room.get_dimensions() * 0.5
	var steps := int(room.get_meta("safe_room_orientation_steps", -99))
	print("  --- doors=[%s] steps=%d ---" % [", ".join(doors), steps])
	if steps < 0:
		failures.append("doors=[%s] 整房旋转步数解析失败" % [", ".join(doors)])
		room.queue_free()
		return

	var corners: Array = []
	var door_sides: Array[String] = []
	var solid_sides: Array[String] = []
	for value in room.find_children("*", "Node3D", true, false):
		var module := value as Node3D
		var asset_id := str(module.get_meta("asset_id", ""))
		var world_direction := str(module.get_meta("tower_wall_direction", ""))
		if asset_id == CORNER_ASSET_ID:
			corners.append(module)
		elif asset_id == DOOR_WALL_ASSET_ID:
			door_sides.append(world_direction)
		elif asset_id == SOLID_WALL_ASSET_ID:
			solid_sides.append(world_direction)

	var expected_corner_count := DungeonRoom3D.SAFE_ROOM_CORNER_IDS.size()
	_expect(
		corners.size() == expected_corner_count,
		"四角 L 件应为 %d 件，实测 %d" % [expected_corner_count, corners.size()],
		doors
	)
	var expected_solid_count := maxi(0, DungeonRoom3D.safe_room_middle_slot_count() - doors.size())
	_expect(
		solid_sides.size() == expected_solid_count,
		"实墙应为 %d 段，实测 %d %s" % [expected_solid_count, solid_sides.size(), solid_sides],
		doors
	)
	_expect(
		_sorted(door_sides) == _sorted(doors),
		"门墙世界朝向必须等于本房两扇门 %s，实测 %s" % [doors, door_sides],
		doors
	)
	for direction in solid_sides:
		_expect(
			direction not in doors,
			"实墙不得落在有门的那面墙：%s（门=%s）" % [direction, doors],
			doors
		)

	# L 角 id 必须与它所在的世界角位一致（判据由位置符号推出，不复述 _spawn_room_corner 的表）。
	for corner in corners:
		var node := corner as Node3D
		var corner_id := str(node.get_meta("tower_wall_corner", ""))
		_expect(
			absf(absf(node.position.x) - half.x) <= TOLERANCE_M
			and absf(absf(node.position.z) - half.y) <= TOLERANCE_M,
			"L 角 %s 必须落在房间角点 ±%s，实测 %s" % [corner_id, half, node.position],
			doors
		)
		_expect(
			corner_id == _corner_id_from_sign(node.position.x, node.position.z),
			"L 角 id 与所在世界角位不一致：id=%s 位置=%s" % [corner_id, node.position],
			doors
		)

	# 四条边必须被「L 臂 + 中段墙」的包围盒铺满。这一条同时锁住位置与旋转：
	# 只要某件 L 的朝向错了，它覆盖的区间就会跑到别的边上去，这条边立刻露缺口。
	var modules: Array = []
	modules.append_array(corners)
	for value in room.find_children("*", "Node3D", true, false):
		var asset_id := str((value as Node3D).get_meta("asset_id", ""))
		if asset_id == SOLID_WALL_ASSET_ID or asset_id == DOOR_WALL_ASSET_ID:
			modules.append(value)
	for side in SIDES:
		var boundary := _side_boundary(side, half)
		var intervals: Array = []
		for module in modules:
			var box := _relative_aabb(room, module as Node3D)
			if not _box_straddles_line(box, side, boundary):
				continue
			intervals.append(_box_span_along(box, side))
		_expect(
			_covers(intervals, -boundary, boundary),
			"%s 边（%s=%.2f）没有铺满：实测区间 %s" % [side, _side_axis(side), boundary, intervals],
			doors
		)
	print("      角=%d 实墙=%d 门墙=%d  四边覆盖检查完成" % [
		corners.size(), solid_sides.size(), door_sides.size()
	])
	room.queue_free()


func _side_axis(side: String) -> String:
	return "z" if side in ["north", "south"] else "x"


func _side_boundary(side: String, half: Vector2) -> float:
	match side:
		"north":
			return -half.y
		"south":
			return half.y
		"west":
			return -half.x
		_:
			return half.x


func _corner_id_from_sign(x: float, z: float) -> String:
	if x < 0.0 and z < 0.0:
		return "NW"
	if x > 0.0 and z < 0.0:
		return "NE"
	if x < 0.0 and z > 0.0:
		return "SW"
	return "SE"


func _box_straddles_line(box: AABB, side: String, boundary: float) -> bool:
	var low := box.position.z if side in ["north", "south"] else box.position.x
	var high := low + (box.size.z if side in ["north", "south"] else box.size.x)
	return low - TOLERANCE_M <= boundary and high + TOLERANCE_M >= boundary


func _box_span_along(box: AABB, side: String) -> Vector2:
	if side in ["north", "south"]:
		return Vector2(box.position.x, box.position.x + box.size.x)
	return Vector2(box.position.z, box.position.z + box.size.z)


## 区间并集是否从 start 一路连续盖到 end。
func _covers(intervals: Array, start: float, end: float) -> bool:
	if intervals.is_empty():
		return false
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var cursor := start
	for value in intervals:
		var span := value as Vector2
		if span.x > cursor + TOLERANCE_M:
			return false
		cursor = maxf(cursor, span.y)
	return cursor >= end - TOLERANCE_M


func _relative_aabb(root: Node3D, node: Node3D) -> AABB:
	var result := AABB()
	var has_result := false
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := _relative_transform(root, mesh_instance) * mesh_instance.get_aabb()
		if not has_result:
			result = box
			has_result = true
		else:
			result = result.merge(box)
	return result


func _relative_transform(root: Node, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy


func _expect(condition: bool, message: String, doors: Array[String]) -> void:
	if not condition:
		failures.append("[%s] %s" % [", ".join(doors), message])
