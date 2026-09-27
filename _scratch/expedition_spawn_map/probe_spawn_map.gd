extends Node
## 只读探针：dump 远征关卡01 每个房间的**刷怪落点**（运行时真值）。
## 判据全部取运行时对象：房间实例来自 Dungeon3D._rooms，落点来自
## DungeonRoom3D.spawn_point_for_index()（与 _spawn_enemy_batch 同一条路径）。
## 输出：res://_scratch/expedition_spawn_map/spawn_map.json

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const OUT_PATH := "res://_scratch/expedition_spawn_map/spawn_map.json"
const SEEDS: Array[int] = [77001199]
const MAX_SPAWN_INDEX := 16


func _ready() -> void:
	print("[probe] boot")
	var payload: Dictionary = {"seeds": []}
	for seed_value in SEEDS:
		payload["seeds"].append(await _dump_seed(seed_value))
	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 %s" % OUT_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("[probe] SPAWN_MAP_DONE %s" % OUT_PATH)
	get_tree().quit(0)


func _dump_seed(seed_value: int) -> Dictionary:
	var packed: PackedScene = load(EXPEDITION_SCENE) as PackedScene
	var tower: Node = packed.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", seed_value)
	add_child(tower)
	for _index in range(12):
		await get_tree().process_frame
		await get_tree().physics_frame
	print("[probe] tower ready")
	var snapshot: Dictionary = (tower.get("_floor_plan_snapshots") as Dictionary).get(0, {})
	var spec_by_id: Dictionary = {}
	for value in snapshot.get("rooms", []):
		var spec: Dictionary = value as Dictionary
		spec_by_id[str(spec.get("id", ""))] = spec
	var theme: Resource = tower.get("visual_theme")
	var floor: int = maxi(1, int(theme.get("difficulty_rank")))
	var injector: RefCounted = tower.get("_monster_injector")
	var records: Array = tower.get("_records")
	var rooms: Array = tower.get("_rooms")
	var out_rooms: Array = []
	for room in rooms:
		if room == null:
			continue
		var record_index: int = int(tower.call("_record_index", str(room.get("room_id"))))
		var floor_level: int = clampi(
			int(float(record_index) / maxf(1.0, float(records.size() - 1)) * 3.0), 0, 3
		)
		out_rooms.append(_dump_room(room, spec_by_id, injector, floor, floor_level, seed_value, tower))
		print("[probe]   room %s done" % str(room.get("room_id")))
	var result: Dictionary = {
		"seed": seed_value,
		"level_id": str(snapshot.get("level_id", "expedition_01")),
		"layout_id": str(snapshot.get("layout_id", "")),
		"used_fallback": bool(snapshot.get("used_fallback", false)),
		"theme_id": str(theme.get("theme_id")),
		"difficulty_rank": floor,
		"room_count": out_rooms.size(),
		"rooms": out_rooms,
	}
	tower.queue_free()
	await get_tree().process_frame
	return result


