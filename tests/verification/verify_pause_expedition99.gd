extends Node

const MAIN := preload("res://scenes/TowerDescent3D.tscn")
const TARGET := "res://scenes/ExpeditionLevel99_3D.tscn"
var failures := 0
var pad := "--pad" in OS.get_cmdline_user_args()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("ESC99 ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.has_feature("editor"):
		check(false, "requires windowed editor engine")
		get_tree().quit(1)
		return
	var tree := get_tree()
	# Keep the runner outside current_scene so it can observe the real replacement.
	var tower := MAIN.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_SCENE_REENTRY, GameEntryFlow.SPAWN_BASE_99F)
	tree.root.add_child(tower)
	tree.current_scene = tower
	await tree.process_frame
	var menu := tower.get_node("HUD/PauseOverlay") as PauseMenu3D
	# Move out and back within one frame so the real traversal controller does not start a stair transition.
	var base_spawn := tower.player.global_position
	tower.player.global_position = Vector3(-17.5, 0.10, 2.5)
	check(not tower.can_launch_expedition_test_from_pause(), "rooftop is not the safe base floor")
	tower.player.global_position = base_spawn
	await _tap(KEY_ESCAPE, JOY_BUTTON_START, true)
	check(menu.is_pause_open() and tree.paused, "Esc/Start opens real pause")
	check(menu.expedition_99_button.is_visible_in_tree() and menu.expedition_99_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "base test entry fits inside viewport")
	check(menu.resume_button.has_focus(), "resume owns default focus")
	check(menu.graphics_button.is_visible_in_tree() and menu.controls_button.is_visible_in_tree() and menu.training_range_button.is_visible_in_tree() and menu.reset_game_save_button.is_visible_in_tree(), "other pause actions remain")
	for i in range(6):
		if menu.expedition_99_button.has_focus():
			break
		await _tap(KEY_UP, JOY_BUTTON_DPAD_UP, false)
	check(menu.expedition_99_button.has_focus(), "directional input reaches test button")
	if not menu.expedition_99_button.has_focus():
		get_tree().quit(1)
		return
	var screenshot := OS.get_environment("SS_ESC99_SCREENSHOT")
	if not screenshot.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(screenshot)
	Global.acquire_pause("verify_other_owner")
	await _tap(KEY_ENTER, JOY_BUTTON_A, true)
	check(tree.current_scene == tower and Global.has_pause_reason("manual") and Global.has_pause_reason("verify_other_owner") and GameDesignConfig.pending_expedition_level_id.is_empty(), "other pause owner blocks departure without clearing locks")
	Global.release_pause("verify_other_owner")
	await _tap(KEY_ENTER, JOY_BUTTON_A, true)
	var saw_loading := false
	var deadline := Time.get_ticks_msec() + 120000
	var arrived := false
	while Time.get_ticks_msec() < deadline:
		var scene := tree.current_scene
		if scene != null and scene.scene_file_path == TARGET and not IrisTransition.is_loading_active() and not IrisTransition.is_covered():
			arrived = true
			break
		saw_loading = saw_loading or IrisTransition.is_loading_active()
		await tree.process_frame
	check(saw_loading and arrived, "input traverses production loader and arrives in 99")
	check(arrived and not tree.paused and not Global.has_pause_reason("manual") and GameDesignConfig.pending_expedition_level_id.is_empty(), "no pause or pending selection leaks to 99")
	if arrived:
		var arrived_menu := tree.current_scene.get_node("HUD/PauseOverlay") as PauseMenu3D
		await _tap(KEY_ESCAPE, JOY_BUTTON_START, true)
		check(not arrived_menu.expedition_99_button.visible, "expedition never exposes the test shortcut")
		if arrived_menu.is_pause_open():
			await _tap(KEY_ESCAPE, JOY_BUTTON_START, true)
	print("ESC99_RESULT ", "pad" if pad else "keyboard", " failures=", failures)
	tree.quit(0 if failures == 0 else 1)

func _tap(key: Key, button: JoyButton, physical: bool) -> void:
	for pressed: bool in [true, false]:
		if pad:
			var ev := InputEventJoypadButton.new()
			ev.device = 0
			ev.button_index = button
			ev.pressed = pressed
			ev.pressure = 1.0 if pressed else 0.0
			Input.parse_input_event(ev)
		else:
			var ev := InputEventKey.new()
			if physical:
				ev.physical_keycode = key
			else:
				ev.keycode = key
			ev.pressed = pressed
			Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await get_tree().process_frame
