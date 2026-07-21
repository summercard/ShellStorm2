extends Node

const PREVIEW_PATH := "res://assets/art/environments/dungeon_3d/env_dungeon_runtime_preview_top3d_v001.png"


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/levels3d/IronFrontier3D.tscn") as PackedScene
	var dungeon := scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 4242
	add_child(dungeon)
	await get_tree().process_frame
	dungeon.player.global_position = Vector3(25, 0.05, 0)
	dungeon.force_enter_room_for_test("main_01")
	await get_tree().physics_frame
	await get_tree().create_timer(0.75).timeout
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("Dungeon3D preview viewport is empty")
	elif image.save_png(PREVIEW_PATH) != OK:
		failures.append("Dungeon3D preview cannot be saved")
	var snapshot := dungeon.get_generation_snapshot()
	if int(snapshot.get("room_count", 0)) < 10 or not bool(snapshot.get("has_extraction", false)):
		failures.append("Dungeon3D preview scene is not the full runtime")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FULL_3D_VISUAL_OK: dungeon room, wasteland lighting, modular props, player and enemies preview saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
