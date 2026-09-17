extends Node
## 战局区块通用组件库 v004 · 09 地板组件（floor_tile_5m）契约验收（无渲染）。
##
## v003 版盯的是「结构件本身」；v004 把 entry_safe_room v006 的砖面装饰
## （压边 / 拼缝 / 标识 / 检修格栅 / 方形检修盖）并进了组件，所以除了复核
## 原点与碰撞没被带坏，还要额外证明「并美术没有动结构」：
##   结构上板顶面必须仍精确在厚度值上（c01 0.056 / c02 0.081），
##   装饰只能叠在它上面，不能把它顶起来或压下去。
##
## 四件事任意一条不成立即退出码非 0：
##   1. 原点契约：底面中心（Godot 底面 Y=0、XZ 居中）—— 替换资产时的唯一定位基准。
##   2. 几何口径：footprint 4.94m × 4.94m；可视顶面 = visual_bounds_size_m.y；
##      结构顶面 = thickness（= 碰撞盒厚）。
##   3. 内嵌碰撞按结构不按美术（collision_owner = self）。
##   4. 场景自报的 visual_bounds_size_m 与实测包围盒一致。
##
## 运行时接入口径（供 TowerFloorStage3D 替换时对本断言负责）：
##   实例落位 y = snap_to_walk_plane_offset_m = -结构厚度，使地砖顶面回到步行平面 Y=0。

const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const EPS := 0.0015
const VERSION := "v004"
const RUNTIME_DIR := "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m"

const CASES := [
	{
		"slug": "floor_tile_r01_c01",
		"asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
		"footprint": 4.94,
		"thickness": 0.056,
		"visual_thickness": 0.083,
	},
	{
		"slug": "floor_tile_r01_c02",
		"asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
		"footprint": 4.94,
		"thickness": 0.081,
		"visual_thickness": 0.0852,
	},
]

## 本组件沿用 L 型转角 v005 包装的写法，顺带确认该包装仍可解析。
const REFERENCE_L_CORNER := "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d.tscn"

## 运行时塔楼楼板口径（TowerFloorStage3D 常量），用于断言"缝"是刻意值而非误差。
const RUNTIME_GRID_UNIT := 5.0
const RUNTIME_FLOOR_THICKNESS := 0.30
const EXPECTED_TILE_GAP := 0.06


func _ready() -> void:
	var failures: Array[String] = []
	print("=== battle common floor tile component contract (%s) ===" % VERSION)
	if load(REFERENCE_L_CORNER) == null:
		failures.append("L 型转角 v005 包装无法解析，地板组件继承的包装写法已失效")
	if not _near(RUNTIME_GRID_UNIT - 4.94, EXPECTED_TILE_GAP):
		failures.append("地砖留缝口径漂移：期望 %.3fm" % EXPECTED_TILE_GAP)
	for case in CASES:
		await _check_case(case, failures)
	if failures.is_empty():
		print("COMMON_FLOOR_TILE_COMPONENTS_V004_OK: 原点/口径/结构未被带坏/碰撞/自报尺寸契约全部成立")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


