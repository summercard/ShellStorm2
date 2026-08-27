extends Node
## 100F天台—99F阁楼专用升降门：视觉、碰撞、手动开关和自动关闭回归。

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

		# 玩家站在门外安全距离内，通过既有E键链路开启。
		_expect(bool(tower.call("_try_open_base_rooftop_transit_door")), "专用门开启交互失败", failures)
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
		_expect(str(door.get("_prompt").text) == "[E] 关闭通道", "专用门打开后没有关闭交互提示", failures)
		_expect(not _doorway_ray_hits_door(tower, door), "专用门完全打开后物理射线仍命中门板", failures)

		# 再次交互执行关闭；阻挡从高位门板开始随动画下降。
		_expect(bool(tower.call("_try_open_base_rooftop_transit_door")), "专用门关闭交互失败", failures)
		await get_tree().physics_frame
		var closing := door.get_snapshot()
		_expect(not door.is_open and bool(closing.get("transitioning", false)), "专用门没有进入关闭动画", failures)
		_expect(bool(closing.get("blocks_passage", false)), "关闭动画开始后门板碰撞没有恢复", failures)
		await get_tree().create_timer(0.36).timeout
		var closing_mid_y := panel.position.y if panel != null else -1.0
		_expect(closing_mid_y > CLOSED_Y and closing_mid_y < OPEN_Y, "关闭过程没有中间位移", failures)
		await get_tree().create_timer(0.50).timeout
		await get_tree().physics_frame
		var closed := door.get_snapshot()
		_expect(not bool(closed.get("transitioning", true)) and not door.is_open, "专用门关闭动画未完成", failures)
		_expect(bool(closed.get("blocks_passage", false)), "专用门关闭后没有恢复阻挡", failures)
		_expect(panel != null and is_equal_approx(panel.position.y, CLOSED_Y), "专用门关闭后门板位置错误", failures)
		_expect(_doorway_ray_hits_door(tower, door), "专用门关闭后物理射线没有恢复阻挡", failures)

		# 打开后离开门口，专用门应自动执行同一套关闭动画。
		tower.player.global_position = door.to_global(Vector3(0.0, 0.05, 1.5))
		tower.call("_try_open_base_rooftop_transit_door")
		await get_tree().create_timer(0.82).timeout
		tower.player.global_position = door.to_global(Vector3(0.0, 0.05, 4.0))
		await get_tree().create_timer(1.25).timeout
		await get_tree().physics_frame
		var auto_closed := door.get_snapshot()
		_expect(not door.is_open and not bool(auto_closed.get("transitioning", true)), "离开门口后专用门没有自动关闭", failures)
		_expect(bool(auto_closed.get("blocks_passage", false)), "专用门自动关闭后没有恢复阻挡", failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE_ROOFTOP_TRANSIT_DOOR_MOTION_OK: visual, moving blocker, manual toggle and auto-close pass")
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
