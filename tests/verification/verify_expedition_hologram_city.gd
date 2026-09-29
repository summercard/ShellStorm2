extends Node3D
const MENU = preload("res://scenes/RogueMapSelectMenu.tscn")
const PLATFORM = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/hologram_terminal_platform/hologram_terminal_platform_root_top3d.tscn")
var failures: Array[String] = []
class RecordingMenu extends RogueMapSelectMenu:
	var requests: Array[String] = []
	func _enter_level(level_id: String) -> void:
		requests.append(level_id)

func _ready() -> void:
	if "--tower" in OS.get_cmdline_user_args():
		await _verify_tower()
		return
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.001, 0.003, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.25, 0.4)
	env.ambient_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var platform := PLATFORM.instantiate() as BaseFacility3D
	add_child(platform)
	platform.position = Vector3(12, -1176, 9)
	var anchor: Vector3 = platform.call("get_hologram_anchor")
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = anchor + Vector3(0, 8, 6)
	camera.look_at(anchor)
	camera.make_current()
	var hud := CanvasLayer.new()
	add_child(hud)
	await get_tree().process_frame
	var menu := RecordingMenu.new()
	menu.set_facility(platform)
	add_child(menu)
	await get_tree().create_timer(0.8).timeout
	_expect(menu._city.deployment > 0.0, "city not starting one second earlier")
	_expect(is_equal_approx(menu._camera.environment.ambient_light_energy, env.ambient_light_energy), "environment darkened before approach")
	await _shot("opening")
	await get_tree().create_timer(0.6).timeout
	_expect(menu._city.deployment > 0.25, "main tower stage not reached")
	_expect(menu._city.site_reveal(1) == 0.0, "99 appeared before its stage")
	await _shot("main_rising")
	await get_tree().create_timer(0.7).timeout
	_expect(menu._city.site_reveal(0) > menu._city.site_reveal(1), "entry stages not staggered")
	await _shot("entries_rising")
	await get_tree().create_timer(2.8).timeout
	_expect(menu._state == "active", "opening did not complete")
	_expect(menu.find_children("*", "Control", true, false).is_empty(), "flat UI remains")
	_expect(menu._city.block_count > 120, "box city missing")
	_expect(menu._city.global_position.distance_to(anchor) < 0.01, "city not on actual facility at nonzero floor")
	_expect(not hud.visible, "HUD not hidden")
	for i in 2:
		var marker: Node3D = menu._city.markers[i]
		var screen: Vector2 = menu._camera.unproject_position(marker.global_position)
		_expect(get_viewport().get_visible_rect().grow(-30).has_point(screen), "entry outside viewport")
		_expect(menu._pick(screen) == i, "world-space picking wrong")
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		Input.parse_input_event(motion)
		await get_tree().process_frame
		_expect(menu._selection == i, "hover input failed")
		var click := InputEventMouseButton.new()
		click.position = screen
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		Input.parse_input_event(click)
		await get_tree().process_frame
	_expect(menu.requests == ["expedition_01", "99"], "mouse clicks routed to wrong levels")
	_expect(menu._city.site_reveal(0) == 1.0 and menu._city.site_reveal(1) == 1.0, "staged sites incomplete")
	await _shot("active")
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	Input.parse_input_event(right)
	await get_tree().process_frame
	_expect(menu._selection == 0, "keyboard selection failed")
	var accept := InputEventKey.new()
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	_expect(menu.requests == ["expedition_01", "99", "expedition_01"], "Enter did not confirm selected building")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_RIGHT
	pad.pressed = true
	Input.parse_input_event(pad)
	await get_tree().process_frame
	_expect(menu._selection == 1, "gamepad direction failed")
	pad = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Input.parse_input_event(pad)
	await get_tree().process_frame
	_expect(menu.requests.back() == "99", "gamepad confirmation failed")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await get_tree().process_frame
	_expect(menu._state == "closing", "cancel skipped transition")
	await get_tree().create_timer(0.9).timeout
	await _shot("closing")
	await get_tree().create_timer(3.1).timeout
	_expect(not is_instance_valid(menu), "menu leaked")
	_expect(camera.current and hud.visible, "camera/HUD not restored")
	var again := MENU.instantiate()
	again.set_facility(platform)
	add_child(again)
	await get_tree().create_timer(0.25).timeout
	again.request_close()
	await get_tree().create_timer(0.5).timeout
	_expect(not is_instance_valid(again), "early cancel leaked")
	if failures.is_empty():
		print("EXPEDITION_HOLOGRAM_CITY_OK anchored=true controls=0 input=passed restore=passed")
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _shot(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_scratch/hologram_city_%s.png" % stage)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _verify_tower() -> void:
	await get_tree().process_frame
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	if "--enter-01" in OS.get_cmdline_user_args() or "--enter-99" in OS.get_cmdline_user_args():
		get_tree().root.add_child(tower)
		get_tree().current_scene = tower
	else:
		add_child(tower)
	await get_tree().create_timer(1.0).timeout
	tower.force_enter_room_for_test("floor_01_entry")
	await get_tree().create_timer(0.5).timeout
	var platform: BaseFacility3D
	for node in get_tree().get_nodes_in_group("base_facility"):
		if node is BaseFacility3D and node.facility_id == "mission_operations" and tower.is_ancestor_of(node):
			platform = node
	if platform == null:
		printerr("FAIL: real tower facility missing")
		get_tree().quit(1)
		return
	tower.player.global_position = platform.to_global(Vector3(5, 0.15, 0.35))
	await get_tree().create_timer(0.5).timeout
	await _shot("tower_before")
	# Use the actual provider and host activation path, not a parallel preview host.
	platform.call("_on_body_entered", tower.player)
	platform.perform_interaction(tower.player, platform.get_interaction_candidate(tower.player))
	await get_tree().create_timer(1.0).timeout
	await _shot("tower_opening")
	await get_tree().create_timer(4.0).timeout
	var menu := tower.get_active_facility_menu()
	_expect(menu is RogueMapSelectMenu, "real facility did not launch city")
	if menu is RogueMapSelectMenu:
		_expect(menu._state == "active", "tower animation incomplete")
		_expect(tower.player.input_locked, "player not locked")
		await _shot("tower_active")

		if "--enter-01" in OS.get_cmdline_user_args() or "--enter-99" in OS.get_cmdline_user_args():
			var index := 1 if "--enter-99" in OS.get_cmdline_user_args() else 0
			var id: String = menu.LEVEL_IDS[index]
			get_tree().current_scene = tower
			BaseManager.register_runtime_checkpoint_provider(tower)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = menu._camera.unproject_position(menu._city.markers[index].global_position)
			Input.parse_input_event(click)
			for step in 300:
				await get_tree().create_timer(0.1).timeout
				var current := get_tree().current_scene
				if current != null and current.scene_file_path == GameDesignConfig.expedition_level_scene(id):
					await get_tree().create_timer(0.5).timeout
					print("HOLOGRAM_REAL_DEPARTURE_OK level=" + id)
					await _shot("arrival_" + id)
					get_tree().quit(0)
					return
			printerr("FAIL: destination not reached " + id)
			get_tree().quit(1)
			return
		menu.request_close()
		await get_tree().create_timer(4.0).timeout
		_expect(tower.get_active_facility_menu() == null, "host did not release modal")
		_expect(not tower.player.input_locked, "host did not unlock player")
		await _shot("tower_return")
	if failures.is_empty():
		print("EXPEDITION_HOLOGRAM_TOWER_OK real_facility=true lock=true restore=true")
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)
