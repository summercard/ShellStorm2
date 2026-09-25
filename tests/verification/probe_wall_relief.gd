extends Node
## 探针：逐 mesh 量「装饰相对结构面的凸出量」+ 三角面构成。
##
## 判据：
##   墙组件原点契约 = bottom_center，结构包围盒 5 × 11.9 × 0.30（声明 `bounds_size_m`）
##   ⇒ 结构面在局部 z = ±0.15。逐 mesh 取 AABB，看它相对 ±0.15 凸出多少毫米。
##   凸出量决定「这面墙看起来是浮雕装甲还是纯平面」。

const OUT := "I:/ss2_iso/relief_report.txt"

const TARGETS := [
	{"tag": "battle 通用墙（远征直墙在用）",
	 "path": "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"},
	{"tag": "battle 通用门墙",
	 "path": "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d.tscn"},
	{"tag": "tower A 套实墙",
	 "path": "res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"},
	{"tag": "tower A 套角件 L",
	 "path": "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"},
	{"tag": "旧纯平面占位墙",
	 "path": "res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn"},
]

var _lines: PackedStringArray = []


func _ready() -> void:
	for spec in TARGETS:
		_inspect(str(spec["tag"]), str(spec["path"]))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	for line in _lines:
		print(line)
	print("\nDONE")
	get_tree().quit(0)


func _inspect(tag: String, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_log("!! %s 加载失败" % tag)
		return
	var node := packed.instantiate() as Node3D
	add_child(node)
	_log("========== %s ==========" % tag)
	_log("  asset_id=%s  version=%s  forward_axis=%s" % [
		str(node.get_meta("asset_id", "")), str(node.get_meta("asset_version", "")),
		str(node.get_meta("forward_axis", "")),
	])
	var declared := node.get_meta("bounds_size_m", Vector3.ZERO) as Vector3
	_log("  声明 bounds_size_m = %s  ⇒ 结构面 z = ±%.4f" % [
		str(declared), declared.z * 0.5,
	])
	var half := declared.z * 0.5
	# 逐 MeshInstance 取 AABB（局部→根空间，根无变换故等价）。
	var rows: Array = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for sub in n.get_children():
			stack.append(sub)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var tris := 0
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		rows.append({
			"name": str(mi.name), "tris": tris,
			"min_z": box.position.z, "max_z": box.end.z,
			"min_x": box.position.x, "max_x": box.end.x,
			"min_y": box.position.y, "max_y": box.end.y,
		})
	rows.sort_custom(func(a, b) -> bool:
		return absf(float(a["max_z"]) - half) > absf(float(b["max_z"]) - half)
	)
	_log("  MeshInstance3D 共 %d 个：" % rows.size())
	for value in rows:
		var row := value as Dictionary
		_log("    %-34s 三角=%-6d  X[%+.3f,%+.3f] Y[%+.3f,%+.3f] Z[%+.3f,%+.3f]  → −Z凸%+.1fmm / +Z凸%+.1fmm" % [
			str(row["name"]), int(row["tris"]),
			float(row["min_x"]), float(row["max_x"]),
			float(row["min_y"]), float(row["max_y"]),
			float(row["min_z"]), float(row["max_z"]),
			((-half) - float(row["min_z"])) * 1000.0,
			(float(row["max_z"]) - half) * 1000.0,
		])
	var union := _union(rows)
	_log("  合计可视 Z 范围 [%+.4f, %+.4f] ⇒ 装饰最大凸出 = %.1f mm" % [
		float(union["min_z"]), float(union["max_z"]),
		maxf((-half) - float(union["min_z"]), float(union["max_z"]) - half) * 1000.0,
	])
	_log("")
	node.queue_free()


func _union(rows: Array) -> Dictionary:
	var min_z := INF
	var max_z := -INF
	for value in rows:
		var row := value as Dictionary
		min_z = minf(min_z, float(row["min_z"]))
		max_z = maxf(max_z, float(row["max_z"]))
	return {"min_z": min_z, "max_z": max_z}


func _log(text: String) -> void:
	_lines.append(text)
