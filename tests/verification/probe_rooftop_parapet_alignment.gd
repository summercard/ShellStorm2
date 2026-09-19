extends Node
## 天台女儿墙装配对齐探针。
## 实测 TowerFloorStage3D 装完后的 64 段直段 + 4 件转角件，在四条边上是否
## 「无缝且不重叠」，以及转角件是否正好坐在 2.5m 让位区内。
## 纯诊断，不算门禁；输出 PROBE_ALIGN_* 行供比对。
##
## ⚠️ 历史上必须带窗口跑（不要加 --headless）：MultiMesh 的实例变换存在
## RenderingServer 侧，dummy 渲染器下 get_instance_transform() 一律回读成单位
## 阵，会让直段全部「消失」并误报整条边缺 85m。那是探针的读法限制，不是装配错。
##
## 2026-09-19：直段包络改为读 TowerFloorStage3D 自己的**槽位表**（普通 Array），
## 不再读 MultiMesh 实例变换，所以本探针现在 headless 也能跑对。上面那条窗口要求
## 对「仍想从 MultiMesh 回读实例变换」的写法继续成立，保留作为说明。

const ROOFTOP_WORLD_RECT := Rect2(-50.0, -35.0, 90.0, 80.0)
const CORNER_ARM_M := 2.5
const EDGE_TOLERANCE := 0.01

var _failures: Array[String] = []


