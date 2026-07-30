extends Node
## PH43 楼顶特殊楼梯、连续坡面、下落与落地动作视觉抽样。

const OUTPUT_DIR := "res://outputs/019facd3-bb17-7462-8504-0210c0919463/previews"
const ROOF_STAIR_PATH := OUTPUT_DIR + "/tower_rooftop_stair_lower_wall_camera_arc_ph46.png"
const STAIR_PATH := OUTPUT_DIR + "/tower_continuous_stair_support_ph43.png"
const FALL_PATH := OUTPUT_DIR + "/player_falling_pose_ph43.png"
const LANDING_PATH := OUTPUT_DIR + "/player_landing_pose_ph43.png"


func _ready() -> void:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 4033416533
	add_child(tower)
	await _settle()
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight != null:
		flashlight.set_light_enabled(true)
	tower.force_open_edge_for_test("start", "facility")
	tower.force_enter_room_for_test("start")
	var stair := _find_vertical_connector(tower, "start", "facility")
	if stair == null:
		failures.append("找不到楼顶特殊楼梯")
	else:
		var points: Array = stair.get_meta("path_points", [])
		tower.player.global_position = (points[1] as Vector3) + Vector3.UP * 0.04
		await _settle_physics(45)
		_capture(ROOF_STAIR_PATH, failures)
		tower.player.global_position = (
			(points[2] as Vector3).lerp(points[3] as Vector3, 0.55)
			+ Vector3.UP * 0.04
		)
		await _settle()
		_capture(STAIR_PATH, failures)

	tower.player.global_position = Vector3(8.0, 3.2, -8.0)
	tower.player.velocity = Vector3.ZERO
	for _frame in range(90):
		await get_tree().physics_frame
		await get_tree().process_frame
		if tower.player.get_state_machine_state() == "falling":
			tower.player.avatar.call("_process", 0.06)
			_capture(FALL_PATH, failures)
			break
	for _frame in range(120):
		await get_tree().physics_frame
		await get_tree().process_frame
		if tower.player.get_state_machine_state() == "landing":
			tower.player.avatar.call("_process", 0.06)
			_capture(LANDING_PATH, failures)
			break

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PH43_STAIR_FALL_VISUAL_OK: rooftop camera, stair support, falling and landing previews saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.20).timeout


func _settle_physics(frames: int) -> void:
	for _frame in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture(path: String, failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append("无法保存 %s" % path)


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
