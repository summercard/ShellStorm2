extends Node3D
## 诊断（只读）：真实武器实弹命中率 vs 距离曲线 + 枪口横向偏移（同一目标，冻结不动作）。
## 用来判定「瞄准了却打不中」是 ① 枪口不在瞄准轴上（子弹平行偏移） ② 还是 spread 随机散布。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOM_ID := "room_01"
const DISTANCES := [2.0, 3.0, 4.0, 5.0, 7.0, 10.0, 14.0]
const SHOTS_PER_CASE := 12

var tower: TowerDescent3D
var _last_projectile: Node = null
var _last_trace := "n/a"


func _on_projectile_spawned(projectile: Node) -> void:
	if projectile != null and is_instance_valid(projectile):
		_last_projectile = projectile


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	var room := await _find_hostile_room()
	if room == null or tower.player == null:
		print("HR_ABORT missing")
		get_tree().quit(0)
		return
	tower.force_enter_room_for_test(room.room_id)
	await _settle(30)
	# 冻住全场敌人，只留一只做靶
	var live := _live(room)
	if live.is_empty():
		print("HR_ABORT no_enemies room=%s" % room.room_id)
		get_tree().quit(0)
		return
	print("HR_ROOM id=%s dim=%s" % [room.room_id, str(room.get_dimensions())])
	for value in live:
		var e := value as Enemy3D
		e.set_physics_process(false)
		e.move_speed = 0.0
	var target := live[0] as Enemy3D
	for index in range(1, live.size()):
		(live[index] as Enemy3D).global_position += Vector3(0.0, 300.0, 0.0)
	var weapon := tower.player.weapon as WeaponModel3D
	if weapon == null:
		print("HR_ABORT no_weapon")
		get_tree().quit(0)
		return
	var muzzle := weapon.get("_muzzle") as Marker3D
	if not weapon.projectile_spawned.is_connected(_on_projectile_spawned):
		weapon.projectile_spawned.connect(_on_projectile_spawned)
	print("HR_WEAPON gun=%s proj=%d spread=%.4f speed=%.2f muzzle=%s" % [
		weapon.gun_id, weapon.projectile_count, weapon.spread, weapon.bullet_speed,
		("ok" if muzzle != null and muzzle.is_inside_tree() else "null"),
	])
	var dir := await _pick_dir(room, target)
	if dir == Vector3.ZERO:
		print("HR_ABORT no_clear_dir")
		get_tree().quit(0)
		return
	print("HR_TARGET kind=%s radius=%.3f height=%.3f layer=%d mask=%d" % [
		target.enemy_kind, _radius(target), _height(target),
		target.collision_layer, target.collision_mask,
	])
	# 1) 枪口横向偏移（多角度）
	var half := room.get_dimensions() * 0.5 - Vector2(3.0, 3.0)
	for yaw_index in 4:
		var yaw := TAU * float(yaw_index) / 4.0
		var probe_dir := Vector3(cos(yaw), 0.0, sin(yaw)).normalized()
		var stand := target.global_position - probe_dir * 4.0
		stand.y = target.global_position.y
		var local := room.to_local(stand)
		if absf(local.x) > half.x or absf(local.z) > half.y:
			continue
		tower.player.global_position = stand
		_face_flat(probe_dir)
		await _settle(8)
		_face_flat(probe_dir)
		await _settle(1)
		var mp: Vector3 = muzzle.global_position if muzzle != null and muzzle.is_inside_tree() else tower.player.global_position
		print("HR_MUZZLE yaw=%d lat_perp_axis=%.3f signed=%.3f player_y=%.2f muzzle_dy=%.3f" % [
			yaw_index * 90, _lateral_from_player(mp, probe_dir),
			_lateral_signed(mp, probe_dir), tower.player.global_position.y,
			mp.y - tower.player.global_position.y,
		])
	# 2) 命中率曲线
	for d in DISTANCES:
		await _sweep(room, dir, float(d))


func _sweep(room: DungeonRoom3D, dir: Vector3, d: float) -> void:
	var target := _reacquire(room)
	if target == null:
		print("HR_CASE d=%.1f target_freed_skip" % d)
		return
	var stand: Vector3 = target.global_position - dir * d
	stand.y = target.global_position.y
	tower.player.global_position = stand
	_face_flat(dir)
	await _settle(10)
	var weapon := tower.player.weapon as WeaponModel3D
	target = _reacquire(room)
	if weapon == null or target == null:
		print("HR_CASE d=%.1f lost_target" % d)
		return
	var muzzle := weapon.get("_muzzle") as Marker3D
	_face_flat(dir)
	await _settle(1)
	var mp: Vector3 = muzzle.global_position if muzzle != null and muzzle.is_inside_tree() else tower.player.global_position
	var lat := _lateral_from_player(mp, dir)
	# 枪口→靶的遮挡检查（同一 mask 5），确认弹道不被家具/墙挡
	var ray_note := _ray_note(mp, target)
	# spread 保持产品值
	var normal_hits := await _fire_batch(target, weapon, dir, SHOTS_PER_CASE)
	var after_normal := _last_trace
	var saved_spread := weapon.spread
	weapon.spread = 0.0
	var zero_hits := await _fire_batch(target, weapon, dir, SHOTS_PER_CASE)
	var after_zero := _last_trace
	weapon.spread = saved_spread
	print("HR_CASE d=%.1f muzzle_lat=%.3f radius=%.3f muzzle_dy=%.3f normal=%d/%d spread0=%d/%d ray=%s trace_normal=%s trace_spread0=%s" % [
		d, lat, _radius(target), mp.y - tower.player.global_position.y,
		normal_hits, SHOTS_PER_CASE, zero_hits, SHOTS_PER_CASE, ray_note, after_normal, after_zero,
	])


