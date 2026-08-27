extends Node
## 楼层坐标、房间归属与雷达显示必须共享同一位置权威。


func _ready() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990100
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var rooms := tower.get("_room_by_id") as Dictionary
	var start := rooms.get("start") as DungeonRoom3D
	var facility := rooms.get("facility") as DungeonRoom3D
	_expect(start != null and facility != null, "楼顶或99F基地房间缺失", failures)
	if start != null and facility != null:
		# 从100F穿阁楼门进入基地建筑体：应在进入阁楼的第一时间统一为99F/facility。
		tower.set("_current_room_id", "start")
		tower.set("_authoritative_floor_index", 0)
		tower.minimap.set_current_room("start")
		tower.player.global_position = facility.global_position + Vector3(0.0, 5.05, 0.0)
		tower.call("_refresh_physical_location_authority")
		_assert_location(tower, 99, "facility", "阁楼入口", failures)

		# 复现旧存档/旧运行态：楼层已缓存为99F，房间和雷达仍停在100F。
		# 同层走到基地地面后必须继续复检，而不是因楼层未变化提前返回。
		tower.set("_current_room_id", "start")
		tower.set("_authoritative_floor_index", 1)
		tower.minimap.set_current_room("start")
		tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
		tower.call("_refresh_physical_location_authority")
		_assert_location(tower, 99, "facility", "同层地面恢复", failures)

		# 雷达楼层不再依赖房间Area：即使暂时没有可解析房间，也应服从物理层。
		tower.set("_current_room_id", "")
		tower.set("_authoritative_floor_index", 1)
		tower.minimap.set_current_room("start")
		tower.player.global_position = facility.global_position + Vector3(0.0, 5.05, 0.0)
		tower.call("_refresh_physical_location_authority")
		_expect(tower.minimap.get_floor_label() == "99F", "无房间触发时雷达没有服从物理楼层", failures)

		# 离开基地体积回到100F，既有楼层切换仍应恢复楼顶房间和雷达。
		tower.player.global_position = start.global_position + Vector3(-20.0, 0.05, 0.0)
		tower.call("_refresh_physical_location_authority")
		_assert_location(tower, 100, "start", "返回楼顶", failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("TOWER_FLOOR_ROOM_AUTHORITY_OK: attic, same-floor recovery and rooftop return stay synchronized")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("TOWER_FLOOR_ROOM_AUTHORITY_FAIL: %s" % failure)
	get_tree().quit(1)


func _assert_location(
	tower: TowerDescent3D,
	expected_floor: int,
	expected_room: String,
	context: String,
	failures: Array[String]
) -> void:
	var snapshot := tower.get_physical_location_snapshot()
	_expect(int(snapshot.get("floor_number", 0)) == expected_floor, "%s楼层错误：%s" % [context, snapshot], failures)
	_expect(str(snapshot.get("room_id", "")) == expected_room, "%s房间错误：%s" % [context, snapshot], failures)
	_expect(tower.minimap.get_floor_label() == "%dF" % expected_floor, "%s雷达楼层错误：%s" % [context, tower.minimap.get_floor_label()], failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
