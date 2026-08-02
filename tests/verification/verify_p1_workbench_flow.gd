extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var player_scene: PackedScene = load("res://scenes/Player.tscn") as PackedScene
	var panel_scene: PackedScene = load("res://scenes/WorkbenchPanel.tscn") as PackedScene
	if player_scene == null:
		failures.append("Player scene does not load")
	if panel_scene == null:
		failures.append("WorkbenchPanel scene does not load")
	if not failures.is_empty():
		_finish(failures)
		return

	var player: Node = player_scene.instantiate()
	add_child(player)

	var panel: Control = panel_scene.instantiate() as Control
	panel.set_player(player)
	add_child(panel)
	await get_tree().process_frame

	var transform_button: Button = panel.get("_transform_button") as Button
	if transform_button == null:
		failures.append("WorkbenchPanel has no transform mode button")
	else:
		if transform_button.get_parent() == null:
			failures.append("Transform mode button is removed during initial option build")
		if not str(transform_button.text).contains("命运改造"):
			failures.append("Initial workbench mode does not invite fate transformation")

	var press_t := InputEventKey.new()
	press_t.keycode = KEY_T
	press_t.physical_keycode = KEY_T
	press_t.pressed = true
	panel._input(press_t)
	await get_tree().process_frame
	if not bool(panel.get("_transform_mode")):
		failures.append("Pressing T once does not switch to fate transform mode")
	if transform_button != null and (transform_button.get_parent() == null or not str(transform_button.text).contains("基础改造")):
		failures.append("Fate transform mode does not keep a readable button to return")

	var echo_t := InputEventKey.new()
	echo_t.keycode = KEY_T
	echo_t.physical_keycode = KEY_T
	echo_t.pressed = true
	echo_t.echo = true
	panel._input(echo_t)
	await get_tree().process_frame
	if not bool(panel.get("_transform_mode")):
		failures.append("Holding T causes repeated mode toggles")

	panel._input(press_t)
	await get_tree().process_frame
	if bool(panel.get("_transform_mode")):
		failures.append("Pressing T again does not return to blueprint mode")
	if transform_button != null and (transform_button.get_parent() == null or not str(transform_button.text).contains("命运改造")):
		failures.append("Blueprint mode does not restore the fate transform affordance")

	_finish(failures)

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("P1_WORKBENCH_FLOW_OK: Workbench transform mode toggles once per press and remains readable")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