func _ready() -> void:
	var rooftop := TowerFloorStage3D.new()
	rooftop.configure(0, "rooftop", ["west"])
	add_child(rooftop)
	await get_tree().process_frame
	await get_tree().physics_frame

	var outer := rooftop.get("_outer_visual") as MultiMeshInstance3D
	if outer == null or outer.multimesh == null:
		print("PROBE_ALIGN_FAIL outer multimesh missing")
		get_tree().quit(1)
		return
	var mesh_aabb := outer.multimesh.mesh.get_aabb()
	# 2026-09-19：直段可视件改为「按种子随机分档」——intact + 崩顶/贯穿/塌脚三件
	# 破损变体各占一个 MultiMesh 批次，所以「直段槽位」不再等于 _outer_visual 这一个
	# MultiMesh 的实例（那是完好档的件数，本种子下是 44）。
	# 槽位真源改为 TowerFloorStage3D.get_outer_straight_slot_transforms()：破损只换
	# 外观、不挪槽位，所以「每条边覆盖到哪」与破损比例完全无关。
	# 破损件与 intact 件包络逐值相同（probe_rooftop_parapet_damage_prefabs 已证），
	# 因此这里继续统一用 intact 的 mesh AABB 算槽位包络是成立的。
	var slot_transforms: Array = rooftop.call("get_outer_straight_slot_transforms")
	var segment_spans: Array[Rect2] = []
	for slot_transform in slot_transforms:
		segment_spans.append(_world_xz(slot_transform as Transform3D, mesh_aabb))
	var corner_spans: Array[Rect2] = []
	var corner_names: Array[String] = ["SW", "SE", "NE", "NW"]
	for corner_name in corner_names:
		var corner := rooftop.find_child(
			"RooftopOuterCorner_%s" % corner_name, false, false
		) as Node3D
		if corner == null:
			_failures.append("缺少转角件 %s" % corner_name)
			continue
		corner_spans.append(_node_xz(corner))

	var door_spans: Array[Rect2] = []
	_collect_prefixed_spans(rooftop, "ParapetDoorWall_", door_spans)

	# 哨兵：数量不对说明装配没跑起来，后面的覆盖判定会假绿。
	print(
		"PROBE_ALIGN counts segments=%d corners=%d doorway_walls=%d"
		% [segment_spans.size(), corner_spans.size(), door_spans.size()]
	)
	_expect(segment_spans.size() == 61, "直段实例数不是61（64段-西侧门洞3段）")
	_expect(corner_spans.size() == 4, "转角件不是4件")
	_expect(door_spans.size() == 3, "门洞补位墙不是3件")

	# 周长壳体的成员 = 直段 + 转角件 + 门洞补位墙。门洞墙中间有 2m 通行口，但它
	# 占满该 5m 槽位的足迹；「不许有裸缺口」这条契约对两者一视同仁。
	var module_spans: Array[Rect2] = segment_spans.duplicate()
	module_spans.append_array(corner_spans)
	module_spans.append_array(door_spans)

	var rect := ROOFTOP_WORLD_RECT
	var inset := 0.25
	_check_edge("north", rect.position.x, rect.end.x, rect.position.y + inset, module_spans)
	_check_edge("south", rect.position.x, rect.end.x, rect.end.y - inset, module_spans)
	_check_edge("west", rect.position.y, rect.end.y, rect.position.x + inset, module_spans)
	_check_edge("east", rect.position.y, rect.end.y, rect.end.x - inset, module_spans)

	_check_corner_seats(rect, corner_spans)

	if _failures.is_empty():
		print("PROBE_ALIGN_DONE all_edges_seamless=true corners_seated=true")
	else:
		for failure in _failures:
			print("PROBE_ALIGN_FAIL %s" % failure)
		print("PROBE_ALIGN_DONE failures=%d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


## 检查一条边：把「贴着这条 boundary 的模块」沿边方向排开，
## 看覆盖区间是否恰好铺满全长、且相邻区间不重叠。
func _check_edge(
	label: String,
	along_start: float,
	along_end: float,
	boundary: float,
	module_spans: Array[Rect2]
) -> void:
	var horizontal := label in ["north", "south"]
	var intervals: Array[Vector2] = []
	for span in module_spans:
		# 只有横跨该 boundary 的模块才算这条边的成员。boundary 是一条与边平行
		# 的直线，所以要用「垂直于边」的那个轴去比对：东西边看 X，南北边看 Z。
		var lo := span.position.y
		var hi := span.position.y + span.size.y
		if not horizontal:
			lo = span.position.x
			hi = span.position.x + span.size.x
		if lo > boundary + EDGE_TOLERANCE:
			continue
		if hi < boundary - EDGE_TOLERANCE:
			continue
		intervals.append(
			Vector2(span.position.x, span.position.x + span.size.x)
			if horizontal
			else Vector2(span.position.y, span.position.y + span.size.y)
		)
	intervals.sort_custom(func(a, b): return a.x < b.x)
	var cursor := along_start
	var gap_total := 0.0
	var overlap_total := 0.0
	for interval in intervals:
		if interval.y <= cursor + EDGE_TOLERANCE:
			overlap_total += maxf(0.0, cursor - interval.y)
			cursor = maxf(cursor, interval.y)
			continue
		gap_total += interval.x - cursor
		cursor = interval.y
	if cursor < along_end - EDGE_TOLERANCE:
		gap_total += along_end - cursor
	var coverage := along_end - along_start - gap_total
	print(
		"PROBE_ALIGN edge=%-5s members=%2d coverage=%.3f/%.3f gap=%.3f overlap=%.3f"
		% [label, intervals.size(), coverage, along_end - along_start, gap_total, overlap_total]
	)
	_expect(not intervals.is_empty(), "%s 边没有任何模块" % label)
	_expect(gap_total <= EDGE_TOLERANCE, "%s 边有 %.3fm 缺口" % [label, gap_total])
	_expect(overlap_total <= EDGE_TOLERANCE, "%s 边有 %.3fm 重叠" % [label, overlap_total])


## 转角件应正好坐进该角 2.5m 的让位区：包络 = 2.5×2.5，且内角贴着 rect 角点。
func _check_corner_seats(rect: Rect2, corner_spans: Array[Rect2]) -> void:
	var seats := [
		Rect2(rect.position.x, rect.position.y, CORNER_ARM_M, CORNER_ARM_M),
		Rect2(rect.end.x - CORNER_ARM_M, rect.position.y, CORNER_ARM_M, CORNER_ARM_M),
		Rect2(rect.end.x - CORNER_ARM_M, rect.end.y - CORNER_ARM_M, CORNER_ARM_M, CORNER_ARM_M),
		Rect2(rect.position.x, rect.end.y - CORNER_ARM_M, CORNER_ARM_M, CORNER_ARM_M),
	]
	for index in range(corner_spans.size()):
		var span: Rect2 = corner_spans[index]
		print(
			"PROBE_ALIGN corner=%s span=(%.3f,%.3f) size=(%.3f,%.3f)"
			% [index, span.position.x, span.position.y, span.size.x, span.size.y]
		)
		_expect(
			is_equal_approx(span.size.x, CORNER_ARM_M) and is_equal_approx(span.size.y, CORNER_ARM_M),
			"转角件%d 包络不是%.1f×%.1f" % [index, CORNER_ARM_M, CORNER_ARM_M]
		)
		var seated := false
		for seat in seats:
			if span.position.is_equal_approx(seat.position):
				seated = true
				break
		_expect(seated, "转角件%d 没有坐进任一2.5m让位区：%s" % [index, span.position])


func _world_xz(transform: Transform3D, aabb: AABB) -> Rect2:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for bits in range(8):
		var local := Vector3(
			aabb.position.x + (aabb.size.x if (bits & 1) != 0 else 0.0),
			aabb.position.y + (aabb.size.y if (bits & 2) != 0 else 0.0),
			aabb.position.z + (aabb.size.z if (bits & 4) != 0 else 0.0)
		)
		var world := transform * local
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_z = minf(min_z, world.z)
		max_z = maxf(max_z, world.z)
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


func _node_xz(node: Node3D) -> Rect2:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var instance := current as MeshInstance3D
			if instance.mesh != null:
				var span := _world_xz(instance.global_transform, instance.mesh.get_aabb())
				min_x = minf(min_x, span.position.x)
				max_x = maxf(max_x, span.position.x + span.size.x)
				min_z = minf(min_z, span.position.y)
				max_z = maxf(max_z, span.position.y + span.size.y)
		for child in current.get_children():
			stack.append(child)
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


## 收集名字以 prefix 开头的节点（含子树）的 XZ 包络。
func _collect_prefixed_spans(root: Node, prefix: String, out: Array[Rect2]) -> void:
	if root.name.begins_with(prefix) and root is Node3D:
		out.append(_node_xz(root as Node3D))
		return
	for child in root.get_children():
		_collect_prefixed_spans(child, prefix, out)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
