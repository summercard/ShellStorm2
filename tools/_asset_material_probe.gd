extends SceneTree
## 查清：资产代入时材质从哪来。到底需不需要"赋予材质"。

const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

func _initialize() -> void:
	_check_prefab("manor_floor_wood")
	_check_prefab("manor_wall_standard")
	_check_prefab("manor_wall_door")
	_check_prefab("manor_sofa")
	_check_prefab("manor_wall_lamp")
	# 对比：01 用的墙
	_check_prefab_path("res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/l_corridor/wall_5m_a/wall_5m_a_root_top3d.tscn", "01 wall_5m_a")
	# 对比：程序化白盒 prefab（引擎自己铺的）
	_check_prefab_path("res://assets/art/props/dungeon_3d/prp_room_floor.tscn", "白盒 prp_room_floor")
	quit(0)

func _check_prefab(slug: String) -> void:
	_check_prefab_path("%s/%s/env_%s_root_top3d.tscn" % [MANOR, slug, slug], slug)

func _check_prefab_path(path: String, label: String) -> void:
	if not ResourceLoader.exists(path, "PackedScene"):
		print("MAT %-24s 场景不存在" % label)
		return
	var packed := load(path) as PackedScene
	var root := packed.instantiate()
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var surface_count := 0
	var with_material := 0
	var override_count := 0
	var tex_paths := {}
	for value in meshes:
		var mi := value as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.material_override != null:
			override_count += 1
		for i in mi.mesh.get_surface_count():
			surface_count += 1
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			with_material += 1
			if mat.albedo_texture != null:
				tex_paths[mat.albedo_texture.resource_path.get_file()] = true
	print("MAT %-24s meshes=%-2d surfaces=%-2d 自带材质=%-2d override=%-2d 贴图=%s"
		% [label, meshes.size(), surface_count, with_material, override_count,
			str(tex_paths.keys())])
	root.free()
