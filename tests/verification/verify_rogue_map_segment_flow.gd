extends Node
## 独立 Rogue 副本闭环验收：
## 1) 目录动作：mission_operations 打开 RogueMapSelectMenu；
## 2) 独立图四计划：仅 98/97/96/95；
## 3) 首个安全房 15×15；
## 4) 终端 95F 无 94F 入口/电梯但有 Boss 撤离；
## 5) 独立图使用战局快照并能在重启时被主塔路由回自身；
## 6) 默认塔楼行为不受影响（仍规划到 85F，含天台与 99F 基地）。

const SAFE_ROOM_SIZE := Vector2(15.0, 15.0)


func _ready() -> void:
	var failures: Array[String] = []

	# 1) 目录动作检查（无需实例化世界）。
	var def := BaseFacilityCatalog.get_definition("mission_operations")
	if str(def.get("action_kind", "")) != BaseFacilityCatalog.ACTION_MENU:
		failures.append("mission_operations 动作类型不是 menu：%s" % str(def.get("action_kind", "")))
	if str(def.get("action_path", "")) != "res://scenes/RogueMapSelectMenu.tscn":
		failures.append("mission_operations 目标菜单不是 RogueMapSelectMenu：%s" % str(def.get("action_path", "")))

	# 1b) 菜单冒烟测试：加载、构建 UI、按钮存在且关闭按钮可释放菜单。
	var menu_scene := load("res://scenes/RogueMapSelectMenu.tscn") as PackedScene
	if menu_scene == null:
		failures.append("RogueMapSelectMenu.tscn 加载失败")
	else:
		var menu := menu_scene.instantiate() as CanvasLayer
		if menu == null:
			failures.append("RogueMapSelectMenu 实例化失败")
		else:
			add_child(menu)
			await get_tree().process_frame
			var menu_panel := menu.find_child("Panel", true, false) as Control
			if menu_panel == null:
				failures.append("RogueMapSelectMenu 缺少主面板")
			else:
				var viewport_center := get_viewport().get_visible_rect().size * 0.5
				var panel_center := menu_panel.get_global_rect().get_center()
				if not panel_center.is_equal_approx(viewport_center):
					failures.append("RogueMapSelectMenu 主面板未居中：panel=%s viewport=%s" % [panel_center, viewport_center])
			if menu.find_child("TeleportButton", true, false) == null:
				failures.append("RogueMapSelectMenu 缺少传送按钮")
			var close_btn := menu.find_child("CloseButton", true, false)
			if close_btn == null:
				failures.append("RogueMapSelectMenu 缺少关闭按钮")
			elif not close_btn.pressed.is_connected(menu._on_close_pressed):
				failures.append("RogueMapSelectMenu 关闭按钮未连接关闭逻辑")
			else:
				close_btn.pressed.emit()
				await get_tree().process_frame
				if is_instance_valid(menu):
					failures.append("RogueMapSelectMenu 关闭按钮未释放菜单")
			if is_instance_valid(menu):
				menu.queue_free()
			await get_tree().process_frame

	# 2)-4) 独立图实例化与生成。
	var scene := load("res://scenes/RogueMap01TowerSegment3D.tscn") as PackedScene
	if scene == null:
		failures.append("RogueMap01TowerSegment3D.tscn 加载失败")
		_report(failures)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		failures.append("RogueMap01TowerSegment3D 实例化失败")
		_report(failures)
		return
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame

	if not tower.is_standalone_rogue():
		failures.append("独立图 standalone_rogue 未开启")
	if not str(tower.get_rogue_map_id()).ends_with("rogue_map_01"):
		failures.append("独立图 rogue_map_id 不正确：%s" % tower.get_rogue_map_id())
	if tower.return_scene_path != "res://scenes/BaseWorld3D.tscn":
		failures.append("独立图结算返回场景不是正式3D基地：%s" % tower.return_scene_path)

	var planned := tower.get_standalone_planned_floor_numbers()
	for expected in [98, 97, 96, 95]:
		if expected not in planned:
			failures.append("独立图缺少计划楼层 %d（计划：%s）" % [expected, planned])
	for forbidden in [100, 99, 94]:
		if forbidden in planned:
			failures.append("独立图不应包含计划楼层 %d（计划：%s）" % [forbidden, planned])

	if not tower.generate_through_floor_for_test(95):
		failures.append("独立图无法连续提交到 95F")

	# 3) 首个安全房 15×15，并且必须实际装配原 98F v007 正式美术。
	var safe_dims := tower.get_first_safe_room_dimensions()
	if not safe_dims.is_equal_approx(SAFE_ROOM_SIZE):
		failures.append("首个安全房尺寸不是 15×15：%s" % safe_dims)
	var entry_room := tower._room_by_id.get("start") as DungeonRoom3D
	if entry_room == null:
		failures.append("独立图缺少 98F 入口安全房 start")
	else:
		var safe_snapshot := entry_room.get_room_snapshot()
		if str(safe_snapshot.get("safe_room_art_version", "")) != "v007":
			failures.append("独立图 98F 入口未接入 v007 安全房美术：%s" % safe_snapshot)
		if int(safe_snapshot.get("safe_room_wall_module_count", -1)) != 10:
			failures.append("独立图安全房实墙不是 10 段：%s" % safe_snapshot)
		if int(safe_snapshot.get("safe_room_door_wall_module_count", -1)) != 2:
			failures.append("独立图安全房门墙不是 2 段：%s" % safe_snapshot)
		if int(safe_snapshot.get("safe_room_floor_tile_count", -1)) != 9:
			failures.append("独立图安全房地砖不是 9 块：%s" % safe_snapshot)
		if int(safe_snapshot.get("safe_room_package_count", -1)) != 17:
			failures.append("独立图安全房房间包不是 17 个：%s" % safe_snapshot)
		if entry_room.doors.size() != 2:
			failures.append("独立图安全房必须保留双门结构：%s" % entry_room.doors)
		var hub_id := ""
		for room_value in tower._floor_plan_snapshots[2].get("rooms", []):
			var room_spec := room_value as Dictionary
			if str(room_spec.get("key", "")) == "hub":
				hub_id = str(room_spec.get("id", ""))
				break
		var has_hub_target := false
		var closed_arrival_count := 0
		for target_value in entry_room.door_targets.values():
			if str(target_value) == hub_id:
				has_hub_target = true
			elif str(target_value).is_empty():
				closed_arrival_count += 1
		if not has_hub_target:
			failures.append("独立图安全房缺少真实 Hub 门目标：%s" % entry_room.door_targets)
		if closed_arrival_count != 1:
			failures.append("独立图安全房应有 1 扇传送抵达封闭门：%s" % entry_room.door_targets)
		var retreat_door_count := 0
		for side_value in entry_room.door_targets.keys():
			var side := str(side_value)
			if not str(entry_room.door_targets[side_value]).is_empty():
				continue
			var retreat_door := entry_room.get_door_node(side)
			if retreat_door != null and retreat_door.get_interaction_prompt_text() == "[E] 退出战局":
				retreat_door_count += 1
		if retreat_door_count != 1:
			failures.append("独立图出生安全房未注册唯一退出战局门：%d" % retreat_door_count)
		tower.player.global_position = entry_room.global_position + Vector3(5.0, 0.05, 0.0)
		await get_tree().physics_frame
		var retreat_candidate := tower.get_interaction_candidate(tower.player)
		if str(retreat_candidate.get("mode", "")) != "configured_standalone_retreat":
			failures.append("独立图出生门未产生 standalone_retreat 交互候选：%s" % retreat_candidate)
		elif not tower.perform_interaction(tower.player, retreat_candidate):
			failures.append("独立图出生门按E未打开退出确认")
		elif tower.get_node_or_null("HUD/StandaloneExitWarning") == null:
			failures.append("独立图出生门交互后缺少独立副本退出确认弹窗")
		else:
			# 退出确认必须是独立副本自己的文案，不能复用塔楼 98F 反向撤退弹窗。
			if tower.get_node_or_null("HUD/InitialLoopRetreatWarning") != null:
				failures.append("独立图退出确认误用了塔楼反向撤退弹窗")
			tower._cancel_standalone_exit()

	# 4) 终端条件：无 94F 计划、无 95F 电梯、有 Boss 撤离。
	if tower._floor_plan_snapshots.has(6):
		failures.append("独立图存在 94F（floor_index 6）规划")
	if tower._elevator_facilities_by_floor.has(95):
		failures.append("独立图错误生成了 95F 电梯")
	if not tower.has_standalone_terminal_boss_extraction():
		failures.append("独立图 95F 缺少 Boss 撤离信标")

	# 5) 独立图的入口安全房仍是战局，不是基地；保存必须标记自身 map id。
	var rogue_snapshot := tower.build_runtime_save_snapshot()
	if str(rogue_snapshot.get("scope", "")) != "combat":
		failures.append("独立图 98F 入口安全房未按战局范围保存：%s" % rogue_snapshot.get("scope", ""))
	if str(rogue_snapshot.get("runtime_map_id", "")) != "rogue_map_01":
		failures.append("独立图运行时快照缺少 rogue_map_01 隔离标记")

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# 5) 默认塔楼行为不受影响。
	var std_scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var std := std_scene.instantiate() as TowerDescent3D
	std.test_mode = true
	std.run_seed_override = 77001199
	add_child(std)
	await get_tree().process_frame

	if std.is_standalone_rogue():
		failures.append("默认塔楼被意外标记为 standalone_rogue")
	var std_planned := std.get_standalone_planned_floor_numbers()
	if 94 not in std_planned:
		failures.append("默认塔楼缺少 94F 规划（默认行为已变）")
	if 85 not in std_planned:
		failures.append("默认塔楼缺少 85F 规划（默认规划范围已变）")
	if not std._room_by_id.has("start"):
		failures.append("默认塔楼缺少 100F 天台(start)")
	if not std._room_by_id.has("facility"):
		failures.append("默认塔楼缺少 99F 基地(facility)")
	var resume_scene := std.get_runtime_resume_scene_path(rogue_snapshot)
	if resume_scene != "res://scenes/RogueMap01TowerSegment3D.tscn":
		failures.append("主塔未把 rogue_map_01 战局快照路由回独立副本：%s" % resume_scene)
	var normal_snapshot := rogue_snapshot.duplicate(true)
	normal_snapshot["runtime_map_id"] = ""
	if not std.get_runtime_resume_scene_path(normal_snapshot).is_empty():
		failures.append("旧塔楼战局快照被错误路由到独立副本")

	std.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# 6) 退出战局门的离场契约，两条入口都要成立：
	#    首次进入后按门，以及“关卡内重新上线 → 98F 安全房 → 按门”。
	#    独立副本没有 99F 基地房，确认退出必须“清空随身物品 + 登记基地返回契约”，
	#    而不是按塔楼 98F 重建世界（那会把整张地图换成一间无美术白盒房，
	#    玩家既回不到基地，也留在副本里）。
	await _verify_standalone_exit_contract(failures, false)
	await _verify_standalone_exit_contract(failures, true)

	_report(failures)


