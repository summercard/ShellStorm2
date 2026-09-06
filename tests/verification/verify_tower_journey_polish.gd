extends Node
## 正式塔楼的目标、画质重应用和冲刺缓冲回归；不写用户存档。

func _ready() -> void:
	var failures: Array[String] = []
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.player.set_physics_process(false)
	var stage := (tower.get("_floor_stages") as Dictionary)[0] as TowerFloorStage3D
	var rooftop := stage.get("_rooftop_art_instance") as Node3D
	var ambience: Dictionary = rooftop.call("get_presentation_snapshot")
	_expect(int(ambience.get("authored_tracks", 0)) >= 29, "天台Blender环境动画未接入", failures)
	_expect(int(ambience.get("practical_lights", 0)) == 3, "天台串灯缺少真实暖光", failures)
	var windmill := rooftop.find_child("棚屋小风车_旋转根", true, false) as Node3D
	var animator := rooftop.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if windmill == null or animator == null:
		failures.append("天台风车的源动画挂点缺失")
	else:
		var before := windmill.transform
		animator.advance(0.5)
		_expect(not before.is_equal_approx(windmill.transform), "风车轨道没有驱动真实模型", failures)
	rooftop.hide()
	_expect(animator.process_mode == Node.PROCESS_MODE_DISABLED, "隐藏天台继续计算动画", failures)
	rooftop.show()
	var floor_mesh := (stage.get("_floor_visual_light") as MultiMeshInstance3D)
	_expect(floor_mesh.material_override == null, "程序材质覆盖了Blender色盘", failures)
	_expect(floor_mesh.multimesh.mesh.get_surface_count() == 2, "地砖未保留金属与哑光双材质", failures)
	var bounds := floor_mesh.multimesh.mesh.get_aabb()
	_expect(absf(bounds.size.x - 5.0) < 0.002 and absf(bounds.size.z - 5.0) < 0.002, "地砖不符合5米模块接口", failures)
	_expect(absf(bounds.end.y - 0.15) < 0.002, "地砖顶面偏离承重面", failures)
	for surface in range(floor_mesh.multimesh.mesh.get_surface_count()):
		var material := floor_mesh.multimesh.mesh.surface_get_material(surface) as BaseMaterial3D
		_expect(material.albedo_texture != null and material.albedo_texture.resource_path.ends_with("设施低亮多巴胺色盘_10x10_512.png"), "地砖未引用唯一色盘", failures)
	_expect("西侧" in tower._journey_objective(100), "天台没有西侧路线", failures)
	_expect("东侧" in tower._journey_objective(99), "基地没有东侧路线", failures)
	var environment := tower.world_environment.environment
	GraphicsSettingsManager.apply_to_environment(environment)
	_expect(is_equal_approx(environment.volumetric_fog_density, 0.003), "画质重应用覆盖了塔楼体积雾", failures)
	var density := environment.fog_density
	var atmosphere := tower.get_node("TowerAtmosphere3D") as TowerAtmosphere3D
	atmosphere.set_floor_number(98)
	var clock_before := GameTimeManager.get_persistence_snapshot()
	GameTimeManager.set_elapsed_game_seconds(5.0 * 3600.0, false)
	_expect(tower.key_light.light_energy < 0.1, "跳时至夜晚太阳仍保持白昼", failures)
	GameTimeManager.restore_from_persistence(clock_before, false)
	_expect(is_equal_approx(density, environment.fog_density), "楼层改变全塔雾参数", failures)
	_expect(tower.activate_arrival_between_for_test("facility", "floor_01_entry"), "98F到达门生成失败", failures)
	var rooms := tower.get("_room_by_id") as Dictionary
	var entry := rooms["floor_01_entry"] as DungeonRoom3D
	tower.player.global_position = entry.global_position + Vector3.UP * 0.05
	tower.force_enter_room_for_test(entry.room_id)
	_expect("电梯" not in tower._journey_objective(98), "98F仍有错误电梯指引", failures)
	tower.force_open_edge_for_test("floor_01_entry", "floor_01_hub")
	var hub := rooms["floor_01_hub"] as DungeonRoom3D
	tower.player.global_position = hub.global_position + Vector3.UP * 0.05
	tower.force_enter_room_for_test(hub.room_id)
	hub.cleared = false
	(tower.get("_alive_by_room") as Dictionary)[hub.room_id] = 3
	_expect("3" in tower._journey_objective(98), "目标未反映存活敌人", failures)
	hub.cleared = true
	tower.set("_room_key_count", 1)
	_expect("钥匙开门" in tower._journey_objective(98), "清房没有路线选择提示", failures)
	var title := tower.get_node("HUD/ReferenceCombatHUD/FloorArrivalTitle") as Label
	var tween_before: Tween = tower.get("_arrival_tween")
	tower._announce_floor_arrival(98)
	_expect(tower.get("_arrival_tween") == tween_before, "同层重复进入重播标题", failures)
	_expect(title.mouse_filter == Control.MOUSE_FILTER_IGNORE, "进入标题吞掉输入", failures)

	var player := tower.player
	var machine := player.get("_state_machine") as StateMachine
	player.input_locked = false
	machine.transition_to("idle")
	player.dash_cooldown_timer = 0.08
	player.request_dash()
	_expect(not player.is_dashing, "缓冲提前绕过冷却", failures)
	player.dash_cooldown_timer = 0.0
	player._tick_dash_input_buffer(0.016)
	_expect(player.is_dashing, "冷却结束未消费缓冲", failures)
	machine.transition_to("idle")
	player.dash_cooldown_timer = 0.5
	player.request_dash()
	player.dash_cooldown_timer = 0.0
	player._tick_dash_input_buffer(0.016)
	_expect(not player.is_dashing, "过早输入不应缓存", failures)
	player.dash_cooldown_timer = 0.08
	player.request_dash()
	player.set_input_locked(true)
	# 暂停期间没有物理帧，关闭菜单也不能消费暂停前的旧请求。
	player.set_input_locked(false)
	player.dash_cooldown_timer = 0.0
	player._tick_dash_input_buffer(0.016)
	_expect(not player.is_dashing, "菜单关闭后误执行旧冲刺", failures)
	player.dash_cooldown_timer = 0.08
	player.request_dash()
	machine.transition_to("hurt")
	player._tick_dash_input_buffer(0.016)
	machine.transition_to("idle")
	player.dash_cooldown_timer = 0.0
	player._tick_dash_input_buffer(0.016)
	_expect(not player.is_dashing, "受伤后误执行旧冲刺", failures)
	tower.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TOWER_JOURNEY_POLISH_OK")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
