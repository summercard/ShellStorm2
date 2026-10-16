extends Node
## 探针：踩点遭遇「封门」后，玩家能不能从**进来时那扇门**走出去。
##
## 业主反馈：「激活后进来的门还是开着的，还能往房间外走。」
##
## 关键前提：玩家是从西边那扇门进来的 ⇒ 那条**边已经打开**（`_open_edges` 为 true）。
## 所以复现必须**先开边**再触发，否则测的是"边还关着"的假象（第一版探针就是这么错的：
## 走位被墙挡住、误判成"封门有效"）。
##
## 同时打出共享门的三件事，用来定位失败在哪一步：
##   · 两端各自的 `door_endpoint_owners` / `_door_nodes`（谁持有门扇）
##   · 该边的 `_edge_door_sides_by_key`（两端方向）
##   · `RoomDoor3D.is_open`（门扇到底关没关）

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEED_VALUE := 77001199
const ROOM_KEY := "room_03"
const PEER_KEY := "room_02"

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	var room := tower._room_by_id.get(ROOM_KEY) as DungeonRoom3D
	var peer := tower._room_by_id.get(PEER_KEY) as DungeonRoom3D
	room.ensure_shell_built()
	room.ensure_detail_built()
	if peer != null:
		peer.ensure_shell_built()
		peer.ensure_detail_built()
	await get_tree().physics_frame
	await get_tree().physics_frame

	# —— 绑定失败点定位：按端口取门扇 ——
	if peer != null:
		var peer_port := peer.get_connection_port_towards(ROOM_KEY)
		var peer_port_id := str(peer_port.get("port_id", ""))
		print("PROBE|room_02 端口id=%s" % peer_port_id)
		print("PROBE|room_02._door_nodes_by_port 键=%s" % str(peer._door_nodes_by_port.keys()))
		print("PROBE|room_02.get_door_node_by_port(%s)=%s" % [
			peer_port_id, str(peer.get_door_node_by_port(peer_port_id)),
		])
		print("PROBE|_edge_expects_door_leaf(room_02,east)=%s" % str(tower._edge_expects_door_leaf(peer, "east")))
		print("PROBE|room_03._door_nodes_by_port 键=%s" % str(room._door_nodes_by_port.keys()))

	# —— 复现前提：入口那条边是**已打开**的（玩家就是这样进来的）——
	tower.force_enter_room_for_test(ROOM_KEY)
	tower.force_open_edge_for_test(PEER_KEY, ROOM_KEY)
	for _frame in 4:
		await get_tree().process_frame
	print("PROBE|入口边已打开=%s" % str(tower._open_edges.get(tower._edge_key(PEER_KEY, ROOM_KEY), false)))
	_dump(room, peer, "开边后 / 触发前")

	# —— 触发 ——
	tower.player.global_position = room.global_position + Vector3(0.0, 0.5, 0.0)
	for _frame in 4:
		await get_tree().process_frame
	print("PROBE|触发=%s|封门=%s" % [
		str(tower._room_encounters_fired.has(room.room_id)),
		str(tower._room_is_sealed(room.room_id)),
	])
	_dump(room, peer, "封门后")

	# —— 物理走位：**沿门巷**从房内走出去 ——
	# ⚠ 必须走门洞那条线。第一版沿 z=0 直走，撞的是实墙（门洞在门巷 z=-2.5 上），
	# 结果把"墙挡住了"误读成"封门有效" —— 这是本探针第二次踩同一个坑。
	var port := room.get_connection_port_towards(PEER_KEY)
	var lane_z := float(port.get("lane_m", 0.0))
	var port_pos := port.get("position_m", []) as Array
	if port_pos.size() >= 2:
		lane_z = float(port_pos[1])
	print("PROBE|入口端口=%s|门巷局部z=%.2f" % [str(port), lane_z])
	var half_x := room.get_dimensions().x * 0.5
	var start_local := Vector3(-half_x * 0.4, 0.0, lane_z)
	var out_local := Vector3(-half_x - 8.0, 0.0, lane_z)
	tower.player.global_position = room.to_global(start_local + Vector3(0.0, 0.5, 0.0))
	await get_tree().physics_frame
	var farthest := start_local.x
	for _frame in 200:
		var target := room.to_global(out_local + Vector3(0.0, 0.5, 0.0))
		var current := tower.player.global_position
		var step := target - current
		step.y = 0.0
		if step.length() > 0.3:
			step = step.normalized() * 0.3
		tower.player.global_position = current + step
		await get_tree().physics_frame
		farthest = minf(farthest, room.to_local(tower.player.global_position).x)
	var final_local := room.to_local(tower.player.global_position)
	print("PROBE|走位结果|最终局部x=%.2f|最远局部x=%.2f|半宽=%.2f|在房内=%s|出界=%s" % [
		final_local.x, farthest, half_x,
		str(room.contains_world_position(tower.player.global_position)),
		str(final_local.x < -half_x),
	])
	print("PROBE_DONE")
	get_tree().quit(0)


func _dump(room: DungeonRoom3D, peer: DungeonRoom3D, tag: String) -> void:
	print("--- %s ---" % tag)
	print("  %s owners=%s _door_nodes=%s" % [
		room.room_id, str(room.door_endpoint_owners), str(room._door_nodes.keys()),
	])
	if peer != null:
		print("  %s owners=%s _door_nodes=%s" % [
			peer.room_id, str(peer.door_endpoint_owners), str(peer._door_nodes.keys()),
		])
	for direction_value in room.door_targets.keys():
		var direction := str(direction_value)
		var door := room.get_door_node(direction)
		print("    %s.%-6s -> %s" % [
			room.room_id, direction,
			"无节点" if door == null else "is_open=%s" % str(door.is_open),
		])
	if peer != null:
		for direction_value in peer.door_targets.keys():
			var direction := str(direction_value)
			var door := peer.get_door_node(direction)
			print("    %s.%-6s -> %s" % [
				peer.room_id, direction,
				"无节点" if door == null else "is_open=%s" % str(door.is_open),
			])
