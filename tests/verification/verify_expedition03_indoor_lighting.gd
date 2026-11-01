extends Node3D
## 正式03房间/通道：真实太阳射线、作者灯开关、流送/读档与原生画面对照。
const LEVEL := preload("res://scenes/ExpeditionLevel03_3D.tscn")
var failures: Array[String] = []
var checks := 0
var samples := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("INDOOR_FAIL ", reason)

func settle() -> void:
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	var level := LEVEL.instantiate() as TowerDescent3D
	level.test_mode = true
	level.run_seed_override = 77003244
	add_child(level)
	for i in 24:
		await get_tree().process_frame
	var envelope := level.get_node("IndoorLightEnvelope")
	check(envelope.get_snapshot()["built"], "envelope not built")
	var sun := level.get_node("DirectionalLight3D") as DirectionalLight3D
	# 固定白天方向与能量，不关闭太阳来通过室内断言。
	sun.rotation_degrees = Vector3(-60, -32, 0)
	sun.light_energy = 1.0
	var rooms: Array = level.get("_rooms")
	await _verify_camera_occlusion(level, envelope, rooms[0])
	if "--camera-only" in OS.get_cmdline_user_args():
		level.queue_free()
		await settle()
		print("INDOOR_CAMERA_RESULT checks=%d failures=%d" % [checks, failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	if "--capture-only" in OS.get_cmdline_user_args():
		await _capture(level, rooms[0], envelope, sun)
		level.queue_free()
		await settle()
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	var sensor_body := CharacterBody3D.new()
	sensor_body.collision_layer = 0
	sensor_body.collision_mask = 0
	add_child(sensor_body)
	var sensor := EnemyIllumination3D.new()
	sensor.configure(sensor_body)
	var space := get_world_3d().direct_space_state
	for other in rooms:
		other.set_room_light_on(false)
	for value in rooms:
		var room := value as DungeonRoom3D
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		await settle()
		var raw: Array[Light3D] = []
		for node in room.find_children("*", "Light3D", true, false):
			if node.get_parent() is WastelandLight3D:
				continue
			raw.append(node)
		check(not raw.is_empty(), "no authored/bounce lights " + room.room_id)
		room.set_room_light_on(false)
		await settle()
		for light in raw:
			check(is_zero_approx(light.light_energy), "switch off ignored " + str(light.get_path()))
		var dims := room.get_dimensions()
		for u in [-0.40, 0.0, 0.40]:
			for v in [-0.40, 0.0, 0.40]:
				var point := room.to_global(Vector3(dims.x * u, 1.1, dims.y * v))
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point + sun.global_basis.z * 1000, 1))
				check(not hit.is_empty(), "sun ray escapes " + room.room_id)
				samples += 1
		sensor_body.global_position = room.to_global(Vector3(0, 0.15, 0))
		sensor.force_refresh()
		check(is_zero_approx(sensor.sun_exposure_ratio), "sensor sees sunlight " + room.room_id)
		check(sensor.illumination_state == EnemyIllumination3D.STATE_DARKNESS, "off room still artificially lit " + room.room_id)
		var wall_switch := room.get("_light_switch") as RoomLightSwitch3D
		check(wall_switch != null and wall_switch.toggle_light(), "wall switch rejected " + room.room_id)
		await settle()
		sensor.force_refresh()
		check(sensor.illumination_state == EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "on room not artificial light " + room.room_id)
		for light in raw:
			check(light.light_energy > 0, "switch on ignored " + str(light.get_path()))
		# detail卸载后重建、同实例状态回灌，验证新开关仍掌控原作者灯。
		room.apply_runtime_detail_state({"room_light_on": false})
		room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		await settle()
		for light in raw:
			check(is_zero_approx(light.light_energy), "restored off state ignored " + room.room_id)
		room.set_room_light_on(true)
		await settle()
		for light in raw:
			check(light.light_energy > 0, "rebuilt switch ignored " + room.room_id)
		room.set_room_light_on(false)
	if DisplayServer.get_name() != "headless":
		await _capture(level, rooms[0], envelope, sun)
	sensor_body.queue_free()
	level.queue_free()
	await settle()
	print("INDOOR_RESULT ", JSON.stringify({"checks":checks,"failures":failures.size(),"rooms":rooms.size(),"sun_samples":samples,"rendered":DisplayServer.get_name() != "headless"}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_camera_occlusion(level: TowerDescent3D, envelope: Node3D, room: DungeonRoom3D) -> void:
	var player: Player3D = level.player
	var camera: Camera3D = player.camera
	var was_processing := level.is_processing()
	var was_physics_processing := player.is_physics_processing()
	var player_pose := player.transform
	var camera_pose := camera.transform
	level.set_process(false)
	player.set_physics_process(false)
	player.global_position = room.global_position + Vector3(0, 0.15, 0)
	camera.global_position = player.global_position + Vector3(0, level.CAMERA_HEIGHT_M, 4.914455)
	camera.look_at(player.global_position + Vector3(0, 0.72, 0))
	camera.make_current()
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	room.set_room_light_on(true)
	await settle()
	var body := envelope.get_node("Ceiling/SunOcclusionBody") as StaticBody3D
	var collider := body.get_node("SunOcclusionShape") as CollisionShape3D
	var box := collider.shape as BoxShape3D
	var bounds := collider.global_transform * AABB(-box.size / 2.0, box.size)
	print("INDOOR_HEIGHTS ", JSON.stringify({"cover_bottom":bounds.position.y,"cover_top":bounds.end.y,"camera_y":camera.global_position.y,"player_feet_y":player.global_position.y}))
	check(is_equal_approx(bounds.position.y - room.global_position.y, 12.0), "sun cover bottom must be 12m above room")
	check(bounds.position.y > camera.global_position.y, "sun cover is below the normal camera")
	level._update_camera_occlusion_silhouette()
	check(not bool(level.get("_player_occluded")), "invisible sun cover incorrectly enables player X-ray")
	await _camera_shot("camera_normal")
	# 只把顶盖临时降回6m，证明能重现之前的角色透视；随后恢复12m。
	var roof := envelope.get_node("Ceiling") as Node3D
	var roof_y := roof.position.y
	roof.position.y -= 6.0
	await settle()
	level._update_camera_occlusion_silhouette()
	check(bool(level.get("_player_occluded")), "negative control did not reproduce sun-cover X-ray")
	await _camera_shot("camera_old_regression_control")
	roof.position.y = roof_y
	await settle()
	# 顶盖升高后，真实阻挡仍须触发原有轮廓。
	var wall := StaticBody3D.new()
	wall.name = "CameraRealWallControl"
	wall.collision_layer = 1
	wall.collision_mask = 0
	add_child(wall)
	wall.global_position = camera.global_position.lerp(player.global_position + Vector3(0, 0.72, 0), 0.70)
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4, 1, 4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	var wall_visual := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = wall_box.size
	wall_visual.mesh = wall_mesh
	wall.add_child(wall_visual)
	await settle()
	level._update_camera_occlusion_silhouette()
	check(bool(level.get("_player_occluded")), "real wall no longer enables original X-ray")
	await _camera_shot("camera_real_wall_control")
	wall.free()
	await settle()
	level._update_camera_occlusion_silhouette()
	check(not bool(level.get("_player_occluded")), "X-ray did not clear after real wall removal")
	check(body.collision_layer == 1, "camera fix disabled gameplay sun occlusion")
	player.transform = player_pose
	camera.transform = camera_pose
	player.set_physics_process(was_physics_processing)
	level.set_process(was_processing)

func _camera_shot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty():
		return
	var directory := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))

