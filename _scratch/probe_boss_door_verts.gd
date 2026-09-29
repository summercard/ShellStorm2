extends Node
## 诊断（复刻探针口径）：实例化真实远征场景，取 boss 房，按
## `art_root.transform.affine_inverse() * door.position` 求门位车道，
## 再数净空盒内的网格顶点，并打印提交顶点的模块与 art_root/door 的真实变换。

const EXP := "res://scenes/ExpeditionLevel01_3D.tscn"
const RUN_SEED := 77001199


func _ready() -> void:
	var tower: Node = (load(EXP) as PackedScene).instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", RUN_SEED)
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition")
	var room: Node = block.get_node_or_null("boss") if block != null else null
	if room == null:
		print("BOSS_ROOM_MISSING")
		get_tree().quit()
		return
	room.call("ensure_shell_built")
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	print("art.transform = ", art.transform)
	print("art.global    = ", art.global_transform)
	var ports := art.get_node_or_null("ConnectionPorts")
	for direction in room.get("doors"):
		var door: Node3D = room.call("get_door_node", direction)
		if door == null:
			print("door %s = null" % str(direction))
			continue
		var lane: Vector3 = art.transform.affine_inverse() * door.position
		print("=== %s door.position(room-local)=%s  lane(art-local)=%s ===" % [
			str(direction), str(door.position), str(lane),
		])
		var total := 0
		for child in art.get_children():
			if not (child is Node3D):
				continue
			var n := child as Node3D
			var res := _box_hits(n, art, str(direction), lane)
			if int(res[0]) > 0:
				total += int(res[0])
				print("  HIT %-30s verts=%-4d comp=%s y[%.3f,%.3f]" % [
					n.name, int(res[0]), str(n.get_meta("authored_component_id", "")),
					float(res[1]), float(res[2]),
				])
		print("  TOTAL = %d" % total)
	# 端口原位置（art-local）用于对比
	if ports != null:
		for c in ports.get_children():
			print("port %s local=%s" % [c.name, str((c as Node3D).position)])
	get_tree().quit()


func _box_hits(module: Node3D, art_root: Node3D, direction: String, lane: Vector3) -> Array:
	var count := 0
	var ymin := INF
	var ymax := -INF
	for m in _meshes(module):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_art := _rel(mi, art_root)
		for s in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(s)
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for v in verts:
				var p := to_art * v
				if p.y < 0.15 or p.y > 2.35:
					continue
				var hit := false
				if direction in ["north", "south"]:
					hit = absf(p.x - lane.x) <= 1.05 and absf(p.z - lane.z) <= 0.4
				else:
					hit = absf(p.z - lane.z) <= 1.05 and absf(p.x - lane.x) <= 0.4
				if hit:
					count += 1
					ymin = minf(ymin, p.y)
					ymax = maxf(ymax, p.y)
	return [count, ymin, ymax]


func _meshes(module: Node3D) -> Array:
	var out: Array = []
	if module is MeshInstance3D:
		out.append(module)
	out.append_array(module.find_children("*", "MeshInstance3D", true, false))
	return out


func _rel(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := node.transform
	var c := node.get_parent()
	while c != null and c != ancestor:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
