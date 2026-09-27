extends Node3D
## 诊断（只读）：远征关卡里**实际刷出来**的怪，能不能被子弹打到。
## 用真实刷怪路径（_on_room_entered → _commit_room_waves），再对每只怪做
## ① 八个方向的实体射线（mask=5，与玩家子弹同掩码）② 真实 Projectile3D 命中。
## 结果只打印 + push_error，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const RAY_DISTANCE := 3.6
const EYE_HEIGHT := 1.15
const CHEST_HEIGHT := 0.95
const BULLET_SAMPLE_LIMIT := 8
const BULLET_TAG := &"diagnostic"

var tower: TowerDescent3D
var failures: Array[String] = []
var total_enemies := 0
var unhittable := 0
var bullet_sampled := 0
var bullet_failed := 0
var bullet_state: Array = [null, false]


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(10)
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	var room_count := 0
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		room_count += 1
		await _inspect_room(room)
	print("HITTABLE_SUMMARY rooms=%d enemies=%d unhittable=%d bullet_sampled=%d bullet_failed=%d failures=%d" % [
		room_count, total_enemies, unhittable, bullet_sampled, bullet_failed, failures.size(),
	])
	for message in failures:
		push_error(message)
	print("ENEMY_HITTABLE_PROBE_OK" if failures.is_empty() else "ENEMY_HITTABLE_PROBE_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)


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
	if live.is_empty():
		print("ROOM %s type=%s enemies=0 cleared=%s spawn_blocked=%s wave=%s/%s" % [
			room.room_id, room.room_type, str(room.cleared),
			str(tower._room_spawn_blocked.has(room.room_id)),
			str(tower._room_wave_numbers.get(room.room_id, 0)),
			str(tower._room_wave_totals.get(room.room_id, 0)),
		])
		return
	for enemy in live:
		total_enemies += 1
		var local := room.to_local(enemy.global_position)
		var free_dirs: Array[int] = []
		var blocked: Array[String] = []
		var clear_dir := Vector3.ZERO
		for dir_index in 8:
			var angle := TAU * float(dir_index) / 8.0
			var origin := enemy.global_position + Vector3(0.0, EYE_HEIGHT, 0.0) + Vector3(cos(angle), 0.0, sin(angle)) * RAY_DISTANCE
			var target := enemy.global_position + Vector3(0.0, CHEST_HEIGHT, 0.0)
			var hit := _ray(origin, target)
			if hit.is_empty():
				blocked.append("%d:穿过去" % dir_index)
				continue
			if hit.get("collider") == enemy:
				free_dirs.append(dir_index)
				if clear_dir == Vector3.ZERO:
					clear_dir = (target - origin).normalized()
			else:
				blocked.append("%d:%s" % [dir_index, _label(hit.get("collider"))])
		var shape_radius := -1.0
		if enemy.collision_shape != null and enemy.collision_shape.shape is CylinderShape3D:
			shape_radius = (enemy.collision_shape.shape as CylinderShape3D).radius
		print("ENEMY room=%s kind=%s local=(%.2f,%.2f,%.2f) state=%s active=%s visible=%s layer=%d mask=%d shape_disabled=%s radius=%.2f free_dirs=%d blocked=%s" % [
			room.room_id, enemy.enemy_kind, local.x, local.y, local.z, enemy.ai_state,
			str(enemy.is_runtime_ai_active()), str(enemy.visible), enemy.collision_layer,
			enemy.collision_mask, str(enemy.collision_shape.disabled if enemy.collision_shape != null else true),
			shape_radius, free_dirs.size(), str(blocked),
		])
		if not _on_floor(room, enemy):
			failures.append("房 %s 的 %s 不在主通行层地砖上 local=%s" % [room.room_id, enemy.enemy_kind, local])
		if free_dirs.is_empty():
			unhittable += 1
			failures.append("房 %s 的 %s 八个方向都打不到 local=%s blocked=%s" % [
				room.room_id, enemy.enemy_kind, local, str(blocked),
			])
			continue
		if bullet_sampled < BULLET_SAMPLE_LIMIT:
			bullet_sampled += 1
			var origin := enemy.global_position + Vector3(0.0, EYE_HEIGHT, 0.0) - clear_dir * RAY_DISTANCE
			if not await _bullet_hits(origin, clear_dir, enemy):
				bullet_failed += 1
				failures.append("房 %s 的 %s 真实子弹未命中（射线判定通过）local=%s" % [room.room_id, enemy.enemy_kind, local])


func _on_floor(room: DungeonRoom3D, enemy: Enemy3D) -> bool:
	if absf(room.to_local(enemy.global_position).y) > 0.30:
		return false
	return room._spawn_floor_contains(room.to_local(enemy.global_position), 0.6)


func _bullet_hits(origin: Vector3, dir: Vector3, enemy: Enemy3D) -> bool:
	var pool := tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	if pool == null:
		return true
	bullet_state[0] = enemy
	bullet_state[1] = false
	var projectile := pool.acquire({
		"direction": dir, "damage": 0, "hostile": false, "speed": 30.0,
		"tags": [] as Array[String],
	}, origin)
	projectile.hit_confirmed.connect(_on_bullet_hit)
	for _index in 24:
		await get_tree().physics_frame
		if bool(bullet_state[1]):
			break
	projectile.hit_confirmed.disconnect(_on_bullet_hit)
	var confirmed := bool(bullet_state[1])
	if not confirmed and is_instance_valid(projectile):
		projectile.call("_retire")
	return confirmed


func _on_bullet_hit(target: Node, _damage: int, _critical: bool) -> void:
	if target == bullet_state[0]:
		bullet_state[1] = true


func _label(collider: Variant) -> String:
	var node := collider as Node
	if node == null:
		return "?"
	var body := node as CollisionObject3D
	if body != null:
		return "%s(layer=%d)" % [node.name, body.collision_layer]
	return str(node.name)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 5
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