func _capture(level: TowerDescent3D, room: DungeonRoom3D, envelope: Node, sun: DirectionalLight3D) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		check(false, "render requires external output directory")
		return
	get_window().size = Vector2i(960, 640)
	for node in level.find_children("*", "CanvasLayer", true, false):
		node.visible = false
	var player := level.get("player") as Player3D
	if player != null:
		player.global_position = room.global_position + Vector3(0, 0.2, 0)
		player.set_physics_process(false)
		var torch := player.get_node_or_null("PlayerFlashlight3D")
		if torch != null:
			torch.set_light_enabled(false)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = room.global_position + Vector3(0, 10.26, 6.7)
	camera.look_at(room.global_position + Vector3(0, 0.5, 0))
	camera.make_current()
	DirAccess.make_dir_recursive_absolute(args[0])
	room.set_room_light_on(false)
	# 邻房开灯透过门洞会污染太阳A/B，拍摄时先熄灭全层室内灯。
	for other in level.get("_rooms"):
		other.set_room_light_on(false)
	sun.rotation_degrees = Vector3(-60, -32, 0)
	sun.light_energy = 1.0
	await settle()
	await RenderingServer.frame_post_draw
	var dark := get_viewport().get_texture().get_image()
	dark.save_png(args[0].path_join("room_lights_off.png"))
	envelope.visible = false
	await settle()
	await RenderingServer.frame_post_draw
	var exposed := get_viewport().get_texture().get_image()
	exposed.save_png(args[0].path_join("sun_unblocked_control.png"))
	envelope.visible = true
	room.set_room_light_on(true)
	await settle()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0].path_join("room_lights_on.png"))
	var lit := get_viewport().get_texture().get_image()
	var values := {"covered_off":_luma(dark),"exposed_off":_luma(exposed),"covered_on":_luma(lit)}
	check(values.exposed_off > values.covered_off * 3.0, "roof fails rendered sun A/B")
	check(values.covered_on > values.covered_off * 3.0, "room switch fails rendered A/B")
	print("INDOOR_RENDER ", JSON.stringify(values))
	check(sun.light_energy > 0.0, "render test disabled sun")
	camera.queue_free()

func _luma(frame: Image) -> float:
	var total := 0.0
	var count := 0
	for x in range(frame.get_width() / 4, frame.get_width() * 3 / 4, 8):
		for y in range(frame.get_height() / 3, frame.get_height() * 4 / 5, 8):
			total += frame.get_pixel(x, y).get_luminance()
			count += 1
	return total / maxi(count, 1)
