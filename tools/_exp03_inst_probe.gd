extends Node
## 远征03 真实加载：每间房的美术层实例按 Prefab 归组，给出「实际摆了多少份」。

func _ready() -> void:
	var tower := (load("res://scenes/ExpeditionLevel03_3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)
	var waited := 0.0
	while waited < 120.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			break
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var per_prefab := {}
	var rooms := 0
	var tris := 0
	print("EXP03_ROOMS")
	for node in tower.find_children("*", "", true, false):
		if not (node is DungeonRoom3D):
			continue
		var room := node as DungeonRoom3D
		rooms += 1
		var art := room.get_node_or_null("AuthoredLayoutArtRoot")
		var detail := room.get_node_or_null("RuntimeDetail")
		var rt := 0
		for n in room.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh == null:
				continue
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				rt += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		tris += rt
		print("  room %-16s type=%-10s stream=%-12s art=%s detail=%s tris=%d" % [
			room.room_id, room.room_type, room.get_stream_state_name(),
			str(art != null), str(detail != null), rt,
		])
		# 按**实例化子场景的原路径**归组：从每个 MeshInstance3D 往上爬到
		# `scene_file_path` 非空的那个节点，那就是组件 Prefab 的根。
		for n in room.find_children("*", "MeshInstance3D", true, false):
			var cur: Node = n
			var key := ""
			while cur != null and cur != room:
				var sp := str(cur.scene_file_path)
				if not sp.is_empty() and sp.contains("components/"):
					key = sp
					break
				cur = cur.get_parent()
			if key.is_empty():
				key = "<不可归属:%s>" % str(n.name)
			per_prefab[key] = per_prefab.get(key, 0) + 1
	print("EXP03_TOTAL rooms=%d tris=%d" % [rooms, tris])
	print("EXP03_PREFABS")
	var keys := per_prefab.keys()
	keys.sort()
	for k in keys:
		print("  %-44s %d" % [k, per_prefab[k]])
	get_tree().quit(0)


## 从节点名里抽组件 slug：AuthoredServiceStation 等非美术件返回原名。
func re_name(n: String) -> String:
	var low := n.to_lower()
	if low.contains("floor") or low.contains("wall") or low.contains("manor") or low.contains("breakable"):
		var parts := n.split("_")
		if parts.size() >= 3:
			return "%s_%s" % [parts[0], parts[1]]
	return n
