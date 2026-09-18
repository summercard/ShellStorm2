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
	if not bool(facilities.get_meta("visual_only", false)):
		_fail("FACILITY_VISUAL_ONLY_MISSING")
		return
	for child in facilities.get_children():
		if child.get_meta("collision_shape_count", 0) != 0:
			_fail("FACILITY_COLLISION_NOT_ZERO:%s" % child.name)
			return
	root.free()
	print("BATTLE_WALL_FLOOR_FACILITY_KIT_OK walls=12 floors=9 facilities=3")
	call_deferred("_finish", 0)

func _fail(message: String) -> void:
	printerr(message)
	call_deferred("_finish", 1)

func _finish(code: int) -> void:
	get_tree().quit(code)
