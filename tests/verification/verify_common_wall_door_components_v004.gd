extends Node
## 战局区块通用组件库 v004 · 08 墙壁组件 / 10 门组件 契约验收（无渲染）。
##
## v003 版只验「结构件本身」；v004 把 entry_safe_room v006 的房内美术（装甲壁板 /
## 装甲门禁）并进了组件，所以这一版除了复核结构契约没被带坏，还要盯住三件新事：
##   1. 并进来的美术不得把「可替换性」弄丢：
##        背面结构面必须仍精确落在 +壁厚/2（贴网格中线的那个面），
##        正面允许朝房内凸出，但必须有明确上限，不能无限长。
##      这两条合起来就是「任意 5m 槽位、任意朝向都能自动对上」的几何保证。
##   2. 碰撞仍按结构、不按美术：碰撞盒与 v003 逐值相同，装饰件不改变体积。
##   3. 场景里自报的 visual_bounds_size_m 必须与运行时实测包围盒一致，
##      否则等于对外承诺了一个假尺寸。
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
const VERSION := "v004"

## 房内装饰件允许朝「前」(-Z，即 forward_axis) 凸出的最大量。
## 壁板压条约 3mm、装甲门禁约 65mm，取 0.12m 留足余量；超过即说明并错了东西。
const MAX_FORWARD_PROTRUSION_M := 0.12

const CASES := {
	"wall_standard_5m": {
		"asset_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M",
		"collision_policy": "embedded_box_bottom_center",
		"shape_count": 1,
		"visual_height_m": 11.9,
		"visual_thickness_m": 0.303,
	},
	"wall_door_5m": {
		"asset_id": "ENV-BATTLE-COMMON-WALL-DOOR-5M",
		"collision_policy": "embedded_three_box_bottom_center",
		"shape_count": 3,
		"visual_height_m": 11.9,
		"visual_thickness_m": 0.365,
	},
	"door_5m": {
		"asset_id": "ENV-BATTLE-COMMON-DOOR-5M",
		"collision_policy": "embedded_box_bottom_center",
		"shape_count": 1,
		"visual_height_m": 2.5,
		"visual_thickness_m": 0.18,
	},
}


func _ready() -> void:
	var failures: Array[String] = []
	print("=== battle common wall/door component contract (%s) ===" % VERSION)
	_check_authority_constants(failures)
	for slug in CASES.keys():
		await _check_case(str(slug), CASES[slug], failures)
	# 门墙与门扇必须严格配对：门楣底 = 门扇顶 = DOOR_CLEAR_HEIGHT_M
	await _check_door_pairing(failures)
	if failures.is_empty():
		print("COMMON_WALL_DOOR_COMPONENTS_V004_OK: 原点/可替换性/碰撞/门洞净空/自报尺寸契约全部成立")
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
	var scene_path := "%s/%s/%s_root_top3d.tscn" % [RUNTIME_DIR, _subdir(slug), slug]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("%s 包装场景加载失败：%s" % [slug, scene_path])
		return
	var inst := packed.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	_check_metadata(inst, slug, case, failures)
	_check_geometry(inst, slug, case, failures)
	_check_collision(inst, slug, case, failures)
	if slug == "wall_door_5m":
		_check_door_aperture(inst, slug, failures)
	inst.queue_free()


func _subdir(slug: String) -> String:
	return "floor_tile_5m" if slug.begins_with("floor_tile") else slug


func _check_metadata(inst: Node3D, slug: String, case: Dictionary, failures: Array[String]) -> void:
	_expect_meta(inst, slug, "asset_id", str(case["asset_id"]), failures)
	_expect_meta(inst, slug, "asset_version", VERSION, failures)
	_expect_meta(inst, slug, "origin_contract", "bottom_center", failures)
	_expect_meta(inst, slug, "forward_axis", "-Z", failures)
	_expect_meta(inst, slug, "up_axis", "+Y", failures)
	_expect_meta(inst, slug, "collision_owner", "self", failures)
	_expect_meta(inst, slug, "collision_policy", str(case["collision_policy"]), failures)
	_expect_meta(inst, slug, "runtime_instantiation", "per_instance_prefab", failures)
	# v004 的来源可追溯：必须声明自己取代 v003，且注明房内美术的出处。
	_expect_meta(inst, slug, "supersedes", "v003", failures)
	if not inst.has_meta("carries_room_art_from"):
		failures.append("%s 缺少 metadata/carries_room_art_from，无法追溯并入美术的房间版本" % slug)
	elif not str(inst.get_meta("carries_room_art_from")).contains("entry_safe_room/v006"):
		failures.append("%s carries_room_art_from = %s，期望指向 entry_safe_room/v006" % [
			slug, inst.get_meta("carries_room_art_from")
		])
	if not inst.has_meta("collision_structure_note"):
		failures.append("%s 缺少 metadata/collision_structure_note" % slug)
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


