extends Node
## 永久结构遮光专项：所有楼板与塔楼外圈墙均不参与显隐，局部补丁关闭。


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_stage_patch_contract(failures)
	await _verify_tower_integration(failures)
	if failures.is_empty():
		print("FLOOR_VISIBILITY_SHADOW_PATCH_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_stage_patch_contract(failures: Array[String]) -> void:
	var stage := TowerFloorStage3D.new()
	stage.configure(1, "facility", [])
	add_child(stage)
	await get_tree().process_frame
	stage.set_render_state(false, false)
	stage.set_protected_floor_patch(Vector3(2.5, -9.0, 2.5), true)
	var snapshot := stage.get_snapshot()
	_expect(bool(snapshot.get("floor_visible", false)), "流送调用隐藏了完整楼板", failures)
	_expect(bool(snapshot.get("outer_visible", false)), "流送调用隐藏了塔楼外圈墙", failures)
	_expect(bool(snapshot.get("shell_visible", false)), "流送调用隐藏了结构壳体", failures)
	_expect(not bool(snapshot.get("protected_floor_patch_visible", true)), "永久楼板模式仍启用了重复局部补丁", failures)
	stage.queue_free()
	await get_tree().process_frame


func _verify_tower_integration(failures: Array[String]) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var facility := room_by_id.get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间未生成", failures)
	if facility != null:
		tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
		tower.set("_current_room_id", "facility")
		tower.call("_update_floor_visibility_state")
		await get_tree().process_frame
		# 主动压到最低流送状态，验证关卡生成墙不是“房间节点可见、子墙实际隐藏”的假通过。
		facility.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
		await get_tree().process_frame
		_verify_room_structural_walls(facility, failures)
		var snapshot := tower.get_tower_snapshot()
		_expect((snapshot.get("loaded_floor_indices", []) as Array) == [1], "99层完整流送窗口不是单层", failures)
		_expect((snapshot.get("protected_floor_patch_indices", []) as Array).is_empty(), "永久楼板模式仍创建局部补丁", failures)
		_expect(int(snapshot.get("protected_floor_patch_stage_count", -1)) == 0, "永久楼板模式仍报告保护补丁", failures)
		for stage_data_value in snapshot.get("floor_stages", []):
			var stage_data := stage_data_value as Dictionary
			_expect(bool(stage_data.get("floor_visible", false)), "存在被隐藏的楼板", failures)
			_expect(bool(stage_data.get("outer_visible", false)), "存在被隐藏的塔楼外圈墙", failures)
			_expect(not bool(stage_data.get("protected_floor_patch_visible", true)), "完整楼板与局部补丁发生重叠", failures)
		var stages := tower.get("_floor_stages") as Dictionary
		for stage_value in stages.values():
			var stage := stage_value as TowerFloorStage3D
			var support := stage.get_node_or_null("FloorSupport") as StaticBody3D if stage != null else null
			_expect(
				support != null and support.process_mode == Node.PROCESS_MODE_ALWAYS,
				"远层楼板承重/遮光碰撞会随stage处理窗口退出物理空间",
				failures
			)
	tower.queue_free()
	await get_tree().process_frame


func _verify_room_structural_walls(room: DungeonRoom3D, failures: Array[String]) -> void:
	var wall_visual_count := 0
	var wall_collision_count := 0
	var pending: Array[Node] = [room]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node is GeometryInstance3D and str(node.get_meta("asset_id", "")).contains("WALL"):
			wall_visual_count += 1
			var geometry := node as GeometryInstance3D
			_expect(geometry.visible, "最低流送状态隐藏了关卡生成墙 Mesh", failures)
			_expect(geometry.is_visible_in_tree(), "关卡生成墙受父级显隐影响而不可见", failures)
			_expect(
				geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"关卡生成墙关闭了投影",
				failures
			)
		if node is CollisionShape3D and str(node.get_parent().name).contains("WallCollision"):
			wall_collision_count += 1
			_expect(not (node as CollisionShape3D).disabled, "最低流送状态关闭了墙体碰撞", failures)
			var wall_body := node.get_parent() as PhysicsBody3D
			_expect(
				wall_body != null and wall_body.process_mode == Node.PROCESS_MODE_ALWAYS,
				"最低流送状态让墙体碰撞随房间父节点退出物理空间",
				failures
			)
	_expect(wall_visual_count > 0, "验收场景未发现关卡生成墙 Mesh", failures)
	_expect(wall_collision_count > 0, "验收场景未发现关卡生成墙碰撞", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
