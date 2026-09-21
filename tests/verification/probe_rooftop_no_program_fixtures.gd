extends Node
## 只读核对：100F 天台房间**不应有任何程序生成的玩法设施**。
##
## 既有需求（DungeonRoom3D._build_content 内 "用户要求清空屋顶设施，包含程序生成的家具
## 和可搜容器" ⇒ prop_count = 0）只清了家具，**漏了墙边电灯开关 RoomLightSwitch3D**
## （业主 2026-09-21：「天台为什么还会刷一个电灯开关？」）。
##
## 本探针给出可反向对照的判据：样本数哨兵（必须找到 ≥1 个 rooftop 房间）+ 逐项计数。
## 改前：switch=1 ⇒ 红（证明判据咬人）；改后：switch=0 ⇒ 绿。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const SEED := 100990


func _ready() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(100)
	await get_tree().process_frame

	var room_by_id := tower.get("_room_by_id") as Dictionary
	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room != null:
			# 2 = STREAM_ACTIVE，必须推到 ACTIVE 才会跑 _build_content()
			room.set_stream_state(2)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	print("=== 100F 天台房间的程序生成设施计数 ===")
	var rooftops := 0
	var total_switch := 0
	var total_light := 0
	var total_furniture := 0
	var sample_switch := ""
	var sample_switch_pos := Vector3.ZERO
	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room == null or room.size_class != "rooftop":
			continue
		rooftops += 1
		var switch_count := _count(room, "RoomLightSwitch3D")
		var light_count := _count(room, "RoomCeilingLight")
		var furniture_count := _count_type(room, "RoomFurniture3D")
		total_switch += switch_count
		total_light += light_count
		total_furniture += furniture_count
		print("  %-18s y=%7.1f  type=%-8s dim=%s  CeilingLight=%d  LightSwitch=%d  Furniture=%d  state=%d" % [
			room.room_id, room.global_position.y, room.room_type,
			str(room.get_dimensions()), light_count, switch_count, furniture_count,
			room.get("_stream_state"),
		])
		if switch_count > 0 and sample_switch.is_empty():
			var node: Node = _first(room, "RoomLightSwitch3D")
			if node is Node3D:
				sample_switch_pos = (node as Node3D).global_position
				sample_switch = str((node as Node3D).get_path())
	print("  ---- rooftop 房间数=%d  RoomCeilingLight 合计=%d  RoomLightSwitch3D 合计=%d  RoomFurniture3D 合计=%d" % [
		rooftops, total_light, total_switch, total_furniture
	])
	if not sample_switch.is_empty():
		print("  ---- 开关样本（改前应存在）: %s @ %s" % [sample_switch, str(sample_switch_pos)])

	var failures: Array[String] = []
	# 样本数哨兵：没找到 rooftop 房间 ⇒ 探针本身失效，不能判 OK。
	if rooftops < 1:
		failures.append("sample guard: rooftop room count=%d expected>=1" % rooftops)
	if total_switch != 0:
		failures.append("RoomLightSwitch3D count=%d expected=0 (天台不应有电灯开关)" % total_switch)
	if total_furniture != 0:
		failures.append("RoomFurniture3D count=%d expected=0 (天台不应有家具/可搜容器)" % total_furniture)

	for failure in failures:
		push_error(failure)
	print("ROOFTOP_NO_PROGRAM_FIXTURES_%s rooftops=%d light=%d switch=%d furniture=%d" % [
		"OK" if failures.is_empty() else "FAIL", rooftops, total_light, total_switch, total_furniture
	])
	if failures.is_empty():
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _count(root: Node, keyword: String) -> int:
	var found := 0
	for value in root.find_children("*", "Node", true, false):
		if keyword in String(value.name):
			found += 1
	return found


func _count_type(root: Node, type_name: String) -> int:
	return root.find_children("*", type_name, true, false).size()


func _first(root: Node, keyword: String) -> Node:
	for value in root.find_children("*", "Node", true, false):
		if keyword in String(value.name):
			return value
	return null
