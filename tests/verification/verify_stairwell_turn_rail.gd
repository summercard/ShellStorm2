extends Node3D
## 楼梯间折返平台护栏验收（ENV-TOWER-STAIRWELL-TURN-RAIL）
##
## 业主反馈（2026-10-19）：「99-100 / 99-98 的楼梯间，这两边都没有栏杆，角色会走过去。」
## 本用例只回答一个问题：**折返平台那两条敞口边，现在是不是真的挡住了角色**，
## 同时确认**两跑口没有被护栏封死**（封死 = 楼梯不可通行，比漏护栏更严重）。
##
## 判据不查表、不读坐标常量，全部从节点自身变换推：
##   1. 两座楼梯间各挂 1 个护栏实例，各含 4 段 StaticBody3D 碰撞（外沿 / 两个窄槽 / 中间井口）；
##   2. 每段碰撞体沿自身局部 Z 轴穿过时的射线必须命中**它自己**（层 1 = 角色可撞）；
##   3. 视觉网格真实存在，且包络尺寸 = 资产清单声明（14.38 × 1.175 × 5.99m，容差 0.02）；
##   4. 两跑口（下跑 / 上跑踏步入口）在腰部高度射线上**不得**命中护栏碰撞 —— 楼梯必须还能走；
##   5. 护栏碰撞顶面必须高于折返平台楼面 ≥ 1.05m（低于这个数就不是能挡人的栏杆）。
##
## 跑法：
##   godot --headless --path <project> res://tests/verification/verify_stairwell_turn_rail.tscn

const EXPECTED_RAIL_INSTANCES := 2
const EXPECTED_SEGMENTS_PER_RAIL := 4
const EXPECTED_BBOX_SIZE := Vector3(14.38, 1.175, 5.99)
const BBOX_TOLERANCE := 0.02
const MIN_RAIL_HEIGHT_M := 1.05
const FLOOR_BELOW_MIDDLE_LANDING := -6.0

var failures: Array[String] = []
var samples := 0


