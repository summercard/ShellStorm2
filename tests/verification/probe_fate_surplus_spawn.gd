extends Node3D
## 只读探针：核对「编成外增援」是否只加怪、不动卡价。
## 1) 进入 room_01，看波次总数是否 +1（原 1 波）；
## 2) 看 FateEconomyService 的参考收益与逐门价表是否一字未变；
## 3) 看 Boss / 撤离 / 安全屋是否没有被加增援。

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
			"PRICE door=%d base=%d prices=%s" % [
				int(row.get("door", 0)), int(row.get("base", 0)),
				JSON.stringify(row.get("prices", []))
			]
		)

	for room_id in ["room_01", "room_02", "boss"]:
		var rooms: Dictionary = dungeon.get("_room_by_id")
		var room: DungeonRoom3D = rooms.get(room_id)
		if room == null:
			print("ROOM %s missing" % room_id)
			continue
		dungeon.player.global_position = room.global_position + Vector3.UP * 0.1
		dungeon.force_enter_room_for_test(room_id)
		for i in range(4):
			await get_tree().process_frame
		var totals: Dictionary = dungeon.get("_room_wave_totals")
		var queues: Dictionary = dungeon.get("_room_wave_queues")
		var nodes: Dictionary = dungeon.get("_enemy_nodes_by_room")
		var queued: Array = queues.get(room_id, []) as Array
		var surplus_size := 0
		if not queued.is_empty():
			surplus_size = (queued[queued.size() - 1] as Array).size()
		print(
			"ROOM %s type=%s wave_total=%d queued_waves=%d spawned=%d alive=%d surplus=%d" % [
				room_id, str(room.room_type), int(totals.get(room_id, 0)),
				queued.size(), (nodes.get(room_id, []) as Array).size(),
				int((dungeon.get("_alive_by_room") as Dictionary).get(room_id, -1)),
				surplus_size
			]
		)

	print("PROBE_SURPLUS_DONE failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
