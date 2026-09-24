extends SceneTree
## 远征关卡01 · Boss房通用组件库 v001 · 6 件专属组件运行时契约断言。
##
## 盯住五件事，任何一条不成立就退出码非 0：
##   1. 可加载：PackedScene 能解析、实例化后确有 MeshInstance3D。
##   2. 元数据契约：asset_id / origin_contract=bottom_center / collision_owner / policy / shape_count=0。
##   3. 几何口径：底面贴 Y=0、XZ 居中、尺寸 = catalog 声明的 Godot 系包围盒。
##   4. 无内嵌阻挡：包内不得出现 StaticBody3D / CollisionShape3D（6 件按设计均不持有碰撞）。
##   5. 色盘：每个 surface 都绑上了共享色盘（scene_facility_shared_palette 后处理生效）。
##
## 运行：
##   "I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" \
##       --headless --path "I:\工作项目\shellstrom2\ShellStorm2" \
##       --script res://assets/art/environments/tower_zones/expedition/source/common_components/v001/qa/probe_boss_component_prefabs.gd

const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const LIBRARY_ID := "ENV-EXPEDITION-L01-COMMON-COMPONENT-LIBRARY"
const EPS := 0.002
const RUNTIME_ROOT := "res://assets/art/environments/tower_zones/expedition/runtime/common_components/"

const CASES := [
	{
		"slug": "base_floor_base",
		"asset_id": "ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE",
		"library_root_object": "ExpeditionCommonBaseFloorBase",
		"size": Vector3(50.0, 0.26, 40.0),
		"collision_owner": "TowerFloorStage3D._build_support",
		"collision_policy": "external_owner_no_shape_in_package",
		"forward_axis": "+Y",
	},
	{
		"slug": "main_fault_screen",
		"asset_id": "ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN",
		"library_root_object": "ExpeditionCommonMainFaultScreen",
		"size": Vector3(21.52, 7.09, 1.575),
		"collision_owner": "none",
		"collision_policy": "no_blocking_by_design",
		"forward_axis": "+Z",
	},
	{
		"slug": "heavy_conduits",
		"asset_id": "ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS",
		"library_root_object": "ExpeditionCommonHeavyConduits",
		"size": Vector3(47.305603, 3.672169, 32.303619),
		"collision_owner": "none",
		"collision_policy": "no_blocking_by_design",
		"forward_axis": "+Z",
	},
	{
		"slug": "north_wall_typography",
		"asset_id": "ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY",
		"library_root_object": "ExpeditionCommonNorthWallTypography",
		"size": Vector3(35.900246, 2.3201, 0.041998),
		"collision_owner": "none",
		"collision_policy": "no_blocking_by_design",
		"forward_axis": "+Z",
	},
	{
		"slug": "south_floor_marking",
		"asset_id": "ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING",
		"library_root_object": "ExpeditionCommonSouthFloorMarking",
		"size": Vector3(3.696866, 0.012, 2.726689),
		"collision_owner": "none",
		"collision_policy": "no_blocking_by_design",
		"forward_axis": "+Z",
	},
	{
		"slug": "debris_00",
		"asset_id": "ENV-EXPEDITION-BOSSROOM-DEBRIS-00",
		"library_root_object": "ExpeditionCommonDebris00",
		"size": Vector3(2.425321, 0.2195, 1.988281),
		"collision_owner": "none",
		"collision_policy": "no_blocking_by_design",
		"forward_axis": "+Z",
	},
]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== expedition boss common component prefab probe ===")
	for case in CASES:
		_check_case(case)
	print("")
	print("RESULT pass=%d fail=%d" % [_pass, _fail])
	print("PROBE_OK" if _fail == 0 else "PROBE_FAIL")
	quit(0 if _fail == 0 else 1)


func _ok(label: String, detail: String) -> void:
	_pass += 1
	print("  [PASS] %s — %s" % [label, detail])


func _bad(label: String, detail: String) -> void:
	_fail += 1
	print("  [FAIL] %s — %s" % [label, detail])


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


