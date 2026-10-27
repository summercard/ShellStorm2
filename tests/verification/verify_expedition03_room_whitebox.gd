extends Node3D
## 白盒静态布局的**真实加载**验收（远征03 房间 / 通道 / 门 + EGT 全房型谱）。
##
## 为什么文本门禁不够：`check_expedition03_room_layouts.py` 只读文本。2026-10-27 那版
## 白盒把 `Transform3D` 的基写成带括号的 `(-1, 0, 0, …)`，**门禁全绿**，Godot 报
## `Parse Error` 整个场景加载失败。文本自洽 ≠ 引擎能读。
##
## 本场景逐份 instantiate，量五件事：
##
## 1. **能加载** —— instantiate 成功且根节点类型对。
## 2. **组件数对得上** —— 实际 MeshInstance3D 数 == `layout_instance_total`。
## 3. **地面不越出轮廓** —— 每一块 `Floor_*` 的四个角都必须落在 `footprint_polygon_m` 内。
##    这条专盯"矩形近似"这个缺陷：把 L 形做成矩形时，缺角处的格子会落在轮廓外。
## 4. **端口在轮廓线上** —— 每个 `Port_*` 的世界位置到最近轮廓边的距离 < 2cm。
## 5. **每面门数不超过该面槽数** —— `slot_count(格数)` 首尾各留一格不贴角，
##    所以 2 格能开 2 门、3 格反而只能开 1 门。超了就是几何放不下的坏房。
##
## 不做的事：不判材质、不判陈设、不判好不好看。白盒阶段没有那些东西。

const LAYOUT_DIRS := [
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03",
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/egt_room_types",
]
const DOOR_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components/whitebox_doors"
const EPS := 0.02
const GRID := 5.0

var _failures: Array[String] = []
var _checks := 0
var _rooms := 0
var _corridors := 0
var _doors := 0
var _egt := 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_layouts()
	await _verify_doors()
	_report()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## 从根节点元数据取轮廓多边形（footprint 坐标 → 房间局部 x/z）。
func _footprint(root: Node) -> PackedVector2Array:
	var points := PackedVector2Array()
	var raw: Variant = root.get_meta("footprint_polygon_m", [])
	if not (raw is Array):
		return points
	var size_meta: Variant = root.get_meta("size_m", [0.0, 0.0])
	var size := Vector2(float(size_meta[0]), float(size_meta[1]))
	for value in raw as Array:
		var pair := value as Array
		if pair.size() < 2:
			continue
		points.append(Vector2(float(pair[0]) - size.x * 0.5, float(pair[1]) - size.y * 0.5))
	return points


func _polygon_of_rect(width: float, depth: float) -> PackedVector2Array:
	var half := Vector2(width, depth) * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])


