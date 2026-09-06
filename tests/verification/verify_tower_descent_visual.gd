extends Node
## v0.1 全局光照、30m基地、98层入口、独立电梯、战斗房、楼梯与95层Boss采样。

const OUTPUT_DIR := "res://outputs/verification"
const ROOF_PATH := OUTPUT_DIR + "/tower_godot_rooftop_global_light_ph49.png"
const BASE_LIT_PATH := OUTPUT_DIR + "/tower_godot_floor99_base_lights_on_ph49.png"
const BASE_DARK_PATH := OUTPUT_DIR + "/tower_godot_floor99_base_lights_off_ph49.png"
const BASE_RELIT_PATH := OUTPUT_DIR + "/tower_godot_floor99_base_lights_restored_ph51.png"
const ENTRY_GATE_PATH := OUTPUT_DIR + "/tower_godot_floor98_stair_gate_closed_ph49.png"
const ENTRY_PATH := OUTPUT_DIR + "/tower_godot_floor98_inward_entry_ph49.png"
const COMBAT_DARK_PATH := OUTPUT_DIR + "/tower_godot_floor98_flashlight_only_ph49.png"
const FLASHLIGHT_FAR_WALL_PATH := OUTPUT_DIR + "/tower_godot_floor98_flashlight_far_wall_ph52.png"
const COMBAT_LIT_PATH := OUTPUT_DIR + "/tower_godot_floor98_room_light_on_ph49.png"
const CAMERA_CLOSE_WALL_PATH := OUTPUT_DIR + "/tower_godot_floor98_camera_close_south_wall_ph49.png"
const CAMERA_OPEN_SOUTH_DOOR_PATH := OUTPUT_DIR + "/tower_godot_floor98_camera_open_south_door_ph49.png"
const ENTRY_NORTH_SHARED_WALL_PATH := OUTPUT_DIR + "/tower_godot_floor98_entry_north_shared_wall_ph50.png"
const ELEVATOR_PATH := OUTPUT_DIR + "/tower_godot_floor95_stair_elevator_ph49.png"
const STAIR_PATH := OUTPUT_DIR + "/tower_godot_stairwell_global_light_ph49.png"
const BASE_ENTRY_CORRIDOR_PATH := OUTPUT_DIR + "/tower_godot_floor99_base_entry_corridor_ph50.png"
const BOSS_PATH := OUTPUT_DIR + "/tower_godot_floor95_boss_ph49.png"


