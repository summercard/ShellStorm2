extends Node
## 铺装结果验收：17 间房逐间检查「美术层是否接管、覆盖是否满、门洞是否通」。
##
## 门洞"通"的判据不是看有没有墙，而是**看门位格上放的是不是门墙模块**
## （`manor_wall_door`，净空 2.2m 居中）。放成实心护墙 = 门被堵死。
## 这条必须逐格核对，因为它是这套铺装唯一会造成"走过去撞墙"的失效。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const SEED := 77003244
const GRID := 5.0

var _failures: Array[String] = []
var _total_leaves := 0
var _total_ports := 0


func _ready() -> void:
	var tower := await _spawn()
	var rooms: Array = []
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		if room.room_id.begins_with("cr") or room.room_id.begins_with("conn_"):
			continue
		rooms.append(room)
	rooms.sort_custom(func(a, b): return str(a.room_id) < str(b.room_id))
	print("VERIFY_ROOMS %d" % rooms.size())
	var ok_count := 0
	for value in rooms:
		var room := value as DungeonRoom3D
		if _verify(room):
			ok_count += 1
	print("VERIFY_DONE ok=%d / %d  door_leaves=%d door_ports=%d"
		% [ok_count, rooms.size(), _total_leaves, _total_ports])
	# 全局：门扇不必等于门位（双端只建一端），但必须存在且覆盖大多数门位。
	_check(_total_leaves > 0, "全关卡没有任何门扇")
	_check(_total_leaves * 2 >= _total_ports,
		"门扇 %d 相对于门位 %d 过少（可能成片未生成）" % [_total_leaves, _total_ports])
	tower.queue_free()
	await get_tree().process_frame
	print("VERIFY_%s failures=%d"
		% ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("VERIFY_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify(room: DungeonRoom3D) -> bool:
	var room_id := room.room_id
	var art_loaded := bool(room.get_meta("art_layer_loaded", false))
	var floor_full := bool(room.get_meta("art_layer_floor_complete", false))
	var sides: Array = room.get_meta("art_layer_covered_sides", [])
	var floor_skip := bool(room.get_meta("procedural_floor_skipped", false))
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D

	_check(art_loaded, "%s: 运行时没加载美术层" % room_id)
	_check(floor_full, "%s: 地板没判定为铺满" % room_id)
	_check(sides.size() == 4, "%s: 只覆盖了 %d 面墙（应 4）" % [room_id, sides.size()])
	_check(floor_skip, "%s: 没跳过程序化地板（两层叠着）" % room_id)
	_check(art_root != null, "%s: 没有 AuthoredLayoutArtRoot" % room_id)
	if art_root == null:
		return false

	# 门洞：每个门位格必须放的是门墙模块
	var dim: Vector2 = room.call("get_dimensions")
	var door_count := 0
	for value in room.get("connection_ports"):
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		var lane := float(port.get("lane_m", 0.0))
		if side.is_empty():
			continue
		door_count += 1
		_total_ports += 1
		var door_walls := art_root.find_children("DoorWall_%s_*" % side, "Node3D", true, false)
		if door_walls.is_empty():
			_fail("%s: %s 面有门（lane %.1f）但美术层没有门墙模块 —— 门被实心墙堵死"
				% [room_id, side, lane])
			continue
		# 门墙的沿墙位置必须等于 lane
		var matched := false
		for node in door_walls:
			var along := (node as Node3D).position.x if side in ["north", "south"] else (node as Node3D).position.z
			if absf(float(along) - lane) < 0.01:
				matched = true
				break
		_check(matched, "%s: %s 面门墙位置与 lane %.1f 不符（门洞错位）"
			% [room_id, side, lane])

	# 实心墙不该出现在门位格上（与上一条互为交叉验证）
	for node in art_root.find_children("Wall_*", "Node3D", true, false):
		var name := str(node.name)
		var parts := name.split("_")
		if parts.size() < 3:
			continue
		var side := parts[1]
		var index := int(parts[2])
		var cells := _cells(dim, side)
		if index < 0 or index >= cells.size():
			continue
		var along := cells[index]
		for value in room.get("connection_ports"):
			var port := value as Dictionary
			if str(port.get("side", "")) != side:
				continue
			if absf(along - float(port.get("lane_m", 0.0))) < 0.01:
				_fail("%s: 门位格（%s 第 %d 格）放了实心墙 —— 门被堵死" % [room_id, side, index])

	# 门扇：**不按房间要求**。门是双端共享的，`_build_door_for_port()` 里
	# `owns_door_endpoint(side)` 让一端建、另一端不建（避免同一位置两扇门）。
	# 实测 n04 / reward_02 本房 0 扇，其门由相邻房与走廊提供 —— 这是设计，不是缺陷。
	# 真正的"过不去"只有一种成因：门位格被实心墙占住（上面逐格验过）。
	# 这里只统计本房门扇数，用于报告；全局总量在 `_ready()` 末尾核对。
	var door_leaves := room.find_children("*", "RoomDoor3D", true, false).size()
	_total_leaves += door_leaves

	# 美术件的可见性
	var total := 0
	var visible := 0
	for node in art_root.find_children("*", "Node3D", true, false):
		if not str(node.scene_file_path).contains("env_manor_"):
			continue
		total += 1
		if node.is_visible_in_tree():
			visible += 1
	_check(total > 0, "%s: 美术层里没有公馆件" % room_id)
	_check(visible == total, "%s: %d/%d 件公馆件不可见" % [room_id, visible, total])

	print("VERIFY_ROOM %-22s art=%-5s floor=%-5s sides=%d doors=%d leaves=%d manor=%d"
		% [room_id, art_loaded, floor_full, sides.size(), door_count, door_leaves, total])
	return total > 0 and visible == total and door_count > 0


func _cells(dim: Vector2, side: String) -> Array[float]:
	var length := dim.x if side in ["north", "south"] else dim.y
	var count := int(round(length / GRID))
	var out: Array[float] = []
	for index in range(count):
		out.append(-length * 0.5 + (float(index) + 0.5) * GRID)
	return out


func _spawn() -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
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


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)