func _check_case(case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	print("--- %s ---" % slug)
	var scene_path := "%s/%s_root_top3d.tscn" % [RUNTIME_DIR, slug]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("%s 包装场景加载失败：%s" % [slug, scene_path])
		return
	var inst := packed.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	_check_metadata(inst, case, failures)
	_check_geometry(inst, case, failures)
	_check_structure_untouched(inst, case, failures)
	_check_collision(inst, case, failures)
	inst.queue_free()


func _check_metadata(inst: Node3D, case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	_expect_meta(inst, slug, "asset_id", str(case["asset_id"]), failures)
	_expect_meta(inst, slug, "asset_version", VERSION, failures)
	_expect_meta(inst, slug, "origin_contract", "bottom_center", failures)
	_expect_meta(inst, slug, "forward_axis", "-Z", failures)
	_expect_meta(inst, slug, "collision_owner", "self", failures)
	_expect_meta(inst, slug, "collision_policy", "embedded_box_bottom_center", failures)
	_expect_meta(inst, slug, "supersedes", "v003", failures)
	# 地板把「整层拼装口径」放在 runtime_floor_composition，绝不能占用基线键 runtime_instantiation。
	_expect_meta(inst, slug, "runtime_instantiation", "per_instance_prefab", failures)
	_expect_meta(inst, slug, "runtime_floor_composition", "multi_mesh_ab_chessboard", failures)
	if not inst.has_meta("carries_room_art_from"):
		failures.append("%s 缺少 metadata/carries_room_art_from" % slug)
	elif not str(inst.get_meta("carries_room_art_from")).contains("entry_safe_room/v006"):
		failures.append("%s carries_room_art_from = %s，期望指向 entry_safe_room/v006" % [
			slug, inst.get_meta("carries_room_art_from")
		])
	if not inst.has_meta("snap_to_walk_plane_offset_m"):
		failures.append("%s 缺少 metadata/snap_to_walk_plane_offset_m，接入方无从得知落位偏移" % slug)
	elif not _near(
		float(inst.get_meta("snap_to_walk_plane_offset_m")),
		-float(case["thickness"])
	):
		failures.append("%s 落位偏移 %.4f 与结构厚度不一致" % [slug, float(inst.get_meta("snap_to_walk_plane_offset_m"))])


func _check_geometry(inst: Node3D, case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	var bounds := _local_bounds(inst)
	if bounds.size == Vector3.ZERO:
		failures.append("%s 没有可用的可视网格" % slug)
		return
	var size := bounds.size
	var footprint := float(case["footprint"])
	if not _near(size.x, footprint) or not _near(size.z, footprint):
		failures.append("%s XZ = %.4f x %.4f，期望 %.2f" % [slug, size.x, size.z, footprint])
	# 可视顶面 = 结构厚度 + 装饰层，必须等于实测值（并美术后这一项比 v003 更高）。
	if not _near(size.y, float(case["visual_thickness"])):
		failures.append("%s 可视厚度 = %.4f，期望 %.4f（结构 %.3f + 装饰）" % [
			slug, size.y, float(case["visual_thickness"]), float(case["thickness"])
		])
	if absf(bounds.position.y) > EPS:
		failures.append("%s 底面 Y = %.4f，期望 0.0（底面中心原点）" % [slug, bounds.position.y])
	if absf(bounds.position.x + bounds.end.x) > EPS or absf(bounds.position.z + bounds.end.z) > EPS:
		failures.append("%s XZ 未相对原点居中：x[%.4f,%.4f] z[%.4f,%.4f]" % [
			slug, bounds.position.x, bounds.end.x, bounds.position.z, bounds.end.z
		])
	# 场景自报尺寸必须与实测一致。
	if not inst.has_meta("visual_bounds_size_m"):
		failures.append("%s 缺少 metadata/visual_bounds_size_m" % slug)
	else:
		var declared: Vector3 = inst.get_meta("visual_bounds_size_m")
		if not _near(declared.x, size.x) or not _near(declared.y, size.y) or not _near(declared.z, size.z):
			failures.append("%s 自报 visual_bounds_size_m = %v，实测 %v，二者不符" % [slug, declared, size])


## v004 的关键回归点：并入装饰后，结构上板顶面必须仍在厚度值上。
## 只要还有一块子网格的顶面精确停在 thickness，就证明结构没被装饰顶起或压扁。
func _check_structure_untouched(inst: Node3D, case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	var structural_top := float(case["thickness"])
	var found := false
	for mesh_value in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var top := _mesh_top_y(mesh_instance, inst)
		if _near(top, structural_top):
			found = true
			break
	if not found:
		failures.append("%s 找不到顶面停在结构厚度 %.3f 的网格：并美术时把结构板动了" % [slug, structural_top])


func _mesh_top_y(mesh_instance: MeshInstance3D, root: Node3D) -> float:
	var local := _relative_transform(mesh_instance, root)
	var mesh_aabb := mesh_instance.mesh.get_aabb()
	var top := -INF
	for index in 8:
		var point := local * mesh_aabb.get_endpoint(index)
		top = maxf(top, point.y)
	return top


func _check_collision(inst: Node3D, case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	var shape_node := _first_collision_shape(inst)
	if shape_node == null:
		failures.append("%s 内嵌碰撞缺失（collision_owner=self 要求自带碰撞）" % slug)
		return
	var box := shape_node.shape as BoxShape3D
	if box == null:
		failures.append("%s CollisionShape3D.shape 不是 BoxShape3D" % slug)
		return
	var footprint := float(case["footprint"])
	var thickness := float(case["thickness"])
	if (
		not _near(box.size.x, footprint)
		or not _near(box.size.z, footprint)
		or not _near(box.size.y, thickness)
	):
		failures.append("%s 碰撞盒 = %v，期望 %.2f x %.3f x %.2f（按结构，不随装饰变）" % [
			slug, box.size, footprint, thickness, footprint
		])
	var center := shape_node.transform.origin
	if not _near(center.y, thickness * 0.5):
		failures.append("%s 碰撞盒中心 Y = %.4f，期望 %.4f（与底面中心原点齐平）" % [slug, center.y, thickness * 0.5])


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


func _first_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found := _first_collision_shape(child)
		if found != null:
			return found
	return null
