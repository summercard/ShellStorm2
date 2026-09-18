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
	if tower.return_scene_path != "res://scenes/TowerDescent3D.tscn":
		failures.append("独立图结算返回场景不是 TowerDescent3D：%s" % tower.return_scene_path)

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

	_report(failures)


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print("ROGUE_MAP_SEGMENT_FLOW_OK: catalog->menu, standalone 98/97/96/95, 15x15 safe room, terminal 95F boss extraction without 94F/elevator, default tower unchanged")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
