extends Node3D
## 可独立运行的落点专项；不改波次测试和公共 runner。
## APPDATA 必须在启动 Godot 前隔离，再 --headless --editor --import 后运行本场景。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEEDS := [700000, 707919, 715838, 20260925]
var failures: Array[String] = []
var checked_points := 0
var checked_rooms := 0
var bridge_poses: Dictionary = {}
var first_positions: Dictionary = {}
var changed_rooms := 0
var legacy_unsafe := 0
var tower: TowerDescent3D


func _ready() -> void:
	for run_seed in SEEDS:
		tower = SCENE.instantiate() as TowerDescent3D
		tower.test_mode = true
		tower.run_seed_override = run_seed
		add_child(tower)
		tower.process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().process_frame
		_check(tower._room_by_id.size() == 13, "实际远征不是13房 seed=%d" % run_seed)
		# 先把全部壳体建好，邻房后建也不得令先测房间漏掉共墙碰撞。
		for room_value in tower._room_by_id.values():
			(room_value as DungeonRoom3D).ensure_shell_built()
		for room_value in tower._room_by_id.values():
			var room := room_value as DungeonRoom3D
			room.ensure_shell_built()
			room.ensure_detail_built()
			# 同帧先查一次：家具碰撞不能依赖物理服务器下一帧同步。
			var same_frame := room.spawn_point_for_index(0)
			_check(same_frame.is_finite(), "%s 无有效落点" % room.room_id)
			await get_tree().physics_frame
			await get_tree().physics_frame
			_verify_room(room, run_seed)
			if room.room_id == "room_01":
				_verify_same_frame_blocker(room)
			if run_seed == SEEDS[0] and room.room_id == "room_05":
				_verify_real_batches(room)
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_verify_floor_contract()
	# 2026-09-26 起主路房型**钉死**（`pin_content_templates: true`）⇒ 桥房不再随种子换 0°/90° 姿态，
	# 跨种子只出**一种**固定姿态。原断言 `== 2` 属「房型每局重洗」时代，已随钉死失效；
	# 改判「至少覆盖一种桥房姿态」（钉死本就是把双姿态覆盖换成确定性，故不再要求 2 种）。
	_check(bridge_poses.size() >= 1, "没有覆盖任何桥房姿态: %s" % bridge_poses)
	_check(changed_rooms >= 10, "不同run seed未改变足够房间落点")
	_check(legacy_unsafe > 0, "旧四角旋转算法反向对照没有检出问题")
	print("SPAWN_SAFETY_SUMMARY rooms=%d points=%d bridge_poses=%s changed_rooms=%d legacy_unsafe=%d failures=%d" % [checked_rooms, checked_points, bridge_poses, changed_rooms, legacy_unsafe, failures.size()])
	for failure in failures:
		push_error(failure)
	print("EXPEDITION_SPAWN_SAFETY_OK" if failures.is_empty() else "EXPEDITION_SPAWN_SAFETY_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_floor_contract() -> void:
	var room := DungeonRoom3D.new()
	room.configure({"authored_layout_shell": true, "custom_dimensions": Vector2(15, 15), "authored_layout_instances": [
		{"slot_role": "floor_tile", "position": Vector3(0, -0.3, 0)},
		{"slot_role": "multi_level_component", "part": "pit_floor_tile", "position": Vector3(5, -12, 0)},
	]})
	add_child(room)
	var point := room.spawn_point_for_index(0)
	_check(point.is_finite() and absf(point.y) < 0.001, "原始floor_tile高度未按装配吸附，或少于四砖回退房心")
	_check(not room._spawn_floor_contains(Vector3(5, 0, 0), 1.15), "误用多层坑底砖")
	_check(not room._spawn_floor_contains(Vector3(2.0, 0, 0), 1.15), "缺少边缘半径余量")
	room.authored_layout_instances.clear()
	room._build_spawn_points()
	_check(room._spawn_candidates.is_empty() and not room._spawn_floor_contains(Vector3.ZERO, 1.15), "空授权地板回退包围盒")
	room.free()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _main_cells(room: DungeonRoom3D) -> Array[Vector3]:
	var cells: Array[Vector3] = []
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		if str(instance.get("slot_role", "")) == "floor_tile":
			var p: Vector3 = instance["position"]
			cells.append(Vector3(p.x, 0, p.z))
	return cells


## 独立于产品的面积并集判据：密集采样整个占地正方形，而非调用产品安全函数。
func _supported(room: DungeonRoom3D, local: Vector3, radius: float) -> bool:
	var cells := _main_cells(room)
	var half := room.get_dimensions() * 0.5
	for x in 9:
		for z in 9:
			var p := local + Vector3(lerpf(-radius, radius, x / 8.0), 0, lerpf(-radius, radius, z / 8.0))
			if absf(p.x) > half.x or absf(p.z) > half.y:
				return false
			if not room.authored_layout_shell:
				continue
			var found := false
			for cell in cells:
				if absf(p.x - cell.x) <= 2.50001 and absf(p.z - cell.z) <= 2.50001:
					found = true
					break
			if not found:
				return false
	return true


func _verify_room(room: DungeonRoom3D, run_seed: int) -> void:
	checked_rooms += 1
	var label := "seed=%d room=%s" % [run_seed, room.room_id]
	var radius := 2.2 if room.room_type == "BOSS" else 1.15
	var points: Array[Vector3] = []
	var edge_count := 0
	var min_distance := INF
	var count := 24 if room.room_id == "start" else 64
	var shape := CylinderShape3D.new()
	shape.radius = radius - 0.03
	shape.height = 2.5
	for index in count:
		var point := room.spawn_point_for_index(index)
		points.append(point)
		checked_points += 1
		if not point.is_finite():
			_check(false, "%s index=%d 非有限落点" % [label, index])
			continue
		var local := room.to_local(point)
		_check(absf(local.y) < 0.001, "%s 落点不在主通行层 %s" % [label, local])
		_check(_supported(room, local, radius), "%s index=%d 在房外/凹口/桥坑或无半径余量 %s" % [label, index, local])
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3(0, 1.30, 0))
		query.collision_mask = 1
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
			if hit["collider"] is StaticBody3D:
				_check(false, "%s index=%d 与实体碰撞 %s" % [label, index, (hit["collider"] as Node).get_path()])
		if index < 24:
			for other in range(index):
				min_distance = minf(min_distance, point.distance_to(points[other]))
		if index < 8 and not _supported(room, local, radius + 3.0):
			edge_count += 1
	# 特殊安全房不是实际刷怪房，家具密集，不强制其24只占地容量。
	if room.room_id != "start":
		_check(min_distance >= radius * 2.0, "%s 前24只间距不足 %.3f" % [label, min_distance])
		_check(edge_count >= 6, "%s 前8只未优先分散边缘 edge=%d" % [label, edge_count])
	for index in count:
		_check(room.spawn_point_for_index(index).is_equal_approx(points[index]), "%s 重复调用不确定 index=%d" % [label, index])
	if room.room_id != "start":
		for index in [64, 127, 1024]:
			_check(_supported(room, room.to_local(room.spawn_point_for_index(index)), radius), "%s 超大索引落到地板外" % label)
	var first_local := room.to_local(points[0])
	var old_seed := room.room_seed
	room.room_seed += 7919
	room._build_spawn_points()
	_check(not room.spawn_point_for_index(0).is_equal_approx(points[0]), "%s 同布局换seed无变化" % label)
	room.room_seed = old_seed
	room._build_spawn_points()
	for index in 8:
		_check(room.spawn_point_for_index(index).is_equal_approx(points[index]), "%s 重建候选后不确定" % label)
	if first_positions.has(room.room_id):
		if not first_local.is_equal_approx(first_positions[room.room_id]):
			changed_rooms += 1
	else:
		first_positions[room.room_id] = first_local
	var pit_count := 0
	var raw_heights: Dictionary = {}
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		if str(instance.get("slot_role", "")) == "floor_tile":
			var raw: Vector3 = instance["position"]
			raw_heights[raw.y] = true
		if str(instance.get("part", "")) == "pit_floor_tile":
			pit_count += 1
			var pit: Vector3 = instance["position"]
			_check(pit.y < -1.0, "%s 坑底标高错误" % label)
			# 坑底铺满36格，桥面正下方12格也有坑底装饰，不能误判这12格为悬空。
			if absf(pit.x) > 5.0 and absf(pit.z) > 5.0:
				_check(not _supported(room, Vector3(pit.x, 0, pit.z), 0.1), "%s 坑底被当作上层地板" % label)
	if pit_count > 0:
		bridge_poses[str(room.get_dimensions())] = true
		print("SPAWN_BRIDGE %s size=%s floor_slot_y=%s pit_tiles=%d" % [label, room.get_dimensions(), raw_heights, pit_count])
	_legacy_negative_control(room)
	print("SPAWN_ROOM %s points=%d first8_edge=%d min24=%.3f first=%s floor_slot_y=%s" % [label, count, edge_count, min_distance, first_local, raw_heights])


