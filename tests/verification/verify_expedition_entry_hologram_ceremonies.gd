extends Node3D
## 真Player3D最小舞台，正常播放与全部归还断言共用正式导演/适配器。

const IDS := ["nar_expedition_entry_hologram_scan", "nar_expedition_entry_hologram_materialize"]
var failures: Array[String] = []
var output := ""
var rendering := false

class CeremonyHost extends Node3D:
	signal room_entered(room: Variant)
	signal expedition_entry_ceremony_scan_ready(room_id: String)
	signal expedition_entry_ceremony_materialize_ready(room_id: String)
	var player: Player3D
	var request_id := 41
	var source := ExpeditionEntryContext.BASE
	var held := false
	var modal := false
	var reason := GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT
	func is_expedition() -> bool:
		return true
	func get_entry_context_snapshot() -> Dictionary:
		return {"request_id": request_id, "reason": reason}
	func get_expedition_entry_source() -> String:
		return source
	func get_expedition_run_id() -> String:
		return "fixture"
	func set_scripted_input_hold(value: bool, _force := false, _source := "") -> void:
		held = value
		refresh_player_input_lock()
	func refresh_player_input_lock() -> void:
		if is_instance_valid(player):
			player.set_input_locked(held or modal or NarrativeDirector.is_player_input_locked())


func _ready() -> void:
	output = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	rendering = DisplayServer.get_name() != "headless"
	_expect(not output.is_empty(), "必须由隔离runner启动")
	_expect(ProjectSettings.globalize_path("user://").replace("\\", "/").begins_with(OS.get_environment("APPDATA").replace("\\", "/")), "Autoload前APPDATA未隔离")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--loading-e2e-seed="):
			await _check_loading_e2e(int(argument.get_slice("=", 1)))
			return
		if argument.begins_with("--base-menu-e2e-seed="):
			await _check_loading_e2e(int(argument.get_slice("=", 1)), true)
			return
		if argument == "--official-hosts":
			# 正式 host 用例每次都要完整装配一座远征关卡（约 40s/次），
			# 与两套 fixture 同进程会把全进程预算吃穿；
			# 因此拆成独立进程，超时只代表这一组没跑完，不污染 fixture 结论。
			NarrativeDirector.set_process(false)
			NarrativeDirector.reset_for_test()
			await _check_official_hosts()
			NarrativeDirector.reset_for_test()
			for failure in failures:
				printerr("FAIL: ", failure)
			print("EXPEDITION_ENTRY_RESULT official_hosts renderer=%s failures=%d user_dir=%s" % [RenderingServer.get_current_rendering_method(), failures.size(), ProjectSettings.globalize_path("user://")])
			get_tree().quit(0 if failures.is_empty() else 1)
			return
	NarrativeDirector.set_process(false)
	NarrativeDirector.reset_for_test()
	_build_stage()
	for index in IDS.size():
		await _check_mode(index)
	# 正式 host 装配另起 `--official-hosts` 进程：四次完整装配约 3min，
	# 与 fixture 同进程会把全进程预算吃穿，不能让 fixture 的结论被超时连坐。
	NarrativeDirector.reset_for_test()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("EXPEDITION_ENTRY_RESULT renderer=%s failures=%d user_dir=%s" % [DisplayServer.get_name(), failures.size(), ProjectSettings.globalize_path("user://")])
	get_tree().quit(0 if failures.is_empty() else 1)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.045, 0.075)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.64, 0.77, 0.92)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -25, 0)
	light.light_energy = 1.6
	add_child(light)
	var floor_body := StaticBody3D.new()
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(24, 0.2, 24)
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.13, 0.19)
	material.roughness = 0.65
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = box.size
	shape.shape = collision
	shape.position.y = -0.1
	floor_body.add_child(shape)
	add_child(floor_body)


func _new_host() -> CeremonyHost:
	var host := CeremonyHost.new()
	add_child(host)
	host.player = (load("res://scenes/Player3D.tscn") as PackedScene).instantiate() as Player3D
	host.add_child(host.player)
	host.player.position = Vector3(1.0, 0.05, -0.5)
	host.player.aim_yaw = 1.1
	host.player.avatar.visual_root.rotation.y = 1.1
	host.player.camera_feedback.suspended = true
	host.player.equip_weapon_item_to_slot(BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("weapon_pistol")), 0)
	host.player.equip_backpack_item(BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("equipment_backpack_2")))
	host.player.expression_system.set_random_enabled(false)
	host.player.set_physics_process(false)
	return host


func _register() -> void:
	for id in IDS:
		NarrativeDirector.register_script_for_test(id, NarrativeScript3D.load_from_id(id))
		NarrativeDirector.arm(id)


