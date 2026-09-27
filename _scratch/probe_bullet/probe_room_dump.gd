extends Node3D
## 诊断（只读）：远征01 全房落点几何与"可命中"实测。
## 逐房记录：壳体来源 / 尺寸 / 地砖格数 / 候选点数 / 可用点数 / 本房失败锁，
## 再进房刷怪，对每只怪记录：局部坐标、碰撞体世界区间、碰撞层、可见性、
## 与最近障碍盒的平面距离、以及从 5m 外以真实枪口高度水平射击能否命中。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const MUZZLE_Y := 0.458
const SHOT_DISTANCE := 5.0

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
	print("DUMP_ROOMS count=%d" % ids.size())
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		_dump_geometry(room)
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		await _inspect_room(room)
	print("DUMP_PROBE_DONE")
	get_tree().quit(0)


func _dump_geometry(room: DungeonRoom3D) -> void:
	var dims := room.get_dimensions()
	print("DUMP_ROOM id=%s type=%s size=%s auth=%s dims=(%.1f,%.1f) tiles=%d cand=%d edge=%d blocked=%s" % [
		room.room_id, room.room_type, room.size_class, str(room.authored_layout_shell),
		dims.x, dims.y, room._authored_tile_cells.size(), room._spawn_candidates.size(),
		room._spawn_edge_candidates.size(), str(tower._room_spawn_blocked.has(room.room_id)),
	])
	var probe_index := 0
	for _i in 3:
		var p: Vector3 = room.spawn_point_for_index(probe_index)
		print("DUMP_POINT room=%s idx=%d finite=%s local=(%.2f,%.2f,%.2f) avail=%d" % [
			room.room_id, probe_index, str(p.is_finite()),
			room.to_local(p).x, room.to_local(p).y, room.to_local(p).z,
			room._spawn_available.size(),
		])
		probe_index += 1


func _inspect_room(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(4)
	var live: Array = _live(room)
	print("DUMP_LIVE room=%s enemies=%d" % [room.room_id, live.size()])
	for value in live:
		await _probe_enemy(room, value as Enemy3D)


func _probe_enemy(room: DungeonRoom3D, enemy: Enemy3D) -> void:
	enemy.set_physics_process(false)
	enemy.set_process(false)
	var local := room.to_local(enemy.global_position)
	var span := _collider_span(enemy)
	var nearest := _nearest_blocker(room, local)
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
	print("DUMP_ENEMY room=%s kind=%s active=%s vis=%s layer=%d mask=%d shape_disabled=%s shp=%s local=(%.2f,%.2f,%.2f) span=%.2f..%.2f blocker_dist=%.2f ray=%s hit=%s" % [
		room.room_id, enemy.enemy_kind, str(enemy.is_runtime_ai_active()), str(enemy.visible),
		enemy.collision_layer, enemy.collision_mask, str(enemy.collision_shape.disabled),
		"null" if enemy.collision_shape.shape == null else enemy.collision_shape.shape.get_class(),
		local.x, local.y, local.z, span.x, span.y, nearest, ray, str(hit),
	])


func _nearest_blocker(room: DungeonRoom3D, local: Vector3) -> float:
	var best := 999.0
	for bounds in room._spawn_blockers:
		var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
		best = minf(best, _rect_distance(rect, Vector2(local.x, local.z)))
	return best


## 点到 AABB 的平面距离；点在盒内返回 0。
func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


func _live(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
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
