extends Node
## 探针：100F 天台「西侧缺口」到底由什么几何填着（只读）。
##
## 背景：TowerFloorStage3D 在西侧楼梯口会跳过若干女儿墙直段，改成摆
## prp_tower_wall_parapet_door_5m（BoxMesh 占位矮墙）。用户反馈这里是
## 「系统栏杆 + 缺口没连起来」。本探针把西边上所有的填空件、女儿墙直段槽位、
## 以及天台房间自带的栏杆/外立面节点全部按世界坐标列出来，供判断该换哪一批件。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const WEST_BAND_MAX_X := -30.0


func _ready() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	if scene == null:
		print("WEST_EDGE_FAIL: 塔楼场景加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()

	var stages: Dictionary = tower.get("_floor_stages")
	var stage := stages.get(0) as Node3D
	_dump_stage_gap(stage)
	_dump_named_children(stage, "ParapetDoorWall_", "女儿墙缺口占位矮墙（系统的）")
	_dump_outer_slots(stage)
	_dump_named_children(tower, "RooftopRail", "天台房间自带栏杆")
	_dump_named_children(tower, "RooftopRailPost", "天台房间自带栏杆立柱")
	_dump_named_children(tower, "RooftopExteriorWall", "天台房间自外立面")
	_dump_named_children(tower, "RooftopExteriorBand", "天台房间自外立面横带")
	_dump_west_band_mesh_nodes(tower)

	# 物理：西侧边界内侧 1m 与外侧 1m，沿 Z 扫描，看墙到底在哪、有没有断。
	print("\n=== 西边界物理扫描（y=0.9，x 从 -55 到 -30） ===")
	for z in [-30.0, -20.0, -10.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]:
		_cast_along_x(z)

	print("\nWEST_EDGE_DONE")
	get_tree().quit(0)


func _dump_stage_gap(stage: Node3D) -> void:
	print("\n########## stage(floor_index=0) 西侧缺口口径 ##########")
	if stage == null:
		print("  MISSING")
		return
	print("  stair_hole_sides=%s" % str(stage.get("stair_hole_sides")))
	print("  _outer_straight_slot_count=%s" % str(stage.get("_outer_straight_slot_count")))
	var outer_rect: Rect2 = stage.call("_outer_world_rect")
	print("  _outer_world_rect=%s" % str(outer_rect))
	var dims: Vector2i = stage.call("_outer_grid_dimensions")
	print("  _outer_grid_dimensions=%s" % str(dims))
	var count_x: int = stage.call("_outer_segment_count", dims.x)
	var count_y: int = stage.call("_outer_segment_count", dims.y)
	print("  segment_count_x=%d segment_count_y=%d" % [count_x, count_y])
	for side in ["west", "north", "south", "east"]:
		var n: int = count_y if side in ["west", "east"] else count_x
		var gaps: Array[String] = []
		for index in range(n):
			if bool(stage.call("_is_in_wall_door_gap", side, index)):
				var pos: Vector3 = stage.call("_wall_module_position", side, index)
				gaps.append("%d@%s" % [index, str(pos.snapped(Vector3(0.01, 0.01, 0.01)))])
		print("  side=%s segments=%d door_gap_indices=%s" % [side, n, str(gaps)])


func _dump_outer_slots(stage: Node3D) -> void:
	if stage == null:
		return
	var slots: Array = stage.get("_outer_straight_slot_transforms")
	print("\n=== 女儿墙直段槽位（实际摆出来的 %d 段） ===" % slots.size())
	var west_slots := 0
	for index in range(slots.size()):
		var t := slots[index] as Transform3D
		if t.origin.x <= WEST_BAND_MAX_X:
			west_slots += 1
			print("  slot[%02d] origin=%s" % [index, str(t.origin.snapped(Vector3(0.01, 0.01, 0.01)))])
	print("  (西侧 x<=%.1f 的直段共 %d 段)" % [WEST_BAND_MAX_X, west_slots])


func _dump_named_children(root: Node, prefix: String, label: String) -> void:
	if root == null:
		return
	var found: Array[Node3D] = []
	_collect(root, prefix, found)
	print("\n=== %s（前缀 %s，共 %d 个） ===" % [label, prefix, found.size()])
	for node in found:
		var line := "  %-34s [%s] world=%s" % [
			str(node.name), node.get_class(), str(node.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
		]
		if node is Node3D:
			line += " scale=%s" % str((node as Node3D).scale.snapped(Vector3(0.001, 0.001, 0.001)))
		var mesh := _find_mesh(node)
		if mesh != null and mesh.mesh != null:
			var aabb := mesh.mesh.get_aabb()
			line += " mesh_aabb pos=%s size=%s" % [
				str(aabb.position.snapped(Vector3(0.01, 0.01, 0.01))),
				str(aabb.size.snapped(Vector3(0.01, 0.01, 0.01)))
			]
		print(line)


## 西带（x < -30）里所有带网格的节点，用来抓「到底哪件摆在西边界上」。
func _dump_west_band_mesh_nodes(root: Node) -> void:
	var stack: Array[Node] = [root]
	var rows: Array[String] = []
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is Node3D):
			continue
		var node_3d := node as Node3D
		if node_3d.global_position.x > WEST_BAND_MAX_X:
			continue
		if node_3d.global_position.x < -60.0:
			continue
		if not (node is MeshInstance3D or node is MultiMeshInstance3D or node is StaticBody3D):
			continue
		rows.append("  %-46s [%s] world=%s" % [
			str(node.name), node.get_class(),
			str(node_3d.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
		])
	rows.sort()
	print("\n=== 西带 x∈[-60,-30] 的可见/碰撞节点（共 %d 个） ===" % rows.size())
	for row in rows:
		print(row)


func _collect(node: Node, prefix: String, output: Array[Node3D]) -> void:
	for child in node.get_children():
		if str(child.name).begins_with(prefix):
			var child_3d := child as Node3D
			if child_3d != null:
				output.append(child_3d)
		_collect(child, prefix, output)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _cast_along_x(z: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(-58.0, 0.9, z), Vector3(-30.0, 0.9, z)
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		print("  z=%7.1f 向内扫描 -> 一路无碰撞（墙是断的）" % z)
		return
	var collider := hit["collider"] as Node
	var position: Vector3 = hit["position"]
	print("  z=%7.1f 向内扫描 -> 首次命中 x=%.3f  collider=%s  path=%s" % [
		z, position.x, collider.name if collider != null else "<null>", _path_of(collider)
	])


func _path_of(node: Node) -> String:
	if node == null:
		return "<null>"
	var parts: Array[String] = []
	var cursor: Node = node
	while cursor != null:
		parts.push_front(str(cursor.name))
		cursor = cursor.get_parent()
	return "/".join(parts)


func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
