extends SceneTree
## 战局区块通用组件库 v003 · 09 地板组件（floor_tile_5m）运行时契约断言。
##
## 盯住的是三件事，任何一条不成立就退出码非 0：
##   1. 原点契约：底面中心（Godot 底面 Y=0、XZ 居中）—— 替换资产时的定位基准。
##   2. 几何口径：footprint 4.94m × 4.94m、厚度 = manifest 值（c01 0.056 / c02 0.081）。
##   3. 内嵌碰撞与色盘后处理是否真的生效（collision_owner = self；
##      albedo_texture 必须指向共享色盘而非 GLB 自带图）。
##
## 运行：
##   "I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe" \
##       --headless --path "I:\工作项目\shellstrom2\ShellStorm2" \
##       --script res://assets/art/environments/tower_zones/battle/source/common_components/v003/qa/probe_floor_tile_components.gd

const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const EPS := 0.0015

const CASES := [
	{
		"slug": "floor_tile_r01_c01",
		"scene": "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn",
		"footprint": 4.94,
		"thickness": 0.056,
		"asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
	},
	{
		"slug": "floor_tile_r01_c02",
		"scene": "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d.tscn",
		"footprint": 4.94,
		"thickness": 0.081,
		"asset_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
	},
]

## 顺带验证 `;` 行注释格式能解析（本组件沿用了 L 型转角包装的写法）。
const REFERENCE_L_CORNER := "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v005.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== battle common floor tile component contract probe ===")

	_check_reference_comment_format()

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


func _check_reference_comment_format() -> void:
	var packed := load(REFERENCE_L_CORNER) as PackedScene
	if packed == null:
		_bad("reference_l_corner", "%s 无法解析（行注释格式不可用）" % REFERENCE_L_CORNER)
	else:
		_ok("reference_l_corner", "L 型转角 v005 包装可解析，行注释写法可用")


func _check_case(case: Dictionary) -> void:
	var slug: String = case["slug"]
	print("")
	print("--- %s ---" % slug)

	var packed := load(case["scene"]) as PackedScene
	if packed == null:
		_bad(slug + "/load", "%s 加载失败" % case["scene"])
		return
	_ok(slug + "/load", case["scene"])

	var inst := packed.instantiate() as Node3D

	# 注意：_initialize() 阶段 SceneTree.root 尚未入树，get_global_transform() 会返回
	# 单位矩阵。因此全部改用「相对组件根节点」的变换自行累乘，结果与场景树无关。

	# --- metadata 契约 ---
	_expect_meta(inst, slug, "asset_id", case["asset_id"])
	_expect_meta(inst, slug, "origin_contract", "bottom_center")
	_expect_meta(inst, slug, "forward_axis", "-Z")
	_expect_meta(inst, slug, "collision_owner", "self")

	# --- 网格 AABB（Godot 局部空间，root 在原点） ---
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	if meshes.is_empty():
		_bad(slug + "/mesh", "未找到 MeshInstance3D")
	else:
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
	var footprint: float = case["footprint"]
	var thickness: float = case["thickness"]

	# 口径：X/Z = footprint，Y = 厚度
	if _near(size.x, footprint) and _near(size.z, footprint):
		_ok(slug + "/footprint", "XZ = %.4f x %.4f（期望 %.2f）" % [size.x, size.z, footprint])
	else:
		_bad(slug + "/footprint", "XZ = %.4f x %.4f，期望 %.2f x %.2f" % [size.x, size.z, footprint, footprint])

	if _near(size.y, thickness):
		_ok(slug + "/thickness", "Y = %.4f（期望 %.3f）" % [size.y, thickness])
	else:
		_bad(slug + "/thickness", "Y = %.4f，期望 %.3f" % [size.y, thickness])

	# 原点契约：底面贴 Y=0、XZ 居中
	if _near(mn.y, 0.0):
		_ok(slug + "/origin_y", "底面 Y = %.4f（期望 0.0）" % mn.y)
	else:
		_bad(slug + "/origin_y", "底面 Y = %.4f，期望 0.0" % mn.y)

	if _near(mn.x, -mx.x) and _near(mn.z, -mx.z):
		_ok(slug + "/origin_centered", "XZ 居中：x[%.3f,%.3f] z[%.3f,%.3f]" % [mn.x, mx.x, mn.z, mx.z])
	else:
		_bad(slug + "/origin_centered", "XZ 未居中：x[%.4f,%.4f] z[%.4f,%.4f]" % [mn.x, mx.x, mn.z, mx.z])

	print("        AABB min=%v max=%v size=%v" % [mn, mx, size])
	print("        材质=%s" % str(material_names))

	# --- 色盘后处理是否生效 ---
	if surface_total > 0 and palette_bound == surface_total:
		_ok(slug + "/palette", "%d/%d 个 surface 已绑定共享色盘" % [palette_bound, surface_total])
	else:
		_bad(slug + "/palette", "仅 %d/%d 个 surface 绑定共享色盘（后处理未生效？）" % [palette_bound, surface_total])
	_ok(slug + "/surface_count", "surface 共 %d 个" % surface_total)

	# --- 内嵌碰撞 ---
	var shape_node := _first_collision_shape(inst)
	if shape_node == null:
		_bad(slug + "/collision", "未找到 CollisionShape3D")
	else:
		var box := shape_node.shape as BoxShape3D
		if box == null:
			_bad(slug + "/collision", "CollisionShape3D.shape 不是 BoxShape3D")
		else:
			var csize := box.size
			if _near(csize.x, footprint) and _near(csize.z, footprint) and _near(csize.y, thickness):
				_ok(slug + "/collision_box", "Box = %v（期望 %.2f x %.3f x %.2f）" % [csize, footprint, thickness, footprint])
			else:
				_bad(slug + "/collision_box", "Box = %v，期望 %.2f x %.3f x %.2f" % [csize, footprint, thickness, footprint])
			# 碰撞体的相对上下沿应与网格一致
			var half := csize.y * 0.5
			var c_pos := _rel_transform(shape_node, inst).origin
			var c_bottom := c_pos.y - half
			var c_top := c_pos.y + half
			if _near(c_bottom, mn.y) and _near(c_top, mx.y):
				_ok(slug + "/collision_align", "碰撞体 Y[%.4f,%.4f] 与网格 Y[%.4f,%.4f] 齐平" % [c_bottom, c_top, mn.y, mx.y])
			else:
				_bad(slug + "/collision_align", "碰撞体 Y[%.4f,%.4f] 与网格 Y[%.4f,%.4f] 不齐" % [c_bottom, c_top, mn.y, mx.y])

	# --- 与运行时常量的口径差 ---
	var runtime_grid := 5.0
	var runtime_thickness := 0.30
	print("        		vs 运行时：网格 %.2f → 本组件 %.2f（缝 %.3f）；厚 %.2f → 本组件 %.3f" % [
		runtime_grid, footprint, runtime_grid - footprint, runtime_thickness, thickness
	])

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


func _first_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found := _first_collision_shape(child)
		if found != null:
			return found
	return null


func _expect_meta(node: Node, slug: String, key: String, expected: String) -> void:
	if not node.has_meta(key):
		_bad(slug + "/meta:" + key, "缺少 metadata/%s" % key)
		return
	var got := String(node.get_meta(key))
	if got == expected:
		_ok(slug + "/meta:" + key, got)
	else:
		_bad(slug + "/meta:" + key, "得到 %s，期望 %s" % [got, expected])
