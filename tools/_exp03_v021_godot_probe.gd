extends Node
const SLUGS := ["manor_rug_lounge", "manor_reception_desk", "manor_rug_runner", "manor_rug_bedroom", "manor_flower_arrangement"]
const LIMITS := {"manor_rug_lounge":1999, "manor_reception_desk":5385, "manor_rug_runner":2808, "manor_rug_bedroom":2729, "manor_flower_arrangement":2302}

func _ready() -> void:
	var failed := 0
	for slug in SLUGS:
		var path := "res://assets/art/environments/tower_zones/expedition/runtime/common_components/%s/env_%s_root_top3d.tscn" % [slug, slug]
		var packed := load(path) as PackedScene
		if packed == null:
			print("FAIL %s prefab_load" % slug); failed += 1; continue
		var root := packed.instantiate() as Node3D
		add_child(root)
		await get_tree().process_frame
		var tris := 0
		var meshes := 0
		var mats := {}
		var visible := true
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null: continue
			meshes += 1
			for s in mesh_node.mesh.get_surface_count():
				var arrays := mesh_node.mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				var material := mesh_node.mesh.surface_get_material(s)
				if material != null: mats[str(material.resource_name)] = true
			if not mesh_node.is_visible_in_tree(): visible = false
		var box := _world_aabb(root)
		var ok := tris <= int(LIMITS[slug]) and meshes > 0 and visible and not mats.is_empty()
		print("GODOT %s tris=%d limit=%d meshes=%d mats=%d visible=%s size=%s %s" % [slug, tris, int(LIMITS[slug]), meshes, mats.size(), str(visible), str(box.size), "OK" if ok else "FAIL"])
		if not ok: failed += 1
		root.queue_free()
	await get_tree().process_frame
	print("EXP03_V021_GODOT_OK=%s failed=%d" % [str(failed == 0), failed])
	get_tree().quit(0 if failed == 0 else 1)

func _world_aabb(root: Node3D) -> AABB:
	var first := true
	var box := AABB()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: continue
		var world := mesh_node.global_transform * mesh_node.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box
