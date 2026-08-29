extends Node
## 复现阁楼入口已归属99F基地、但地面细节流送仍可能切换的路径。
## 普通基地设施必须独立于房间流送，持续保留统一交互协议与实体碰撞。


func _ready() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var rooms := tower.get("_room_by_id") as Dictionary
	var facility_room := rooms.get("facility") as DungeonRoom3D
	_expect(facility_room != null, "99层facility房间缺失", failures)
	var facilities := tower.get("_facility_nodes") as Array
	_expect(facilities.size() == 10, "99层常驻设施数量异常: %d" % facilities.size(), failures)

	# 先停在阁楼层：楼层与房间权威都必须归属99F基地。
	if facility_room != null:
		tower.set("_current_room_id", "start")
		tower.set("_authoritative_floor_index", 0)
		tower.player.global_position = facility_room.to_global(Vector3(0.0, 5.05, 0.0))
		tower.call("_refresh_physical_location_authority")
		_expect(
			str(tower.get("_current_room_id")) == "facility",
			"阁楼入口没有归属99F基地房间上下文",
			failures
		)
		# 再到一楼，但不强制刷新；旧缺陷会因floor_index仍为1而提前返回。
		tower.player.global_position = facility_room.to_global(Vector3(0.0, 0.05, 0.0))
		tower.call("_refresh_physical_location_authority")
		tower.call("_refresh_facility_runtime")
		await get_tree().physics_frame

	for facility_value in facilities:
		var facility := facility_value as BaseFacility3D
		if facility == null:
			failures.append("设施列表含无效节点")
			continue
		_expect(
			facility.process_mode == Node.PROCESS_MODE_ALWAYS,
			"%s仍受房间流送启停" % facility.facility_id,
			failures
		)
		_expect(
			facility.monitoring and facility.monitorable,
			"%s交互Area仍被全局关闭" % facility.facility_id,
			failures
		)
		_expect(
			str(facility.get_meta("runtime_activation_policy", ""))
				== "always_present_distance_interaction",
			"%s没有登记常驻距离交互策略" % facility.facility_id,
			failures
		)
		var bodies := facility.find_children("*", "StaticBody3D", true, false)
		_expect(not bodies.is_empty(), "%s缺少实体阻挡" % facility.facility_id, failures)
		for body_value in bodies:
			var body := body_value as StaticBody3D
			_expect(
				body != null
				and body.process_mode == Node.PROCESS_MODE_ALWAYS
				and bool(body.get_meta("persistent_base_facility_collision", false)),
				"%s实体阻挡仍会随父节点停用" % facility.facility_id,
				failures
			)
			_expect(
				_body_is_in_physics_world(tower, body),
				"%s实体阻挡没有留在PhysicsServer" % facility.facility_id,
				failures
			)
			for shape_value in body.find_children("*", "CollisionShape3D", true, false):
				var collision := shape_value as CollisionShape3D
				_expect(
					collision != null and not collision.disabled,
					"%s存在关闭的实体碰撞" % facility.facility_id,
					failures
				)

	# 设施只实现统一候选/执行协议，不再自行读取E键。
	var target := _find_facility(facilities, "mission_operations")
	_expect(target != null, "缺少用于功能回归的远征情报终端", failures)
	if target != null:
		var activation_count := [0]
		target.activated.connect(func(_facility: BaseFacility3D): activation_count[0] += 1)
		target.call("_on_body_entered", tower.player)
		_expect(
			bool(target.perform_interaction(tower.player, target.get_interaction_candidate(tower.player))),
			"设施没有实现统一交互协议",
			failures
		)
		_expect(int(activation_count[0]) == 1, "设施统一交互激活信号被破坏", failures)
		target.call("_on_body_exited", tower.player)
		_expect(not bool(target.get("_player_in_range")), "离开设施后仍保持交互范围", failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("TOWER_BASE_FACILITY_PERSISTENT_OK: attic route keeps all base interactions and blockers alive without room activation")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _find_facility(facilities: Array, facility_id: String) -> BaseFacility3D:
	for value in facilities:
		var facility := value as BaseFacility3D
		if facility != null and facility.facility_id == facility_id:
			return facility
	return null


func _body_is_in_physics_world(tower: TowerDescent3D, body: StaticBody3D) -> bool:
	if body == null:
		return false
	var collision_nodes := body.find_children("*", "CollisionShape3D", true, false)
	var collision := collision_nodes[0] as CollisionShape3D if not collision_nodes.is_empty() else null
	if collision == null or collision.shape == null:
		return false
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = 0.03
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe_shape
	query.transform = Transform3D(Basis.IDENTITY, collision.global_position)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [tower.player.get_rid()]
	for result in tower.get_world_3d().direct_space_state.intersect_shape(query, 64):
		if result.get("collider") == body:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
