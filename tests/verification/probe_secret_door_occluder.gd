extends Node

## 一次性诊断：暗门正前方到底有哪些"面"（含 MultiMesh），谁把门挡在画面外。
##
## `SecretBranch3D._push_site_out_of_wall()` 只扫 `MeshInstance3D`；
## 如果墙体是 `MultiMeshInstance3D` 画的，就会漏掉 → 外推量算成 0 → 门被埋。
## 本探针把每个位点法线方向上 `(face, base]` 区间的所有绘制件列出来。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SEED := 77001199


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var branch := tower.get_node_or_null("SecretBranches")
	if branch == null:
		print("DIAG_MISS 没有 SecretBranches")
		get_tree().quit(0)
		return
	var snapshot := branch.call("debug_snapshot") as Dictionary
	var sites: Array = snapshot.get("sites", []) as Array
	var rooms: Variant = branch.get("_room_nodes")

	for value in sites:
		var site := value as Dictionary
		var site_id := str(site.get("site_id", ""))
		var pos := site.get("position", Vector3.ZERO) as Vector3
		var normal := _normal(str(site.get("wall", "")))
		var room_id := str(site.get("room_id", ""))
		var room: Node3D = null
		if rooms is Dictionary and (rooms as Dictionary).has(room_id):
			room = (rooms as Dictionary)[room_id] as Node3D
		print("")
		print("=== %s  room=%s  外推=%.3fm  base=%.3f ===" % [
			site_id, room_id, float(site.get("wall_push_m", 0.0)), pos.dot(normal),
		])
		if room == null:
			print("  房间节点缺失")
			continue
		var base := pos.dot(normal)
		var tangent := _tangent(str(site.get("wall", "")))
		var along := pos.dot(tangent)

		# —— 1. 统计房间内两类绘制件 ——
		var mi := room.find_children("*", "MeshInstance3D", true, false)
		var mm := room.find_children("*", "MultiMeshInstance3D", true, false)
		print("  房间内 MeshInstance3D=%d  MultiMeshInstance3D=%d" % [mi.size(), mm.size()])

		# —— 2. 法线方向上挡在门前面的绘制件（投影 < base-0.02）——
		var blockers: Array = []
		for node in room.find_children("*", "VisualInstance3D", true, false):
			var vi := node as VisualInstance3D
			var box := _world_box(vi, normal)
			if box.size == Vector3.ZERO:
				continue
			var center := box.get_center()
			if Vector2(center.x - pos.x, center.z - pos.z).length() > 4.0:
				continue
			if box.end.y <= 0.7 or box.position.y >= 2.6:
				continue
			var lo := INF
			var hi := -INF
			var t_lo := INF
			var t_hi := -INF
			for index in range(8):
				var proj := box.get_endpoint(index).dot(normal)
				lo = minf(lo, proj)
				hi = maxf(hi, proj)
				var tp := box.get_endpoint(index).dot(tangent)
				t_lo = minf(t_lo, tp)
				t_hi = maxf(t_hi, tp)
			# 只擦到门边不算挡住（`room_10` 的灯开关就凸出 0.45m，但在门宽之外）。
			var overlap := minf(t_hi, along + 0.9) - maxf(t_lo, along - 0.9)
			if overlap < 1.08:
				continue
			if lo < base - 0.02:
				blockers.append({
					"name": _label(vi), "lo": lo, "hi": hi,
					"cls": vi.get_class(), "protrude": base - lo, "box": box,
				})
		if blockers.is_empty():
			print("  门前无遮挡件 ✔")
		else:
			blockers.sort_custom(func(a, b): return float(a["protrude"]) > float(b["protrude"]))
			for row in blockers.slice(0, 8):
				print("    挡住：%-52s [%s] 区间 %.3f~%.3f  凸出 %.3fm" % [
					str(row["name"]), str(row["cls"]),
					float(row["lo"]), float(row["hi"]), float(row["protrude"]),
				])
				var box := row.get("box", AABB()) as AABB
				print("        AABB pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [
					box.position.x, box.position.y, box.position.z,
					box.size.x, box.size.y, box.size.z,
				])
	print("")
	print("SECRET_DOOR_OCCLUDER_DIAG_OK")
	get_tree().quit(0)


func _world_box(vi: VisualInstance3D, _normal: Vector3) -> AABB:
	if vi is MeshInstance3D:
		var mesh_node := vi as MeshInstance3D
		if mesh_node.mesh == null:
			return AABB()
		return mesh_node.global_transform * mesh_node.get_aabb()
	if vi is MultiMeshInstance3D:
		var multi := vi as MultiMeshInstance3D
		if multi.multimesh == null or multi.multimesh.mesh == null:
			return AABB()
		return multi.global_transform * multi.multimesh.get_aabb()
	return AABB()


func _label(node: Node) -> String:
	var text := ""
	var cursor := node
	for _i in range(6):
		if cursor == null:
			break
		if str(cursor.name).to_lower().contains("wall"):
			return "%s/%s" % [str(cursor.name), str(node.name)]
		cursor = cursor.get_parent()
	cursor = node
	for _i in range(5):
		if cursor == null:
			break
		text = "%s/%s" % [str(cursor.name), text]
		cursor = cursor.get_parent()
	return text


func _normal(wall: String) -> Vector3:
	match wall:
		"south": return Vector3(0, 0, 1)
		"north": return Vector3(0, 0, -1)
		"east": return Vector3(1, 0, 0)
		"west": return Vector3(-1, 0, 0)
	return Vector3.ZERO


func _tangent(wall: String) -> Vector3:
	match wall:
		"south", "north": return Vector3(1, 0, 0)
		"east", "west": return Vector3(0, 0, 1)
	return Vector3.ZERO
