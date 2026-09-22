extends Node
## 98—95、94—90、89—85连续三区段真实塔楼生成、独立Boss内容与顺序卸载验收。
##
## ⚠️ 砍层早退（2026-09-22）：塔楼当前配置为「98F 即最深层」（TowerDescent3D.
## DEEPEST_PLANNED_FLOOR == 98），本用例的三个区段前提整体不存在。判据取**运行时
## 计划层集合**（`_floor_plan_snapshots` 是否含物理层索引 3），不读常量，所以两种
## 配置下都成立；并把实测层集合打出来，避免「没跑还报绿」。砍层本身的正向断言在
## `probe_tower_deepest_floor_cutoff.gd`（竖边数、层种子门、撤离信标全查）。


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 95009085
	add_child(tower)
	await get_tree().process_frame
	# 先按原口径驱动到 85F（砍层模式下会在提交 97F 时失败并返回 false），
	# 再判定塔楼是不是被砍成单层 —— 判定必须在驱动**之后**，否则计划层还没建出来。
	var reached_85 := tower.generate_through_floor_for_test(85)
	await get_tree().process_frame
	var plan_snapshots := tower.get("_floor_plan_snapshots") as Dictionary
	if not plan_snapshots.has(3):
		var floor_rooms := tower.get("_floor_room_ids") as Dictionary
		print(
			"THREE_SEGMENT_TOWER_SKIPPED: 98F 即最深层（砍层模式），"
			+ "98—95/94—90/89—85 三区段前提不成立"
		)
		print(
			"  实测：计划层索引=%s；_floor_room_ids 层索引=%s；generate_through_floor_for_test(85)=%s"
			% [str(plan_snapshots.keys()), str(floor_rooms.keys()), str(reached_85)]
		)
		tower.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
		return
	if not reached_85:
		failures.append("真实塔楼无法连续提交到85层")
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
