extends Node3D
## 诊断（只读）：冻结目标怪后，扫描「玩家站位距离 → 真实武器实弹命中率」曲线，
## 并记录每一发的真实子弹几何：枪口相对「玩家→敌」轴的横向偏移、以及实际弹道
## 与 aim 方向的夹角。用于判定 REAL 脱靶是探针朝向假象，还是产品真缺陷。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOMS := ["room_03", "room_01", "room_02", "room_05"]
const DISTANCES := [0.7, 0.9, 1.1, 1.3, 1.6, 2.0, 2.5, 3.0, 4.0, 5.0]

var tower: TowerDescent3D
var pool: ProjectilePool3D
var _shots: Array = []


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(15)
	pool = tower.get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	for room_id in ROOMS:
		await _run_room(room_id)
	print("DIST_PROBE_DONE")
	get_tree().quit(0)


func _run_room(room_id: String) -> void:
	var room := tower._room_by_id.get(room_id) as DungeonRoom3D
	if room == null or tower.player == null:
		print("DIST_ROOM %s missing" % room_id)
		return
	tower.force_enter_room_for_test(room_id)
	tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(30)
	var live := _live(room)
	print("DIST_ROOM %s enemies=%d" % [room_id, live.size()])
	if live.is_empty():
		return
	for value in live:
		var e := value as Enemy3D
		e.set_physics_process(false)
		e.move_speed = 0.0
	var target := live[0] as Enemy3D
	for index in range(1, live.size()):
		(live[index] as Enemy3D).global_position += Vector3(0.0, 200.0, 0.0)
	var room_y := room.global_position.y
	var anchor: Vector3 = room.to_global(Vector3.ZERO)
	anchor.y = room_y
	target.global_position = anchor
	var weapon := tower.player.weapon as WeaponModel3D
	if weapon == null:
		print("DIST_ROOM %s no_weapon" % room_id)
		return
	if not weapon.projectile_spawned.is_connected(_on_projectile_spawned):
		weapon.projectile_spawned.connect(_on_projectile_spawned)
	var dir := await _pick_dir(room, target, anchor, room_y)
	if dir == Vector3.ZERO:
		print("DIST_ROOM %s no_clear_dir" % room_id)
		return
	print("DIST_TARGET %s kind=%s radius=%.3f h=%.3f gun=%s proj=%d spread=%.3f layer=%d" % [
		room_id, target.enemy_kind, _radius(target), _height(target),
		weapon.gun_id, weapon.projectile_count, weapon.spread, target.collision_layer,
	])
	for d in DISTANCES:
		await _sweep_one(room, target, weapon, dir, float(d), room_y)


func _on_projectile_spawned(projectile: Node) -> void:
	if projectile != null and is_instance_valid(projectile):
		_shots.append(projectile)


func _pick_dir(room: DungeonRoom3D, target: Enemy3D, anchor: Vector3, room_y: float) -> Vector3:
	var weapon := tower.player.weapon as WeaponModel3D
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var dir := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		var stand := anchor - dir * 5.0
		stand.y = room_y + 0.10
		if not room._spawn_floor_contains(room.to_local(stand), 0.5):
			continue
		tower.player.global_position = stand
		_face(target)
		await _settle(3)
		_face(target)
		var muzzle := weapon.get("_muzzle") as Marker3D
		if muzzle == null or not muzzle.is_inside_tree():
			continue
		var origin := muzzle.global_position
		var aim_point: Vector3 = target.global_position + Vector3(0.0, _height(target) * 0.5, 0.0)
		var to_target: Vector3 = aim_point - origin
		var query := PhysicsRayQueryParameters3D.create(origin, origin + to_target)
		query.collision_mask = 5
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.get("collider") == target:
			return dir
	return Vector3.ZERO


## 让玩家真正面向敌人（真实游玩里朝向就是这么来的）。
func _face(target: Enemy3D) -> void:
	var player := tower.player
	if player == null:
		return
	var flat := Vector3(target.global_position.x, player.global_position.y, target.global_position.z)
	if player.global_position.distance_squared_to(flat) <= 0.0004:
		return
	player.look_at(flat, Vector3.UP)
	var aim: Vector3 = target.global_position - player.global_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		player.aim_direction = aim.normalized()


func _sweep_one(room: DungeonRoom3D, target: Enemy3D, weapon: WeaponModel3D, dir: Vector3, d: float, room_y: float) -> void:
	var stand := target.global_position - dir * d
	stand.y = room_y + 0.10
	tower.player.global_position = stand
	_face(target)
	await _settle(4)
	_face(target)
	await _settle(1)
	var muzzle := weapon.get("_muzzle") as Marker3D
	var muzzle_pos: Vector3 = (
		muzzle.global_position
		if (muzzle != null and muzzle.is_inside_tree())
		else tower.player.global_position
	)
	var radius := _radius(target)
	var lateral := _lateral(muzzle_pos, target, dir)
	var real_hit := await _fire_real(target, weapon, dir)
	target.current_hp = target.max_hp
	var syn_hit := await _fire_syn(target, muzzle_pos, dir)
	target.current_hp = target.max_hp
	print("DIST %s kind=%s d=%.2f muzzle_lat=%.3f radius=%.3f REAL=%s SYN=%s shots=%s" % [
		room.room_id, target.enemy_kind, d, lateral, radius,
		("hit" if real_hit else "MISS"), ("hit" if syn_hit else "MISS"), _shot_summary(),
	])
	_shots.clear()


## 起点相对「过敌人中心、沿 dir 的轴」的横向垂直距离。
func _lateral(point: Vector3, target: Enemy3D, dir: Vector3) -> float:
	var rel: Vector3 = point - target.global_position
	rel.y = 0.0
	return (rel - dir * rel.dot(dir)).length()


func _shot_summary() -> String:
	if _shots.is_empty():
		return "none"
	var parts: Array[String] = []
	for value in _shots:
		var projectile := value as Node3D
		if projectile == null or not is_instance_valid(projectile):
			continue
		var direction: Vector3 = projectile.direction
		var dist: float = projectile.global_position.distance_to(projectile.global_position)
		parts.append("y=%.2f" % projectile.global_position.y)
		parts.append("dx=%.2f" % direction.x)
		parts.append("dz=%.2f" % direction.z)
		if dist > 0.0:
			parts.append("?")
	parts.append("n=%d" % _shots.size())
	return ",".join(parts)


func _fire_real(target: Enemy3D, weapon: WeaponModel3D, dir: Vector3) -> bool:
	_shots.clear()
	var before := target.current_hp
	var fired := false
	var attempts := 0
	while attempts < 8 and not fired:
		attempts += 1
		fired = weapon.try_fire(dir, tower.player)
		if not fired:
			await _settle(12)
	if not fired:
		return false
	for _index in 60:
		await get_tree().physics_frame
		if target.current_hp < before:
			return true
	return false


func _fire_syn(target: Enemy3D, origin: Vector3, dir: Vector3) -> bool:
	_shots.clear()
	if pool == null:
		return false
	var before := target.current_hp
	var projectile := pool.acquire({
		"direction": dir, "damage": 7, "hostile": false, "speed": 30.0,
		"shooter": tower.player, "tags": [] as Array[String],
	}, origin)
	for _index in 60:
		await get_tree().physics_frame
		if target.current_hp < before:
			return true
	if projectile != null and is_instance_valid(projectile):
		projectile.call("_retire")
	return false


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
