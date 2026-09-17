extends SceneTree
## 只读校验：替换后的 4 个塔楼模块 Prefab 是否结构正确。

const TARGETS := [
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn",
]

var failures: Array[String] = []


func _initialize() -> void:
	for path in TARGETS:
		_dump(path)
	print("================================================================================")
	if failures.is_empty():
		print("PREFAB_PROBE_OK")
	else:
		print("PREFAB_PROBE_FAILED count=%d" % failures.size())
		for f in failures:
			print("  - %s" % f)
	quit(0 if failures.is_empty() else 1)


func _dump(path: String) -> void:
	print("================================================================================")
	print("### %s" % path)
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		failures.append("cannot load: %s" % path)
		return
	var root := packed.instantiate()
	print("    root: %s (%s)" % [String(root.name), root.get_class()])
	for key in [
		"asset_id", "asset_version", "preserve_authored_palette",
		"visual_only", "collision_owner", "origin_contract",
	]:
		print("    meta %-26s = %s" % [key, str(root.get_meta(key, "<未声明>"))])
	var first := _find_first_mesh(root)
	if first == null:
		failures.append("_find_first_mesh -> null: %s" % path)
		print("    _find_first_mesh -> null")
	else:
		var a := first.get_aabb()
		print("    _find_first_mesh aabb pos=%s size=%s surfaces=%d" % [
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
			extra = "  aabb pos=%s size=%s surf=%d visible=%s" % [
				str(a.position), str(a.size), mi.mesh.get_surface_count(), str(mi.visible)
			]
		else:
			extra = "  mesh=<null>"
	elif node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is BoxShape3D:
			extra = "  box=%s" % str((cs.shape as BoxShape3D).size)
	print("%s%s (%s)%s" % [pad, String(node.name), node.get_class(), extra])
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
