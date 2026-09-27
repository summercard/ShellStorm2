extends Node3D
## 诊断（只读）：`_collect_spawn_blockers()` 到底找不找得到家具？
## 对比「只建壳体」与「建完家具」两种状态下：
##   · `_spawn_blockers` 的条目数与被收录的节点名
##   · `_spawn_available` 的可用点数
##   · 同一批 index 的落点是否发生位移（位移=家具确实参与了避让）
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const PROBE_COUNT := 8

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(12)
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		await _inspect(room)
	print("BLOCKER_PROBE_DONE")
	get_tree().quit(0)


func _inspect(room: DungeonRoom3D) -> void:
	room.ensure_shell_built()
	await _settle(2)
	room.spawn_point_for_index(0)
	var shell_blockers := room._spawn_blockers.size()
	var shell_avail := room._spawn_available.size()
	var shell_points := _points(room)
	var shell_names := _blocker_names(room)

	room.ensure_detail_built()
	await _settle(3)
	room.spawn_point_for_index(0)
	var detail_blockers := room._spawn_blockers.size()
	var detail_avail := room._spawn_available.size()
	var detail_points := _points(room)
	var detail_names := _blocker_names(room)

	var moved := 0
	for index in PROBE_COUNT:
		if shell_points[index].distance_to(detail_points[index]) > 0.001:
			moved += 1
	print("BLOCKER_ROOM %s type=%s ｜ 壳体态 blockers=%d avail=%d ｜ 家具态 blockers=%d avail=%d ｜ 落点位移数=%d/%d" % [
		room.room_id, room.room_type,
		shell_blockers, shell_avail, detail_blockers, detail_avail, moved, PROBE_COUNT,
	])
	print("BLOCKER_NAMES room=%s shell=%s detail=%s" % [
		room.room_id, str(shell_names), str(detail_names),
	])


func _blocker_names(room: DungeonRoom3D) -> Array[String]:
	var out: Array[String] = []
	var bounds_list := room._spawn_blockers
	var dimensions := room.get_dimensions()
	var room_bounds := AABB(
		Vector3(-dimensions.x * 0.5, 0.05, -dimensions.y * 0.5),
		Vector3(dimensions.x, 2.6, dimensions.y)
	).grow(room._spawn_clearance())
	var root: Node = room.get_parent() if room.get_parent() != null else room
	for value in root.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		var body := collision.get_parent() as StaticBody3D
		if body == null or (body.collision_layer & 1) == 0 or collision.disabled or collision.shape == null:
			continue
		var bounds: AABB = room.global_transform.affine_inverse() * collision.global_transform * collision.shape.get_debug_mesh().get_aabb()
		if bounds.end.y <= 0.05 or bounds.position.y >= 2.6 or not room_bounds.intersects(bounds):
			continue
		var name := str(body.name)
		if name not in out:
			out.append(name)
		if out.size() >= 8:
			break
	return out


func _points(room: DungeonRoom3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index in PROBE_COUNT:
		out.append(room.spawn_point_for_index(index))
	return out


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
