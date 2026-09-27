extends Node3D
## 诊断（只读）：把 room_01/02/10 的「地砖格心集合」与「实心墙局部位置」打成 ASCII 图，
## 并标出坑区矩形、实际刷怪落点、敌人落点。只打印，不改产品代码。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const ROOMS := ["room_01", "room_02", "room_10"]

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(20)
	for rid in ROOMS:
		await _dump(tower._room_by_id.get(rid) as DungeonRoom3D)
	print("RG_DONE")
	get_tree().quit(0)


func _dump(room: DungeonRoom3D) -> void:
	if room == null:
		return
	room.set_stream_state(DungeonRoom3D.STREAM_SHELL_READY)
	await _settle(4)
	var dim := room.get_dimensions()
	var cols := maxi(1, int(round(dim.x / 5.0)))
	var rows := maxi(1, int(round(dim.y / 5.0)))
	var origin := Vector2(-dim.x * 0.5 + 2.5, -dim.y * 0.5 + 2.5)
	print("RG_ROOM %s dim=(%.0f,%.0f) shell=%s tiles=%d walls=%d doors=%d corners=%d multi=%d" % [
		room.room_id, dim.x, dim.y, str(room.authored_layout_shell),
		_count(room, "floor_tile", ""), _count(room, "solid_wall", ""),
		_count(room, "door_wall", ""), _count(room, "corner_l", ""),
		_count(room, "multi_level_component", ""),
	])
	# 网格：T=主地砖格心  W=实心墙/门墙/角件占格  p=坑件占格  c=刷怪候选  .=空
	var cells := {}
	for value in room._authored_tile_cells:
		var cell := value as Vector3
		cells[_key(cell, origin)] = "T"
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		var pos := instance.get("position", Vector3.ZERO) as Vector3
		var mark := ""
		if role == "multi_level_component":
			mark = "p"
		elif role in ["solid_wall", "door_wall", "corner_l"]:
			mark = "W"
		if not mark.is_empty():
			var k := _key(pos, origin)
			if not cells.has(k):
				cells[k] = mark
	for value in room._spawn_candidates:
		var cand := value as Vector3
		var k := _key(cand, origin)
		if not cells.has(k):
			cells[k] = "c"
		else:
			cells[k] = "C"
	for r in rows:
		var line := ""
		for c in cols:
			line += str(cells.get(Vector2i(c, r), "."))
		print("RG_ROW %s r=%02d %s" % [room.room_id, r, line])
	# 实心墙的实际碰撞体位置（局部，取每个 wall 件的实例位置）
	var wall_positions: Array[String] = []
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		if role not in ["solid_wall", "door_wall", "corner_l"]:
			continue
		var pos := instance.get("position", Vector3.ZERO) as Vector3
		wall_positions.append("%s(%.1f,%.1f)" % [role.substr(0, 1), pos.x, pos.z])
	print("RG_WALLS %s %s" % [room.room_id, " ".join(wall_positions)])


func _count(room: DungeonRoom3D, role: String, part: String) -> int:
	var n := 0
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		if str(instance.get("slot_role", "")) != role:
			continue
		if not part.is_empty() and str(instance.get("part", "")) != part:
			continue
		n += 1
	return n


func _key(local: Vector3, origin: Vector2) -> Vector2i:
	return Vector2i(int(round((local.x - origin.x) / 5.0)), int(round((local.z - origin.y) / 5.0)))


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