func _check_mode(index: int) -> void:
	NarrativeDirector.reset_for_test()
	_register()
	var host := _new_host()
	await get_tree().process_frame
	var player := host.player
	player.avatar.lock_ring.visible = true
	var state_material := player.avatar.lock_ring.material_override
	var meshes: Array[MeshInstance3D] = []
	for child in player.avatar.visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.is_visible_in_tree() and mesh.mesh != null and not player.avatar.lock_ring.get_parent().is_ancestor_of(mesh) and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			meshes.append(mesh)
	_expect(meshes.size() > 8, "必须是真实多部件兔子，不是box")
	var probe := meshes[0]
	var overlay := StandardMaterial3D.new()
	overlay.albedo_color = Color(0.7, 0.2, 0.3, 0.15)
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	probe.material_overlay = overlay
	probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var originals: Array[Dictionary] = []
	for mesh in meshes:
		originals.append({"mesh": mesh, "override": mesh.material_override, "overlay": mesh.material_overlay, "shadow": mesh.cast_shadow, "transparency": mesh.transparency})
	var hidden := Node3D.new()
	hidden.visible = false
	player.avatar.visual_root.add_child(hidden)
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.mesh = BoxMesh.new()
	hidden.add_child(hidden_mesh)
	var hidden_original := hidden_mesh.material_override
	var outside := player.aim_cursor.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var outside_original := outside.material_override
	var camera_original := player.camera.global_transform
	var fov_original := player.camera.fov
	var attributes_original := player.camera.attributes
	var id: String = IDS[index]
	var saved_camera := player.camera
	player.camera = null
	_expect(not NarrativeDirector.prepare_expedition_entry(id), "无效相机仍预备成功")
	player.camera = saved_camera
	_check_restored(host, originals, camera_original, fov_original, attributes_original, "预备失败回滚")
	_expect(NarrativeDirector.prepare_expedition_entry(id), "预备失败 " + id)
	_expect(not NarrativeDirector.is_playing() and player.input_locked and NarrativeDirector.is_player_input_locked() and host.held, "预备态必须持锁而非假active")
	_expect(probe.material_overlay == null and probe.cast_shadow == 0, "预备没有清overlay/影子")
	_expect(hidden_mesh.material_override == hidden_original and outside.material_override == outside_original and player.avatar.lock_ring.material_override == state_material, "错误覆盖隐藏祖先、准星或状态环")
	var shader_material := probe.material_override as ShaderMaterial
	if shader_material == null:
		_expect(false, "真实角色未应用全息材质 " + str(probe.get_path()))
		NarrativeDirector.abort("fixture_prepare_failed")
		host.queue_free()
		return
	var shader := shader_material.shader
	for mesh in meshes:
		var applied := mesh.material_override as ShaderMaterial
		if applied == null:
			printerr("MESH_NOT_HOLOGRAM path=", mesh.get_path(), " visible=", mesh.is_visible_in_tree(), " shadow=", mesh.cast_shadow)
		_expect(applied != null and applied.shader == shader, "没有共享shader " + str(mesh.get_path()))
	var behind := Vector3.BACK.rotated(Vector3.UP, player.aim_yaw)
	var offset := player.camera.global_position - player.global_position
	offset.y = 0
	_expect(offset.normalized().dot(behind) > 0.90, "prepare相机不在真实朝向后方")
	NarrativeDirector.abort("pending_cancel")
	_check_restored(host, originals, camera_original, fov_original, attributes_original, "预备取消")
	_expect(NarrativeDirector.prepare_expedition_entry(id), "取消后不可重试")
	_emit(host, index)
	NarrativeDirector.call("_process", 0.0)
	var script := NarrativeScript3D.load_from_id(id)
	var rebuild := float(script.presentation["rebuild_seconds"])
	var solidify := float(script.presentation["solidify_seconds"])
	await _advance(rebuild * 0.5)
	var hologram := probe.material_override as ShaderMaterial
	_expect(hologram != null and is_equal_approx(float(hologram.get_shader_parameter("reveal_progress")), 0.5), "半成形未到统一扫描中点")
	await _capture("%s_half" % index)
	await _advance(rebuild * 0.5 + solidify + 0.05)
	_expect(probe.material_overlay == overlay and probe.material_override == originals[0]["override"], "实体化结束前未还真实材质")
	await _capture("%s_solid_close" % index)
	await _advance(script.duration - rebuild - solidify - 0.05 + 0.03)
	_check_restored(host, originals, camera_original, fov_original, attributes_original, "正常结束")
	await _capture("%s_gameplay" % index)
	_expect(not NarrativeDirector.prepare_expedition_entry("invalid"), "非法ID未拒绝")
	# 同出发已完成不能重演，也不能留下准备锁。
	_expect(not NarrativeDirector.prepare_expedition_entry(id), "已完成出发仍可预备")
	for cancel in ["interrupt", "invalid_camera", "unload_pending", "unload_active"]:
		host.request_id += 1
		_expect(NarrativeDirector.prepare_expedition_entry(id), "故障专项无法预备 " + cancel)
		if cancel != "unload_pending":
			_emit(host, index)
			NarrativeDirector.call("_process", 0.0)
			await _advance(0.4)
		if cancel == "interrupt":
			NarrativeDirector.abort(cancel)
		elif cancel == "invalid_camera":
			var camera := player.camera
			player.camera = null
			NarrativeDirector.call("_process", 0.01)
			player.camera = camera
		else:
			remove_child(host)
			_expect(not host.held and not player.input_locked, "卸载后原host/player仍持锁")
			add_child(host)
		_check_restored(host, originals, camera_original, fov_original, attributes_original, cancel)
		# 同request故障重试可启动，成功后才消费departure。
		_expect(NarrativeDirector.prepare_expedition_entry(id), "故障同request不可重试 " + cancel)
		_emit(host, index)
		NarrativeDirector.call("_process", 0.0)
		_expect(NarrativeDirector.is_playing(), "重试事件未启动 " + cancel)
		NarrativeDirector.abort("retry_cleanup")
	host.source = ExpeditionEntryContext.TOWER03
	_expect(not NarrativeDirector.prepare_expedition_entry(id), "非base错误预备")
	host.source = ExpeditionEntryContext.BASE
	host.reason = GameEntryFlow.REASON_RUNTIME_RESTORE
	_expect(not NarrativeDirector.prepare_expedition_entry(id), "续档错误预备")
	var before_movement := player.global_position
	player.set_physics_process(true)
	Input.action_press("move_right")
	for frame in 12:
		await get_tree().physics_frame
	Input.action_release("move_right")
	player.set_physics_process(false)
	_expect(player.global_position.distance_to(before_movement) > 0.1, "仪式归还后真实玩家无法移动")
	host.queue_free()
	await get_tree().process_frame
	print("CEREMONY_MODE_OK mode=%s meshes=%d duration=%.2f" % [id, meshes.size(), script.duration])


