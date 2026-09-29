extends Node
## 临时探针：定位「格面无碰撞体且不是门洞」的那几面墙到底是什么状态。
## 口径与 verify_expedition_level01_flow 的轮廓感知判据完全一致，额外打印：
##   ① 该格面的世界坐标、射线结果
##   ② 静态场景里离该面 4m 内的实例（名字 / 来源 prefab / 世界坐标 / 有无 StaticBody3D）
##   ③ 本局清单 `authored_layout_instances` 里离该面 4m 内的记录（slot_role / 局部坐标）
##   ④ 该面是否落在门洞（门世界坐标 0.75m 内）

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SEED := 77001199
const GRID := 5.0
const SIDE_DIRECTIONS := {
	"north": Vector3(0, 0, -1),
	"south": Vector3(0, 0, 1),
	"west": Vector3(-1, 0, 0),
	"east": Vector3(1, 0, 0),
}


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate()
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := tower.get_viewport().world_3d.direct_space_state
	var door_positions := _collect_doors(tower)
	var room_ids := ["room_03", "room_06", "room_07", "room_09"]
	for rid in room_ids:
		var room = tower._room_by_id.get(rid)
		if room == null:
			print("!! 无 %s" % rid)
			continue
		_dump_room(space, room, rid, door_positions)
	get_tree().quit(0)


func _collect_doors(tower) -> Array:
	var out: Array = []
	for value in tower._room_by_id.values():
		var room = value
		if room == null:
			continue
		for side in room.doors:
			var key := "room_door_world_%s" % str(side)
			if room.has_meta(key):
				out.append(room.get_meta(key))
	return out


func _cell_key(local: Vector2) -> String:
	return "%d|%d" % [roundi(local.x * 10.0), roundi(local.y * 10.0)]


func _dump_room(space, room, rid: String, door_positions: Array) -> void:
	var cells := {}
	for value in room.authored_layout_instances:
		var inst := value as Dictionary
		if str(inst.get("slot_role", "")) != "floor_tile":
			continue
		var p := inst.get("position", Vector3.ZERO) as Vector3
		cells[_cell_key(Vector2(p.x, p.z))] = Vector2(p.x, p.z)
	print("")
	print("===== %s dims=%s center_world=%s cells=%d" % [
		rid, str(room.get_dimensions()), str(room.global_position), cells.size(),
	])
	var static_root: Node3D = room.get_node_or_null("AuthoredLayoutArtRoot")
	print("     静态场景根=%s rot_y=%.1f°" % [
		"有" if static_root != null else "无",
		rad_to_deg(static_root.rotation.y) if static_root != null else 0.0,
	])
	var face_half := GRID * 0.5
	var probe_length := GRID * 0.5 + 0.5
	for cell_value in cells.values():
		var local := cell_value as Vector2
		for side_value in SIDE_DIRECTIONS.keys():
			var side := str(side_value)
			var direction := SIDE_DIRECTIONS[side] as Vector3
			var neighbour := local + Vector2(direction.x, direction.z) * GRID
			if cells.has(_cell_key(neighbour)):
				continue
			var from := room.global_position + Vector3(local.x, 0.5, local.y)
			var hit := _ray(space, from, from + direction * probe_length)
			var face_center := from + direction * face_half
			var is_door := _is_door_face(face_center, door_positions)
			if not hit.is_empty() or is_door:
				continue
			print("  -- 缺口 %s 侧 格心(%.1f,%.1f) 面心world=%s" % [
				side, local.x, local.y, str(face_center),
			])
			_report_near_static(static_root, face_center)
			_report_near_instances(room, local, side, face_center)


func _report_near_static(static_root: Node3D, face_center: Vector3) -> void:
	if static_root == null:
		print("     静态场景：无根节点")
		return
	var found := 0
	for child in static_root.get_children():
		if not (child is Node3D):
			continue
		var c3 := child as Node3D
		var flat := Vector2(c3.global_position.x - face_center.x, c3.global_position.z - face_center.z)
		if flat.length() > 4.0:
			continue
		found += 1
		print("     邻近实例 %-52s src=%-28s global=(%.2f,%.2f) 碰撞体=%d" % [
			str(c3.name), c3.scene_file_path.get_file(), c3.global_position.x, c3.global_position.z,
			_count_bodies(c3),
		])
	if found == 0:
		print("     静态场景：4m 内没有任何实例（= 这段墙压根没摆东西）")


func _count_bodies(node: Node) -> int:
	var count := 0
	for body in node.find_children("*", "StaticBody3D", true, false):
		count += 1
	return count


func _report_near_instances(room, local: Vector2, side: String, face_center: Vector3) -> void:
	var local_face := Vector2(local.x, local.y) + Vector2(
		(SIDE_DIRECTIONS[side] as Vector3).x, (SIDE_DIRECTIONS[side] as Vector3).z
	) * (GRID * 0.5)
	var rows: Array = []
	for value in room.authored_layout_instances:
		var inst := value as Dictionary
		var p := inst.get("position", Vector3.ZERO) as Vector3
		var flat := Vector2(p.x, p.z)
		if flat.distance_to(local_face) > 4.0:
			continue
		rows.append("        %-50s role=%-12s local=(%.2f,%.2f) rot=%.0f" % [
			str(inst.get("name", "")), str(inst.get("slot_role", "")),
			p.x, p.z, float(inst.get("rotation_y_deg", 0.0)),
		])
	print("     清单 4m 内 %d 条：" % rows.size())
	for row in rows:
		print(row)


func _is_door_face(face_center: Vector3, door_positions: Array) -> bool:
	var flat := Vector2(face_center.x, face_center.z)
	for value in door_positions:
		var door := value as Vector3
		if flat.distance_to(Vector2(door.x, door.z)) <= 0.75:
			return true
	return false


func _ray(space, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)
