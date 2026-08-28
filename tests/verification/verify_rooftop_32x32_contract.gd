extends Node
## 100层缩为32×32格；99层只收外墙，其他楼层维持250m网格。

const ROOFTOP_TILE_COUNT_WITH_OPENINGS := 970


func _ready() -> void:
	var failures: Array[String] = []
	var rooftop := TowerFloorStage3D.new()
	rooftop.configure(0, "rooftop", ["west"])
	add_child(rooftop)
	var facility := TowerFloorStage3D.new()
	facility.configure(1, "facility", [])
	add_child(facility)
	var combat := TowerFloorStage3D.new()
	combat.configure(2, "combat", [])
	add_child(combat)
	await get_tree().process_frame

	_verify_rooftop(rooftop, failures)
	_verify_facility(facility.get_snapshot(), failures)
	_verify_combat_floor(combat.get_snapshot(), failures)

	rooftop.queue_free()
	facility.queue_free()
	combat.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_32X32_CONTRACT_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_rooftop(rooftop: TowerFloorStage3D, failures: Array[String]) -> void:
	var snapshot := rooftop.get_snapshot()
	_expect(int(snapshot.get("grid_count", -1)) == 32, "100层地板没有缩为32格", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 160.0), "100层地板边长不是160m", failures)
	_expect(int(snapshot.get("tile_count", -1)) == ROOFTOP_TILE_COUNT_WITH_OPENINGS, "100层地砖数没有按36格基地开口和18格楼梯间开口扣除", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 32, "100层围栏没有缩为32格", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 160.0), "100层围栏边界不是160m", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_wall_height", -1.0)), 0.75), "100层围栏没有降低50%至0.75m", failures)
	var outer := rooftop.get("_outer_visual") as MultiMeshInstance3D
	_expect(outer != null and outer.multimesh != null, "100层围栏MultiMesh缺失", failures)
	if outer != null and outer.multimesh != null and outer.multimesh.instance_count > 0:
		var transform := outer.multimesh.get_instance_transform(0)
		_expect(is_equal_approx(transform.origin.y, 0.375), "100层围栏可视模型没有降至0.75m高度", failures)
		_expect(is_equal_approx(transform.basis.get_scale().y, 0.5), "100层围栏可视模型没有按50%纵向缩放", failures)
	var doorway := rooftop.find_child("ParapetDoorWall_West", false, false) as Node3D
	_expect(doorway != null and is_equal_approx(doorway.scale.y, 0.5), "楼梯门洞旁围栏没有同步降低50%", failures)


func _verify_facility(snapshot: Dictionary, failures: Array[String]) -> void:
	_expect(int(snapshot.get("grid_count", -1)) == 50, "99层地板被错误缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 250.0), "99层地板边长被错误修改", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 32, "99层外墙没有收至32格", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 160.0), "99层外墙边长不是160m", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_wall_height", -1.0)), 9.0), "99层外墙高度被意外改变", failures)


func _verify_combat_floor(snapshot: Dictionary, failures: Array[String]) -> void:
	_expect(int(snapshot.get("grid_count", -1)) == 50, "普通楼层地板被错误缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 250.0), "普通楼层地板边长被错误修改", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 50, "普通楼层外墙被错误收缩", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 250.0), "普通楼层外墙边长被错误修改", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