func _emit(host: CeremonyHost, index: int) -> void:
	if index == 0:
		host.expedition_entry_ceremony_scan_ready.emit("start")
	else:
		host.expedition_entry_ceremony_materialize_ready.emit("start")


func _check_restored(host: CeremonyHost, originals: Array[Dictionary], camera: Transform3D, fov: float, attributes: CameraAttributes, label: String) -> void:
	_expect(not NarrativeDirector.is_playing() and not NarrativeDirector.is_player_input_locked() and not NarrativeDirector.is_camera_override_active(), label + " 导演未归还")
	_expect(not host.held and not host.player.input_locked, label + " 实际输入未归还")
	_expect(host.player.camera.global_transform.is_equal_approx(camera), label + " 相机不精确")
	_expect(host.player.camera.fov == fov and host.player.camera.attributes == attributes, label + " 相机光学状态变更")
	for entry in originals:
		var mesh := entry["mesh"] as MeshInstance3D
		_expect(mesh.material_override == entry["override"] and mesh.material_overlay == entry["overlay"] and mesh.cast_shadow == entry["shadow"] and mesh.transparency == entry["transparency"], label + " 材质/overlay/shadow/透明度未归还 " + str(mesh.get_path()))


func _advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.00001:
		var step := minf(remaining, 1.0 / 60.0)
		NarrativeDirector.call("_process", step)
		remaining -= step
		await get_tree().process_frame


func _capture(label: String) -> void:
	if not rendering:
		return
	await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	_expect(get_viewport().get_texture().get_image().save_png(path) == OK, "截图失败 " + path)
	print("CAPTURE ", path)


