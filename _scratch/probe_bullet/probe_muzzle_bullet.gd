extends Node3D
## 诊断（只读）：复现「玩家子弹打不中已刷出的怪」。
## 真实几何前提：Player3D 把瞄准方向 `flat_direction.y = 0`，即玩家永远**水平**射击，
## 子弹从武器枪口高度水平飞出。本探针测三件事：
##   ① 枪口相对玩家脚底的世界高度
##   ② 每只怪的碰撞体世界顶部高度
##   ③ 从枪口高度水平射出的**真实子弹**能否命中，以及同高射线撞到了什么
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const SHOT_DISTANCE := 5.0

var tower: TowerDescent3D
var pool: ProjectilePool3D
var muzzle_offset_y := 0.0
var muzzle_source := "none"
var player_capsule_height := -1.0
var rows: Array[String] = []
var tested := 0
var hits := 0
var misses := 0
var occluded := 0


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(10)
	pool = tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	_measure_player()
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		await _inspect_room(room)
	for row in rows:
		print("MUZZLE_ROW %s" % row)
	print("MUZZLE_SUMMARY muzzle_offset=%.3f source=%s player_capsule=%.2f tested=%d hit=%d miss=%d occluded=%d" % [
		muzzle_offset_y, muzzle_source, player_capsule_height, tested, hits, misses, occluded,
	])
	print("MUZZLE_PROBE_DONE")
	get_tree().quit(0)


func _measure_player() -> void:
	var player := tower.player
	if player == null:
		print("MUZZLE_PLAYER_MISSING")
		return
	var weapon := player.weapon as WeaponModel3D
	if weapon != null:
		var muzzle := weapon.get("_muzzle") as Marker3D
		if muzzle != null and muzzle.is_inside_tree():
			muzzle_offset_y = muzzle.global_position.y - player.global_position.y
			muzzle_source = "weapon_muzzle"
	for value in player.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		if collision.shape is CapsuleShape3D:
			player_capsule_height = (collision.shape as CapsuleShape3D).height
	if muzzle_source == "none":
		muzzle_offset_y = player_capsule_height if player_capsule_height > 0.0 else 0.0
		muzzle_source = "fallback_capsule_top"
	print("MUZZLE_PLAYER origin_y=%.3f muzzle_offset=%.3f source=%s capsule=%.2f weapon_present=%s" % [
		player.global_position.y, muzzle_offset_y, muzzle_source, player_capsule_height,
		str(weapon != null),
	])


func _inspect_room(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	await _settle(4)
	var live: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			live.append(enemy)
	for enemy in live:
		# 冻结 AI，使「水平弹道能否命中」可复现；碰撞体不动。
		enemy.set_physics_process(false)
		enemy.set_process(false)
		var local := room.to_local(enemy.global_position)
		var collider_top := _collider_top_offset(enemy)
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
			var origin: Vector3 = room.to_global(stand_local) + Vector3(0.0, muzzle_offset_y, 0.0)
			var direction := enemy.global_position - origin
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				direction = direction.normalized()
			ray_label = _ray_label(origin, enemy.global_position + Vector3(0.0, muzzle_offset_y, 0.0), enemy)
			hit = await _flat_shot(origin, direction, enemy)
		tested += 1
		if hit:
			hits += 1
		else:
			misses += 1
			if ray_label != "enemy":
				occluded += 1
		rows.append(
			"room=%s kind=%s scale_y=%.2f local=(%.2f,%.2f) collider_top=%.3f muzzle=%.3f stand=%s ray=%s hit=%s" % [
				room.room_id, enemy.enemy_kind, enemy.scale.y, local.x, local.z,
				collider_top, muzzle_offset_y, str(found), ray_label, str(hit),
			]
		)


func _collider_top_offset(enemy: Enemy3D) -> float:
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
