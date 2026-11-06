extends Node3D
## 楼梯间折返平台护栏验收（ENV-TOWER-STAIRWELL-TURN-RAIL）
##
## 业主反馈（2026-10-19）：「99-100 / 99-98 的楼梯间，这两边都没有栏杆，角色会走过去。」
## 本用例只回答一个问题：**折返平台那两条敞口边，现在是不是真的挡住了角色**，
## 同时确认**两跑口没有被护栏封死**（封死 = 楼梯不可通行，比漏护栏更严重）。
##
## 判据不查表、不读坐标常量，全部从节点自身变换推：
##   0. 护栏碰撞必须跟着楼梯间一起开关：楼梯间不可见时不得留下挡人的空气墙，
##      可见时必须真的能撞（2026-11 起连接器碰撞由 `_set_connector_collision_enabled` 统一卸载）；
##   1. 两座楼梯间各挂 1 个护栏实例，各含 4 段 StaticBody3D 碰撞（外沿 / 两个窄槽 / 中间井口）；
##   2. 每段碰撞体沿自身局部 Z 轴穿过时的射线必须命中**它自己**（层 1 = 角色可撞）；
##   3. 视觉网格真实存在，且包络尺寸 = 资产清单声明（14.38 × 1.175 × 5.99m，容差 0.02）；
##   4. 两跑口（下跑 / 上跑踏步入口）在腰部高度射线上**不得**命中护栏碰撞 —— 楼梯必须还能走；
##   5. 护栏碰撞顶面必须高于折返平台楼面 ≥ 1.05m（低于这个数就不是能挡人的栏杆）。
##
## 高度口径（2026-11-06 修正）：原来拿世界常量 `-6.0` 当楼面，层高改成 12m 之后
## 98–99 那座楼梯间的可视根在世界 `-12`，于是「护栏高」被算成 **-10.845m** —— 假的。
## 现在一律在**楼梯间装配根局部坐标系**里算（资产自己声明 `coordinate_frame =
## stairwell_assembly_root_local`），折返平台平面 = 半层层高；楼板真实存在时
## 再用向下射线复核该平面，两条口径互相咬。
##
## 跑法：
##   godot --headless --path <project> res://tests/verification/verify_stairwell_turn_rail.tscn

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

const EXPECTED_RAIL_INSTANCES := 2
const EXPECTED_SEGMENTS_PER_RAIL := 4
const EXPECTED_BBOX_SIZE := Vector3(14.38, 1.175, 5.99)
const BBOX_TOLERANCE := 0.02
const MIN_RAIL_HEIGHT_M := 1.05
## 上限只用来抓「算错坐标系」：折返平台护栏不可能高过一层楼。
const MAX_RAIL_HEIGHT_M := 6.0
## 折返平台在装配根局部坐标里的平面高度 = 半层层高（12m 层高 ⇒ local -6.0）。
const MID_LANDING_LOCAL_Y := -TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5
## 楼面实测与声明平面的容差（m）。
const FLOOR_PLANE_TOLERANCE_M := 0.06

var failures: Array[String] = []
var samples := 0
var floor_misses := 0


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
		# ① 先按「闸门关闭时不许留空气墙」验一次初始态
		_check_gating(connector_name, connector, rail, false)
		# ② 再把楼梯间打开（玩家走进去时的状态），验几何与可撞性
		if not _open_connector(tower, connector):
			failures.append("%s：找不到该楼梯间对应的边，无法按玩家路径打开" % connector_name)
			continue
		await _settle()
		_check_gating(connector_name, connector, rail, true)
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
		"STAIRWELL_TURN_RAIL samples=%d failures=%d rails=%d floor_misses=%d"
		% [samples, failures.size(), rail_instances, floor_misses]
	)
	get_tree().quit(0 if failures.is_empty() else 1)


## 把楼梯间按玩家的路径打开：边标记 + 连接器碰撞统一启用。
## 直接调用装配器内部的两处开关，是因为本用例**没有玩家**走到楼梯间门口；
## 不断言这两处内部实现，只借用它们进入「楼梯间已打开」这个真实状态。
func _open_connector(tower: TowerDescent3D, connector: Node3D) -> bool:
	var corridors := tower._corridor_by_edge as Dictionary
	for edge_value in corridors.keys():
		if corridors[edge_value] == connector:
			tower._open_edges[str(edge_value)] = true
			# `_refresh_edge_visuals()` 打开连接器时同时恢复这三样：
			# 可见性、处理模式（PROCESS_MODE_DISABLED 的子树连碰撞体都不进物理步进）与碰撞。
			# 少写任何一样，射线都会「一根都打不中」—— 本轮实测就是这么来的。
			connector.visible = true
			connector.process_mode = Node.PROCESS_MODE_INHERIT
			tower._set_connector_collision_enabled(connector, true, false)
			return true
	return false


