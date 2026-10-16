extends Node

const PREVIEW_PATH := "res://outputs/verification/training_range_3d.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	var training := scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	training.player.global_position = Vector3(0, 0.05, -7.0)
	training.equip_combination_for_test("bp_rifle", "mod_bullet_explosive")
	await get_tree().physics_frame
	await get_tree().create_timer(0.75).timeout
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("TrainingRange3D preview viewport is empty")
	elif image.save_png(PREVIEW_PATH) != OK:
		failures.append("TrainingRange3D preview cannot be saved")
	# 组合数必须**现算**：枪身/弹药目录会随蓝图扩充而增长，写死数字会让本验收
	# 在每次加枪后误报（2026-10-16：原写死 59，实际已是 75，白白红了很久）。
	var gunbodies := BlueprintRegistry.get_available_gunbodies(99)
	var bullets := BlueprintRegistry.get_available_bullets(99)
	var ranged_count := 0
	var melee_count := 0
	for gun in gunbodies:
		if "melee" in (gun.get("tags", []) as Array):
			melee_count += 1
		else:
			ranged_count += 1
	var expected_combinations := ranged_count * bullets.size() + melee_count
	var snapshot := training.get_training_snapshot()
	var actual_combinations := int(snapshot.get("combination_count", 0))
	if actual_combinations != expected_combinations or snapshot.get("target_types", []).size() != 3:
		failures.append(
			"TrainingRange3D preview scene is incomplete: %d combinations (expected %d), %d target types"
			% [actual_combinations, expected_combinations, (snapshot.get("target_types", []) as Array).size()]
		)
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TRAINING_RANGE_3D_VISUAL_OK: racks, three lanes, three targets, lights and modular player preview saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
