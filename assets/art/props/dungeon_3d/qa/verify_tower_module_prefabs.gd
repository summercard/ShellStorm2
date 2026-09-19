extends SceneTree
## 断言门禁：塔楼通用物体（地板 / 墙壁 / 墙壁门 / 女儿墙 / 门扇 / L 墙角）的「统一契约」是否成立。
##
## 背景：这些件原本各自用「递归取第一个 MeshInstance3D」的隐式约定找视觉网格，
## 已被实测打破 —— prp_tower_wall_door_5m（当时是 v003 塔楼旧套件）的第一个
## MeshInstance3D 是 visible=false 的门扇，尺寸 2.08×2.38×0.18，而不是 5×11.9×0.3 的墙体。
## 该资产 2026-09-19 已换 v004 派生美术（隐藏门扇不复存在），但「隐式取首网格会漂移」
## 这条教训对任何带装饰件/隐藏件的资产都成立。
## 现在改为按资产自己声明的 metadata/visual_node_name 解析，断言门禁盯住这条契约。
## 清单是六件（2026-09-19 加入 prp_tower_door_leaf_5m 与 prp_corner_l_5m），名字里的
## 「四类」已不准确，故判据统一改为带 count 的形式。
##
## 检查项（任一不满足即失败）：
##   1. 统一字段齐全：asset_id / asset_version / origin_contract / forward_axis /
##      bounds_size_m / visual_bounds_size_m / visual_node_name / visual_only /
##      collision_owner / preserve_authored_palette / runtime_instantiation
##   2. visual_node_name 能解析到真实存在的节点，且不靠回退命中
##   3. 根空间可视包络 == visual_bounds_size_m（容差 0.02m）
##   4. origin_contract 语义与实测包络一致（bottom_center / centered_slab / bottom_corner）
##   5. forward_axis 全集一致（塔楼 A 套 = +Z）
##   6. visual_only=true ⇒ Prefab 内不得内嵌任何 StaticBody3D / CollisionShape3D
##   7. preserve_authored_palette=true ⇒ Prefab 内不得有任何 material_override
##   8. runtime_instantiation==batched_multimesh ⇒ 视觉节点必须是 MeshInstance3D
##      （批渲染只吃单个 Mesh 资源，这条正是「墙/地砖不能逐实例化」的编码依据）
##
## 跑法：
##   Godot --headless --path <项目> --script res://assets/art/props/dungeon_3d/qa/verify_tower_module_prefabs.gd

const GEOM := preload("res://src/world3d/TowerGeometry3D.gd")

const TOLERANCE_M := 0.02
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
const EXPECTED_FORWARD_AXIS := "+Z"
const VALID_INSTANTIATION: Array[String] = ["per_instance_prefab", "batched_multimesh"]

const TARGETS: Array[String] = [
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn",
	# 2026-09-19 新增：5m 段门扇（门板）。与门墙共用 forward_axis=+Z，
	# 由战局通用组件库的 door_5m_通用包派生；原先战斗房的门扇是程序化方块，
	# 没有资产可管，所以它此前不在本门禁里。
	"res://assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn",
	# 2026-09-19 新增：5m L 墙角。它不由单独建模产出，而是两份同一通用墙刚性拼成
	# （见 tower_descent_3d/source/corner_l_5m/），因此首次带来 bottom_corner 原点
	# 约定：原点落在转角而非几何中心。它也是清单里唯一自带碰撞的件（相机下压契约），
	# 故 visual_only=false。
	"res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn",
]

var failures: Array[String] = []


func _initialize() -> void:
	for path in TARGETS:
		_verify(path)
	print("================================================================================")
	if failures.is_empty():
		# 把覆盖的物体种类写进通过信息：这条门禁的目标清单会随资产入册增长
		# （2026-09-19 由四类扩到五类），只印 count 的话看日志的人无法确认
		# 「多出来的那一件」是哪个，也无法确认它真的被检查了。
		print(
			"PREFAB_CONTRACT_OK: 塔楼通用物体（地板/墙壁/墙壁门/女儿墙/门扇/L墙角）统一契约全部成立 count=%d"
			% TARGETS.size()
		)
	else:
		print("PREFAB_CONTRACT_FAILED count=%d" % failures.size())
		for failure in failures:
			print("  - %s" % failure)
	quit(0 if failures.is_empty() else 1)


