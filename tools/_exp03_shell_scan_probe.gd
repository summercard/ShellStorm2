extends Node
## 扫描远征03 每间真房间的精确壳体参数：尺寸、四面的门位 lane、门宽。
##
## 为什么要这份数据：墙件必须按 lane 放 `manor_wall_door`，放成实心 `manor_wall_standard`
## 会把门洞堵死（实心件 `collision_owner: self`）。lane 是相对房间中心的沿墙偏移，
## 与 5m 网格的对应关系决定了「哪一块墙换成门墙」。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEEDS := [77003244]
const GRID := 5.0


func _ready() -> void:
	for seed_value in SEEDS:
		var tower := await _spawn(seed_value)
		print("SCAN_SEED %d" % seed_value)
		var rooms: Array = []
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room == null or not room.procedural_shell:
				continue
			if _is_corridor(room):
				continue
			rooms.append(room)
		rooms.sort_custom(func(a, b): return str(a.room_id) < str(b.room_id))
		for value in rooms:
			var room := value as DungeonRoom3D
			_dump(room)
		tower.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)


func _dump(room: DungeonRoom3D) -> void:
	var dim: Vector2 = room.call("get_dimensions")
	var ports: Array = room.get("connection_ports")
	var by_side := {}
	for value in ports:
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		if side.is_empty():
			continue
		if not by_side.has(side):
			by_side[side] = []
		by_side[side].append({
			"lane": float(port.get("lane_m", 0.0)),
			"width": float(port.get("door_width_m", 0.0)),
			"open": bool(port.get("open_passage", false)),
			"target": str(port.get("target", port.get("target_room_id", ""))),
		})
	# 每个 side 上「格心位置」与 lane 的对应：砖心 = -half + (i+0.5)*GRID，相对中心 = -half + (i+0.5)*GRID
	var cols := int(round(dim.x / GRID))
	var rows := int(round(dim.y / GRID))
	var cell_x: Array[float] = []
	for i in range(cols):
		cell_x.append(-dim.x * 0.5 + (float(i) + 0.5) * GRID)
	var cell_z: Array[float] = []
	for i in range(rows):
		cell_z.append(-dim.y * 0.5 + (float(i) + 0.5) * GRID)
	var sides: Array[String] = ["north", "south", "west", "east"]
	var door_slots := {}
	for side in sides:
		var lanes: Array[float] = []
		for entry in by_side.get(side, []):
			lanes.append(float(entry["lane"]))
		door_slots[side] = lanes
	print("ROOM %s type=%s size=%.0fx%.0f grid=%.0fx%.0f" % [
		room.room_id, str(room.room_type), dim.x, dim.y, cols, rows])
	print("  doors=%s" % JSON.stringify(_port_brief(by_side)))
	print("  cell_x=%s cell_z=%s" % [str(cell_x), str(cell_z)])
	# 每个 side 上：哪些格心要换门墙（lane 落在该格心 ±半格内）
	var plan := {}
	for side in sides:
		var need: Array[int] = []
		var lanes: Array = door_slots[side]
		var cells: Array = cell_x if side in ["north", "south"] else cell_z
		for lane_value in lanes:
			var lane := float(lane_value)
			for index in range(cells.size()):
				if absf(float(cells[index]) - lane) < GRID * 0.5 - 0.01:
					if not need.has(index):
						need.append(index)
		plan[side] = need
	print("  door_cells=%s" % JSON.stringify(plan))


func _port_brief(by_side: Dictionary) -> Dictionary:
	var out := {}
	for side in by_side.keys():
		var parts: Array[String] = []
		for entry in by_side[side]:
			parts.append("lane=%.2f w=%.2f open=%s" % [
				float(entry["lane"]), float(entry["width"]), str(entry["open"])])
		out[side] = parts
	return out


func _is_corridor(room: DungeonRoom3D) -> bool:
	var id := room.room_id
	return id.begins_with("cr") or id.begins_with("conn_")


func _spawn(seed_value: int) -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", seed_value)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower
