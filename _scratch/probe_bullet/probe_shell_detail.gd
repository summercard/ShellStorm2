extends Node3D
## 诊断（只读）：复现真实流送时序「刷怪 → 家具出现」的顺序，验证敌人是否被后到的家具碰撞体埋住；
## 并做对照实验：同一只怪在 process_mode=INHERIT / DISABLED 下的射线可命中性。
## 隔离措施：把玩家挪到高空并停物理，避免 tower 因玩家进房而重新流送本房（那会把本房打回 DATA_ONLY，
## 使「家具态」测量失真）。只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const MUZZLE_Y := 0.458
const RAY_RADIUS := 5.0
const RAY_DIRS := 24

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	if tower.player != null:
		tower.player.global_position = Vector3(0.0, 500.0, 0.0)
		tower.player.set_physics_process(false)
	await _settle(3)
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		await _run(tower._room_by_id[id_value] as DungeonRoom3D)
	await _control()
	print("SD_PROBE_DONE")
	get_tree().quit(0)


func _run(room: DungeonRoom3D) -> void:
	if room == null:
		return
	var id := room.room_id
	_free_room_enemies(id)
	await _settle(2)
	room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	tower._spawned_rooms.erase(id)
	tower._room_spawn_blocked.erase(id)
	tower._alive_by_room[id] = 0
	tower._room_wave_queues[id] = []
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	await _settle(3)
	if not tower._prepare_revealed_hostile_room(room):
		print("SD_ROOM %s skip type=%s" % [id, room.room_type])
		return
	await _settle(4)
	var shell_live := _live(id)
	print("SD_ROOM %s type=%s phase=SHELL enemies=%d detail_built=%s" % [
		id, room.room_type, shell_live.size(), str(room._detail_built),
	])
	for value in shell_live:
		_print_enemy(room, value as Enemy3D, "SHELL")
	# 家具出现（隔离：只建房具，不动流送状态与图）
	room.ensure_detail_built()
	await _settle(6)
	var detail_live := _live(id)
	print("SD_ROOM %s type=%s phase=DETAIL enemies=%d detail_built=%s detail_root=%s" % [
		id, room.room_type, detail_live.size(), str(room._detail_built),
		str(room._detail_root != null),
	])
	for value in detail_live:
		_print_enemy(room, value as Enemy3D, "DETAIL")


## 对照：同一只怪，pm=INHERIT vs pm=DISABLED，射线是否还看得见它。
func _control() -> void:
	var room := tower._room_by_id.get("room_03") as DungeonRoom3D
	var live := _live("room_03")
	if room == null or live.is_empty():
		print("SD_CONTROL unavailable")
		return
	var enemy := live[0] as Enemy3D
	enemy.set_runtime_active(true, true)
	await _settle(2)
	print("SD_CONTROL kind=%s pm=INHERIT -> %s" % [enemy.enemy_kind, _ray_probe(enemy)])
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	await _settle(2)
	print("SD_CONTROL kind=%s pm=DISABLED -> %s" % [enemy.enemy_kind, _ray_probe(enemy)])
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	await _settle(2)
	print("SD_CONTROL kind=%s pm=INHERIT(restored) -> %s" % [enemy.enemy_kind, _ray_probe(enemy)])


func _print_enemy(room: DungeonRoom3D, enemy: Enemy3D, phase: String) -> void:
	if not is_instance_valid(enemy):
		return
	var inside := _static_contains(enemy)
	var probe := _ray_probe(enemy)
	var shape_disabled := true
	if enemy.collision_shape != null:
		shape_disabled = enemy.collision_shape.disabled
	print("SD_ENEMY %s phase=%s kind=%s pos=(%.2f,%.2f,%.2f) inside_static=%d layer=%d mask=%d shape_dis=%s pm=%d phys=%s vis=%s ai=%s %s" % [
		room.room_id, phase, enemy.enemy_kind,
		enemy.global_position.x, enemy.global_position.y, enemy.global_position.z,
		inside, enemy.collision_layer, enemy.collision_mask, str(shape_disabled),
		enemy.process_mode, str(enemy.is_physics_processing()), str(enemy.visible),
		enemy.ai_state, probe,
	])


func _ray_probe(enemy: Enemy3D) -> String:
	var feet := enemy.global_position
	var aim := feet + Vector3(0.0, 0.30, 0.0)
	var to_enemy := 0
	var blocked := 0
	var nothing := 0
	var blockers := {}
	for index in RAY_DIRS:
		var angle := TAU * float(index) / float(RAY_DIRS)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var origin := feet + Vector3(0.0, MUZZLE_Y, 0.0) - dir * RAY_RADIUS
		var query := PhysicsRayQueryParameters3D.create(origin, aim)
		query.collision_mask = 5
		query.collide_with_areas = false
		query.exclude = _player_exclude()
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			nothing += 1
		elif hit.get("collider") == enemy:
			to_enemy += 1
		else:
			blocked += 1
			var node := hit.get("collider") as Node
			var hit_name: String = str(node.name) if node != null else "?"
			blockers[hit_name] = int(blockers.get(hit_name, 0)) + 1
	return "ray%dhit=%d blocked=%d none=%d blockers=%s" % [
		RAY_DIRS, to_enemy, blocked, nothing, str(blockers),
	]


func _static_contains(enemy: Enemy3D) -> int:
	var point := enemy.global_position + Vector3(0.0, 0.30, 0.0)
	var count := 0
	for value in tower.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		if collision == null or collision.shape == null or collision.disabled:
			continue
		var body := collision.get_parent() as StaticBody3D
		if body == null or (body.collision_layer & 1) == 0:
			continue
		var aabb: AABB = collision.global_transform * collision.shape.get_debug_mesh().get_aabb()
		if aabb.has_point(point):
			count += 1
	return count


func _live(room_id: String) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			out.append(enemy)
	return out


func _free_room_enemies(room_id: String) -> void:
	for value in tower._enemy_nodes_by_room.get(room_id, []):
		var node := value as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	tower._enemy_nodes_by_room[room_id] = []


func _player_exclude() -> Array[RID]:
	var ex: Array[RID] = []
	var player := tower.player
	if player != null and is_instance_valid(player) and player is CollisionObject3D:
		ex.append((player as CollisionObject3D).get_rid())
	return ex


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
