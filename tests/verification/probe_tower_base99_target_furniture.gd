extends Node

const OUTPUT_PATH := "res://_scratch/probe_tower_base99_target_furniture.log"

func _ready() -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	await _settle()

	var lines: Array[String] = []
	lines.append("PROBE=tower_base99_target_furniture")
	lines.append("tower_global=%s" % _v3(tower.global_position))
	var rooms := tower.get("_room_by_id") as Dictionary
	var facility_room := rooms.get("facility") as DungeonRoom3D
	if facility_room == null:
		lines.append("ERROR=facility_room_missing")
		_write_and_quit(lines, 1)
		return

	tower.player.global_position = facility_room.to_global(Vector3(0.0, 5.05, 0.0))
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	lines.append("facility_room_path=%s" % str(facility_room.get_path()))
	lines.append("facility_room_global=%s" % _v3(facility_room.global_position))
	lines.append("player_global=%s" % _v3(tower.player.global_position))
	lines.append("current_room=%s" % str(tower.get("_current_room_id")))
	lines.append("authoritative_floor=%s" % str(tower.get("_authoritative_floor_index")))

	var facilities := tower.get("_facility_nodes") as Array
	lines.append("facility_count=%d" % facilities.size())
	for value in facilities:
		var facility := value as BaseFacility3D
		if facility == null:
			lines.append("FACILITY_INVALID=%s" % str(value))
			continue
		lines.append("FACILITY id=%s name=%s path=%s parent=%s global=%s rot_y=%.6f meta=%s" % [
			facility.facility_id,
			facility.name,
			str(facility.get_path()),
			facility.get_parent().name if facility.get_parent() != null else "<none>",
			_v3(facility.global_position),
			facility.global_rotation.y,
			_meta_text(facility),
		])
		_dump_tree(facility, lines, 0)

	lines.append("ALL_BASE_ART_MESHES")
	var art := facility_room.get_node_or_null("Art") as Node
	if art != null:
		lines.append("ART_PATH=%s" % str(art.get_path()))
		_dump_tree(art, lines, 0)
	else:
		lines.append("ART_MISSING")

	_write_and_quit(lines, 0)

func _dump_tree(node: Node, lines: Array[String], depth: int) -> void:
	if depth > 16:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var world_box := _world_mesh_aabb(mi)
			lines.append("MESH depth=%d name=%s path=%s parent=%s global=%s rot_y=%.6f size=%s min=%s max=%s mesh=%s meta=%s ancestors=%s" % [
				depth,
				mi.name,
				str(mi.get_path()),
				mi.get_parent().name if mi.get_parent() != null else "<none>",
				_v3(mi.global_position),
				mi.global_rotation.y,
				_v3(world_box.size),
				_v3(world_box.position),
				_v3(world_box.end),
				mi.mesh.get_class(),
				_meta_text(mi),
				_parent_chain(mi),
			])
	for child in node.get_children():
		_dump_tree(child, lines, depth + 1)

func _world_mesh_aabb(mi: MeshInstance3D) -> AABB:
	var local_box := mi.get_aabb()
	var world_box := AABB(mi.global_transform * local_box.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		world_box = world_box.expand(mi.global_transform * local_box.get_endpoint(i))
	return world_box

func _parent_chain(node: Node) -> String:
	var names: Array[String] = []
	var current := node
	while current != null and names.size() < 20:
		names.append(str(current.name))
		current = current.get_parent()
	names.reverse()
	return "/".join(names)

func _meta_text(node: Node) -> String:
	var values: Array[String] = []
	for key in node.get_meta_list():
		values.append("%s=%s" % [str(key), str(node.get_meta(key))])
	values.sort()
	return "{" + ",".join(values) + "}"

func _v3(value: Vector3) -> String:
	return "(%.5f,%.5f,%.5f)" % [value.x, value.y, value.z]

func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout

func _write_and_quit(lines: Array[String], exit_code: int) -> void:
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for line in lines:
		print(line)
	get_tree().quit(exit_code)
