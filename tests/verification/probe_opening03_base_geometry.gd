extends Node
## 探针：实测 99F 基地（facility 房）几何 —— 为「开场03」剧本提供实测数值。
## 只读运行时节点树与内存字典，不读 .blend / .glb 源文件。
##
## 要钉死的事实：
##   1. facility 房的世界坐标 / 旋转 / 尺寸 / 门向（决定触发点与运镜枢轴）。
##   2. 东门（→98F floor_01_entry）与西门（→100F start）的实际世界坐标。
##   3. 东/西墙面灯开关的世界坐标与 meta，以及 get_narrative_light_switch_anchor 的返回值。
##   4. 基地默认灯态（关灯 = false 才符合「开场03：基地状态是关灯状态」）。

const FACILITY_FLOOR_INDEX := 1
const STREAM_ACTIVE := 2
const SEED := 990099


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await _settle()

	tower.call("_ensure_floor_generated", FACILITY_FLOOR_INDEX, "probe")

	var room_by_id: Dictionary = tower.get("_room_by_id")
	print("\n########## ROOM INDEX ##########")
	print("-- keys = %s" % str(room_by_id.keys()))

	var facility := room_by_id.get("facility") as DungeonRoom3D
	if facility == null:
		print("PROBE_FAIL: 找不到 facility 房节点")
		get_tree().quit(1)
		return

	# 强制壳体 + detail 装配（基地灯与开关随壳体内建）。
	facility.call("set_stream_state", STREAM_ACTIVE)
	await _settle()

	_dump_facility(tower, facility)
	_dump_doors(facility)
	_dump_switches(facility)
	_dump_narrative_anchor(facility)
	_dump_stairs(tower, facility)
	_dump_player(tower)

	print("\nPROBE_DONE")
	get_tree().quit(0)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _dump_facility(tower: Node, facility: DungeonRoom3D) -> void:
	print("\n########## FACILITY ROOM ##########")
	print("-- global_position = %s" % str(facility.global_position))
	print("-- global_rotation  = %s  (y=%.4f rad = %.2f deg)" % [
		str(facility.global_rotation), facility.global_rotation.y,
		rad_to_deg(facility.global_rotation.y),
	])
	print("-- dimensions = %s  type = %s  size_class = %s" % [
		str(facility.get_dimensions()), facility.room_type, facility.size_class,
	])
	print("-- doors = %s" % str(facility.doors))
	print("-- door_targets = %s" % str(facility.door_targets))
	print("-- open_wall_directions = %s" % str(facility.open_wall_directions))
	print("-- authored_room_light_on = %s" % str(facility.get("authored_room_light_on")))
	print("-- is_room_light_on() = %s  (期望 false = 关灯)" % str(facility.call("is_room_light_on")))
	print("-- _room_lights.size() = %s" % str((facility.get("_room_lights") as Array).size()))
	print("-- shell_built = %s  detail_built = %s" % [
		str(facility.get("_shell_built")), str(facility.get("_detail_built")),
	])
	var records: Array = tower.get("_records")
	for record_value in records:
		var record := record_value as Dictionary
		if str(record.get("id", "")) == "facility":
			print("-- RECORD position=%s dims=%s doors=%s light_on=%s" % [
				str(record.get("position", Vector3.ZERO)),
				str(record.get("custom_dimensions", Vector2.ZERO)),
				str(record.get("doors", [])),
				str(record.get("authored_room_light_on", false)),
			])
			break


func _dump_doors(facility: DungeonRoom3D) -> void:
	print("\n########## DOORS ##########")
	var count := 0
	for child in facility.get_children():
		var door := child as RoomDoor3D
		if door == null:
			continue
		count += 1
		var local := facility.to_local(door.global_position)
		print("-- DOOR[%s] world=%s local_to_room=%s rot_y=%.2fdeg open=%s" % [
			str(door.name), str(door.global_position), str(local),
			rad_to_deg(door.global_rotation.y), str(door.is_open),
		])
	print("-- door_count = %d" % count)


func _dump_switches(facility: DungeonRoom3D) -> void:
	print("\n########## LIGHT SWITCHES ##########")
	var switches: Array = facility.get("_light_switches")
	if switches.is_empty():
		print("-- _light_switches 为空！(普通房单开关路径?)  _light_switch=%s" % str(
			facility.get("_light_switch") != null
		))
	for switch_value in switches:
		var light_switch := switch_value as RoomLightSwitch3D
		if light_switch == null:
			continue
		var local := facility.to_local(light_switch.global_position)
		print("-- SWITCH[%s] world=%s local_to_room=%s meta_dir=%s light_on=%s" % [
			str(light_switch.name), str(light_switch.global_position), str(local),
			str(light_switch.get_meta("facility_entry_direction", "<none>")),
			str(light_switch.call("is_light_on")),
		])
		print("     interaction_dot_anchor = %s" % str(
			light_switch.call("get_interaction_dot_anchor")
		))


func _dump_narrative_anchor(facility: DungeonRoom3D) -> void:
	print("\n########## NARRATIVE LIGHT-SWITCH ANCHOR ##########")
	for side in ["east", "west"]:
		var anchor: Variant = facility.call("get_narrative_light_switch_anchor", side)
		print("-- anchor[%s] = %s" % [side, str(anchor)])


## 基地 ↔ 98F 的竖直连接器（楼梯）路径点：探明玩家从 99F 下去时**走过哪些点**，
## 用来判断「东门内侧」的触发点会不会被这条下行路径扫到。
func _dump_stairs(tower: Node, facility: DungeonRoom3D) -> void:
	print("\n########## VERTICAL CONNECTORS (facility) ##########")
	var corridors: Dictionary = tower.get("_corridor_by_edge")
	for connector_value in corridors.values():
		var connector := connector_value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var to_id := str(connector.get_meta("to_room_id", ""))
		if from_id != "facility" and to_id != "facility":
			continue
		print("-- connector edge from=%s to=%s" % [from_id, to_id])
		print("   lower_door_position = %s" % str(
			connector.get_meta("lower_door_position", Vector3.INF)
		))
		var points: Array = connector.get_meta("path_points", [])
		print("   path_points count = %d" % points.size())
		for index in range(points.size()):
			var world: Vector3 = points[index]
			var local := facility.to_local(world)
			print("     [%02d] world=%s  local_to_facility=%s" % [
				index, str(world), str(local)
			])


func _dump_player(tower: Node) -> void:
	print("\n########## PLAYER ##########")
	var player := tower.get("player") as Player3D
	if player == null:
		print("-- player: MISSING")
		return
	print("-- global_position = %s" % str(player.global_position))
	print("-- camera = %s" % str(player.camera))
	if player.camera != null:
		print("-- camera global_position = %s" % str(player.camera.global_position))
