extends Node
## 天台女儿墙破损变体探针（资产层）。
##
## 用户口径：在 Blender 里做 3 个破损变种（三种不同破损），**但要能接起来**，
## 导入成新 prefab 后由外墙随机排布。本探针把「能接起来」翻译成可实测的判据：
##   1. 三件破损件与 intact 件 **同包络**（5.00×高度×0.50，高度取运行时口径常量，
##      2026-09-20 起 = 0.80m）且同原点（底面中心）；
##   2. 三件破损件的 **端头带 |x|>=2.05m 顶点与 intact 件一致**（去重后位置集合大小相等
##      + 点云双向最近邻最大距离 <= 0.2mm）—— 这是「接头无缝、槽位相位不变」的硬证据，
##      光看包络相同抓不到。源文件的逐位相同由
##      source/verify_env_rooftop_parapet_damage_bands.py 在 GLB 字节层证明（Godot 的
##      固定导入管线做不了「源文件」级比对，见 _compare_cross_variant 的说明）；
##      ⚠️ 判据用「去重后位置集合」，不用「原始顶点数」：glTF 按 (position,normal,uv)
##      三元组拆点，布尔切割会改变某个既有端头带顶点的 UV 参数化 → 同一位置被发射两次
##      （实测 dmg_b 端头带原始 292 顶点 vs intact 288，去重后同为 72 个位置、Hausdorff=0）。
##      原始顶点数是导入管线的记账产物，不是几何；拿它当判据会把「几何逐位相同」误报成不同。
##   3. 三件与 intact 件 **同色盘绑定**（PaletteUV 材质，albedo_texture != null）；
##   4. 三件与 intact 件 **同契约**（visual_only 无内嵌碰撞、无 material_override、
##      统一字段齐全、visual_node_name 能解析到真实节点且不靠回退）。
##
## 纯诊断，不算门禁；输出 PROBE_DMG_* 行供比对。
## 跑法：Godot --headless --path <项目> res://tests/verification/probe_rooftop_parapet_damage_prefabs.tscn

const GEOM := preload("res://src/world3d/TowerGeometry3D.gd")

const END_BAND_START_M := 2.05
const TOLERANCE_M := 0.01
## 高度取运行时口径常量（2026-09-20 起 = 0.80m），不写字面量：
## 破损件与 intact 件必须同包络，而「同包络」的绝对值就是脚本声明的高度。
const EXPECTED_SIZE := Vector3(5.0, TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT, 0.5)

const TARGETS: Array[Dictionary] = [
	{
		"key": "intact",
		"asset_id": "ENV-ROOFTOP-REF-PARAPET",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_parapet_5m.tscn",
		"node": "女儿墙直段_主体",
	},
	{
		"key": "dmg_a",
		"asset_id": "ENV-ROOFTOP-REF-PARAPET-DMG-A",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_a_5m.tscn",
		"node": "女儿墙直段破损A_主体",
	},
	{
		"key": "dmg_b",
		"asset_id": "ENV-ROOFTOP-REF-PARAPET-DMG-B",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_b_5m.tscn",
		"node": "女儿墙直段破损B_主体",
	},
	{
		"key": "dmg_c",
		"asset_id": "ENV-ROOFTOP-REF-PARAPET-DMG-C",
		"prefab": "res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_c_5m.tscn",
		"node": "女儿墙直段破损C_主体",
	},
]

const REQUIRED_FIELDS: Array[String] = [
	"asset_id",
	"asset_version",
	"origin_contract",
	"forward_axis",
	"bounds_size_m",
	"visual_bounds_size_m",
	"visual_node_name",
	"visual_only",
	"collision_owner",
	"preserve_authored_palette",
	"runtime_instantiation",
]

var _failures: Array[String] = []
var _band_keys := {}
var _mesh_sizes := {}


