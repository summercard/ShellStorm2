extends Node3D
## 诊断（只读）：逐个验证 2 波房（room_03/04/05/08）第 2 波新刷怪的可命中性。
## 流程：进房 → 记录第1波 → 全部击杀 → 等过间歇 → 第2波生成 → 对每只新怪
## 记录（在树/激活/可见/碰撞层/碰撞体世界区间/局部坐标/是否 finite）并做水平实弹命中测试。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const MUZZLE_Y := 0.458
const SHOT_DISTANCE := 5.0
const ROOMS := ["room_03", "room_04", "room_05", "room_08"]

var tower: TowerDescent3D
var pool: ProjectilePool3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(12)
	pool = tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	for room_id in ROOMS:
		await _run_room(room_id)
	print("W2_PROBE_DONE")
	get_tree().quit(0)


func _run_room(room_id: String) -> void:
	var room := tower._room_by_id.get(room_id) as DungeonRoom3D
	if room == null:
		print("W2_ROOM %s missing" % room_id)
		return
	tower.force_enter_room_for_test(room_id)
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(6)
	print("W2_ROOM %s wave=%d/%d live=%d tiles=%d cand=%d blocked=%s" % [
		room_id, int(tower._room_wave_numbers.get(room_id, 0)),
		int(tower._room_wave_totals.get(room_id, 0)), _live(room).size(),
		room._authored_tile_cells.size(), room._spawn_candidates.size(),
		str(tower._room_spawn_blocked.has(room_id)),
	])
	await _sample("W2_WAVE1", room)
	var wave1 := _live(room)
	for value in wave1:
		(value as Enemy3D).take_damage(999999, false, Vector3.FORWARD)
	await _settle(4)
	print("W2_KILLED %s after_kill_live=%d alive_account=%s queue=%d pending=%s" % [
		room_id, _live(room).size(), str(tower._alive_by_room.get(room_id, -1)),
		(tower._room_wave_queues.get(room_id, []) as Array).size(),
		str(tower._wave_spawn_pending.has(room_id)),
	])
	# 等间歇（2s ≈ 120 物理帧）并等第 2 波落地
	var waited := 0
	while waited < 420:
		await get_tree().physics_frame
		waited += 1
		if _live(room).size() > 0:
			break
	await _settle(6)
	print("W2_SPAWN %s waited=%d wave=%d/%d live=%d queued=%d" % [
		room_id, waited, int(tower._room_wave_numbers.get(room_id, 0)),
		int(tower._room_wave_totals.get(room_id, 0)), _live(room).size(),
		(tower._room_wave_queues.get(room_id, []) as Array).size(),
	])
	await _sample("W2_WAVE2", room)


func _sample(tag: String, room: DungeonRoom3D) -> void:
	for value in _live(room):
		var enemy := value as Enemy3D
		enemy.set_physics_process(false)
		enemy.set_process(false)
		var local := room.to_local(enemy.global_position)
		var span := _collider_span(enemy)
		var stand_found := false
		var stand_local := Vector3.ZERO
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var candidate := Vector3(
				local.x + cos(angle) * SHOT_DISTANCE, local.y, local.z + sin(angle) * SHOT_DISTANCE
			)
			if room._spawn_floor_contains(candidate, 0.6):
				stand_local = candidate
				stand_found = true
				break
		var ray := "no_stand"
		var hit := false
		if stand_found:
			var ground: Vector3 = room.to_global(stand_local)
			var origin := Vector3(ground.x, ground.y + MUZZLE_Y, ground.z)
			var direction: Vector3 = enemy.global_position - origin
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				direction = direction.normalized()
			ray = _ray_label(origin, origin + direction * SHOT_DISTANCE, enemy)
			hit = await _flat_shot(origin, direction, enemy)
		print("%s kind=%s active=%s vis=%s layer=%d mask=%d disabled=%s finite=%s local=(%.2f,%.2f,%.2f) span=%.2f..%.2f ray=%s hit=%s" % [
			tag, enemy.enemy_kind, str(enemy.is_runtime_ai_active()), str(enemy.visible),
			enemy.collision_layer, enemy.collision_mask, str(enemy.collision_shape.disabled),
			str(enemy.global_position.is_finite()),
			local.x, local.y, local.z, span.x, span.y, ray, str(hit),
		])


func _live(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			out.append(enemy)
	return out


func _collider_span(enemy: Enemy3D) -> Vector2:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return Vector2(-1.0, -1.0)
	var aabb := enemy.collision_shape.shape.get_debug_mesh().get_aabb()
	var world_aabb: AABB = enemy.collision_shape.global_transform * aabb
	return Vector2(world_aabb.position.y - enemy.global_position.y, world_aabb.end.y - enemy.global_position.y)


func _ray_label(from: Vector3, to: Vector3, enemy: Enemy3D) -> String:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 5
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "nothing"
	if hit.get("collider") == enemy:
		return "enemy"
	var node := hit.get("collider") as Node
	return "blocked:%s" % (node.name if node != null else "?")


func _flat_shot(origin: Vector3, direction: Vector3, enemy: Enemy3D) -> bool:
	if pool == null:
		return false
	var before := enemy.current_hp
	var projectile := pool.acquire({
		"direction": direction, "damage": 7, "hostile": false, "speed": 30.0,
		"shooter": tower.player, "tags": [] as Array[String],
	}, origin)
	for _index in 30:
		await get_tree().physics_frame
		if enemy.current_hp < before:
			break
	var confirmed := enemy.current_hp < before
	if not confirmed and projectile != null and is_instance_valid(projectile):
		projectile.call("_retire")
	return confirmed


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
