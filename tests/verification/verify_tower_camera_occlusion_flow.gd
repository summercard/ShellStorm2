extends Node
## 真实场景专项：只有房间南面朝北的墙响应镜头；楼梯/侧墙不触发抬升。


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle(3)

	var facility := (
		tower.get("_room_by_id") as Dictionary
	).get("facility") as DungeonRoom3D
	var dimensions := facility.get_dimensions()
	tower.force_enter_room_for_test("facility")
	tower.player.global_position = (
		facility.global_position
		+ Vector3(0.0, 0.05, dimensions.y * 0.5 - 1.2)
	)
	await _settle(45)
	var facility_snapshot := tower.get_tower_snapshot()
	print("v0.1_REAL_FACILITY_CAMERA ", {
		"player": tower.player.global_position,
		"camera_local": tower.player.camera.position,
		"detected": facility_snapshot.get("camera_lower_wall_detected"),
		"distance": facility_snapshot.get("camera_lower_wall_distance_m"),
		"lift": facility_snapshot.get("camera_lift_current_m"),
		"trailing": facility_snapshot.get("camera_trailing_current_m"),
		"occluded": facility_snapshot.get("camera_occluded_player"),
	})
	_expect_real_wall_cleared("99层基地南墙", tower, facility_snapshot, failures)

	# 98层枢纽南侧同时覆盖门墙与SW拐角，防止内部门墙碰撞抢先命中却
	# 没有镜头标记，或L角两臂共用一个StaticBody导致漏检/误检。
	var hub := (
		(tower.get("_room_by_id") as Dictionary).get("floor_01_hub")
		as DungeonRoom3D
	)
	hub.set_stream_state(1)
	tower.force_enter_room_for_test("floor_01_hub")
	var south_door := hub.get_door_node("south")
	if south_door == null:
		failures.append("98层枢纽缺少南侧门墙，无法验收镜头碰撞")
	else:
		tower.player.global_position = south_door.global_position + Vector3(0.0, 0.05, -1.2)
		await _settle(45)
		_expect_real_wall_cleared(
			"98层枢纽南侧门墙", tower, tower.get_tower_snapshot(), failures
		)
		south_door.set_open(true, true)
		await get_tree().physics_frame
		tower.player.global_position = south_door.global_position + Vector3(0.0, 0.05, -0.50)
		await _settle(45)
		var open_south_door_snapshot := tower.get_tower_snapshot()
		if bool(open_south_door_snapshot.get("camera_door_bypass_active", true)):
			failures.append("98层已开启南门仍错误进入镜头旁路")
		_expect_real_wall_cleared(
			"98层已开启南门门洞中心", tower, open_south_door_snapshot, failures
		)
		south_door.set_open(false, true)
		await get_tree().physics_frame
	var hub_dimensions := hub.get_dimensions()
	tower.player.global_position = (
		hub.global_position
		+ Vector3(-hub_dimensions.x * 0.5 + 1.0, 0.05, hub_dimensions.y * 0.5 - 1.2)
	)
	await _settle(45)
	_expect_real_wall_cleared(
		"98层枢纽SW拐角南墙臂", tower, tower.get_tower_snapshot(), failures
	)
	tower.player.global_position = (
		hub.global_position
		+ Vector3(-hub_dimensions.x * 0.5 + 7.5, 0.05, hub_dimensions.y * 0.5 - 0.50)
	)
	await _settle(45)
	_expect_real_wall_cleared(
		"98层枢纽角色贴墙状态", tower, tower.get_tower_snapshot(), failures
	)

	tower.force_open_edge_for_test("start", "facility")
	tower.force_enter_room_for_test("start")
	var stair := _find_vertical_connector(tower, "start", "facility")
	if stair != null:
		var points: Array = stair.get_meta("path_points", [])
		tower.player.global_position = (points[1] as Vector3) + Vector3.UP * 0.04
		await _settle(45)
		var stair_snapshot := tower.get_tower_snapshot()
		print("v0.1_REAL_STAIR_CAMERA ", {
			"player": tower.player.global_position,
			"camera_local": tower.player.camera.position,
			"detected": stair_snapshot.get("camera_lower_wall_detected"),
			"distance": stair_snapshot.get("camera_lower_wall_distance_m"),
			"lift": stair_snapshot.get("camera_lift_current_m"),
			"trailing": stair_snapshot.get("camera_trailing_current_m"),
			"occluded": stair_snapshot.get("camera_occluded_player"),
			"near_faded": stair_snapshot.get("camera_near_faded_mesh_count"),
			"door_bypass": stair_snapshot.get("camera_door_bypass_active"),
		})
		_expect_real_door_bypass(
			"楼顶特殊楼梯已开启门槛",
			tower,
			stair_snapshot,
			failures
		)
		tower.player.global_position = (
			(points[4] as Vector3) + Vector3.UP * 0.04
		)
		# 把角色向楼梯平台围护墙再推 1.2m，确保墙进入 65° 俯视默认镜头管（2.77m）。
		var facing := tower.player.global_basis.z
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			facing = facing.normalized()
		else:
			facing = Vector3.BACK
		tower.player.global_position += facing * 1.2
		await _settle(45)
		var stair_wall_snapshot := tower.get_tower_snapshot()
		print("v0.1_REAL_STAIR_WALL_CAMERA ", {
			"player": tower.player.global_position,
			"camera_local": tower.player.camera.position,
			"detected": stair_wall_snapshot.get("camera_lower_wall_detected"),
			"distance": stair_wall_snapshot.get("camera_lower_wall_distance_m"),
			"door_bypass": stair_wall_snapshot.get("camera_door_bypass_active"),
		})
		if bool(stair_wall_snapshot.get("camera_door_bypass_active", true)):
			failures.append("离开窄门槛后楼梯平台仍错误保持门洞旁路")
		_expect_non_south_wall_ignored(
			"楼梯平台StairwellWall围护墙", tower, stair_wall_snapshot, failures
		)
	else:
		failures.append("没有找到楼顶到基地的真实楼梯连接器")

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("v0.1_REAL_CAMERA_FLOW_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("v0.1_REAL_CAMERA_FLOW_FAIL: %s" % failure)
	get_tree().quit(1)


func _expect_real_wall_cleared(
	label: String,
	tower: TowerDescent3D,
	snapshot: Dictionary,
	failures: Array[String]
) -> void:
	var distance := float(snapshot.get("camera_lower_wall_distance_m", -1.0))
	var trailing := tower.player.camera.position.z
	if not bool(snapshot.get("camera_lower_wall_detected", false)):
		failures.append("%s没有被下方墙探针识别" % label)
	if distance <= 0.0 or trailing >= distance - 0.08:
		failures.append(
			"%s镜头未收回墙内侧：墙距%.3fm，镜头后移%.3fm"
			% [label, distance, trailing]
		)
	if bool(snapshot.get("camera_occluded_player", true)):
		failures.append("%s收镜后仍有黑墙遮住角色" % label)
	if (
		tower.player.camera.position.y <= 8.20
		or tower.player.camera.position.y > 8.301
	):
		failures.append(
			"%s镜头抬升高度异常：%.3fm"
			% [label, tower.player.camera.position.y]
		)
	if (
		not bool(snapshot.get("camera_yaw_locked", false))
		or not bool(snapshot.get("camera_horizontal_pose_fixed", false))
		or str(snapshot.get("camera_collision_mode", ""))
			!= "lower_wall_lift_and_retract_arc"
	):
		failures.append("%s没有保持固定视角抬升收拢契约" % label)


func _expect_non_south_wall_ignored(
	label: String,
	tower: TowerDescent3D,
	snapshot: Dictionary,
	failures: Array[String]
) -> void:
	if bool(snapshot.get("camera_lower_wall_detected", true)):
		failures.append("%s错误触发了仅限南墙的镜头交互" % label)
	if (
		absf(tower.player.camera.position.y - 8.0) > 0.02
		or absf(tower.player.camera.position.z - 2.77) > 0.03
	):
		failures.append("%s错误改变了固定镜头位置：%s" % [label, tower.player.camera.position])


func _expect_real_door_bypass(
	label: String,
	tower: TowerDescent3D,
	snapshot: Dictionary,
	failures: Array[String]
) -> void:
	if not bool(snapshot.get("camera_door_bypass_active", false)):
		failures.append("%s没有进入门洞镜头旁路" % label)
	if bool(snapshot.get("camera_lower_wall_detected", true)):
		failures.append("%s仍触发了下方墙探测" % label)
	if int(snapshot.get("camera_near_faded_mesh_count", -1)) != 0:
		failures.append("%s仍在淡出门板或门楣" % label)
	if (
		absf(tower.player.camera.position.y - 8.0) > 0.01
		or absf(tower.player.camera.position.z - 2.77) > 0.03
		or absf(tower.player.camera.position.x) > 0.001
	):
		failures.append(
			"%s没有以固定镜头过门：%s"
			% [label, str(tower.player.camera.position)]
		)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame


func _find_vertical_connector(
	tower: TowerDescent3D,
	a: String,
	b: String
) -> Node3D:
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or not bool(
			connector.get_meta("is_vertical_connector", false)
		):
			continue
		var ids := [
			str(connector.get_meta("from_room_id", "")),
			str(connector.get_meta("to_room_id", "")),
		]
		if a in ids and b in ids:
			return connector
	return null
