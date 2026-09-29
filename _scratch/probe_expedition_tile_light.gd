extends Node
## 探针：远征01 房间**可走区归属 + 灯落位**实测（游戏内实际走的 STATIC 静态 TSCN 路径）。
##
## 起因：room_01 / room_04 / room_08 的**包围盒中心**不属于任何房间，
## 而运行时中央顶灯与墙面开关的落位公式都以包围盒为基准。
## 本探针回答：
##   ① 每房授权地砖格心数、格心质心（真正的房内参考点）；
##   ② 中央顶灯落位 local 点是否落在某个真砖格上（=是否在房内）；
##   ③ 玩家站在**格心质心**处时，归属能否切到本房、房间能否 ACTIVE、开关能否交互开灯。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_probe'
##   "<godot-console>" --headless --path "<project>" --scene res://_scratch/probe_expedition_tile_light.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var rooms := _collect_rooms(tower)
	var player := tower.player
	print("EXPEDITION_TILE_LIGHT rooms=%d" % rooms.size())
	for room in rooms:
		await _probe_room(tower, room, player)
	print("EXPEDITION_TILE_LIGHT_DONE")
	get_tree().quit(0)


func _probe_room(tower: TowerDescent3D, room: DungeonRoom3D, player: Node3D) -> void:
	var cells: Array = room.get("_authored_tile_cells") as Array
	var dims := room.get_dimensions()
	var center_local := Vector3.ZERO
	var nearest := INF
	var nearest_cell := Vector3.ZERO
	for value in cells:
		var cell := value as Vector3
		var d := Vector2(cell.x, cell.z).distance_to(Vector2.ZERO)
		if d < nearest:
			nearest = d
			nearest_cell = cell
	var inside_center := room.call("_inside_authored_footprint", center_local)
	print("")
	print("--- %s type=%s dims=%s tiles=%d" % [
		room.room_id, room.room_type, _v2(dims), cells.size(),
	])
	if cells.is_empty():
		print("    无地砖格清单（矩形房/程序化房）")
	else:
		# 格心质心（房内参考点）与 5m 相位
		var sum := Vector3.ZERO
		for value in cells:
			sum += value as Vector3
		var centroid := sum / float(cells.size())
		print("    格心质心 local=%s  最近格心=%s 距包围盒中心=%.2fm" % [
			_v(centroid), _v(nearest_cell), nearest,
		])
		print("    包围盒中心 local(0,0,0) 落在真砖格上=%s" % str(inside_center))
		print("    中央顶灯落位 local=%s → 在房内=%s" % [
			_v(Vector3(0, 9.28, 0)), str(inside_center),
		])
	var switch := room.get("_light_switch") as RoomLightSwitch3D
	print("    _light_switch=%s" % ("有" if switch != null else "无(detail 未建)"))
	if player == null or cells.is_empty():
		return
	var sum2 := Vector3.ZERO
	for value2 in cells:
		sum2 += value2 as Vector3
	var centroid_local := sum2 / float(cells.size())
	var stand_local := Vector3(centroid_local.x, 0.05, centroid_local.z)
	player.global_position = room.global_position + stand_local
	await _settle()
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	print("    玩家站在格心质心 %s → current_room=%s stream=%s detail_built=%s" % [
		_v(room.global_position + stand_local),
		str(tower.get("_current_room_id")), room.get_stream_state_name(),
		str(room.get("_detail_built")),
	])
	var sw := room.get("_light_switch") as RoomLightSwitch3D
	if sw == null:
		print("    !! 该房没有运行时开关（light_switch 为空）")
		return
	# 走到开关正面 1.2m 交互
	var facing := -sw.global_transform.basis.z
	player.global_position = sw.global_position + facing * 1.2 + Vector3(0, 0.05, 0)
	await _settle()
	var candidate := sw.get_interaction_candidate(player)
	print("    开关 global=%s 交互候选=%s" % [_v(sw.global_position), str(candidate)])
	if candidate.is_empty():
		return
	var ok := sw.perform_interaction(player, candidate)
	await get_tree().process_frame
	await get_tree().process_frame
	print("    开灯=%s → light_on=%s" % [str(ok), str(sw.is_light_on())])
	var lights: Array = room.get("_room_lights") as Array
	for value3 in lights:
		var light := value3 as WastelandLight3D
		if light == null:
			continue
		var omni := light.get("_light") as OmniLight3D
		print("      %s local=%s enabled=%s runtime_active=%s omni_energy=%.2f" % [
			light.name, _v(light.position), str(light.is_light_enabled()),
			str(light.get_snapshot().get("runtime_active", false)),
			omni.light_energy if omni != null else -1.0,
		])
		if not cells.is_empty():
			# 灯到最近真砖格心的水平距离：>0 说明灯不在房内
			var light_local := light.position
			var best := INF
			for value4 in cells:
				var c := value4 as Vector3
				best = minf(best, Vector2(light_local.x, light_local.z).distance_to(Vector2(c.x, c.z)))
			print("      灯到最近真砖格心水平距离=%.2fm（>2.51 即灯不在房内地砖上）" % best)
	player.global_position = room.global_position + stand_local
	await _settle()


func _collect_rooms(tower: TowerDescent3D) -> Array[DungeonRoom3D]:
	var rooms: Array[DungeonRoom3D] = []
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms.append(room)
	return rooms


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout


func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]


func _v2(value: Vector2) -> String:
	return "(%.1fx%.1f)" % [value.x, value.y]
