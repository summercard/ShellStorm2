extends Node
## 探针：远征01 各房**运行时**灯光装配实测（游戏内实际走的 STATIC 静态 TSCN 路径）。
##
## 回答的问题：
##   ① 房间根下到底有没有 WastelandLight3D（`_room_lights` 登记数）、灯的世界坐标；
##   ② 灯是不是被顶到天花板**之上**（程序化落位 y=层高-2.72，而远征房层高远小于塔楼层）；
##   ③ 墙面开关在不在、受控灯数、当前灯态；
##   ④ 显式开灯后每盏灯的 light_enabled / runtime_active / OmniLight 实际 energy。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_probe'
##   "<godot-console>" --headless --path "<project>" --scene res://_scratch/probe_expedition_room_light_runtime.tscn

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
	print("EXPEDITION_ROOM_LIGHT_PROBE rooms=%d seed=%d" % [rooms.size(), RUN_SEED])
	for room in rooms:
		# 模拟游戏内真实进房：把房间推到 STREAM_ACTIVE（=2），否则灯不会被
		# set_runtime_active 激活，探针会读出「关了流送所以是黑的」的假象。
		room.set_stream_state(2)
		await _settle()
		await _report(room)
		room.set_stream_state(0)
		await _settle()
	print("EXPEDITION_ROOM_LIGHT_PROBE_DONE")
	get_tree().quit(0)


func _collect_rooms(tower: TowerDescent3D) -> Array[DungeonRoom3D]:
	var rooms: Array[DungeonRoom3D] = []
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		print("!! Blocks/Expedition 不存在")
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms.append(room)
	return rooms


func _report(room: DungeonRoom3D) -> void:
	print("")
	print("--- %s type=%s size_class=%s dims=%s" % [
		room.room_id, room.room_type, room.size_class, _v2(room.get_dimensions()),
	])
	print("    tower_module_shell=%s authored_room_light_on=%s static_layout=%s stream=%s" % [
		str(room.tower_module_shell), str(room.authored_room_light_on),
		str(room.get_meta("static_layout_scene_loaded", false)), room.get_stream_state_name(),
	])
	var lights: Array = room.get("_room_lights") as Array
	print("    _room_lights=%d" % lights.size())
	for value in lights:
		var light := value as WastelandLight3D
		if light == null:
			print("      <非 WastelandLight3D 条目> %s" % str(value))
			continue
		var snap := light.get_snapshot()
		var omni := light.get("_light") as OmniLight3D
		print("      %s local=%s global=%s enabled=%s runtime_active=%s illum=%s omni_energy=%.2f omni_visible=%s" % [
			light.name, _v(light.position), _v(light.global_position),
			str(snap.get("light_enabled", false)), str(snap.get("runtime_active", false)),
			str(snap.get("illumination_active", false)),
			omni.light_energy if omni != null else -1.0,
			str(omni.visible) if omni != null else "<无 OmniLight>",
		])
	var omni_all := room.find_children("*", "OmniLight3D", true, false)
	print("    子树 OmniLight3D=%d" % omni_all.size())
	var switch := room.get("_light_switch") as RoomLightSwitch3D
	if switch == null:
		print("    !! 无 _light_switch")
	else:
		var sw_snap := switch.get_snapshot()
		print("    switch global=%s controlled=%s light_on=%s in_tree=%s prompt=%s" % [
			_v(switch.global_position), str(sw_snap.get("controlled_light_count", -1)),
			str(sw_snap.get("light_on", false)), str(switch.is_inside_tree()),
			switch.get_node_or_null("InteractLabel") != null,
		])
		var changed := switch.set_light_on(true)
		await get_tree().process_frame
		var on := switch.is_light_on()
		print("    强制开灯 set_light_on(true)=%s → is_light_on=%s" % [str(changed), str(on)])
		for value2 in lights:
			var l2 := value2 as WastelandLight3D
			if l2 == null:
				continue
			var omni2 := l2.get("_light") as OmniLight3D
			print("      after %s enabled=%s runtime_active=%s omni_energy=%.2f" % [
				l2.name, str(l2.is_light_enabled()),
				str(l2.get_snapshot().get("runtime_active", false)),
				omni2.light_energy if omni2 != null else -1.0,
			])
	# 房间中心视野：从 1.0m 起向上打射线找天花板/顶，再向下打射线找地板。
	var center := room.global_position
	var up_hit := _ray(room, center + Vector3(0, 1.0, 0), center + Vector3(0, 60.0, 0))
	print("    中心向上射线: %s" % up_hit)
	var down_hit := _ray(room, center + Vector3(0, 1.0, 0), center - Vector3(0, 60.0, 0))
	print("    中心向下射线: %s" % down_hit)
	for value3 in lights:
		var l3 := value3 as WastelandLight3D
		if l3 == null:
			continue
		var probe := _ray(room, l3.global_position, l3.global_position - Vector3(0, 60.0, 0))
		print("    灯 %s 向下射线: %s" % [l3.name, probe])


## 返回 "命中 <路径> @ <距离>m" 或 "CLEAR"。
func _ray(room: DungeonRoom3D, from: Vector3, to: Vector3) -> String:
	var space := room.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "CLEAR"
	var collider := hit.get("collider") as Node
	var path := "<null>"
	if collider != null:
		path = str(collider.get_path()).replace(str(room.get_path()) + "/", "")
	return "命中 %s @ %.2fm (%s)" % [
		path, from.distance_to(hit.get("position") as Vector3), str(collider.get_class() if collider != null else "?"),
	]


func _settle() -> void:
	for _index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout


func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]


func _v2(value: Vector2) -> String:
	return "(%.1fx%.1f)" % [value.x, value.y]