func _ready() -> void:
	for target in TARGETS:
		_verify(target)
	print(
		"PROBE_DMG samples=%d (intact=1 + damaged=%d)"
		% [TARGETS.size(), TARGETS.size() - 1]
	)
	# 防假绿哨兵：样本数为 0 / 只跑到 intact 时，下面的比对会「怎么都绿」。
	if TARGETS.size() < 4:
		_failures.append("样本数不足：期望 1 件 intact + 3 件破损，实际 %d" % TARGETS.size())
	_compare_cross_variant()
	if _failures.is_empty():
		print(
			"PROBE_DMG_DONE seamless_band=true envelope_match=true palette_bound=true contract_ok=true"
		)
	else:
		for failure in _failures:
			print("PROBE_DMG_FAIL %s" % failure)
		print("PROBE_DMG_DONE failures=%d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify(target: Dictionary) -> void:
	var key := str(target["key"])
	var path := str(target["prefab"])
	var declared := str(target["node"])
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_failures.append("%s 无法加载 %s" % [key, path])
		return
	var root := packed.instantiate()
	var missing := GEOM.missing_contract_fields(root, REQUIRED_FIELDS)
	var resolved := GEOM.resolve_visual_node(root)
	var resolved_name := String(resolved.name) if resolved != null else "<null>"
	var bounds := GEOM.resolve_visual_bounds(root)
	var mesh := GEOM.resolve_visual_mesh(root)
	if mesh == null:
		_failures.append("%s 找不到可视网格" % key)
		root.free()
		return
	var aabb := mesh.get_aabb()
	print(
		"PROBE_DMG %-6s asset_id=%s declared=%s resolved=%s"
		% [key, str(root.get_meta("asset_id", "")), declared, resolved_name]
	)
	print(
		"PROBE_DMG %-6s visual_bounds pos=%s size=%s  mesh_aabb pos=%s size=%s"
		% [key, _vec(bounds.position), _vec(bounds.size), _vec(aabb.position), _vec(aabb.size)]
	)

	if not missing.is_empty():
		_failures.append("%s 缺统一契约字段: %s" % [key, str(missing)])
	if str(root.get_meta("asset_id", "")) != str(target["asset_id"]):
		_failures.append(
			"%s asset_id=%s，期望 %s" % [key, str(root.get_meta("asset_id", "")), str(target["asset_id"])]
		)
	if resolved_name != declared:
		_failures.append("%s visual_node_name 声明 %s 但解析为 %s（声明节点不存在）" % [key, declared, resolved_name])
	if str(root.get_meta("origin_contract", "")) != "bottom_center":
		_failures.append("%s origin_contract=%s，期望 bottom_center" % [key, str(root.get_meta("origin_contract", ""))])
	if str(root.get_meta("forward_axis", "")) != "+Z":
		_failures.append("%s forward_axis=%s，期望 +Z" % [key, str(root.get_meta("forward_axis", ""))])
	if str(root.get_meta("runtime_instantiation", "")) != "batched_multimesh":
		_failures.append("%s runtime_instantiation=%s，期望 batched_multimesh" % [key, str(root.get_meta("runtime_instantiation", ""))])
	_mesh_sizes[key] = aabb.size
	if not aabb.size.is_equal_approx(EXPECTED_SIZE):
		_failures.append("%s 网格包络 %s != %s" % [key, _vec(aabb.size), _vec(EXPECTED_SIZE)])
	if absf(aabb.position.y) > TOLERANCE_M:
		_failures.append("%s 网格底面不在 Y=0（%s）" % [key, _vec(aabb.position)])
	var bodies := root.find_children("*", "StaticBody3D", true, false)
	var shapes := root.find_children("*", "CollisionShape3D", true, false)
	if not bodies.is_empty() or not shapes.is_empty():
		_failures.append("%s 内嵌了碰撞（body=%d shape=%d）" % [key, bodies.size(), shapes.size()])
	var overrides := _count_overrides(root)
	if overrides > 0:
		_failures.append("%s 有 %d 处 material_override（会盖掉美术色盘）" % [key, overrides])

	var surfaces := mesh.get_surface_count()
	print("PROBE_DMG %-6s surfaces=%d" % [key, surfaces])
	if surfaces < 1:
		_failures.append("%s 没有材质表面" % key)
	for index in range(surfaces):
		var material := mesh.surface_get_material(index)
		var material_name := "<null>"
		var palette_bound := false
		if material is BaseMaterial3D:
			material_name = String((material as BaseMaterial3D).resource_name)
			palette_bound = (material as BaseMaterial3D).albedo_texture != null
		print(
			"PROBE_DMG %-6s surface=%d material=%s palette_texture_bound=%s"
			% [key, index, material_name, palette_bound]
		)
		if not palette_bound:
			_failures.append("%s surface=%d 未绑定共享色盘（palette_texture_bound=false，会渲染成白板）" % [key, index])

	var band_points := _end_band_points(mesh)
	_band_keys[key] = band_points
	print(
		"PROBE_DMG %-6s end_band_vertices=%d (|x|>=%.2f)"
		% [key, band_points.size(), END_BAND_START_M]
	)
	if band_points.is_empty():
		_failures.append("%s 端头带顶点为 0（哨兵：比对会假绿）" % key)
	root.free()


## 三件破损件必须与 intact 件在端头带一致（接头无缝）、包络逐值一致。
##
## ⚠️ 这里刻意**不**做「排序后逐点相减」：
##   Godot 的 glTF 导入会把顶点过一遍焊接/去重，对「位置几乎重合的重复顶点」只留一个
##   代表，而留哪个取决于遍历顺序。同一个源值在 intact 与派生件里因此可能被换成
##   邻近的重复点（实测 2.4709999… 被换成 2.470932，差 6.8e-5 m），排序后逐点相减
##   就会在同一个下标上配到两个不同的点，把「源文件逐位相同」的几何误报成不同。
##   源文件的逐位相同由 source/verify_env_rooftop_parapet_damage_bands.py 在 GLB
##   字节层证明（那才是「端头带没被动过」的权威证据）。
##   本探针改用「点云最近邻」比法：intact 端头带每个点到派生件端头带的最近距离、
##   以及反方向，都必须 <= 0.2mm。它对上述顶点重排免疫，同时照样抓得住「真的动了
##   端头带」——端头带里的构件特征（36mm 分隔带、倒角）尺度是厘米级，一旦真被动过，
##   最近邻距离会是毫米到厘米级，远超阈值。
const BAND_MAX_NEAREST_NEIGHBOUR_M := 2.0e-4


func _compare_cross_variant() -> void:
	var intact_points: Array = _band_keys.get("intact", [])
	if intact_points.is_empty():
		return
	var intact_unique := _dedup_points(intact_points)
	var intact_size: Vector3 = _mesh_sizes.get("intact", Vector3.ZERO)
	for target in TARGETS:
		var key := str(target["key"])
		if key == "intact":
			continue
		var points: Array = _band_keys.get(key, [])
		var unique_points := _dedup_points(points)
		# 判据 = 去重后位置集合大小（不是原始顶点数，见文件头说明）。
		if unique_points.size() != intact_unique.size():
			_failures.append(
				"%s 端头带去重位置数 %d != intact 件 %d —— 接头会错位"
				% [key, unique_points.size(), intact_unique.size()]
			)
		else:
			var forward := _max_nearest_neighbour(intact_unique, unique_points)
			var backward := _max_nearest_neighbour(unique_points, intact_unique)
			var worst := maxf(forward, backward)
			print(
				"PROBE_DMG %-6s end_band_unique=%d (raw=%d) pointcloud_max_nn=%.7f m (intact->variant=%.7f variant->intact=%.7f)"
				% [key, unique_points.size(), points.size(), worst, forward, backward]
			)
			if worst > BAND_MAX_NEAREST_NEIGHBOUR_M:
				_failures.append(
					"%s 端头带点云最近邻最大距离 %.6f m > %.4f m —— 接头会错位"
					% [key, worst, BAND_MAX_NEAREST_NEIGHBOUR_M]
				)
		var variant_size: Vector3 = _mesh_sizes.get(key, Vector3.ZERO)
		if not variant_size.is_equal_approx(intact_size):
			_failures.append("%s 网格包络与 intact 件不同" % key)


## 位置集合去重：glTF 会按 (position,normal,uv) 拆点，同一位置可能出现多次。
## 几何判据只关心「位置集合」，故先按精确值去重（重复点是逐位相同的，无需容差）。
func _dedup_points(points: Array) -> Array:
	var seen := {}
	for point in points:
		seen[point] = true
	return seen.keys()


## 点云 A 中每个点到点云 B 的最近距离的最大值（单向 Hausdorff 距离）。
func _max_nearest_neighbour(from_points: Array, to_points: Array) -> float:
	var worst := 0.0
	for from_point in from_points:
		var nearest := INF
		for to_point in to_points:
			var distance: float = (Vector3(from_point) - Vector3(to_point)).length_squared()
			if distance < nearest:
				nearest = distance
		worst = maxf(worst, sqrt(nearest))
	return worst


## 端头带顶点：只取 |x| >= 2.05m 的顶点，按 (x, y, z) 排序后返回。
## 排序只为了让两份网格可以在没有共享索引的情况下配对；比对见 _compare_cross_variant，
## 用的是点云最近邻而不是同下标相减。
func _end_band_points(mesh: Mesh) -> Array:
	var points: Array = []
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		for point in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(point.x) < END_BAND_START_M - TOLERANCE_M:
				continue
			points.append(point)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if a.x != b.x:
			return a.x < b.x
		if a.y != b.y:
			return a.y < b.y
		return a.z < b.z
	)
	return points


func _count_overrides(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D and (root as MeshInstance3D).material_override != null:
		count += 1
	for child in root.get_children():
		count += _count_overrides(child)
	return count


func _vec(value: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [value.x, value.y, value.z]
