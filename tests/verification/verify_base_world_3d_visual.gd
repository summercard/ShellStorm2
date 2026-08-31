extends Node

const PREVIEW_PATH := "res://outputs/verification/base_world_3d.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var scene := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	if scene == null:
		failures.append("BaseWorld3D visual scene does not load")
		_finish(failures)
		return
	LevelSelect.return_entrance_id = ""
	var world := scene.instantiate() as BaseWorld3D
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.65).timeout
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("BaseWorld3D viewport preview is empty")
	else:
		var save_error := image.save_png(PREVIEW_PATH)
		if save_error != OK:
			failures.append("BaseWorld3D preview cannot be saved")
	var snapshot := world.player.avatar.get_component_snapshot()
	if int(snapshot.get("component_count", 0)) != 4 or int(snapshot.get("visible_hand_count", 0)) != 2:
		failures.append("3D preview does not use the modular bunny avatar")
	if world.get_node_or_null("Facilities/BaseConsole") != null:
		failures.append("Removed base management terminal still exists in visual scene")
	if world.get_node_or_null("Facilities/Divination") != null:
		failures.append("Removed fate divination facility still exists in visual scene")
	var facilities := world.get_node_or_null("Facilities")
	if facilities == null or facilities.get_child_count() != 9:
		failures.append("Base visual scene does not contain the expected nine remaining catalog facilities")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_WORLD_3D_VISUAL_OK: 1280x720 world preview saved with nine remaining facilities")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
