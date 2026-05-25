extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var mode_scene: PackedScene = load("res://scenes/DemoRoomChain.tscn") as PackedScene
	var boss_scene: PackedScene = load("res://scenes/RoomBoss.tscn") as PackedScene
	if mode_scene == null:
		failures.append("DemoRoomChain scene does not load")
	if boss_scene == null:
		failures.append("RoomBoss scene does not load")
	if not failures.is_empty():
		_finish(failures)
		return

	var mode: DemoRoomGameMode = mode_scene.instantiate() as DemoRoomGameMode
	var boss_room: Node2D = boss_scene.instantiate() as Node2D
	add_child(mode)
	add_child(boss_room)
	await get_tree().process_frame

	mode._setup_boss_room_signals(boss_room)
	mode._setup_boss_room_signals(boss_room)
	await get_tree().process_frame

	var spawn_connections := Signal(boss_room, "boss_spawn_triggered").get_connections()
	var defeated_connections := Signal(boss_room, "boss_defeated_triggered").get_connections()
	if spawn_connections.size() != 1:
		failures.append("Boss spawn signal has %d connections after repeated setup" % spawn_connections.size())
	if defeated_connections.size() != 1:
		failures.append("Boss defeated signal has %d connections after repeated setup" % defeated_connections.size())
	if not boss_room.has_method("is_boss_spawned") or not bool(boss_room.call("is_boss_spawned")):
		failures.append("Boss setup no longer triggers boss spawn")

	_finish(failures)

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("P1_BOSS_SIGNAL_FLOW_OK: Boss room setup connects root logic once and still spawns")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
