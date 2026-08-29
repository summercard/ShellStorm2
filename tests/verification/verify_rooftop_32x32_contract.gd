extends Node
## 100层保留原16×16主区，只向西扩2格为18×16；其他三边、99层和普通层不动。

const ROOFTOP_TILE_COUNT_WITH_OPENINGS := 234
const ROOFTOP_WORLD_RECT := Rect2(-50.0, -35.0, 90.0, 80.0)
const WEST_STAIR_WORLD_RECT := Rect2(-45.0, 0.0, 15.0, 30.0)
const WEST_PARAPET_X := -49.85


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
		print("ROOFTOP_WEST_EXPANSION_CONTRACT_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_rooftop(rooftop: TowerFloorStage3D, failures: Array[String]) -> void:
	var snapshot := rooftop.get_snapshot()
	_expect((snapshot.get("grid_dimensions", Vector2i.ZERO) as Vector2i) == Vector2i(18, 16), "100层地板没有只向西扩成18×16格", failures)
	_expect((snapshot.get("map_dimensions", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(90.0, 80.0)), "100层地板尺寸不是90m×80m", failures)
	_expect(int(snapshot.get("grid_count", -1)) == 18, "100层旧标量接口没有返回西向宽度18格", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 90.0), "100层旧标量接口没有返回西向宽度90m", failures)
	_expect((snapshot.get("floor_world_rect", Rect2()) as Rect2).is_equal_approx(ROOFTOP_WORLD_RECT), "100层没有保持东南北边界并向西扩10m", failures)
	_expect(int(snapshot.get("tile_count", -1)) == ROOFTOP_TILE_COUNT_WITH_OPENINGS, "100层地砖数没有按18×16主面、36格基地开口和18格完整楼梯开口计算", failures)
	_expect((snapshot.get("outer_grid_dimensions", Vector2i.ZERO) as Vector2i) == Vector2i(18, 16), "100层围栏没有同步改为18×16轮廓", failures)
	_expect((snapshot.get("outer_map_dimensions", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(90.0, 80.0)), "100层围栏尺寸不是90m×80m", failures)
	_expect(int(snapshot.get("outer_module_count", -1)) == 68, "100层围栏模块周长计数不是68", failures)
	_expect((snapshot.get("outer_world_rect", Rect2()) as Rect2).is_equal_approx(ROOFTOP_WORLD_RECT), "100层围栏没有与扩展地板共用轮廓", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_wall_height", -1.0)), 0.75), "100层围栏没有降低50%至0.75m", failures)
	var outer := rooftop.get("_outer_visual") as MultiMeshInstance3D
	_expect(outer != null and outer.multimesh != null, "100层围栏MultiMesh缺失", failures)
	if outer != null and outer.multimesh != null:
		# 西侧门洞由2个独立预制体替代，因此MultiMesh应为68-2个实体模块。
		_expect(outer.multimesh.instance_count == 66, "100层围栏实体模块数量不符合18×16周长和西门洞合同", failures)
	var doorway := rooftop.find_child("ParapetDoorWall_West", false, false) as Node3D
	_expect(doorway != null and is_equal_approx(doorway.scale.y, 0.5), "楼梯门洞旁围栏没有同步降低50%", failures)
	if doorway != null:
		_expect(is_equal_approx(doorway.position.x, WEST_PARAPET_X), "西侧楼梯门洞墙仍位于旧边界并插入楼梯间", failures)
	var west_collision := rooftop.find_child("OuterBoundaryCollision_West", false, false) as StaticBody3D
	_expect(west_collision != null, "100层西侧边界碰撞缺失", failures)
	if west_collision != null:
		for child in west_collision.get_children():
			if child is CollisionShape3D:
				var collision := child as CollisionShape3D
				var shape := collision.shape as BoxShape3D
				_expect(is_equal_approx(collision.position.x, WEST_PARAPET_X), "100层西侧碰撞没有随围栏移动", failures)
				if shape != null:
					var collision_east_edge := collision.position.x + shape.size.x * 0.5
					_expect(collision_east_edge < WEST_STAIR_WORLD_RECT.position.x, "100层西侧碰撞仍侵入楼梯外廓", failures)


func _verify_facility(snapshot: Dictionary, failures: Array[String]) -> void:
	_expect(int(snapshot.get("grid_count", -1)) == 50, "99层地板被错误缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 250.0), "99层地板边长被错误修改", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 32, "99层外墙被意外缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 160.0), "99层外墙边长被意外改变", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_wall_height", -1.0)), 9.0), "99层外墙高度被意外改变", failures)


func _verify_combat_floor(snapshot: Dictionary, failures: Array[String]) -> void:
	_expect(int(snapshot.get("grid_count", -1)) == 50, "普通楼层地板被错误缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 250.0), "普通楼层地板边长被错误修改", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 50, "普通楼层外墙被错误收缩", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 250.0), "普通楼层外墙边长被错误修改", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
