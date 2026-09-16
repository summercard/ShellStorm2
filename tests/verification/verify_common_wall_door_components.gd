extends Node
## 战局区块通用组件库 v003 · 08 墙壁组件 / 10 门组件 契约验收（无渲染）。
##
## 覆盖三件新资产（与 09 地板组件同一范式 B 口径）：
##   wall_standard_5m  标准实墙 5.0 × 0.3 × 11.9
##   wall_door_5m      门墙，三块（左/右门垛 + 门楣），门洞净空 2.2 × 2.5
##   door_5m           门扇 2.2 × 0.18 × 2.5，底边中心原点，垂直升起
##
## 每条断言都对着项目权威常量，而不是脚本内自洽的估算：
##   TowerGeometry3D.GRID_UNIT_M / WALL_VISUAL_HEIGHT_M / WALL_LOGICAL_HEIGHT_M
##   TowerGeometry3D.DOOR_CLEAR_WIDTH_M / DOOR_CLEAR_HEIGHT_M
##   FloorPlanGenerator.WALL_THICKNESS_M
##   RoomDoor3D.PANEL_THICKNESS_M
##
## 任何一条不成立即退出码非 0，供 scripts/run_verification_suite.sh 的 core 套件使用。

const EPS := 0.0015
const RUNTIME_DIR := "res://assets/art/environments/tower_zones/battle/runtime/common_components"

const CASES := {
	"wall_standard_5m": {
		"asset_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
		"collision_policy": "embedded_box_bottom_center",
		"shape_count": 1,
	},
	"wall_door_5m": {
		"asset_id": "ENV-BATTLE-COMMON-WALL-DOOR-5M",
		"collision_policy": "embedded_three_box_bottom_center",
		"shape_count": 3,
	},
	"door_5m": {
		"asset_id": "ENV-BATTLE-COMMON-DOOR-5M",
		"collision_policy": "embedded_box_bottom_center",
		"shape_count": 1,
	},
}


func _ready() -> void:
	var failures: Array[String] = []
	print("=== battle common wall/door component contract ===")
	_check_authority_constants(failures)
	for slug in CASES.keys():
		await _check_case(str(slug), CASES[slug], failures)
	# 门墙与门扇必须严格配对：门楣底 = 门扇顶 = DOOR_CLEAR_HEIGHT_M
	await _check_door_pairing(failures)
	if failures.is_empty():
		print("COMMON_WALL_DOOR_COMPONENTS_OK: 原点/口径/碰撞/门洞净空契约全部成立")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


## 项目权威常量本身必须还在预期的值上——否则断言基准就漂了。
func _check_authority_constants(failures: Array[String]) -> void:
	if not _near(TowerGeometry3D.GRID_UNIT_M, 5.0):
		failures.append("TowerGeometry3D.GRID_UNIT_M 漂移：%s" % TowerGeometry3D.GRID_UNIT_M)
	if not _near(TowerGeometry3D.WALL_VISUAL_HEIGHT_M, 11.9):
		failures.append("TowerGeometry3D.WALL_VISUAL_HEIGHT_M 漂移：%s" % TowerGeometry3D.WALL_VISUAL_HEIGHT_M)
	if not _near(TowerGeometry3D.WALL_LOGICAL_HEIGHT_M, 12.0):
		failures.append("TowerGeometry3D.WALL_LOGICAL_HEIGHT_M 漂移：%s" % TowerGeometry3D.WALL_LOGICAL_HEIGHT_M)
	if not _near(TowerGeometry3D.DOOR_CLEAR_WIDTH_M, 2.2):
		failures.append("TowerGeometry3D.DOOR_CLEAR_WIDTH_M 漂移：%s" % TowerGeometry3D.DOOR_CLEAR_WIDTH_M)
	if not _near(TowerGeometry3D.DOOR_CLEAR_HEIGHT_M, 2.5):
		failures.append("TowerGeometry3D.DOOR_CLEAR_HEIGHT_M 漂移：%s" % TowerGeometry3D.DOOR_CLEAR_HEIGHT_M)
	if not _near(FloorPlanGenerator.WALL_THICKNESS_M, 0.3):
		failures.append("FloorPlanGenerator.WALL_THICKNESS_M 漂移：%s" % FloorPlanGenerator.WALL_THICKNESS_M)
	if not _near(RoomDoor3D.PANEL_THICKNESS_M, 0.18):
		failures.append("RoomDoor3D.PANEL_THICKNESS_M 漂移：%s" % RoomDoor3D.PANEL_THICKNESS_M)
	# 视觉墙顶与逻辑层高之间必须留有 0.1m 净空，作为楼板/天花挂点
	if not _near(TowerGeometry3D.WALL_LOGICAL_HEIGHT_M - TowerGeometry3D.WALL_VISUAL_HEIGHT_M, 0.1):
		failures.append("墙顶净空不再是 0.1m，视觉墙高与逻辑层高口径已分叉")


