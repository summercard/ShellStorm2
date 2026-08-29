extends Node
## 统一交互合同：只有玩家控制器读取interact；候选按优先级/距离唯一选择；
## 新档100F下楼后从start上下文开启99F基地下端普通门不得触发命运。

const MIGRATED_INTERACTION_SCRIPTS := [
	"res://src/world3d/Dungeon3D.gd",
	"res://src/world3d/TowerDescent3D.gd",
	"res://src/base3d/BaseFacility3D.gd",
	"res://src/base3d/DungeonEntrance3D.gd",
	"res://src/world3d/ServiceStation3D.gd",
	"res://src/world3d/ExtractionBeacon3D.gd",
	"res://src/world3d/RoomFurniture3D.gd",
	"res://src/world3d/RoomLightSwitch3D.gd",
	"res://src/world3d/ThemedNPC3D.gd",
	"res://src/training3d/TrainingRack3D.gd",
	"res://src/training3d/TrainingExit3D.gd",
]


class InteractionProbe:
	extends Node3D
	var probe_id := ""
	var priority := 0
	var interaction_count := 0
	var focused := false

	func configure(id_value: String, priority_value: int) -> void:
		probe_id = id_value
		priority = priority_value
		add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)

	func get_interaction_candidate(_player: Player3D) -> Dictionary:
		return {
			"available": true,
			"interaction_id": probe_id,
			"position": global_position,
			"priority": priority,
			"prompt": probe_id,
		}

	func set_interaction_focus(_candidate: Dictionary, value: bool) -> void:
		focused = value

	func perform_interaction(_player: Player3D, _candidate: Dictionary) -> bool:
		interaction_count += 1
		return true


func _ready() -> void:
	var failures: Array[String] = []
	_validate_single_input_owner(failures)
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 1009902
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	_expect(
		tower.player.interaction_controller != null,
		"Player3D没有安装唯一交互控制器",
		failures
	)
	await _validate_priority_and_input_lock(tower, failures)
	await _validate_fresh_rooftop_to_base_door(tower, failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("UNIFIED_PLAYER_INTERACTION_OK: one input owner, deterministic focus and fresh-save 99F door without fate")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("UNIFIED_PLAYER_INTERACTION_FAIL: %s" % failure)
	get_tree().quit(1)


func _validate_single_input_owner(failures: Array[String]) -> void:
	for path in MIGRATED_INTERACTION_SCRIPTS:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "无法读取交互脚本：%s" % path, failures)
		if file == null:
			continue
		var source := file.get_as_text()
		_expect(
			"is_action_pressed(\"interact\")" not in source,
			"交互对象仍直接读取E键：%s" % path,
			failures
		)
		_expect(
			"func get_interaction_candidate" in source
			and "func perform_interaction" in source,
			"交互对象没有完整实现统一候选/执行协议：%s" % path,
			failures
		)
	var controller_file := FileAccess.open(
		"res://src/player3d/PlayerInteractionController3D.gd", FileAccess.READ
	)
	_expect(controller_file != null, "统一交互控制器脚本缺失", failures)
	if controller_file != null:
		_expect(
			controller_file.get_as_text().count("is_action_pressed(\"interact\")") == 1,
			"统一控制器没有且仅有一个interact输入入口",
			failures
		)


func _validate_priority_and_input_lock(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	tower.player.global_position = Vector3(0.0, 0.05, 1000.0)
	var low := InteractionProbe.new()
	low.name = "LowPriorityInteractionProbe"
	low.position = tower.player.global_position
	tower.add_child(low)
	low.configure("low", 10)
	var high := InteractionProbe.new()
	high.name = "HighPriorityInteractionProbe"
	high.position = tower.player.global_position
	tower.add_child(high)
	high.configure("high", 90)
	await get_tree().process_frame
	await _tap_interact()
	_expect(high.interaction_count == 1 and low.interaction_count == 0, "重叠目标没有只执行最高优先级对象", failures)
	_expect(high.focused and not low.focused, "重叠目标没有保持唯一提示焦点", failures)
	tower.player.set_input_locked(true)
	_expect(not tower.player.request_interaction_for_test(), "输入锁定时仍执行了世界交互", failures)
	_expect(high.interaction_count == 1, "输入锁定后交互对象仍被调用", failures)
	tower.player.set_input_locked(false)
	low.queue_free()
	high.queue_free()
	await get_tree().process_frame


func _validate_fresh_rooftop_to_base_door(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var rooms := tower.get("_room_by_id") as Dictionary
	var facility := rooms.get("facility") as DungeonRoom3D
	_expect(facility != null, "99F基地房间缺失", failures)
	if facility == null:
		return
	facility.ensure_shell_built()
	var lower_door := facility.get_door_node("west")
	_expect(lower_door != null, "100F→99F楼梯下端普通门缺失", failures)
	if lower_door == null:
		return
	lower_door.set_open(false, true)
	tower.set("_current_room_id", "start")
	tower.set("_door_fate_active", false)
	tower.player.global_position = lower_door.global_position + lower_door.global_basis.z * 1.4 + Vector3.UP * 0.05
	tower.player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	# 门尚未通过时，楼梯上下文必须仍可保持start；交互路由应使用门的显式owner/edge。
	tower.set("_current_room_id", "start")
	var keys_before := int(tower.call("_get_total_room_keys"))
	var expected_edge := tower.call("_edge_key", "start", "facility") as String
	var focus := tower.player.get_interaction_focus_snapshot()
	_expect(
		"configured_room_edge" in str(focus.get("interaction_id", "")),
		"99F下端门没有被识别为显式绑定的普通交通门",
		failures
	)
	await _tap_interact()
	_expect(lower_door.is_open, "99F下端普通门没有打开", failures)
	_expect(not bool(tower.get("_door_fate_active")), "99F下端普通门错误触发命运卡", failures)
	_expect(int(tower.call("_get_total_room_keys")) == keys_before, "99F下端普通门错误消耗房间钥匙", failures)
	_expect(bool((tower.get("_open_edges") as Dictionary).get(expected_edge, false)), "普通门交互破坏永久start|facility连接", failures)
	_expect(not (tower.get("_open_edges") as Dictionary).has("start|start"), "门路由仍根据当前房间错误生成start|start边", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _tap_interact() -> void:
	var pressed := InputEventAction.new()
	pressed.action = "interact"
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventAction.new()
	released.action = "interact"
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame
