extends Node3D
## Run in a project with user data isolated BEFORE Autoload startup.
## Add -- --capture-dir=<absolute external path> with a real renderer for pixel QA.

const FEEDBACK := preload("res://src/player3d/PlayerCameraFeedback3D.gd")
var failures: Array[String] = []
var checks := 0
var capture_dir := ""
var _damage_events := 0

# Run the real camera owner without assembling a whole floor or touching saves.
class CameraWallOwner extends TowerDescent3D:
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)

class CameraWallPlayer extends Player3D:
	func _ready() -> void:
		set_physics_process(false)
		camera_feedback.configure(self)
		camera_feedback.set_physics_process(false)


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
	if "--look-model-only" in OS.get_cmdline_user_args():
		print("PLAYER_CAMERA_LOOK_MODEL checks=%d failures=%d" % [checks, failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	await _verify_wall_fixture()
	if "--wall-fixture-only" in OS.get_cmdline_user_args():
		print("PLAYER_CAMERA_WALL_FIXTURE checks=%d failures=%d" % [checks, failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	var paths := ["res://scenes/TowerDescent3D.tscn", "res://scenes/ExpeditionLevel03_3D.tscn"]
	if "--expedition01-only" in OS.get_cmdline_user_args():
		paths = ["res://scenes/ExpeditionLevel01_3D.tscn"]
	for path in paths:
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
	if feedback.has_method("set_look_blocked_direction"):
		feedback.reset()
		feedback.look_offset = Vector3(0.4, 0.0, 1.0)
		feedback.set_look_blocked_direction(Vector3.BACK)
		check(feedback.look_offset.is_equal_approx(Vector3(0.4, 0, 0)), "entering wall constraint clears only existing toward-wall look")
		for i in 120:
			feedback.advance_look(1.0 / 60.0, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(feedback.look_offset.is_zero_approx(), "wall blocks downward look target and residual offset")
		feedback.advance_look(1.0, Vector2(600, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(feedback.look_offset.x > 0.5 and is_zero_approx(feedback.look_offset.z), "diagonal down preserves lateral look")
		feedback.advance_look(1.0, Vector2(0, -600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(feedback.look_offset.z < -1.6, "wall still allows upward look")
		feedback.set_look_blocked_direction(Vector3.ZERO)
		feedback.advance_look(1.0, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(feedback.look_offset.z > 1.6, "leaving wall restores downward look")
		feedback.set_look_blocked_direction(Vector3.RIGHT * 5.0)
		feedback.advance_look(1.0, Vector2(600, 0), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(is_zero_approx(feedback.look_offset.x), "profile constraint uses normalized world direction")
		feedback.reset()
		feedback.advance_look(1.0, Vector2(600, 0), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(feedback.look_offset.x > 1.6, "reset releases stale wall constraint")
	else:
		check(false, "feedback must accept world-owned directional wall constraint")
	# Exercise the real flow branch without assembling an unrelated full level.
	var flow := TowerDescent3D.new()
	flow.player = Player3D.new()
	flow.add_child(flow.player)
	flow.set("_flow_rules_active", true)
	if flow.player.camera_feedback.has_method("set_look_blocked_direction"):
		flow.player.camera_feedback.set_look_blocked_direction(Vector3.BACK)
		flow.call("_update_camera_lower_wall_lift", 1.0, true)
		flow.player.camera_feedback.advance_look(1.0, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(flow.player.camera_feedback.look_offset.z > 1.6, "flow branch must clear a stale directional wall constraint")
	flow.free()
	feedback.free()
	fast.free()


func _verify_wall_fixture() -> void:
	var expected_root := OS.get_environment("APPDATA").replace("\\", "/")
	var user_root := OS.get_user_data_dir().replace("\\", "/")
	check(not expected_root.is_empty() and user_root.begins_with(expected_root + "/"), "isolated user data must be established before Autoload startup")
	print("ISOLATION_USER_DIR ", user_root)
	# Keep the required scene nodes, but omit unrelated multi-tower art/streaming.
	var shell := (load("res://scenes/Dungeon3D.tscn") as PackedScene).instantiate()
	shell.set_script(CameraWallOwner)
	var owner := shell as TowerDescent3D
	owner.test_mode = true
	var player := owner.get_node("Player3D") as Player3D
	player.set_script(CameraWallPlayer)
	add_child(owner)
	var camera := player.camera
	camera.fov = TowerDescent3D.CAMERA_FOV_DEG
	camera.make_current()
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	wall.collision_mask = 0
	wall.set_meta("camera_lower_wall", true)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 14, 0.3)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(0, 7, 0.5)
	owner.add_child(wall)
	await get_tree().physics_frame
	var feedback: Node = player.camera_feedback
	var size := get_viewport().get_visible_rect().size
	var down_pointer := size * Vector2(0.5, 0.95)
	feedback.look_offset = Vector3.BACK * FEEDBACK.LOOK_MAX_M
	var distance: float = owner.call("_find_lower_camera_wall_distance")
	check(absf(distance - 0.35) < 0.001, "fixture must hit real tagged south wall at 0.35m regardless of look offset")
	var previous_basis := Basis.IDENTITY
	var max_angle := 0.0
	var max_step := 0.0
	var previous_position := Vector3.ZERO
	for frame in 240:
		owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, frame % 2 == 0)
		owner.call("_apply_indoor_camera_pose")
		var body_screen := camera.unproject_position(player.global_position + Vector3.UP * 0.6)
		feedback.advance_look(1.0 / 60.0, down_pointer - body_screen, size, camera.global_basis.x, camera.global_basis.y, true)
		if frame >= 180:
			max_angle = maxf(max_angle, previous_basis.get_rotation_quaternion().angle_to(camera.global_basis.get_rotation_quaternion()))
			max_step = maxf(max_step, previous_position.distance_to(camera.global_position))
		previous_basis = camera.global_basis
		previous_position = camera.global_position
	check(feedback.look_offset.is_zero_approx(), "actual camera basis and body projection must block held south pointer")
	check(max_angle < 0.0001 and max_step < 0.0001, "held south pointer must not oscillate settled camera orientation or position")
	if not capture_dir.is_empty():
		await _verify_fixture_pointer(owner)
	for pointer in [size * Vector2(0.05, 0.5), size * Vector2(0.95, 0.95), size * Vector2(0.5, 0.05)]:
		for frame in 120:
			owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, true)
			owner.call("_apply_indoor_camera_pose")
			var body_screen := camera.unproject_position(player.global_position + Vector3.UP * 0.6)
			feedback.advance_look(1.0 / 60.0, pointer - body_screen, size, camera.global_basis.x, camera.global_basis.y, true)
		check(feedback.look_offset.x < -1.0 if pointer.x < size.x * 0.1 else feedback.look_offset.x > 0.5 if pointer.y > size.y * 0.9 else feedback.look_offset.z < -1.0, "wall preserves west, southeast lateral component and north with live projection")
	# Small position/physics fluctuations must not toggle the two camera modes.
	var trigger := TowerDescent3D.CAMERA_LOWER_WALL_RETRACT_TRIGGER_M
	var retracted_frames := 0
	feedback.reset()
	for frame in 120:
		owner.set("_camera_lower_wall_detected", true)
		owner.set("_camera_lower_wall_distance_m", trigger + (-0.03 if frame % 2 == 0 else 0.03))
		owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, false)
		feedback.advance_look(1.0 / 60.0, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		if float(owner.get("_camera_trailing_target_m")) < 0.2:
			retracted_frames += 1
	check(retracted_frames == 120, "south-wall trigger needs exit hysteresis, not alternating retract/extend on 3cm boundary noise")
	check(feedback.look_offset.z < 0.0001, "south look cannot leak through boundary noise")
	owner.set("_camera_lower_wall_distance_m", trigger + 0.21)
	owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, false)
	check(is_equal_approx(float(owner.get("_camera_trailing_target_m")), TowerDescent3D.CAMERA_DEFAULT_TRAILING_M), "wall camera exits outside the hysteresis band")
	# Release a retracted camera: look must not run south before the base pose recovers.
	owner.set("_camera_lower_wall_detected", false)
	owner.set("_camera_lower_wall_distance_m", -1.0)
	owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, false)
	feedback.advance_look(1.0 / 60.0, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
	check(is_zero_approx(feedback.look_offset.z), "south look stays blocked during initial wall-camera recovery")
	for frame in 180:
		owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, false)
		feedback.advance_look(1.0 / 60.0, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
	check(feedback.look_offset.z > 1.6, "south look smoothly returns after wall camera recovery")
	# The release gate must be time-based, not frame-count dependent.
	for hz in [30, 60, 144]:
		feedback.reset()
		owner.set("_camera_lower_wall_detected", true)
		owner.set("_camera_lower_wall_distance_m", 0.35)
		owner.call("_update_camera_lower_wall_lift", 5.0, false)
		owner.set("_camera_lower_wall_detected", false)
		owner.set("_camera_lower_wall_distance_m", -1.0)
		for frame in int(hz * 0.5):
			owner.call("_update_camera_lower_wall_lift", 1.0 / hz, false)
			feedback.advance_look(1.0 / hz, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(is_zero_approx(feedback.look_offset.z), "recovery gate still active after 0.5s at %dHz" % hz)
		for frame in hz * 2:
			owner.call("_update_camera_lower_wall_lift", 1.0 / hz, false)
			feedback.advance_look(1.0 / hz, Vector2(0, 600), size, Vector3.RIGHT, Vector3.FORWARD, true)
		check(feedback.look_offset.z > 1.6, "recovery releases naturally at %dHz" % hz)
	# Rotated camera profiles must constrain their own rear, not hardcoded world Z.
	player.rotation.y = PI * 0.5
	feedback.reset()
	owner.set("_camera_lower_wall_detected", true)
	owner.set("_camera_lower_wall_distance_m", 0.35)
	owner.call("_update_camera_lower_wall_lift", 1.0, false)
	var rear: Vector3 = owner.call("_camera_profile_trailing_direction")
	feedback.advance_look(1.0, Vector2(0, 600), size, Vector3.FORWARD, -rear, true)
	check(is_zero_approx(feedback.look_offset.dot(rear)), "rotated owner blocks its rear direction")
	owner.set("_flow_rules_active", true)
	owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, false)
	feedback.advance_look(1.0, Vector2(0, 600), size, Vector3.FORWARD, -rear, true)
	check(feedback.look_offset.dot(rear) > 1.6 and not bool(owner.get("_camera_lower_wall_retract_active")), "flow mode clears wall state and immediately releases directional constraint")
	print("CAMERA_WALL_FIXTURE ", {"distance": distance, "settled_angle_span": max_angle, "settled_position_step": max_step, "boundary_retracted_frames": retracted_frames})
	owner.queue_free()
	await get_tree().process_frame


func _verify_fixture_pointer(owner: TowerDescent3D) -> void:
	var player := owner.player
	var feedback: Node = player.camera_feedback
	var blocks := owner.get_node_or_null("Blocks") as Node3D
	if blocks != null:
		blocks.hide()
	owner.get_node("HUD").hide()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.18, 0.23, 0.28)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	owner.world_environment.environment = environment
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.29, 0.32)
	floor_mesh.material_override = material
	floor_mesh.position = Vector3(0, -0.02, -8)
	owner.add_child(floor_mesh)
	for x in range(-10, 11, 2):
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.04, 0.02, 20)
		marker.mesh = mesh
		marker.position = Vector3(x, 0, -9)
		owner.add_child(marker)
	get_window().grab_focus()
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	await get_tree().create_timer(0.15).timeout
	check(DisplayServer.window_is_focused() and player.camera.current and player.uses_pointer_camera_aim(), "real mouse fixture must own focused current keyboard/mouse camera")
	for sample in [{"label": "south_blocked", "point": Vector2(0.5, 0.95)}, {"label": "east_allowed", "point": Vector2(0.95, 0.5)}, {"label": "west_allowed", "point": Vector2(0.05, 0.5)}, {"label": "north_allowed", "point": Vector2(0.5, 0.05)}]:
		get_window().grab_focus()
		var viewport_point := get_viewport().get_visible_rect().size * (sample["point"] as Vector2)
		var window_point := get_viewport().get_final_transform() * viewport_point
		Input.warp_mouse(window_point)
		var motion := InputEventMouseMotion.new()
		motion.position = window_point
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await get_tree().process_frame
		for frame in 90:
			owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, frame % 2 == 0)
			owner.call("_apply_indoor_camera_pose")
			# Simulate fixed ticks synchronously; desktop pointer/focus changes from
			# unrelated windows must not splice into a single direction sample.
			feedback._physics_process(1.0 / 60.0)
		var offset: Vector3 = feedback.look_offset
		var label := str(sample["label"])
		check(DisplayServer.window_is_focused() and get_viewport().get_mouse_position().distance_to(viewport_point) < 6.0, "actual pointer sample must remain focused and inside intended viewport position: " + label)
		print("CAMERA_POINTER ", {"sample": label, "offset": offset, "pointer": get_viewport().get_mouse_position(), "rect": get_viewport().get_visible_rect(), "window_size": get_window().size, "body": player.camera.unproject_position(player.global_position + Vector3.UP * 0.6), "focus": DisplayServer.window_is_focused(), "current": player.camera.current, "locked": player.input_locked, "suspended": feedback.suspended, "hp": player.current_hp, "device": InputDevice.get_active_device()})
		check(offset.is_zero_approx() if label == "south_blocked" else offset.x > 1.0 if label == "east_allowed" else offset.x < -1.0 if label == "west_allowed" else offset.z < -1.0, "actual focused mouse: " + label)
		await _capture("fixture_" + label, "tower")


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
	await _verify_lower_wall_look(level, path)
	if "--wall-look-only" in OS.get_cmdline_user_args():
		level.queue_free()
		for i in 6:
			await get_tree().process_frame
		return
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


func _verify_lower_wall_look(level: TowerDescent3D, path: String) -> void:
	var player := level.player
	var feedback: Node = player.camera_feedback
	var original_position := player.global_position
	var original_room := str(level.get("_current_room_id"))
	var player_physics := player.is_physics_processing()
	level.set_physics_process(false)
	player.set_physics_process(false)
	var is_flow := bool(level.get("_flow_rules_active"))
	var room := (level.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if room == null:
		room = (level.get("_room_by_id") as Dictionary).get(original_room) as DungeonRoom3D
	check(room != null, path + " wall regression needs a real room")
	if room != null:
		level.force_enter_room_for_test(room.room_id)
		var center := room.global_position + Vector3.UP * 0.05
		var half_depth := room.get_dimensions().y * 0.5
		player.global_position = center + Vector3.BACK * (half_depth - 0.5)
		await get_tree().physics_frame
		var wall_distance: float = level.call("_find_lower_camera_wall_distance")
		# Arrive at the wall with a full downward look already in flight.
		feedback.look_offset = Vector3.BACK * FEEDBACK.LOOK_MAX_M
		var shifted_distance: float = level.call("_find_lower_camera_wall_distance")
		if not is_flow:
			check(wall_distance >= 0.0, path + " real south wall must be tagged")
			check(is_equal_approx(shifted_distance, wall_distance), path + " mouse look cannot move wall probe through the wall")
		var min_height := INF
		var max_height := -INF
		var detections := 0
		for frame in 180:
			level.call("_update_camera_lower_wall_lift", 1.0 / 60.0, true)
			feedback.advance_look(1.0 / 60.0, Vector2(0, 600), Vector2(1280, 720),
				Vector3.RIGHT, Vector3.FORWARD, true)
			level.call("_apply_indoor_camera_pose")
			if bool(level.get("_camera_lower_wall_detected")):
				detections += 1
			if frame >= 120:
				min_height = minf(min_height, player.camera.global_position.y)
				max_height = maxf(max_height, player.camera.global_position.y)
		check(max_height - min_height < 0.001, path + " sustained down look must not oscillate camera height")
		if is_flow:
			check(detections == 0 and feedback.look_offset.z > 1.6, "flow without wall lift must retain downward look")
		else:
			check(detections == 180, path + " wall must stay detected every frame while dragging down")
			check(is_zero_approx(feedback.look_offset.z), path + " downward look is blocked against lower wall")
			check(float(level.get("_camera_trailing_current_m")) < 0.16, path + " wall retraction remains active")
			check(float(level.get("_camera_lift_current_m")) > 0.29, path + " wall lift remains active")
			if not capture_dir.is_empty():
				get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.5, 0.95))
				await get_tree().process_frame
				for frame in 60:
					level.call("_update_camera_lower_wall_lift", 1.0 / 60.0, true)
					feedback._physics_process(1.0 / 60.0)
					level.call("_apply_indoor_camera_pose")
					await get_tree().process_frame
				check(is_zero_approx(feedback.look_offset.z), path + " actual mouse down stays blocked at wall")
			await _capture("wall_look_down", path)
			for screen_delta in [Vector2(-600, 0), Vector2(600, 600), Vector2(0, -600)]:
				feedback.advance_look(1.0, screen_delta, Vector2(1280, 720), Vector3.RIGHT, Vector3.FORWARD, true)
				if screen_delta.x < 0:
					check(feedback.look_offset.x < -1.6, path + " wall preserves left look")
				elif screen_delta.y > 0:
					check(feedback.look_offset.x > 0.5 and is_zero_approx(feedback.look_offset.z), path + " diagonal down preserves lateral look")
				else:
					check(feedback.look_offset.z < -1.6, path + " wall preserves upward look")
			player.global_position = center
			await get_tree().physics_frame
			for frame in 180:
				level.call("_update_camera_lower_wall_lift", 1.0 / 60.0, true)
				feedback.advance_look(1.0 / 60.0, Vector2(0, 600), Vector2(1280, 720), Vector3.RIGHT, Vector3.FORWARD, true)
				level.call("_apply_indoor_camera_pose")
			check(feedback.look_offset.z > 1.6, path + " walking away restores downward look")
			check(float(level.get("_camera_lift_current_m")) < 0.001, path + " walking away releases wall lift")
			await _capture("away_look_down", path)
		print("CAMERA_WALL_LOOK ", {"path": path, "probe": wall_distance, "shifted_probe": shifted_distance,
			"detected_frames": detections, "settled_height_span": max_height - min_height})
	level.force_enter_room_for_test(original_room)
	player.global_position = original_position
	feedback.reset()
	level.call("_update_camera_lower_wall_lift", 5.0, true)
	player.set_physics_process(player_physics)
	level.set_physics_process(true)


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
	var prefix := "expedition03" if "03_3D" in path else "expedition01" if "01_3D" in path else "tower"
	var error := get_viewport().get_texture().get_image().save_png(capture_dir.path_join(prefix + "_" + label + ".png"))
	check(error == OK, "capture " + label)