func _check_case(slug: String, case: Dictionary, failures: Array[String]) -> void:
	print("--- %s ---" % slug)
	var scene_path := "%s/%s/%s_root_top3d_v003.tscn" % [RUNTIME_DIR, slug, slug]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("%s 包装场景加载失败：%s" % [slug, scene_path])
		return
	var inst := packed.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	_check_metadata(inst, slug, case, failures)
	_check_geometry(inst, slug, failures)
	_check_collision(inst, slug, case, failures)
	if slug == "wall_door_5m":
		_check_door_aperture(inst, slug, failures)
	inst.queue_free()


func _check_metadata(inst: Node3D, slug: String, case: Dictionary, failures: Array[String]) -> void:
	_expect_meta(inst, slug, "asset_id", str(case["asset_id"]), failures)
	_expect_meta(inst, slug, "origin_contract", "bottom_center", failures)
	_expect_meta(inst, slug, "forward_axis", "-Z", failures)
	_expect_meta(inst, slug, "up_axis", "+Y", failures)
	_expect_meta(inst, slug, "collision_owner", "self", failures)
	_expect_meta(inst, slug, "collision_policy", str(case["collision_policy"]), failures)
	_expect_meta(inst, slug, "runtime_instantiation", "per_instance_prefab", failures)
	if not inst.has_meta("collision_shape_count"):
		failures.append("%s 缺少 metadata/collision_shape_count" % slug)
	elif int(inst.get_meta("collision_shape_count")) != int(case["shape_count"]):
		failures.append("%s collision_shape_count = %s，期望 %s" % [
			slug, inst.get_meta("collision_shape_count"), case["shape_count"]
		])
	if not inst.has_meta("snap_to_ground_offset_m"):
		failures.append("%s 缺少 metadata/snap_to_ground_offset_m" % slug)
	elif not _near(float(inst.get_meta("snap_to_ground_offset_m")), 0.0):
		failures.append("%s snap_to_ground_offset_m 非 0，底面中心原点不应需要额外落位偏移" % slug)


func _check_geometry(inst: Node3D, slug: String, failures: Array[String]) -> void:
	var bounds := _local_bounds(inst)
	if bounds.size == Vector3.ZERO:
		failures.append("%s 没有可用的可视网格" % slug)
		return
	var size := bounds.size
	var expected := _expected_visual_size(slug)
	if not _near(size.x, expected.x) or not _near(size.y, expected.y) or not _near(size.z, expected.z):
		failures.append("%s 可视包围盒 = %v，期望 %v（项目权威常量推导）" % [slug, size, expected])
	if absf(bounds.position.y) > EPS:
		failures.append("%s 底面 Y = %.4f，期望 0.0（底面中心原点）" % [slug, bounds.position.y])
	if absf(bounds.position.x + bounds.end.x) > EPS or absf(bounds.position.z + bounds.end.z) > EPS:
		failures.append("%s XZ 未相对原点居中：x[%.4f,%.4f] z[%.4f,%.4f]" % [
			slug, bounds.position.x, bounds.end.x, bounds.position.z, bounds.end.z
		])


func _expected_visual_size(slug: String) -> Vector3:
	var width := TowerGeometry3D.GRID_UNIT_M
	var thickness := FloorPlanGenerator.WALL_THICKNESS_M
	var wall_height := TowerGeometry3D.WALL_VISUAL_HEIGHT_M
	match slug:
		"door_5m":
			return Vector3(
				TowerGeometry3D.DOOR_CLEAR_WIDTH_M,
				TowerGeometry3D.DOOR_CLEAR_HEIGHT_M,
				RoomDoor3D.PANEL_THICKNESS_M
			)
		_:
			return Vector3(width, wall_height, thickness)


func _check_collision(inst: Node3D, slug: String, case: Dictionary, failures: Array[String]) -> void:
	var shapes := _collision_shapes(inst)
	if shapes.size() != int(case["shape_count"]):
		failures.append("%s 内嵌碰撞 shape 数 = %d，期望 %d" % [slug, shapes.size(), case["shape_count"]])
		return
	for shape_node in shapes:
		var box := shape_node.shape as BoxShape3D
		if box == null:
			failures.append("%s CollisionShape3D.shape 不是 BoxShape3D" % slug)
			return
	match slug:
		"wall_standard_5m":
			_check_solid_wall_shape(shapes[0], slug, failures)
		"wall_door_5m":
			_check_door_wall_shapes(shapes, slug, failures)
		"door_5m":
			_check_door_shape(shapes[0], slug, failures)
		_:
			pass