## 可替换性的核心几何：
##   墙类：宽度必须正好是网格单元、底面落在 0、背面结构面精确压在 +壁厚/2、
##         正面凸出在上限内 —— 四条合起来即「任意槽位任意朝向自动对上」。
##   门扇：不是 5m 墙，而是嵌在门洞里的板件，改为对齐门洞口径且以原点居中。
func _check_geometry(inst: Node3D, slug: String, case: Dictionary, failures: Array[String]) -> void:
	var bounds := _local_bounds(inst)
	if bounds.size == Vector3.ZERO:
		failures.append("%s 没有可用的可视网格" % slug)
		return
	var size := bounds.size
	var thickness := FloorPlanGenerator.WALL_THICKNESS_M

	# 高度与底面：两类组件都成立，先统一查。
	var expected_height := float(case["visual_height_m"])
	if not _near(size.y, expected_height):
		failures.append("%s 可视高度 = %.4f，期望 %.2f" % [slug, size.y, expected_height])
	if absf(bounds.position.y) > EPS:
		failures.append("%s 底面 Y = %.4f，期望 0.0（底面中心原点）" % [slug, bounds.position.y])

	if slug == "door_5m":
		# 门扇：宽度 = 门洞净宽，厚度以原点为中心对称，XZ 皆居中。
		if not _near(size.x, TowerGeometry3D.DOOR_CLEAR_WIDTH_M):
			failures.append("%s X 向跨度 = %.4f，期望门洞净宽 %.2f" % [
				slug, size.x, TowerGeometry3D.DOOR_CLEAR_WIDTH_M
			])
		if not _near(size.z, RoomDoor3D.PANEL_THICKNESS_M):
			failures.append("%s Z 向厚度 = %.4f，期望面板厚 %.3f" % [
				slug, size.z, RoomDoor3D.PANEL_THICKNESS_M
			])
		if absf(bounds.position.x + bounds.end.x) > EPS or absf(bounds.position.z + bounds.end.z) > EPS:
			failures.append("%s 门扇 XZ 未相对原点居中：x[%.4f,%.4f] z[%.4f,%.4f]" % [
				slug, bounds.position.x, bounds.end.x, bounds.position.z, bounds.end.z
			])
	else:
		# 墙体：X 向（沿墙铺开那一轴）必须严丝合缝等于网格单元，且相对原点居中。
		if not _near(size.x, TowerGeometry3D.GRID_UNIT_M):
			failures.append("%s X 向跨度 = %.4f，期望网格单元 %.2f（否则无法沿网格无缝平铺）" % [
				slug, size.x, TowerGeometry3D.GRID_UNIT_M
			])
		if absf(bounds.position.x + bounds.end.x) > EPS:
			failures.append("%s X 未相对原点居中：x[%.4f,%.4f]" % [slug, bounds.position.x, bounds.end.x])
		# 背面结构面 = max Z 必须精确压在 +壁厚/2（贴网格中线的那个面）。
		# 贴中线的面动一毫米，整面墙就整体偏移。
		if not _near(bounds.end.z, thickness * 0.5):
			failures.append("%s 背面结构面 Z = %.4f，期望 +%.3f（必须与网格中线齐平）" % [
				slug, bounds.end.z, thickness * 0.5
			])
		var protrusion := -bounds.position.z - thickness * 0.5
		if protrusion < -EPS:
			failures.append("%s 可视范围没盖住结构厚度：Z = [%.4f,%.4f]，结构应为 ±%.3f" % [
				slug, bounds.position.z, bounds.end.z, thickness * 0.5
			])
		elif protrusion > MAX_FORWARD_PROTRUSION_M + EPS:
			failures.append("%s 朝房内凸出 %.4f，超过上限 %.3f，疑似并进了不该并的东西" % [
				slug, protrusion, MAX_FORWARD_PROTRUSION_M
			])

	# 场景自报的 visual_bounds_size_m 必须与实测一致（不能承诺假尺寸）。
	if not inst.has_meta("visual_bounds_size_m"):
		failures.append("%s 缺少 metadata/visual_bounds_size_m" % slug)
	else:
		var declared: Vector3 = inst.get_meta("visual_bounds_size_m")
		if not _near(declared.x, size.x) or not _near(declared.y, size.y) or not _near(declared.z, size.z):
			failures.append("%s 自报 visual_bounds_size_m = %v，实测 %v，二者不符" % [slug, declared, size])


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
		failures.append("%s 碰撞盒 = %v，期望 %v（与 v003 一致，不随美术变）" % [slug, size, expected])
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
## v004 并进了门禁美术，但美术不参与碰撞——这条正是用来证明「装饰没有堵门」。
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
	var wall := load("%s/wall_door_5m/wall_door_5m_root_top3d.tscn" % RUNTIME_DIR) as PackedScene
	var door := load("%s/door_5m/door_5m_root_top3d.tscn" % RUNTIME_DIR) as PackedScene
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
