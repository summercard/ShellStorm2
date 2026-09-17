extends Node
## 只读探查：塔楼 STAIR_LOBBY（安全房）边界/门/门墙在运行时的真实全局坐标。
## 用于对比 HEAD（旧塔楼拼装）与 v007 接入后的几何差异，不做任何断言。

const ROOM_SCENE := "res://scenes/TowerDescent3D.tscn"


func _ready() -> void:
	var scene := load(ROOM_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(95)

	var generation := tower.get_generation_snapshot()
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var records := generation.get("records", []) as Array
	print("=== RECORDS ===")
	for record_value in records:
		var record := record_value as Dictionary
		var id := str(record.get("id", ""))
		var pos := record.get("position", Vector3.ZERO) as Vector3
		var dims := record.get("custom_dimensions", Vector2.ZERO) as Vector2
		var role := str(record.get("map_role", record.get("role", "")))
		var logic := str(record.get("logic", record.get("logic_id", "")))
		print("  %-18s pos=%s dims=%s role=%s logic=%s" % [id, str(pos), str(dims), role, logic])

	for record_value in records:
		var record := record_value as Dictionary
		var id := str(record.get("id", ""))
		var room := room_by_id.get(id) as DungeonRoom3D
		if room == null:
			continue
		if room.room_type != "STAIR_LOBBY":
			continue
		room.set_stream_state(1)
		await get_tree().process_frame
		print("=== STAIR_LOBBY %s ===" % id)
		print("  room pos=%s dims=%s doors=%s rot_y=%.3f" % [
			str(room.global_position), str(room.get_dimensions()), str(room.doors), room.rotation.y
		])
		print("  meta art_version=%s steps=%s wall=%s tile=%s pkg=%s" % [
			str(room.get_meta("safe_room_art_version", "<none>")),
			str(room.get_meta("safe_room_orientation_steps", "<none>")),
			str(room.get_meta("safe_room_wall_module_count", "<none>")),
			str(room.get_meta("safe_room_floor_tile_count", "<none>")),
			str(room.get_meta("safe_room_package_count", "<none>")),
		])
		for side in room.doors:
			var door := room.get_door_node(side)
			print("  door[%s] global=%s" % [
				side, str(door.global_position) if door != null else "<null>"
			])
		print("  --- wall/door-wall modules with meta asset_id ---")
		for value in room.find_children("*", "Node3D", true, false):
			var node := value as Node3D
			if node == null:
				continue
			var aid := str(node.get_meta("asset_id", ""))
			if aid.is_empty():
				continue
			var fw := node.find_children("*", "MeshInstance3D", true, false)
			var ab := AABB()
			var has_mesh := false
			for mv in fw:
				var mi := mv as MeshInstance3D
				if mi != null and mi.mesh != null:
					var a := mi.get_aabb()
					var t := mi.global_transform
					var pts: Array[Vector3] = []
					for ix in [a.position.x, a.position.x + a.size.x]:
						for iy in [a.position.y, a.position.y + a.size.y]:
							for iz in [a.position.z, a.position.z + a.size.z]:
								pts.append(t * Vector3(ix, iy, iz))
					for k in range(pts.size()):
						if not has_mesh:
							ab = AABB(pts[k], Vector3.ZERO)
						ab = ab.expand(pts[k])
					has_mesh = true
			print("    %-40s aid=%-34s dir=%-6s gpos=%s aabb_size=%s" % [
				String(node.name),
				aid,
				str(node.get_meta("tower_wall_direction", "")),
				str(node.global_position),
				str(ab.size) if has_mesh else "<no mesh>",
			])

	print("=== CONNECTORS touching STAIR_LOBBY ===")
	var corridor_by_edge := tower.get("_corridor_by_edge") as Dictionary
	for connector_value in corridor_by_edge.values():
		var connector := connector_value as Node3D
		if connector == null:
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var to_id := str(connector.get_meta("to_room_id", ""))
		var from_room := room_by_id.get(from_id) as DungeonRoom3D
		var to_room := room_by_id.get(to_id) as DungeonRoom3D
		var touches := (
			(from_room != null and from_room.room_type == "STAIR_LOBBY")
			or (to_room != null and to_room.room_type == "STAIR_LOBBY")
		)
		if not touches:
			continue
		print("  connector %s -> %s vertical=%s" % [
			from_id, to_id, str(connector.get_meta("is_vertical_connector", false))
		])
		print("    start_door=%s end_door=%s" % [
			str(connector.get_meta("start_door_position", "<none>")),
			str(connector.get_meta("end_door_position", "<none>")),
		])
		for value in connector.find_children("*", "Node3D", true, false):
			var node := value as Node3D
			var aid := str(node.get_meta("asset_id", ""))
			if aid.is_empty():
				continue
			if "WALL" not in aid:
				continue
			print("      %-44s aid=%-34s dir=%-6s gpos=%s" % [
				String(node.name), aid,
				str(node.get_meta("tower_wall_direction", "")),
				str(node.global_position),
			])
	print("STAIR_LOBBY_GEOMETRY_DUMP_DONE")
	get_tree().quit(0)