## 护栏碰撞的开合必须与楼梯间可见性一致：
## 不可见 ⇒ 全部 disabled（否则就是看不见却挡人的空气墙）；
## 可见 ⇒ 全部 enabled（否则栏杆是纯装饰，人照样走过去）。
func _check_gating(
	connector_name: String, connector: Node3D, rail: Node3D, opened: bool
) -> void:
	var segments := _rail_segments(rail)
	if segments.is_empty():
		return
	samples += 1
	var expect_enabled := opened
	if not opened and connector.visible:
		# 楼梯间默认就是开着的（99F↔100F），此时「未打开」只表示本用例没去动它 ——
		# 不把「可见却关着碰撞」判成失败，交给下一轮 opened 分支。
		return
	for body in segments:
		var collision := body.get_child(0) as CollisionShape3D
		if collision == null:
			continue
		var enabled := not collision.disabled
		if enabled != expect_enabled:
			failures.append(
				"%s/%s：楼梯间%s，护栏碰撞却是%s（空气墙 / 纯装饰）"
				% [
					connector_name,
					body.name,
					"已打开" if opened else "不可见",
					"启用" if enabled else "关闭",
				]
			)


func _rail_segments(rail: Node3D) -> Array[StaticBody3D]:
	var segments: Array[StaticBody3D] = []
	for body_value in rail.find_children("*", "StaticBody3D", true, false):
		var body := body_value as StaticBody3D
		if body != null and body.get_child_count() > 0:
			segments.append(body)
	return segments


func _check_rail(connector_name: String, connector: Node3D, rail: Node3D) -> void:
	var label := "%s/护栏" % connector_name
	var segments := _rail_segments(rail)
	if segments.size() != EXPECTED_SEGMENTS_PER_RAIL:
		failures.append("%s：碰撞段 %d，应为 %d" % [label, segments.size(), EXPECTED_SEGMENTS_PER_RAIL])
		return

	# 折返平台平面在**楼梯间装配根局部坐标**里量，不碰世界 Y —— 楼层层高改过
	# 一次（6m → 12m），世界常量口径会让整条判据静默算错 12m。
	var assembly := rail.get_parent() as Node3D
	if assembly == null:
		failures.append("%s：护栏没有挂在楼梯间装配根下（坐标系不可推导）" % label)
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
		var local_top := assembly.to_local(Vector3(center.x, top_y, center.z)).y
		var rail_height := local_top - MID_LANDING_LOCAL_Y
		if rail_height < MIN_RAIL_HEIGHT_M or rail_height > MAX_RAIL_HEIGHT_M:
			failures.append(
				"%s/%s：护栏高 %.3fm（局部口径），应落在 %.2f~%.2fm"
				% [label, body.name, rail_height, MIN_RAIL_HEIGHT_M, MAX_RAIL_HEIGHT_M]
			)
		# ⑤b 楼板真实存在时复核：声明平面必须就是实测楼面。
		# 只对外沿段做 —— 内侧两段一侧是井口、另一侧是梯跑，向下射线的最高点
		# 是**上行踏步**而不是折返平台（实测 -5.508 对 -6.000），拿它当楼面会误判。
		if str(body.get_meta("rail_segment", "")) == "outer_edge":
			var measured := _measure_floor_local_y(body, assembly)
			if is_nan(measured):
				floor_misses += 1
			elif absf(measured - MID_LANDING_LOCAL_Y) > FLOOR_PLANE_TOLERANCE_M:
				failures.append(
					"%s/%s：折返平台实测楼面 local %.3f 与声明 %.3f 不符（护栏高度基准不成立）"
					% [label, body.name, measured, MID_LANDING_LOCAL_Y]
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


## 在护栏两侧各打几条向下射线，取**最高**命中作为折返平台楼面（局部 Y）。
## 取最高而不是最低：井口那一侧会掉到下层梯跑上，最低点不是平台。
## 楼板根本没生成（例：只装配了 99F 区块时 98–99 那座楼梯间）时返回 NAN。
func _measure_floor_local_y(body: StaticBody3D, assembly: Node3D) -> float:
	var normal := body.global_basis.z.normalized()
	var origin_base := body.global_position + Vector3(0.0, 0.8, 0.0)
	var best := -INF
	for offset in [-1.2, -0.75, -0.35, 0.35, 0.75, 1.2]:
		var origin: Vector3 = origin_base + normal * offset
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.0, 1)
		query.exclude = [body.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider := hit.get("collider") as Node
		if collider != null and bool(collider.get_meta("stair_turn_rail_collision", false)):
			continue
		best = maxf(best, (hit.get("position") as Vector3).y)
	if best == -INF:
		return NAN
	return assembly.to_local(Vector3(body.global_position.x, best, body.global_position.z)).y


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
