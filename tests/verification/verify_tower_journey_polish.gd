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
	var stage_snapshot := stage.get_snapshot()
	_expect(int(stage_snapshot.get("formal_rooftop_art_blocker_count", -1)) == 0, "天台旧设施阻挡仍未清空", failures)
	var floor_mesh := (stage.get("_floor_visual_light") as MultiMeshInstance3D)
	_expect(floor_mesh.material_override == null, "程序材质覆盖了Blender色盘", failures)
	_expect(floor_mesh.multimesh.mesh.get_surface_count() >= 1, "地砖没有可渲染表面", failures)
	var bounds := floor_mesh.multimesh.mesh.get_aabb()
	_expect(absf(bounds.size.x - 5.0) < 0.002 and absf(bounds.size.z - 5.0) < 0.002, "地砖不符合5米模块接口", failures)
	var floor_visual_origin := float(stage.call("_floor_visual_origin_y", floor_mesh.multimesh.mesh))
	_expect(absf(bounds.end.y + floor_visual_origin) < 0.002, "地砖顶面偏离承重面: %.4f" % (bounds.end.y + floor_visual_origin), failures)
	for surface in range(floor_mesh.multimesh.mesh.get_surface_count()):
		var material := floor_mesh.multimesh.mesh.surface_get_material(surface) as BaseMaterial3D
		_expect(material.albedo_texture != null and material.albedo_texture.resource_path.ends_with("设施低亮多巴胺色盘_10x10_512.png"), "地砖未引用唯一色盘", failures)
	_expect("西侧" in tower._journey_objective(100), "天台没有西侧路线", failures)
	_expect("东侧" in tower._journey_objective(99), "基地没有东侧路线", failures)
	var environment := tower.world_environment.environment
	GraphicsSettingsManager.apply_to_environment(environment)
	_expect(
		is_equal_approx(environment.volumetric_fog_density, TowerAtmosphere3D.VOLUMETRIC_FOG_DENSITY),
		"画质重应用覆盖了塔楼体积雾",
		failures
	)
	var density := environment.fog_density
	var atmosphere := tower.get_node("TowerAtmosphere3D") as TowerAtmosphere3D
	# 三扇基地门共用同一个基地壳体判定，并由塔楼宿主把结果交给大气所有者。
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	tower.player.global_position = facility.to_global(Vector3(0.0, 0.05, 0.0))
	tower._update_base_fog_transition(0.0, true)
	_expect(
		is_equal_approx(float(atmosphere.get_snapshot().get("base_interior_fog_blend", -1.0)), 1.0),
		"基地中心没有被判为室内雾范围",
		failures
	)
	for exit_offset in [
		Vector3(-15.4, 0.05, 0.0), # 底层西门外
		Vector3(15.4, 0.05, 0.0), # 底层东门外
		Vector3(15.4, TowerDescent3D.FLOOR_HEIGHT, -7.5), # 上层东侧天台门外
	]:
		tower.player.global_position = facility.to_global(exit_offset)
		tower._update_base_fog_transition(0.0, true)
		_expect(
			is_equal_approx(float(atmosphere.get_snapshot().get("base_interior_fog_blend", -1.0)), 0.0),
			"基地门外没有恢复室外雾范围: %s" % exit_offset,
			failures
		)
	tower.player.global_position = facility.to_global(Vector3(0.0, 0.05, 0.0))
	tower._update_base_fog_transition(0.0, true)
	_expect(
		is_equal_approx(environment.fog_density, TowerAtmosphere3D.BASE_INTERIOR_FOG_DENSITY),
		"基地室内距离雾没有切到低浓度",
		failures
	)
	_expect(
		is_equal_approx(
			environment.volumetric_fog_density,
			TowerAtmosphere3D.BASE_INTERIOR_VOLUMETRIC_FOG_DENSITY
		),
		"基地室内体积雾没有切到低浓度",
		failures
	)
	GraphicsSettingsManager.set_debug_postfx("debug_base_interior_fog_density", 0.0165)
	GraphicsSettingsManager.set_debug_postfx("debug_base_interior_volumetric_fog_density", 0.0045)
	_expect(is_equal_approx(environment.fog_density, 0.0165), "P键距离雾调参没有实时进入基地环境", failures)
	_expect(
		is_equal_approx(environment.volumetric_fog_density, 0.0045),
		"P键体积雾调参没有实时进入基地环境",
		failures
	)
	GraphicsSettingsManager.clear_debug_postfx()
	_expect(
		is_equal_approx(environment.fog_density, TowerAtmosphere3D.BASE_INTERIOR_FOG_DENSITY),
		"清除调试覆盖后基地距离雾没有恢复默认值",
		failures
	)
	GraphicsSettingsManager.apply_to_environment(environment)
	_expect(
		is_equal_approx(
			environment.volumetric_fog_density,
			TowerAtmosphere3D.BASE_INTERIOR_VOLUMETRIC_FOG_DENSITY
		),
		"画质重应用把基地室内体积雾闪回室外浓度",
		failures
	)
	atmosphere.update_base_interior_fog(false, 0.1)
	_expect(
		environment.fog_density > TowerAtmosphere3D.BASE_INTERIOR_FOG_DENSITY
		and environment.fog_density < TowerAtmosphere3D.FOG_DENSITY,
		"离开基地后的距离雾没有平滑过渡",
		failures
	)
	_expect(
		environment.volumetric_fog_density > TowerAtmosphere3D.BASE_INTERIOR_VOLUMETRIC_FOG_DENSITY
		and environment.volumetric_fog_density < TowerAtmosphere3D.VOLUMETRIC_FOG_DENSITY,
		"离开基地后的体积雾没有平滑过渡",
		failures
	)
	atmosphere.update_base_interior_fog(false, 10.0)
	_expect(is_equal_approx(environment.fog_density, density), "基地外距离雾没有恢复原值", failures)
	_expect(
		is_equal_approx(environment.volumetric_fog_density, TowerAtmosphere3D.VOLUMETRIC_FOG_DENSITY),
		"基地外体积雾没有恢复原值",
		failures
	)
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
	_expect("钥匙开门" not in tower._journey_objective(98), "普通门路线仍错误要求钥匙", failures)
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