func _ray_note(from: Vector3, target: Enemy3D) -> String:
	if target == null or not is_instance_valid(target):
		return "no_target"
	# ① 沿子弹真实路径：从枪口水平向前 20m（子弹恒在枪口高度水平飞）
	var flat_query := PhysicsRayQueryParameters3D.create(from, from + _last_dir * 20.0)
	flat_query.collision_mask = 5
	flat_query.collide_with_areas = false
	var flat_hit := get_world_3d().direct_space_state.intersect_ray(flat_query)
	var flat_note := "flat:none"
	if not flat_hit.is_empty():
		var c: Variant = flat_hit.get("collider")
		var n := c as Node
		flat_note = "flat:%s@%.2f" % [str(n.name) if n != null else "?", from.distance_to(flat_hit.get("position"))]
	# ② 枪口→靶心（斜线，旧口径，仅参考）
	var aim_point: Vector3 = target.global_position + Vector3(0.0, 0.30, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, aim_point)
	query.collision_mask = 5
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_note := "none"
	if not hit.is_empty():
		var collider: Variant = hit.get("collider")
		if collider == target:
			aim_note = "target@%.2f" % from.distance_to(hit.get("position"))
		else:
			var node := collider as Node
			aim_note = "%s@%.2f" % [str(node.name) if node != null else "?", from.distance_to(hit.get("position"))]
	return "%s aim:%s" % [flat_note, aim_note]


func _reacquire(room: DungeonRoom3D) -> Enemy3D:
	var live := _live(room)
	if live.is_empty():
		return null
	return live[0] as Enemy3D


func _fire_batch(target: Enemy3D, weapon: WeaponModel3D, dir: Vector3, count: int) -> int:
	var hits := 0
	for _index in count:
		target.current_hp = target.max_hp
		_face_flat(dir)
		var fired := false
		var attempts := 0
		while attempts < 10 and not fired:
			attempts += 1
			fired = weapon.try_fire(dir, tower.player)
			if not fired:
				await _settle(10)
		if not fired:
			continue
		var before := target.current_hp
		var got := false
		var origin: Vector3 = (
			_last_projectile.global_position
			if _last_projectile != null and is_instance_valid(_last_projectile)
			else tower.player.global_position
		)
		var traveled := 0.0
		var end_reason := "timeout"
		for _frame in 90:
			await get_tree().physics_frame
			if target.current_hp < before:
				got = true
				end_reason = "hit"
				break
			if _last_projectile == null or not is_instance_valid(_last_projectile):
				end_reason = "freed"
				break
			if not bool(_last_projectile.get("_active")):
				end_reason = "retired"
				break
			traveled = maxf(traveled, _last_projectile.global_position.distance_to(origin))
		if got:
			hits += 1
		if _index == 0:
			_last_trace = "%s travel=%.2f" % [end_reason, traveled]
		await _settle(2)
	target.current_hp = target.max_hp
	return hits


## 把玩家吸到房间地面（不同房地面可能不是 y=0）。
func _player_stay_on_floor(room: DungeonRoom3D) -> void:
	var player := tower.player
	if player == null:
		return
	var body := player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO


func _face_flat(dir: Vector3) -> void:
	var player := tower.player
	if player == null:
		return
	player.aim_direction = dir
	player.look_at(player.global_position + dir, Vector3.UP)


## 枪口相对「过玩家原点、沿 dir 的轴」的横向距离（无符号）。
func _lateral_from_player(point: Vector3, dir: Vector3) -> float:
	var rel: Vector3 = point - tower.player.global_position
	rel.y = 0.0
	return (rel - dir * rel.dot(dir)).length()


## 带符号（正 = 玩家右侧），看是不是固定在某一侧。
func _lateral_signed(point: Vector3, dir: Vector3) -> float:
	var rel: Vector3 = point - tower.player.global_position
	rel.y = 0.0
	return rel.dot(Vector3(-dir.z, 0.0, dir.x))


func _pick_dir(room: DungeonRoom3D, target: Enemy3D) -> Vector3:
	var anchor := target.global_position
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var dir := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		var stand := anchor - dir * 4.0
		stand.y = anchor.y
		if not room._spawn_floor_contains(room.to_local(stand), 0.5):
			continue
		var far := stand - dir * 12.0
		far.y = anchor.y
		if not room._spawn_floor_contains(room.to_local(far), 0.5):
			continue
		return dir
	return Vector3.ZERO


func _find_hostile_room() -> DungeonRoom3D:
	for id_value in ["room_03", "room_01", "room_02", "room_10", "room_05", "room_07", "room_08"]:
		var room := tower._room_by_id.get(id_value) as DungeonRoom3D
		if room == null:
			continue
		tower.force_enter_room_for_test(str(id_value))
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
		for _wait in 90:
			await get_tree().physics_frame
			if not _live(room).is_empty():
				return room
	return null


func _live(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			out.append(enemy)
	return out


func _radius(enemy: Enemy3D) -> float:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return -1.0
	var aabb := enemy.collision_shape.shape.get_debug_mesh().get_aabb()
	var world_aabb: AABB = enemy.collision_shape.global_transform * aabb
	return (world_aabb.end.x - world_aabb.position.x) * 0.5


func _height(enemy: Enemy3D) -> float:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return -1.0
	var aabb := enemy.collision_shape.shape.get_debug_mesh().get_aabb()
	var world_aabb: AABB = enemy.collision_shape.global_transform * aabb
	return world_aabb.end.y - world_aabb.position.y


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