func _check_solid_wall_shape(shape_node: CollisionShape3D, slug: String, failures: Array[String]) -> void:
	var size := (shape_node.shape as BoxShape3D).size
	var height := TowerGeometry3D.WALL_VISUAL_HEIGHT_M
	var expected := Vector3(TowerGeometry3D.GRID_UNIT_M, height, FloorPlanGenerator.WALL_THICKNESS_M)
	if not _near(size.x, expected.x) or not _near(size.y, expected.y) or not _near(size.z, expected.z):
		failures.append("%s 碰撞盒 = %v，期望 %v" % [slug, size, expected])
	var center := shape_node.transform.origin
	if not _near(center.y, height * 0.5) or not _near(center.x, 0.0) or not _near(center.z, 0.0):
		failures.append("%s 碰撞盒中心 = %v，期望 (0, %.4f, 0)" % [slug, center, height * 0.5])


## 门墙：左/右门垛各 1.4 宽在 x=±1.8，门楣 2.2 宽 9.4 高在 y=7.2，中间让出 2.2 × 2.5。
func _check_door_wall_shapes(shapes: Array, slug: String, failures: Array[String]) -> void:
	var wall_height := TowerGeometry3D.WALL_VISUAL_HEIGHT_M
	var thickness := FloorPlanGenerator.WALL_THICKNESS_M
	var clear_width := TowerGeometry3D.DOOR_CLEAR_WIDTH_M
	var clear_height := TowerGeometry3D.DOOR_CLEAR_HEIGHT_M
	var pier_width := (TowerGeometry3D.GRID_UNIT_M - clear_width) * 0.5
	var lintel_height := wall_height - clear_height

	var found_pier_l := false
	var found_pier_r := false
	var found_lintel := false
	for shape_node in shapes:
		var box := shape_node.shape as BoxShape3D
		var center: Vector3 = shape_node.transform.origin
		var size: Vector3 = box.size
		if _near(center.y, wall_height * 0.5) and _near(size.y, wall_height):
			if _near(center.x, -(clear_width * 0.5 + pier_width * 0.5)):
				found_pier_l = _pier_ok(size, pier_width, wall_height, thickness, slug, "左门垛", failures)
			elif _near(center.x, clear_width * 0.5 + pier_width * 0.5):
				found_pier_r = _pier_ok(size, pier_width, wall_height, thickness, slug, "右门垛", failures)
		elif _near(center.x, 0.0) and _near(size.x, clear_width):
			found_lintel = true
			if not _near(size.y, lintel_height) or not _near(size.z, thickness):
				failures.append("%s 门楣碰撞盒 = %v，期望 (%.2f, %.2f, %.3f)" % [
					slug, size, clear_width, lintel_height, thickness
				])
			if not _near(center.y, clear_height + lintel_height * 0.5):
				failures.append("%s 门楣碰撞盒中心 Y = %.4f，期望 %.4f（底部正好压在门洞顶）" % [
					slug, center.y, clear_height + lintel_height * 0.5
				])
	if not found_pier_l:
		failures.append("%s 缺少左门垛碰撞（x = %.4f）" % [slug, -(clear_width * 0.5 + pier_width * 0.5)])
	if not found_pier_r:
		failures.append("%s 缺少右门垛碰撞（x = %.4f）" % [slug, clear_width * 0.5 + pier_width * 0.5])
	if not found_lintel:
		failures.append("%s 缺少门楣碰撞（x = 0, 宽 = %.2f）" % [slug, clear_width])


func _pier_ok(
	size: Vector3,
	pier_width: float,
	wall_height: float,
	thickness: float,
	slug: String,
	label: String,
	failures: Array[String]
) -> bool:
	if (
		not _near(size.x, pier_width)
		or not _near(size.y, wall_height)
		or not _near(size.z, thickness)
	):
		failures.append("%s %s碰撞盒 = %v，期望 (%.2f, %.2f, %.3f)" % [
			slug, label, size, pier_width, wall_height, thickness
		])
		return false
	return true


