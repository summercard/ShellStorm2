extends Node3D
## 诊断（只读）：复现「波次切换后新刷出来的怪打不中」。
## 真实流程：进房 → 第1波 → 全部击杀 → 等 2 秒间歇 → 第2波生成 → 测新怪可命中性。
## 逐项记录：是否在树、active/visible、碰撞层、碰撞体世界区间、实体位置、水平弹道命中。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOM := "room_01"
const MUZZLE_Y := 0.458
const SHOT_DISTANCE := 5.0

var tower: TowerDescent3D
var pool: ProjectilePool3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(10)
	pool = tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	tower.force_enter_room_for_test(ROOM)
	var room := tower._room_by_id[ROOM] as DungeonRoom3D
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(5)
	print("WAVE_PROBE wave1_count=%d wave=%s/%s" % [
		_live(room).size(),
		str(tower._room_wave_numbers.get(ROOM, 0)),
		str(tower._room_wave_totals.get(ROOM, 0)),
	])
	await _sample("WAVE1", room)
	# 全部击杀
	for value in _live(room):
		(value as Enemy3D).take_damage(99999, false, Vector3.FORWARD)
	await _settle(4)
	print("WAVE_PROBE after_kill live=%d alive_account=%s" % [
		_live(room).size(), str(tower._alive_by_room.get(ROOM, -1)),
	])
	# 等间歇 + 第2波
	var spawm_wait := 0
	var previous_wave := int(tower._room_wave_numbers.get(ROOM, 1))
	while spawm_wait < 400:
		await get_tree().physics_frame
		spawm_wait += 1
		if _live(room).size() > 0 and int(tower._room_wave_numbers.get(ROOM, 1)) != previous_wave:
			break
	await _settle(4)
	print("WAVE_PROBE wave2_wait_frames=%d wave=%s/%s live=%d" % [
		spawm_wait,
		str(tower._room_wave_numbers.get(ROOM, 0)),
		str(tower._room_wave_totals.get(ROOM, 0)),
		_live(room).size(),
	])
	await _sample("WAVE2", room)
	print("WAVE_PROBE_DONE")
	get_tree().quit(0)


func _live(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			out.append(enemy)
	return out


func _sample(tag: String, room: DungeonRoom3D) -> void:
	for value in _live(room):
		var enemy := value as Enemy3D
		var local: Vector3 = room.to_local(enemy.global_position)
		var span: Vector2 = _collider_span(enemy)
		var stand_local := Vector3.ZERO
		var found := false
		for index in 8:
			var angle := TAU * float(index) / 8.0
			var candidate := Vector3(
				local.x + cos(angle) * SHOT_DISTANCE, local.y, local.z + sin(angle) * SHOT_DISTANCE
			)
			if room._spawn_floor_contains(candidate, 0.6):
				stand_local = candidate
				found = true
				break
		var hit := false
		var ray := "no_stand"
		if found:
			var ground: Vector3 = room.to_global(stand_local)
			var origin := Vector3(ground.x, ground.y + MUZZLE_Y, ground.z)
			var direction: Vector3 = enemy.global_position - origin
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				direction = direction.normalized()
			ray = _ray_label(origin, origin + direction * SHOT_DISTANCE, enemy)
			hit = await _flat_shot(origin, direction, enemy)
		print("%s kind=%s in_tree=%s active=%s visible=%s layer=%d mask=%d shape_disabled=%s local=(%.2f,%.2f,%.2f) collider=%.3f..%.3f ray=%s hit=%s" % [
			tag, enemy.enemy_kind, str(enemy.is_inside_tree()), str(enemy.is_runtime_ai_active()),
			str(enemy.visible), enemy.collision_layer, enemy.collision_mask,
			str(enemy.collision_shape.disabled), local.x, local.y, local.z,
			span.x, span.y, ray, str(hit),
		])


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
