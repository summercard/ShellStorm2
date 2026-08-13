extends Node
## 98—95、94—90、89—85连续三区段真实塔楼生成、独立Boss内容与顺序卸载验收。


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 95009085
	add_child(tower)
	await get_tree().process_frame
	if not tower.generate_through_floor_for_test(85):
		failures.append("真实塔楼无法连续提交到85层")
	await get_tree().process_frame
	var snapshot := tower.get_tower_snapshot()
	var generated := snapshot.get("generated_floor_indices", []) as Array
	for floor_index in range(2, 16):
		if floor_index not in generated:
			failures.append("连续三区段缺少物理层索引%d" % floor_index)
	for floor_number in [95, 90, 85]:
		var expected := BossContentCatalog.get_for_floor(floor_number)
		var matched := false
		for room in tower._rooms:
			if room.room_type != "BOSS" or int(room.get_meta("floor_number", 0)) != floor_number:
				continue
			matched = true
			if str(room.get_meta("boss_content_id", "")) != str(expected.get("boss_content_id", "")):
				failures.append("%d层Boss房内容ID错误" % floor_number)
			if str(room.get_meta("arena_asset_id", "")) != str(expected.get("arena_asset_id", "")):
				failures.append("%d层Boss房场地ID错误" % floor_number)
		if not matched:
			failures.append("%d层没有真实Boss房" % floor_number)

	# 按玩家跨过Boss隔离间的顺序提交旧段；每段必须释放自己的房间集合。
	var remaining_before := tower._rooms.size()
	for lower_floor_index in [6, 11, 16]:
		tower._unload_completed_segment(lower_floor_index)
		await get_tree().process_frame
		if tower._rooms.size() >= remaining_before:
			failures.append("区段边界%d未释放旧段房间" % lower_floor_index)
		remaining_before = tower._rooms.size()
	var final_snapshot := tower.get_tower_snapshot()
	var unloaded := final_snapshot.get("unloaded_segment_floor_indices", []) as Array
	for floor_index in range(2, 16):
		if floor_index not in unloaded:
			failures.append("物理层索引%d未进入区段卸载记录" % floor_index)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("THREE_SEGMENT_TOWER_GENERATION_FLOW_OK: 98-95/94-90/89-85 generated with unique Boss content and unloaded sequentially")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