func _distance_to_outline(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		best = minf(best, point.distance_to(closest))
	return best


func _point_inside(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)


func _verify_layouts() -> void:
	for layout_dir in LAYOUT_DIRS:
		await _verify_layout_dir(layout_dir)


func _verify_layout_dir(layout_dir: String) -> void:
	var dir := DirAccess.open(layout_dir)
	if dir == null:
		_failures.append("打不开布局目录 %s" % layout_dir)
		return
	var names: Array[String] = []
	for file_name in dir.get_files():
		if not file_name.ends_with("_static_layout.tscn"):
			continue
		if file_name.begins_with("rt_") or file_name.begins_with("cr_") \
				or file_name.begins_with("egt_"):
			names.append(file_name)
	names.sort()
	_check(not names.is_empty(), "%s: 一份 rt_/cr_/egt_ TSCN 都没找到" % layout_dir)

	for file_name in names:
		var path := "%s/%s" % [layout_dir, file_name]
		if not ResourceLoader.exists(path):
			_failures.append("%s: ResourceLoader.exists 为 false（引擎认不出这个资源）" % file_name)
			continue
		var scene: PackedScene = load(path)
		if scene == null:
			_failures.append("%s: load() 返回 null（TSCN 解析失败）" % file_name)
			continue
		var root: Node = scene.instantiate()
		if root == null:
			_failures.append("%s: instantiate() 返回 null" % file_name)
			continue
		_check(root is Node3D, "%s: 根节点不是 Node3D" % file_name)
		add_child(root)
		await get_tree().process_frame

		if file_name.begins_with("cr_"):
			_corridors += 1
			_verify_corridor(file_name, root)
		elif file_name.begins_with("egt_"):
			_egt += 1
			_verify_room(file_name, root, true)
		else:
			_rooms += 1
			_verify_room(file_name, root, false)

		root.queue_free()
		await get_tree().process_frame


## 一面 count 格的墙允许开几个门槽（与 `RoomDoorLane.lane_offsets()` 同源）：
## 首尾各留一格不贴角 ⇒ 格数 >=3 时为 `格数-2`，否则等于格数。
func _slot_count(cells: int) -> int:
	return cells - 2 if cells >= 3 else cells


func _verify_room(file_name: String, root: Node, is_egt: bool) -> void:
	if is_egt:
		_check(root.has_meta("egt_kind"), "%s: 缺 metadata/egt_kind" % file_name)
		_check(root.has_meta("door_sides"), "%s: 缺 metadata/door_sides（门面组合）" % file_name)
	else:
		_check(root.has_meta("template_id"), "%s: 缺 metadata/template_id" % file_name)
	_check(not root.has_meta("room_id"),
		"%s: 绑定了具体房间（写了 metadata/room_id）—— 共享壳会失效" % file_name)

	var polygon := _footprint(root)
	if polygon.size() < 3:
		_failures.append("%s: footprint_polygon_m 不足 3 点" % file_name)
		return
	# 轮廓必须是逆时针且面积为正（否则"内部/外部"判断整体反了）
	_check(Geometry2D.is_polygon_clockwise(polygon) == false,
		"%s: 轮廓顶点不是逆时针（点序反了会让地面判定整体反相）" % file_name)

	var declared := int(root.get_meta("layout_instance_total", -1))
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	_check(meshes.size() == declared,
		"%s: 实际 MeshInstance3D %d != layout_instance_total %d" % [file_name, meshes.size(), declared])

	# 地面块四角必须在轮廓内 —— 这条专抓"矩形近似"
	var floors := 0
	var outside := 0
	for mesh in meshes:
		if not str(mesh.name).begins_with("Floor_"):
			continue
		floors += 1
		var size: Vector3 = (mesh.mesh as BoxMesh).size if mesh.mesh is BoxMesh else Vector3.ZERO
		var center := Vector2(mesh.position.x, mesh.position.z)
		var half := Vector2(size.x, size.z) * 0.5
		for corner in [
			center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
			center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
		]:
			if not _point_inside(corner as Vector2, polygon):
				outside += 1
				break
	_check(floors > 0, "%s: 一块地面都没有" % file_name)
	_check(outside == 0,
		"%s: 有 %d 块地面越出轮廓（L/U/缺角房被做成了矩形）" % [file_name, outside])

	# 端口必须落在轮廓线上
	var ports := root.find_child("ConnectionPorts", true, false)
	if ports == null:
		_failures.append("%s: 缺 ConnectionPorts" % file_name)
		return
	var declared_ports := int(root.get_meta("connection_port_count", -1))
	_check(ports.get_child_count() == declared_ports,
		"%s: 端口节点 %d != connection_port_count %d" % [
			file_name, ports.get_child_count(), declared_ports])
	var per_side := {}
	for port in ports.get_children():
		var marker := port as Node3D
		if marker == null:
			continue
		var point := Vector2(marker.position.x, marker.position.z)
		var distance := _distance_to_outline(point, polygon)
		_check(distance < EPS,
			"%s: 端口 %s 离轮廓 %.3fm（应贴在轮廓外墙上，门才开得通）" % [
				file_name, marker.name, distance])
		_check(marker.has_meta("lane_m") and marker.has_meta("side"),
			"%s: 端口 %s 缺 lane_m / side" % [file_name, marker.name])
		if marker.has_meta("side"):
			var side := str(marker.get_meta("side"))
			per_side[side] = int(per_side.get(side, 0)) + 1

	# 每面门数必须放得进该面墙的槽位。slot_count 非单调（2 格 2 槽、3 格 1 槽），
	# 这条能抓「把 2 扇门挤在只有 1 个槽的墙上」——几何上放不下的坏房。
	var size_meta: Variant = root.get_meta("size_m", [])
	if (size_meta as Array).size() >= 2:
		var width := float(size_meta[0])
		var depth := float(size_meta[1])
		for side in per_side:
			var wall_len := width if side in ["north", "south"] else depth
			var slots := _slot_count(int(round(wall_len / GRID)))
			_check(int(per_side[side]) <= slots,
				"%s: %s 面要开 %d 扇门，但 %.0fm 墙只有 %d 个合法槽位" % [
					file_name, side, per_side[side], wall_len, slots])
		if is_egt:
			# EGT 谱是「房型 × 门面组合」，门数必须与 door_sides 声明一致
			var declared_sides := str(root.get_meta("door_sides", ""))
			var total := 0
			for side in per_side:
				total += int(per_side[side])
			var expected := 0
			for ch in declared_sides:
				if ch.is_valid_int():
					expected += ch.to_int()
			_check(total == expected,
				"%s: 实际门 %d 扇，door_sides=%s 声明 %d 扇" % [
					file_name, total, declared_sides, expected])
			_check(int(root.get_meta("door_count", -1)) == total,
				"%s: door_count %s != 实际门数 %d" % [
					file_name, str(root.get_meta("door_count", -1)), total])


func _verify_corridor(file_name: String, root: Node) -> void:
	_check(root.has_meta("shell_id"), "%s: 缺 metadata/shell_id" % file_name)
	_check(not root.has_meta("room_id"),
		"%s: 通道路径绑定了具体房间（写了 metadata/room_id）" % file_name)
	var size_meta: Variant = root.get_meta("size_m", [])
	if (size_meta as Array).size() < 2:
		_failures.append("%s: 缺 metadata/size_m" % file_name)
		return
	var polygon := _polygon_of_rect(float(size_meta[0]), float(size_meta[1]))

	var declared := int(root.get_meta("layout_instance_total", -1))
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	_check(meshes.size() == declared,
		"%s: 实际 MeshInstance3D %d != layout_instance_total %d" % [file_name, meshes.size(), declared])

	var outside := 0
	for mesh in meshes:
		if not str(mesh.name).begins_with("Floor_"):
			continue
		var center := Vector2(mesh.position.x, mesh.position.z)
		if not _point_inside(center, polygon):
			outside += 1
	_check(outside == 0, "%s: %d 块地面越出通道净宽" % [file_name, outside])

	var ports := root.find_child("ConnectionPorts", true, false)
	if ports == null:
		_failures.append("%s: 缺 ConnectionPorts" % file_name)
		return
	var declared_ports := int(root.get_meta("connection_port_count", -1))
	_check(ports.get_child_count() == declared_ports,
		"%s: 端口节点 %d != connection_port_count %d" % [
			file_name, ports.get_child_count(), declared_ports])
	# 通道端口必须贴在矩形边界上（两侧内缩 0 —— 通道窄，端口就在墙线上）
	for port in ports.get_children():
		var marker := port as Node3D
		if marker == null:
			continue
		var point := Vector2(marker.position.x, marker.position.z)
		_check(_distance_to_outline(point, polygon) < EPS,
			"%s: 端口 %s 不在通道边界上" % [file_name, marker.name])


func _verify_doors() -> void:
	var dir := DirAccess.open(DOOR_DIR)
	if dir == null:
		_failures.append("打不开门扇目录 %s" % DOOR_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tscn"):
			continue
		var path := "%s/%s" % [DOOR_DIR, file_name]
		var scene: PackedScene = load(path)
		if scene == null:
			_failures.append("%s: load() 返回 null（门扇 TSCN 解析失败）" % file_name)
			continue
		var root: Node = scene.instantiate()
		if root == null:
			_failures.append("%s: instantiate() 返回 null" % file_name)
			continue
		_doors += 1
		add_child(root)
		await get_tree().process_frame
		_check(root is Node3D, "%s: 门扇根不是 Node3D" % file_name)
		_check(root.has_meta("door_kind"), "%s: 门扇缺 metadata/door_kind" % file_name)
		_check(root.has_meta("asset_id"), "%s: 门扇缺 metadata/asset_id（运行时读它填 visual_asset_id）" % file_name)
		# 门扇几何必须盖住门洞：2.2 × 2.5 × 0.18，且原点在底面中心
		var bounds := _bounds_of(root as Node3D)
		_check(absf(bounds.size.x - 2.2) < 0.35,
			"%s: 门扇宽 %.2fm，离 2.2m 门洞太远" % [file_name, bounds.size.x])
		_check(absf(bounds.size.y - 2.5) < 0.15,
			"%s: 门扇高 %.2fm，离 2.5m 净高太远" % [file_name, bounds.size.y])
		var feet := bounds.position.y
		_check(absf(feet) < 0.06,
			"%s: 门扇底面在 y=%.3f，应为 0（原点契约 = 底面中心）" % [file_name, feet])
		root.queue_free()
		await get_tree().process_frame


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _bounds_of(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in _all_meshes(root):
		var box: AABB = mesh.transform * (mesh.mesh as BoxMesh).get_aabb() \
			if mesh.mesh is BoxMesh else AABB()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(node, out)
	return out


func _report() -> void:
	print("WHITEBOX_CHECKED rooms=%d egt_types=%d corridors=%d doors=%d checks=%d"
		% [_rooms, _egt, _corridors, _doors, _checks])
	if _failures.is_empty():
		print("EXPEDITION03_WHITEBOX_OK rooms=%d egt_types=%d corridors=%d doors=%d"
			% [_rooms, _egt, _corridors, _doors])
		get_tree().quit(0)
		return
	for failure in _failures:
		printerr("WHITEBOX FAIL: %s" % failure)
	print("EXPEDITION03_WHITEBOX_FAILED failures=%d" % _failures.size())
	get_tree().quit(1)
