extends Node
## PH48真实场景专项：普通墙和楼梯墙保留响应，仅已开启门的窄门槛固定镜头。


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
	print("PH46_REAL_FACILITY_CAMERA ", {
		"player": tower.player.global_position,
		"camera_local": tower.player.camera.position,
		"detected": facility_snapshot.get("camera_lower_wall_detected"),
		"distance": facility_snapshot.get("camera_lower_wall_distance_m"),
		"lift": facility_snapshot.get("camera_lift_current_m"),
		"trailing": facility_snapshot.get("camera_trailing_current_m"),
		"occluded": facility_snapshot.get("camera_occluded_player"),
	})
	_expect_real_wall_cleared("99层基地南墙", tower, facility_snapshot, failures)

	tower.force_open_edge_for_test("start", "facility")
	tower.force_enter_room_for_test("start")
	var stair := _find_vertical_connector(tower, "start", "facility")
	if stair != null:
		var points: Array = stair.get_meta("path_points", [])
		tower.player.global_position = (points[1] as Vector3) + Vector3.UP * 0.04
		await _settle(45)
		var stair_snapshot := tower.get_tower_snapshot()
		print("PH46_REAL_STAIR_CAMERA ", {
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
		print("PH48_REAL_STAIR_WALL_CAMERA ", {
			"player": tower.player.global_position,
			"camera_local": tower.player.camera.position,
			"detected": stair_wall_snapshot.get("camera_lower_wall_detected"),
			"distance": stair_wall_snapshot.get("camera_lower_wall_distance_m"),
			"door_bypass": stair_wall_snapshot.get("camera_door_bypass_active"),
		})
		if bool(stair_wall_snapshot.get("camera_door_bypass_active", true)):
			failures.append("离开窄门槛后楼梯平台仍错误保持门洞旁路")
		_expect_real_wall_cleared(
			"楼梯平台StairwellWall围护墙",
			tower,
			stair_wall_snapshot,
			failures
		)
	else:
		failures.append("没有找到楼顶到基地的真实楼梯连接器")

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PH46_REAL_CAMERA_FLOW_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("PH46_REAL_CAMERA_FLOW_FAIL: %s" % failure)
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
	if distance <= 0.0 or trailing >= distance - 0.30:
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
