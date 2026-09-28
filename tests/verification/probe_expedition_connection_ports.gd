extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, RUN_SEED)
	_check(not bool(plan.get("used_fallback", true)), "显式端口版图不得回退旧样例")
	_check(bool(plan.get("valid", false)), "显式端口版图必须通过校验")
	var room_01_spec := _plan_room(plan, "room_01")
	_check(is_equal_approx(float(room_01_spec.get("rotation_deg", -1.0)), 270.0), "room01 应由端口求解为 270°")

	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _index in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	_check(block != null, "运行时必须生成远征区块")
	var rooms := _collect_rooms(block)
	_check(rooms.size() == 13, "运行时必须生成 13 间房")
	var unique_doors := {}
	var checked_edges := {}
	for room_value in rooms.values():
		var room := room_value as DungeonRoom3D
		var port_root := room.find_child("ConnectionPorts", true, false) as Node3D
		_check(port_root != null, "%s 缺少 ConnectionPorts" % room.room_id)
		if port_root != null:
			_check(
				port_root.get_child_count() == room.connection_ports.size(),
				"%s 端口 Marker 数量不匹配" % room.room_id
			)
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var port_id := str(port.get("port_id", ""))
			var target_id := str(port.get("target_room_id", ""))
			_check(not port_id.is_empty(), "%s 存在空端口编号" % room.room_id)
			if port_root != null:
				_check(
					port_root.get_node_or_null("Port_%s" % port_id) != null,
					"%s-%s 缺少 Marker3D" % [room.room_id, port_id]
				)
			if target_id.is_empty():
				continue
			var edge := _edge_key(room.room_id, target_id)
			if checked_edges.has(edge):
				continue
			checked_edges[edge] = true
			var peer := rooms.get(target_id) as DungeonRoom3D
			_check(peer != null, "%s 指向不存在的房间 %s" % [room.room_id, target_id])
			if peer == null:
				continue
			var reciprocal := peer.get_connection_port_towards(room.room_id)
			_check(not reciprocal.is_empty(), "%s 缺少回指 %s 的端口" % [target_id, room.room_id])
			if reciprocal.is_empty():
				continue
			var a_world := _port_world(room, port)
			var b_world := _port_world(peer, reciprocal)
			_check(a_world.distance_to(b_world) <= 0.01, "%s 两端锚点未重合" % edge)
			_check(
				_port_outward(port).dot(_port_outward(reciprocal)) <= -0.999,
				"%s 两端朝外方向未相反" % edge
			)
			var a_side := str(port.get("side", ""))
			var b_side := str(reciprocal.get("side", ""))
			var a_door := room.get_door_node(a_side)
			var b_door := peer.get_door_node(b_side)
			_check(a_door != null and b_door != null, "%s 缺少运行时门" % edge)
			if a_door != null and b_door != null:
				_check(a_door == b_door, "%s 两端没有共享同一个 RoomDoor3D" % edge)
				unique_doors[a_door.get_instance_id()] = true
			_check(
				room.owns_door_endpoint(a_side) != peer.owns_door_endpoint(b_side),
				"%s 必须且只能有一个门实体所有者" % edge
			)
	_check(checked_edges.size() == 12, "主路必须形成 12 条连接边")
	_check(unique_doors.size() == 12, "12 条边必须恰好只有 12 个门实体")

	var room_01 := rooms.get("room_01") as DungeonRoom3D
	_check(room_01 != null, "缺少 room_01")
	if room_01 != null:
		var ports_by_id := {}
		for value in room_01.connection_ports:
			var port := value as Dictionary
			ports_by_id[str(port.get("port_id", ""))] = port
		_check(str((ports_by_id.get("A", {}) as Dictionary).get("target_room_id", "")) == "start", "room01-A 必须连接安全屋")
		_check(str((ports_by_id.get("B", {}) as Dictionary).get("target_room_id", "")) == "room_02", "room01-B 必须连接 room02")
		_check(str((ports_by_id.get("C", {}) as Dictionary).get("target_room_id", "x")).is_empty(), "room01-C 必须保持封闭")
		_check(str((ports_by_id.get("D", {}) as Dictionary).get("target_room_id", "x")).is_empty(), "room01-D 必须保持封闭")
		var art_root := room_01.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		_check(art_root != null, "room01 缺少静态艺术根")
		if art_root != null:
			_check(art_root.get_node_or_null("ENV-EXPEDITION-L-CORRIDOR-WALL_X_05_REAR") != null, "room01-C 未用门洞必须有封墙")
			_check(art_root.get_node_or_null("ENV-EXPEDITION-L-CORRIDOR-WALL_X_35_REAR") != null, "room01-D 未用门洞必须有封墙")
			_check(art_root.get_node_or_null("ENV-EXPEDITION-L-CORRIDOR-WALL_Y_30_00") == null, "room01-A 非所有者不得保留重叠墙")

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("EXPEDITION_CONNECTION_PORTS_OK checks=%d edges=%d doors=%d" % [checks, checked_edges.size(), unique_doors.size()])
		get_tree().quit(0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)


func _plan_room(plan: Dictionary, key: String) -> Dictionary:
	for value in plan.get("rooms", []):
		var room := value as Dictionary
		if str(room.get("key", "")) == key:
			return room
	return {}


func _collect_rooms(block: Node3D) -> Dictionary:
	var rooms := {}
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms[room.room_id] = room
	return rooms


func _port_world(room: DungeonRoom3D, port: Dictionary) -> Vector3:
	var raw := port.get("position_m", []) as Array
	return room.to_global(Vector3(float(raw[0]), 0.0, float(raw[1])))


func _port_outward(port: Dictionary) -> Vector2:
	var raw := port.get("outward", []) as Array
	return Vector2(float(raw[0]), float(raw[1])).normalized()


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
