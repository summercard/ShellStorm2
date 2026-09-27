extends Node3D
## 诊断（只读）：① 逐房地面高度图（找 y=0 上的洞）；② 敌人落地审计 ——
## 用**玩家枪口高度的水平射线**测命中（这才是子弹的真实路径），而不是敌人自身高度。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOMS := ["room_01", "room_02", "room_10", "room_03", "room_05", "room_08"]
const CHEST_OFFSET_Y := 0.458

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	for rid in ROOMS:
		var room := tower._room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		await _map_room(room)
	for rid in ROOMS:
		var room := tower._room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		await _audit(room)
	print("SL_DONE")
	get_tree().quit(0)


func _map_room(room: DungeonRoom3D) -> void:
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	await _settle(4)
	var dim := room.get_dimensions()
	var cols := maxi(1, int(round(dim.x / 5.0)))
	var rows := maxi(1, int(round(dim.y / 5.0)))
	print("SL_MAP %s dim=(%.0f,%.0f) shell=%s cols=%d rows=%d" % [
		room.room_id, dim.x, dim.y, str(room.authored_layout_shell), cols, rows,
	])
	for r in rows:
		var line := ""
		for c in cols:
			var lx := -dim.x * 0.5 + 2.5 + float(c) * 5.0
			var lz := -dim.y * 0.5 + 2.5 + float(r) * 5.0
			line += _cell_symbol(room, Vector3(lx, 3.0, lz))
		print("SL_ROW %s r=%02d %s" % [room.room_id, r, line])


func _cell_symbol(room: DungeonRoom3D, local: Vector3) -> String:
	var from := room.to_global(local)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -60.0, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "."
	var rel_y := float(hit.get("position").y) - room.global_position.y
	if absf(rel_y) < 0.8:
		return "0"
	if rel_y < -3.0:
		return "-"
	return "?"


func _audit(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	await _settle(6)
	var player := tower.player
	if player == null:
		return
	var body := player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(90)
	var weapon := player.weapon as WeaponModel3D
	var muzzle := weapon.get("_muzzle") as Marker3D if weapon != null else null
	var chest_y: float = (
		muzzle.global_position.y
		if muzzle != null and muzzle.is_inside_tree()
		else player.global_position.y + CHEST_OFFSET_Y
	)
	var live := _live(room.room_id)
	var pl := room.to_local(player.global_position)
	print("SL_AUDIT %s enemies=%d chest_y=%.3f player_local=(%.1f,%.1f)" % [
		room.room_id, live.size(), chest_y, pl.x, pl.z,
	])
	for value in live:
		var enemy := value as Enemy3D
		var epos := enemy.global_position
		var el := room.to_local(epos)
		var floor_rel := _floor_rel(room, epos)
		var flat := Vector2(epos.x - player.global_position.x, epos.z - player.global_position.z)
		var dist := flat.length()
		var hit_note := _shoot_note(player.global_position, chest_y, epos, enemy)
		print("SL_ENEMY %s kind=%s local=(%.1f,%.1f) rel_y=%.2f floor_rel=%.2f dist=%.2f face=%s hit=%s" % [
			room.room_id, enemy.enemy_kind, el.x, el.z, epos.y - room.global_position.y,
			floor_rel, dist, _face_note(enemy), hit_note,
		])


func _floor_rel(room: DungeonRoom3D, world_point: Vector3) -> float:
	var from := Vector3(world_point.x, world_point.y + 4.0, world_point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -60.0, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 99.0
	return float(hit.get("position").y) - room.global_position.y


## 沿「玩家 → 敌人」水平方向，从枪口高度打一条射线（mask 5）——这就是子弹真实路径。
func _shoot_note(player_pos: Vector3, chest_y: float, epos: Vector3, enemy: Enemy3D) -> String:
	var from := Vector3(player_pos.x, chest_y, player_pos.z)
	var flat := Vector3(epos.x - from.x, 0.0, epos.z - from.z)
	if flat.length_squared() < 0.0001:
		return "same_cell"
	var to := from + flat.normalized() * (flat.length() + 2.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 5
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "none"
	var collider: Variant = hit.get("collider")
	if collider == enemy:
		return "HIT@%.2f" % from.distance_to(hit.get("position"))
	var node := collider as Node3D
	var pos_text := "?"
	if node != null:
		var lp := node.global_position
		pos_text = "(%.1f,%.1f,%.2f)" % [lp.x, lp.y, lp.z]
	return "BLOCKED_by=%s@%.2f at%s" % [
		str(node.name) if node != null else "?", from.distance_to(hit.get("position")), pos_text,
	]


func _face_note(enemy: Enemy3D) -> String:
	var avatar := enemy.avatar if enemy != null else null
	if avatar == null:
		return "no_avatar"
	return "pm=%d vis=%s scale=%.2f" % [
		enemy.process_mode, str(enemy.visible), avatar.scale.x,
	]


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
