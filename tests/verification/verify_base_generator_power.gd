extends Node

var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _ready() -> void:
	BaseManager.save_path = "user://generator_power_test.json"
	BaseManager.data = BaseData.new()
	var data := BaseManager.data
	data.base_energy_current = 50.0
	data.world_time_elapsed_game_seconds = 3600.0
	check(bool(BaseManager.set_base_generator_enabled(false).get("success")), "关机失败")
	var stored := data.base_energy_current
	data.world_time_elapsed_game_seconds = 7200.0
	var off := BaseManager.get_base_energy_snapshot()
	check(is_equal_approx(data.base_energy_current, stored), "停机仍在发电")
	check(float(off.current) == 0.0 and not bool(off.available), "断电仍有可用电量")
	check(not bool(BaseManager.get_facility_snapshot("base_vending").available), "断电售货机仍可用")
	check(bool(BaseManager.get_facility_snapshot("vault").available), "断电锁死非用电仓库")
	check(not BaseManager.consume_base_energy(1), "断电允许消费")
	check(not bool(BaseManager.recover_player_state_at_facility(null).get("success")), "断电允许恢复")
	check(BaseData.from_dict(data._to_dict()).base_generator_enabled == false, "开关序列化丢失")
	check(BaseData.from_dict({}).base_generator_enabled, "旧档默认状态错误")
	BaseManager.load_base()
	check(not BaseManager.is_base_power_on(), "读档丢失关机状态")
	data = BaseManager.data
	data.world_time_elapsed_game_seconds = 10800.0
	BaseManager.force_save_failure_for_test = true
	check(not bool(BaseManager.set_base_generator_enabled(true).get("success")), "故障保存错误成功")
	check(not BaseManager.is_base_power_on(), "故障保存没有回滚")
	BaseManager.force_save_failure_for_test = false
	check(bool(BaseManager.set_base_generator_enabled(true).get("success")), "启动失败")
	check(is_equal_approx(data.base_energy_current, stored), "重新启动补发停机电量")
	data.world_time_elapsed_game_seconds += 3600.0
	BaseManager.get_base_energy_snapshot()
	check(is_equal_approx(data.base_energy_current, stored + 4.0), "启动后恢复速度错误")
	var light := WastelandLight3D.new()
	add_child(light)
	var light_switch := RoomLightSwitch3D.new()
	add_child(light_switch)
	light_switch.configure(light, true)
	light_switch.bind_base_power()
	var peer := RoomLightSwitch3D.new()
	add_child(peer)
	peer.configure(light, true)
	light_switch.link_switch(peer)
	peer.bind_base_power()
	BaseManager.set_base_generator_enabled(false)
	check(not light.is_light_enabled(), "停电灯仍亮")
	check(not light_switch.toggle_light(), "断电墙面开关仍可开灯")
	BaseManager.set_base_generator_enabled(true)
	check(light.is_light_enabled() and peer.is_light_on(), "复电未恢复并联灯光")
	light_switch.set_light_on(false)
	BaseManager.set_base_generator_enabled(false)
	BaseManager.set_base_generator_enabled(true)
	check(not light.is_light_enabled(), "复电覆盖局部关灯意图")
	var generator := load("res://assets/art/environments/tower_zones/rooftop/runtime/generator/env_rooftop_generator_root_top3d.tscn") as PackedScene
	var instance := generator.instantiate()
	add_child(instance)
	check(instance.is_in_group(PlayerInteractionController3D.PROVIDER_GROUP), "正式发电机未注册交互")
	instance.queue_free()
	peer.queue_free()
	light_switch.queue_free()
	light.queue_free()
	await get_tree().process_frame
	await _verify_formal_scene()
	if failures.is_empty():
		print("BASE_GENERATOR_POWER_OK")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_formal_scene() -> void:
	var tower := load("res://scenes/TowerDescent3D.tscn").instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 100990
	add_child(tower)
	for i in 40:
		await get_tree().process_frame
		await get_tree().physics_frame
	var room := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	check(room != null, "正式基地房间缺失")
	if room == null:
		return
	var formal_generator: Node3D
	for content in get_tree().get_nodes_in_group("scene_interactive_content"):
		if content.get_meta("asset_id", "") == "ENV-ROOFTOP-GENERATOR":
			formal_generator = content as Node3D
	check(formal_generator != null, "天台正式发电机缺失")
	if formal_generator != null:
		tower.player.global_position = formal_generator.global_position + Vector3(0, 0.2, -1.8)
		check(not formal_generator.call("get_interaction_candidate", tower.player).is_empty(), "正式发电机E候选缺失")
		check(bool(formal_generator.call("perform_interaction", tower.player, {})), "正式发电机关闭失败")
		check(not BaseManager.is_base_power_on(), "正式交互未关闭供电")
		check(bool(formal_generator.call("perform_interaction", tower.player, {})), "正式发电机启动失败")
		check(BaseManager.is_base_power_on(), "正式交互未启动供电")
	tower.set_process(false)
	tower.set_physics_process(false)
	room.ensure_detail_built()
	var art := room.get_node("Art")
	var switches := room.call("_all_room_light_switches") as Array
	check(switches.size() == 2, "正式基地未装配两个开关")
	if switches.is_empty():
		return
	var wall_switch := switches[0] as RoomLightSwitch3D
	wall_switch.set_light_on(true)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = room.global_position + Vector3(5.0, 4.35, -1.0)
	camera.look_at(room.global_position + Vector3(5.0, 4.44, -4.78))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 65.0
	camera.make_current()
	await _capture("base_power_on")
	BaseManager.set_base_generator_enabled(false)
	check(not wall_switch.is_light_on(), "正式基地停电主灯仍亮")
	check(not bool(art.call("get_presentation_snapshot").get("presentation_lighting_enabled")), "正式基地停电自发光仍亮")
	await _capture("base_power_off")
	BaseManager.set_base_generator_enabled(true)
	check(wall_switch.is_light_on(), "正式基地复电失败")
	wall_switch.set_light_on(false)
	wall_switch.toggle_light()
	await get_tree().create_timer(0.2).timeout
	BaseManager.set_base_generator_enabled(false)
	await get_tree().create_timer(5.3).timeout
	check(not wall_switch.is_light_on(), "在途启动协程在停电后重开主灯")
	check(not bool(art.call("get_presentation_snapshot").get("presentation_lighting_enabled")), "在途启动协程在停电后重开自发光")
	BaseManager.set_base_generator_enabled(true)
	camera.queue_free()
	tower.queue_free()
	await get_tree().process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("GENERATOR_POWER_QA_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
