extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	for _frame in 15:
		await get_tree().physics_frame
	var chairs: Array[PushableSeat3D] = []
	for value in get_tree().get_nodes_in_group("pushable_furniture"):
		var chair := value as PushableSeat3D
		if chair != null and ("圆凳" in chair.name or "指挥椅" in chair.name):
			chairs.append(chair)
	if chairs.size() != 2:
		failures.append("99F 实际场景未装配恰好两把旋转椅：%d" % chairs.size())
	for chair in chairs:
		if chair.swivel_pivot == null or chair.get_node_or_null("PlayerBlocker") == null:
			failures.append("%s 未装配分体视觉或角色代理" % chair.name)
		var base_visual := chair.get_node_or_null("BaseVisual")
		var swivel_visual := chair.get_node_or_null("SwivelPivot/SwivelVisual")
		if base_visual == null or base_visual.find_children("*", "MeshInstance3D", true, false).is_empty():
			failures.append("%s 底座网格未导入" % chair.name)
		if swivel_visual == null or swivel_visual.find_children("*", "MeshInstance3D", true, false).is_empty():
			failures.append("%s 旋转上部网格未导入" % chair.name)
		if not _uses_shared_palette(base_visual) or not _uses_shared_palette(swivel_visual):
			failures.append("%s 分体视觉未绑定设施共享色盘" % chair.name)
		if chair.collision_layer != 1 or chair.collision_mask != 1:
			failures.append("%s 未接入场景物理碰撞" % chair.name)
		if chair.global_basis.get_scale().x < 0.5:
			failures.append("%s 实景缩放异常" % chair.name)
		print("BASE99_SEAT_RUNTIME ", chair.name, " path=", chair.get_path(), " pos=", chair.global_position, " world_scale=", chair.global_basis.get_scale())
	if not chairs.is_empty() and tower.player != null:
		var player := tower.player as Player3D
		var chair := chairs[0]
		player.input_locked = false
		player.global_position = chair.global_position + Vector3(-1.0, 0.0, 0.0)
		player._state_machine.transition_to("idle")
		tower._apply_indoor_camera_pose()
		var standing_camera_y := player.camera.global_position.y
		if not player.try_mount_chair(chair):
			failures.append("99F真实场景无法乘坐椅子")
		else:
			await get_tree().physics_frame
			tower._apply_indoor_camera_pose()
			if absf(player.camera.global_position.y - standing_camera_y) > 0.1:
				failures.append("99F相机控制器覆盖了坐姿高度补偿")
			if not player.try_dismount_chair():
				failures.append("99F真实场景无法安全离座")
			elif player.collision_layer & 1 == 0 or player.collision_mask & 1 == 0:
				failures.append("99F真实场景离座后世界碰撞失效")
	if failures.is_empty():
		print("BASE99_SWIVEL_CHAIRS_OK: 99F两把实例均使用v004分体视觉与独立角色碰撞代理")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _uses_shared_palette(root: Node) -> bool:
	if root == null:
		return false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				if "设施低亮多巴胺色盘" in material.albedo_texture.resource_path:
					return true
	return false
