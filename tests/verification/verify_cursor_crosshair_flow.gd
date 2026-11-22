extends Node

const TRAINING_SCENE := preload("res://scenes/TrainingRange3D.tscn")


class LoadingFixture extends ExpeditionLoadingScreen:
	var fail_request := true

	func _start_after_intro() -> void:
		pass

	func _start_resource_request() -> void:
		if fail_request:
			_show_failure("resource", "Cursor test: simulated loading failure")


var _failures: Array[String] = []
var _samples := 0
var _native_mouse := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_native_mouse = DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)
	call_deferred("_run")


func _run() -> void:
	if _native_mouse:
		get_window().grab_focus()
		await _settle()
		_expect(get_window().has_focus(), "real-window probe requires focus")
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	var mode := UiCursorMode.Presentation
	await _check_state("menu without a world", mode.UI, Input.MOUSE_MODE_VISIBLE)

	var training := TRAINING_SCENE.instantiate() as TrainingRange3D
	training.test_mode = true
	training.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(training)
	var player := training.get_node("Player3D") as Player3D
	var inventory := training.get_node("HUD/InventoryUI3D") as InventoryUI
	var pause := training.get_node("HUD/PauseOverlay") as PauseMenu3D
	await _check_state("training", mode.AIM, Input.MOUSE_MODE_CONFINED_HIDDEN, player.aim_cursor)

	player.set_physics_process(false)
	player._mobile_input_available = true
	player._mobile_face_active = true
	player._mobile_face_direction = Vector2.RIGHT
	player._update_aim_from_mouse()
	var original_aim := player.aim_cursor.global_position

	inventory.toggle_inventory_panel()
	await _check_state("inventory", mode.UI, Input.MOUSE_MODE_VISIBLE, player.aim_cursor)
	_expect(player.input_locked, "inventory should keep its input lock")
	player._mobile_face_direction = Vector2.LEFT
	player._update_aim_from_mouse()
	_expect(player.aim_cursor.global_position.is_equal_approx(original_aim), "inventory changed aim target")
	pause.set_paused(true)
	await _check_state("pause over inventory", mode.UI, Input.MOUSE_MODE_VISIBLE, player.aim_cursor)
	pause.resume_game()
	await _check_state("resume to inventory", mode.UI, Input.MOUSE_MODE_VISIBLE, player.aim_cursor)
	inventory.toggle_inventory_panel()
	await _check_state("close inventory", mode.AIM, Input.MOUSE_MODE_CONFINED_HIDDEN, player.aim_cursor)
	player._update_aim_from_mouse()
	_expect(not player.aim_cursor.global_position.is_equal_approx(original_aim), "aim did not update after returning")

	InputDevice.force_device(InputDevice.DEVICE_GAMEPAD)
	await _check_state("gamepad aiming", mode.AIM, Input.MOUSE_MODE_HIDDEN, player.aim_cursor)
	pause.set_paused(true)
	await _check_state("gamepad pause", mode.UI, Input.MOUSE_MODE_HIDDEN, player.aim_cursor)
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	await _check_state("mouse pause", mode.UI, Input.MOUSE_MODE_VISIBLE, player.aim_cursor)
	pause.resume_game()
	player.set_aim_locked(true)
	await _check_state("scripted hold", mode.HIDDEN, Input.MOUSE_MODE_HIDDEN, player.aim_cursor)
	player.set_aim_locked(false)

	var loading := LoadingFixture.new()
	add_child(loading)
	await _check_state("loading over a ready world", mode.HIDDEN, Input.MOUSE_MODE_HIDDEN, player.aim_cursor)
	loading._start_resource_request()
	await _check_state("loading failure", mode.UI, Input.MOUSE_MODE_VISIBLE, player.aim_cursor)
	loading.fail_request = false
	loading._on_retry_pressed()
	await _check_state("retry", mode.HIDDEN, Input.MOUSE_MODE_HIDDEN, player.aim_cursor)

	var next_reticle := Node3D.new()
	add_child(next_reticle)
	UiCursorMode.bind_world(next_reticle, func() -> UiCursorMode.Presentation: return mode.AIM)
	training.queue_free()
	await _check_state("old world exits under loading", mode.HIDDEN, Input.MOUSE_MODE_HIDDEN, next_reticle)
	loading.queue_free()
	await _check_state("loading hands off to new world", mode.AIM, Input.MOUSE_MODE_CONFINED_HIDDEN, next_reticle)
	next_reticle.queue_free()
	await _check_state("world exit to menu", mode.UI, Input.MOUSE_MODE_VISIBLE)

	if _failures.is_empty():
		print("CURSOR_CROSSHAIR_FLOW_OK samples=%d native_mouse=%s" % [_samples, _native_mouse])
	else:
		for failure in _failures:
			push_error("CURSOR_CROSSHAIR_FLOW_FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _settle() -> void:
	# The always-processing manager applies world changes on the next process pass.
	await get_tree().process_frame
	await get_tree().process_frame


func _check_state(
	label: String, expected: UiCursorMode.Presentation, mouse_mode: Input.MouseMode, reticle: Node3D = null
) -> void:
	await _settle()
	var actual := UiCursorMode.get_presentation()
	_expect(actual == expected, "%s presentation = %s, expected %s" % [label, actual, expected])
	if reticle != null:
		_expect(reticle.is_visible_in_tree() == (expected == UiCursorMode.Presentation.AIM), label + " reticle")
	if _native_mouse:
		_expect(Input.mouse_mode == mouse_mode, "%s mouse = %s, expected %s" % [label, Input.mouse_mode, mouse_mode])


func _expect(condition: bool, message: String) -> void:
	_samples += 1
	if not condition:
		_failures.append(message)
