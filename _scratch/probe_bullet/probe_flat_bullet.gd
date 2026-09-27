extends Node3D
## 诊断（只读）：以**真实枪口高度**水平射出的子弹，能否命中已刷出的怪。
## 依据：Player3D 把瞄准方向 y 归零 ⇒ 玩家永远水平射击；子弹从武器枪口
## （实测相对脚底 0.458m）水平飞出。本探针复用 probe_enemy_hittable 的进房与
## 取怪流程（已验证能取到怪），只把射线/弹道高度换成实测枪口高度。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const SHOT_DISTANCE := 5.0

var tower: TowerDescent3D
var pool: ProjectilePool3D
var muzzle_y := 0.458
var rows: Array[String] = []
var tested := 0
var hits := 0
var misses := 0


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(10)
	pool = tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	_measure_muzzle()
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	print("FLAT_ROOMS count=%d" % ids.size())
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		await _inspect_room(room)
	for row in rows:
		print("FLAT_ROW %s" % row)
	print("FLAT_SUMMARY muzzle_y=%.3f tested=%d hit=%d miss=%d" % [muzzle_y, tested, hits, misses])
	print("FLAT_PROBE_DONE")
	get_tree().quit(0)


func _measure_muzzle() -> void:
	var player := tower.player
	if player == null:
		return
	var weapon := player.weapon as WeaponModel3D
	if weapon == null:
		return
	var muzzle := weapon.get("_muzzle") as Marker3D
	if muzzle != null and muzzle.is_inside_tree():
		muzzle_y = muzzle.global_position.y - player.global_position.y
	print("FLAT_MUZZLE offset=%.3f player_y=%.3f" % [muzzle_y, player.global_position.y])


func _inspect_room(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(4)
	var live: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			live.append(enemy)
	print("FLAT_ROOM id=%s enemies=%d" % [room.room_id, live.size()])
	for enemy in live:
		enemy.set_physics_process(false)
		enemy.set_process(false)
		var local := room.to_local(enemy.global_position)
		var collider_top := _collider_top(enemy)
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
		var ray_label := "no_stand"
		if found:
			var ground: Vector3 = room.to_global(stand_local)
			var origin := Vector3(ground.x, ground.y + muzzle_y, ground.z)
			var direction := enemy.global_position - origin
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				direction = direction.normalized()
			ray_label = _ray_label(origin, origin + direction * SHOT_DISTANCE, enemy)
			hit = await _flat_shot(origin, direction, enemy)
		tested += 1
		if hit:
			hits += 1
		else:
			misses += 1
		rows.append(
			"room=%s kind=%s scale_y=%.2f local=(%.2f,%.2f) collider_span=%.3f..%.3f muzzle=%.3f ray=%s hit=%s" % [
				room.room_id, enemy.enemy_kind, enemy.scale.y, local.x, local.z,
				_collider_bottom(enemy), collider_top, muzzle_y, ray_label, str(hit),
			]
		)


func _collider_bottom(enemy: Enemy3D) -> float:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return -1.0
	var aabb := enemy.collision_shape.shape.get_debug_mesh().get_aabb()
	var world_aabb: AABB = enemy.collision_shape.global_transform * aabb
	return world_aabb.position.y - enemy.global_position.y


func _collider_top(enemy: Enemy3D) -> float:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return -1.0
	var aabb := enemy.collision_shape.shape.get_debug_mesh().get_aabb()
	var world_aabb: AABB = enemy.collision_shape.global_transform * aabb
	return world_aabb.end.y - enemy.global_position.y


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
		"direction": direction,
		"damage": 7,
		"hostile": false,
		"speed": 30.0,
		"shooter": tower.player,
		"tags": [] as Array[String],
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