func _verify(path: String) -> void:
	var file_name := path.get_file()
	print("================================================================================")
	print("### %s" % file_name)
	var packed := ResourceLoader.load(
		path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed == null:
		failures.append("%s 无法加载" % file_name)
		return
	var root := packed.instantiate()

	# 1. 统一字段齐全
	var missing := GEOM.missing_contract_fields(root, REQUIRED_FIELDS)
	for key in missing:
		failures.append("%s 缺统一契约字段: %s" % [file_name, key])
	print("    字段齐全          = %s" % ("是" if missing.is_empty() else "否 %s" % str(missing)))

	# 2. 视觉节点解析（不得靠回退）
	var declared := str(root.get_meta("visual_node_name", ""))
	var resolved := GEOM.resolve_visual_node(root)
	var resolved_name := String(resolved.name) if resolved != null else "<null>"
	print("    visual_node_name  = %s -> %s" % [declared, resolved_name])
	if declared.is_empty():
		failures.append("%s visual_node_name 为空" % file_name)
	elif resolved == null:
		failures.append("%s visual_node_name 解析不到节点: %s" % [file_name, declared])
	elif resolved_name != declared:
		failures.append(
			"%s 声明 %s 但解析回退到 %s（声明节点不存在）"
			% [file_name, declared, resolved_name]
		)
	# 记录「首网格漂移」：声明节点不是第一个 MeshInstance3D 时，说明隐式约定确实不可靠
	var first_mesh := _find_first_mesh(root)
	var first_mesh_name := ""
	if first_mesh != null:
		first_mesh_name = _owner_mesh_instance_name(root, first_mesh)
	if not first_mesh_name.is_empty() and first_mesh_name != declared:
		print(
			"    [记录] 首网格漂移: 递归首件是 %s，声明件是 %s（旧隐式约定会取错）"
			% [first_mesh_name, declared]
		)

	# 3. 可视包络
	var measured := GEOM.resolve_visual_bounds(root)
	var declared_visual := root.get_meta("visual_bounds_size_m", Vector3.ZERO) as Vector3
	print("    可视包络 实测     = pos=%s size=%s" % [
		_vec(measured.position), _vec(measured.size)
	])
	print("    可视包络 声明     = %s" % _vec(declared_visual))
	if measured.size == Vector3.ZERO:
		failures.append("%s 可视包络为空（没有可见网格）" % file_name)
	else:
		var actual_axes := [
			["x", measured.size.x, declared_visual.x],
			["y", measured.size.y, declared_visual.y],
			["z", measured.size.z, declared_visual.z],
		]
		for entry in actual_axes:
			if absf(float(entry[1]) - float(entry[2])) > TOLERANCE_M:
				failures.append(
					"%s 可视包络 %s 实测 %.4f != 声明 %.4f"
					% [file_name, entry[0], entry[1], entry[2]]
				)

	# 4. origin_contract 语义：结构盒必须落在根部原点约定上，且被可视包络包住。
	#    两个包络刻意分离 —— 结构盒是玩法阻挡体，可视包络可以因装饰件外扩。
	#    因此这里不要求「可视包络底面 == 0」，而要求「结构盒 ⊂ 可视包络」。
	var origin_contract := str(root.get_meta("origin_contract", ""))
	var declared_structural := root.get_meta("bounds_size_m", Vector3.ZERO) as Vector3
	# 三种原点约定，差别在结构盒在 X/Z 上从哪里起算：
	#   bottom_center —— X/Z 居中于原点，底面 Y=0（墙 / 地砖 / 门墙 / 女儿墙 / 门扇）
	#   centered_slab —— X/Z 居中，板厚居中于 Y=0（层板类）
	#   bottom_corner —— 原点落在 L 的转角，结构盒只向 +X 与 -Z 伸出，底面 Y=0
	#                    （L 墙角）。DungeonRoom3D._spawn_room_corner() 就是按转角
	#                    摆位的，把它按居中解会让所有房间的角错位。
	var structural_bottom_y := 0.0
	var structural_origin_x := -declared_structural.x * 0.5
	var structural_origin_z := -declared_structural.z * 0.5
	var origin_recognized := true
	match origin_contract:
		"bottom_center":
			structural_bottom_y = 0.0
		"centered_slab":
			structural_bottom_y = -declared_structural.y * 0.5
		"bottom_corner":
			structural_origin_x = 0.0
			structural_origin_z = -declared_structural.z
		_:
			origin_recognized = false
			failures.append("%s 未识别的 origin_contract: %s" % [file_name, origin_contract])
	var structural_box := AABB(
		Vector3(
			structural_origin_x,
			structural_bottom_y,
			structural_origin_z
		),
		declared_structural
	)
	var contains := true
	if origin_recognized:
		contains = _aabb_contains(measured, structural_box, TOLERANCE_M)
		if not contains:
			failures.append(
				"%s 可视包络 %s 未包住结构盒 %s（origin_contract=%s）"
				% [
					file_name,
					_aabb_text(measured),
					_aabb_text(structural_box),
					origin_contract,
				]
			)
	print(
		"    origin_contract   = %s  结构盒=%s  包含=%s"
		% [
			origin_contract,
			_aabb_text(structural_box),
			("是" if contains else "否"),
		]
	)
	var dip := structural_box.position.y - measured.position.y
	if dip > TOLERANCE_M:
		print(
			"    [记录] 装饰件低于结构底面 %.4fm（属可视包络，装配仍按 prefab 根原点）" % dip
		)

	# 5. 朝向一致
	var forward_axis := str(root.get_meta("forward_axis", ""))
	if forward_axis != EXPECTED_FORWARD_AXIS:
		failures.append(
			"%s forward_axis=%s，塔楼 A 套要求 %s（跨套混用会整体反 180°）"
			% [file_name, forward_axis, EXPECTED_FORWARD_AXIS]
		)
	print("    forward_axis      = %s" % forward_axis)

	# 6. visual_only ⇒ 不内嵌碰撞
	var visual_only := bool(root.get_meta("visual_only", false))
	var embedded_bodies := root.find_children("*", "StaticBody3D", true, false)
	var embedded_shapes := root.find_children("*", "CollisionShape3D", true, false)
	print("    visual_only       = %s  内嵌StaticBody=%d CollisionShape=%d" % [
		str(visual_only), embedded_bodies.size(), embedded_shapes.size()
	])
	if visual_only and (not embedded_bodies.is_empty() or not embedded_shapes.is_empty()):
		failures.append(
			"%s 声明 visual_only 却内嵌碰撞（body=%d shape=%d），会与脚本代理重复阻挡"
			% [file_name, embedded_bodies.size(), embedded_shapes.size()]
		)

	# 7. preserve_authored_palette ⇒ 无材质覆盖
	var preserves := bool(root.get_meta("preserve_authored_palette", false))
	var overrides := _count_material_overrides(root)
	print("    preserve_palette  = %s  material_override 数=%d" % [str(preserves), overrides])
	if preserves and overrides > 0:
		failures.append(
			"%s 声明 preserve_authored_palette 却有 %d 处 material_override，美术会被盖掉"
			% [file_name, overrides]
		)

	# 8. 批渲染必须以单 Mesh 资源为载体
	var instantiation := str(root.get_meta("runtime_instantiation", ""))
	print("    装配方式          = %s" % instantiation)
	if instantiation not in VALID_INSTANTIATION:
		failures.append(
			"%s runtime_instantiation=%s 不在 %s 内"
			% [file_name, instantiation, str(VALID_INSTANTIATION)]
		)
	elif instantiation == "batched_multimesh" and not (resolved is MeshInstance3D):
		failures.append(
			"%s 声明 batched_multimesh 但视觉节点 %s 不是 MeshInstance3D，批渲染取不到单一 Mesh 资源"
			% [file_name, resolved_name]
		)

	root.free()


func _find_first_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return (root as MeshInstance3D).mesh
	for child in root.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


## 反查持有该 Mesh 资源的 MeshInstance3D 节点名，用于报告首网格漂移。
func _owner_mesh_instance_name(root: Node, mesh: Mesh) -> String:
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh == mesh:
			return String(mesh_instance.name)
	return ""


func _count_material_overrides(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D and (root as MeshInstance3D).material_override != null:
		count += 1
	if root is MultiMeshInstance3D and (root as MultiMeshInstance3D).material_override != null:
		count += 1
	for child in root.get_children():
		count += _count_material_overrides(child)
	return count


func _aabb_contains(outer: AABB, inner: AABB, tolerance: float) -> bool:
	var outer_end := outer.position + outer.size
	var inner_end := inner.position + inner.size
	return (
		outer.position.x <= inner.position.x + tolerance
		and outer.position.y <= inner.position.y + tolerance
		and outer.position.z <= inner.position.z + tolerance
		and outer_end.x >= inner_end.x - tolerance
		and outer_end.y >= inner_end.y - tolerance
		and outer_end.z >= inner_end.z - tolerance
	)


func _aabb_text(box: AABB) -> String:
	return "pos=%s size=%s" % [_vec(box.position), _vec(box.size)]


func _vec(value: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [value.x, value.y, value.z]
