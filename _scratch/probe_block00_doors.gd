extends Node
## 探针：区块00（98F）"这个区域的门"到底是什么政策、
## 98↔99 楼梯间那扇门（门厅东门）能不能从 98F 侧打开。
## 只打印运行时真值，不做断言。

const SEED := 990098
const STAND_DISTANCE_M := 1.6


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	tower.force_new_game_opening_for_test = true
	add_child(tower)
	await _settle()

	print("PROBE[doors] 开场 current_room_id=", str(tower.get("_current_room_id")))

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var edge_kind := tower.get("_edge_kind_by_key") as Dictionary
	var transit_script := load("res://src/world3d/SimpleTransitDoor3D.gd") as GDScript
	print("PROBE[doors] transit_interaction_distance=", float(transit_script.INTERACTION_DISTANCE_M),
		" auto_close=", float(transit_script.AUTO_CLOSE_DISTANCE_M),
		" delay=", float(transit_script.AUTO_CLOSE_DELAY_S))

	# —— 逐房逐门：政策 + 交通门组件 ——
	for room_id in ["floor_01_exit", "floor_01_main_02", "floor_01_hub", "floor_01_entry"]:
		var room := room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("PROBE[doors] room ", room_id, " = null")
			continue
		print("PROBE[doors] room ", room_id, " peaceful=", room.authored_layout_peaceful,
			" door_targets=", str(room.door_targets))
		for side_value in room.door_targets.keys():
			var side := str(side_value)
			var target := str(room.door_targets[side_value])
			var door := room.get_door_node(side)
			var snapshot := door.get_snapshot() if door != null else {}
			var component := door.get_node_or_null("SimpleTransitDoor3D") if door != null else null
			var edge := str(tower.call("_edge_key", room_id, target))
			print("PROBE[doors]   side=", side, " target=", target,
				" kind=", str(edge_kind.get(edge, "-")),
				" clear=", str(snapshot.get("requires_clear", "-")),
				" key=", str(snapshot.get("requires_key", "-")),
				" fate=", str(snapshot.get("triggers_fate", "-")),
				" transit_component=", str(component != null),
				" motion=", str(snapshot.get("motion_duration_s", "-")))

	# —— 逐边：同一条水平边两端的门到底是不是同一个门洞 ——
	print("PROBE[doors] === 水平边两端门位置 ===")
	for pair in [
		["floor_01_exit", "floor_01_main_02"],
		["floor_01_main_02", "floor_01_hub"],
		["floor_01_hub", "floor_01_entry"],
	]:
		var a := room_by_id.get(pair[0]) as DungeonRoom3D
		var b := room_by_id.get(pair[1]) as DungeonRoom3D
		var a_door: RoomDoor3D = null
		var b_door: RoomDoor3D = null
		for side_value in a.door_targets.keys():
			if str(a.door_targets[side_value]) == pair[1]:
				a_door = a.get_door_node(str(side_value))
		for side_value in b.door_targets.keys():
			if str(b.door_targets[side_value]) == pair[0]:
				b_door = b.get_door_node(str(side_value))
		print("PROBE[doors] ", pair[0], "[", (a_door.direction if a_door != null else "-"), "]=",
			str(a_door.global_position if a_door != null else "-"),
			" <-> ", pair[1], "[", (b_door.direction if b_door != null else "-"), "]=",
			str(b_door.global_position if b_door != null else "-"),
			" 间距=", str(a_door.global_position.distance_to(b_door.global_position) if a_door != null and b_door != null else "-"))

	# —— 用真实 E 交互通道走完整条链：最深房 → 门厅 ——
	var route: Array[String] = ["floor_01_exit", "floor_01_main_02", "floor_01_hub"]
	for room_id in route:
		var room := room_by_id.get(room_id) as DungeonRoom3D
		var door := room.get_door_node("east")
		await _stand_near_door(tower, room, door)
		var candidate := tower.get_interaction_candidate(tower.player)
		print("PROBE[doors] 在 ", room_id, " 东门前 candidate.mode=", str(candidate.get("mode", "<空>")),
			" door=", str((candidate.get("door") as Node) != null))
		if candidate.is_empty():
			continue
		var ok := bool(tower.perform_interaction(tower.player, candidate))
		await _wait_motion()
		var target_id := str(door.target_room_id)
		var target_room := room_by_id.get(target_id) as DungeonRoom3D
		var counterpart: RoomDoor3D = null
		if target_room != null:
			for side_value in target_room.door_targets.keys():
				if str(target_room.door_targets[side_value]) == room_id:
					counterpart = target_room.get_door_node(str(side_value))
		print("PROBE[doors]   perform=", str(ok),
			" 本房[", door.direction, "]&对侧[",
			str(counterpart.direction if counterpart != null else "-"), "] is_open=[",
			str(door.is_open), ", ", str(counterpart.is_open if counterpart != null else "-"), "]",
			" blocks=[", str(door.get_snapshot().get("blocks_passage", "-")), ", ",
			str(counterpart.get_snapshot().get("blocks_passage", "-") if counterpart != null else "-"), "]",
			" 门洞可通行=", str(
				door.is_open and counterpart != null and counterpart.is_open
				and not bool(door.get_snapshot().get("blocks_passage", true))
				and not bool(counterpart.get_snapshot().get("blocks_passage", true))
			))
		await _enter_room(tower, room_by_id.get(target_id) as DungeonRoom3D, target_id)

	# —— 98↔99 楼梯间门：门厅东门（floor_01_entry → facility）——
	print("PROBE[doors] === 门厅东门 = 98↔99 楼梯间门，从 98F 侧开启 ===")
	var lobby := room_by_id.get("floor_01_entry") as DungeonRoom3D
	var up_door := lobby.get_door_node("east")
	var up_edge := str(tower.call("_edge_key", "floor_01_entry", "facility"))
	print("PROBE[doors] kind=", str(edge_kind.get(up_edge, "-")),
		" open_before=", str((tower.get("_open_edges") as Dictionary).get(up_edge, false)),
		" vertical_arrival_open_before=", str((tower.get("_vertical_arrival_open") as Dictionary).get(up_edge, false)),
		" sealed=", str(tower.get("_initial_loop_gate_sealed")))
	await _stand_near_door(tower, lobby, up_door)
	var up_candidate := tower.get_interaction_candidate(tower.player)
	print("PROBE[doors] candidate.mode=", str(up_candidate.get("mode", "<空>")))
	var up_ok := bool(tower.perform_interaction(tower.player, up_candidate)) if not up_candidate.is_empty() else false
	await _settle()
	print("PROBE[doors] perform=", str(up_ok),
		" 门厅东门 is_open=", str(up_door.is_open),
		" blocks=", str(up_door.get_snapshot().get("blocks_passage", "-")),
		" status=", str(tower.status_label.text))
	print("PROBE[doors] open_after=", str((tower.get("_open_edges") as Dictionary).get(up_edge, false)),
		" vertical_arrival_open_after=", str((tower.get("_vertical_arrival_open") as Dictionary).get(up_edge, false)))
	var facility_room := room_by_id.get("facility") as DungeonRoom3D
	if facility_room != null:
		var facility_east := facility_room.get_door_node("east")
		print("PROBE[doors] 99F 基地东门（同一条边的上端门）is_open=",
			str(facility_east.is_open if facility_east != null else "-"))

	# —— 走远后自动关 ——
	tower.player.global_position = lobby.global_position + Vector3(0.0, 0.05, 0.0)
	tower.player.velocity = Vector3.ZERO
	await _settle()
	await get_tree().create_timer(1.2).timeout
	print("PROBE[doors] 走远后门厅东门 is_open=", str(up_door.is_open))

	remove_child(tower)
	tower.queue_free()
	await get_tree().process_frame
	print("PROBE_BLOCK00_DOORS_DONE")
	get_tree().quit(0)


func _stand_near_door(tower: TowerDescent3D, room: DungeonRoom3D, door: RoomDoor3D) -> void:
	if room == null or door == null:
		return
	var toward_center := (room.global_position - door.global_position)
	toward_center.y = 0.0
	if toward_center.length() < 0.01:
		toward_center = Vector3.FORWARD
	tower.player.global_position = door.global_position + toward_center.normalized() * STAND_DISTANCE_M
	tower.player.global_position.y = room.global_position.y + 0.05
	tower.player.velocity = Vector3.ZERO
	await _settle()


func _enter_room(tower: TowerDescent3D, room: DungeonRoom3D, room_id: String) -> void:
	if room == null:
		return
	tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	print("PROBE[doors]   进入 ", room_id, " current_room_id=", str(tower.get("_current_room_id")))


func _wait_motion() -> void:
	await _settle()
	await get_tree().create_timer(1.0).timeout


func _settle() -> void:
	for index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
