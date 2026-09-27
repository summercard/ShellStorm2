extends Node3D
## 诊断 v2（只读）：坑位矩形**从 pit_floor_tile 实测反推**，不假设朝向。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	if tower.player != null:
		tower.player.global_position = Vector3(0.0, 500.0, 0.0)
		tower.player.set_physics_process(false)
	await _settle(3)
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		_dump(tower._room_by_id[id_value] as DungeonRoom3D)
	print("B2_PROBE_DONE")
	get_tree().quit(0)


func _dump(room: DungeonRoom3D) -> void:
	if room == null:
		return
	var id := room.room_id
	var dim := room.get_dimensions()
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	var role_counts := {}
	var pit_rect := Rect2()
	var have_pit := false
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		if role == "multi_level_component" and str(instance.get("part", "")) == "pit_floor_tile":
			var pos := instance.get("position", Vector3.ZERO) as Vector3
			var tile := Rect2(pos.x - 2.5, pos.z - 2.5, 5.0, 5.0)
			pit_rect = tile if not have_pit else pit_rect.merge(tile)
			have_pit = true
	print("B2_ROOM %s dim=(%.0f,%.0f) roles=%s pit=%s" % [
		id, dim.x, dim.y, str(role_counts),
		("(%.1f,%.1f %.1fx%.1f)" % [pit_rect.position.x, pit_rect.position.y, pit_rect.size.x, pit_rect.size.y]) if have_pit else "none",
	])
	if not have_pit:
		return
	var cells := room._authored_tile_cells as Array
	var tiles_in_pit := 0
	for cell_value in cells:
		var cell := cell_value as Vector3
		if pit_rect.has_point(Vector2(cell.x, cell.z)):
			tiles_in_pit += 1
	var cands := room._spawn_candidates as Array
	var cand_in_pit := 0
	var cand_in_pit_bad := 0
	for cand_value in cands:
		var cand := cand_value as Vector3
		if pit_rect.has_point(Vector2(cand.x, cand.z)):
			cand_in_pit += 1
			if not room._spawn_floor_contains(cand, room._spawn_clearance()):
				cand_in_pit_bad += 1
	print("B2_PIT %s tiles_total=%d tiles_in_pit=%d cands_total=%d cands_in_pit=%d cands_in_pit_uncovered=%d" % [
		id, cells.size(), tiles_in_pit, cands.size(), cand_in_pit, cand_in_pit_bad,
	])
	# 真刷一波，看落点是否进坑
	_free_room_enemies(id)
	tower._spawned_rooms.erase(id)
	tower._room_spawn_blocked.erase(id)
	tower._alive_by_room[id] = 0
	tower._room_wave_queues[id] = []
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	await _settle(3)
	if not tower._prepare_revealed_hostile_room(room):
		print("B2_SPAWN %s skipped" % id)
		return
	await _settle(150)
	var n := 0
	var in_pit := 0
	var min_y := 9999.0
	for value in _live(id):
		var enemy := value as Enemy3D
		n += 1
		min_y = minf(min_y, enemy.global_position.y)
		var local := Vector2(
			enemy.global_position.x - room.global_position.x,
			enemy.global_position.z - room.global_position.z
		)
		var is_in := pit_rect.has_point(local)
		if is_in:
			in_pit += 1
		print("B2_ENEMY %s kind=%s y=%.2f local=(%.1f,%.1f) pit=%s" % [
			id, enemy.enemy_kind, enemy.global_position.y, local.x, local.y, str(is_in),
		])
	print("B2_RESULT %s live=%d in_pit=%d min_y=%.2f" % [id, n, in_pit, min_y])


func _live(room_id: String) -> Array:
	var out: Array = []
	for value in tower._enemy_nodes_by_room.get(room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			out.append(enemy)
	return out


func _free_room_enemies(room_id: String) -> void:
	for value in tower._enemy_nodes_by_room.get(room_id, []):
		var node := value as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	tower._enemy_nodes_by_room[room_id] = []


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