func _ready() -> void:
	var failures: Array[String] = []
	var original_clock := GameTimeManager.get_persistence_snapshot()
	GameTimeManager.set_clock_running(false)
	GameTimeManager.set_elapsed_game_seconds(23.0 * 3600.0, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()
	tower.player.set_physics_process(false)
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D

	# 现行90×80m天台：在生活设施前采样，旧z=-122已在可玩区域外。
	tower.player.global_position = Vector3(24.0, 0.05, -18.0)
	tower.force_enter_room_for_test("start")
	await _settle()
	_capture(ROOF_PATH, "楼顶画面采样失败", failures)
	var rooftop_stage := (tower.get("_floor_stages") as Dictionary)[0] as TowerFloorStage3D
	var rooftop := rooftop_stage.get("_rooftop_art_instance") as Node3D
	var warm_bulb := rooftop.find_child("聚落串灯_4_自发光", true, false) as Node3D
	if warm_bulb != null:
		tower.player.global_position = Vector3(warm_bulb.global_position.x - 1.8, 0.6, warm_bulb.global_position.z + 3.0)
		await _settle()
		_capture(OUTPUT_DIR + "/tower_rooftop_living_day_v001.png", "生活区白昼采样失败", failures)
		GameTimeManager.set_elapsed_game_seconds(5.0 * 3600.0, false)
		await _settle()
		_capture(OUTPUT_DIR + "/tower_rooftop_living_night_v001.png", "生活区夜晚采样失败", failures)
		GameTimeManager.set_elapsed_game_seconds(23.0 * 3600.0, false)

	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	var base_player_position := facility.global_position + Vector3(0.0, 0.05, 0.0)
	tower.player.global_position = base_player_position
	tower.force_enter_room_for_test("facility")
	facility.ensure_detail_built()
	# 基地开关验收只比较固定室内灯：排除随角色朝向变化的三盏玩家灯。
	if flashlight != null:
		flashlight.set_light_enabled(false)
	await _settle()
	var base_lit_image := _capture_image(
		BASE_LIT_PATH, "99层基地开灯画面采样失败", failures
	)
	var base_switch := facility.get_node_or_null(
		"RoomLightSwitch3D"
	) as RoomLightSwitch3D
	if base_switch != null:
		base_switch.toggle_light()
		await _settle()
		_capture(BASE_DARK_PATH, "99层基地关灯画面采样失败", failures)
		base_switch.toggle_light()
		tower.player.global_position = base_player_position
		if flashlight != null:
			flashlight.set_light_enabled(false)
		await _settle()
		var base_relit_image := _capture_image(
			BASE_RELIT_PATH, "99层基地重新开灯画面采样失败", failures
		)
		if base_lit_image != null and base_relit_image != null:
			var floor_difference := _mean_rgb_difference(
				base_lit_image,
				base_relit_image,
				[
					Rect2i(330, 330, 180, 180),
					Rect2i(770, 330, 180, 180),
				]
			)
			if floor_difference > 0.015:
				failures.append(
					"99层基地初始开灯与重开后的固定地面亮度不一致: %.4f"
					% floor_difference
				)

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
	if not tower.activate_arrival_between_for_test("facility", "floor_01_entry"):
		failures.append("98层到达门未能提交楼层，后续视觉验收无效")
		for failure in failures:
			push_error(failure)
		GameTimeManager.restore_from_persistence(original_clock, false)
		get_tree().quit(1)
		return
	await _settle()
	# 入口房位于东侧楼梯门的左侧/核心内侧；靠近北向枢纽门采样。
	tower.player.global_position = entry.global_position + Vector3(0.0, 0.05, -3.6)
	tower.force_enter_room_for_test("floor_01_entry")
	if flashlight != null:
		flashlight.set_light_enabled(true)
	await _settle()
	_capture(ENTRY_PATH, "98层楼梯入口大厅画面采样失败", failures)

	tower.force_open_edge_for_test("floor_01_entry", "floor_01_hub")
	var entry_north_door := entry.get_door_node("north")
	if entry_north_door != null:
		entry_north_door.set_open(true, true)
		tower.player.global_position = entry_north_door.global_position + Vector3(0.0, 0.05, -0.50)
		await _settle()
		var entry_shared_wall_snapshot := tower.get_tower_snapshot()
		if (
			not bool(entry_shared_wall_snapshot.get("camera_lower_wall_detected", false))
			or tower.player.camera.position.y <= 8.15
			or tower.player.camera.position.z >= 0.40
		):
			failures.append("98层安全房北门外首个连接格没有触发共享南墙镜头")
		_capture(ENTRY_NORTH_SHARED_WALL_PATH, "98层安全房北门外镜头采样失败", failures)
	var hub := (tower.get("_room_by_id") as Dictionary).get("floor_01_hub") as DungeonRoom3D
	tower.player.global_position = hub.global_position + Vector3(0.0, 0.05, 3.5)
	tower.force_enter_room_for_test("floor_01_hub")
	var room_light := hub.find_child("RoomCeilingLight", true, false) as WastelandLight3D
	if room_light != null:
		room_light.set_light_enabled(false)
	if flashlight != null:
		flashlight.set_light_enabled(true)
	await _settle()
	_capture(COMBAT_DARK_PATH, "98层暗室与探照灯画面采样失败", failures)
	# 在约25m极限距离以小角度照墙，验收 Compatibility 阴影贴图不再出现横纹。
	tower.player.global_position = hub.global_position + Vector3(-10.0, 0.05, 0.0)
	tower.player.aim_direction = Vector3.RIGHT
	if flashlight != null:
		flashlight.force_sync()
	await _settle()
	_capture(FLASHLIGHT_FAR_WALL_PATH, "98层探照灯远墙采样失败", failures)
	if room_light != null:
		room_light.set_light_enabled(true)
	if flashlight != null:
		flashlight.set_light_enabled(false)
	await _settle()
	_capture(COMBAT_LIT_PATH, "98层房间开灯画面采样失败", failures)
	var camera_room := _find_room_with_door_direction(tower, "floor_01_", "south")
	if camera_room == null:
		camera_room = hub
	camera_room.set_stream_state(1)
	tower.force_enter_room_for_test(camera_room.room_id)
	var hub_dimensions := camera_room.get_dimensions()
	tower.player.global_position = (
		camera_room.global_position
		+ Vector3(-hub_dimensions.x * 0.5 + 7.5, 0.05, hub_dimensions.y * 0.5 - 0.50)
	)
	await _settle()
	var close_wall_snapshot := tower.get_tower_snapshot()
	if (
		not bool(close_wall_snapshot.get("camera_lower_wall_detected", false))
		or tower.player.camera.position.y <= 8.15
		or tower.player.camera.position.z >= 0.40
	):
		failures.append("98层角色贴南墙时镜头未抬升收回")
	_capture(CAMERA_CLOSE_WALL_PATH, "98层贴南墙镜头画面采样失败", failures)
	var hub_south_door := camera_room.get_door_node("south")
	if hub_south_door != null:
		hub_south_door.set_open(true, true)
		await get_tree().physics_frame
		tower.player.global_position = hub_south_door.global_position + Vector3(0.0, 0.05, -0.50)
		await _settle()
		var open_south_door_snapshot := tower.get_tower_snapshot()
		if (
			not bool(open_south_door_snapshot.get("camera_lower_wall_detected", false))
			or bool(open_south_door_snapshot.get("camera_door_bypass_active", true))
			or tower.player.camera.position.y <= 8.15
			or tower.player.camera.position.z >= 0.40
		):
			failures.append("98层已开启南门门洞中心未触发镜头抬升收回")
		_capture(CAMERA_OPEN_SOUTH_DOOR_PATH, "98层已开启南门镜头画面采样失败", failures)
		hub_south_door.set_open(false, true)
		await get_tree().physics_frame

	if not tower.generate_through_floor_for_test(95):
		failures.append("无法生成至95层，Boss与唯一电梯视觉验收无效")
	await _settle()
	var elevator_access_id := str(
		(tower.get("_elevator_access_room_by_floor") as Dictionary).get(95, "")
	)
	var elevator_room := (tower.get("_room_by_id") as Dictionary).get(
		elevator_access_id
	) as DungeonRoom3D
	var elevator_facility := (
		(tower.get("_elevator_facilities_by_floor") as Dictionary).get(95)
		as BaseFacility3D
	)
	if elevator_room == null or elevator_facility == null:
		failures.append("95→94楼梯间缺少唯一电梯设施")
	else:
		tower.player.global_position = (
		elevator_facility.global_position
		+ elevator_facility.global_basis.z * 2.7
		+ Vector3.UP * 0.05
		)
		tower.force_enter_room_for_test(elevator_access_id)
		tower.player.look_at(elevator_facility.global_position, Vector3.UP)
	if flashlight != null:
		flashlight.set_light_enabled(true)
	await _settle()
	_capture(ELEVATOR_PATH, "95→94楼梯间唯一电梯画面采样失败", failures)

	var stair := _find_vertical_connector(tower, "facility", "floor_01_entry")
	if stair == null:
		failures.append("找不到99—98层楼梯间用于视觉采样")
	else:
		tower.force_open_edge_for_test("facility", "floor_01_entry")
		tower.force_enter_room_for_test("facility")
		var points: Array = stair.get_meta("path_points", [])
		if points.size() >= 4:
			if points.size() >= 11:
				tower.force_enter_room_for_test("facility")
				tower.player.global_position = (points[9] as Vector3).lerp(points[10] as Vector3, 0.5) + Vector3.UP * 0.05
				await _settle()
				_capture(BASE_ENTRY_CORRIDOR_PATH, "99层楼梯到基地入口走廊采样失败", failures)
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
	GameTimeManager.restore_from_persistence(original_clock, false)
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
	_capture_image(path, failure, failures)


func _capture_image(path: String, failure: String, failures: Array[String]) -> Image:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append(failure)
		return null
	return image


func _mean_rgb_difference(first: Image, second: Image, regions: Array) -> float:
	if first.get_size() != second.get_size():
		return INF
	var difference := 0.0
	var sample_count := 0
	for value in regions:
		var region := (value as Rect2i).intersection(Rect2i(Vector2i.ZERO, first.get_size()))
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var a := first.get_pixel(x, y)
				var b := second.get_pixel(x, y)
				difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				sample_count += 3
	return difference / float(maxi(sample_count, 1))


func _find_room_with_door_direction(
	tower: TowerDescent3D,
	room_id_prefix: String,
	direction: String
) -> DungeonRoom3D:
	for room_value in (tower.get("_room_by_id") as Dictionary).values():
		var room := room_value as DungeonRoom3D
		if room == null or not room.room_id.begins_with(room_id_prefix):
			continue
		room.ensure_shell_built()
		if room.get_door_node(direction) != null:
			return room
	return null


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
