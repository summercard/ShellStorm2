extends Node3D
## 诊断（只读）：证明「刷怪早于家具构建」⇒ 落点会落在**随后才出现**的家具里。
## 复刻真实顺序：壳体已建（SHELL_READY）→ 计算首波落点 → 才建家具（ACTIVE 时）。
## 对每个落点做实体重叠查询（掩码 1，圆柱近似怪物占地），列出撞到的节点名。
## 对照组：建好家具后再取同一批 index 的落点，看有多少仍然撞家具。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const PROBE_COUNT := 8
## 召唤者最大占地半径 1.0225m，取 0.72 做「怪物实体是否与家具相交」的判据。
const BODY_RADIUS := 0.72
const BODY_HEIGHT := 1.80

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
	print("ORDER_PROBE_DONE")
	get_tree().quit(0)


func _inspect(room: DungeonRoom3D) -> void:
	# ① 只建壳体（= 开门后邻房的真实状态），**不建家具**。
	room.ensure_shell_built()
	await _settle(2)
	var pre_points := _points(room)
	var pre_hits: Array[String] = []
	for point in pre_points:
		pre_hits.append(_overlap_label(point))
	# ② 再建家具（= 玩家进房、state 升到 ACTIVE 时发生的事）。
	room.ensure_detail_built()
	await _settle(2)
	var post_points := _points(room)
	var post_hits: Array[String] = []
	for point in post_points:
		post_hits.append(_overlap_label(point))
	var pre_bad := 0
	for label in pre_hits:
		if label != "clear":
			pre_bad += 1
	var post_bad := 0
	for label in post_hits:
		if label != "clear":
			post_bad += 1
	print("ORDER_ROOM %s type=%s 先建壳体后落点=%d 其中撞家具=%d ｜ 建完家具再落点撞家具=%d" % [
		room.room_id, room.room_type, pre_points.size(), pre_bad, post_bad,
	])
	for index in pre_points.size():
		if pre_hits[index] != "clear":
			print("ORDER_PRE_HIT room=%s idx=%d node=%s local=(%.2f,%.2f)" % [
				room.room_id, index, pre_hits[index],
				room.to_local(pre_points[index]).x, room.to_local(pre_points[index]).z,
			])


## 从 index 0 起连续取 PROBE_COUNT 个落点；index 0 会重建障碍缓存。
func _points(room: DungeonRoom3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index in PROBE_COUNT:
		out.append(room.spawn_point_for_index(index))
	return out


## 以怪物占地圆柱做实体重叠查询；返回 "clear" 或命中的节点名（去重前 3 个）。
func _overlap_label(point: Vector3) -> String:
	if not point.is_finite():
		return "NON_FINITE"
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3(0.0, BODY_HEIGHT * 0.5, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var names: Array[String] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var collider := hit.get("collider") as Node
		if collider == null:
			continue
		var name := str(collider.name)
		if name not in names:
			names.append(name)
		if names.size() >= 3:
			break
	if names.is_empty():
		return "clear"
	return ",".join(names)


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
