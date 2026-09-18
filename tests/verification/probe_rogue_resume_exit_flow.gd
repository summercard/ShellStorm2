extends Node
## 一次性探针：独立副本「关卡内重新上线 → 98F 安全屋 → 按下返回门」的真实结果。
## 只读观测，不写存档。覆盖：
##   1) 首次进入时的 98F 安全房装配（房 id / 美术 / 门目标）
##   2) 打进 95F 后把玩家留在战斗房，取一次行动快照（模拟下线）
##   3) 用该快照做一次运行时恢复（模拟重新上线），观察落到哪间房、是不是白盒房
##   4) 在落点房间里找无目标抵达侧门（“退出战局”门），交互并确认，观察是否回基地

const ROGUE_SCENE := "res://scenes/RogueMap01TowerSegment3D.tscn"


func _ready() -> void:
	var packed := load(ROGUE_SCENE) as PackedScene
	if packed == null:
		print("加载失败: ", ROGUE_SCENE)
		get_tree().quit(1)
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	print("=== 1) 首次进入 ===")
	_dump_floor2(tower, "首次进入")
	var entry_room := tower._room_by_id.get("start") as DungeonRoom3D
	_dump_room(tower, entry_room, "入口房")

	print("")
	print("=== 2) 打进度并把玩家留在战斗房 ===")
	print("  连续提交到 95F = ", tower.generate_through_floor_for_test(95))
	var combat_room_id := _first_combat_room_id(tower)
	var combat_room := tower._room_by_id.get(combat_room_id) as DungeonRoom3D
	if combat_room != null:
		combat_room.cleared = true
		tower.player.global_position = combat_room.global_position + Vector3(0.0, 0.05, 0.0)
		tower.player.velocity = Vector3.ZERO
		tower._current_room_id = combat_room_id
		await get_tree().physics_frame
	print("  玩家所在战斗房 = ", combat_room_id, " @ ", tower.player.global_position)
	var snapshot := tower.build_runtime_save_snapshot()
	print("  快照 scope = ", snapshot.get("scope", ""),
		" / runtime_map_id = ", snapshot.get("runtime_map_id", ""),
		" / current_room_id = ", snapshot.get("current_room_id", ""),
		" / current_floor_index = ", snapshot.get("current_floor_index", ""))

	print("")
	print("=== 3) 重新上线（用该快照做运行时恢复）===")
	tower._restore_runtime_save_snapshot(snapshot)
	await get_tree().process_frame
	await get_tree().physics_frame
	print("  恢复后 当前房 = ", tower._current_room_id, " 位置 = ", tower.player.global_position)
	_dump_floor2(tower, "恢复后")
	var landing := tower._room_by_id.get(str(tower._current_room_id)) as DungeonRoom3D
	_dump_room(tower, landing, "恢复后落点房")

	print("")
	print("=== 4) 在落点房间里按下返回门 ===")
	if landing == null:
		print("  无落点房，终止")
	else:
		var exit_door: RoomDoor3D = null
		var exit_side := ""
		for side_value in landing.door_targets.keys():
			var side := str(side_value)
			if str(landing.door_targets[side_value]).is_empty():
				var candidate_door := landing.get_door_node(side) as RoomDoor3D
				if candidate_door != null:
					exit_door = candidate_door
					exit_side = side
					break
		print("  无目标抵达侧门 = ", exit_side, " 提示 = ",
			exit_door.get_interaction_prompt_text() if exit_door != null else "<不存在>")
		if exit_door != null:
			tower.player.global_position = exit_door.global_position + Vector3(0.0, 0.05, 0.0)
			await get_tree().physics_frame
			var candidate := tower.get_interaction_candidate(tower.player)
			print("  交互候选 mode = ", candidate.get("mode", "<空>"), " prompt = ", candidate.get("prompt", "<空>"))
			tower.perform_interaction(tower.player, candidate)
			await get_tree().process_frame
			var standalone_overlay := tower.get_node_or_null("HUD/StandaloneExitWarning") as Control
			var tower_overlay := tower.get_node_or_null("HUD/InitialLoopRetreatWarning") as Control
			print("  独立副本退出框 = ", standalone_overlay != null, " / 塔楼撤退框 = ", tower_overlay != null)
			var confirm := _find_button(standalone_overlay, "确认退出")
			if confirm == null:
				confirm = _find_button(tower_overlay, "确认撤退")
			print("  确认按钮 = ", confirm.text if confirm != null else "<缺失>")
			if confirm != null:
				confirm.pressed.emit()
				await get_tree().process_frame
				await get_tree().physics_frame
			print("  确认后 当前房 = ", tower._current_room_id, " 位置 = ", tower.player.global_position)
			print("  确认后房间数 = ", tower._room_by_id.size(),
				" 含 start = ", tower._room_by_id.has("start"),
				" 含 floor_01_entry = ", tower._room_by_id.has("floor_01_entry"),
				" 含 facility = ", tower._room_by_id.has("facility"))
			var landed := _room_containing(tower)
			_dump_room(tower, landed, "确认后落点房")
			var pending := GameEntryFlow.peek_pending_entry()
			print("  返回契约 = ", pending.get("reason", "<空>"), " / ", pending.get("spawn_target", "<空>"))
			if int(pending.get("request_id", -1)) > 0:
				GameEntryFlow.cancel_request(int(pending["request_id"]))
			print("  状态栏 = ", tower.status_label.text)

	tower.queue_free()
	await get_tree().process_frame
	print("")
	print("PROBE_ROGUE_RESUME_EXIT_DONE")
	get_tree().quit(0)