func _verify_standalone_exit_contract(failures: Array[String], via_resume: bool) -> void:
	var label := "重新上线后" if via_resume else "首次进入"
	var exit_scene := load("res://scenes/RogueMap01TowerSegment3D.tscn") as PackedScene
	if exit_scene == null:
		failures.append("退出契约检查无法加载 RogueMap01TowerSegment3D.tscn")
		return
	var exit_tower := exit_scene.instantiate() as TowerDescent3D
	exit_tower.test_mode = true
	exit_tower.run_seed_override = 77001199
	add_child(exit_tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	if via_resume:
		# 模拟关卡内重新上线：提交到 95F → 把玩家留在战斗房 → 取行动快照 → 恢复。
		if not exit_tower.generate_through_floor_for_test(95):
			failures.append("退出契约检查(%s)无法提交到 95F" % label)
		var combat_room_id := _first_combat_room_id(exit_tower)
		var combat_room := exit_tower._room_by_id.get(combat_room_id) as DungeonRoom3D
		if combat_room == null:
			failures.append("退出契约检查(%s)缺少战斗房" % label)
		else:
			exit_tower.player.global_position = combat_room.global_position + Vector3(0.0, 0.05, 0.0)
			exit_tower.player.velocity = Vector3.ZERO
			exit_tower._current_room_id = combat_room_id
			await get_tree().physics_frame
			var saved := exit_tower.build_runtime_save_snapshot()
			if str(saved.get("runtime_map_id", "")) != "rogue_map_01":
				failures.append("退出契约检查(%s)行动快照缺少 rogue_map_01 隔离标记" % label)
			exit_tower._restore_runtime_save_snapshot(saved)
			await get_tree().process_frame
			await get_tree().physics_frame
			if str(exit_tower._current_room_id) != "start":
				failures.append("退出契约检查(%s)重新上线没有落回 98F 安全房：%s" % [
					label, exit_tower._current_room_id,
				])
			var resume_room := exit_tower._room_by_id.get("start") as DungeonRoom3D
			if resume_room == null:
				failures.append("退出契约检查(%s)重新上线后缺少 start 安全房" % label)
			elif str(resume_room.get_room_snapshot().get("safe_room_art_version", "")) != "v007":
				failures.append("退出契约检查(%s)重新上线后安全房美术丢失：%s" % [
					label, resume_room.get_room_snapshot(),
				])

	var rooms_before := exit_tower._room_by_id.size()
	var exit_room := exit_tower._room_by_id.get("start") as DungeonRoom3D
	if exit_room == null:
		failures.append("退出契约检查(%s)缺少 start 安全房" % label)
		exit_tower.queue_free()
		return
	var exit_door: RoomDoor3D = null
	for side_value in exit_room.door_targets.keys():
		if str(exit_room.door_targets[side_value]).is_empty():
			exit_door = exit_room.get_door_node(str(side_value)) as RoomDoor3D
			break
	if exit_door == null:
		failures.append("退出契约检查(%s)找不到无目标抵达侧门" % label)
		exit_tower.queue_free()
		return
	exit_tower.player.global_position = exit_door.global_position + Vector3(0.0, 0.05, 0.0)
	await get_tree().physics_frame
	var candidate := exit_tower.get_interaction_candidate(exit_tower.player)
	if str(candidate.get("mode", "")) != "configured_standalone_retreat":
		failures.append("退出契约检查(%s)门未产生 standalone_retreat 候选：%s" % [label, candidate])
	exit_tower.perform_interaction(exit_tower.player, candidate)
	await get_tree().process_frame
	var overlay := exit_tower.get_node_or_null("HUD/StandaloneExitWarning") as Control
	if overlay == null:
		failures.append("退出契约检查(%s)未打开独立副本退出弹窗" % label)
		exit_tower.queue_free()
		return
	if exit_tower.get_node_or_null("HUD/InitialLoopRetreatWarning") != null:
		failures.append("退出契约检查(%s)误用了塔楼反向撤退弹窗" % label)
	# 注入一件背包物，验证“98F 反向撤退”的物品契约真的生效。
	if exit_tower._inventory != null:
		exit_tower._inventory.add_item({"id": "verify_exit_loot", "name": "验收物资", "count": 1})
	var confirm := _find_button(overlay, "确认退出")
	if confirm == null:
		failures.append("独立副本退出弹窗缺少确认按钮(%s)" % label)
	else:
		confirm.pressed.emit()
		await get_tree().process_frame
	if not exit_tower._completed:
		failures.append("确认退出后独立副本行动未结束标记(%s)" % label)
	if str(exit_tower.return_scene_path) != GameDesignConfig.BASE_SCENE_3D:
		failures.append("独立副本退出返回场景不是正式基地：%s" % exit_tower.return_scene_path)
	var rooms_after := exit_tower._room_by_id.size()
	if rooms_after != rooms_before:
		failures.append("确认退出后独立副本房间表被重建(%s：%d -> %d)，应为离场而非场景内复位" % [
			label, rooms_before, rooms_after,
		])
	if not exit_tower._room_by_id.has("start"):
		failures.append("确认退出后 start 安全房消失(%s)" % label)
	if exit_tower._room_by_id.has("floor_01_entry"):
		failures.append("确认退出后独立副本出现塔楼 98F 房间 floor_01_entry(%s)" % label)
	if exit_tower._room_by_id.has("facility"):
		failures.append("确认退出后独立副本出现了不应存在的 99F 基地房(%s)" % label)
	if exit_tower._inventory != null and exit_tower._inventory.get_occupied_slots().size() != 0:
		failures.append("确认退出后背包未被清空(%s)" % label)
	var weapons_after := 0
	for slot_index in range(2):
		if not exit_tower.player.get_equipped_weapon_item_for_slot(slot_index).is_empty():
			weapons_after += 1
	if weapons_after != 0:
		failures.append("确认退出后装备武器未被清空(%s：%d 把)" % [label, weapons_after])
	var pending := GameEntryFlow.peek_pending_entry()
	if str(pending.get("reason", "")) != GameEntryFlow.REASON_ABORT_RETURN_99F:
		failures.append("确认退出未登记独立副本退出返回契约(%s)：%s" % [label, pending])
	if str(pending.get("spawn_target", "")) != GameEntryFlow.SPAWN_BASE_99F:
		failures.append("确认退出的返回契约不是 99F 基地出生(%s)：%s" % [label, pending])
	if int(pending.get("request_id", -1)) > 0:
		GameEntryFlow.cancel_request(int(pending["request_id"]))
	exit_tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _first_combat_room_id(tower: TowerDescent3D) -> String:
	for room_id_value in tower._floor_room_ids.get(2, []):
		var room_id := str(room_id_value)
		if room_id == "start":
			continue
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room != null and room.room_type == "COMBAT":
			return room_id
	return ""


func _find_button(root: Node, text_fragment: String) -> Button:
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.text.contains(text_fragment):
			return button
	return null


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print("ROGUE_MAP_SEGMENT_FLOW_OK: catalog->menu, standalone 98/97/96/95, 15x15 safe room, terminal 95F boss extraction without 94F/elevator, birth safe room exit-door abort contract returns to base scene after fresh entry and after in-level resume, default tower unchanged")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
