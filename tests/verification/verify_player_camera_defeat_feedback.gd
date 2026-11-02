extends Node3D
## Run in a project with user data isolated BEFORE Autoload startup.
## Add -- --capture-dir=<absolute external path> with a real renderer for pixel QA.

const FEEDBACK := preload("res://src/player3d/PlayerCameraFeedback3D.gd")
var failures: Array[String] = []
var checks := 0
var capture_dir := ""
var _damage_events := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("FEEDBACK_FAIL ", reason)


func _run() -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	_verify_look_model()
	for path in ["res://scenes/TowerDescent3D.tscn", "res://scenes/ExpeditionLevel03_3D.tscn"]:
		if "--tower-only" in OS.get_cmdline_user_args() and "Expedition" in path:
			continue
		await _verify_runtime(path)
	print("PLAYER_CAMERA_DEFEAT_FEEDBACK checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_look_model() -> void:
	var feedback := FEEDBACK.new()
	var size := Vector2(1280, 720)
	feedback.advance_look(1.0, Vector2(40, 0), size, Vector3.RIGHT, Vector3.BACK, true)
	check(feedback.look_offset.is_zero_approx(), "body dead zone must stay centered")
	feedback.advance_look(1.0 / 60.0, Vector2(600, 0), size, Vector3.RIGHT, Vector3.BACK, true)
	check(feedback.look_offset.x > 0.0 and feedback.look_offset.x < 0.3, "look must ease in, never jump")
	for i in 120:
		feedback.advance_look(1.0 / 60.0, Vector2(600, 0), size, Vector3.RIGHT, Vector3.BACK, true)
	check(is_equal_approx(feedback.look_offset.length(), FEEDBACK.LOOK_MAX_M), "look maximum is bounded")
	for i in 120:
		feedback.advance_look(1.0 / 60.0, Vector2(-600, -300), size, Vector3.RIGHT, Vector3.BACK, true)
	check(feedback.look_offset.x < 0 and feedback.look_offset.z > 0, "reverse and diagonal look direction")
	check(feedback.look_offset.length() <= FEEDBACK.LOOK_MAX_M + 0.0001, "diagonal must not exceed cap")
	var before: Vector3 = feedback.look_offset
	feedback.advance_look(1.0 / 60.0, Vector2.ZERO, size, Vector3.RIGHT, Vector3.BACK, false)
	check(feedback.look_offset.length() < before.length() and not feedback.look_offset.is_zero_approx(), "UI/death return must ease out")
	for i in 120:
		feedback.advance_look(1.0 / 60.0, Vector2.ZERO, size, Vector3.RIGHT, Vector3.BACK, false)
	check(feedback.look_offset.is_zero_approx(), "return must settle exactly")
	var fast := FEEDBACK.new()
	for i in 30:
		feedback.advance_look(1.0 / 30.0, Vector2(600, 0), size, Vector3.RIGHT, Vector3.BACK, true)
	for i in 144:
		fast.advance_look(1.0 / 144.0, Vector2(600, 0), size, Vector3.RIGHT, Vector3.BACK, true)
	check(feedback.look_offset.distance_to(fast.look_offset) < 0.0001, "look response must be frame rate independent")
	fast.advance_look(0.1, Vector2(NAN, 0), size, Vector3.RIGHT, Vector3.BACK, true)
	check(fast.look_offset.is_finite(), "invalid pointer must never poison camera")
	feedback.free()
	fast.free()


func _verify_runtime(path: String) -> void:
	var level := (load(path) as PackedScene).instantiate() as TowerDescent3D
	if level == null:
		check(false, "runtime scene failed to load: " + path)
		return
	level.test_mode = true
	level.run_seed_override = 77003244
	add_child(level)
	for i in 24:
		await get_tree().process_frame
	var player := level.player
	var camera := player.camera
	var feedback: Node = player.camera_feedback
	feedback.set_physics_process(false)
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	check(player.uses_pointer_camera_aim(), "desktop Autoload presence must not disable mouse look")
	InputDevice.force_device(InputDevice.DEVICE_GAMEPAD)
	check(not player.uses_pointer_camera_aim(), "gamepad must not follow a stale mouse cursor")
	InputDevice.force_device(InputDevice.DEVICE_TOUCH)
	check(not player.uses_pointer_camera_aim(), "touch must not follow a stale mouse cursor")
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	if not capture_dir.is_empty():
		player.set_input_locked(false)
		get_window().grab_focus()
		await get_tree().create_timer(0.1).timeout
		get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.92, 0.5))
		await get_tree().create_timer(0.1).timeout
		print("MOUSE_LOOK_GATE pointer=", get_viewport().get_mouse_position(),
			" rect=", get_viewport().get_visible_rect(), " focus=", DisplayServer.window_is_focused(),
			" lock=", player.input_locked, " current=", camera.current,
			" suspended=", feedback.suspended, " device=", InputDevice.get_active_device())
		feedback.reset()
		feedback._physics_process(0.1)
		check(feedback.look_offset.x > 0.05, "actual focused mouse pointer must drive look")
		player.set_input_locked(true)
		var prior_length: float = feedback.look_offset.length()
		feedback._physics_process(0.1)
		check(feedback.look_offset.length() < prior_length, "modal input lock must return actual look toward center")
		player.set_input_locked(false)
	feedback.reset()
	level.call("_apply_indoor_camera_pose")
	var base := camera.global_transform
	feedback.look_offset = Vector3(0.8, 0.0, 0.0)
	level.call("_apply_indoor_camera_pose")
	check(camera.global_position.x > base.origin.x + 0.1, path + " world owner composes forward view")
	await _capture("look_right", path)
	var room := level.get("_room_by_id").get(level.get("_current_room_id")) as DungeonRoom3D
	if bool(level.get("_flow_rules_active")) and room != null:
		feedback.look_offset = Vector3(100, 0, 100)
		level.call("_apply_indoor_camera_pose")
		var local_camera := camera.global_position - room.global_position
		var dims := room.get_dimensions()
		check(absf(local_camera.x) <= dims.x * 0.5 and absf(local_camera.z) <= dims.y * 0.5, "flow room camera must remain inside current room")
	feedback.reset()
	level.call("_apply_indoor_camera_pose")
	var base_image: Image
	var patch := _make_pixel_patches(level) if not capture_dir.is_empty() else null
	if patch != null:
		await RenderingServer.frame_post_draw
		base_image = get_viewport().get_texture().get_image()
	await _capture("healthy", path)
	_damage_events = 0
	player.damage_received.connect(func(_damage: int, _maximum: int) -> void: _damage_events += 1)
	player.is_invincible = false
	player.take_damage(10)
	check(_damage_events == 1, "accepted damage emits once")
	feedback._physics_process(1.0 / 60.0)
	check(absf(camera.h_offset) + absf(camera.v_offset) > 0.001, "accepted hit must shake current camera")
	check(absf(camera.h_offset) <= 0.19 and absf(camera.v_offset) <= 0.19, "shake amplitude must be bounded")
	check(float(feedback.get("_shake_amplitude")) >= 0.11, "hit shake must use the increased amplitude")
	player.call("_update_aim_from_mouse")
	var shaken_aim := player.aim_direction
	var saved_shake := Vector2(camera.h_offset, camera.v_offset)
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	player.call("_update_aim_from_mouse")
	check(shaken_aim.is_equal_approx(player.aim_direction), "cosmetic shake must never change aim direction")
	camera.h_offset = saved_shake.x
	camera.v_offset = saved_shake.y
	await _capture("hurt", path)
	player.take_damage(10)
	player.take_damage(0)
	player.heal(1)
	check(_damage_events == 1, "invulnerability, zero damage and healing must not trigger shake")
	for i in 30:
		feedback._physics_process(1.0 / 60.0)
	check(is_zero_approx(camera.h_offset) and is_zero_approx(camera.v_offset), "shake returns exactly to zero")
	player.is_invincible = false
	player.take_damage(1, false, Vector3.ZERO, false, 0.0, true)
	check(_damage_events == 1, "life cost must not trigger hit shake")
	player.is_invincible = false
	player.take_damage(99999)
	check(is_instance_valid(level.get("_defeat_transition")), "fatal hit starts filter immediately")
	check(level.get("_death_dialog") == null, "fatal hit must not expose return button")
	var transition: Node = level.get("_defeat_transition")
	level.call("_start_defeat_transition")
	check(level.get("_defeat_transition") == transition, "duplicate death must not restart transition")
	level.call("_confirm_death_return")
	check(not bool(level.get("_completed")), "early return command must be rejected")
	await get_tree().create_timer(1.5).timeout
	check(not transition.visible and level.get("_death_dialog") == null, "fall animation must play before any filter or settlement")
	await _capture("fall_1500ms", path)
	await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(0.5).timeout
	await _capture("defeat_2500ms", path)
	await get_tree().create_timer(0.5).timeout
	await _capture("defeat_3000ms", path)
	await get_tree().create_timer(0.65).timeout
	check(level.get("_death_dialog") == null, "return button must remain absent before 4s")
	await get_tree().create_timer(0.5).timeout
	check(bool(transition.get("complete")), "delayed 2s filter must complete after 4s")
	check(level.get("_death_dialog") != null, "settlement UI appears after filter and fall")
	if not capture_dir.is_empty():
		# Modal dimming belongs to HUD and intentionally covers the world. Hide it
		# for the isolated grade measurement, then restore for the actual UI capture.
		var hud := level.get_node("HUD") as CanvasLayer
		hud.hide()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var source := base_image.get_pixel(20, 20)
		var actual := image.get_pixel(20, 20)
		var luma := source.r * 0.2126 + source.g * 0.7152 + source.b * 0.0722
		var expected := Color((lerpf(luma, source.r, 0.5) - 0.5) * 1.2 + 0.5,
			(lerpf(luma, source.g, 0.5) - 0.5) * 1.2 + 0.5,
			(lerpf(luma, source.b, 0.5) - 0.5) * 1.2 + 0.5)
		print("DEFEAT_PIXEL ", path, " source=", source, " actual=", actual, " expected=", expected)
		check(Vector3(actual.r, actual.g, actual.b).distance_to(Vector3(expected.r, expected.g, expected.b)) < 0.025, "real rendered grade must be saturation 0.5 / contrast 1.2")
		check(image.get_pixel(110, 20).is_equal_approx(base_image.get_pixel(110, 20)), "HUD layer must retain its original pixels")
		hud.show()
	await _capture("defeat_4150ms", path)
	level.call("_reset_death_settlement_state")
	check(level.get("_defeat_transition") == null and not bool(level.get("_death_filter_ready")), "new run clears filter and gate")
	level.call("_on_defeat_transition_finished", int(level.get("_run_generation")) - 1)
	check(level.get("_death_dialog") == null, "stale generation callback cannot reopen settlement")
	level.queue_free()
	for i in 6:
		await get_tree().process_frame
	check(get_tree().get_nodes_in_group("player_3d").is_empty(), "scene unload must release player and feedback")


func _make_pixel_patches(level: Node) -> Node:
	for layer_id in [0, 1]:
		var canvas := CanvasLayer.new()
		canvas.layer = layer_id
		level.add_child(canvas)
		var patch := ColorRect.new()
		patch.position = Vector2(10 + 90 * layer_id, 10)
		patch.size = Vector2(60, 60)
		patch.color = Color(0.2, 0.6, 0.3) if layer_id == 0 else Color(0.8, 0.2, 0.6)
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(patch)
	return level


func _capture(label: String, path: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var prefix := "expedition03" if "03_3D" in path else "tower"
	var error := get_viewport().get_texture().get_image().save_png(capture_dir.path_join(prefix + "_" + label + ".png"))
	check(error == OK, "capture " + label)