func _legacy_negative_control(room: DungeonRoom3D) -> void:
	var cells := _main_cells(room)
	if cells.is_empty():
		return
	var chosen: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var distances := [-1.0, -1.0, -1.0, -1.0]
	for cell in cells:
		var sector := clampi(int(floor((atan2(cell.z, cell.x) + PI) / TAU * 4.0)), 0, 3)
		if cell.length() > distances[sector]:
			chosen[sector] = cell
			distances[sector] = cell.length()
	for index in range(4, 24):
		var layer := index / 4
		var old := chosen[index % 4].rotated(Vector3.UP, 0.37 * layer) * maxf(0.12, 1.0 - 0.17 * layer)
		if not _supported(room, old, 1.15):
			legacy_unsafe += 1


func _verify_same_frame_blocker(room: DungeonRoom3D) -> void:
	var old := room.spawn_point_for_index(0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	collision.shape = box
	body.add_child(collision)
	room.add_child(body)
	body.global_position = old + Vector3(0, 1, 0)
	body.rotation.y = 0.37
	# 故意不 await：证明不是只依赖滞后一帧的物理射线。
	var moved := room.spawn_point_for_index(0)
	_check(moved.distance_to(old) > 3.5, "同帧旋转家具没有避让 %s" % room.room_id)
	body.free()
	_check(room.spawn_point_for_index(0).is_equal_approx(old), "移除家具后同seed未恢复 %s" % room.room_id)


func _verify_real_batches(room: DungeonRoom3D) -> void:
	var batch: Array[Dictionary] = []
	for count in [8, 24]:
		batch.clear()
		for index in count:
			batch.append({"enemy_type": "summoner", "hp": 20, "damage": 1, "floor": 1})
		var spawned := tower._spawn_enemy_batch(room, batch, false)
		_check(spawned == count, "正式批次未整批生成%d只" % count)
		var enemies: Array = tower._enemy_nodes_by_room.get(room.room_id, [])
		for value in enemies:
			var enemy := value as Enemy3D
			_check(_supported(room, room.to_local(enemy.global_position), 1.15), "正式生成的敌人落点不安全")
			enemy.free()
		tower._enemy_nodes_by_room[room.room_id] = []
	print("SPAWN_REAL_BATCHES_OK counts=8,24")
