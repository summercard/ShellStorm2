extends Node
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("ENTRY_USER_DIR=", OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("ShellStorm2-entry-verification"):
		push_error("Refusing unisolated test")
		get_tree().quit(2)
		return
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	await get_tree().create_timer(2.0).timeout
	var player := tower.player
	var saved_pos := player.global_position
	var saved_transform := player.camera.transform
	var saved_fov := player.camera.fov
	var saved_player_cull := player.camera.cull_mask
	var attrs := player.camera.attributes
	var env := player.camera.environment
	# 收集展示前整个世界树的 Label3D 及其渲染层，用于后续隔离/还原断言。
	var label_snapshot: Array[Dictionary] = []
	for node in tower.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if label != null:
			label_snapshot.append({"node": label, "layers": label.layers})
	_expect(label_snapshot.size() > 0, "world labels present to hide", true)
	# 出生点意图核对：基地返航/登出落点只改这一处；新游戏仍走 98F 办公室（本测试不重跑那条）。
	_expect(tower.FACILITY_LOGOUT_SPAWN.is_equal_approx(Vector3(4.75, -11.95, 6.65)), "facility logout spawn value", true)
	var entry := (load("res://scenes/ui/MainEntryScreen3D.tscn") as PackedScene).instantiate() as MainEntryScreen3D
	entry.auto_present_when_player_found = false
	tower.add_child(entry)
	_expect(entry.present(player), "present", true)
	await get_tree().create_timer(2.0).timeout
	var snap := entry.get_entry_snapshot()
	print("ENTRY_SNAPSHOT=", JSON.stringify(snap))
	_expect(snap.base_backdrop, "real base background", true)
	_expect(snap.presentation_meshes > 10, "mesh sample sentinel", true)
	_expect(player.global_position.is_equal_approx(saved_pos), "player position unchanged", true)
	_expect(player.camera.attributes == attrs and player.camera.environment == env, "gameplay resources untouched", true)
	_expect(is_equal_approx(player.camera.fov, saved_fov), "gameplay fov untouched", true)
	_expect(player.camera.transform.is_equal_approx(saved_transform), "gameplay transform untouched", true)
	_expect(player.camera.cull_mask == saved_player_cull, "gameplay cull mask untouched", true)
	_expect(entry._camera != player.camera, "dedicated camera is separate instance", true)
	_expect((entry._camera.cull_mask & entry.PRESENTATION_LAYER) != 0, "presentation layer on camera", true)
	_expect(entry._camera.attributes != attrs, "attributes isolated", true)
	var cam_attrs := entry._camera.attributes as CameraAttributesPractical
	_expect(not cam_attrs.dof_blur_near_enabled, "portrait near blur off", true)
	_expect(is_equal_approx(cam_attrs.dof_blur_far_distance, 2.6), "dof far distance", true)
	_expect(is_equal_approx(cam_attrs.dof_blur_far_transition, 1.8), "dof far transition", true)
	_expect(is_equal_approx(cam_attrs.dof_blur_amount, 0.42), "dof far amount strengthened", true)
	# 近景：真实位置前移、无擅自缩放。
	_expect(entry._display_avatar != null, "display avatar exists", true)
	if entry._display_avatar != null:
		_expect(entry._display_avatar.scale.is_equal_approx(Vector3.ONE), "no auto scale", true)
		var fg_dist := entry._display_avatar.global_position.distance_to(entry._camera.global_position)
		_expect(fg_dist > 0.5 and fg_dist < 2.6, "avatar in sharp foreground", true)
	var projected := entry._camera.unproject_position(entry._stand + Vector3.UP * 0.6) / get_viewport().get_visible_rect().size
	_expect(projected.x > 0.55 and projected.x < 0.88 and projected.y > 0.15 and projected.y < 0.85, "portrait on screen right", true)
	# 暗角放屏幕最底层：不盖 UI、不盖过渡黑屏（不改 menu.z_index）。
	var vignette := entry.screen.find_child("EntryVignette", true, false)
	_expect(vignette != null and vignette.get_index() == 0, "vignette at bottom layer", true)
	# 设施头顶 GUI 隔离：所有世界 Label3D 在展示期间被移出渲染层（动态置 visible 也无效）。
	var hidden_ok := true
	for ls in label_snapshot:
		var lab := ls["node"] as Label3D
		if is_instance_valid(lab) and lab.layers != 0:
			hidden_ok = false
	_expect(hidden_ok, "facility/background labels culled during presentation", true)
	await _shot("main_entry_cinematic.png")
	entry.settings_button.grab_focus()
	await _accept()
	_expect(entry._settings_open, "settings input activation", true)
	if entry._settings_open:
		_expect(not entry._settings.reset_game_save_button.visible, "no save reset on home", true)
		await _shot("main_entry_settings.png")
		entry._settings.resume_game()
	await get_tree().process_frame
	_expect(not entry._settings_open and not get_tree().paused, "settings closes and unpauses", true)
	entry.start_button.grab_focus()
	await _accept()
	_expect(entry._transitioning, "start input activation", true)
	await get_tree().create_timer(1.4).timeout
	_expect(not entry._presenting, "handoff finished", true)
	_expect(player.camera.current, "original current camera restored", true)
	_expect(player.camera.attributes == attrs and player.camera.environment == env, "resources preserved after handoff", true)
	_expect(player.camera.cull_mask == saved_player_cull, "gameplay cull mask after handoff", true)
	_expect(tower.find_child("MainEntryPresentationRig", true, false) == null, "presentation cleanup", true)
	_expect(player.avatar.visible, "real avatar restored", true)
	# 标签完整还原：层与可见性都回到展示前。
	var restored_ok := true
	for ls in label_snapshot:
		var lab := ls["node"] as Label3D
		if is_instance_valid(lab):
			if lab.layers != ls["layers"] or not lab.visible:
				restored_ok = false
	_expect(restored_ok, "facility/background labels fully restored", true)
	# Abnormal exit path and repeat calls.
	entry.present(player)
	var second_rig := entry._rig
	entry.present(player)
	_expect(entry._rig == second_rig, "present idempotence", true)
	entry.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(player.camera.current and player.avatar.visible, "unexpected exit restores", true)
	tower.queue_free()
	await get_tree().process_frame
	print("ENTRY_CHECKS=", checks)
	if failures.is_empty() and checks >= 20:
		print("MAIN_ENTRY_CINEMATIC_OK")
	else:
		for msg in failures:
			push_error(msg)
	get_tree().quit(0 if failures.is_empty() and checks >= 20 else 1)

func _accept() -> void:
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("I:/工作项目/shellstrom2/outputs/" + filename)

func _expect(condition: bool, label: String, _expected: bool) -> void:
	checks += 1
	if not condition:
		failures.append(label)
