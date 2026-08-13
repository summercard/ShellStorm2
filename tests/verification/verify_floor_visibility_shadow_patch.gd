extends Node
## 楼层裁剪遮光专项：相邻上下层保留镜头50×50m区域，远层不恢复。


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_stage_patch_contract(failures)
	await _verify_tower_integration(failures)
	if failures.is_empty():
		print("FLOOR_VISIBILITY_SHADOW_PATCH_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_stage_patch_contract(failures: Array[String]) -> void:
	var stage := TowerFloorStage3D.new()
	stage.configure(1, "facility", [])
	add_child(stage)
	await get_tree().process_frame
	stage.set_render_state(false, false)
	stage.set_protected_floor_patch(Vector3(2.5, -9.0, 2.5), true)
	var snapshot := stage.get_snapshot()
	_expect(bool(snapshot.get("protected_floor_patch_visible", false)), "隐藏层50m补丁没有显示", failures)
	_expect(int(snapshot.get("protected_floor_patch_tile_count", 0)) == 100, "中心50m补丁不是100块", failures)
	_expect(bool(snapshot.get("protected_floor_patch_casts_shadow", false)), "50m楼板没有开启投影", failures)
	_expect(is_equal_approx(float(snapshot.get("protected_floor_patch_side_m", 0.0)), 50.0), "补丁边长不是50m", failures)
	var first_center := snapshot.get("protected_floor_patch_grid_center", Vector2i(-1, -1)) as Vector2i
	stage.set_protected_floor_patch(Vector3(7.5, -9.0, 2.5), true)
	snapshot = stage.get_snapshot()
	var second_center := snapshot.get("protected_floor_patch_grid_center", Vector2i(-1, -1)) as Vector2i
	_expect(second_center == first_center + Vector2i.RIGHT, "镜头跨5m格后50m补丁没有移动一格", failures)
	_expect(int(snapshot.get("protected_floor_patch_tile_count", 0)) == 100, "移动后50m补丁实例数改变", failures)
	stage.set_render_state(true, true)
	snapshot = stage.get_snapshot()
	_expect(not bool(snapshot.get("protected_floor_patch_visible", true)), "完整楼板显示时50m补丁发生重叠", failures)
	stage.set_render_state(false, false)
	stage.set_protected_floor_patch(Vector3.ZERO, false)
	snapshot = stage.get_snapshot()
	_expect(not bool(snapshot.get("protected_floor_patch_visible", true)), "禁用后50m补丁仍可见", failures)
	stage.queue_free()
	await get_tree().process_frame


func _verify_tower_integration(failures: Array[String]) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var facility := room_by_id.get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间未生成", failures)
	if facility != null:
		tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
		tower.set("_current_room_id", "facility")
		tower.call("_update_floor_visibility_state")
		await get_tree().process_frame
		var snapshot := tower.get_tower_snapshot()
		var patch_center := snapshot.get("protected_floor_patch_center", Vector3.INF) as Vector3
		_expect(
			patch_center.distance_to(tower.player.camera.global_position) < 0.01,
			"上下层楼板补丁没有以镜头地面投影为中心",
			failures
		)
		_expect((snapshot.get("loaded_floor_indices", []) as Array) == [1], "99层完整流送窗口不是单层", failures)
		_expect((snapshot.get("protected_floor_patch_indices", []) as Array) == [0, 2], "99层上下相邻层未保留镜头50m区域", failures)
		_expect(int(snapshot.get("protected_floor_patch_stage_count", 0)) == 2, "50m保护层数不是2", failures)
		_expect(int(snapshot.get("protected_floor_patch_tile_count", 999)) <= 200, "两层50m补丁总实例超过200", failures)
		for stage_data_value in snapshot.get("floor_stages", []):
			var stage_data := stage_data_value as Dictionary
			var floor_index := int(stage_data.get("floor_index", -1))
			if floor_index not in [0, 2]:
				continue
			var tile_count := int(stage_data.get("protected_floor_patch_tile_count", 0))
			_expect(bool(stage_data.get("protected_floor_patch_visible", false)), "相邻层50m补丁未显示", failures)
			_expect(tile_count > 0 and tile_count <= 100, "相邻层50m补丁实例不在1至100范围", failures)
	tower.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
