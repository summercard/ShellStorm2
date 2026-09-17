extends Node
## 只读核对：把 98F 入口安全房推到 ACTIVE（才会跑 _build_content），
## 数一遍程序生成的地面标线是否真的不再出现。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"


func _ready() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(98)
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

	print("=== 安全房内的程序地面标线与灯光计数 ===")
	var total_route := 0
	var total_threshold := 0
	var total_light := 0
	var total_switch := 0
	var lobbies := 0
	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room == null or room.room_type != "STAIR_LOBBY":
			continue
		lobbies += 1
		var route := _count(room, "StairLobbyRouteGuide")
		var threshold := _count(room, "StairLobbyThresholdGuide")
		var light := _count(room, "RoomCeilingLight")
		var switch_count := _count(room, "RoomLightSwitch3D")
		total_route += route
		total_threshold += threshold
		total_light += light
		total_switch += switch_count
		print("  %-18s y=%7.1f  RouteGuide=%d  ThresholdGuide=%d  CeilingLight=%d  LightSwitch=%d  state=%d" % [
			room.room_id, room.global_position.y, route, threshold, light, switch_count,
			room.get("_stream_state"),
		])
	print("  ---- 安全房数=%d  RouteGuide 合计=%d  ThresholdGuide 合计=%d" % [
		lobbies, total_route, total_threshold
	])
	print("  ---- RoomCeilingLight 合计=%d  RoomLightSwitch3D 合计=%d" % [total_light, total_switch])

	var ok := total_route == 0 and total_threshold == 0 and lobbies > 0
	print("MARKINGS_REMOVED_%s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _count(root: Node, keyword: String) -> int:
	var found := 0
	for value in root.find_children("*", "Node", true, false):
		if keyword in String(value.name):
			found += 1
	return found
