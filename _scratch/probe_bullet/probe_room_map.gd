extends Node3D
## 诊断 v4（只读）：列出远征 13 个运行时房的尺寸、地砖数与多层槽位，
## 找出哪个房才是真的通道桥，以及坑区表达落在哪一层数据里。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 700000
	add_child(tower)
	await _settle(10)
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		room.ensure_detail_built()
		var floor_count := 0
		var roles: Dictionary = {}
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for value in room.authored_layout_instances:
			var instance := value as Dictionary
			var role := str(instance.get("slot_role", ""))
			roles[role] = int(roles.get(role, 0)) + 1
			if role == "floor_tile":
				floor_count += 1
				var position := instance.get("position", Vector3.ZERO) as Vector3
				min_x = minf(min_x, position.x)
				max_x = maxf(max_x, position.x)
				min_z = minf(min_z, position.z)
				max_z = maxf(max_z, position.z)
		print("R4 id=%s type=%s dims=%s floor_tiles=%d span=(%.2f..%.2f, %.2f..%.2f) roles=%s" % [
			room.room_id, room.room_type, str(room.get_dimensions()), floor_count,
			min_x, max_x, min_z, max_z, str(roles),
		])
	print("R4_DONE")
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