func _ready() -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	await _settle()

	var rail_instances := 0
	for connector_name in ["Stair_A", "Stair_B"]:
		var connector := tower.find_child(connector_name, true, false) as Node3D
		if connector == null:
			failures.append("%s：找不到楼梯连接器" % connector_name)
			continue
		var rails := connector.find_children("StairwellTurnRail", "", true, false)
		if rails.size() != 1:
			failures.append(
				"%s：折返平台护栏实例数 %d，应为 1（未装配即无护栏）"
				% [connector_name, rails.size()]
			)
			continue
		rail_instances += 1
		var rail := rails[0] as Node3D
		_check_rail(connector_name, connector, rail)

	if rail_instances != EXPECTED_RAIL_INSTANCES:
		failures.append(
			"护栏实例总数 %d，应为 %d（两座楼梯间都要有）"
			% [rail_instances, EXPECTED_RAIL_INSTANCES]
		)

	tower.free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print(
		"STAIRWELL_TURN_RAIL samples=%d failures=%d rails=%d"
		% [samples, failures.size(), rail_instances]
	)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_rail(connector_name: String, connector: Node3D, rail: Node3D) -> void:
	var label := "%s/护栏" % connector_name
	var segments: Array[StaticBody3D] = []
	for body_value in rail.find_children("*", "StaticBody3D", true, false):
		var body := body_value as StaticBody3D
		if body != null and body.get_child_count() > 0:
			segments.append(body)
	if segments.size() != EXPECTED_SEGMENTS_PER_RAIL:
		failures.append("%s：碰撞段 %d，应为 %d" % [label, segments.size(), EXPECTED_SEGMENTS_PER_RAIL])
		return

	# ① 每段：沿自身局部 Z 轴穿过时，必须命中它自己
	for body in segments:
		var shape_node := body.get_child(0) as CollisionShape3D
		var box := shape_node.shape as BoxShape3D if shape_node != null else null
		if box == null:
			failures.append("%s/%s：碰撞不是 BoxShape3D" % [label, body.name])
			continue
		if body.collision_layer & 1 == 0:
			failures.append("%s/%s：碰撞层没有 1（角色撞不到）" % [label, body.name])
		var axis_z := body.global_basis.z.normalized()
		var center := body.global_position
		var query := PhysicsRayQueryParameters3D.create(
			center - axis_z * 0.9, center + axis_z * 0.9, 1
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		samples += 1
		if hit.is_empty():
			failures.append("%s/%s：横穿护栏的射线没命中任何东西" % [label, body.name])
		elif (hit.collider as Node) != body:
			failures.append(
				"%s/%s：横穿射线命中的是 %s，不是该段护栏"
				% [label, body.name, (hit.collider as Node).name]
			)
		# ⑤ 高度：碰撞顶面必须比折返平台楼面高 ≥ 1.05m
		var top_y := center.y + box.size.y * 0.5
		var rail_height := top_y - FLOOR_BELOW_MIDDLE_LANDING
		if rail_height < MIN_RAIL_HEIGHT_M:
			failures.append(
				"%s/%s：护栏高 %.3fm，低于 %.2fm（挡不住人）"
				% [label, body.name, rail_height, MIN_RAIL_HEIGHT_M]
			)

	# ② 视觉网格存在，包络 = 清单声明
	var visual := _first_mesh(rail)
	if visual == null:
		failures.append("%s：没有可见网格（只有碰撞没有美术 = 空气墙）" % label)
	else:
		var bounds := visual.get_aabb()
		var size_error := (bounds.size - EXPECTED_BBOX_SIZE).abs()
		if size_error.x > BBOX_TOLERANCE or size_error.y > BBOX_TOLERANCE or size_error.z > BBOX_TOLERANCE:
			failures.append(
				"%s：护栏包络 %s 与清单声明 %s 不符"
				% [label, bounds.size, EXPECTED_BBOX_SIZE]
			)

	# ④ 两跑口必须仍可通行：取两跑之间的「两段护栏之间的缺口」，
	#    在腰部高度横穿，不得命中护栏碰撞。
	var segment_centers: Array[Vector3] = []
	for body in segments:
		segment_centers.append(body.global_position)
	# 内外两侧各取一次：外沿段单独一组，内侧三段按 x 排序
	var outer_index := -1
	for index in range(segment_centers.size()):
		if str(segments[index].get_meta("rail_segment", "")) == "outer_edge":
			outer_index = index
	if outer_index < 0:
		failures.append("%s：找不到外沿段（rail_segment=outer_edge）" % label)
	var inner: Array[StaticBody3D] = []
	for body in segments:
		if str(body.get_meta("rail_segment", "")).begins_with("inner"):
			inner.append(body)
	if inner.size() != 3:
		failures.append("%s：内侧段 %d，应为 3（两个窄槽 + 井口）" % [label, inner.size()])
		return
	# 内侧三段按世界 X 排序后，第 1、2 段之间与第 2、3 段之间就是两跑口
	var sorted_inner: Array[StaticBody3D] = []
	sorted_inner.append_array(inner)
	sorted_inner.sort_custom(
		func(a: StaticBody3D, b: StaticBody3D) -> bool:
			return a.global_position.x < b.global_position.x
	)
	var axis_across: Vector3 = (
		sorted_inner[1].global_position - sorted_inner[0].global_position
	).normalized()
	for gap_index in range(1, sorted_inner.size()):
		var left: StaticBody3D = sorted_inner[gap_index - 1]
		var right: StaticBody3D = sorted_inner[gap_index]
		var between: Vector3 = (left.global_position + right.global_position) * 0.5
		var half_span: float = (right.global_position - left.global_position).length() * 0.5
		if half_span < 0.4:
			continue
		# 沿护栏法线方向（局部 Z）从平台一侧打到井一侧：应该打不到护栏
		var normal: Vector3 = left.global_basis.z.normalized()
		var probe := PhysicsRayQueryParameters3D.create(
			between - normal * 0.9, between + normal * 0.9, 1
		)
		var gap_hit := get_world_3d().direct_space_state.intersect_ray(probe)
		samples += 1
		if not gap_hit.is_empty():
			var node := gap_hit.collider as Node
			if node != null and bool(node.get_meta("stair_turn_rail_collision", false)):
				failures.append(
					"%s：两跑口 %d 被护栏封死（缺口宽 %.2fm）"
					% [label, gap_index, half_span * 2.0]
				)
	# 沿两跑口方向（横穿）也要能过
	for gap_index in range(1, sorted_inner.size()):
		var left: StaticBody3D = sorted_inner[gap_index - 1]
		var right: StaticBody3D = sorted_inner[gap_index]
		var between: Vector3 = (left.global_position + right.global_position) * 0.5
		var probe := PhysicsRayQueryParameters3D.create(
			between - axis_across * 0.45, between + axis_across * 0.45, 1
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(probe)
		samples += 1
		if not hit.is_empty():
			var node := hit.collider as Node
			if node != null and bool(node.get_meta("stair_turn_rail_collision", false)):
				failures.append("%s：两跑口 %d 横向被护栏挡住" % [label, gap_index])
	# 连接器元数据一致性
	if int(connector.get_meta("stair_turn_rail_segment_count", 0)) != EXPECTED_SEGMENTS_PER_RAIL:
		failures.append(
			"%s：连接器记录的护栏段数 %s 与实际不符"
			% [label, connector.get_meta("stair_turn_rail_segment_count", "缺失")]
		)


func _first_mesh(root: Node) -> MeshInstance3D:
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := value as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			return mesh_node
	return null


func _settle() -> void:
	for i in 14:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.4).timeout
