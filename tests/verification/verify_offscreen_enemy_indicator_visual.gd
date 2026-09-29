extends Node
## 屏幕外怪物指示箭头 · 真实渲染验收（注册 `visual`）。
##
## 逻辑断言见 `verify_offscreen_enemy_indicator`（注册 `core`，无头跑）。这里只问一件事：
## **真渲染出来了吗** —— 四条边的箭头在画面像素上确实是红的，且把目标清空后红色消失。
## 四支箭头用相机自己的三个轴摆位，与具体房间无关，因此这套像素断言不随版图漂移。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const OUTPUT_DIR := "res://outputs/verification"
const SCREENSHOT_NAME := "offscreen_enemy_indicator.png"
const CONTROL_SCREENSHOT_NAME := "offscreen_enemy_indicator_targets_cleared.png"
## 采样半径：箭头最长 18 px、外发光再放大 1.75 倍 ⇒ 14 px 足以覆盖整支箭头。
const SAMPLE_RADIUS_PX := 14
const MIN_RED_PIXELS_PER_ARROW := 4


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 12:
		await get_tree().process_frame
	dungeon.force_enter_room_for_test(_first_hostile_room_id(dungeon))
	for _frame in 20:
		await get_tree().process_frame
	# 冻结战局自身的喂数，否则它每 1/20 s 会把真实怪的位置覆盖掉确定性目标。
	dungeon.set_process(false)

	var indicator := dungeon.get_node_or_null("HUD/OffscreenEnemyIndicator3D") as OffscreenEnemyIndicator3D
	_expect(indicator != null, "HUD 下没有装屏幕外指示箭头层", failures)
	var camera := get_viewport().get_camera_3d()
	_expect(camera != null, "战局没有活动相机", failures)
	if indicator == null or camera == null:
		_finish(failures, dungeon)
		return

	var forward := -camera.global_transform.basis.z
	var right_axis := camera.global_transform.basis.x
	var up_axis := camera.global_transform.basis.y
	var on_screen_target := camera.global_position + forward * 12.0
	var edge_targets: Array[Vector3] = [
		camera.global_position + forward * 30.0 + right_axis * 200.0,
		camera.global_position + forward * 30.0 - right_axis * 200.0,
		camera.global_position + forward * 30.0 + up_axis * 200.0,
		camera.global_position - forward * 30.0 - up_axis * 200.0,
	]
	var with_screen_target: Array[Vector3] = edge_targets.duplicate()
	with_screen_target.append(on_screen_target)

	indicator.set_targets(with_screen_target, camera)
	for _frame in 4:
		await get_tree().process_frame
	var snapshot := indicator.get_snapshot()
	_expect(
		int(snapshot.get("marker_count", 0)) == 4,
		"四条边上的目标没有各生成一支箭头：marker_count=%d" % int(snapshot.get("marker_count", 0)),
		failures
	)
	_expect(
		int(snapshot.get("on_screen_count", 0)) == 1,
		"画面内的目标没有按「屏内不画」处理：on_screen_count=%d"
		% int(snapshot.get("on_screen_count", 0)),
		failures
	)

	var image := get_viewport().get_texture().get_image()
	_expect(image != null, "取不到渲染结果（真实渲染器未启用？）", failures)
	if image == null:
		_finish(failures, dungeon)
		return
	_expect(_save(image, SCREENSHOT_NAME), "箭头截图没有写盘", failures)

	var red_before: Array[int] = []
	for marker_value in snapshot.get("markers", []):
		var marker: Dictionary = marker_value
		var point: Vector2 = marker.get("screen_point", Vector2.ZERO)
		var hits := _count_arrow_pixels(image, point)
		red_before.append(hits)
		_expect(
			hits >= MIN_RED_PIXELS_PER_ARROW,
			"边缘点 %s 附近没有画红箭头（红像素 %d）" % [point.round(), hits],
			failures
		)

	# A/B：清空目标后同一点位的红色必须消失 —— 证明上面数到的红像素来自箭头，不是场景里的红色物件。
	indicator.set_targets([], camera)
	for _frame in 4:
		await get_tree().process_frame
	var cleared_image := get_viewport().get_texture().get_image()
	_expect(cleared_image != null, "清空目标后取不到渲染结果", failures)
	if cleared_image != null:
		_expect(_save(cleared_image, CONTROL_SCREENSHOT_NAME), "对照截图没有写盘", failures)
		var total_before := 0
		var total_after := 0
		var markers: Array = snapshot.get("markers", [])
		for index in markers.size():
			var point: Vector2 = (markers[index] as Dictionary).get("screen_point", Vector2.ZERO)
			total_before += red_before[index]
			total_after += _count_arrow_pixels(cleared_image, point)
		_expect(
			total_after < total_before,
			"清空目标后红箭头仍然在画（对照 %d 红像素 vs 原 %d）" % [total_after, total_before],
			failures
		)

	_finish(failures, dungeon)


func _first_hostile_room_id(dungeon: Dungeon3D) -> String:
	var room_by_id: Dictionary = dungeon.get("_room_by_id")
	for room_id_value in room_by_id.keys():
		var room := room_by_id[room_id_value] as DungeonRoom3D
		if room != null and GameDesignConfig.ROOM_TYPES_WITH_HOSTILES.has(room.room_type):
			if not room.enemy_spawn_points.is_empty():
				return str(room_id_value)
	return ""


func _count_arrow_pixels(image: Image, center: Vector2) -> int:
	var count := 0
	var min_x := maxi(0, int(center.x) - SAMPLE_RADIUS_PX)
	var max_x := mini(image.get_width() - 1, int(center.x) + SAMPLE_RADIUS_PX)
	var min_y := maxi(0, int(center.y) - SAMPLE_RADIUS_PX)
	var max_y := mini(image.get_height() - 1, int(center.y) + SAMPLE_RADIUS_PX)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pixel := image.get_pixel(x, y)
			# 危险红（0.96, 0.08, 0.14）：红通道显著高于绿蓝才算数，
			# 阈值放宽到 1.8 倍是为了容纳后处理层的轻微偏色。
			if pixel.r > 0.35 and pixel.r > pixel.g * 1.8 and pixel.r > pixel.b * 1.8:
				count += 1
	return count


func _save(image: Image, file_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	return image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String], dungeon: Dungeon3D) -> void:
	if dungeon != null and is_instance_valid(dungeon):
		dungeon.queue_free()
	if failures.is_empty():
		print("OFFSCREEN_ENEMY_INDICATOR_VISUAL_OK: edge arrows render in danger red and vanish when targets clear")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