func _check_door_shape(shape_node: CollisionShape3D, slug: String, failures: Array[String]) -> void:
	var size := (shape_node.shape as BoxShape3D).size
	var expected := Vector3(
		TowerGeometry3D.DOOR_CLEAR_WIDTH_M,
		TowerGeometry3D.DOOR_CLEAR_HEIGHT_M,
		RoomDoor3D.PANEL_THICKNESS_M
	)
	if not _near(size.x, expected.x) or not _near(size.y, expected.y) or not _near(size.z, expected.z):
		failures.append("%s 门扇碰撞盒 = %v，期望 %v（与 RoomDoor3D 面板口径一致）" % [slug, size, expected])
	var center := shape_node.transform.origin
	if not _near(center.y, TowerGeometry3D.DOOR_CLEAR_HEIGHT_M * 0.5):
		failures.append("%s 门扇碰撞盒中心 Y = %.4f，期望 %.4f" % [
			slug, center.y, TowerGeometry3D.DOOR_CLEAR_HEIGHT_M * 0.5
		])
	if absf(center.x) > EPS or absf(center.z) > EPS:
		failures.append("%s 门扇碰撞盒未在 XZ 居中：%v" % [slug, center])


## 门洞净空：x ∈ (-1.1, 1.1) 且 y ∈ (0, 2.5) 处不得有任何碰撞体。
func _check_door_aperture(inst: Node3D, slug: String, failures: Array[String]) -> void:
	var half := TowerGeometry3D.DOOR_CLEAR_WIDTH_M * 0.5
	var top := TowerGeometry3D.DOOR_CLEAR_HEIGHT_M
	for shape_node in _collision_shapes(inst):
		var box := shape_node.shape as BoxShape3D
		var center: Vector3 = shape_node.transform.origin
		var overlap_x := (
			minf(center.x + box.size.x * 0.5, half)
			- maxf(center.x - box.size.x * 0.5, -half)
		)
		var overlap_y := (
			minf(center.y + box.size.y * 0.5, top)
			- maxf(center.y - box.size.y * 0.5, 0.0)
		)
		if overlap_x > EPS and overlap_y > EPS:
			failures.append("%s 碰撞体侵入 2.2 × 2.5 门洞：中心 %v 尺寸 %v" % [slug, center, box.size])


## 门墙门楣底（2.5）必须与门扇顶（2.5）等高；门扇宽（2.2）必须等于门洞宽。
func _check_door_pairing(failures: Array[String]) -> void:
	var wall := load("%s/wall_door_5m/wall_door_5m_root_top3d_v003.tscn" % RUNTIME_DIR) as PackedScene
	var door := load("%s/door_5m/door_5m_root_top3d_v003.tscn" % RUNTIME_DIR) as PackedScene
	if wall == null or door == null:
		failures.append("门墙/门扇包装缺失，无法验证门洞配对")
		return
	var wall_inst := wall.instantiate() as Node3D
	var door_inst := door.instantiate() as Node3D
	add_child(wall_inst)
	add_child(door_inst)
	await get_tree().process_frame
	var lintel_bottom := INF
	for shape_node in _collision_shapes(wall_inst):
		var box := shape_node.shape as BoxShape3D
		if not _near(box.size.x, TowerGeometry3D.DOOR_CLEAR_WIDTH_M):
			continue
		lintel_bottom = shape_node.transform.origin.y - box.size.y * 0.5
	var door_top := _local_bounds(door_inst).end.y
	if is_inf(lintel_bottom):
		failures.append("门墙找不到门楣，无法验证门洞顶高")
	elif not _near(lintel_bottom, door_top):
		failures.append("门楣底 %.4f 与门扇顶 %.4f 不等高，门扇关不上口" % [lintel_bottom, door_top])
	wall_inst.queue_free()
	door_inst.queue_free()


func _expect_meta(
	inst: Node3D,
	slug: String,
	key: String,
	expected: String,
	failures: Array[String]
) -> void:
	if not inst.has_meta(key):
		failures.append("%s 缺少 metadata/%s" % [slug, key])
	elif String(inst.get_meta(key)) != expected:
		failures.append("%s metadata/%s = %s，期望 %s" % [slug, key, inst.get_meta(key), expected])


func _collision_shapes(node: Node) -> Array:
	var result: Array = []
	_collect_collision_shapes(node, result)
	return result


func _collect_collision_shapes(node: Node, result: Array) -> void:
	if node is CollisionShape3D:
		result.append(node)
	for child in node.get_children():
		_collect_collision_shapes(child, result)


func _local_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh_value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local := _relative_transform(mesh_instance, root)
		var mesh_aabb := mesh_instance.mesh.get_aabb()
		var corners := PackedVector3Array()
		for index in 8:
			corners.append(local * mesh_aabb.get_endpoint(index))
		var box := AABB(corners[0], Vector3.ZERO)
		for point in corners:
			box = box.expand(point)
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D()
	var current: Node3D = node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result
