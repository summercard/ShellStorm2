extends Node
## 探针：实测「站在 100F 天台边缘往外看，下方到底有什么」。
## 只读：加载完整塔楼，读天台 stage / 99F stage 的轮廓常量，再沿天台周边向下打射线，
## 报告首次命中物的名字与世界 Y。不读 .blend / .glb 源文件，不做任何修改。

const SAMPLE_X := [-70.0, -60.0, -55.0, -51.0, 41.0, 45.0, 50.0, 60.0, 70.0]
const SAMPLE_Z := [-70.0, -55.0, -40.0, -36.0, 46.0, 50.0, 60.0, 70.0]
const RAY_TOP_Y := 30.0
const RAY_BOTTOM_Y := -120.0


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("DOWNVIEW_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()

	var stages: Dictionary = tower.get("_floor_stages")
	var keys: Array = stages.keys()
	keys.sort()
	print("=== _floor_stages keys = %s ===" % str(keys))
	for floor_index in keys:
		_dump_stage(stages.get(floor_index) as Node3D, int(floor_index))

	print("\n=== 向下射线（天台外圈） ===")
	for x in SAMPLE_X:
		_cast(Vector3(x, RAY_TOP_Y, 0.0), "east_west_band x=%.1f" % x)
	for z in SAMPLE_Z:
		_cast(Vector3(0.0, RAY_TOP_Y, z), "north_south_band z=%.1f" % z)

	# 立面幕帘：从「天台边缘外侧」水平朝内打，看 y=-6（低一层的中段）到底有没有墙。
	# 这是「站在天台边缘往下看是不是空的」的直接证据 —— 有幕帘则射线在天台边缘
	# 平面处就被挡住；没有幕帘则射线穿进内圈、甚至无命中。
	print("\n=== 立面幕帘水平射线（y=-6，从外向内） ===")
	_cast_from_to(Vector3(-58.0, -6.0, 0.0), Vector3(-30.0, -6.0, 0.0), "facade_curtain_west")
	_cast_from_to(Vector3(48.0, -6.0, 0.0), Vector3(20.0, -6.0, 0.0), "facade_curtain_east")
	_cast_from_to(Vector3(0.0, -6.0, -43.0), Vector3(0.0, -6.0, -15.0), "facade_curtain_north")
	_cast_from_to(Vector3(0.0, -6.0, 53.0), Vector3(0.0, -6.0, 25.0), "facade_curtain_south")

	print("\n=== 向下射线（天台正上方向下，作为对照） ===")
	_cast(Vector3(0.0, RAY_TOP_Y, 5.0), "rooftop_center")
	_cast(Vector3(-45.0, RAY_TOP_Y, 15.0), "rooftop_west_stair_hole")

	_dump_upper_shell(tower)

	print("\nDOWNVIEW_DONE")
	get_tree().quit(0)


## 天台上方的「100层上层围护与24米封顶」到底是什么，直接列节点与 AABB。
func _dump_upper_shell(tower: Node) -> void:
	print("\n=== 天台上方结构（key 含 围护 / 封顶 的节点） ===")
	var stack: Array[Node] = [tower]
	var found := 0
	while not stack.is_empty() and found < 40:
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var label := str(node.name)
		if label.contains("围护") or label.contains("封顶"):
			found += 1
			var line := "  %-14s [%s] pos=%s" % [label, node.get_class(), str((node as Node3D).position) if node is Node3D else "n/a"]
			if node is MeshInstance3D:
				var mi := node as MeshInstance3D
				if mi.mesh != null:
					var aabb := mi.mesh.get_aabb()
					line += " mesh_aabb pos=%s size=%s" % [str(aabb.position), str(aabb.size)]
			if node is StaticBody3D or node is CollisionShape3D:
				line += "  path=%s" % _path_of(node)
			print(line)
	print("  (matched=%d)" % found)


func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout


func _dump_stage(stage: Node3D, floor_index: int) -> void:
	print("\n########## stage floor_index=%d ##########" % floor_index)
	if stage == null:
		print("  MISSING")
		return
	print("  node=%s position.y=%.3f" % [stage.name, stage.position.y])
	for method_name in ["_floor_world_rect", "_outer_world_rect", "_outer_wall_height"]:
		var value = stage.call(method_name)
		if value is Rect2:
			var rect := value as Rect2
			print(
				"  %-22s position=(%.2f, %.2f) size=(%.2f, %.2f)"
				% [method_name, rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			)
		else:
			print("  %-22s %s" % [method_name, str(value)])
	print("  _tile_count=%s _outer_straight_slot_count=%s" % [
		str(stage.get("_tile_count")), str(stage.get("_outer_straight_slot_count"))
	])
	var outer := stage.get("_outer_visual") as MultiMeshInstance3D
	if outer != null and outer.multimesh != null:
		print("  _outer_visual instances=%d" % outer.multimesh.instance_count)
	else:
		print("  _outer_visual = null")


func _cast(from: Vector3, label: String) -> void:
	_cast_from_to(from, Vector3(from.x, RAY_BOTTOM_Y, from.z), label)


func _cast_from_to(from: Vector3, to: Vector3, label: String) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		print("  %-32s -> 无命中（那里是空的）" % label)
		return
	var collider := hit["collider"] as Node
	var hit_position: Vector3 = hit["position"]
	print(
		"  %-32s -> hit=(%.3f,%.3f,%.3f)  collider=%s  path=%s"
		% [
			label,
			hit_position.x,
			hit_position.y,
			hit_position.z,
			collider.name if collider != null else "<null>",
			_path_of(collider),
		]
	)


func _path_of(node: Node) -> String:
	if node == null:
		return "<null>"
	var parts: Array[String] = []
	var cursor: Node = node
	while cursor != null:
		parts.push_front(str(cursor.name))
		cursor = cursor.get_parent()
	return "/".join(parts)
