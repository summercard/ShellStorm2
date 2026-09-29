extends Node


func _ready() -> void:
	var failures: Array[String] = []
	BaseManager.save_path = "user://verify_base99_telescopic_ladder_%d.json" % Time.get_ticks_usec()
	BaseManager.data = BaseData.new()
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var player := tower.player as Player3D
	var ladder := get_tree().get_first_node_in_group("interaction_provider_3d") as Base99TelescopicLadder3D
	if ladder == null:
		for node in get_tree().get_nodes_in_group("interaction_provider_3d"):
			if node is Base99TelescopicLadder3D:
				ladder = node
				break
	_expect(player != null and ladder != null, "玩家或直梯未生成", failures)
	if player != null and ladder != null:
		var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
		var anchor := facility.to_local(ladder.global_position)
		_expect(anchor.distance_to(Vector3(14.5, 6.0, -7.5)) < 0.02, "直梯没有贴到东墙门洞下方: %s" % anchor, failures)
		_expect(ladder.global_basis.z.normalized().dot(Vector3.LEFT) > 0.99, "踏棍正面没有朝向阁楼室内", failures)
		_expect(facility.to_local(ladder.get_exit_position(false)).distance_to(Vector3(13.05, 6.1, -7.5)) < 0.03, "99F入口未对准阁楼地板", failures)
		_expect(facility.to_local(ladder.get_exit_position(true)).distance_to(Vector3(15.5, 12.1, -7.5)) < 0.03, "100F出口未对准东门外平台", failures)
		var palette := load("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png") as Texture2D
		var visual_meshes := ladder.find_children("*", "MeshInstance3D", true, false)
		var allowed_roles := ["01_精工金属_紫色骨架", "02_细腻哑光_青绿大面", "03_清漆反光_紫粉点缀", "04_柔和自发光_UI灯光"]
		var actual_roles := {}
		_expect(visual_meshes.size() >= 30, "双段模型缺少踏棍与结构网格", failures)
		for mesh_value in visual_meshes:
			var visual := mesh_value as MeshInstance3D
			if visual == null or visual.mesh == null:
				continue
			for surface in visual.mesh.get_surface_count():
				var material := visual.mesh.surface_get_material(surface) as BaseMaterial3D
				_expect(material != null and material.albedo_texture == palette, "直梯模型材质未绑定项目共用色盘", failures)
				if material != null:
					actual_roles[String(material.resource_name)] = true
					_expect(String(material.resource_name) in allowed_roles, "直梯模型新增了非基地母版的材质角色: %s" % material.resource_name, failures)
		_expect(actual_roles.size() == allowed_roles.size(), "直梯材质角色不是基地母版既有的四种: %s" % [actual_roles.keys()], failures)
		for label in ["bottom", "top"]:
			var exit := ladder.get_exit_position(label == "top")
			var ray := PhysicsRayQueryParameters3D.create(exit + Vector3.UP * 1.5, exit + Vector3.DOWN * 2.0, 1, [player.get_rid()])
			var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			_expect(not hit.is_empty() and absf((hit.get("position", Vector3.INF) as Vector3).y - (exit.y - 0.1)) < 0.2, "%s落脚点没有对应场景地面" % label, failures)
		_expect(not ladder.deployed, "新档直梯应收起", failures)
		_expect(ladder.lower_collision.collision_layer == 0, "收起状态下段碰撞未关闭", failures)
		player.global_position = ladder.get_exit_position(false)
		_expect(ladder.get_interaction_candidate(player).is_empty(), "收起时下方仍可操作", failures)
		player.global_position = ladder.get_exit_position(true)
		var candidate := ladder.get_interaction_candidate(player)
		_expect(str(candidate.get("interaction_id", "")) == "deploy_ladder", "上方放梯入口缺失", failures)
		_expect(ladder.perform_interaction(player, candidate), "上方放梯失败", failures)
		_expect(BaseManager.is_base99_rooftop_ladder_deployed(), "放梯未存档", failures)
		BaseManager.data = BaseData.new()
		BaseManager.load_base()
		var resumed := (load("res://assets/art/props/base_world_3d/runtime/base99_telescopic_ladder/prp_base99_telescopic_ladder_root_top3d.tscn") as PackedScene).instantiate() as Base99TelescopicLadder3D
		add_child(resumed)
		_expect(resumed.deployed and resumed._deploy_progress >= 1.0 and is_equal_approx(resumed.lower_visual.position.y, 0.0), "展开动画中退出后未恢复为永久展开形态", failures)
		resumed.queue_free()
		ladder._deploy_progress = 1.0
		ladder._update_visual()
		_expect(ladder.lower_collision.collision_layer == 1, "展开落锁后下段碰撞未启用", failures)
		_expect(str(ladder.get_interaction_candidate(player).get("interaction_id", "")) == "climb_ladder_down", "展开后上方仍要求重复放梯", failures)
		ladder.prepare_upper_exit()
		for progress in [0.2, 0.35, 0.5, 0.65, 0.8, 0.93, 0.97]:
			var clearance := PhysicsShapeQueryParameters3D.new()
			clearance.shape = player.virtual_collision_capsule.shape
			clearance.transform = Transform3D(player.global_basis, ladder.get_climb_position(progress) + player.virtual_collision_capsule.position)
			clearance.collision_mask = 1
			clearance.exclude = [player.get_rid(), ladder.get_node("UpperCollision").get_rid(), ladder.get_node("LowerCollision").get_rid()]
			var overlaps := player.get_world_3d().direct_space_state.intersect_shape(clearance, 4)
			_expect(overlaps.is_empty(), "攀爬导轨中段与场景碰撞体穿插: %s / %s" % [progress, overlaps], failures)
		player.global_position = ladder.get_exit_position(false)
		var saved_layer := player.collision_layer
		var saved_mask := player.collision_mask
		_expect(player.try_start_ladder_climb(ladder, true), "下方攀爬入口失败", failures)
		for i in 20:
			player._tick_ladder_climb(0.05)
		_expect(player.get_state_machine_state() == "climbing" and player.global_position.y > ladder.global_position.y + 1.0, "自动向上攀爬未推进", failures)
		for tick in 3:
			await get_tree().process_frame
		_expect(str(player.avatar.get_component_snapshot().get("authored_motion_clip", "")) == "climbing", "角色未播放v024攀爬母版动作", failures)
		player._test_move_direction = Vector3(0, 0, 1)
		player._tick_ladder_climb(0.05)
		_expect(player._ladder_direction < 0.0, "途中向下输入未反转", failures)
		player._test_move_direction = null
		for i in 80:
			if player.get_state_machine_state() != "climbing":
				break
			player._tick_ladder_climb(0.05)
		_expect(player.get_state_machine_state() != "climbing", "折返未落地", failures)
		_expect(player.collision_layer == saved_layer and player.collision_mask == saved_mask, "落地后碰撞未恢复", failures)
		player.global_position = ladder.get_exit_position(true)
		_expect(player.try_start_ladder_climb(ladder, false), "上方攀爬入口失败", failures)
		for i in 90:
			if player.get_state_machine_state() != "climbing":
				break
			player._tick_ladder_climb(0.05)
		_expect(player.get_state_machine_state() != "climbing", "向下攀爬未完成", failures)
		_expect(player.collision_layer == saved_layer and player.collision_mask == saved_mask, "向下落地后碰撞未恢复", failures)
		player.global_position = ladder.get_exit_position(false)
		_expect(player.try_start_ladder_climb(ladder, true), "再次从下方攀爬失败", failures)
		for i in 90:
			if player.get_state_machine_state() != "climbing":
				break
			player._tick_ladder_climb(0.05)
		_expect(player.get_state_machine_state() != "climbing" and player.global_position.distance_to(ladder.get_exit_position(true)) < 0.15, "向上攀爬未在100F门外平台落地", failures)
		_expect(player.collision_layer == saved_layer and player.collision_mask == saved_mask, "向上落地后碰撞未恢复", failures)
	tower.queue_free()
	await get_tree().process_frame
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	_expect(BaseManager.is_base99_rooftop_ladder_deployed(), "重载档案后直梯展开状态丢失", failures)
	var restored := (load("res://assets/art/props/base_world_3d/runtime/base99_telescopic_ladder/prp_base99_telescopic_ladder_root_top3d.tscn") as PackedScene).instantiate() as Base99TelescopicLadder3D
	add_child(restored)
	_expect(restored.deployed and is_equal_approx(restored.lower_visual.position.y, 0.0), "重新实例化后下段未保持展开", failures)
	restored.queue_free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("BASE99_TELESCOPIC_LADDER_OK")
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
