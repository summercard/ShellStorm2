extends Node3D
## 端到端实证（只读）：玩家站桥面房心 → 真实武器朝每只怪实弹射击 → 记命中/发数；
## 再把玩家挪到「怪同侧」作对照。用于证明「怪在护栏另一侧时子弹打不到」。
## spread 临时置 0，隔离几何因素；射击结束还原。只打印，不改产品代码。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOMS := ["room_01", "room_02", "room_10", "room_03", "room_05"]
const SHOTS := 8

var tower: TowerDescent3D
var _spawned: Node = null


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	for rid in ROOMS:
		await _case(tower._room_by_id.get(rid) as DungeonRoom3D)
	print("LF_DONE")
	get_tree().quit(0)


func _case(room: DungeonRoom3D) -> void:
	if room == null:
		return
	tower.force_enter_room_for_test(room.room_id)
	await _settle(6)
	var player := tower.player
	if player == null:
		return
	var body := player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(60)
	var weapon := player.weapon as WeaponModel3D
	if weapon == null:
		return
	if not weapon.projectile_spawned.is_connected(_on_spawned):
		weapon.projectile_spawned.connect(_on_spawned)
	var saved_spread := weapon.spread
	weapon.spread = 0.0
	var live := _live(room.room_id)
	print("LF_CASE %s enemies=%d player_local=(%.1f,%.1f) spread0=1" % [
		room.room_id, live.size(),
		room.to_local(player.global_position).x, room.to_local(player.global_position).z,
	])
	for value in live:
		var enemy := value as Enemy3D
		var epos := enemy.global_position
		var from_center := await _shoot(player, weapon, enemy)
		# 对照：把玩家挪到怪的同一侧 4 m 处
		var dir := (epos - player.global_position)
		dir.y = 0.0
		var side_ok := dir.length_squared() > 0.01
		var hits_side := -1
		if side_ok:
			var stand: Vector3 = epos - dir.normalized() * 4.0
			stand.y = room.global_position.y + 0.10
			player.global_position = stand
			if body != null:
				body.velocity = Vector3.ZERO
			await _settle(12)
			enemy = _reacquire(room, enemy)
			if enemy != null:
				hits_side = await _shoot(player, weapon, enemy)
			# 回房心
			player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
			if body != null:
				body.velocity = Vector3.ZERO
			await _settle(12)
		var el := room.to_local(epos)
		print("LF_ENEMY %s kind=%s local=(%.1f,%.1f) from_center=%d/%d same_side=%s" % [
			room.room_id, enemy.enemy_kind if enemy != null else "?", el.x, el.z,
			from_center, SHOTS, ("%d/%d" % [hits_side, SHOTS]) if hits_side >= 0 else "n/a",
		])
	weapon.spread = saved_spread


func _shoot(player: Node3D, weapon: WeaponModel3D, enemy: Enemy3D) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return -1
	var hits := 0
	for _index in SHOTS:
		enemy = _reacquire(null, enemy)
		if enemy == null:
			break
		enemy.current_hp = enemy.max_hp
		var dir := enemy.global_position - player.global_position
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		player.aim_direction = dir
		player.look_at(player.global_position + dir, Vector3.UP)
		var before := enemy.current_hp
		var fired := false
		var attempts := 0
		while attempts < 10 and not fired:
			attempts += 1
			fired = weapon.try_fire(dir, player)
			if not fired:
				await _settle(8)
		if not fired:
			continue
		for _frame in 60:
			await get_tree().physics_frame
			if not is_instance_valid(enemy) or enemy.ai_state == "dead":
				break
			if enemy.current_hp < before:
				hits += 1
				break
		await _settle(2)
	return hits


func _reacquire(room: DungeonRoom3D, enemy: Enemy3D) -> Enemy3D:
	if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
		return enemy
	var rid := enemy.room_id if enemy != null else ""
	var pool := tower._enemy_nodes_by_room.get(rid, []) as Array
	for value in pool:
		var candidate := value as Enemy3D
		if candidate != null and is_instance_valid(candidate) and candidate.ai_state != "dead":
			return candidate
	return null


func _on_spawned(projectile: Node) -> void:
	_spawned = projectile


func _live(room_id: String) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			out.append(enemy)
	return out


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
