extends Node
## 远征03「程序化可搜索物件（BreakableClutter3D）」逐房清点探针。
##
## 回答一个具体问题：**每个房间到底还有没有？走廊还有没有？**
## 判据全部取运行时实例，不读配置猜。
##
## 用法：godot --headless --path . --scene res://tools/_exp03_clutter_room_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED_VALUE := 100990


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("PROBE_FAIL 不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame

	var rooms: Array = tower.get("_rooms") as Array
	print("PROBE_ROOMS %d" % rooms.size())

	var plan: Dictionary = {}
	var raw := FileAccess.get_file_as_string("res://data/level_plans/expedition_03/level_plan.json")
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		plan = ((parsed as Dictionary).get("interactive_clutter", {}) as Dictionary)
	print("PROBE_PLAN ", JSON.stringify(plan))

	var total := 0
	var search_total := 0
	var furniture_total := 0
	var zero_rooms: Array[String] = []
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	for _frame in 4:
		await get_tree().process_frame
		await get_tree().physics_frame

	var rows: Array[Dictionary] = []
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		var dims := room.get_dimensions()
		var items := _room_clutter(room)
		total += items.size()
		var furniture := _room_furniture(room)
		var searchable_count := 0
		var searchable_kinds: Array[String] = []
		for f in furniture:
			if f.searchable:
				searchable_count += 1
				searchable_kinds.append(str(f.furniture_type))
		furniture_total += furniture.size()
		search_total += searchable_count
		var slugs: Array[String] = []
		for item in items:
			slugs.append(str(item.get_meta("clutter_id", item.asset_id)))
		if items.is_empty():
			zero_rooms.append(room.room_id)
		rows.append({
			"room_id": room.room_id,
			"room_type": room.room_type,
			"dims": "%0.1fx%0.1f" % [dims.x, dims.y],
			"count": items.size(),
			"furniture": furniture.size(),
			"searchable": searchable_count,
			"excluded": (plan.get("exclude_room_types", []) as Array).has(room.room_type),
			"below_min_size": minf(dims.x, dims.y) < float(plan.get("min_room_size_m", 0.0)),
		})
		print("PROBE_ROOM %s type=%s dims=%0.1fx%0.1f clutter=%d furniture=%d searchable=%d kinds=%s" % [
			room.room_id, room.room_type, dims.x, dims.y, items.size(),
			furniture.size(), searchable_count, str(searchable_kinds)
		])

	# —— 走廊：主路 + 密道两条都要查 ——
	var corridor_clutter := 0
	var corridor_nodes := 0
	var corridors_root := tower.find_child("GeneratedCorridors", true, false)
	if corridors_root != null:
		for node in corridors_root.find_children("*", "", true, false):
			corridor_nodes += 1
			if node is BreakableClutter3D:
				corridor_clutter += 1
	print("PROBE_CORRIDOR nodes=%d clutter=%d (root=%s)" % [
		corridor_nodes, corridor_clutter, str(corridors_root != null)
	])

	print("PROBE_TOTAL clutter=%d rooms=%d zero=%d %s" % [
		total, rows.size(), zero_rooms.size(), str(zero_rooms)
	])
	print("PROBE_SEARCHABLE total_furniture=%d searchable=%d" % [furniture_total, search_total])
	print("PROBE_DONE")
	get_tree().quit(0)


func _room_clutter(room: DungeonRoom3D) -> Array[BreakableClutter3D]:
	var result: Array[BreakableClutter3D] = []
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter != null and room.is_ancestor_of(clutter):
			result.append(clutter)
	return result


func _room_furniture(room: DungeonRoom3D) -> Array[RoomFurniture3D]:
	var result: Array[RoomFurniture3D] = []
	for node in room.find_children("*", "", true, false):
		var furniture := node as RoomFurniture3D
		if furniture != null and is_instance_valid(furniture) and not furniture.is_queued_for_deletion():
			result.append(furniture)
	return result
