extends Node
## 100/99F四扇普通交通门：统一模型、动画、碰撞、E键开启和自动关闭回归。

const CLOSED_Y := 1.25
const OPEN_Y := 4.07


func _ready() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 1009901
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var door := tower.find_child("BaseRooftopTransitDoor", true, false) as RoomDoor3D
	_expect(door != null, "阁楼天台专用门缺失", failures)
	var rooftop := (tower.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	var simple_doors: Array[RoomDoor3D] = []
	if rooftop != null and rooftop.get_door_node("west") != null:
		simple_doors.append(rooftop.get_door_node("west"))
	if facility != null:
		for side in ["west", "east"]:
			if facility.get_door_node(side) != null:
				simple_doors.append(facility.get_door_node(side))
	if door != null:
		simple_doors.append(door)
	_expect(simple_doors.size() == 4, "100/99F没有且仅有四扇普通交通门", failures)
	var permanent_west_edge := tower.call("_edge_key", "start", "facility") as String
	_expect(
		bool((tower.get("_open_edges") as Dictionary).get(permanent_west_edge, false)),
		"100F↔99F西侧固定楼梯仍在等待门授权",
		failures
	)
	for simple_door in simple_doors:
		var simple_snapshot := simple_door.get_snapshot()
		_expect(simple_door.get_node_or_null("SimpleTransitDoor3D") != null, "%s未挂统一普通交通门组件" % simple_door.name, failures)
		_expect(str(simple_snapshot.get("visual_asset_id", "")) == "ENV-BASE99-DOOR-LIFT-22X25", "%s没有使用统一门模型" % simple_door.name, failures)
		_expect(is_equal_approx(float(simple_snapshot.get("motion_duration_s", 0.0)), 0.72), "%s没有使用统一0.72秒动画" % simple_door.name, failures)
		_expect(bool(simple_snapshot.get("collision_tracks_panel_motion", false)), "%s碰撞没有统一跟随门板动画" % simple_door.name, failures)
	if door != null:
		# 进入门附近会加载99/100F连接区域及其静态碰撞。
		tower.player.global_position = door.to_global(Vector3(0.0, 0.05, 1.5))
		await get_tree().process_frame
		await get_tree().physics_frame
		var panel := door.get_node_or_null("DoorPanel") as Node3D
		var collision := door.find_child("DoorCollision", true, false) as CollisionShape3D
		var initial := door.get_snapshot()
		_expect(panel != null and collision != null, "专用门门板或碰撞缺失", failures)
		_expect(not door.is_open and bool(initial.get("blocks_passage", false)), "专用门初始不是关闭阻挡状态", failures)
		_expect(bool(initial.get("collision_tracks_panel_motion", false)) and bool(initial.get("collision_is_direct_body_child", false)), "专用门碰撞没有以有效物理子节点参与同步动画", failures)
		_expect(panel != null and is_equal_approx(panel.position.y, CLOSED_Y), "专用门初始门板不在关闭位置", failures)
		_expect(_doorway_ray_hits_door(tower, door), "专用门关闭时物理射线可以穿过", failures)

		# 玩家站在门外安全距离内，发送真实E键事件开启。
		var interact_event := InputEventAction.new()
		interact_event.action = "interact"
		interact_event.pressed = true
		tower._unhandled_input(interact_event)
		_expect(door.is_open, "普通交通门没有响应真实E键开启", failures)
		await get_tree().physics_frame
		var opening := door.get_snapshot()
		_expect(door.is_open and bool(opening.get("transitioning", false)), "专用门没有进入开启动画", failures)
		_expect(bool(opening.get("blocks_passage", false)), "门板尚未升起时阻挡提前消失", failures)
		await get_tree().create_timer(0.36).timeout
		var opening_mid_y := panel.position.y if panel != null else -1.0
		_expect(opening_mid_y > CLOSED_Y and opening_mid_y < OPEN_Y, "开启过程没有中间位移", failures)
		_expect(collision != null and collision.get_parent() == door and is_equal_approx(collision.position.y, opening_mid_y), "开启时碰撞没有随门板运动", failures)
		await get_tree().create_timer(0.50).timeout
		await get_tree().physics_frame
		var opened := door.get_snapshot()
		_expect(not bool(opened.get("transitioning", true)) and door.is_open, "专用门开启动画未完成", failures)
		_expect(not bool(opened.get("blocks_passage", true)), "专用门完全打开后仍阻挡", failures)
		_expect(panel != null and is_equal_approx(panel.position.y, OPEN_Y), "专用门完全打开后门板位置错误", failures)
		_expect(str(door.get("_prompt").text) == "通道已开启", "普通交通门打开后提示仍包含手动关闭玩法", failures)
		_expect(not _doorway_ray_hits_door(tower, door), "专用门完全打开后物理射线仍命中门板", failures)

		# 重复按E不会切换关闭；四扇普通门都只在玩家离开后自动关闭。
		tower._unhandled_input(interact_event)
		_expect(door.is_open, "已开门重复E错误触发手动关闭", failures)
		tower.player.global_position = door.to_global(Vector3(0.0, 0.05, 4.0))
		await get_tree().create_timer(1.25).timeout
		await get_tree().physics_frame
		var auto_closed := door.get_snapshot()
		_expect(not door.is_open and not bool(auto_closed.get("transitioning", true)), "离开门口后专用门没有自动关闭", failures)
		_expect(bool(auto_closed.get("blocks_passage", false)), "专用门自动关闭后没有恢复阻挡", failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE_SIMPLE_TRANSIT_DOORS_OK: four doors share model, component, moving blocker, E-open and auto-close")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("BASE_ROOFTOP_TRANSIT_DOOR_MOTION_FAIL: %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _doorway_ray_hits_door(tower: TowerDescent3D, door: RoomDoor3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		door.to_global(Vector3(0.0, 1.0, -1.0)),
		door.to_global(Vector3(0.0, 1.0, 1.0)),
		1
	)
	query.exclude = [tower.player.get_rid()]
	var hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == door
