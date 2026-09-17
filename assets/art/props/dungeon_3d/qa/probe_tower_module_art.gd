extends SceneTree
## 只读探针：列出塔楼 5m 模块「各候选版本」的真实结构，用于确定哪一版符合
## 当前运行时契约（视觉墙高 11.9m、底面中心原点、表面数/材质）。

const CANDIDATES := [
	# --- 实墙：判断 v001/v002/v003 哪个是 11.9m 高版本 ---
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v001.glb",
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v002.glb",
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v003.glb",
	# --- 带门墙 ---
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d_v001.glb",
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d_v002.glb",
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d_v003.glb",
	# --- 女儿墙（只有 v001） ---
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_parapet_5m_top3d_v001.glb",
	# --- 地砖 v001 / v002 ---
	"res://assets/art/environments/tower_descent_3d/components/env_tower_floor_tile_5m_top3d_v001.glb",
	"res://assets/art/environments/tower_descent_3d/components/floor_tile_5m/env_tower_floor_tile_5m_top3d_v002.glb",
	# --- 对照组：基地 12m 高正式墙（当前 FACILITY 已在用） ---
	"res://assets/art/environments/base_facility_3d/components/env_base99_wall_plain_5x12/env_base99_wall_plain_5x12_visual_top3d_v002.glb",
	# --- 现有占位 prefab ---
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m_v001.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m_v001.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m_v001.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m_v001.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m_v001.tscn",
]


func _initialize() -> void:
	for path in CANDIDATES:
		_dump(path)
	quit(0)


func _dump(path: String) -> void:
	print("================================================================================")
	print("### %s" % path)
	if not ResourceLoader.exists(path, "PackedScene"):
		print("    !! MISSING (ResourceLoader.exists == false)")
		return
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		print("    !! cannot load as PackedScene")
		return
	var root := packed.instantiate()
	print("    root: %s  (%s)" % [String(root.name), root.get_class()])
	var first := _find_first_mesh(root)
	if first == null:
		print("    _find_first_mesh -> null")
	else:
		var a := first.get_aabb()
		print("    _find_first_mesh -> %s  aabb pos=%s size=%s surfaces=%d" % [
			String(first.resource_name) if first.resource_name != "" else "(unnamed)",
			str(a.position), str(a.size), first.get_surface_count()
		])
	_dump_tree(root, 1)
	root.free()


func _dump_tree(node: Node, depth: int) -> void:
	var pad := "    ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var a := mi.mesh.get_aabb()
			extra = "  mesh_aabb pos=%s size=%s surf=%d" % [
				str(a.position), str(a.size), mi.mesh.get_surface_count()
			]
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				extra += "\n%s    surf[%d] material=%s" % [
					pad, s, mat.resource_name if mat != null else "<null>"
				]
		else:
			extra = "  mesh=<null>"
	elif node is CollisionShape3D:
		var cs := node as CollisionShape3D
		extra = "  shape=%s" % (cs.shape.get_class() if cs.shape != null else "<null>")
		if cs.shape is BoxShape3D:
			extra += " size=%s" % str((cs.shape as BoxShape3D).size)
	var meta_keys := node.get_meta_list()
	if not meta_keys.is_empty():
		var parts: Array[String] = []
		for k in meta_keys:
			parts.append("%s=%s" % [String(k), str(node.get_meta(k))])
		extra += "  meta{%s}" % ", ".join(parts)
	print("%s%s (%s) xform=%s%s" % [
		pad, String(node.name), node.get_class(), str(node.transform), extra
	])
	for child in node.get_children():
		_dump_tree(child, depth + 1)


func _find_first_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return (root as MeshInstance3D).mesh
	for child in root.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null
