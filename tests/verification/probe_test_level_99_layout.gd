extends Node
## 探针：实测测试关卡99「运行时到底装配了什么」，回答俯瞰图里那片巨大平板是什么。
## 只读运行时节点树与物理射线，不读 .blend / .glb 源文件。
##
## 背景：verify_test_level_99_visual 的俯瞰图只看到一间房的楼面细节，
## 其余是一大片暗色平板，且看不到外墙环。逻辑门禁不会察觉这类问题，
## 故用本探针把「层站结构 + 每间房的外壳 + 垂直射线打到谁」全部打出来。

const SCENE_PATH := "res://scenes/ExpeditionLevel99_3D.tscn"
const ALL_ROOM_IDS: Array[String] = ["start", "room_01", "room_02", "extraction"]
## 俯瞰机位高度（与视觉探针一致），射线从这里往下打。
const RAY_START_Y := 90.0
## 网格采样：在内容包围盒上按这个间距铺点向下打射线。
const GRID_STEP_M := 5.0


func _ready() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		print("PROBE_FAIL: %s 加载失败" % SCENE_PATH)
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77199999
	add_child(tower)
	await _settle()

	print("=== 场景判定 ===")
	print("is_expedition=%s  return_scene_path=%s" % [
		str(tower.is_expedition()), str(tower.return_scene_path)
	])
	_dump_tree(tower, 0, 3)

	print("\n=== 层站 ===")
	var stages: Dictionary = tower.get("_floor_stages")
	print("floor_stages keys=%s" % str(stages.keys()))
	for key in stages.keys():
		var stage := stages[key] as Node3D
		if stage == null:
			print("  stage[%s] = null" % str(key))
			continue
		print("  stage[%s] node=%s [%s] pos=%s visible=%s children=%d" % [
			str(key), stage.name, stage.get_class(), str(stage.global_position),
			str(stage.visible), stage.get_child_count()
		])
		for child in stage.get_children():
			var child_3d := child as Node3D
			print("    - %s [%s] pos=%s visible=%s" % [
				child.name, child.get_class(),
				str(child_3d.global_position) if child_3d != null else "n/a",
				str(child_3d.visible) if child_3d != null else "n/a"
			])

	print("\n=== 每间房 ===")
	var room_by_id: Dictionary = tower.get("_room_by_id")
	print("room_by_id size=%d ids=%s" % [room_by_id.size(), str(room_by_id.keys())])
	for room_id in ALL_ROOM_IDS:
		var room := room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("  room '%s' 未找到" % room_id)
			continue
		room.ensure_shell_built()
		await _settle()
		_print_room(room)

	print("\n=== 垂直射线：谁挡在俯瞰机位下面 ===")
	_raycast_grid(tower)

	print("\n=== 走廊可见性 vs 当前房（流送契约核对）===")
	# 必须 await：本函数含 await，是协程；不 await 会跑到第一个 await 就悄悄返回，
	# 循环一行都不会打印（实测踩过，与本仓 GDScript 陷阱同源）。
	await _dump_corridor_visibility(tower)

	print("\nPROBE_DONE")
	get_tree().quit(0)


## 逐一把玩家放进每间房，逐条打印走廊的 visible / _open_edges 真值 / 契约应否可见。
## 用来定位「玩家在某房里却看不到该边走廊」这类流送问题。
func _dump_corridor_visibility(tower: TowerDescent3D) -> void:
	var open_edges: Dictionary = tower.get("_open_edges")
	var corridors: Dictionary = tower.get("_corridor_by_edge")
	print("corridor_by_edge keys=%s" % str(corridors.keys()))
	print("open_edges(开门前)=%s" % str(open_edges))
	# 与视觉探针一致：先把全部边打开，再看逐房的可见性。
	for edge_value in corridors.keys():
		var ids := str(edge_value).split("|")
		if ids.size() == 2:
			tower.force_open_edge_for_test(ids[0], ids[1])
	print("open_edges(开门后)=%s" % str(open_edges))
	for room_id in ALL_ROOM_IDS:
		tower.force_enter_room_for_test(room_id)
		await get_tree().process_frame
		await get_tree().physics_frame
		var current := str(tower.get("_current_room_id"))
		var parts: Array[String] = []
		for edge_value in corridors.keys():
			var edge := str(edge_value)
			var connector := corridors[edge_value] as Node3D
			var ids := edge.split("|")
			var open_value := bool(open_edges.get(edge, false))
			var contains := current in ids
			var should := open_value and contains
			parts.append(
				"%s open=%s current_in=%s should=%s actual=%s"
				% [
					edge, str(open_value), str(contains), str(should),
					str(connector.visible) if connector != null else "null"
				]
			)
		print("  当前房=%-10s %s" % [current, " | ".join(parts)])