func _check_case(case: Dictionary) -> void:
	var slug: String = case["slug"]
	print("")
	print("--- %s ---" % slug)

	var scene_path: String = RUNTIME_ROOT + slug + "/" + slug + "_root_top3d.tscn"
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_bad(slug + "/load", "%s 加载失败" % scene_path)
		return
	_ok(slug + "/load", scene_path)

	var inst := packed.instantiate() as Node3D
	if inst == null:
		_bad(slug + "/instantiate", "实例化未得到 Node3D")
		return

	# --- 根节点名与 metadata 契约 ---
	if String(inst.name) == String(case["library_root_object"]):
		_ok(slug + "/root_name", String(inst.name))
	else:
		_bad(slug + "/root_name", "得到 %s，期望 %s" % [inst.name, case["library_root_object"]])
	_expect_meta(inst, slug, "asset_id", case["asset_id"])
	_expect_meta(inst, slug, "asset_version", "v001")
	_expect_meta(inst, slug, "library_id", LIBRARY_ID)
	_expect_meta(inst, slug, "origin_contract", "bottom_center")
	_expect_meta(inst, slug, "forward_axis", case["forward_axis"])
	_expect_meta(inst, slug, "collision_owner", case["collision_owner"])
	_expect_meta(inst, slug, "collision_policy", case["collision_policy"])
	_expect_meta(inst, slug, "collision_shape_count", "0")

	# --- 网格 AABB（Godot 局部空间，root 在原点；自行累乘不依赖场景树） ---
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	if meshes.is_empty():
		_bad(slug + "/mesh", "未找到 MeshInstance3D（GLB 未实例化？）")
		inst.free()
		return
	_ok(slug + "/mesh", "MeshInstance3D x%d" % meshes.size())

	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var surface_total := 0
	var palette_bound := 0
	var material_names: Array[String] = []
	for mi in meshes:
		var aabb := mi.mesh.get_aabb()
		var xform := _rel_transform(mi, inst)
		for i in 8:
			var p := xform * aabb.get_endpoint(i)
			mn = mn.min(p)
			mx = mx.max(p)
		surface_total += mi.mesh.get_surface_count()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var nm := String(mat.resource_name)
			if not material_names.has(nm):
				material_names.append(nm)
			if mat.albedo_texture != null and mat.albedo_texture.resource_path == PALETTE_PATH:
				palette_bound += 1

	var size := mx - mn
	var expect: Vector3 = case["size"]
	print("        AABB min=%v max=%v size=%v" % [mn, mx, size])
	print("        材质=%s" % str(material_names))

	# --- 尺寸口径（逐轴，容差 2mm） ---
	if _near(size.x, expect.x) and _near(size.y, expect.y) and _near(size.z, expect.z):
		_ok(slug + "/size", "%v（期望 %v）" % [size, expect])
	else:
		_bad(slug + "/size", "%v，期望 %v" % [size, expect])

	# --- 原点契约：底面贴 Y=0、XZ 居中 ---
	if _near(mn.y, 0.0):
		_ok(slug + "/origin_y", "底面 Y = %.4f（期望 0.0）" % mn.y)
	else:
		_bad(slug + "/origin_y", "底面 Y = %.4f，期望 0.0" % mn.y)

	if _near(mn.x, -mx.x) and _near(mn.z, -mx.z):
		_ok(slug + "/origin_centered", "XZ 居中：x[%.3f,%.3f] z[%.3f,%.3f]" % [mn.x, mx.x, mn.z, mx.z])
	else:
		_bad(slug + "/origin_centered", "XZ 未居中：x[%.4f,%.4f] z[%.4f,%.4f]" % [mn.x, mx.x, mn.z, mx.z])

	# --- 无内嵌阻挡：包内不得出现 StaticBody3D / CollisionShape3D ---
	var bodies: Array[Node] = []
	_collect_by_type(inst, "StaticBody3D", bodies)
	var shapes: Array[Node] = []
	_collect_by_type(inst, "CollisionShape3D", shapes)
	if bodies.is_empty() and shapes.is_empty():
		_ok(slug + "/no_collision", "包内无 StaticBody3D / CollisionShape3D（按设计不持有阻挡）")
	else:
		_bad(slug + "/no_collision", "包内出现 StaticBody3D x%d / CollisionShape3D x%d" % [bodies.size(), shapes.size()])

	# --- 色盘绑定：scene_facility_shared_palette 后处理是否生效 ---
	if surface_total > 0 and palette_bound == surface_total:
		_ok(slug + "/palette", "%d/%d 个 surface 已绑定共享色盘" % [palette_bound, surface_total])
	else:
		_bad(slug + "/palette", "仅 %d/%d 个 surface 绑定共享色盘（后处理未生效？）" % [palette_bound, surface_total])

	inst.free()


## 相对某个祖先节点的变换（自行累乘，不依赖场景树状态）。
func _rel_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node3D = node
	while cur != null and cur != ancestor:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _collect_by_type(node: Node, type_name: String, out: Array[Node]) -> void:
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		_collect_by_type(child, type_name, out)


func _expect_meta(node: Node, slug: String, key: String, expected: String) -> void:
	if not node.has_meta(key):
		_bad(slug + "/meta:" + key, "缺少 metadata/%s" % key)
		return
	var got := str(node.get_meta(key))
	if got == expected:
		_ok(slug + "/meta:" + key, got)
	else:
		_bad(slug + "/meta:" + key, "得到 %s，期望 %s" % [got, expected])
