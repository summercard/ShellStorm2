extends Node
## 探针：98↔99 楼梯间门（floor_01_entry 东门 ↔ facility 东门）在
## 「按普通门办」之后的行为。2026-09-21 主人要求：从 98F 侧随时能开、
## 像 99F 基地门那样 E 开 + 走远自动关、不再有大循环封印/撤退确认。
## 只打印运行时真值，不做断言。

const SEED := 990098
const STAND_DISTANCE_M := 1.6
const AUTO_CLOSE_WAIT_S := 2.2
const FAR_AWAY_M := 9.0


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	tower.force_new_game_opening_for_test = true
	add_child(tower)
	await _settle()

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var edge := str(tower.call("_edge_key", "facility", "floor_01_entry"))
	var kind := str((tower.get("_edge_kind_by_key") as Dictionary).get(edge, "-"))
	print("PROBE[stair] edge=", edge, " kind=", kind,
		" 封印开关=", str(tower.get("INITIAL_LOOP_GATE_SEAL_ENABLED")))

	var lobby := room_by_id.get("floor_01_entry") as DungeonRoom3D
	var facility := room_by_id.get("facility") as DungeonRoom3D
	var lower_door := lobby.get_door_node("east")
	var facility_side := ""
	for side_value in facility.door_targets.keys():
		if str(facility.door_targets[side_value]) == "floor_01_entry":
			facility_side = str(side_value)
	var upper_door := facility.get_door_node(facility_side)
	for pair in [["98F下端", lower_door], ["99F上端", upper_door]]:
		var door := pair[1] as RoomDoor3D
		if door == null:
			print("PROBE[stair] ", pair[0], " = null")
			continue
		var component: Node = door.get_node_or_null("SimpleTransitDoor3D")
		print("PROBE[stair] ", pair[0], " is_open=", str(door.is_open),
			" blocks=", str(door.get_snapshot().get("blocks_passage", "-")),
			" 交通门组件=", str(component != null),
			" 交互距离=", str(door.get_meta("auto_close_distance_m", "-")),
			" motion=", str(door.get_snapshot().get("motion_duration_s", "-")))

	# —— 1) 从 98F 侧（里面）开门 ——
	print("PROBE[stair] === 1) 从 98F 侧开启楼梯间门 ===")
	print("PROBE[stair] 开门前 armed=", str(tower.get("_initial_loop_gate_armed")),
		" sealed=", str(tower.get("_initial_loop_gate_sealed")))
	await _stand_near(tower, lobby, lower_door)
	var candidate := tower.get_interaction_candidate(tower.player)
	print("PROBE[stair] candidate.mode=", str(candidate.get("mode", "<空>")),
		" door=", str((candidate.get("door") as Node) != null))
	var ok := bool(tower.perform_interaction(tower.player, candidate)) if not candidate.is_empty() else false
	await _wait_motion()
	print("PROBE[stair] perform=", str(ok),
		" 下端门 is_open=", str(lower_door.is_open),
		" blocks=", str(lower_door.get_snapshot().get("blocks_passage", "-")),
		" status=", str(tower.status_label.text))

	# —— 2) 走远自动关（照 99F 基地门口径）——
	print("PROBE[stair] === 2) 走远自动关 ===")
	tower.player.global_position = lobby.global_position + Vector3(0.0, 0.05, FAR_AWAY_M)
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	print("PROBE[stair] 走远 %.1fm 即时 is_open=" % FAR_AWAY_M, str(lower_door.is_open))
	await get_tree().create_timer(AUTO_CLOSE_WAIT_S).timeout
	print("PROBE[stair] 等 %.1fs 后 is_open=" % AUTO_CLOSE_WAIT_S, str(lower_door.is_open),
		" blocks=", str(lower_door.get_snapshot().get("blocks_passage", "-")))

	# —— 3) 封印已停用：强行武装+触发封门也不生效，门仍能从里面开 ——
	print("PROBE[stair] === 3) 封印停用复核 ===")
	tower.set("_initial_loop_gate_armed", true)
	tower.call("_on_initial_loop_entry_physically_entered", lobby)
	await _settle()
	print("PROBE[stair] 强行走封门后 armed=", str(tower.get("_initial_loop_gate_armed")),
		" sealed=", str(tower.get("_initial_loop_gate_sealed")),
		" open_edges[edge]=", str((tower.get("_open_edges") as Dictionary).get(edge, false)))
	await _stand_near(tower, lobby, lower_door)
	var candidate2 := tower.get_interaction_candidate(tower.player)
	print("PROBE[stair] candidate.mode=", str(candidate2.get("mode", "<空>")))
	var ok2 := bool(tower.perform_interaction(tower.player, candidate2)) if not candidate2.is_empty() else false
	await _wait_motion()
	var overlay: Node = tower.get("_initial_loop_retreat_overlay") as Node
	print("PROBE[stair] perform=", str(ok2),
		" 撤退弹窗=", str(overlay != null),
		" 下端门 is_open=", str(lower_door.is_open),
		" blocks=", str(lower_door.get_snapshot().get("blocks_passage", "-")))
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()

	remove_child(tower)
	tower.queue_free()
	await get_tree().process_frame
	print("PROBE_BLOCK00_STAIR_DOOR_DONE")
	get_tree().quit(0)


func _stand_near(tower: TowerDescent3D, room: DungeonRoom3D, door: RoomDoor3D) -> void:
	if room == null or door == null:
		return
	tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var toward_center := room.global_position - door.global_position
	toward_center.y = 0.0
	if toward_center.length() < 0.01:
		toward_center = Vector3.LEFT
	tower.player.global_position = door.global_position + toward_center.normalized() * STAND_DISTANCE_M
	tower.player.global_position.y = room.global_position.y + 0.05
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()


func _wait_motion() -> void:
	await _settle()
	await get_tree().create_timer(1.0).timeout


func _settle() -> void:
	for index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
