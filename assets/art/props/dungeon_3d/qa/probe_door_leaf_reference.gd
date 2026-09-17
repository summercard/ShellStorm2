extends SceneTree
## 只读探针：对照基地99层正式带门墙 GLB —— 它的门扇是美术自带还是由 RoomDoor3D 提供？

const CANDIDATES := [
	"res://assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x12/env_base99_wall_door_5x12_visual_top3d.glb",
	"res://assets/art/environments/base_facility_3d/components/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d.glb",
]


func _initialize() -> void:
	for path in CANDIDATES:
		_dump(path)
	quit(0)


func _dump(path: String) -> void:
	print("================================================================================")
	print("### %s" % path)
	if not ResourceLoader.exists(path, "PackedScene"):
		print("    !! MISSING")
		return
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		print("    !! cannot load as PackedScene")
		return
	var root := packed.instantiate()
	print("    root: %s  (%s)" % [String(root.name), root.get_class()])
	_dump_tree(root, 1)
	root.free()


func _dump_tree(node: Node, depth: int) -> void:
	var pad := "    ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var aabb := mi.mesh.get_aabb()
			extra = "  mesh_aabb pos=%s size=%s surf=%d" % [
				str(aabb.position), str(aabb.size), mi.mesh.get_surface_count()
			]
		else:
			extra = "  mesh=<null>"
	print("%s%s (%s) xform=%s%s" % [
		pad, String(node.name), node.get_class(), str(node.transform), extra
	])
	for child in node.get_children():
		_dump_tree(child, depth + 1)
