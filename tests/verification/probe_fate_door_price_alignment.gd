extends Node3D
## 只读探针：核对「第几次开命运门」与「刚清完哪间房」的对应关系，以及该门报价基准是否落在同一间房。
## 不改任何运行数据。

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var dungeon := load("res://scenes/ExpeditionLevel01_3D.tscn").instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for i in range(6):
		await get_tree().process_frame
	var economy: RefCounted = dungeon.get("_fate_economy")
	var snapshot: Dictionary = economy.get_snapshot()
	print("SEGMENTS=", JSON.stringify(snapshot.get("segment_income_expected", [])))
	for row_value in snapshot.get("door_price_table", []) as Array:
		var row: Dictionary = row_value as Dictionary
		print(
			"PRICE_TABLE door=%d segment=%d base=%d prices=%s" % [
				int(row.get("door", 0)), int(row.get("segment_index", -1)),
				int(row.get("base", 0)), JSON.stringify(row.get("prices", []))
			]
		)

	var rooms: Dictionary = dungeon.get("_room_by_id")
	var ids: Array = []
	for key in rooms.keys():
		ids.append(str(key))
	ids.sort()
	print("ROOMS=", JSON.stringify(ids))

	# 逐条主路边：起点安全屋→第一间内容房，之后各房间串联。
	var current: String = str(dungeon.get("_current_room_id"))
	print("START_ROOM=", current)
	var door_index := 0
	var visited: Dictionary = {current: true}
	while door_index < 12:
		var room: DungeonRoom3D = rooms.get(current)
		if room == null:
			break
		var targets: Dictionary = room.door_targets
		var next_id := ""
		for direction in targets.keys():
			var candidate := str(targets[direction])
			if candidate.is_empty() or visited.has(candidate):
				continue
			next_id = candidate
			break
		if next_id.is_empty():
			break
		var edge := "%s|%s" % [current, next_id]
		var policy: Dictionary = dungeon.call("_door_policy_towards", current, next_id)
		print(
			"EDGE %s -> %s triggers_fate=%s clear=%s" % [
				current, next_id, str(policy.get("triggers_fate", true)),
				str(policy.get("requires_clear", true))
			]
		)
		if bool(policy.get("triggers_fate", true)):
			door_index += 1
			var segment: int = int(economy.price_segment_index_for_door(door_index))
			print(
				"FATE_DOOR #%d after clearing %s -> segment=%d" % [door_index, current, segment]
			)
		visited[next_id] = true
		current = next_id
		if door_index >= 6:
			break
	print("PROBE_DONE failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
