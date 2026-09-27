extends Node3D
## 诊断（只读）：**保留敌人物理**的前提下，测每只怪的脚下是否有地、以及水平实弹能否命中。
## 上一版探针冻结了敌人物理 ⇒ 悬空怪不会掉落、掩盖了「掉进下沉坑」这类问题。
## 本版：进房后不冻结，先跑 150 物理帧（≈2.5s，足够掉落），再逐只记录：
##   脚下地面射线落差（无地面/落差 >0.5m = 悬空）、世界 Y、与房间主层 Y 的差、
##   碰撞体世界区间、以及从玩家站立点水平射击的命中结果。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const MUZZLE_Y := 0.458
const SHOT_DISTANCE := 5.0
const SETTLE_FRAMES := 150

var tower: TowerDescent3D
var pool: ProjectilePool3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(12)
	pool = tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		await _inspect(room)
	print("GROUND_PROBE_DONE")
	get_tree().quit(0)


func _inspect(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(8)
	var live := _live(room)
	if live.is_empty():
		print("GROUND_ROOM %s enemies=0" % room.room_id)
		return
	# 让重力/物理真正跑起来，悬空怪会掉下去。
	for _index in SETTLE_FRAMES:
		await get_tree().physics_frame
	var room_y := room.global_position.y
	print("GROUND_ROOM %s dims=(%.1f,%.1f) tiles=%d enemies=%d" % [
		room.room_id, room.get_dimensions().x, room.get_dimensions().y,
		room._authored_tile_cells.size(), live.size(),
	])
	for value in live:
		var enemy := value as Enemy3D
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var local := room.to_local(enemy.global_position)
		var drop := _ground_drop(enemy)
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
			var origin := Vector3(ground.x, room_y + MUZZLE_Y, ground.z)
			var direction: Vector3 = enemy.global_position - origin
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				direction = direction.normalized()
			ray = _ray_label(origin, origin + direction * SHOT_DISTANCE, enemy)
			hit = await _flat_shot(origin, direction, enemy)
		print("GROUND_ENEMY room=%s kind=%s local_y=%.2f world_y=%.2f vs_room=%.2f ground_drop=%s span=%.2f..%.2f ray=%s hit=%s" % [
			room.room_id, enemy.enemy_kind, local.y, enemy.global_position.y, enemy.global_position.y - room_y,
			("none" if drop < -900.0 else "%.2f" % drop), span.x, span.y, ray, str(hit),
		])


## 从敌人中心正下方探测地面；返回「敌人中心 Y − 命中点 Y」。
## 没命中任何层 1 碰撞 = -999（脚下是空的）。
func _ground_drop(enemy: Enemy3D) -> float:
	var from: Vector3 = enemy.global_position + Vector3(0.0, 0.4, 0.0)
	var to: Vector3 = from + Vector3(0.0, -40.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return -999.0
	var point := result.get("position") as Vector3
	return from.y - point.y


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
