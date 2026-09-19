extends SceneTree
## 一次性核对：塔楼门墙 prefab 实例化后的节点树 / 可视包络 / 材质表面。
##
## 为什么单独写一个：probe_door_anchor 只测它挑中的那个房间（楼梯厅，本身不建
## 门墙模块），所以「门墙模块长什么样」它答不上来。本探针直接实例化 prefab，
## 是替换美术后最贴近资产本身的一层核对。
##
## 判据 PREFAB_DOOR_WALL_OK：
##   · 可视 AABB = (5.0, 11.9, 0.683)，关于 z=0 对称，落在 z ∈ [-0.3415, 0.3415]
##     （v005 双面：装饰面在两侧各前凸到 ±0.3415；v004 是 [-0.15, 0.3415] 单面）
##   · 视觉节点解析到 ENV_TOWER_WALL_DOOR_5M
##   · 网格表面数 = 4（四个美术材质角色）
##   · 子节点里没有静态门扇（门扇由 RoomDoor3D 提供）
##   · 无内嵌碰撞、无 material_override

const PREFAB := "res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn"
const EXPECTED_VERSION := "v005"
const EXPECTED_SIZE := Vector3(5.0, 11.9, 0.683)
const EXPECTED_SURFACES := 4
const DECOR_DEPTH_M := 0.3415
const GEOM := preload("res://src/world3d/TowerGeometry3D.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(PREFAB) as PackedScene
	if packed == null:
		printerr("PREFAB_DOOR_WALL_FAILED: 无法加载 %s" % PREFAB)
		quit(1)
		return
	var instance := packed.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Holder"
	holder.add_child(instance)
	root.add_child(holder)
	await process_frame

	print("=== 门墙 prefab 实例化核对 ===")
	print("node name            = %s" % instance.name)
	print("metadata/asset_id    = %s" % instance.get_meta("asset_id", "<无>"))
	print("metadata/version     = %s" % instance.get_meta("asset_version", "<无>"))
	print("metadata/visual_node = %s" % instance.get_meta("visual_node_name", "<无>"))
	print("metadata/forward     = %s" % instance.get_meta("forward_axis", "<无>"))
	print("metadata/origin      = %s" % instance.get_meta("origin_contract", "<无>"))
	print("metadata/visual_size = %s" % str(instance.get_meta("visual_bounds_size_m", "<无>")))
	print("metadata/bounds_size = %s" % str(instance.get_meta("bounds_size_m", "<无>")))
	print("metadata/runtime     = %s" % instance.get_meta("runtime_instantiation", "<无>"))

	var resolved := GEOM.resolve_visual_node(instance)
	print("resolve_visual_node  = %s" % (String(resolved.name) if resolved != null else "<null>"))

	var bounds := _visual_bounds(instance)
	print("visual AABB local    = pos=%s size=%s" % [
		str(bounds.position.snappedf(0.0001)), str(bounds.size.snappedf(0.0001))
	])
	_expect(bounds.size.is_equal_approx(EXPECTED_SIZE), "可视 AABB size=%s，期望 %s" % [
		str(bounds.size), str(EXPECTED_SIZE)
	])
	# v005 双面：包络必须关于 z=0 对称（结构板基准面），否则镜像跑到了错误的平面上。
	_expect(
		absf(bounds.position.z + bounds.end.z) < 0.002,
		"可视包络不关于 z=0 对称：[%.5f, %.5f]（双面镜像应围绕基准面）"
		% [bounds.position.z, bounds.end.z]
	)
	_expect(
		absf(bounds.position.z + DECOR_DEPTH_M) < 0.002,
		"可视 AABB 起点 z=%.5f，期望 %.4f（v005 起装饰面两面各前凸到 ±%.4f）"
		% [bounds.position.z, -DECOR_DEPTH_M, DECOR_DEPTH_M]
	)
	_expect(
		absf(bounds.end.z - DECOR_DEPTH_M) < 0.002,
		"可视 AABB 终点 z=%.5f，期望 %.4f（房内侧装饰面）" % [bounds.end.z, DECOR_DEPTH_M]
	)
	_expect(absf(bounds.position.y) < 0.002, "底面 y=%.5f，期望 0" % bounds.position.y)
	_expect(
		String(instance.get_meta("asset_version", "")) == EXPECTED_VERSION,
		"asset_version=%s，期望 %s" % [instance.get_meta("asset_version", "<无>"), EXPECTED_VERSION]
	)
	_expect(
		bool(instance.get_meta("double_sided", false)),
		"prefab 未声明 double_sided=true，双面这件事在 prefab 层就丢了"
	)

	var surfaces := 0
	var mesh_nodes := 0
	for value in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		mesh_nodes += 1
		surfaces += mesh_instance.mesh.get_surface_count()
		print("mesh node            = %s surfaces=%d aabb=%s" % [
			mesh_instance.name,
			mesh_instance.mesh.get_surface_count(),
			str(mesh_instance.mesh.get_aabb().size.snappedf(0.0001)),
		])
		print("   override          = %s" % (
			"null(美术自带)"
			if mesh_instance.material_override == null
			else String(mesh_instance.material_override.resource_name)
		))
		for index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(index)
			var label := "<null>" if material == null else String(material.resource_name)
			var has_texture := false
			var standard := material as StandardMaterial3D
			if standard != null:
				has_texture = standard.albedo_texture != null
			print("   surface[%d]        = %s albedo_texture=%s" % [index, label, str(has_texture)])
		_expect(
			mesh_instance.material_override == null,
			"%s 存在 material_override，美术被主题覆盖" % mesh_instance.name
		)
	print("mesh node count      = %d  合计表面数 = %d" % [mesh_nodes, surfaces])
	_expect(surfaces == EXPECTED_SURFACES, "表面数=%d，期望 %d（四个美术材质角色）" % [
		surfaces, EXPECTED_SURFACES
	])

	var leaf_hits: Array[String] = []
	for value in instance.find_children("*", "Node", true, false):
		var child := value as Node
		if child != null and String(child.name).contains("DoorLeaf"):
			leaf_hits.append(String(child.name))
	print("静态门扇节点         = %s" % (str(leaf_hits) if leaf_hits.size() > 0 else "无（门扇由 RoomDoor3D 提供）"))
	_expect(leaf_hits.is_empty(), "门墙仍带静态门扇节点 %s，会与 RoomDoor3D 门扇重叠" % str(leaf_hits))

	var shapes := 0
	for value in instance.find_children("*", "CollisionShape3D", true, false):
		shapes += 1
	print("内嵌 CollisionShape  = %d" % shapes)
	_expect(shapes == 0, "prefab 内嵌了 %d 个碰撞，应全部由脚本代理提供" % shapes)

	if _failures.is_empty():
		print("PREFAB_DOOR_WALL_OK: 门墙 prefab 节点树/包络/四表面/无门扇/无内嵌碰撞全部成立")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("PREFAB_DOOR_WALL_FAILED count=%d" % _failures.size())
	quit(1)


func _visual_bounds(node: Node) -> AABB:
	var acc := AABB()
	var found := false
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local := mesh_instance.transform * mesh_instance.mesh.get_aabb()
		acc = local if not found else acc.merge(local)
		found = true
	return acc


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
