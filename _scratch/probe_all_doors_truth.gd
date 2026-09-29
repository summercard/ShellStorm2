extends Node
## 全房真值表 v2：用**全局坐标**求车道（正确口径），碰撞盒按玩家净空（y 到 1.90m）判定，
## 并打印元凶的位置与包围盒，用于分辨「真·门洞被封」与「探针盒子过严 / 车道错位」。

const EXP := "res://scenes/ExpeditionLevel01_3D.tscn"
const RUN_SEED := 77001199
const CLEAR_TOP_MESH := 2.35
const CLEAR_TOP_COLLISION := 1.90


func _ready() -> void:
	var tower: Node = (load(EXP) as PackedScene).instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", RUN_SEED)
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition")
	if block == null:
		print("NO_EXPEDITION_BLOCK")
		get_tree().quit()
		return
	for room in block.get_children():
		if not (room is Node3D):
			continue
		var room3 := room as Node3D
		if not room3.has_method("ensure_shell_built"):
			continue
		room3.call("ensure_shell_built")
		var art := room3.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		if art == null:
			continue
		for direction in room3.get("doors"):
			var door: Node3D = room3.call("get_door_node", direction)
			if door == null:
				print("%-10s %-6s door=NULL" % [room3.name, str(direction)])
				continue
			var lane_g: Vector3 = art.global_transform.affine_inverse() * door.global_position
			var vg := 0
			var cg := 0
			var detail: Array[String] = []
			for child in art.get_children():
				if not (child is Node3D):
					continue
				var n := child as Node3D
				var hv := int(_verts_in_box(n, art, str(direction), lane_g)[0])
				var hc := _shapes_in_box(n, art, str(direction), lane_g)
				vg += hv
				cg += hc
				if hv > 0 or hc > 0:
					detail.append("%s(v%d/c%d) pos=%s comp=%s" % [
						n.name, hv, hc, str(n.position), str(n.get_meta("authored_component_id", "")),
					])
			var tag := "OK" if (vg == 0 and cg == 0) else "BLOCKED"
			print("%-10s %-6s %-8s lane=%-24s verts=%-4d cols=%-2d %s" % [
				room3.name, str(direction), tag, str(lane_g), vg, cg, " | ".join(detail),
			])
	get_tree().quit()


func _box_of(direction: String, lane: Vector3, top: float) -> AABB:
	var h := top - 0.15
	if direction in ["north", "south"]:
		return AABB(Vector3(lane.x - 1.05, 0.15, lane.z - 0.4), Vector3(2.10, h, 0.80))
	return AABB(Vector3(lane.x - 0.4, 0.15, lane.z - 1.05), Vector3(0.80, h, 2.10))


func _verts_in_box(module: Node3D, art_root: Node3D, direction: String, lane: Vector3) -> Array:
	var count := 0
	var ymin := INF
	var ymax := -INF
	for m in _meshes(module):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_art := _rel(mi, art_root)
		for s in range(mi.mesh.get_surface_count()):
			var verts := mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for v in verts:
				var p := to_art * v
				if p.y < 0.15 or p.y > CLEAR_TOP_MESH:
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


func _shapes_in_box(module: Node3D, art_root: Node3D, direction: String, lane: Vector3) -> int:
	var clear := _box_of(direction, lane, CLEAR_TOP_COLLISION)
	var count := 0
	for node in _shapes(module):
		var cs := node as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if (_rel(cs, art_root) * _shape_aabb(cs.shape)).intersects(clear):
			count += 1
	return count


func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var box := (shape as BoxShape3D).size
		return AABB(-box * 0.5, box)
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return AABB(
			Vector3(-cap.radius, -cap.height * 0.5, -cap.radius),
			Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0),
		)
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return AABB(
			Vector3(-cyl.radius, -cyl.height * 0.5, -cyl.radius),
			Vector3(cyl.radius * 2.0, cyl.height, cyl.radius * 2.0),
		)
	var debug_mesh := shape.get_debug_mesh()
	return debug_mesh.get_aabb() if debug_mesh != null else AABB()


func _meshes(module: Node3D) -> Array:
	var out: Array = []
	if module is MeshInstance3D:
		out.append(module)
	out.append_array(module.find_children("*", "MeshInstance3D", true, false))
	return out


func _shapes(module: Node3D) -> Array:
	var out: Array = []
	if module is CollisionShape3D:
		out.append(module)
	out.append_array(module.find_children("*", "CollisionShape3D", true, false))
	return out


func _rel(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := node.transform
	var c := node.get_parent()
	while c != null and c != ancestor:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
