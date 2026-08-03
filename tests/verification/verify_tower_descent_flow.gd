extends Node
## v0.1 98—95层搜打撤、30m基地、独立电梯、全局光照、窄门与全息HUD验收。


func _ready() -> void:
	var failures: Array[String] = []
	if str(ProjectSettings.get_setting("application/run/main_scene", "")) != "res://scenes/TowerDescent3D.tscn":
		failures.append("项目正式入口不是 TowerDescent3D")

	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		_finish(["TowerDescent3D 场景无法加载"], 0)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		_finish(["TowerDescent3D 根节点契约缺失"], 0)
		return
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var generation := tower.get_generation_snapshot()
	var snapshot := tower.get_tower_snapshot()
	var primary_layout_signature := _layout_signature(generation, snapshot)
	var rooftop_atmosphere := snapshot.get("atmosphere", {}) as Dictionary
	var minimap_snapshot := generation.get("minimap", {}) as Dictionary
	_expect(str(snapshot.get("mode", "")) == "tower_descent", "缺少塔楼模式快照", failures)
	_expect(int(snapshot.get("map_size", 0)) == 250, "整层外壳不是250m", failures)
	_expect(int(snapshot.get("core_size", 0)) == 65, "核心区不是65m", failures)
	_expect(int(snapshot.get("grid_unit", 0)) == 5, "模块网格不是5m", failures)
	_expect(
		str(snapshot.get("floor_generation_mode", ""))
			== "triggered_atomic_floor_plan"
		and bool(snapshot.get("floor_layout_plan_valid", false))
		and (snapshot.get("floor_layout_plan_conflicts", []) as Array).is_empty()
		and (snapshot.get("generated_floor_indices", []) as Array) == [0],
		"塔楼没有使用首触发整层生成，或初始布局已与楼梯占位重叠",
		failures
	)
	_expect(
		(snapshot.get("facility_dimensions", Vector2.ZERO) as Vector2)
			.is_equal_approx(Vector2(30.0, 30.0))
		and (
			snapshot.get("facility_grid_dimensions", Vector2i.ZERO) as Vector2i
		) == Vector2i(6, 6)
		and int(snapshot.get("facility_grid_tile_count", 0)) == 36,
		"99层基地不是30×30m或没有使用6×6地砖",
		failures
	)
	_expect(
		is_equal_approx(
			float(snapshot.get("base_to_stair_corridor_length_m", 0.0)),
			15.0
		),
		"99层基地西门没有按5m组件边界保留15m入口走廊",
		failures
	)
	_expect(is_equal_approx(float(snapshot.get("floor_height", 0.0)), 9.0), "层高不是9m", failures)
	_expect(int(snapshot.get("combat_floor_count", 0)) == 4, "首批探索层不是98—95四层", failures)
	_expect(
		int(snapshot.get("rooms_per_normal_combat_floor", 0)) == 12
		and int(snapshot.get("boss_floor_room_count", 0)) == 10,
		"探索层不是十二房外围环或Boss层不是九房加Boss区",
		failures
	)
	_expect(int(snapshot.get("logical_combat_room_count", 0)) == 46, "四层逻辑房间总数不是46", failures)
	_expect(
		(snapshot.get("combat_room_size", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(30.0, 25.0))
		and (snapshot.get("combat_room_grid", Vector2i.ZERO) as Vector2i) == Vector2i(6, 5)
		and (
			snapshot.get("combat_stair_lobby_size", Vector2.ZERO) as Vector2
		).is_equal_approx(Vector2(15.0, 15.0))
		and (snapshot.get("boss_arena_size", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(90.0, 90.0)),
		"15m楼梯大厅、30×25m/6×5基础战斗房或90m Boss区尺寸错误",
		failures
	)
	_expect(int(snapshot.get("vertical_connector_count", 0)) == 5, "楼顶至95层不是五段楼梯间", failures)
	_expect(
		int(snapshot.get("vertical_arrival_gate_count", 0)) == 5
		and int(snapshot.get("vertical_arrival_open_count", -1)) == 0,
		"五段楼梯没有各自独立的下端门，或下端门初始状态错误",
		failures
	)
	_expect(
		is_equal_approx(
			float(snapshot.get("camera_door_bypass_half_width_m", 0.0)),
			0.0
		)
		and is_equal_approx(
			float(snapshot.get("camera_door_bypass_half_depth_m", 0.0)),
			0.0
		),
		"开放门洞仍保留会全局跳过南墙的镜头旁路",
		failures
	)
	_expect(
		not bool(snapshot.get("stair_surface_snap_enabled", true))
		and int(snapshot.get("stair_support_surface_count", 0)) >= 30
		and str(snapshot.get("stair_support_mode", "")) == "imported_walkable_mesh_colliders",
		"楼梯没有为Blender Walkable楼板生成碰撞，或仍在强制吸附角色Y坐标",
		failures
	)
	_expect(int(snapshot.get("support_floor_count", 0)) == 6, "六个物理层没有保持承重碰撞", failures)
	_expect(int(snapshot.get("loaded_floor_count", 99)) <= 5, "物理加载窗口超过五层", failures)
	_expect(bool(snapshot.get("has_base_elevator", false)), "99层基地没有电梯终端", failures)
	_expect(
		int(snapshot.get("standalone_elevator_count", 0)) == 5
		and not bool(snapshot.get("elevator_facilities_are_room_content", true)),
		"99—95层电梯没有拆成五个墙边独立设施",
		failures
	)
	_expect(snapshot.get("unlocked_elevator_floors", []) == [99], "初始电梯越权解锁了未探索楼层", failures)
	_expect(int(snapshot.get("facility_count", 0)) == 7, "99层没有保留七个原基地设施", failures)
	_expect(int(generation.get("room_count", 0)) == 48, "楼顶+基地+四层房间总数不是48", failures)
	_expect(bool(generation.get("has_extraction", false)), "95层没有Boss撤离点", failures)
	_expect(
		str(minimap_snapshot.get("projection_mode", ""))
			== "current_floor_holographic"
		and bool(minimap_snapshot.get("realtime_player_state", false))
		and int(minimap_snapshot.get("realtime_update_hz", 0)) >= 15
		and bool(minimap_snapshot.get("player_marker", false))
		and bool(minimap_snapshot.get("player_heading", false))
		and bool(minimap_snapshot.get("holographic_scan", false)),
		"小地图没有启用当前楼层实时全息玩家投影",
		failures
	)
	_expect(
		str(rooftop_atmosphere.get("lighting_mode", ""))
		== "global_fixed_environment",
		"塔楼没有使用全局固定环境光模式",
		failures
	)
	_expect(
		not bool(rooftop_atmosphere.get("floor_dependent_lighting", true))
		and not bool(
			rooftop_atmosphere.get("lighting_visibility_follows_player", true)
		),
		"塔楼自然光可见性仍依赖玩家当前楼层",
		failures
	)
	_expect(
		is_equal_approx(float(rooftop_atmosphere.get("sun_energy", 0.0)), 0.58)
		and bool(rooftop_atmosphere.get("sun_shadow_enabled", false)),
		"楼顶固定太阳能量或阴影状态错误",
		failures
	)
	_expect(
		is_equal_approx(float(rooftop_atmosphere.get("ambient_energy", 0.0)), 0.42)
		and bool(rooftop_atmosphere.get("rooftop_sky_bounce", false)),
		"塔楼全局环境底光或固定天空补光错误",
		failures
	)
	_expect(
		_count_named_nodes(tower, "TowerWindow_") == 0
		and _count_named_nodes(tower, "TowerWindowNaturalLight") == 0,
		"塔楼仍生成自发光假窗或窗口聚光灯",
		failures
	)
	var base_room := (
		(tower.get("_room_by_id") as Dictionary).get("facility")
		as DungeonRoom3D
	)
	base_room.ensure_detail_built()
	await get_tree().process_frame
	var base_room_snapshot := base_room.get_room_snapshot()
	_expect(
		int(base_room_snapshot.get("light_count", 0)) == 4
		and int(base_room_snapshot.get("controlled_light_count", 0)) == 4
		and bool(base_room_snapshot.get("light_switch", false))
		and bool(base_room_snapshot.get("room_light_on", false)),
		"99层基地没有默认点亮的四灯一控照明系统",
		failures
	)
	_expect(
		int(base_room_snapshot.get("tower_corner_module_count", 0)) == 4
		and int(base_room_snapshot.get("tower_door_wall_module_count", 0)) == 2
		and int(base_room_snapshot.get("tower_wall_module_count", 0)) >= 8
		and int(base_room_snapshot.get("wall_material_variant_a_count", 0)) > 0
		and int(base_room_snapshot.get("wall_material_variant_b_count", 0)) > 0,
		"99层基地没有复用5m墙/门/拐角组件，或A/B墙材质没有交替",
		failures
	)
	_expect(
		int(base_room_snapshot.get("shadow_capable_light_count", 0)) == 1
		and int(base_room_snapshot.get("room_light_cull_mask", 0)) == 3,
		"99层基地没有配置一盏角色/怪物可投影主灯",
		failures
	)
	var base_light_switch := base_room.get_node_or_null(
		"RoomLightSwitch3D"
	) as RoomLightSwitch3D
	_expect(base_light_switch != null, "99层基地灯光总开关不存在", failures)
	if base_light_switch != null:
		var base_entry_door := base_room.get_door_node("west")
		_expect(
			base_entry_door != null
			and base_light_switch.position.distance_to(base_entry_door.position) >= 3.8
			and str(base_light_switch.get_meta("facility_entry_direction", "")) == "west",
			"99层基地灯开关没有放在入口侧，或离开门交互区过近",
			failures
		)
		base_light_switch.toggle_light()
		_expect(
			not base_light_switch.is_light_on(),
			"99层基地灯光总开关不能统一关闭四盏灯",
			failures
		)
		base_light_switch.toggle_light()
		_expect(
			base_light_switch.is_light_on(),
			"99层基地灯光总开关不能统一恢复四盏灯",
			failures
		)
	await _validate_door_contract(tower, failures)
	await _validate_floor_search_and_loot(tower, failures)
	await _validate_manual_flashlight(tower, failures)
	_validate_combat_floor_layouts(generation, snapshot, failures)
	_validate_stair_room_clearance(tower, failures)
	_expect(
		tower.player.camera.position.is_equal_approx(Vector3(0.0, 8.0, 2.77)),
		"塔楼摄像机没有保持Y=8m、后移2.77m(65°俯视)",
		failures
	)
	_expect(
		tower.player.camera.rotation.x > -1.25
		and tower.player.camera.rotation.x < -1.05,
		"塔楼摄像机没有形成室内65°斜俯视角",
		failures
	)
	_expect(
		is_equal_approx(tower.player.camera.fov, 65.0),
		"塔楼摄像机FOV不是65度",
		failures
	)
	_expect(
		not bool(snapshot.get("camera_floor_cutaway_enabled", true))
		and str(snapshot.get("camera_cutaway_mode", "")) == "occluded_player_silhouette"
		and bool(snapshot.get("camera_occlusion_silhouette_enabled", false))
		and int(snapshot.get("camera_hidden_wall_count", -1)) == 0
		and bool(snapshot.get("physical_occlusion_only", false))
		and int(snapshot.get("camera_near_fade_candidate_count", -1)) == 0
		and not bool(snapshot.get("camera_wall_material_mutation_enabled", true)),
		"固定镜头仍在隐藏墙体，或没有启用遮挡角色轮廓",
		failures
	)
	await _validate_camera_lower_wall_lift(tower, failures)

	var heights: Array = snapshot.get("floor_heights", [])
	_expect(heights.size() == 6, "物理高度层数不是六层", failures)
	for index in range(heights.size()):
		_expect(
			is_equal_approx(float(heights[index]), -9.0 * float(index)),
			"第%d个物理层高度不在9m网格" % index,
			failures
		)

	var stage_snapshots: Array = snapshot.get("floor_stages", [])
	_expect(stage_snapshots.size() == 6, "没有生成六个模块化楼层外壳", failures)
	for stage in stage_snapshots:
		var stage_data := stage as Dictionary
		_expect(int(stage_data.get("outer_module_count", 0)) == 200, "外墙没有按5m模块拼成250m周长", failures)
		_expect(bool(stage_data.get("uses_imported_floor_mesh", false)), "楼板没有使用Blender导入模块", failures)
		_expect(bool(stage_data.get("uses_imported_outer_mesh", false)), "外墙没有使用Blender导入模块", failures)
		_expect(bool(stage_data.get("support_collision_persistent", false)), "隐藏楼层失去承重碰撞", failures)

	# 已加载楼层保持完整渲染；楼顶地板与实体楼层关系自然遮住下层。
	var roof_stage := _stage_snapshot(stage_snapshots, 0)
	var base_stage := _stage_snapshot(stage_snapshots, 1)
	_expect(bool(roof_stage.get("floor_visible", false)), "出生时楼顶地面不可见", failures)
	_expect(bool(base_stage.get("outer_visible", false)), "楼顶边缘看不到99层外立面", failures)
	_expect(bool(base_stage.get("floor_visible", false)), "加载中的99层楼板被动态隐藏", failures)
	for stage in stage_snapshots:
		var stage_data := stage as Dictionary
		var floor_index := int(stage_data.get("floor_index", -1))
		var loaded: bool = floor_index in (snapshot.get("loaded_floor_indices", []) as Array)
		_expect(
			bool(stage_data.get("floor_visible", false)) == loaded
			and bool(stage_data.get("outer_visible", false)) == loaded,
			"第%d层没有遵循纯流送显隐" % floor_index,
			failures
		)
	_expect(
		int(roof_stage.get("outer_module_count", 0)) == 200
		and bool(roof_stage.get("uses_imported_outer_mesh", false)),
		"楼顶外缘没有使用200块5m围栏模块",
		failures
	)

	# 五段楼梯都必须共享9m U形模板契约，通行宽度/折返位移一致并有三面满高墙。
	var first_stair: Node3D = null
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		var points: Array = connector.get_meta("path_points", [])
		_expect(points.size() == 11, "%s 不是十一节点U形楼梯模板" % connector.name, failures)
		if points.size() == 11:
			_expect(
				(points[0] as Vector3).distance_to(
					connector.get_meta("upper_door_position", Vector3.INF) as Vector3
				) <= 0.01
				and (points[10] as Vector3).distance_to(
					connector.get_meta("lower_door_position", Vector3.INF) as Vector3
				) <= 0.01,
				"%s 楼梯上下接口没有与房门零误差对齐" % connector.name,
				failures
			)
		_expect(is_equal_approx(float(connector.get_meta("passage_width", 0.0)), 6.0), "%s 通行宽度不是6m" % connector.name, failures)
		_expect(is_equal_approx(float(connector.get_meta("approach_outset", 0.0)), 6.0), "%s 门厅不是6m" % connector.name, failures)
		_expect(is_equal_approx(float(connector.get_meta("lane_spacing", 0.0)), 8.0), "%s 折返走道不是8m" % connector.name, failures)
		_expect(
			int(connector.get_meta("enclosure_collision_count", 0)) == 4,
			"%s 没有为四面可视围护墙生成同形碰撞" % connector.name,
			failures
		)
		_expect(
			int(connector.get_meta("walkable_collision_count", 0)) >= 6,
			"%s 没有为六块Blender Walkable楼板生成碰撞" % connector.name,
			failures
		)
		_expect(
			_count_named_nodes(connector, "Stair_") >= 4
			and int(connector.get_meta("walkable_collision_count", 0)) >= 6,
			"%s 导入外壳或Walkable楼板碰撞缺失" % connector.name,
			failures
		)
		_expect(
			bool(connector.get_meta("uses_blender_stairwell_visual", false)),
			"%s 仍在使用程序盒体楼梯，而非Blender模型" % connector.name,
			failures
		)
		_expect(
			_count_named_nodes(connector, "ImportedStairwell") == 1,
			"%s 没有且仅有一套Blender楼梯视觉" % connector.name,
			failures
		)
		_expect(
			_count_named_nodes(connector, "StairTread_") == 0,
			"%s 仍残留程序生成踏步视觉" % connector.name,
			failures
		)
		if str(connector.get_meta("from_room_id", "")) == "start":
			first_stair = connector
	_expect(first_stair != null, "楼顶特殊楼梯间缺失", failures)
	if first_stair != null:
		_expect(
			str(first_stair.get_meta("stair_asset_id", ""))
			== "ENV-TOWER-STAIRWELL-ROOFTOP-9M",
			"楼顶没有使用Blender特殊楼梯资产",
			failures
		)
		_expect(
			int(first_stair.get_meta("stair_approach_lower_module_count", 0)) == 3,
			"楼顶到99层基地入口缺少15m模块化走廊",
			failures
		)

	# 楼顶→99层是免费交通门：仍阻挡通行与视线，但不消耗钥匙、不触发命运。
	var rooftop := (tower.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	var closed_roof_door := false
	for door_snapshot in rooftop.get_room_snapshot().get("door_snapshots", []):
		closed_roof_door = closed_roof_door or (
			not bool(door_snapshot.get("is_open", true))
			and bool(door_snapshot.get("blocks_passage", false))
			and not bool(door_snapshot.get("requires_key", true))
			and not bool(door_snapshot.get("triggers_fate", true))
		)
	_expect(closed_roof_door, "楼顶关闭门没有阻挡通行/视线", failures)
	var keys_before_rooftop := int(tower.call("_get_total_room_keys"))
	_expect(tower.try_open_room_door("facility"), "楼顶门无法触发开启流程", failures)
	await get_tree().process_frame
	_expect(not bool(tower.get("_door_fate_active")), "楼顶→99层错误触发命运卡", failures)
	_expect(
		int(tower.call("_get_total_room_keys")) == keys_before_rooftop,
		"楼顶→99层错误消耗钥匙",
		failures
	)
	await get_tree().physics_frame
	if first_stair != null:
		_validate_stair_wall_collisions(first_stair, failures)
		_expect(
			_count_enabled_named_collisions(
				first_stair,
				"EnclosureWall_Inner"
			) == 1,
			"Blender楼梯内侧围护墙没有启用同形碰撞，仍可穿透",
			failures
		)
		var stair_points: Array = first_stair.get_meta("path_points", [])
		tower.player.global_position = (stair_points[3] as Vector3).lerp(stair_points[4] as Vector3, 0.5) + Vector3.UP * 0.05
		await get_tree().physics_frame
		await get_tree().process_frame
		var midpoint_snapshot := tower.get_tower_snapshot()
		var midpoint_stages: Array = midpoint_snapshot.get("floor_stages", [])
		_expect(
			bool(_stage_snapshot(midpoint_stages, 0).get("floor_visible", false)),
			"楼梯中段错误隐藏了上层楼板",
			failures
		)
		_expect(
			bool(_stage_snapshot(midpoint_stages, 1).get("floor_visible", false)),
			"楼梯中段错误隐藏了下层落脚楼板",
			failures
		)
		tower.player.global_position = (stair_points[0] as Vector3) + Vector3.UP * 0.05
		var reached_facility_gate := true
		for point_index in range(1, stair_points.size()):
			if not await _walk_player_to(tower.player, stair_points[point_index] as Vector3):
				reached_facility_gate = (
					point_index >= stair_points.size() - 2
					and tower.player.global_position.distance_to(
						first_stair.get_meta("lower_door_position", Vector3.INF) as Vector3
					) <= 1.0
				)
				break
		_expect(reached_facility_gate, "角色不能走到楼顶楼梯的99层下端门前", failures)
		_expect(
			str(tower.get("_current_room_id")) == "start",
			"99层下端门未开启前错误提前进入基地层",
			failures
		)
		_expect(
			tower.try_open_stair_arrival_for_test(),
			"99层下端门无法在楼梯行动路线末端开启",
			failures
		)
		await get_tree().process_frame
		await get_tree().physics_frame
		var descended := await _walk_player_to(
			tower.player,
			(stair_points[stair_points.size() - 1] as Vector3)
				+ Vector3.UP * 0.05
		)
		_expect(descended, "99层下端门开启后角色仍不能通过", failures)
		_expect(
			absf(tower.player.global_position.y + 9.0) <= 0.65,
			"角色走到底后没有落在99层高度",
			failures
		)
		var ascended := true
		for point_index in range(stair_points.size() - 2, -1, -1):
			if not await _walk_player_to(tower.player, stair_points[point_index] as Vector3):
				ascended = false
				break
		_expect(ascended, "角色不能从99层完整回爬楼顶U形楼梯", failures)
		_expect(
			absf(tower.player.global_position.y) <= 0.65,
			"角色回爬后没有回到楼顶高度",
			failures
		)

	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	tower.player.global_position = facility.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("facility")
	await get_tree().process_frame
	_expect(not tower.player.combat_enabled, "99层基地仍允许战斗", failures)
	var active_base_snapshot := facility.get_room_snapshot()
	_expect(
		int(active_base_snapshot.get("active_shadow_light_count", 0)) == 1,
		"99层基地成为当前房间后，嵌套四灯组的投影主灯没有随流送激活",
		failures
	)

	# 99层→98层同样免费且无命运；98入口→枢纽免费但必须弹一次命运。
	var closed_base_door := false
	for door_snapshot in facility.get_room_snapshot().get("door_snapshots", []):
		if str((door_snapshot as Dictionary).get("target_room_id", "")) != "floor_01_entry":
			continue
		closed_base_door = (
			not bool((door_snapshot as Dictionary).get("is_open", true))
			and bool((door_snapshot as Dictionary).get("blocks_passage", false))
			and not bool((door_snapshot as Dictionary).get("requires_key", true))
			and not bool((door_snapshot as Dictionary).get("triggers_fate", true))
		)
	_expect(closed_base_door, "99层→98层交通门缺失或没有阻挡通行", failures)
	var keys_before_base_door := int(tower.call("_get_total_room_keys"))
	_expect(tower.try_open_room_door("floor_01_entry"), "99层基地→98层交通门打不开", failures)
	await get_tree().process_frame
	_expect(not bool(tower.get("_door_fate_active")), "99层基地→98层错误触发命运卡", failures)
	_expect(
		int(tower.call("_get_total_room_keys")) == keys_before_base_door,
		"99层基地→98层错误消耗钥匙",
		failures
	)
	var entry98 := (tower.get("_room_by_id") as Dictionary).get("floor_01_entry") as DungeonRoom3D
	var base_to_98_stair := _find_vertical_connector(tower, "facility", "floor_01_entry")
	_expect(base_to_98_stair != null and base_to_98_stair.visible, "交通门开启后99层→98层楼梯没有显示", failures)
	_expect(
		base_to_98_stair != null
		and int(base_to_98_stair.get_meta("stair_approach_upper_module_count", 0)) == 4,
		"99层基地出口到98层楼梯接口缺少20m模块化走廊",
		failures
	)
	_expect(
		entry98.visible
		and int(entry98.get_room_snapshot().get("stream_state", 0)) > 0
		and entry98.get_dimensions().is_equal_approx(Vector2(15.0, 15.0)),
		"交通门开启后98层15m入口大厅没有流送出来",
		failures
	)
	_expect(
		int(entry98.get_room_snapshot().get("furniture_count", -1)) == 0,
		"98层楼梯入口大厅生成了阻挡门厅的家具或搜索物",
		failures
	)
	var closed_98_arrival_door := false
	for door_snapshot in entry98.get_room_snapshot().get("door_snapshots", []):
		if str((door_snapshot as Dictionary).get("target_room_id", "")) != "facility":
			continue
		closed_98_arrival_door = (
			not bool((door_snapshot as Dictionary).get("is_open", true))
			and bool((door_snapshot as Dictionary).get("blocks_passage", false))
		)
	_expect(
		closed_98_arrival_door,
		"打开99层上端门时98层下端门被错误同步打开",
		failures
	)
	if base_to_98_stair != null:
		var lower_door_position := (
			base_to_98_stair.get_meta("lower_door_position", Vector3.INF) as Vector3
		)
		var entry_east_door := entry98.global_position + Vector3(
			entry98.get_dimensions().x * 0.5,
			0.0,
			0.0
		)
		_expect(
			lower_door_position.distance_to(entry_east_door) <= 0.01
			and entry98.global_position.x < lower_door_position.x,
			"98层入口大厅没有刷在东侧楼梯门后的左侧/核心内侧",
			failures
		)
		var base_stair_points: Array = base_to_98_stair.get_meta("path_points", [])
		var reached_98_gate := base_stair_points.size() == 11
		if reached_98_gate:
			tower.player.global_position = (
				(base_stair_points[0] as Vector3) + Vector3.UP * 0.05
			)
			for point_index in range(1, base_stair_points.size()):
				if not await _walk_player_to(
					tower.player,
					base_stair_points[point_index] as Vector3
				):
					reached_98_gate = (
						point_index >= base_stair_points.size() - 2
						and tower.player.global_position.distance_to(
							lower_door_position
						) <= 1.0
					)
					break
		_expect(reached_98_gate, "角色不能沿真实通用楼梯抵达98层入口门前", failures)
		_expect(
			str(tower.get("_current_room_id")) == "facility",
			"98层入口门未开启前错误提前激活战斗层",
			failures
		)
		var interact_event := InputEventAction.new()
		interact_event.action = "interact"
		interact_event.pressed = true
		tower._unhandled_input(interact_event)
		var opened_98_arrival := (
			int(tower.get_tower_snapshot().get(
				"vertical_arrival_open_count",
				0
			)) == 2
		)
		_expect(opened_98_arrival, "98层楼梯间入口门无法开启", failures)
		await get_tree().process_frame
		await get_tree().physics_frame
		var descended_to_98 := opened_98_arrival
		if descended_to_98:
			descended_to_98 = await _walk_player_to(
					tower.player,
					entry98.global_position + Vector3(0.0, 0.05, 0.0)
				)
		_expect(descended_to_98, "角色不能沿真实通用楼梯进入98层入口大厅", failures)
		_expect(
			str(tower.get("_current_room_id")) == "floor_01_entry"
			and absf(tower.player.global_position.y + 18.0) <= 0.65,
			"走下99层楼梯后没有自动激活98层入口关卡",
			failures
		)
		var opened_98_arrival_door := false
		for door_snapshot in entry98.get_room_snapshot().get("door_snapshots", []):
			if str((door_snapshot as Dictionary).get("target_room_id", "")) == "facility":
				opened_98_arrival_door = bool(
					(door_snapshot as Dictionary).get("is_open", false)
				)
		_expect(
			opened_98_arrival_door
			and int(tower.get_tower_snapshot().get(
				"vertical_arrival_open_count",
				0
			)) == 2,
			"楼顶→99层或99层→98层的下端门没有记录为独立开启",
			failures
		)
	tower.player.global_position = entry98.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("floor_01_entry")
	await get_tree().process_frame
	_validate_atomic_floor_generation(tower, 2, failures)
	var entry_light := entry98.get_node_or_null("RoomCeilingLight") as WastelandLight3D
	_expect(
		not tower.player.combat_enabled
		and entry_light != null
		and entry_light.is_light_enabled(),
		"98层楼梯入口大厅没有保持安全区或自动点亮顶灯",
		failures
	)
	_expect(
		_count_named_nodes(entry98, "StairLobbyRouteGuide") == 1
		and _count_named_nodes(entry98, "StairLobbyThresholdGuide") == 2,
		"98层安全厅缺少可读的路线与双门槛地面标识",
		failures
	)
	var keys_before_entry_door := int(tower.call("_get_total_room_keys"))
	_expect(tower.try_open_room_door("floor_01_hub"), "98层入口门打不开", failures)
	await get_tree().process_frame
	_expect(bool(tower.get("_door_fate_active")), "98层入口门没有触发命运卡", failures)
	_expect(
		int(tower.call("_get_total_room_keys")) == keys_before_entry_door,
		"98层入口门错误消耗钥匙",
		failures
	)
	tower.resolve_fate_choice_for_test(0)
	await get_tree().process_frame
	_expect(not bool(tower.get("_door_fate_active")), "98层入口命运卡无法结算", failures)

	# 进入98层中心战斗房，验证坐标、刷怪、楼层隐藏和鼠标瞄准平面。
	var hub98 := (tower.get("_room_by_id") as Dictionary).get("floor_01_hub") as DungeonRoom3D
	tower.player.global_position = hub98.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("floor_01_hub")
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(is_equal_approx(hub98.global_position.y, -18.0), "98层房间坐标不是Y=-18m", failures)
	_expect(tower.player.combat_enabled, "进入98层战斗枢纽后没有恢复战斗输入", failures)
	_expect(_count_room_enemies(tower, "floor_01_hub") > 0, "98层战斗房没有刷怪", failures)
	snapshot = tower.get_tower_snapshot()
	var combat_atmosphere := snapshot.get("atmosphere", {}) as Dictionary
	var combat_sun_color: Color = combat_atmosphere.get("sun_color", Color.BLACK)
	var rooftop_sun_color: Color = rooftop_atmosphere.get("sun_color", Color.WHITE)
	_expect(
		is_equal_approx(
			float(combat_atmosphere.get("sun_energy", -1.0)),
			float(rooftop_atmosphere.get("sun_energy", -2.0))
		)
		and combat_sun_color.is_equal_approx(rooftop_sun_color)
		and is_equal_approx(
			float(combat_atmosphere.get("ambient_energy", -1.0)),
			float(rooftop_atmosphere.get("ambient_energy", -2.0))
		)
		and is_equal_approx(
			float(combat_atmosphere.get("fog_density", -1.0)),
			float(rooftop_atmosphere.get("fog_density", -2.0))
		),
		"进入98层后太阳、环境光或雾参数发生楼层切换",
		failures
	)
	_expect(
		_count_named_nodes(tower, "TowerWindow_") == 0
		and _count_named_nodes(tower, "TowerWindowNaturalLight") == 0,
		"战斗层运行时重新生成了假窗光",
		failures
	)
	_expect(
		int(snapshot.get("rendered_floor_count", 99))
		== int(snapshot.get("loaded_floor_count", 0)),
		"完整渲染层数与流送窗口不一致",
		failures
	)
	for stage in snapshot.get("floor_stages", []):
		var stage_data := stage as Dictionary
		var stage_floor_index := int(stage_data.get("floor_index", -1))
		var stage_loaded: bool = (
			stage_floor_index in (snapshot.get("loaded_floor_indices", []) as Array)
		)
		_expect(
			bool(stage_data.get("floor_visible", false)) == stage_loaded,
			"98层状态下仍按摄像机而不是流送窗口隐藏楼板",
			failures
		)
	tower.player.call("_update_aim_from_mouse")
	var aim_cursor := tower.player.get_node("AimCursor") as Node3D
	_expect(
		absf(aim_cursor.global_position.y - (tower.player.global_position.y + 0.035)) < 0.02,
		"鼠标光标仍停留在最上层平面",
		failures
	)

	# 98层独立墙边电梯只有亲自点亮后才解锁；未访问97层绝不能被选中。
	var elevator98 := (tower.get("_room_by_id") as Dictionary).get("floor_01_elevator") as DungeonRoom3D
	tower.player.global_position = elevator98.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("floor_01_elevator")
	await get_tree().process_frame
	var elevator_facilities := (
		tower.get("_elevator_facilities_by_floor") as Dictionary
	)
	var elevator_station := elevator_facilities.get(98) as BaseFacility3D
	_expect(
		elevator_station != null
		and elevator_station.get_parent() != elevator98
		and str(elevator_station.get_meta("placement", ""))
			== "standalone_wall_edge",
		"98层电梯仍是房间内容，或没有贴墙独立设施",
		failures
	)
	if elevator_station != null:
		tower.call("_on_facility_activated", elevator_station)
		await get_tree().process_frame
	snapshot = tower.get_tower_snapshot()
	_expect(98 in snapshot.get("unlocked_elevator_floors", []), "98层电梯点亮失败", failures)
	_expect(97 not in snapshot.get("unlocked_elevator_floors", []), "电梯错误解锁未访问的97层", failures)
	tower.call("_travel_elevator_to", 99)
	await get_tree().process_frame
	_expect(str(tower.get("_current_room_id")) == "facility", "电梯不能返回99层基地", failures)
	tower.call("_open_elevator_panel")
	tower.call("_travel_elevator_to", 98)
	await get_tree().process_frame
	_expect(str(tower.get("_current_room_id")) == "floor_01_elevator", "电梯不能返回已点亮的98层", failures)

	# 逐层进入出口/入口，最终95层必须生成Boss；整个运行期活动楼层仍不超过5。
	var previous_exit := "floor_01_exit"
	for physical_floor in range(2, 5):
		var entry_id := "floor_%02d_entry" % physical_floor
		tower.force_open_edge_for_test(previous_exit if physical_floor > 2 else "floor_01_exit", entry_id)
		var entry := (tower.get("_room_by_id") as Dictionary).get(entry_id) as DungeonRoom3D
		tower.player.global_position = entry.global_position + Vector3(0, 0.05, 0)
		tower.force_enter_room_for_test(entry_id)
		await get_tree().process_frame
		previous_exit = "floor_%02d_exit" % physical_floor
	var boss_room := (tower.get("_room_by_id") as Dictionary).get("extraction") as DungeonRoom3D
	tower.player.global_position = boss_room.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("extraction")
	await get_tree().process_frame
	await get_tree().physics_frame
	var boss_room_snapshot := boss_room.get_room_snapshot()
	_expect(
		int(boss_room_snapshot.get("controlled_light_count", 0)) == 4
		and bool(boss_room_snapshot.get("room_light_on", false)),
		"95层90m Boss区没有四区基础照明或默认灯光未开启",
		failures
	)
	_expect(_count_room_enemies(tower, "extraction") > 0, "95层Boss房没有刷怪", failures)
	var boss_found := false
	for enemy in get_tree().get_nodes_in_group("enemy_3d"):
		if enemy is Enemy3D and tower.is_ancestor_of(enemy) and (enemy as Enemy3D).room_id == "extraction":
			boss_found = boss_found or (enemy as Enemy3D).enemy_kind == "boss"
	_expect(boss_found, "95层没有Boss单位", failures)
	var loot_before_boss := _count_ground_loot(tower)
	var boss_enemies := (
		(tower.get("_enemy_nodes_by_room") as Dictionary)
			.get("extraction", []) as Array
	).duplicate()
	for enemy_value in boss_enemies:
		var enemy := enemy_value as Enemy3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		tower.call("_on_enemy_killed", enemy, enemy.get_enemy_data())
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var boss_extraction := tower.get("_extraction") as ExtractionBeacon3D
	_expect(
		boss_extraction != null
		and not bool(boss_extraction.get_snapshot().get("locked", true)),
		"95层Boss全灭后撤离信标没有解锁",
		failures
	)
	_expect(
		_count_ground_loot(tower) > loot_before_boss,
		"95层怪物死亡后没有生成掉落物品",
		failures
	)
	if boss_extraction != null:
		boss_extraction.force_complete_for_test()
		await get_tree().process_frame
		_expect(
			bool(tower.get("_completed")),
			"95层信标解锁后不能完成撤离闭环",
			failures
		)
	snapshot = tower.get_tower_snapshot()
	_expect(int(snapshot.get("loaded_floor_count", 99)) <= 5, "抵达95层后流送窗口超过五层", failures)
	_expect(int(snapshot.get("support_floor_count", 0)) == 6, "深层流送错误删除上层承重碰撞", failures)
	_expect(
		snapshot.get("visible_room_floor_indices", []) == [5],
		"抵达95层后仍看得到其他楼层室内",
		failures
	)

	var node_count := _count_nodes(tower)
	_expect(node_count <= 3500, "塔楼Demo超过3500节点预算：%d" % node_count, failures)
	tower.queue_free()
	await get_tree().process_frame

	# 随机布局必须满足“同种子完全可复现、换种子至少有一层变化”。
	var same_seed_tower := scene.instantiate() as TowerDescent3D
	same_seed_tower.test_mode = true
	same_seed_tower.run_seed_override = 990095
	add_child(same_seed_tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(
		_layout_signature(
			same_seed_tower.get_generation_snapshot(),
			same_seed_tower.get_tower_snapshot()
		) == primary_layout_signature,
		"同一塔楼种子没有复现相同房间拓扑",
		failures
	)
	same_seed_tower.queue_free()
	await get_tree().process_frame

	var alternate_seed_tower := scene.instantiate() as TowerDescent3D
	alternate_seed_tower.test_mode = true
	alternate_seed_tower.run_seed_override = 990096
	add_child(alternate_seed_tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(
		_layout_signature(
			alternate_seed_tower.get_generation_snapshot(),
			alternate_seed_tower.get_tower_snapshot()
		) != primary_layout_signature,
		"更换塔楼种子后四层房间拓扑与内容仍完全相同",
		failures
	)
	alternate_seed_tower.queue_free()
	await get_tree().process_frame
	_finish(failures, node_count)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _validate_door_contract(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var probes: Array[RoomDoor3D] = []
	for direction in ["north", "south", "west", "east"]:
		var door := RoomDoor3D.new()
		door.configure(direction, "door_contract_target", Color(0.2, 0.9, 1.0))
		door.position = Vector3(300.0 + probes.size() * 4.0, 30.0, 300.0)
		tower.add_child(door)
		probes.append(door)
		door.set_open(true, true)
	await get_tree().physics_frame
	for door in probes:
		var door_snapshot := door.get_snapshot()
		_expect(
			is_equal_approx(float(door_snapshot.get("clear_width_m", 0.0)), 2.2)
			and is_equal_approx(
				float(door_snapshot.get("clear_height_m", 0.0)),
				2.5
			)
			and not bool(door_snapshot.get("blocks_passage", true)),
			"%s门不是2.2×2.5m，或开启后仍有碰撞" % door.direction,
			failures
		)
		door.queue_free()
	await get_tree().process_frame


func _validate_floor_search_and_loot(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var room_by_id := tower.get("_room_by_id") as Dictionary
	for floor_index in range(1, 5):
		var room_id := "floor_%02d_elevator" % floor_index
		var search_room := room_by_id.get(room_id) as DungeonRoom3D
		_expect(search_room != null, "%s搜索/电梯接入房不存在" % room_id, failures)
		if search_room == null:
			continue
		search_room.ensure_detail_built()
		await get_tree().process_frame
		var searchable_count := 0
		for node in get_tree().get_nodes_in_group("searchable_prop_3d"):
			if search_room.is_ancestor_of(node):
				searchable_count += 1
		_expect(
			searchable_count >= 1,
			"%d层没有随机可搜索容器" % (99 - floor_index),
			failures
		)
	var floor98_room := room_by_id.get("floor_01_elevator") as DungeonRoom3D
	if floor98_room == null:
		return
	var loot_before := _count_ground_loot(tower)
	tower.call("_on_prop_searched", floor98_room, {
		"size_class": "medium",
		"prop_id": "ph49_acceptance_container",
	})
	await get_tree().process_frame
	_expect(
		_count_ground_loot(tower) > loot_before,
		"98层搜索容器没有生成落地物品",
		failures
	)


func _validate_combat_floor_layouts(
	generation: Dictionary,
	snapshot: Dictionary,
	failures: Array[String]
) -> void:
	var records: Array = generation.get("records", [])
	var all_records_by_id: Dictionary = {}
	for record_value in records:
		var source_record := record_value as Dictionary
		all_records_by_id[str(source_record.get("id", ""))] = source_record
	var floor_templates := snapshot.get("floor_layout_templates", {}) as Dictionary
	_expect(floor_templates.size() == 4, "四个战斗层没有各自记录布局模板", failures)
	for physical_floor in range(2, 6):
		var floor_y := -9.0 * float(physical_floor)
		var floor_records: Array[Dictionary] = []
		for record_value in records:
			var record := record_value as Dictionary
			var position := record.get("position", Vector3.ZERO) as Vector3
			if is_equal_approx(position.y, floor_y):
				floor_records.append(record)
		_expect(
			floor_records.size() == (10 if physical_floor == 5 else 12),
			"第%d物理层房间数量不符合十二房环/Boss十房结构" % physical_floor,
			failures
		)
		var occupied: Dictionary = {}
		var record_by_id: Dictionary = {}
		for record in floor_records:
			var position := record.get("position", Vector3.ZERO) as Vector3
			var dimensions := record.get("custom_dimensions", Vector2.ZERO) as Vector2
			var grid_key := "%.1f,%.1f" % [position.x, position.z]
			occupied[grid_key] = true
			record_by_id[str(record.get("id", ""))] = record
			_expect(
				absf(position.x) + dimensions.x * 0.5 <= 125.01
				and absf(position.z) + dimensions.y * 0.5 <= 125.01,
				"第%d物理层房间超出250m整层" % physical_floor,
				failures
			)
			if str(record.get("id", "")) == "extraction":
				_expect(
					dimensions.is_equal_approx(Vector2(90.0, 90.0)),
					"95层Boss净战斗区不是90×90m",
					failures
				)
			elif str(record.get("tower_role", "")) in [
				"stair_entry",
				"stair_exit",
			]:
				_expect(
					dimensions.is_equal_approx(Vector2(15.0, 15.0)),
					"第%d物理层楼梯入口/出口大厅不是15×15m" % physical_floor,
					failures
				)
			else:
				_expect(
					dimensions.is_equal_approx(Vector2(30.0, 25.0)),
					"第%d物理层存在不是30×25m的6×5基础房间" % physical_floor,
					failures
				)
		_expect(
			occupied.size() == floor_records.size(),
			"第%d物理层存在房间重叠" % physical_floor,
			failures
		)
		for first_index in range(floor_records.size()):
			var first_record := floor_records[first_index] as Dictionary
			var first_rect := _record_rect(first_record)
			for second_index in range(first_index + 1, floor_records.size()):
				var second_record := floor_records[second_index] as Dictionary
				_expect(
					first_rect.intersection(_record_rect(second_record)).get_area()
						<= 0.01,
					"第%d物理层的%s与%s实际占地重叠" % [
						physical_floor,
						str(first_record.get("id", "")),
						str(second_record.get("id", "")),
					],
					failures
				)
		var floor_types: Array[String] = []
		var elevator_access_count := 0
		for record in floor_records:
			floor_types.append(str(record.get("type", "")))
			if str(record.get("tower_role", "")) == "elevator_access":
				elevator_access_count += 1
			var room_id := str(record.get("id", ""))
			var doors := record.get("doors", []) as Array
			var targets := record.get("door_targets", {}) as Dictionary
			_expect(
				doors.size() == targets.size(),
				"%s存在没有目标引用的门" % room_id,
				failures
			)
			for direction_value in targets.keys():
				var direction := str(direction_value)
				var target_id := str(targets[direction_value])
				var target_record := (
					all_records_by_id.get(target_id, {}) as Dictionary
				)
				var target_targets := (
					target_record.get("door_targets", {}) as Dictionary
				)
				_expect(
					direction in ["north", "south", "west", "east"]
					and not target_record.is_empty()
					and room_id in target_targets.values(),
					"%s的%s门没有有效双向目标" % [room_id, direction],
					failures
				)
		_expect(
			elevator_access_count == 1
			and "ELEVATOR" not in floor_types,
			"第%d物理层仍把电梯做成房型，或缺少独立电梯接入房"
				% physical_floor,
			failures
		)
		_expect(
			(
				"COMBAT" in floor_types
				or "ELITE" in floor_types
				or "BOSS" in floor_types
			)
			and (
				"STORAGE" in floor_types
				or "SCAVENGE" in floor_types
			),
			"第%d物理层缺少战斗或搜索内容" % physical_floor,
			failures
		)
		for record in floor_records:
			var parent_id := str(record.get("parent", ""))
			if not record_by_id.has(parent_id):
				continue
			var position := record.get("position", Vector3.ZERO) as Vector3
			var parent_position := (
				(record_by_id[parent_id] as Dictionary).get("position", Vector3.ZERO)
				as Vector3
			)
			var dimensions := record.get("custom_dimensions", Vector2.ZERO) as Vector2
			var parent_dimensions := (
				(record_by_id[parent_id] as Dictionary).get("custom_dimensions", Vector2.ZERO)
				as Vector2
			)
			var delta_x := absf(position.x - parent_position.x)
			var delta_z := absf(position.z - parent_position.z)
			var horizontal_x := delta_x >= delta_z
			var tangent_error := delta_z if horizontal_x else delta_x
			var corridor_gap := -1.0
			if not horizontal_x:
				corridor_gap = (
					delta_z
					- dimensions.y * 0.5
					- parent_dimensions.y * 0.5
				)
			else:
				corridor_gap = (
					delta_x
					- dimensions.x * 0.5
					- parent_dimensions.x * 0.5
				)
			_expect(
				tangent_error <= 2.51
				and corridor_gap >= 4.99
				and corridor_gap <= 40.01,
				"第%d物理层相邻组件没有留下5—40m门轴对齐走廊" % physical_floor,
				failures
			)
		if physical_floor < 5:
			var entry_id := "floor_%02d_entry" % (physical_floor - 1)
			var exit_id := "floor_%02d_exit" % (physical_floor - 1)
			var entry_position := (
				(record_by_id.get(entry_id, {}) as Dictionary).get("position", Vector3.ZERO)
				as Vector3
			)
			var exit_position := (
				(record_by_id.get(exit_id, {}) as Dictionary).get("position", Vector3.ZERO)
				as Vector3
			)
			_expect(
				(
					Vector2(entry_position.x, entry_position.z)
					+ Vector2(exit_position.x, exit_position.z)
				).is_equal_approx(TowerGeometry3D.CORE_CENTER_XZ * 2.0)
				and is_equal_approx(entry_position.z, exit_position.z),
				"第%d物理层上下楼大厅没有围绕核心中心对齐" % physical_floor,
				failures
			)
			var entry_record := record_by_id.get(entry_id, {}) as Dictionary
			var exit_record := record_by_id.get(exit_id, {}) as Dictionary
			_expect(
				(entry_record.get("custom_dimensions", Vector2.ZERO) as Vector2)
					.is_equal_approx(Vector2(15.0, 15.0))
				and (exit_record.get("custom_dimensions", Vector2.ZERO) as Vector2)
					.is_equal_approx(Vector2(15.0, 15.0)),
				"第%d物理层上下楼大厅没有使用15m固定模板" % physical_floor,
				failures
			)
			var hub_id := "floor_%02d_hub" % (physical_floor - 1)
			var hub_position := (
				(record_by_id.get(hub_id, {}) as Dictionary).get(
					"position",
					Vector3.ZERO
				) as Vector3
			)
			_expect(
				is_equal_approx(absf(hub_position.z - entry_position.z), 45.0)
				and absf(hub_position.x - entry_position.x) <= 2.51,
				"第%d物理层入口大厅到战斗枢纽没有以25m直走廊避开楼梯占位" % physical_floor,
				failures
			)


func _validate_atomic_floor_generation(
	tower: TowerDescent3D,
	floor_index: int,
	failures: Array[String]
) -> void:
	var snapshot := tower.get_tower_snapshot()
	_expect(
		floor_index in (snapshot.get("generated_floor_indices", []) as Array),
		"第%d物理层首次进入后没有登记为整层生成" % floor_index,
		failures
	)
	var floor_room_ids: Array = []
	for floor_value in snapshot.get("combat_floors", []):
		var floor_data := floor_value as Dictionary
		if is_equal_approx(
			float(floor_data.get("height", INF)),
			-9.0 * float(floor_index)
		):
			floor_room_ids = floor_data.get("room_ids", []) as Array
			break
	var hidden_streamed_room_count := 0
	for room_id_value in floor_room_ids:
		var room := (
			(tower.get("_room_by_id") as Dictionary).get(str(room_id_value))
			as DungeonRoom3D
		)
		if room == null:
			failures.append("整层生成清单引用了不存在的房间：%s" % room_id_value)
			continue
		_expect(
			bool(room.get_meta("floor_plan_generated", false))
			and (room.get_meta("floor_plan_position", Vector3.INF) as Vector3)
				.is_equal_approx(room.position)
			and (room.get_meta("floor_plan_dimensions", Vector2.ZERO) as Vector2)
				.is_equal_approx(room.get_dimensions()),
			"第%d物理层的%s没有在楼层触发时冻结组件坐标" % [
				floor_index,
				str(room_id_value),
			],
			failures
		)
		var room_snapshot := room.get_room_snapshot()
		if int(room_snapshot.get("stream_state", 0)) == 0 and not room.visible:
			hidden_streamed_room_count += 1
	_expect(
		hidden_streamed_room_count > 0,
		"整层布局事务错误地同时激活了所有房间表现/碰撞",
		failures
	)
	var room_floor_index := tower.get("_room_floor_index") as Dictionary
	for edge_value in (tower.get("_corridor_by_edge") as Dictionary).keys():
		var connector := (
			(tower.get("_corridor_by_edge") as Dictionary).get(edge_value)
			as Node3D
		)
		if connector == null:
			continue
		var from_floor := int(room_floor_index.get(
			str(connector.get_meta("from_room_id", "")), -1
		))
		var to_floor := int(room_floor_index.get(
			str(connector.get_meta("to_room_id", "")), -1
		))
		if floor_index not in [from_floor, to_floor]:
			continue
		_expect(
			bool(connector.get_meta("floor_plan_generated_%d" % floor_index, false)),
			"第%d物理层的房间连接或楼梯间没有纳入同一生成事务" % floor_index,
			failures
		)


func _validate_stair_room_clearance(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var room_floor_index := tower.get("_room_floor_index") as Dictionary
	var rooms := tower.get("_rooms") as Array
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or not bool(
			connector.get_meta("is_vertical_connector", false)
		):
			continue
		var imported: Node3D = null
		for child_value in connector.get_children():
			var child := child_value as Node3D
			if child != null and child.name.begins_with("ImportedStairwell"):
				imported = child
				break
		if imported == null:
			failures.append("%s缺少可用于占位验收的导入楼梯Mesh" % connector.name)
			continue
		var stair_rect := Rect2()
		var has_rect := false
		for mesh_value in imported.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_value as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var world_aabb := mesh.global_transform * mesh.get_aabb()
			var mesh_rect := Rect2(
				Vector2(world_aabb.position.x, world_aabb.position.z),
				Vector2(world_aabb.size.x, world_aabb.size.z)
			)
			stair_rect = mesh_rect if not has_rect else stair_rect.merge(mesh_rect)
			has_rect = true
		if not has_rect:
			failures.append("%s导入楼梯没有有效Mesh占地" % connector.name)
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var to_id := str(connector.get_meta("to_room_id", ""))
		var endpoint_floors := [
			int(room_floor_index.get(from_id, -1)),
			int(room_floor_index.get(to_id, -1)),
		]
		for room_value in rooms:
			var room := room_value as DungeonRoom3D
			if (
				room == null
				or room.room_id in [from_id, to_id]
				or int(room_floor_index.get(room.room_id, -2)) not in endpoint_floors
			):
				continue
			var room_rect := Rect2(
				Vector2(room.position.x, room.position.z) - room.get_dimensions() * 0.5,
				room.get_dimensions()
			)
			_expect(
				stair_rect.intersection(room_rect).get_area() <= 0.01,
				"%s真实Mesh占地与%s房间重叠" % [connector.name, room.room_id],
				failures
			)


func _record_rect(record: Dictionary) -> Rect2:
	var position := record.get("position", Vector3.ZERO) as Vector3
	var dimensions := record.get("custom_dimensions", Vector2.ZERO) as Vector2
	return Rect2(
		Vector2(position.x, position.z) - dimensions * 0.5,
		dimensions
	)


func _layout_signature(generation: Dictionary, snapshot: Dictionary) -> String:
	var parts: Array[String] = []
	for record_value in generation.get("records", []):
		var record := record_value as Dictionary
		var id := str(record.get("id", ""))
		if not id.begins_with("floor_") and id != "extraction":
			continue
		var position := record.get("position", Vector3.ZERO) as Vector3
		parts.append("%s:%s:%s:%d,%d,%d" % [
			id,
			str(record.get("type", "")),
			str(record.get("parent", "")),
			roundi(position.x),
			roundi(position.y),
			roundi(position.z),
		])
	var template_parts: Array[String] = []
	var templates := snapshot.get("floor_layout_templates", {}) as Dictionary
	var floor_indices: Array = templates.keys()
	floor_indices.sort()
	for floor_index in floor_indices:
		template_parts.append("%d=%s" % [int(floor_index), str(templates[floor_index])])
	return "%s|templates:%s" % [";".join(parts), ",".join(template_parts)]


func _stage_snapshot(stages: Array, floor_index: int) -> Dictionary:
	for stage in stages:
		if int((stage as Dictionary).get("floor_index", -1)) == floor_index:
			return stage as Dictionary
	return {}


func _find_elevator_station(root: Node) -> ServiceStation3D:
	if root is ServiceStation3D and (root as ServiceStation3D).station_type == "elevator":
		return root as ServiceStation3D
	for child in root.get_children():
		var found := _find_elevator_station(child)
		if found != null:
			return found
	return null


func _find_vertical_connector(
	tower: TowerDescent3D,
	a: String,
	b: String
) -> Node3D:
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or not bool(
			connector.get_meta("is_vertical_connector", false)
		):
			continue
		var ids := [
			str(connector.get_meta("from_room_id", "")),
			str(connector.get_meta("to_room_id", "")),
		]
		if a in ids and b in ids:
			return connector
	return null


func _validate_stair_wall_collisions(
	connector: Node3D,
	failures: Array[String]
) -> void:
	var wall_count := 0
	var enabled_collision_count := 0
	for child_value in connector.find_children("*", "StaticBody3D", true, false):
		var body := child_value as StaticBody3D
		if body == null or not bool(body.get_meta("stair_enclosure_collision", false)):
			continue
		wall_count += 1
		var collision := body.get_child(0) as CollisionShape3D
		var visual := body.get_parent() as MeshInstance3D
		if (
			collision != null
			and not collision.disabled
			and collision.shape is ConcavePolygonShape3D
			and visual != null
			and visual.mesh != null
		):
			enabled_collision_count += 1
	_expect(
		wall_count == 4 and enabled_collision_count == 4,
		"楼梯间四面可视围护墙没有全部启用同形实体碰撞",
		failures
	)


func _count_enabled_named_collisions(root: Node, name_part: String) -> int:
	var count := 0
	if (
		root is CollisionShape3D
		and name_part in str(root.name)
		and not (root as CollisionShape3D).disabled
	):
		count += 1
	for child in root.get_children():
		count += _count_enabled_named_collisions(child, name_part)
	return count


func _count_room_enemies(tower: Node, room_id: String) -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemy_3d"):
		if enemy is Enemy3D and tower.is_ancestor_of(enemy) and (enemy as Enemy3D).room_id == room_id:
			count += 1
	return count


func _count_ground_loot(tower: Node) -> int:
	var count := 0
	for pickup in get_tree().get_nodes_in_group("ground_loot_3d"):
		if pickup is GroundLootPickup3D and tower.is_ancestor_of(pickup):
			count += 1
	return count


func _validate_camera_lower_wall_lift(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var blocker := StaticBody3D.new()
	blocker.name = "TowerWallCollision_CameraLowerTest"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	blocker.set_meta("camera_lower_wall", true)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 9.0, 0.4)
	collision.shape = shape
	blocker.add_child(collision)
	var blocker_visual := MeshInstance3D.new()
	blocker_visual.name = "CameraCutawayTestVisual"
	var blocker_mesh := BoxMesh.new()
	blocker_mesh.size = shape.size
	blocker_visual.mesh = blocker_mesh
	blocker.add_child(blocker_visual)
	tower.add_child(blocker)
	blocker.global_position = tower.player.global_position + Vector3(0.0, 4.5, 2.0)
	var expected_yaw := tower.player.camera.rotation.y
	var expected_roll := tower.player.camera.rotation.z
	tower.player.camera.position = Vector3(2.0, 6.0, 3.0)
	tower.player.camera.rotation += Vector3(0.0, 0.45, 0.18)
	var lift_samples: Array[float] = []
	var trailing_samples: Array[float] = []
	for _frame in range(30):
		await get_tree().physics_frame
		lift_samples.append(tower.player.camera.position.y)
		trailing_samples.append(tower.player.camera.position.z)
	var blocked_snapshot := tower.get_tower_snapshot()
	var blocked_planar_offset := (
		blocked_snapshot.get("camera_planar_offset", Vector3.ZERO) as Vector3
	)
	var detected_distance := float(
		blocked_snapshot.get("camera_lower_wall_distance_m", -1.0)
	)
	_expect(
		is_equal_approx(blocked_planar_offset.x, 0.0)
		and is_equal_approx(blocked_planar_offset.y, 0.0)
		and is_equal_approx(tower.player.camera.position.x, 0.0)
		and tower.player.camera.position.z >= 0.149
		and tower.player.camera.position.z < detected_distance - 0.35
		and tower.player.camera.position.y > 8.18
		and tower.player.camera.position.y <= 8.301,
		"下方墙没有把镜头平滑抬升并收回墙内侧，或错误改变了固定X",
		failures
	)
	_expect(
		is_equal_approx(tower.player.camera.rotation.y, expected_yaw)
		and is_equal_approx(tower.player.camera.rotation.z, expected_roll)
		and is_equal_approx(tower.player.camera.fov, 65.0),
		"下方墙抬升导致镜头左右旋转、侧倾或FOV变化",
		failures
	)
	_expect(
		bool(blocked_snapshot.get("camera_collision_enabled", false))
		and bool(blocked_snapshot.get("camera_collision_adjusted", false))
		and bool(blocked_snapshot.get("camera_horizontal_pose_fixed", false))
		and bool(blocked_snapshot.get("camera_yaw_locked", false))
		and bool(blocked_snapshot.get("camera_lower_wall_detected", false))
		and str(blocked_snapshot.get("camera_collision_mode", ""))
			== "lower_wall_lift_and_retract_arc",
		"镜头没有启用仅下方墙抬升收拢契约",
		failures
	)
	var lift_is_smooth := lift_samples.size() >= 6
	for index in range(1, lift_samples.size()):
		var step := lift_samples[index] - lift_samples[index - 1]
		if step < -0.001 or step > 0.18:
			lift_is_smooth = false
			break
	_expect(
		lift_is_smooth
		and lift_samples[lift_samples.size() - 1] - lift_samples[0] > 0.16,
		"下方墙镜头抬升不是连续平滑过程",
		failures
	)
	var retract_is_smooth := trailing_samples.size() >= 6
	for index in range(1, trailing_samples.size()):
		var step := trailing_samples[index] - trailing_samples[index - 1]
		if step > 0.001 or step < -0.90:
			retract_is_smooth = false
			break
	_expect(
		retract_is_smooth
		and trailing_samples[0] - trailing_samples[trailing_samples.size() - 1] > 2.4,
		"下方墙镜头收拢不是连续平滑过程",
		failures
	)
	_expect(
		not bool(blocked_snapshot.get("camera_occluded_player", true))
		and int(blocked_snapshot.get("camera_occlusion_blocked_ray_count", 0)) < 2
		and int(blocked_snapshot.get("camera_silhouette_mesh_count", 0)) >= 1
		and int(blocked_snapshot.get("camera_hidden_wall_count", -1)) == 0
		and blocker_visual.visible
		and not collision.disabled,
		"镜头收回墙内侧后角色仍被遮挡，或墙体视觉/碰撞被错误关闭",
		failures
	)
	blocker.queue_free()
	for _frame in range(75):
		await get_tree().physics_frame
	var recovered_snapshot := tower.get_tower_snapshot()
	_expect(
		not bool(recovered_snapshot.get("camera_occluded_player", true))
		and not bool(recovered_snapshot.get("camera_lower_wall_detected", true))
		and not bool(recovered_snapshot.get("camera_collision_adjusted", true))
		and absf(tower.player.camera.position.y - 8.0) <= 0.02
		and absf(tower.player.camera.position.z - 2.77) <= 0.03,
		"下方墙移除后镜头或角色轮廓没有平滑恢复",
		failures
	)
	var side_blocker := StaticBody3D.new()
	side_blocker.name = "TowerWallCollision_CameraSideTest"
	side_blocker.collision_layer = 1
	side_blocker.collision_mask = 0
	var side_collision := CollisionShape3D.new()
	var side_shape := BoxShape3D.new()
	side_shape.size = Vector3(0.4, 9.0, 4.0)
	side_collision.shape = side_shape
	side_blocker.add_child(side_collision)
	tower.add_child(side_blocker)
	side_blocker.global_position = (
		tower.player.global_position + Vector3(2.4, 4.5, 0.0)
	)
	for _frame in range(30):
		await get_tree().physics_frame
	var side_snapshot := tower.get_tower_snapshot()
	_expect(
		not bool(side_snapshot.get("camera_lower_wall_detected", true))
		and not bool(side_snapshot.get("camera_collision_adjusted", true))
		and absf(tower.player.camera.position.y - 8.0) <= 0.02
		and absf(tower.player.camera.position.z - 2.77) <= 0.03,
		"左右墙错误触发了下方墙镜头抬升",
		failures
	)
	side_blocker.queue_free()
	await get_tree().physics_frame
	var rooftop_door := _find_room_door(tower, "facility")
	_expect(rooftop_door != null, "楼顶到99层的门洞不存在", failures)
	if rooftop_door != null:
		tower.player.global_position = (
			rooftop_door.global_position + Vector3(0.45, 0.05, 0.0)
		)
		for _frame in range(75):
			await get_tree().physics_frame
		var door_snapshot := tower.get_tower_snapshot()
		_expect(
			not bool(door_snapshot.get("camera_door_bypass_active", true))
			and not bool(door_snapshot.get("camera_lower_wall_detected", true))
			and int(door_snapshot.get("camera_near_faded_mesh_count", -1)) == 0
			and absf(tower.player.camera.position.y - 8.0) <= 0.01
			and absf(tower.player.camera.position.z - 2.77) <= 0.03
			and absf(tower.player.camera.position.x) <= 0.001,
			"关闭门错误启用了门槛旁路，或改变了固定镜头",
			failures
		)


func _validate_manual_flashlight(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var flashlight := tower.player.get_node_or_null(
		"PlayerFlashlight3D"
	) as PlayerFlashlight3D
	_expect(flashlight != null, "玩家缺少手动探照灯节点", failures)
	if flashlight == null:
		return
	_expect(not flashlight.is_light_enabled(), "塔楼探照灯没有以关闭状态开始", failures)
	flashlight.set_light_enabled(true)
	tower.force_enter_room_for_test("facility")
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(
		flashlight.is_light_enabled(),
		"进入基地时自动覆盖了玩家选择的探照灯状态",
		failures
	)
	tower.force_enter_room_for_test("start")
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(
		flashlight.is_light_enabled(),
		"返回楼顶时自动关闭了玩家选择的探照灯",
		failures
	)
	flashlight.set_light_enabled(false)


func _find_room_door(root: Node, target_room_id: String) -> RoomDoor3D:
	if root is RoomDoor3D and (root as RoomDoor3D).target_room_id == target_room_id:
		return root as RoomDoor3D
	for child in root.get_children():
		var found := _find_room_door(child, target_room_id)
		if found != null:
			return found
	return null


func _count_named_nodes(root: Node, prefix: String) -> int:
	var count := 1 if root.name.begins_with(prefix) else 0
	for child in root.get_children():
		count += _count_named_nodes(child, prefix)
	return count


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _walk_player_to(player: Player3D, target: Vector3) -> bool:
	var stalled_frames := 0
	var previous_distance := INF
	for _frame in range(420):
		var offset := target - player.global_position
		var planar := Vector3(offset.x, 0.0, offset.z)
		# 路径点位于平台接缝中心线；0.55m包含0.43m角色半宽与接缝安全余量。
		if planar.length() <= 0.55 and absf(offset.y) <= 0.72:
			player.set_test_move_direction(Vector3.ZERO)
			await get_tree().physics_frame
			return true
		player.set_test_move_direction(planar.normalized())
		await get_tree().physics_frame
		var distance := planar.length()
		if distance < previous_distance - 0.008:
			stalled_frames = 0
		else:
			stalled_frames += 1
		previous_distance = distance
		if stalled_frames >= 90:
			print("TOWER_STAIR_STALL current=%s target=%s offset=%s" % [player.global_position, target, offset])
			for collision_index in range(player.get_slide_collision_count()):
				var collision := player.get_slide_collision(collision_index)
				var collider := collision.get_collider() as Node
				print(
					"TOWER_STAIR_STALL_COLLIDER name=%s path=%s normal=%s position=%s"
					% [
						str(collider.name) if collider != null else "<null>",
						str(collider.get_path()) if collider != null else "<null>",
						str(collision.get_normal()),
						str(collision.get_position()),
					]
				)
			player.set_test_move_direction(Vector3.ZERO)
			return false
	player.set_test_move_direction(Vector3.ZERO)
	print("TOWER_STAIR_TIMEOUT current=%s target=%s" % [player.global_position, target])
	return false


func _finish(failures: Array[String], node_count: int) -> void:
	if failures.is_empty():
		print("TOWER_DESCENT_FLOW_OK: v0.1基地、98—95搜打撤、独立电梯、全局光照、窄门、墙体与全息小地图通过（nodes=%d）" % node_count)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
