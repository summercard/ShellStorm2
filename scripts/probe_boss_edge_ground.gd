extends Node
## 定点诊断：远征01 换房后「走廊 boss|room_10 中点没有地面」到底是哪一段没有面。
##
## 打印每条边的起止门位世界坐标、中点、竖直射线结果，以及 Boss 房的高位入口门位。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	print("=== EDGE boss ===")
	for edge_value in tower._corridor_by_edge.keys():
		var edge := str(edge_value)
		if not edge.contains("boss"):
			continue
		var corridor := tower._corridor_by_edge[edge_value] as Node3D
		if corridor == null:
			continue
		var start := corridor.get_meta("start_door_position", Vector3.ZERO) as Vector3
		var end := corridor.get_meta("end_door_position", Vector3.ZERO) as Vector3
		var mid := (start + end) * 0.5
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(mid + Vector3(0, 2.0, 0), mid + Vector3(0, -2.0, 0))
		)
		print("  边 %-20s start=%s end=%s mid=%s 射线=%s" % [
			edge, _v(start), _v(end), _v(mid),
			"空" if hit.is_empty() else "%s @%s" % [
				str((hit.collider as Node).name), _v(hit.position as Vector3),
			],
		])
	for room_id in ["room_10", "boss", "extraction"]:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		print("  房 %-11s pos=%s dims=%s" % [
			room_id, _v(room.global_position), str(room.get_dimensions()),
		])
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var side := str(port.get("side", ""))
			var lane := float(port.get("lane_m", 0.0))
			var h := float(port.get("height_m", 0.0))
			var dims := room.get_dimensions()
			var local := Vector3.ZERO
			match side:
				"north":
					local = Vector3(lane, h, -dims.y * 0.5)
				"south":
					local = Vector3(lane, h, dims.y * 0.5)
				"west":
					local = Vector3(-dims.x * 0.5, h, lane)
				_:
					local = Vector3(dims.x * 0.5, h, lane)
			print("     port %-3s %-5s lane=%7.2f h=%5.2f → 世界 %s" % [
				str(port.get("port_id", "")), side, lane, h, _v(room.to_global(local)),
			])
	# 门节点世界坐标
	for room_id in ["room_10", "boss"]:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		for side in ["north", "south", "east", "west"]:
			var door := room.get_door_node(side)
			if door != null:
				print("  门 %-9s %-5s 世界=%s open=%s" % [
					room_id, side, _v(door.global_position), str(door.get("is_open")),
				])
	print("EDGE_GROUND_DONE")
	get_tree().quit(0)


func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
