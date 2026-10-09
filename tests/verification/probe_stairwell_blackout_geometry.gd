extends Node
## 探针：多跑几个种子，判断「98F→99F 楼梯间」的几何是否随种子变化 ——
## 决定「提前关灯」触发点能否写死世界坐标，还是必须走房间相对/脚本判定。
##
## 同时实测：玩家在楼梯间时，99F facility 的壳体/灯开关是否已建
## （未建则 scene.light 会降级跳过，提前关灯失效）。
##
## 运行：
##   godot --headless --path . res://tests/verification/probe_stairwell_blackout_geometry.tscn

const SEEDS: Array[int] = [990099, 12345, 777, 424242]


func _ready() -> void:
	for seed_value in SEEDS:
		await _probe_seed(seed_value)
	print("\nPROBE_DONE")
	get_tree().quit(0)


func _probe_seed(seed_value: int) -> void:
	print("\n################ SEED %d ################" % seed_value)
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout

	var room_by_id: Dictionary = tower.get("_room_by_id")
	for room_id in ["facility", "floor_01_entry"]:
		var room := room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("  room %-16s MISSING" % room_id)
			continue
		print("  room %-16s global=%s dims=%s rot_y=%.2f" % [
			room_id, str(room.global_position), str(room.get_dimensions()),
			rad_to_deg(room.global_rotation.y),
		])

	var corridors: Dictionary = tower.get("_corridor_by_edge")
	for connector_value in corridors.values():
		var connector := connector_value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var to_id := str(connector.get_meta("to_room_id", ""))
		if not (("facility" in [from_id, to_id]) and ("floor_01_entry" in [from_id, to_id])):
			continue
		print("  connector %s -> %s" % [from_id, to_id])
		var points: Array = connector.get_meta("path_points", [])
		print("     path_points count = %d" % points.size())
		for index in range(points.size()):
			print("       [%02d] %s" % [index, str(points[index])])

	# 玩家站在 98F 时，99F 各层/房间的加载与壳体状态。
	print("  loaded_floor_indices = %s" % str(tower.get("_loaded_floor_indices")))
	var facility := room_by_id.get("facility") as DungeonRoom3D
	if facility != null:
		print("  facility stream_state=%s shell_built=%s switches=%d lights=%d" % [
			str(facility.get("_stream_state")), str(facility.get("_shell_built")),
			(facility.get("_light_switches") as Array).size(),
			(facility.get("_room_lights") as Array).size(),
		])

	tower.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
