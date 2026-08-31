extends Node
## 100层保留原16×16主区，只向西扩2格为18×16；其他三边、99层和普通层不动。

const ROOFTOP_TILE_COUNT_WITH_OPENINGS := 234
const ROOFTOP_WORLD_RECT := Rect2(-50.0, -35.0, 90.0, 80.0)
const WEST_STAIR_WORLD_RECT := Rect2(-45.0, 0.0, 15.0, 30.0)
const WEST_PARAPET_X := -49.85
const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")


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
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	if tower != null:
		tower.test_mode = true
		tower.run_seed_override = 100990
		add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	_verify_rooftop(rooftop, failures)
	_verify_facility(facility.get_snapshot(), failures)
	_verify_combat_floor(combat.get_snapshot(), failures)
	_verify_start_rooftop_shell(tower, failures)

	rooftop.queue_free()
	facility.queue_free()
	combat.queue_free()
	if tower != null:
		tower.queue_free()
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
	_expect(bool(snapshot.get("uses_formal_rooftop_art", false)), "100层正式运行时未接入天台v017设施", failures)
	_expect(str(snapshot.get("formal_rooftop_art_version", "")) == "v017", "100层正式天台设施版本不是v017", failures)
	_expect(int(snapshot.get("formal_rooftop_art_blocker_count", 0)) == 39, "100层正式天台美术没有带入39个细分阻挡组件", failures)
	var facilities := rooftop.find_child("FormalRooftopFacilitiesV017", false, false) as Node3D
	_expect(facilities != null, "100层Stage缺少v017正式设施实例", failures)
	if facilities != null:
		_expect(str(facilities.get_meta("runtime_scope", "")) == "facilities_only", "100层正式实例并非仅设施包装", failures)
		_expect(facilities.get_node_or_null("BaseEnvironment") == null, "100层正式实例错误带入Blender地板或围护", failures)
	var outer := rooftop.get("_outer_visual") as MultiMeshInstance3D
	_expect(outer != null and outer.multimesh != null, "100层围栏MultiMesh缺失", failures)
	_expect(outer != null and outer.visible, "100层原生围栏被设施导入隐藏", failures)
	var floor_light := rooftop.get("_floor_visual_light") as MultiMeshInstance3D
	var floor_dark := rooftop.get("_floor_visual_dark") as MultiMeshInstance3D
	_expect(floor_light != null and floor_light.visible, "100层原生浅色地砖被设施导入隐藏", failures)
	_expect(floor_dark != null and floor_dark.visible, "100层原生深色地砖被设施导入隐藏", failures)
	if outer != null and outer.multimesh != null:
		# 西侧门洞由2个独立预制体替代，因此MultiMesh应为68-2个实体模块。
		_expect(outer.multimesh.instance_count == 66, "100层围栏实体模块数量不符合18×16周长和西门洞合同", failures)
	var doorway := rooftop.find_child("ParapetDoorWall_West", false, false) as Node3D
	_expect(doorway != null and is_equal_approx(doorway.scale.y, 0.5), "楼梯门洞旁围栏没有同步降低50%", failures)
	if doorway != null:
		_expect(doorway.visible, "100层原生西侧门洞围护被设施导入隐藏", failures)
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


func _verify_start_rooftop_shell(tower: TowerDescent3D, failures: Array[String]) -> void:
	_expect(tower != null, "正式塔楼场景无法实例化", failures)
	if tower == null:
		return
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var rooftop_room := room_by_id.get("start") as DungeonRoom3D
	_expect(rooftop_room != null, "100层start房间缺失", failures)
	if rooftop_room == null:
		return
	rooftop_room.ensure_shell_built()
	var snapshot := rooftop_room.get_room_snapshot()
	var open_directions := snapshot.get("open_wall_directions", []) as Array
	for direction in ["north", "south", "east"]:
		_expect(direction in open_directions, "100层start仍未开放%s侧旧房间墙" % direction, failures)
	_expect(
		_count_nodes_with_asset_id(rooftop_room, "ENV-TOWER-WALL-SOLID-5M") == 0,
		"100层start仍生成65米旧房间墙视觉",
		failures
	)
	_expect(
		_count_nodes_with_suffix(rooftop_room, "_Run") == 0,
		"100层start仍生成65米旧房间墙碰撞",
		failures
	)
	_expect(
		_count_nodes_with_asset_id(rooftop_room, "ENV-TOWER-WALL-DOOR-5M") == 1,
		"移除旧房间墙时误删或重复生成了西侧5米门洞墙",
		failures
	)
	_expect(
		rooftop_room.get_door_node("west") != null,
		"移除旧房间墙时误删了100层西侧楼梯门",
		failures
	)


func _count_nodes_with_asset_id(root: Node, asset_id: String) -> int:
	var count := 1 if str(root.get_meta("asset_id", "")) == asset_id else 0
	for child in root.get_children():
		count += _count_nodes_with_asset_id(child, asset_id)
	return count


func _count_nodes_with_suffix(root: Node, suffix: String) -> int:
	var count := 1 if root.name.ends_with(suffix) else 0
	for child in root.get_children():
		count += _count_nodes_with_suffix(child, suffix)
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
