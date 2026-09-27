extends Node3D
## 诊断（只读）：用**真实武器开火路径**（Player3D → WeaponModel3D.try_fire → 真实枪口）
## 对准真实敌人射击，验证「刷出来的怪能否被击中」。
## 与前一版探针的差别：不再自己往弹池塞子弹，而是走玩家实际用的那把枪、实际枪口、
## 实际瞄准方向；同时对每只怪记录枪口世界高度与命中所需高度区间。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOMS := ["room_03", "room_05", "room_01"]

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(15)
	for room_id in ROOMS:
		await _run_room(room_id)
	print("REALFIRE_PROBE_DONE")
	get_tree().quit(0)


func _run_room(room_id: String) -> void:
	var room := tower._room_by_id.get(room_id) as DungeonRoom3D
	if room == null or tower.player == null:
		return
	tower.force_enter_room_for_test(room_id)
	tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(30)
	var live := _live(room)
	print("REALFIRE_ROOM %s enemies=%d" % [room_id, live.size()])
	for value in live:
		await _shoot(room, value as Enemy3D)


func _shoot(room: DungeonRoom3D, enemy: Enemy3D) -> void:
	var player := tower.player
	var weapon := player.weapon as WeaponModel3D
	if weapon == null or not is_instance_valid(enemy):
		return
	# 对准：把玩家摆到敌人前方 4m 处（地面高度），朝向敌人。
	var to_enemy: Vector3 = enemy.global_position - player.global_position
	to_enemy.y = 0.0
	if to_enemy.length_squared() < 0.0001:
		return
	var dir := to_enemy.normalized()
	var stand: Vector3 = enemy.global_position - dir * 4.0
	stand.y = room.global_position.y + 0.10
	player.global_position = stand
	await _settle(6)
	# 重新对准（敌人可能移动过）
	to_enemy = enemy.global_position - player.global_position
	to_enemy.y = 0.0
	if to_enemy.length_squared() < 0.0001:
		return
	dir = to_enemy.normalized()
	player.aim_direction = dir
	player.look_at(player.global_position + dir, Vector3.UP)
	await _settle(4)
	var muzzle := weapon.get("_muzzle") as Marker3D
	var muzzle_y := -999.0
	if muzzle != null and muzzle.is_inside_tree():
		muzzle_y = muzzle.global_position.y
	var span := _collider_span(enemy)
	var before := enemy.current_hp
	var fired := false
	var attempts := 0
	while attempts < 6 and not fired:
		attempts += 1
		fired = weapon.try_fire(player.aim_direction, player)
		if not fired:
			await _settle(12)
	if not fired:
		print("REALFIRE %s kind=%s FIRED_FALSE" % [room.room_id, enemy.enemy_kind])
		return
	for _index in 40:
		await get_tree().physics_frame
		if enemy.current_hp < before:
			break
	var hit := enemy.current_hp < before
	print("REALFIRE %s kind=%s muzzle_world_y=%.3f player_feet_y=%.3f muzzle_off=%.3f collider_abs=%.3f..%.3f dist=%.2f hit=%s hp %.1f->%.1f" % [
		room.room_id, enemy.enemy_kind, muzzle_y, player.global_position.y,
		muzzle_y - player.global_position.y,
		room.global_position.y + span.x, room.global_position.y + span.y,
		player.global_position.distance_to(enemy.global_position), str(hit), before, enemy.current_hp,
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
	return Vector2(world_aabb.position.y, world_aabb.end.y)


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