func _check_official_hosts() -> void:
	# 使用真正的TowerDescent目标host，走公开入口及检查点恢复。
	for negative in ["base_scan", "tower03", "base_materialize", "resume"]:
		NarrativeDirector.reset_for_test()
		if negative != "resume":
			BaseManager.clear_active_run_checkpoint("entry_qa_new_departure")
		GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_RUNTIME_RESTORE if negative == "resume" else GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
		var host := (load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene).instantiate() as TowerDescent3D
		host.test_mode = false
		host.run_seed_override = 20261111 if negative == "base_materialize" else 20261110
		add_child(host)
		for frame in 8:
			await get_tree().process_frame
		_register()
		if negative == "tower03":
			host.set("_expedition_entry_source", ExpeditionEntryContext.TOWER03)
		host.prepare_expedition_entry_ceremony()
		host.notify_expedition_entry_ceremony_ready()
		if negative.begins_with("base_"):
			_expect(NarrativeDirector.is_playing(), "正式目标host正向未触发 " + negative)
			var door_point: Variant = host.forward_door_point_from("start")
			_expect(door_point != null, "正式host找不到通往第一间房的门 " + negative)
			if door_point != null:
				var facing := Vector3(-sin(host.player.aim_yaw), 0.0, -cos(host.player.aim_yaw))
				var to_door := (door_point as Vector3) - host.player.global_position
				to_door.y = 0.0
				_expect(to_door.length_squared() > 0.0001 and facing.normalized().dot(to_door.normalized()) > 0.95, "正式host入场朝向未面向第一间房的门 " + negative)
			if negative == "base_scan":
				NarrativeDirector.abort("official_host_retry")
				host.prepare_expedition_entry_ceremony()
				host.notify_expedition_entry_ceremony_ready()
				_expect(NarrativeDirector.is_playing(), "正式host同request取消后不能重试")
			await _advance(3.7)
			_expect(not NarrativeDirector.is_playing() and not host.player.input_locked and not NarrativeDirector.is_camera_override_active(), "正式host正常结束未归还 " + negative)
			if negative == "base_materialize":
				var snapshot := host.build_runtime_save_snapshot()
				_expect(BaseManager.set_active_run_checkpoint(snapshot, "entry_qa_resume"), "续档检查点未落盘")
		else:
			_expect(not NarrativeDirector.is_playing() and not NarrativeDirector.is_player_input_locked(), "正式目标host负向失败 " + negative)
			if negative == "resume":
				_expect(not (host.get("_runtime_restore_snapshot") as Dictionary).is_empty(), "续档未实际恢复目标host")
		print("OFFICIAL_HOST_OK ", negative, " host=", host.get_script().resource_path)
		BaseManager.unregister_runtime_checkpoint_provider(host, false)
		host.queue_free()
		await get_tree().process_frame


