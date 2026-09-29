extends Node
## 探针：远征01 房间灯开关的**玩家交互全链路**实测（游戏内实际走的 STATIC 静态 TSCN 路径）。
##
## 与 probe_expedition_room_light_runtime 的区别：不手动 set_stream_state，
## 而是把玩家真放到开关面前，走 TowerDescent3D 的物理归属刷新 ⇒ 房间流送 ⇒
## 开关 Area3D 检测 ⇒ get_interaction_candidate ⇒ perform_interaction ⇒ 灯是否亮。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_probe'
##   "<godot-console>" --headless --path "<project>" --scene res://_scratch/probe_expedition_light_interaction.tscn

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
	print("EXPEDITION_LIGHT_INTERACTION rooms=%d player=%s" % [rooms.size(), str(player != null)])
	for room in rooms:
		await _probe_room(tower, room, player)
	print("EXPEDITION_LIGHT_INTERACTION_DONE")
	get_tree().quit(0)


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


func _probe_room(tower: TowerDescent3D, room: DungeonRoom3D, player: Node3D) -> void:
	print("")
	print("--- %s type=%s dims=%s" % [room.room_id, room.room_type, _v2(room.get_dimensions())])
	if player != null:
		# 玩家站到房间中心，先让归属刷新把房间推到 ACTIVE。
		player.global_position = room.global_position + Vector3(0, 0.05, 0)
		await _settle()
		tower.call("_refresh_physical_location_authority", true)
		await _settle()
	print("    归属刷新后 current_room=%s stream=%s detail_built=%s" % [
		str(tower.get("_current_room_id")), room.get_stream_state_name(),
		str(room.get("_detail_built")),
	])
	var switch := room.get("_light_switch") as RoomLightSwitch3D
	if switch == null:
		print("    !! 房间没有 _light_switch（detail 未建或无开关）")
		return
	# 玩家挪到开关正面 1.2m（沿开关局部 -Z 即面板正面方向的反向）。
	var facing := -switch.global_transform.basis.z
	var stand := switch.global_position + facing * 1.2
	if player != null:
		player.global_position = stand + Vector3(0, 0.05, 0)
		await _settle()
	var in_range := bool(switch.get("_player_in_range"))
	print("    开关 global=%s 玩家站位=%s 玩家在检测范围内=%s" % [
		_v(switch.global_position), _v(stand), str(in_range),
	])
	var candidate := {}
	if player != null:
		candidate = switch.get_interaction_candidate(player)
	print("    交互候选=%s" % str(candidate))
	var before := switch.get_snapshot()
	var lights: Array = room.get("_room_lights") as Array
	var ok := false
	if not candidate.is_empty() and player != null:
		ok = switch.perform_interaction(player, candidate)
	await get_tree().process_frame
	await get_tree().process_frame
	print("    perform_interaction=%s  开灯前 light_on=%s → 开灯后 light_on=%s" % [
		str(ok), str(before.get("light_on", false)), str(switch.is_light_on()),
	])
	for value in lights:
		var light := value as WastelandLight3D
		if light == null:
			continue
		var omni := light.get("_light") as OmniLight3D
		print("      %s enabled=%s runtime_active=%s omni_energy=%.2f omni_visible=%s" % [
			light.name, str(light.is_light_enabled()),
			str(light.get_snapshot().get("runtime_active", false)),
			omni.light_energy if omni != null else -1.0,
			str(omni.visible) if omni != null else "<无>",
		])
	# 再挪开，模拟离开
	if player != null:
		player.global_position = room.global_position + Vector3(0, 0.05, 0)
		await _settle()


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout


func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]


func _v2(value: Vector2) -> String:
	return "(%.1fx%.1f)" % [value.x, value.y]
