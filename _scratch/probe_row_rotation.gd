extends Node
## 临时探针：逐房试 4 个候选朝向，跑封边判据；并打印两种几何打分：
##   all  = 清单全部实例（含地砖/陈设）与场景实例的最近邻匹配数（用来定朝向）
##   shell= 只算墙/L 角/门墙（结构件）

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SEED := 77001199
const GRID := 5.0
const SIDE_DIRECTIONS := {
	"north": Vector3(0, 0, -1),
	"south": Vector3(0, 0, 1),
	"west": Vector3(-1, 0, 0),
	"east": Vector3(1, 0, 0),
}
const SHELL_ROLES := ["solid_wall", "door_wall", "corner_l"]


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
	for room_key in tower._room_by_id.keys():
		var room := tower._room_by_id[room_key] as DungeonRoom3D
		if room == null:
			continue
		await _dump(space, room, str(room_key), door_positions)
	get_tree().quit(0)


func _dump(space, room: DungeonRoom3D, rid: String, door_positions: Array) -> void:
	var root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if root == null:
		root = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if root == null:
		print("%-11s 无静态场景根" % rid)
		return
	var original := rad_to_deg(root.rotation.y)
	var name_delta := room._static_layout_alignment_delta_deg(root)
	var all_scores := []
	var shell_scores := []
	var failures_by_delta := {}
	for delta in [0, 90, 180, 270]:
		root.rotation.y = deg_to_rad(float(delta))
		await get_tree().physics_frame
		await get_tree().physics_frame
		all_scores.append("%d:%.0f" % [delta, _geom_score(room, root, float(delta), false)])
		shell_scores.append("%d:%.0f" % [delta, _geom_score(room, root, float(delta), true)])
		var list: Array = _seal_failures(space, room, door_positions)
		failures_by_delta[delta] = list.size()
	root.rotation.y = deg_to_rad(original)
	await get_tree().physics_frame
	var parts := []
	for delta in [0, 90, 180, 270]:
		parts.append("%d→%d" % [delta, int(failures_by_delta[delta])])
	print("%-11s 名字=%4d all[%s] shell[%s] 缺墙[%s]" % [
		rid, int(name_delta), ",".join(all_scores), ",".join(shell_scores), ", ".join(parts),
	])


## 场景实例位置 p 按 Δ 转进房间帧，与清单位置 q 做最近邻匹配。
func _geom_score(room: DungeonRoom3D, root: Node3D, delta: float, shell_only: bool) -> float:
	var basis := Basis(Vector3.UP, deg_to_rad(delta))
	var scene_points: Array = []
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var c3 := child as Node3D
		if c3.scene_file_path.is_empty():
			continue
		var rotated := basis * c3.position
		scene_points.append(Vector2(rotated.x, rotated.z))
	var matched := 0
	for value in room.authored_layout_instances:
		var inst := value as Dictionary
		if shell_only and str(inst.get("slot_role", "")) not in SHELL_ROLES:
			continue
		var p := inst.get("position", Vector3.ZERO) as Vector3
		var wanted := Vector2(p.x, p.z)
		for scene_point in scene_points:
			if (scene_point as Vector2).distance_to(wanted) <= 0.6:
				matched += 1
				break
	return float(matched)


func _seal_failures(space, room: DungeonRoom3D, door_positions: Array) -> Array:
	var cells := {}
	for value in room.authored_layout_instances:
		var inst := value as Dictionary
		if str(inst.get("slot_role", "")) != "floor_tile":
			continue
		var p := inst.get("position", Vector3.ZERO) as Vector3
		cells[_cell_key(Vector2(p.x, p.z))] = Vector2(p.x, p.z)
	var out: Array = []
	if cells.is_empty():
		return out
	var face_half := GRID * 0.5
	var probe_length := GRID * 0.5 + 0.5
	for cell_value in cells.values():
		var local := cell_value as Vector2
		for side_value in SIDE_DIRECTIONS.keys():
			var side := str(side_value)
			var direction := SIDE_DIRECTIONS[side] as Vector3
			if cells.has(_cell_key(local + Vector2(direction.x, direction.z) * GRID)):
				continue
			var from: Vector3 = room.global_position + Vector3(local.x, 0.5, local.y)
			if not _ray(space, from, from + direction * probe_length).is_empty():
				continue
			var face_center: Vector3 = from + direction * face_half
			if _is_door_face(face_center, door_positions):
				continue
			out.append("%s(%.1f,%.1f)" % [side, local.x, local.y])
	return out


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
