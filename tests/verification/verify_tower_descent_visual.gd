extends Node
## v0.1 全局光照、30m基地、98层入口、独立电梯、战斗房、楼梯与95层Boss采样。

const OUTPUT_DIR := "res://outputs/verification"
const ROOF_PATH := OUTPUT_DIR + "/tower_godot_rooftop_global_light_ph49.png"
const BASE_LIT_PATH := OUTPUT_DIR + "/tower_godot_floor99_base_lights_on_ph49.png"
const BASE_DARK_PATH := OUTPUT_DIR + "/tower_godot_floor99_base_lights_off_ph49.png"
const ENTRY_GATE_PATH := OUTPUT_DIR + "/tower_godot_floor98_stair_gate_closed_ph49.png"
const ENTRY_PATH := OUTPUT_DIR + "/tower_godot_floor98_inward_entry_ph49.png"
const COMBAT_DARK_PATH := OUTPUT_DIR + "/tower_godot_floor98_flashlight_only_ph49.png"
const COMBAT_LIT_PATH := OUTPUT_DIR + "/tower_godot_floor98_room_light_on_ph49.png"
const ELEVATOR_PATH := OUTPUT_DIR + "/tower_godot_floor98_standalone_elevator_ph49.png"
const STAIR_PATH := OUTPUT_DIR + "/tower_godot_stairwell_global_light_ph49.png"
const BOSS_PATH := OUTPUT_DIR + "/tower_godot_floor95_boss_ph49.png"


func _ready() -> void:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D

	# 北侧边缘：镜头从南向北看过围栏，可同时读到250m楼体外墙和远景城市。
	tower.player.global_position = Vector3(0.0, 0.05, -122.0)
	tower.force_enter_room_for_test("start")
	await _settle()
	_capture(ROOF_PATH, "楼顶画面采样失败", failures)

	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
	tower.force_enter_room_for_test("facility")
	facility.ensure_detail_built()
	await _settle()
	_capture(BASE_LIT_PATH, "99层基地开灯画面采样失败", failures)
	var base_switch := facility.get_node_or_null(
		"RoomLightSwitch3D"
	) as RoomLightSwitch3D
	if base_switch != null:
		base_switch.toggle_light()
		await _settle()
		_capture(BASE_DARK_PATH, "99层基地关灯画面采样失败", failures)
		base_switch.toggle_light()

	tower.force_open_edge_for_test("facility", "floor_01_entry")
	var entry := (tower.get("_room_by_id") as Dictionary).get(
		"floor_01_entry"
	) as DungeonRoom3D
	var entry_stair := _find_vertical_connector(
		tower,
		"facility",
		"floor_01_entry"
	)
	if entry_stair != null:
		var outward := entry_stair.get_meta("outward", Vector3.RIGHT) as Vector3
		tower.player.global_position = (
			entry_stair.get_meta("lower_door_position", Vector3.ZERO) as Vector3
		) + outward * 0.7 + Vector3.UP * 0.05
		if flashlight != null:
			flashlight.set_light_enabled(true)
		await _settle()
		_capture(ENTRY_GATE_PATH, "98层楼梯下端关闭门画面采样失败", failures)
		tower.try_open_stair_arrival_for_test()
	# 入口房位于东侧楼梯门的左侧/核心内侧；靠近北向枢纽门采样。
	tower.player.global_position = entry.global_position + Vector3(0.0, 0.05, -3.6)
	tower.force_enter_room_for_test("floor_01_entry")
	if flashlight != null:
		flashlight.set_light_enabled(true)
	await _settle()
	_capture(ENTRY_PATH, "98层楼梯入口大厅画面采样失败", failures)

	tower.force_open_edge_for_test("floor_01_entry", "floor_01_hub")
	var hub := (tower.get("_room_by_id") as Dictionary).get("floor_01_hub") as DungeonRoom3D
	tower.player.global_position = hub.global_position + Vector3(0.0, 0.05, 3.5)
	tower.force_enter_room_for_test("floor_01_hub")
	var room_light := hub.get_node_or_null("RoomCeilingLight") as WastelandLight3D
	if room_light != null:
		room_light.set_light_enabled(false)
	if flashlight != null:
		flashlight.set_light_enabled(true)
	await _settle()
	_capture(COMBAT_DARK_PATH, "98层暗室与探照灯画面采样失败", failures)
	if room_light != null:
		room_light.set_light_enabled(true)
	if flashlight != null:
		flashlight.set_light_enabled(false)
	await _settle()
	_capture(COMBAT_LIT_PATH, "98层房间开灯画面采样失败", failures)

	var elevator_room := (tower.get("_room_by_id") as Dictionary).get(
		"floor_01_elevator"
	) as DungeonRoom3D
	var elevator_facility := (
		(tower.get("_elevator_facilities_by_floor") as Dictionary).get(98)
		as BaseFacility3D
	)
	tower.player.global_position = (
		elevator_facility.global_position
		+ elevator_facility.global_basis.z * 2.7
		+ Vector3.UP * 0.05
		if elevator_facility != null
		else elevator_room.global_position + Vector3(0.0, 0.05, 15.0)
	)
	tower.force_enter_room_for_test("floor_01_elevator")
	if elevator_facility != null:
		tower.player.look_at(elevator_facility.global_position, Vector3.UP)
	if flashlight != null:
		flashlight.set_light_enabled(true)
	await _settle()
	_capture(ELEVATOR_PATH, "98层独立墙边电梯画面采样失败", failures)

	var stair := _find_vertical_connector(tower, "facility", "floor_01_entry")
	if stair == null:
		failures.append("找不到99—98层楼梯间用于视觉采样")
	else:
		tower.force_open_edge_for_test("facility", "floor_01_entry")
		tower.force_enter_room_for_test("facility")
		var points: Array = stair.get_meta("path_points", [])
		if points.size() >= 4:
			# 在上半段向下行进的位置采样：既能验收门厅衔接，也能看到
			# 第一跑楼梯与护栏，不让下层楼板占满整个预览画面。
			tower.player.global_position = (points[2] as Vector3).lerp(points[3] as Vector3, 0.5) + Vector3.UP * 0.05
			await _settle()
			_capture(STAIR_PATH, "楼梯间画面采样失败", failures)

	var boss := (tower.get("_room_by_id") as Dictionary).get(
		"extraction"
	) as DungeonRoom3D
	tower.player.global_position = boss.global_position + Vector3(0.0, 0.05, 10.0)
	tower.force_enter_room_for_test("extraction")
	if flashlight != null:
		flashlight.set_light_enabled(false)
	await _settle()
	_capture(BOSS_PATH, "95层Boss与撤离区画面采样失败", failures)

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.08).timeout
	if failures.is_empty():
		print("TOWER_DESCENT_VISUAL_OK: v0.1 rooftop/base/entry/elevator/combat/stair/boss previews saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.24).timeout


func _capture(path: String, failure: String, failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append(failure)


func _find_vertical_connector(tower: TowerDescent3D, a: String, b: String) -> Node3D:
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		var ids := [
			str(connector.get_meta("from_room_id", "")),
			str(connector.get_meta("to_room_id", "")),
		]
		if a in ids and b in ids:
			return connector
	return null