func _dump_room(
	room: Node, spec_by_id: Dictionary, injector: RefCounted,
	floor: int, floor_level: int, run_seed: int, tower: Node
) -> Dictionary:
	var rid: String = str(room.get("room_id"))
	var dimensions: Vector2 = room.call("get_dimensions")
	var origin: Vector3 = room.global_position
	var yaw_deg: float = rad_to_deg(room.global_rotation.y)
	var local_cells: Array = []
	var world_cells: Array = []
	for value in room.get("_authored_tile_cells"):
		var cell: Vector3 = value as Vector3
		local_cells.append(_v2(cell))
		var world_cell: Vector3 = room.to_global(cell)
		world_cells.append(_v2(world_cell))
	var doors: Array = []
	var door_nodes: Dictionary = room.get("_door_nodes")
	var door_targets: Dictionary = room.get("door_targets")
	for direction in room.get("doors"):
		var node: Node3D = door_nodes.get(str(direction)) as Node3D
		var door_local: Vector3 = Vector3.ZERO
		if node != null:
			door_local = node.position
		doors.append({
			"dir": str(direction),
			"target": str(door_targets.get(str(direction), "")),
			"local": _v2(door_local),
		})
	var points: Array = []
	for index in range(MAX_SPAWN_INDEX):
		var point: Vector3 = room.call("spawn_point_for_index", index)
		if not point.is_finite():
			break
		var point_local: Vector3 = room.to_local(point)
		points.append({
			"index": index,
			"local": _v2(point_local),
			"world": _v2(point),
		})
	var spec: Dictionary = spec_by_id.get(rid, {})
	var spawn_plan: Dictionary = spec.get("enemy_spawn_plan", {}) as Dictionary
	var waves: Array = []
	for wave_value in spawn_plan.get("waves", []):
		var wave: Dictionary = wave_value as Dictionary
		waves.append({
			"pool": wave.get("pool", []),
			"kinds": wave.get("kinds", {}),
			"count": wave.get("count", {}),
			"monsters": wave.get("monsters", []),
		})
	var rolled: Array = []
	if injector != null and not waves.is_empty():
		var built: Array = injector.call(
			"build_waves_from_plan", spawn_plan, floor, floor_level, run_seed + rid.hash()
		)
		for wave_batch in built:
			var entries: Array = []
			for enemy_value in (wave_batch as Array):
				var enemy: Dictionary = enemy_value as Dictionary
				entries.append({
					"type": str(enemy.get("enemy_type", "?")),
					"name": str(enemy.get("name", "?")),
					"hp": int(enemy.get("hp", 0)),
					"damage": int(enemy.get("damage", 0)),
				})
			rolled.append(entries)
	var alive_map: Dictionary = tower.get("_alive_by_room")
	var wave_total_map: Dictionary = tower.get("_room_wave_totals")
	var enemy_nodes_map: Dictionary = tower.get("_enemy_nodes_by_room")
	var runtime_enemies: Array = []
	for node_value in (enemy_nodes_map.get(rid, []) as Array):
		var enemy: Node = node_value as Node
		if enemy == null or not is_instance_valid(enemy):
			continue
		var ep: Vector3 = (enemy as Node3D).global_position
		var el: Vector3 = room.to_local(ep)
		runtime_enemies.append({
			"kind": str(enemy.get("enemy_kind")),
			"world": _v2(ep),
			"local": _v2(el),
		})
	var boss_probe: Array = []
	if room.get("room_type") == "BOSS" and injector != null:
		boss_probe = injector.call("generate_enemies", {
			"type": "boss", "floor": floor, "floor_level": floor_level,
			"floor_number": maxi(1, int(room.get_meta("floor_number", floor))),
			"boss_content_id": str(room.get_meta("boss_content_id", "")),
		})
	return {
		"room_id": rid,
		"room_key": str(spec.get("key", rid)),
		"role": str(spec.get("role", "")),
		"room_type": str(room.get("room_type")),
		"content_type": str(spec.get("content_type", "")),
		"size_class": str(room.get("size_class")),
		"is_main_path": bool(room.get("is_main_path")),
		"peaceful": bool(room.get("authored_layout_peaceful")),
		"floor_level": floor_level,
		"dimensions": [snappedf(dimensions.x, 0.001), snappedf(dimensions.y, 0.001)],
		"origin": _v2(origin),
		"yaw_deg": snappedf(yaw_deg, 0.01),
		"tile_cells_local": local_cells,
		"tile_cells_world": world_cells,
		"doors": doors,
		"spawn_points": points,
		"spawn_plan_waves": waves,
		"rolled_waves": rolled,
		"runtime_alive": int(alive_map.get(rid, 0)),
		"runtime_wave_total": int(wave_total_map.get(rid, 0)),
		"runtime_enemies": runtime_enemies,
		"boss_probe_count": boss_probe.size(),
		"boss_probe_kinds": [str((boss_probe[0] as Dictionary).get("enemy_type", "")) if not boss_probe.is_empty() else ""],
	}


func _v2(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.z, 0.001)]