func _dump_floor2(tower: TowerDescent3D, label: String) -> void:
	var floor_rooms: Array = tower._floor_room_ids.get(2, [])
	print("  [%s] 98F 房 id = %s" % [label, floor_rooms])
	print("  [%s] 全部房数 = %d" % [label, tower._room_by_id.size()])


func _dump_room(tower: TowerDescent3D, room: DungeonRoom3D, label: String) -> void:
	if room == null:
		print("  [%s] <无>" % label)
		return
	var snapshot := room.get_room_snapshot()
	print("  [%s] id=%s type=%s 尺寸=%s 门向=%s 门目标=%s" % [
		label, room.room_id, room.room_type, room.get_dimensions(),
		room.doors, room.door_targets,
	])
	print("  [%s] 美术: art=%s 墙=%s 门墙=%s 地砖=%s 包=%s 旋转=%s" % [
		label,
		snapshot.get("safe_room_art_version", ""),
		snapshot.get("safe_room_wall_module_count", -1),
		snapshot.get("safe_room_door_wall_module_count", -1),
		snapshot.get("safe_room_floor_tile_count", -1),
		snapshot.get("safe_room_package_count", -1),
		snapshot.get("safe_room_orientation_steps", -1),
	])
	print("  [%s] 子节点数=%d 玩家是否在其内=%s" % [
		label, room.get_child_count(), tower._is_player_inside_room(room),
	])


func _first_combat_room_id(tower: TowerDescent3D) -> String:
	for room_id_value in tower._floor_room_ids.get(2, []):
		var room_id := str(room_id_value)
		if room_id == "start":
			continue
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room != null and room.room_type == "COMBAT":
			return room_id
	var ids: Array = tower._floor_room_ids.get(2, [])
	return str(ids[1]) if ids.size() > 1 else str(ids[0])


func _room_containing(tower: TowerDescent3D) -> DungeonRoom3D:
	for room_id_value in tower._room_by_id.keys():
		var room := tower._room_by_id.get(room_id_value) as DungeonRoom3D
		if room != null and tower._is_player_inside_room(room):
			return room
	return null


func _find_button(root: Node, text_fragment: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.text.contains(text_fragment):
			return button
	return null
