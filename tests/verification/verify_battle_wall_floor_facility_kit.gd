extends Node

const KIT_PATH := "res://assets/art/environments/tower_zones/battle/runtime/wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn"

func _init() -> void:
	var scene := load(KIT_PATH) as PackedScene
	if scene == null:
		_fail("KIT_LOAD_FAILED")
		return
	var root := scene.instantiate()
	if root == null:
		_fail("KIT_INSTANTIATE_FAILED")
		return
	if root.get_meta("block_id", "") != "battle":
		_fail("BLOCK_ID_MISMATCH")
		return
	if root.get_meta("grid_unit_m", 0.0) != 5.0:
		_fail("GRID_UNIT_MISMATCH")
		return
	if root.get_meta("room_size_m", Vector2.ZERO) != Vector2(15, 15):
		_fail("ROOM_SIZE_MISMATCH")
		return
	var walls := root.get_node("Walls")
	var floor := root.get_node("Floor")
	var facilities := root.get_node("WallSideFacilities")
	if walls.get_child_count() != 12:
		_fail("WALL_COUNT=%d" % walls.get_child_count())
		return
	if floor.get_child_count() != 9:
		_fail("FLOOR_COUNT=%d" % floor.get_child_count())
		return
	if facilities.get_child_count() != 3:
		_fail("FACILITY_COUNT=%d" % facilities.get_child_count())
		return
	# 2026-09-20：kit 复用的 v007 房间包已按 v004 组件契约内嵌自身 BoxShape3D 碰撞，
	# 因此 kit 不能再声明「设施纯视觉」。改为断言「声明值 == 实际启用形数」的一致性，
	# 并强制至少一件真的会挡 —— 0 样本 / 全不挡都必须变红，否则等于静默退化成纯装饰。
	if bool(facilities.get_meta("visual_only", false)):
		_fail("FACILITY_VISUAL_ONLY_STILL_TRUE")
		return
	var checked := 0
	var blocking := 0
	for child in facilities.get_children():
		checked += 1
		var declared := int(child.get_meta("collision_shape_count", -1))
		if declared < 0:
			_fail("FACILITY_COLLISION_COUNT_MISSING:%s" % child.name)
			return
		var actual := _count_enabled_shapes(child)
		if declared != actual:
			_fail("FACILITY_COLLISION_MISMATCH:%s declared=%d actual=%d" % [child.name, declared, actual])
			return
		if actual > 0:
			blocking += 1
	if checked != 3:
		_fail("FACILITY_SAMPLE_MISSING checked=%d" % checked)
		return
	if blocking == 0:
		_fail("FACILITY_NONE_BLOCKING checked=%d" % checked)
		return
	root.free()
	print("BATTLE_WALL_FLOOR_FACILITY_KIT_OK walls=12 floors=9 facilities=3 blocking=%d" % blocking)
	call_deferred("_finish", 0)

func _count_enabled_shapes(node: Node) -> int:
	var count := 0
	if node is StaticBody3D:
		for shape_holder in node.get_children():
			if shape_holder is CollisionShape3D and not shape_holder.disabled and shape_holder.shape != null:
				count += 1
	for descendant in node.get_children():
		count += _count_enabled_shapes(descendant)
	return count

func _fail(message: String) -> void:
	printerr(message)
	call_deferred("_finish", 1)

func _finish(code: int) -> void:
	get_tree().quit(code)
