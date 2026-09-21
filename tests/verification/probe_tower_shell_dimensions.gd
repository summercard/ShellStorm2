extends Node
## 探针：实测 100F / 99F / 98F 三层壳体的真实平面尺寸 —— **楼板网格 vs 外墙轮廓**。
##
## 起因（2026-09-21）：主人问「98F 及以下能不能改成跟 99F / 天台同一个面积」。
## 回答之前必须先把现状量出来，而不是读常量反推：`TowerFloorStage3D` 里
## `_floor_grid_dimensions()`（楼板）与 `_outer_grid_dimensions()`（外墙）是
## **两条独立分支**，99F 在两条分支上取的格数不同（50 vs 32），
## 只有运行时实测才知道楼板到底铺到哪、墙立在哪。
##
## 本探针只读运行时节点树与 MultiMesh 实例变换，不读 .blend / .glb 源文件。

const FLOOR_INDICES: Array[int] = [0, 1, 2]


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990321
	add_child(tower)
	await _settle()

	for floor_index in FLOOR_INDICES:
		print("\n########## FLOOR %dF (floor_index=%d) ##########" % [100 - floor_index, floor_index])
		_dump_stage(tower, floor_index)

	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility != null:
		print("\n[facility 房间] dimensions=%s global_position=%s" % [
			str(facility.get_dimensions()), str(facility.global_position)
		])
	else:
		print("\n[facility 房间] MISSING")

	_dump_plan_extents(tower)

	print("\nPROBE_DONE")
	get_tree().quit(0)


## 逐层统计规划房间的平面包络 —— 这是「250 能不能缩到 160」的直接判据：
## 内容房的包络必须整体落在目标轮廓内，否则缩轮廓就等于把房间丢到楼板外。
func _dump_plan_extents(tower: Node) -> void:
	var snapshot: Dictionary = tower.call("get_tower_snapshot")
	var plans: Dictionary = snapshot.get("floor_plan_snapshots", {})
	var indices: Array = plans.keys()
	indices.sort()
	print("\n=== 各层规划房间平面包络（设计源口径，非运行时实例）===")
	for value in indices:
		var floor_index := int(value)
		var plan := plans[value] as Dictionary
		var rooms := plan.get("rooms", []) as Array
		if rooms.is_empty():
			print("%dF (floor_index=%d): rooms=0" % [100 - floor_index, floor_index])
			continue
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for room_value in rooms:
			var room := room_value as Dictionary
			var position: Vector2 = room.get("position", Vector2.ZERO)
			var dimensions: Vector2 = room.get("dimensions", Vector2.ZERO)
			var x0: float = position.x - dimensions.x * 0.5
			var x1: float = position.x + dimensions.x * 0.5
			var z0: float = position.y - dimensions.y * 0.5
			var z1: float = position.y + dimensions.y * 0.5
			if x0 < min_x:
				min_x = x0
			if x1 > max_x:
				max_x = x1
			if z0 < min_z:
				min_z = z0
			if z1 > max_z:
				max_z = z1
		print("%dF (floor_index=%d): rooms=%d  包络 x[%.1f, %.1f] z[%.1f, %.1f]  跨 %.1f × %.1f m" % [
			100 - floor_index, floor_index, rooms.size(),
			min_x, max_x, min_z, max_z, max_x - min_x, max_z - min_z,
		])
		print("   布局 id=%s  模板=%s" % [
			str(plan.get("layout_id", "")), str(snapshot.get("floor_layout_templates", {}).get(floor_index, ""))
		])


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _dump_stage(tower: Node, floor_index: int) -> void:
	var stages: Dictionary = tower.get("_floor_stages")
	var stage := stages.get(floor_index) as Node3D
	if stage == null:
		print("-- stage MISSING（该层壳体未构建）")
		return
	var snapshot: Dictionary = stage.call("get_snapshot")
	print("-- node=%s position=%s" % [stage.name, str(stage.position)])
	print("   floor_kind                 = %s" % str(snapshot.get("floor_kind")))
	print("   [楼板] map_size            = %s" % str(snapshot.get("map_size")))
	print("   [楼板] grid_count          = %s" % str(snapshot.get("grid_count")))
	print("   [楼板] floor_world_rect    = %s" % str(snapshot.get("floor_world_rect")))
	print("   [外墙] outer_map_size      = %s" % str(snapshot.get("outer_map_size")))
	print("   [外墙] outer_grid_count    = %s" % str(snapshot.get("outer_grid_count")))
	print("   [外墙] outer_world_rect    = %s" % str(snapshot.get("outer_world_rect")))
	print("   [外墙] outer_segment_count = %s" % str(snapshot.get("outer_segment_count")))
	print("   [楼板] tile_count          = %s (light=%s dark=%s)" % [
		str(snapshot.get("tile_count")),
		str(snapshot.get("tile_count_light")),
		str(snapshot.get("tile_count_dark")),
	])
	print("   [承重] support_rect_count  = %s" % str(snapshot.get("support_rect_count")))
	for side in ["west", "east", "north", "south"]:
		print("   [楼梯井] %-5s world_rect = %s" % [
			side, str(stage.call("_stair_hole_world_rect", side))
		])
	_dump_derived_coverage(stage, snapshot)


## 由 snapshot 的**规划口径**推出实际铺设覆盖范围。
##
## ⚠️ 不要改成「遍历 MultiMesh.get_instance_transform() 求包络」——实测在本项目
## 的 `--headless`（dummy 渲染驱动）下回读到的是一律 (0,0,0)：`set_instance_transform`
## 写进的是渲染服务器缓冲，dummy 驱动不回填。逐格摆放与 `tile_count` 是同一趟循环
## 里累加出来的，因此这里的推导与「实例包络」等价，且在任何驱动下都成立。
func _dump_derived_coverage(stage: Node3D, snapshot: Dictionary) -> void:
	var tile_count := int(snapshot.get("tile_count", 0))
	var floor_rect: Rect2 = snapshot.get("floor_world_rect", Rect2())
	var outer_rect: Rect2 = snapshot.get("outer_world_rect", Rect2())
	print("   [推导] 楼板铺设覆盖 = %s（%d 格 × %d 格，实铺 %d 块）" % [
		str(floor_rect),
		int(snapshot.get("grid_count", 0)),
		int(snapshot.get("grid_count", 0)),
		tile_count,
	])
	print("   [推导] 楼板与外墙重合 = %s" % (
		"是" if floor_rect.is_equal_approx(outer_rect) else "**否** —— 楼板比外墙多出 %.1f m/边" % (
			maxf(
				absf(outer_rect.position.x - floor_rect.position.x),
				absf(outer_rect.end.x - floor_rect.end.x)
			)
		)
	))
	var outer_visual := stage.get("_outer_visual") as MultiMeshInstance3D
	if outer_visual != null and outer_visual.multimesh != null:
		print("   [实测] 外墙 MultiMesh 实例数 = %d（直段槽位规划 %d）" % [
			outer_visual.multimesh.instance_count,
			int(stage.get("_outer_straight_slot_count")),
		])
