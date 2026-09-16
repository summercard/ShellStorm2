extends Node
## 探针 v2：先按抵达闸门把 98/97/96/95 四层全部实体化，再实测各自「运行时实际装配成什么」。
## 初始状态只有 98F 入口壳存在，其余层按需构建，故必须先 commit 才能看到 97/96/95。

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

	for fi in FLOOR_INDICES:
		var ok: Variant = tower.call("_commit_floor_bundle", fi, "probe")
		print("COMMIT floor_index=%d -> %s" % [fi, str(ok)])
		await _settle()

	var floor_rooms: Dictionary = tower.get("_floor_room_ids")
	print("\n=== after commits, floor_index keys = %s" % str(floor_rooms.keys()))

	for fi in FLOOR_INDICES:
		var floor_number := 100 - fi
		print("\n\n########## FLOOR %dF (floor_index=%d) ##########" % [floor_number, fi])
		_dump_stage(tower, fi)
		var ids: Array = floor_rooms.get(fi, [])
		print("-- rooms on this floor: count=%d" % ids.size())
		var picked := _pick_combat_room(tower, ids)
		if picked.is_empty():
			print("-- 未取到可测房间")
			continue
		var target := str(picked.get("id", ""))
		print("-- picked room id=%s type=%s" % [target, str(picked.get("type", "?"))])
		tower.force_enter_room_for_test(target)
		await _settle()
		var room := (tower.get("_room_by_id") as Dictionary).get(target) as DungeonRoom3D
		if room == null:
			print("-- room '%s' 未找到" % target)
			continue
		room.ensure_shell_built()
		await _settle()
		_dump_room(room)

	print("\nPROBE_V2_DONE")
	get_tree().quit(0)


func _pick_combat_room(tower: Node, ids: Array) -> Dictionary:
	var fallback: Dictionary = {}
	for id_value in ids:
		var rid := str(id_value)
		var record := tower.call("_find_record", rid) as Dictionary
		if record.is_empty():
			continue
		if fallback.is_empty():
			fallback = record
		if str(record.get("type", "")) in ["COMBAT", "BOSS"]:
			return record
	return fallback


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
	print("-- stage node=%s position=%s" % [stage.name, str(stage.position)])
	print("   meta floor_number=%s block_id=%s" % [
		str(stage.get_meta("floor_number", "<none>")), str(stage.get_meta("block_id", "<none>"))
	])
	print("   _tile_count=%s" % str(stage.get("_tile_count")))
	for key in ["_floor_visual_light", "_floor_visual_dark", "_outer_visual"]:
		var vis := stage.get(key) as MultiMeshInstance3D
		if vis == null:
			print("   %-18s = null" % key)
			continue
		var mm: MultiMesh = vis.multimesh
		var mesh_path := "<null>"
		if mm != null and mm.mesh != null:
			mesh_path = mm.mesh.resource_path
		print("   %-18s node=%s instances=%d mat_override=%s" % [
			key, vis.name, (mm.instance_count if mm != null else -1),
			("YES" if vis.material_override != null else "no")
		])
		print("   %-18s mesh=%s" % ["", mesh_path])


func _dump_room(room: DungeonRoom3D) -> void:
	print("-- room node=%s type=%s size_class=%s tower_module_shell=%s" % [
		room.name, room.room_type, room.size_class, str(room.tower_module_shell)
	])
	print("   global_position=%s dimensions=%s" % [
		str(room.global_position), str(room.get_dimensions())
	])
	var hist: Dictionary = {}
	var multimeshes: Array[String] = []
	var prefab_kinds: Dictionary = {}
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
			multimeshes.append("%s  instances=%d mat_override=%s asset_id=%s mesh=%s" % [
				child.name, (mm.instance_count if mm != null else -1),
				("YES" if vis.material_override != null else "no"),
				str(vis.get_meta("asset_id", "<none>")), mesh_path
			])
		elif str(child.name).begins_with("Imported_") or child is RoomDoor3D:
			var kind := str(child.name).split("_")[1] if str(child.name).begins_with("Imported_") else "RoomDoor3D"
			prefab_kinds[kind] = int(prefab_kinds.get(kind, 0)) + 1
			if kind in ["DoorWall5M", "CornerL5M"] or child is RoomDoor3D:
				print("   >> %s [%s] local_pos=%s rot.y=%.4f" % [
					child.name, cls, str((child as Node3D).position), (child as Node3D).rotation.y
				])
				print("      asset_id=%s  CS(deep)=%d SB(deep)=%d  MeshInst(deep)=%d  BoxShapes=%s" % [
					str(child.get_meta("asset_id", "<none>")),
					_count_type(child, "CollisionShape3D"), _count_type(child, "StaticBody3D"),
					_count_type(child, "MeshInstance3D"), str(_box_sizes(child))
				])
		deep_cs += _count_type(child, "CollisionShape3D")
		deep_body += _count_type(child, "StaticBody3D")

	print("   child histogram = %s" % str(hist))
	print("   room-local CS(deep)=%d SB(deep)=%d" % [deep_cs, deep_body])
	print("   MultiMeshInstance3D children = %d" % multimeshes.size())
	for line in multimeshes:
		print("      MM  %s" % line)
	print("   prefab-instance groups = %s" % str(prefab_kinds))


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