func _check_loading_e2e(seed: int, via_base_menu := false) -> void:
	# 让同一探针跨真实 change_scene 存活，不把测试舞台带进正式关卡。
	var tree := get_tree()
	tree.current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	NarrativeDirector.reset_run_state()
	NarrativeDirector.set_process(true)
	var injected: Array[Node] = []
	var seed_hook := func(node: Node) -> void:
		if node.scene_file_path == GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D:
			node.set("run_seed_override", seed)
			injected.append(node)
			print("LOADING_E2E_SEED seed=", seed, " test_mode=", node.get("test_mode"))
	tree.node_added.connect(seed_hook)
	var weapon: Dictionary = {}
	var request_id := 0
	if not via_base_menu:
		weapon = BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("weapon_pistol"))
		var backpack := BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("equipment_backpack_2"))
		var carry := RunPersistenceService.finalize_runtime_snapshot({
			"scope": "base", "runtime_map_id": "", "current_room_id": "facility",
			"current_floor_index": 1, "player_position": [3.0, 0.05, -7.0],
			"run_seed": 99, "run_id": "loading_qa_base", "player_hp": 73,
			"inventory_capacity": 12, "inventory_slots": [],
			"equipped_weapon_items": [weapon, {}], "active_weapon_slot": 0,
			"equipped_backpack_item": backpack, "run_currency": 17,
			Dungeon3D.MISSION_OPERATIONS_DEPARTURE_CARRY_KEY: true,
			ExpeditionEntryContext.SOURCE_KEY: ExpeditionEntryContext.BASE,
		})
		_expect(BaseManager.set_active_run_checkpoint(carry, "loading_e2e_departure"), "BASE carry写入失败")
		request_id = GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
		_expect(GameDesignConfig.select_expedition_level("expedition_01"), "pending level登记失败")
	_expect(rendering and RenderingServer.get_current_rendering_method() == "forward_plus", "真实读取页E2E要求Forward+")
	var result := {"seed": seed, "request_id": request_id, "route": "base_menu" if via_base_menu else "prepared_request", "events": [], "completed": false, "renderer": RenderingServer.get_current_rendering_method(), "user_dir": ProjectSettings.globalize_path("user://")}
	var tag := "basemenu" if via_base_menu else "loading"
	var finished: Dictionary = {}
	var finish_hook := func(id: String, reason: String) -> void:
		if not id.begins_with("nar_expedition_entry_hologram_"):
			return
		finished["id"] = id
		finished["reason"] = reason
		var host := tree.current_scene as TowerDescent3D
		if host != null and host.player != null:
			finished["camera"] = host.player.camera.global_transform
			finished["local"] = host.player.camera.transform
			finished["player_position"] = host.player.global_position
			finished["fov"] = host.player.camera.fov
			finished["attributes"] = host.player.camera.attributes
			var materials: Dictionary = {}
			for child in host.player.avatar.visual_root.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				materials[str(mesh.get_path())] = {"override": mesh.material_override, "overlay": mesh.material_overlay, "shadow": mesh.cast_shadow, "transparency": mesh.transparency}
			finished["materials"] = materials
	NarrativeDirector.narrative_finished.connect(finish_hook)
	var started := Time.get_ticks_msec()
	var departed := true
	if via_base_menu:
		departed = await _depart_from_base_menu(result)
	else:
		_expect(tree.change_scene_to_file("res://scenes/ExpeditionLoadingScreen.tscn") == OK, "真实读取页切换失败")
	var loading: ExpeditionLoadingScreen
	var host: TowerDescent3D
	var original: Dictionary = {}
	var originals: Array[Dictionary] = []
	var prepared := false
	var opening := false
	var active := false
	var solid := false
	var last_status := ""
	while departed and Time.get_ticks_msec() - started < 420000:
		await tree.process_frame
		await RenderingServer.frame_post_draw
		if tree.current_scene is ExpeditionLoadingScreen and loading == null:
			loading = tree.current_scene as ExpeditionLoadingScreen
			_expect(str(loading.get("_target_scene")) == GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D, "读取页目的地不是正式01")
			_expect(str(loading.get("_level_id")) == "expedition_01" and GameDesignConfig.pending_expedition_level_id.is_empty(), "pending level未被真实读取页消费")
			_loading_event(result, "loading_screen")
			await _capture("%s_%d_screen" % [tag, seed])
		if IrisTransition.loading_status != last_status:
			last_status = IrisTransition.loading_status
			print("LOADING_E2E_STATUS seed=", seed, " elapsed_ms=", Time.get_ticks_msec() - started, " status=", last_status)
		if is_instance_valid(loading) and not str(loading.get("_failure_kind")).is_empty():
			_expect(false, "真实读取页失败: " + str(loading.get("_failure_kind")) + " " + last_status)
			break
		host = tree.current_scene as TowerDescent3D
		if host == null or host.player == null or host.player.camera == null:
			continue
		var player := host.player
		var adapter: RefCounted = NarrativeDirector.get("_adapter")
		var presentation: RefCounted = adapter.get("_expedition_entry_presentation")
		if presentation == null and not prepared and bool(host.get_meta("loading_scene_ready", false)):
			original = {"camera": player.camera.global_transform, "local": player.camera.transform, "player_position": player.global_position, "fov": player.camera.fov, "attributes": player.camera.attributes}
			originals.clear()
			for child in player.avatar.visual_root.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				originals.append({"mesh": mesh, "override": mesh.material_override, "overlay": mesh.material_overlay, "shadow": mesh.cast_shadow, "transparency": mesh.transparency})
		if presentation != null and not prepared:
			prepared = true
			_expect(not original.is_empty() and not originals.is_empty(), "未观察到预备前正式相机/材质")
			# 预热阶段的表情材质不是接管边界；以prepare实际保存的材质为归还真源。
			# 不禁用表情、不替换正式材质；结束信号仍逐件要求精确引用相同。
			originals.clear()
			for entry in presentation.get("_materials"):
				originals.append({"mesh": entry["mesh"], "override": entry["material_override"], "overlay": entry["material_overlay"], "shadow": entry["cast_shadow"], "transparency": entry["transparency"]})
			result["restored_mesh_count"] = originals.size()
			_expect(originals.size() > 8, "正式prepare未保存真实多部件玩家")
			_expect(IrisTransition.is_covered() and not NarrativeDirector.is_playing() and not presentation.is_active(), "未在全黑且尚未start时完成prepare")
			_expect(player.input_locked and NarrativeDirector.is_player_input_locked(), "黑幕下预备未锁实际玩家")
			_expect(host.run_seed == seed and not host.test_mode and injected.size() == 1, "未使用正式host及指定seed")
			_expect(host.get_expedition_entry_source() == ExpeditionEntryContext.BASE, "BASE来源未转交")
			# 入场近景是从背后拍的，所以"朝哪"直接决定玩家第一眼看到什么：
			# 必须朝主路第一间房的门，而不是出生时的世界 −Z（那会正对入口/出口侧）。
			var door_point: Variant = host.forward_door_point_from("start")
			_expect(door_point != null, "远征起始房找不到通往第一间房的门/下一间房")
			if door_point != null:
				var facing := Vector3(-sin(player.aim_yaw), 0.0, -cos(player.aim_yaw))
				var to_door := (door_point as Vector3) - player.global_position
				to_door.y = 0.0
				var dot := facing.normalized().dot(to_door.normalized()) if to_door.length_squared() > 0.0001 else -1.0
				result["door_facing_dot"] = dot
				_expect(dot > 0.95, "入场朝向未面向第一间房的门: dot=%.3f" % dot)
			var consumed_request := int(host.get_entry_context_snapshot().get("request_id", -1))
			result["request_id"] = consumed_request
			if via_base_menu:
				# 基地菜单链的 request/carry 全由正式出发代码写；这里只要求确实消费了一条正式请求。
				_expect(consumed_request > 0 and GameEntryFlow.peek_pending_entry().is_empty(), "基地菜单出发的request未被正式host消费")
			else:
				_expect(consumed_request == request_id and GameEntryFlow.peek_pending_entry().is_empty(), "入口request未由正式host消费")
				_expect(player.current_hp == 73 and GameManager.currency == 17 and str(player.get_equipped_weapon_item_for_slot(0).get("weapon_instance_id", "")) == str(weapon.get("weapon_instance_id", "")), "BASE carry未恢复HP/金币/原枪实例")
			_expect((host.get("_runtime_restore_snapshot") as Dictionary).is_empty(), "错误走了续档路径")
			var warm: Dictionary = host.get_meta("loading_warmup_report", {})
			var rooms: Dictionary = host.get_meta("loading_room_warm_report", {})
			result["warmup"] = warm
			result["room_warmup"] = rooms
			_expect(bool(warm.get("completed", false)) and not bool(warm.get("skipped", true)) and int(warm.get("vfx_pending", -1)) == 0 and int(warm.get("kinds_done", 0)) == int(warm.get("kinds_total", -1)), "实际VFX/怪物预热未完成: " + str(warm))
			_expect(not bool(rooms.get("skipped", true)) and int(rooms.get("rooms", 0)) == int(rooms.get("total", -1)) and str(rooms.get("truncated", "")).is_empty(), "逐房预热未完成: " + str(rooms))
			_loading_event(result, "prepared_under_black")
		if prepared and not active:
			_expect(player.input_locked, "开圈期间输入提前解锁")
			var offset := player.camera.global_position - player.global_position
			offset.y = 0.0
			_expect(offset.normalized().dot(Vector3.BACK.rotated(Vector3.UP, player.aim_yaw)) > 0.90 and offset.length() < 5.0, "开圈时后方近景未就绪")
			if not IrisTransition.is_covered() and (IrisTransition.get("_mask") as CanvasItem).visible and not opening:
				opening = true
				_expect(not presentation.is_active() and not NarrativeDirector.is_playing(), "开圈尚未完成便presentation.start")
				_expect(is_instance_valid(loading) and not loading.visible, "读取页背板开圈时未撤走")
				_loading_event(result, "iris_opening_prepared_locked")
		if presentation != null and presentation.is_active() and not active:
			active = true
			_expect(opening and not (IrisTransition.get("_mask") as CanvasItem).visible and is_equal_approx(float(IrisTransition.get("_radius")), IrisTransition.HOLE_MAX), "presentation.start早于黑幕完全打开")
			_expect(NarrativeDirector.active_id() == IDS[posmod(seed, 2)], "正式seed选片语义不符")
			_loading_event(result, "presentation.start_after_open")
		if presentation != null and active and not solid and bool(presentation.get_snapshot().get("solid", false)):
			solid = true
			_expect(player.input_locked and NarrativeDirector.is_camera_override_active(), "近景完成时已提前归还")
			_loading_event(result, "solid_close")
			await _capture("%s_%d_solid_close" % [tag, seed])
		if not finished.is_empty():
			_expect(str(finished.get("reason", "")) == "flow.end", "仪式非正常结束: " + str(finished.get("reason")))
			_expect(active and solid, "未观察到真实start及近景成形")
			_expect(not player.input_locked and not NarrativeDirector.is_player_input_locked() and not NarrativeDirector.is_camera_override_active(), "结束输入/相机所有权未归还")
			if not original.is_empty():
				result["camera_diagnostic"] = {"before_global": str(original["camera"]), "after_global": str(finished["camera"]), "before_local": str(original["local"]), "after_local": str(finished["local"]), "before_player": str(original["player_position"]), "after_player": str(finished["player_position"])}
				# 相机挂在玩家身下；真实物理启用后会从出生y=0.05落到地面y=0.03。
				# 局部位姿须精确归还，世界位移只能等于玩家的实际位移。
				var expected_global: Transform3D = original["camera"]
				expected_global.origin += (finished["player_position"] as Vector3) - (original["player_position"] as Vector3)
				_expect((finished["local"] as Transform3D).is_equal_approx(original["local"]) and (finished["camera"] as Transform3D).is_equal_approx(expected_global), "结束相机未精确归位: " + str(result["camera_diagnostic"]))
				_expect(finished["fov"] == original["fov"] and finished["attributes"] == original["attributes"], "结束相机光学状态未归还")
			for entry in originals:
				var mesh := entry["mesh"] as MeshInstance3D
				# 在导演完成信号的同步边界检查，避免随后正常表情随机换材质造成误报。
				var restored: Dictionary = (finished.get("materials", {}) as Dictionary).get(str(mesh.get_path()), {})
				_expect(restored.get("override") == entry["override"] and restored.get("overlay") == entry["overlay"] and restored.get("shadow") == entry["shadow"] and restored.get("transparency") == entry["transparency"], "正式玩家材质/overlay残留: " + str(mesh.get_path()))
			_expect(not is_instance_valid(loading) and not IrisTransition.is_loading_active() and not (IrisTransition.get("_mask") as CanvasItem).visible and not get_viewport().disable_3d, "读取页/黑幕/渲染门禁残留")
			_expect(adapter.get("_expedition_entry_presentation") == null and (NarrativeDirector.get("_pending_entry") as Dictionary).is_empty(), "presentation或pending残留")
			await _capture("%s_%d_gameplay" % [tag, seed])
			var before := player.global_position
			Input.action_press("move_right")
			for frame in 12:
				await tree.physics_frame
			Input.action_release("move_right")
			_expect(player.global_position.distance_to(before) > 0.1, "归位后真实玩家无法移动")
			result["movement_distance"] = player.global_position.distance_to(before)
			result["dispatch"] = NarrativeDirector.dispatch_log()
			result["completed"] = true
			_loading_event(result, "gameplay_restored_movable")
			break
	if not bool(result["completed"]):
		_expect(false, "真实读取页E2E未完成，最后状态=" + last_status)
	result["elapsed_ms"] = Time.get_ticks_msec() - started
	result["failures"] = failures
	var file := FileAccess.open(output.path_join("%s_%d_result.json" % [tag, seed]), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
	tree.node_added.disconnect(seed_hook)
	NarrativeDirector.narrative_finished.disconnect(finish_hook)
	print("EXPEDITION_ENTRY_RESULT %s seed=%d renderer=%s failures=%d completed=%s" % [result["route"], seed, RenderingServer.get_current_rendering_method(), failures.size(), result["completed"]])
	tree.quit(0 if failures.is_empty() and bool(result["completed"]) else 1)


## 真实基地菜单链：BaseWorld3D → 情报室交互（与按 E 同一条正式控制器）→ 真实 RogueMapSelectMenu
## → 真实鼠标事件点击远征01牌 → 正式出发/读取页。补的是“人工在99F基地菜单点出发”这一步；
## 仍不是人手操作，但走的是正式设施交互、正式菜单输入和正式出发代码，不是测试直接造请求。
func _depart_from_base_menu(result: Dictionary) -> bool:
	var tree := get_tree()
	if tree.change_scene_to_file("res://scenes/BaseWorld3D.tscn") != OK:
		_expect(false, "真实基地场景切换失败")
		return false
	var base_world: Node3D = null
	for frame in 900:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == "res://scenes/BaseWorld3D.tscn":
			base_world = tree.current_scene as Node3D
			break
	_expect(base_world != null, "真实基地场景未加载")
	if base_world == null:
		return false
	_loading_event(result, "base_world_loaded")
	_expect(bool(BaseManager.data.base_generator_enabled), "基地未供电，情报室不可用")
	var facility: BaseFacility3D = null
	for node in base_world.find_children("*", "BaseFacility3D", true, false):
		var candidate := node as BaseFacility3D
		if candidate != null and candidate.facility_id == "mission_operations":
			facility = candidate
			break
	_expect(facility != null, "真实基地缺少情报室设施")
	if facility == null:
		return false
	var player := base_world.get("player") as Player3D
	_expect(player != null and not player.input_locked, "真实基地玩家缺失或开局即被锁")
	if player == null:
		return false
	var placed := false
	for offset in [Vector3(0.0, 0.0, 2.4), Vector3(0.0, 0.0, -2.4), Vector3(2.4, 0.0, 0.0), Vector3(-2.4, 0.0, 0.0), Vector3.ZERO]:
		player.global_position = facility.global_position + (offset as Vector3)
		player.velocity = Vector3.ZERO
		for frame in 8:
			await tree.physics_frame
		if not (facility.get_interaction_candidate(player) as Dictionary).is_empty():
			placed = true
			break
	_expect(placed, "玩家未能进入情报室交互区")
	if not placed:
		return false
	# 正式交互控制器：与玩家按 E 同一条调用链，不直接 emit activated。
	var activated_hits := [0]
	facility.activated.connect(func(_f): activated_hits[0] += 1)
	var focus_before: Dictionary = player.get_interaction_focus_snapshot()
	print("BASE_MENU_DIAG focus_before=", focus_before, " available=", facility.get("_available"), " candidate=", facility.get_interaction_candidate(player), " snapshot=", BaseManager.get_facility_snapshot("mission_operations"))
	_expect(player.request_interaction_for_test(), "正式交互请求未触发情报室")
	for frame in 6:
		await tree.process_frame
	var status := base_world.get("status_label") as Label
	print("BASE_MENU_DIAG activated=", activated_hits[0], " menu=", base_world.get("_active_menu"), " status=", status.text if status != null else "")
	var menu := base_world.get("_active_menu") as RogueMapSelectMenu
	_expect(menu != null, "情报室未打开真实选关菜单")
	if menu == null:
		return false
	for frame in 600:
		if str(menu.get("_state")) == "active":
			break
		await tree.process_frame
	_expect(str(menu.get("_state")) == "active", "选关菜单未进入可操作态")
	_expect(menu.entry_state("expedition_01") == RogueMapSelectMenu.ENTRY_OPEN, "远征01入口在真实菜单里不可点")
	var index := menu.LEVEL_IDS.find("expedition_01")
	_expect(index >= 0, "真实选关菜单缺少远征01")
	if index < 0 or str(menu.get("_state")) != "active":
		return false
	var city := menu.get("_city") as Node3D
	var camera := menu.get("_camera") as Camera3D
	_expect(city != null and camera != null, "选关菜单相机/全息城缺失")
	if city == null or camera == null:
		return false
	var markers := city.get("markers") as Array
	_expect(markers != null and index < markers.size(), "全息城缺少远征01标注点")
	if markers == null or index >= markers.size():
		return false
	var marker := markers[index] as Node3D
	var screen := camera.unproject_position(marker.global_position)
	print("BASE_MENU_DIAG markers=", markers.size(), " index=", index, " marker=", marker.global_position, " screen=", screen, " pick=", menu.call("_pick", screen), " state=", menu.get("_state"), " selection=", menu.get("_selection"))
	await _capture("basemenu_%d_select" % int(result["seed"]))
	# 真实鼠标事件：窗口事件 → 菜单 `_input` → `_pick` 命中牌面 → confirm_selection。
	# `unproject_position` 给的是视口逻辑坐标；`parse_input_event` 的鼠标事件先经窗口伸缩，
	# 与 `verify_expedition_hologram_city` 同一口径，直接拿逻辑坐标点会点空。
	print("BASE_MENU_DIAG input_state processing=", menu.is_processing_input(), " final_transform=", get_viewport().get_final_transform(), " mouse_mode=", Input.mouse_mode)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	get_viewport().push_input(motion, true)
	await tree.process_frame
	print("BASE_MENU_DIAG push_local_hover selection=", menu.get("_selection"), " state=", menu.get("_state"))
	var click := InputEventMouseButton.new()
	click.position = screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	get_viewport().push_input(click, true)
	await tree.process_frame
	print("BASE_MENU_DIAG push_local_click state=", menu.get("_state"), " departing=", menu.get("_departing"))
	if str(menu.get("_state")) == "active":
		# 回退路线：窗口坐标 + 系统输入队列（与全息城回归同一写法）。
		var window_point := get_viewport().get_final_transform() * screen
		var wmotion := InputEventMouseMotion.new()
		wmotion.position = window_point
		Input.parse_input_event(wmotion)
		Input.flush_buffered_events()
		await tree.process_frame
		var wclick := InputEventMouseButton.new()
		wclick.position = window_point
		wclick.button_index = MOUSE_BUTTON_LEFT
		wclick.pressed = true
		Input.parse_input_event(wclick)
		Input.flush_buffered_events()
		await tree.process_frame
		print("BASE_MENU_DIAG parse_event_click state=", menu.get("_state"), " departing=", menu.get("_departing"))
	var release := InputEventMouseButton.new()
	release.position = screen
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	get_viewport().push_input(release, true)
	for frame in 12:
		await tree.process_frame
	print("BASE_MENU_DIAG after_click departing=", menu.get("_departing"), " state=", menu.get("_state"), " selection=", menu.get("_selection"))
	var departing := bool(menu.get("_departing")) or str(menu.get("_state")) in ["entering", "departing"]
	_expect(departing, "真实鼠标点击远征01未触发出发")
	if not departing:
		return false
	_loading_event(result, "base_menu_click_departure")
	return true


func _loading_event(result: Dictionary, event: String) -> void:
	(result["events"] as Array).append({"event": event, "ms": Time.get_ticks_msec(), "frame": Engine.get_process_frames()})
	print("LOADING_E2E_EVENT seed=", result["seed"], " ", event, " frame=", Engine.get_process_frames())


func _expect(value: bool, message: String) -> void:
	if not value and message not in failures:
		failures.append(message)
		printerr("FAIL: ", message)
