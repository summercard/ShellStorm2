extends Node
## 量远征01 真实加载的三角面：每房布局是否入树、入树后多少面、全场合计。

func _ready() -> void:
	var tower := (load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)
	var waited := 0.0
	while waited < 90.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			break
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	var sum := 0
	var sum_visible := 0
	var rooms := 0
	print("ROOM | 状态 | 布局入树 | 网格 | 面 | 可见面")
	for node in tower.find_children("*", "", true, false):
		if not (node is DungeonRoom3D):
			continue
		var room := node as DungeonRoom3D
		rooms += 1
		var art := room.get_node_or_null("AuthoredLayoutArtRoot")
		var detail := room.get_node_or_null("RuntimeDetail")
		var tris := 0
		var tris_vis := 0
		var meshes := 0
		for n in room.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh == null:
				continue
			meshes += 1
			var t := 0
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			tris += t
			if m.is_visible_in_tree():
				tris_vis += t
		sum += tris
		sum_visible += tris_vis
		print("%-12s | %-12s | %s | %4d | %8d | %8d" % [
			room.room_id, room.get_stream_state_name(),
			("布局" if art != null else "-") + ("/细节" if detail != null else ""),
			meshes, tris, tris_vis,
		])
	print("合计: 房间 %d 间，全树三角 %d，其中可见 %d" % [rooms, sum, sum_visible])
	get_tree().quit(0)
