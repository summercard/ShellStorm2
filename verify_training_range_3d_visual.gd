extends Node

const PREVIEW_PATH := "res://assets/art/environments/training_range_3d/env_training_range_preview_top3d_v001.png"


func _ready() -> void:
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
	var snapshot := training.get_training_snapshot()
	if int(snapshot.get("combination_count", 0)) != 56 or snapshot.get("target_types", []).size() != 3:
		failures.append("TrainingRange3D preview scene is incomplete")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TRAINING_RANGE_3D_VISUAL_OK: racks, three lanes, three targets, lights and modular player preview saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
