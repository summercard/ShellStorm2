extends Node
## 临时探针（真值口径）：把 room_01 依次摆到 4 个整房朝向（随机拼接下每局就是其中之一），
## 每次用**游戏自己的** `_find_lower_camera_wall_distance()` 逐地砖格心实测，
## 再与「几何上是否真有沿世界 X 的墙挡在 +Z」比对。
##
##   镜头穿墙 = 几何有墙，游戏探针却报 -1（镜头不会收/抬，直接从墙里穿过去）
##   虚探     = 几何无墙，游戏探针却报有（镜头无故抬高收近）

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SEED := 77001199
const PROBE_LENGTH := 7.47
const PROBE_HEIGHT := 1.09
const MAX_HITS := 8
const ROTATIONS := [0.0, 90.0, 180.0, 270.0]


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate()
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await get_tree().process_frame
	for _i in range(4):
		await get_tree().physics_frame
	var room := tower._room_by_id.get("room_01") as DungeonRoom3D
	var root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if root == null:
		print("room_01 无静态场景根")
		get_tree().quit(0)
		return
	var original := root.rotation.y
	for rotation in ROTATIONS:
		root.rotation.y = deg_to_rad(rotation)
		room._restore_static_layout_camera_wall_contract(root)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_scan(tower, room, int(rotation))
	root.rotation.y = original
	room._restore_static_layout_camera_wall_contract(root)
	get_tree().quit(0)


func _scan(tower, room: DungeonRoom3D, rotation: int) -> void:
	var space := room.get_world_3d().direct_space_state as PhysicsDirectSpaceState3D
	var cells: Array = []
	for value in room.authored_layout_instances:
		var inst := value as Dictionary
		if str(inst.get("slot_role", "")) != "floor_tile":
			continue
		var p := inst.get("position", Vector3.ZERO) as Vector3
		cells.append(Vector2(p.x, p.z))
	if cells.is_empty():
		print("--- rot=%d 无地砖" % rotation)
		return
	cells.sort_custom(func(a, b): return (a as Vector2).y < (b as Vector2).y)
	var player = tower.player
	var original: Vector3 = player.global_position
	var through := 0
	var phantom := 0
	var rows: Array = []
	for cell_value in cells:
		var local := cell_value as Vector2
		player.global_position = room.global_position + Vector3(local.x, 0.05, local.y)
		var detected := float(tower._find_lower_camera_wall_distance())
		var expected := _expected_distance(space, room, local, player)
		if detected < 0.0 and expected >= 0.0:
			through += 1
			if rows.size() < 6:
				rows.append("穿镜(%.1f,%.1f) 期望%.2f" % [local.x, local.y, expected])
		elif detected >= 0.0 and expected < 0.0:
			phantom += 1
			if rows.size() < 6:
				rows.append("虚探(%.1f,%.1f) 实测%.2f" % [local.x, local.y, detected])
	player.global_position = original
	print("--- rot=%-3d 格点=%-3d 镜头穿墙=%-3d 虚探=%-3d  %s" % [
		rotation, cells.size(), through, phantom, " | ".join(rows),
	])


## 几何期望：沿 +Z 找到第一面「沿世界 X 延伸」的墙，返回其平面 Z 距离；没有则 -1。
func _expected_distance(
	space: PhysicsDirectSpaceState3D, room: DungeonRoom3D, local: Vector2, player
) -> float:
	var from: Vector3 = room.global_position + Vector3(local.x, PROBE_HEIGHT, local.y)
	var to: Vector3 = from + Vector3(0, 0, 1) * PROBE_LENGTH
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())
	var ray_from := from
	for _hit_index in range(MAX_HITS):
		# 掩码与引擎一致：1 | COLLISION_LAYER_CAMERA_ONLY（16）—— 镜头专用代理层
		# 也在探针的查询范围内，只用 1 会漏掉 CameraOnlyDoorWall 那类代理。
		var query := PhysicsRayQueryParameters3D.create(
			ray_from, to, 1 | GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY, excluded
		)
		query.collide_with_areas = false
		query.hit_from_inside = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return -1.0
		var collider := hit.get("collider") as Node
		var hit_position := hit.get("position", ray_from) as Vector3
		var piece := _wall_piece_of(collider)
		if piece != null and _runs_along_world_x(piece):
			var offset := hit_position - room.global_position
			offset.y = 0.0
			return maxf(0.0, offset.z - local.y)
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		var direction := ray_from.direction_to(to)
		if direction.is_zero_approx():
			return -1.0
		ray_from = hit_position + direction * 0.03
	return -1.0


func _wall_piece_of(collider: Node) -> Node3D:
	var node := collider
	while node != null:
		if node is Node3D and node.has_meta("tower_wall_direction"):
			return node as Node3D
		node = node.get_parent()
	return null


## 墙件长轴是否沿**世界 X**：取碰撞盒世界包围盒较长的一边。
func _runs_along_world_x(piece: Node3D) -> bool:
	var bounds := AABB()
	var has_bounds := false
	for value in piece.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		var box := collision.shape as BoxShape3D
		if box == null:
			continue
		var shape_basis := collision.global_transform.basis
		var half := box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var point: Vector3 = (
						collision.global_transform.origin
						+ shape_basis * (Vector3(sx, sy, sz) * half)
					)
					if not has_bounds:
						bounds = AABB(point, Vector3.ZERO)
						has_bounds = true
					else:
						bounds = bounds.expand(point)
	if not has_bounds:
		return false
	return bounds.size.x >= bounds.size.z
