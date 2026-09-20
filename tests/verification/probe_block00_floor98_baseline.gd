extends Node
## 探针：实测 98F（floor_index=2）「基线现状」—— 把区块00 固定布局接进去之前，
## 先钉死这几件事：
##   1. 98F 的 plan snapshot 房间表（区块00 要整层替换它，必须先看见它的真实 schema）。
##   2. 各房间 record 的**世界坐标**与门向，用来确认坐标换算与门洞方位。
##   3. 98F 实际装配出来的 DungeonRoom3D 节点：尺寸、门、走的是哪套壳体
##      （v007 安全房整房旋转 vs 通用 _build_tower_wall_v2 5m 拼装）。
##   4. 每个 Door 子节点的世界坐标（99→98 楼梯的下端落点就是入口房东门）。
## 只读运行时节点树与内存字典，不读 .blend / .glb 源文件。

const FLOOR_INDEX := 2
const FLOOR_NUMBER := 98
const SEED := 990098


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await _settle()

	_dump_plan(tower)
	_dump_records(tower)
	_dump_edges(tower)
	_dump_rooms(tower)
	_dump_stage(tower)

	print("\nPROBE_DONE")
	get_tree().quit(0)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _dump_plan(tower: Node) -> void:
	print("\n########## 98F PLAN SNAPSHOT (floor_index=%d) ##########" % FLOOR_INDEX)
	var snaps: Dictionary = tower.get("_floor_plan_snapshots")
	if not snaps.has(FLOOR_INDEX):
		print("-- MISSING: 该层无 plan snapshot")
		return
	var plan := snaps[FLOOR_INDEX] as Dictionary
	print("-- plan keys = %s" % str(plan.keys()))
	print("-- layout_id=%s layout_variant=%s entry_side=%s exit_side=%s valid=%s" % [
		str(plan.get("layout_id", "")), str(plan.get("layout_variant", "")),
		str(plan.get("entry_side", "")), str(plan.get("exit_side", "")),
		str(plan.get("valid", false)),
	])
	print("-- main_path_keys = %s" % str(plan.get("main_path_keys", [])))
	var rooms: Array = plan.get("rooms", [])
	print("-- rooms count = %d" % rooms.size())
	for room_value in rooms:
		var room := room_value as Dictionary
		print("   RAW %s" % str(room))


func _dump_records(tower: Node) -> void:
	print("\n########## 98F RECORDS (world positions) ##########")
	var records: Dictionary = tower.get("_records")
	var by_id: Dictionary = {}
	for record_value in records:
		var r := record_value as Dictionary
		by_id[str(r.get("id", ""))] = r
	var floor_rooms: Dictionary = tower.get("_floor_room_ids")
	var ids: Array = floor_rooms.get(FLOOR_INDEX, [])
	print("-- _floor_room_ids[%d] = %s" % [FLOOR_INDEX, str(ids)])
	for room_id_value in ids:
		var room_id := str(room_id_value)
		var record := by_id.get(room_id) as Dictionary
		if record == null:
			print("   id=%-16s RECORD MISSING" % room_id)
			continue
		print("   id=%-16s type=%-12s role=%-12s" % [
			room_id, str(record.get("type", "")), str(record.get("role", "")),
		])
		print("      position=%s dims=%s parent=%s" % [
			str(record.get("position", Vector3.ZERO)),
			str(record.get("custom_dimensions", Vector2.ZERO)),
			str(record.get("parent", "")),
		])
		print("      doors=%s targets=%s open_wall=%s" % [
			str(record.get("doors", [])), str(record.get("door_targets", {})),
			str(record.get("open_wall_directions", [])),
		])


func _dump_edges(tower: Node) -> void:
	print("\n########## 98F EDGES / SIDES ##########")
	for key in ["_declared_edges", "_edge_side_by_key", "_edge_door_sides_by_key",
			"_edge_kind_by_key", "_descent_side_sequence", "_floor_seed_gate_edges",
			"_generated_floor_indices"]:
		print("-- %s = %s" % [key, str(tower.get(key))])


func _dump_rooms(tower: Node) -> void:
	print("\n########## 98F ACTUAL DungeonRoom3D NODES ##########")
	var room_by_id: Dictionary = tower.get("_room_by_id")
	for room_id_value in room_by_id.keys():
		var room := room_by_id[room_id_value] as DungeonRoom3D
		if room == null:
			continue
		var floor_index := int((tower.get("_room_floor_index") as Dictionary).get(
			str(room_id_value), -1
		))
		if floor_index != FLOOR_INDEX:
			continue
		print("   room %s pos=%s dims=%s type=%s doors=%s" % [
			str(room.room_id), str(room.global_position), str(room.get_dimensions()),
			str(room.room_type), str(room.doors),
		])
		print("      safe_room_art_version=%s corner_l=%s wall_module_count=%s" % [
			str(room.get_meta("safe_room_art_version", "<none>")),
			str(room.get_meta("safe_room_corner_l", "<none>")),
			str(room.get_meta("safe_room_wall_module_count", "<none>")),
		])
		for door_value in room.get_children():
			var door := door_value as RoomDoor3D
			if door != null:
				print("      DOOR[%s] pos=%s open=%s rot_y=%.3f" % [
					str(door.name), str(door.global_position), str(door.is_open),
					door.global_rotation.y,
				])
		# 壳体构件清点：L 角件 / 实墙 / 门墙
		var corner := 0
		var solid := 0
		var doorwall := 0
		for value in room.find_children("*", "", true, false):
			var n := str(value.name)
			if n.begins_with("CornerL"):
				corner += 1
			elif n.begins_with("TowerWallSolid") or n.begins_with("Imported_Wall5M"):
				solid += 1
			elif n.begins_with("Imported_DoorWall5M"):
				doorwall += 1
		print("      SHELL corner_l=%d solid=%d door_wall=%d" % [corner, solid, doorwall])


func _dump_stage(tower: Node) -> void:
	print("\n########## 98F STAGE ##########")
	var stages: Dictionary = tower.get("_floor_stages")
	var stage := stages.get(FLOOR_INDEX) as Node3D
	if stage == null:
		print("-- stage: MISSING（该层壳体未构建）")
		return
	print("-- node=%s position=%s" % [stage.name, str(stage.position)])
	print("   meta floor_number=%s block_id=%s" % [
		str(stage.get_meta("floor_number", "<none>")), str(stage.get_meta("block_id", "<none>")),
	])
	for key in ["_tile_count", "_support_rect_count"]:
		print("   %s=%s" % [key, str(stage.get(key))])
