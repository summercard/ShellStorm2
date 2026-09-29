extends Node
## 临时探针：换 N 个种子，逐房跑「轮廓感知封边」判据，统计缺墙数 + 各房对齐到的朝向。
## 判据与 verify_expedition_level01_flow 同源（地砖格心朝四个格面打 3m 射线）。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const GRID := 5.0
const SEEDS := [1, 7, 42, 999, 12345, 77001199, 77001200, 31415926, 60606060, 88888888]
const SIDE_DIRECTIONS := {
	"north": Vector3(0, 0, -1),
	"south": Vector3(0, 0, 1),
	"west": Vector3(-1, 0, 0),
	"east": Vector3(1, 0, 0),
}


func _ready() -> void:
	var total_failures := 0
	var deltas := {}
	for seed_value in SEEDS:
		var scene := load(EXPEDITION_SCENE) as PackedScene
		var tower := scene.instantiate()
		tower.test_mode = true
		tower.run_seed_override = int(seed_value)
		add_child(tower)
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var space := tower.get_viewport().world_3d.direct_space_state
		var door_positions := _collect_doors(tower)
		var failures: Array[String] = []
		var line := []
		for room_key in tower._room_by_id.keys():
			var room := tower._room_by_id[room_key] as DungeonRoom3D
			if room == null:
				continue
			var root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
			if root == null:
				root = room.get_node_or_null("SafeRoomArtRoot") as Node3D
			var delta := 0.0
			if root != null:
				delta = rad_to_deg(root.rotation.y)
			deltas[str(room_key)] = float(deltas.get(str(room_key), 0.0)) + delta
			line.append("%s:%d°" % [str(room_key), int(round(delta))])
			var room_failures := _seal_failures(space, room, door_positions)
			for failure in room_failures:
				failures.append("%s %s" % [str(room_key), failure])
		total_failures += failures.size()
		print("seed %-9d 缺墙 %2d %s" % [seed_value, failures.size(), str(failures)])
		print("             朝向 %s" % " ".join(line))
		tower.queue_free()
		await get_tree().process_frame
	print("===== 合计缺墙 %d 条（%d 个种子）" % [total_failures, SEEDS.size()])
	# 每房朝向的分布：全 0 说明对齐恒等（随机没生效），有多种说明朝向随种子变。
	var summary := []
	for key in deltas.keys():
		summary.append("%s 平均%.0f°" % [str(key), float(deltas[key]) / float(SEEDS.size())])
	print("朝向均值 %s" % str(summary))
	get_tree().quit(0)


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
