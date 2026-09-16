extends Node
## 战局区块通用组件库 v003 · 09 地板组件（floor_tile_5m）契约验收（无渲染）。
##
## 盯住三件事，任何一条不成立即退出码非 0：
##   1. 原点契约：底面中心（Godot 底面 Y=0、XZ 居中）—— 替换资产时的唯一定位基准。
##   2. 几何口径：footprint 4.94m × 4.94m、厚度 = manifest 值（c01 0.056 / c02 0.081）。
##   3. 内嵌碰撞与色盘后处理真的生效（collision_owner = self；
##      albedo_texture 必须指向共享色盘，而不是 GLB 自带图）。
##
## 运行时接入口径（供 TowerFloorStage3D 替换时对本断言负责）：
##   实例落位 y = -厚度，使地砖顶面回到步行平面 Y=0。

const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const EPS := 0.0015

const CASES := [
	{
		"slug": "floor_tile_r01_c01",
		"scene": "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d_v003.tscn",
		"footprint": 4.94,
		"thickness": 0.056,
		"asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
	},
	{
		"slug": "floor_tile_r01_c02",
		"scene": "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d_v003.tscn",
		"footprint": 4.94,
		"thickness": 0.081,
		"asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
	},
]

## 本组件沿用 L 型转角 v005 包装的写法，顺带确认该包装仍可解析。
const REFERENCE_L_CORNER := "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v005.tscn"

## 运行时塔楼楼板口径（TowerFloorStage3D 常量），用于断言"缝"是刻意值而非误差。
const RUNTIME_GRID_UNIT := 5.0
const RUNTIME_FLOOR_THICKNESS := 0.30
const EXPECTED_TILE_GAP := 0.06


func _ready() -> void:
	var failures: Array[String] = []
	print("=== battle common floor tile component contract ===")
	if load(REFERENCE_L_CORNER) == null:
		failures.append("L 型转角 v005 包装无法解析，地板组件继承的包装写法已失效")
	if not _near(RUNTIME_GRID_UNIT - 4.94, EXPECTED_TILE_GAP):
		failures.append("地砖留缝口径漂移：期望 %.3fm" % EXPECTED_TILE_GAP)
	for case in CASES:
		await _check_case(case, failures)
	if failures.is_empty():
		print("COMMON_FLOOR_TILE_COMPONENTS_OK: 原点/口径/碰撞/色盘契约全部成立")
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
	var packed := load(str(case["scene"])) as PackedScene
	if packed == null:
		failures.append("%s 包装场景加载失败：%s" % [slug, case["scene"]])
		return
	var inst := packed.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	_check_metadata(inst, case, failures)
	_check_geometry(inst, case, failures)
	_check_collision(inst, case, failures)
	inst.queue_free()


func _check_metadata(inst: Node3D, case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	_expect_meta(inst, slug, "asset_id", str(case["asset_id"]), failures)
	_expect_meta(inst, slug, "origin_contract", "bottom_center", failures)
	_expect_meta(inst, slug, "forward_axis", "-Z", failures)
	_expect_meta(inst, slug, "collision_owner", "self", failures)
	_expect_meta(inst, slug, "collision_policy", "embedded_box_bottom_center", failures)
	if not inst.has_meta("snap_to_walk_plane_offset_m"):
		failures.append("%s 缺少 metadata/snap_to_walk_plane_offset_m，接入方无从得知落位偏移" % slug)
	elif not _near(
		float(inst.get_meta("snap_to_walk_plane_offset_m")),
		-float(case["thickness"])
	):
		failures.append("%s 落位偏移 %.4f 与厚度不一致" % [slug, float(inst.get_meta("snap_to_walk_plane_offset_m"))])


func _check_geometry(inst: Node3D, case: Dictionary, failures: Array[String]) -> void:
	var slug := str(case["slug"])
	var bounds := _local_bounds(inst)
	if bounds.size == Vector3.ZERO:
		failures.append("%s 没有可用的可视网格" % slug)
		return
	var size := bounds.size
	var footprint := float(case["footprint"])
	var thickness := float(case["thickness"])
	if not _near(size.x, footprint) or not _near(size.z, footprint):
		failures.append("%s XZ = %.4f x %.4f，期望 %.2f" % [slug, size.x, size.z, footprint])
	if not _near(size.y, thickness):
		failures.append("%s 厚度 = %.4f，期望 %.3f" % [slug, size.y, thickness])
	if absf(bounds.position.y) > EPS:
		failures.append("%s 底面 Y = %.4f，期望 0.0（底面中心原点）" % [slug, bounds.position.y])
	if absf(bounds.position.x + bounds.end.x) > EPS or absf(bounds.position.z + bounds.end.z) > EPS:
		failures.append("%s XZ 未相对原点居中：x[%.4f,%.4f] z[%.4f,%.4f]" % [
			slug, bounds.position.x, bounds.end.x, bounds.position.z, bounds.end.z
		])


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
		failures.append("%s 碰撞盒 = %v，期望 %.2f x %.3f x %.2f" % [slug, box.size, footprint, thickness, footprint])
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
