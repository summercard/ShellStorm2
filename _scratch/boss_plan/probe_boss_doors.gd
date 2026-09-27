extends Node
## 诊断：Boss 房（v008）门位车道、门扇与墙件落位现场数据。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199


func _ready() -> void:
	var level := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	level.test_mode = true
	level.run_seed_override = RUN_SEED
	add_child(level)
	await _frames(12)
	var room := _find_room("boss")
	if room == null:
		print("!! 未找到 boss")
		get_tree().quit(1)
		return
	print("---- boss 尺寸=%s doors=%s" % [str(room.get_dimensions()), str(room.doors)])
	for side in ["north", "south", "east", "west"]:
		print(
			"  车道偏移 %-6s = %.3f"
			% [side, float(room.get_meta("tower_wall_door_offset_%s" % side, 0.0))]
		)
	var door_nodes := room.get("_door_nodes") as Dictionary
	for key in door_nodes:
		var door := door_nodes[key] as RoomDoor3D
		if door == null:
			continue
		print(
			"  门 %-6s 局部=(%.2f, %.2f, %.2f) rot=%6.1f°"
			% [str(key), door.position.x, door.position.y, door.position.z, rad_to_deg(door.rotation.y)]
		)
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	print("art_root children=%d" % (art_root.get_child_count() if art_root else -1))
	if art_root != null:
		# 门位净空盒逐件归因
		var to_art := art_root.global_transform.affine_inverse()
		for key in door_nodes:
			var door := door_nodes[key] as RoomDoor3D
			if door == null:
				continue
			var direction := str(key)
			var lane := to_art * door.global_position
			print("  == %s 门位 lane=(%.2f, %.2f, %.2f)" % [direction, lane.x, lane.y, lane.z])
			for child in art_root.get_children():
				var module := child as Node3D
				if module == null:
					continue
				var blocked := _count_in_box(module, to_art, direction, lane)
				if blocked > 0:
					print(
						"     命中 %-34s role=%-18s pos=(%7.2f,%6.2f,%7.2f) verts=%d"
						% [
							str(module.get_meta("authored_component_id", "")).replace("ENV-EXPEDITION-L01-BOSS-", ""),
							str(module.get_meta("authored_slot_role", "")),
							module.position.x,
							module.position.y,
							module.position.z,
							blocked,
						]
					)
		for child in art_root.get_children():
			var module := child as Node3D
			if module == null:
				continue
			var role := str(module.get_meta("authored_slot_role", ""))
			var dir := str(module.get_meta("tower_wall_direction", ""))
			if role not in ["solid_wall", "door_wall"]:
				continue
			print(
				"    %-34s role=%-10s dir=%-5s promoted=%-5s pos=(%7.2f,%6.2f,%7.2f)"
				% [
					str(module.get_meta("authored_component_id", "")).replace("ENV-EXPEDITION-L01-BOSS-", ""),
					role,
					dir,
					str(bool(module.get_meta("authored_door_wall_promoted", false))),
					module.position.x,
					module.position.y,
					module.position.z,
				]
			)
	print("PROBE_BOSS_DOOR_DONE")
	get_tree().quit(0)


func _count_in_box(module: Node3D, to_art: Transform3D, direction: String, lane: Vector3) -> int:
	var blocked := 0
	var meshes: Array[Node] = []
	if module is MeshInstance3D:
		meshes.append(module)
	meshes.append_array(module.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var xform := to_art * mesh_instance.global_transform
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for vertex in vertices:
				var local := xform * vertex
				if local.y < 0.15 or local.y > 2.35:
					continue
				if direction in ["north", "south"]:
					if absf(local.x - lane.x) <= 1.05 and absf(local.z - lane.z) <= 0.6:
						blocked += 1
				elif absf(local.z - lane.z) <= 1.05 and absf(local.x - lane.x) <= 0.6:
					blocked += 1
	return blocked


func _find_room(room_id: String) -> DungeonRoom3D:
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_room_id == room_id:
			return room
	return null


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
