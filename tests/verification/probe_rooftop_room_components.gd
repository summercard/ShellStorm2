extends Node
## 临时探针：把 11 个新导入的天台房间墙 / 门 / 房顶 GLB 的节点树、包络、表面与色盘绑定全部打出来。
## 只用于确定 prefab 的 visual_node_name / 表面数口径，跑完即删。

const GLBS: Array = [
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_wall_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_window_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_doorwall_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_wall_ivy_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_window_ivy_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_doorwall_ivy_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_door_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_room_door_leaf_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_roof_full_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_roof_edge_top3d.glb",
	"res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_roof_corner_top3d.glb",
]


func _ready() -> void:
	var loaded := 0
	for path in GLBS:
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		print("\n=== %s ===" % path.get_file())
		if packed == null:
			print("  !! LOAD FAILED")
			continue
		loaded += 1
		var instance := packed.instantiate()
		add_child(instance)
		var union := _union_bounds(instance)
		print("  ROOT=%s class=%s children=%d" % [
			instance.name, instance.get_class(), instance.get_child_count()
		])
		print("  UNION min=%s size=%s" % [str(union.position), str(union.size)])
		_dump(instance, "    ")
		remove_child(instance)
		instance.free()
	print("\nDUMP_OK loaded=%d/%d" % [loaded, GLBS.size()])
	get_tree().quit(0)


func _union_bounds(root: Node) -> AABB:
	var acc := AABB()
	var has := false
	for node in _all_geometry(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box: AABB = _xform(root, mesh_instance) * mesh_instance.mesh.get_aabb()
		acc = box if not has else acc.merge(box)
		has = true
	return acc


func _all_geometry(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root)
	for child in root.get_children():
		out.append_array(_all_geometry(child))
	return out


func _xform(root: Node, node: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var cursor := node
	while cursor != null and cursor != root:
		var as_3d := cursor as Node3D
		if as_3d == null:
			break
		chain.append(as_3d)
		cursor = cursor.get_parent()
	var xform := Transform3D.IDENTITY
	for index in range(chain.size() - 1, -1, -1):
		xform = xform * chain[index].transform
	return xform


func _dump(node: Node, indent: String) -> void:
	var line := "%s%s (%s)" % [indent, node.name, node.get_class()]
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null:
		var mesh := mesh_instance.mesh
		if mesh == null:
			print(line + " mesh=null")
		else:
			print(line + " surfaces=%d aabb_min=%s aabb_size=%s" % [
				mesh.get_surface_count(),
				str(mesh.get_aabb().position),
				str(mesh.get_aabb().size),
			])
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material == null:
					print("%s   surface=%d mat=null" % [indent, surface_index])
					continue
				var palette := "<no-texture>"
				if material.albedo_texture != null:
					palette = material.albedo_texture.resource_path
				print("%s   surface=%d mat=%s albedo=%s" % [
					indent, surface_index, str(material.resource_name), palette
				])
	else:
		print(line)
	for child in node.get_children():
		_dump(child, indent + "  ")
