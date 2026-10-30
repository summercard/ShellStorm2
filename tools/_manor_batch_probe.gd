extends SceneTree
## 远征03 复古公馆组件批次（manor_*, v017）体检。
##
## 只读：逐个加载 runtime 包装场景，实测网格节点数、碰撞、AABB，
## 与包装里声明的 metadata/bounds_size_m 逐件对比。
## 退出码 0 = 全通过，1 = 有失败项。

const BASE := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var dirs: Array[String] = []
	var dir := DirAccess.open(BASE)
	if dir == null:
		printerr("MANOR_FAIL 打不开目录 ", BASE)
		quit(1)
		return
	for name in dir.get_directories():
		if name.begins_with("manor_"):
			dirs.append(name)
	dirs.sort()
	print("MANOR_BATCH dirs=%d" % dirs.size())

	var total_mesh := 0
	var total_collision := 0
	var by_family := {}
	for slug in dirs:
		var path := "%s/%s/env_%s_root_top3d.tscn" % [BASE, slug, slug]
		if not ResourceLoader.exists(path, "PackedScene"):
			_fail("%s 场景不存在 %s" % [slug, path])
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("%s 无法加载为 PackedScene" % slug)
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			_fail("%s 根节点不是 Node3D" % slug)
			continue
		root.transform = Transform3D.IDENTITY

		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		var shapes := root.find_children("*", "CollisionShape3D", true, false)
		total_mesh += meshes.size()
		total_collision += shapes.size()

		var box := AABB()
		var has_box := false
		for node in meshes:
			var mesh := (node as MeshInstance3D).mesh
			if mesh == null:
				continue
			var b: AABB = node.transform * mesh.get_aabb()
			box = box.merge(b) if has_box else b
			has_box = true

		var declared: Vector3 = root.get_meta("bounds_size_m", Vector3.ZERO)
		var family := str(root.get_meta("component_family", "?"))
		by_family[family] = int(by_family.get(family, 0)) + 1

		# ① 网格真的在
		_check(meshes.size() > 0, "%s 网格节点数为 0（GLB 没导入出网格）" % slug)
		# ② 声明尺寸非零
		_check(declared.x > 0.0 and declared.y > 0.0 and declared.z > 0.0,
			"%s 声明 bounds_size_m 非法 %s" % [slug, declared])
		# ③ 实测 vs 声明（容差 0.12m：包装是按 AABB 取整声明的）
		if has_box:
			var delta := Vector3(
				absf(box.size.x - declared.x),
				absf(box.size.y - declared.y),
				absf(box.size.z - declared.z))
			var worst := maxf(delta.x, maxf(delta.y, delta.z))
			_check(worst <= 0.12,
				"%s 声明 %s 与实测 %s 差 %.3fm" % [slug, _v(declared), _v(box.size), worst])
			# ④ 落地契约：origin = bottom_center ⇒ 底面应贴 y=0
			if str(root.get_meta("origin_contract", "")) == "bottom_center":
				_check(absf(box.position.y) <= 0.05,
					"%s bottom_center 契约不成立：底面 y=%.3f" % [slug, box.position.y])
			# ⑤ 结构件必须带碰撞，装饰件可以没有
			if CONTRACT.is_structure_prefab(path):
				_check(shapes.size() > 0, "%s 判为结构件却没有碰撞" % slug)
		else:
			_fail("%s 拿不到任何网格 AABB" % slug)

		root.free()

	# ⑥ 分类：结构件必须被判出来，装饰件必须不被剥
	var expect_struct := ["manor_wall_standard", "manor_wall_door", "manor_wall_window",
		"manor_floor_wood", "manor_floor_stone", "manor_floor_bath"]
	for slug in expect_struct:
		_check(CONTRACT.is_structure_prefab("%s/%s/env_%s_root_top3d.tscn" % [BASE, slug, slug]),
			"结构件 %s 没被判成结构（会被当装饰留在美术层）" % slug)
	for slug in dirs:
		if not expect_struct.has(slug):
			_check(not CONTRACT.is_structure_prefab("%s/%s/env_%s_root_top3d.tscn" % [BASE, slug, slug]),
				"装饰件 %s 被误判成结构（会被剥掉消失）" % slug)

	var fam_parts: Array[String] = []
	for key in by_family:
		fam_parts.append("%s=%d" % [key, by_family[key]])
	fam_parts.sort()
	print("MANOR_FAMILIES %s" % ", ".join(fam_parts))
	print("MANOR_TOTALS meshes=%d collision_shapes=%d" % [total_mesh, total_collision])
	if failures == 0:
		print("MANOR_OK checks=%d failures=0" % checks)
	else:
		print("MANOR_FAILED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MANOR_FAIL ", message)


func _fail(message: String) -> void:
	checks += 1
	failures += 1
	printerr("MANOR_FAIL ", message)
