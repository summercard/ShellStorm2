extends Node
## 探针：实测 98/97/96/95 层（战斗层 floor_index 2..5）「运行时实际装配成什么」。
## 目的：回答「这些房间是不是同一规格 prefab 实例化的墙/地砖/门墙/门」。
## 只读运行时节点树，不读 .blend / .glb 源文件。

const FLOOR_INDICES: Array[int] = [2, 3, 4, 5]


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()

	var floor_rooms: Dictionary = tower.get("_floor_room_ids")
	print("=== floor_index keys = %s" % str(floor_rooms.keys()))

	for fi in FLOOR_INDICES:
		var floor_number := 100 - fi
		print("\n\n########## FLOOR %dF (floor_index=%d) ##########" % [floor_number, fi])
		_dump_stage(tower, fi)
		var ids: Array = floor_rooms.get(fi, [])
		print("-- rooms on this floor: count=%d ids=%s" % [ids.size(), str(ids)])
		if ids.is_empty():
			continue
		var target := str(ids[0])
		tower.force_enter_room_for_test(target)
		await _settle()
		var room := (tower.get("_room_by_id") as Dictionary).get(target) as DungeonRoom3D
		if room == null:
			print("-- room '%s' 未找到" % target)
			continue
		room.ensure_shell_built()
		await _settle()
		_dump_room(room)

	print("\nPROBE_DONE")
	get_tree().quit(0)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _dump_stage(tower: Node, floor_index: int) -> void:
	var stages: Dictionary = tower.get("_floor_stages")
	var stage := stages.get(floor_index) as Node3D
	if stage == null:
		print("-- stage: MISSING（该层壳体未构建）")
		return
	print("-- stage node=%s [%s] position=%s" % [stage.name, stage.get_class(), str(stage.position)])
	print("   meta floor_number=%s block_id=%s" % [
		str(stage.get_meta("floor_number", "<none>")), str(stage.get_meta("block_id", "<none>"))
	])
	print("   _tile_count=%s _support_rect_count=%s" % [
		str(stage.get("_tile_count")), str(stage.get("_support_rect_count"))
	])
	for key in ["_floor_visual_light", "_floor_visual_dark", "_outer_visual"]:
		var vis := stage.get(key) as MultiMeshInstance3D
		if vis == null:
			print("   %-20s = null" % key)
			continue
		var mm: MultiMesh = vis.multimesh
		var mesh_path := "<null>"
		if mm != null and mm.mesh != null:
			mesh_path = mm.mesh.resource_path
		print("   %-20s node=%s instances=%d" % [key, vis.name, (mm.instance_count if mm != null else -1)])
		print("   %-20s mesh=%s" % ["", mesh_path])
		print("   %-20s material_override=%s" % ["", ("YES" if vis.material_override != null else "no")])


func _dump_room(room: DungeonRoom3D) -> void:
	print("-- room node=%s id=%s type=%s size_class=%s tower_module_shell=%s" % [
		room.name, room.room_id, room.room_type, room.size_class, str(room.tower_module_shell)
	])
	print("   global_position=%s  global_rotation.y=%.4f" % [
		str(room.global_position), room.global_rotation.y
	])
	print("   dimensions=%s" % str(room.get_dimensions()))
	for key in ["tower_wall_door_offset_north", "tower_wall_door_offset_south",
			"tower_wall_door_offset_west", "tower_wall_door_offset_east"]:
		if room.has_meta(key):
			print("   meta %s=%s" % [key, str(room.get_meta(key))])

	var hist: Dictionary = {}
	var multimeshes: Array[String] = []
	var prefab_instances: Array[String] = []
	var deep_cs := 0
	var deep_body := 0
	for child in room.get_children():
		var cls := child.get_class()
		hist[cls] = int(hist.get(cls, 0)) + 1
		if child is MultiMeshInstance3D:
			var vis := child as MultiMeshInstance3D
			var mm: MultiMesh = vis.multimesh
			var mesh_path := "<null>"
			if mm != null and mm.mesh != null:
				mesh_path = mm.mesh.resource_path
			multimeshes.append("%s  instances=%d  mat_override=%s\n            mesh=%s\n            asset_id=%s" % [
				child.name, (mm.instance_count if mm != null else -1),
				("YES" if vis.material_override != null else "no"),
				mesh_path, str(vis.get_meta("asset_id", "<none>"))
			])
		elif str(child.name).begins_with("Imported_") or child is RoomDoor3D:
			prefab_instances.append("%s [%s]" % [child.name, cls])
		if str(child.name).begins_with("Imported_DoorWall5M_") or (
			str(child.name).begins_with("Imported_CornerL5M_")
		) or child is RoomDoor3D:
			print("   >> %s [%s]" % [child.name, cls])
			print("      local_pos=%s rotation.y=%.4f" % [
				str((child as Node3D).position), (child as Node3D).rotation.y
			])
			print("      asset_id=%s" % str(child.get_meta("asset_id", "<none>")))
			print("      CollisionShape3D(deep)=%d StaticBody3D(deep)=%d" % [
				_count_type(child, "CollisionShape3D"), _count_type(child, "StaticBody3D")
			])
			print("      MeshInstance3D(deep)=%d BoxShape3D sizes=%s" % [
				_count_type(child, "MeshInstance3D"), str(_box_sizes(child))
			])
			print("      groups=%s" % str(child.get_groups()))
		deep_cs += _count_type(child, "CollisionShape3D")
		deep_body += _count_type(child, "StaticBody3D")

	print("   child type histogram = %s" % str(hist))
	print("   room-local CollisionShape3D(deep)=%d StaticBody3D(deep)=%d" % [deep_cs, deep_body])
	print("   MultiMeshInstance3D children = %d" % multimeshes.size())
	for line in multimeshes:
		print("      MM  %s" % line)
	print("   prefab-instance children = %d -> %s" % [prefab_instances.size(), str(prefab_instances)])


func _count_type(root: Node, type_name: String) -> int:
	var count := 0
	if root.is_class(type_name):
		count += 1
	for child in root.get_children():
		count += _count_type(child, type_name)
	return count


func _box_sizes(root: Node) -> Array[String]:
	var sizes: Array[String] = []
	for value in root.find_children("*", "CollisionShape3D", true, false):
		var cs := value as CollisionShape3D
		if cs.shape is BoxShape3D:
			sizes.append(str((cs.shape as BoxShape3D).size))
	return sizes