func _print_room(room: DungeonRoom3D) -> void:
	var snapshot := room.get_room_snapshot()
	print("  room %s type=%s dims=%s global_pos=%s visible=%s stream_state=%s shell_built=%s" % [
		room.room_id, room.room_type, str(room.get_dimensions()),
		str(room.global_position), str(room.visible),
		str(snapshot.get("stream_state", "?")), str(snapshot.get("shell_built", "?"))
	])
	var meshes := 0
	var multimeshes := 0
	var static_bodies := 0
	var mesh_names: Array[String] = []
	for child in room.get_children():
		if child is MultiMeshInstance3D:
			multimeshes += 1
		elif child is MeshInstance3D:
			meshes += 1
			if mesh_names.size() < 6:
				mesh_names.append(str(child.name))
		elif child is StaticBody3D:
			static_bodies += 1
	print("    children=%d mesh=%d multimesh=%d staticbody=%d sample_meshes=%s" % [
		room.get_child_count(), meshes, multimeshes, static_bodies, str(mesh_names)
	])
	# 房间自身 MeshInstance3D 与 MultiMesh 的世界 AABB，用来看可见包络对不对。
	var bounds := _visual_aabb(room)
	print("    visual_aabb(own)=%s" % str(bounds))


## 在房间包围盒上按网格向下打射线，统计每个命中节点被打了多少次。
func _raycast_grid(tower: TowerDescent3D) -> void:
	var bounds := _content_bounds(tower)
	print("content_bounds=%s" % str(bounds))
	if bounds.size.x <= 0.0:
		print("bounds 退化，跳过射线")
		return
	var space := get_viewport().world_3d.direct_space_state
	var hits: Dictionary = {}
	var columns := int(bounds.size.x / GRID_STEP_M)
	var rows := int(bounds.size.y / GRID_STEP_M)
	for row in range(rows + 1):
		for column in range(columns + 1):
			var x := bounds.position.x + float(column) * GRID_STEP_M
			var z := bounds.position.y + float(row) * GRID_STEP_M
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, RAY_START_Y, z), Vector3(x, -20.0, z)
			)
			query.collide_with_areas = false
			var result := space.intersect_ray(query)
			if result.is_empty():
				hits["<miss>"] = int(hits.get("<miss>", 0)) + 1
				continue
			var collider := result.get("collider") as Node
			var label := "<null>"
			if collider != null:
				label = "%s [%s]" % [collider.name, collider.get_class()]
			hits[label] = int(hits.get(label, 0)) + 1
	print("射线采样 %d 根，命中统计：" % [(rows + 1) * (columns + 1)])
	var keys := hits.keys()
	keys.sort_custom(func(a, b): return int(hits[a]) > int(hits[b]))
	for key in keys:
		print("  %5d  hit  %s" % [int(hits[key]), str(key)])


func _visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in root.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var box := mesh.global_transform * mesh.mesh.get_aabb()
			result = box if first else result.merge(box)
			first = false
		var multim := child as MultiMeshInstance3D
		if multim != null and multim.multimesh != null and multim.multimesh.mesh != null and multim.multimesh.instance_count > 0:
			var inst_box := multim.multimesh.mesh.get_aabb()
			for index in [0, multim.multimesh.instance_count - 1]:
				var xform := multim.global_transform * multim.multimesh.get_instance_transform(index)
				var box := xform * inst_box
				result = box if first else result.merge(box)
				first = false
	return result if not first else AABB(Vector3.ZERO, Vector3.ZERO)


func _content_bounds(tower: TowerDescent3D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var found := false
	for room_id in ALL_ROOM_IDS:
		var room := (tower.get("_room_by_id") as Dictionary).get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var dimensions := room.get_dimensions()
		var center := room.global_position
		minimum.x = minf(minimum.x, center.x - dimensions.x * 0.5)
		minimum.y = minf(minimum.y, center.z - dimensions.y * 0.5)
		maximum.x = maxf(maximum.x, center.x + dimensions.x * 0.5)
		maximum.y = maxf(maximum.y, center.z + dimensions.y * 0.5)
		found = true
	if not found:
		return Rect2()
	return Rect2(minimum, maximum - minimum)


func _dump_tree(node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var node_3d := node as Node3D
	var suffix := ""
	if node_3d != null and depth <= 2:
		suffix = "  visible=%s" % str(node_3d.visible)
	print("%s%s [%s]%s" % ["  ".repeat(depth), node.name, node.get_class(), suffix])
	for child in node.get_children():
		_dump_tree(child, depth + 1, max_depth)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
