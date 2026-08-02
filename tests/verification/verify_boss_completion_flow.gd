extends Node

## Boss completion is a cross-system contract, not a scene-local animation:
## bullet collision -> BossActor -> BossRoomDirector -> extraction unlock.
## Keep this test at the public scene level so future asset replacements cannot
## silently remove the actor collision or disconnect the settlement bridge.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	var bullet_scene := load("res://scenes/Bullet.tscn") as PackedScene
	if main_scene == null or bullet_scene == null:
		_finish(["Main or Bullet scene does not load"])
		return

	var main := main_scene.instantiate()
	add_child(main)
	await _frames(3)

	var mode := main.get_node_or_null("RoomGameMode") as RoomGameMode
	if mode == null or mode.map_manager == null:
		_finish(["Main did not create RoomGameMode and MapManager"])
		return
	var graph := mode.map_manager.get_graph()
	var boss_room_id := _find_room_id(graph, RoomData.RoomType.BOSS)
	if boss_room_id < 0:
		_finish(["Generated chapter map has no boss room"])
		return

	# Tests jump to the boss room deliberately; regular play still uses doors.
	mode.call("_set_room_revealed", boss_room_id, true)
	var from_room_id: int = mode.map_manager.get_current_room_id()
	mode.call("_enter_room_by_id", boss_room_id, from_room_id)
	await _frames(4)

	var boss_room: Node2D = mode.map_manager.get_instantiated_room(boss_room_id)
	var actor := boss_room.get_node_or_null("BossActor") as BossActor if boss_room != null else null
	if actor == null:
		failures.append("Boss room has no BossActor")
	else:
		var collider := actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collider == null or collider.shape == null:
			failures.append("BossActor has no collision shape for player bullets")
		elif not (collider.shape is CircleShape2D):
			failures.append("BossActor collision shape is not a replaceable primitive")
		if actor._state_machine == null or actor._state_machine.current_state_name != "combat":
			failures.append("BossActor was not activated when entering its room")
		else:
			var bullet := bullet_scene.instantiate()
			main.add_child(bullet)
			bullet.call(
				"fire",
				actor.global_position - Vector2(130.0, 0.0),
				Vector2.RIGHT,
				1200.0,
				int(actor.max_hp) + 1,
				true
			)
			await _physics_frames(12)

			if not actor._is_dead:
				failures.append("A player bullet cannot complete the BossActor encounter")

	var director := mode.map_manager.boss_director
	if director == null or not director.is_boss_defeated():
		failures.append("BossActor defeat does not settle BossRoomDirector progress")
	elif not _has_unlocked_boss_extraction(mode.map_manager.extraction_director):
		failures.append("Boss defeat does not unlock the BOSS_KILL extraction")

	main.queue_free()
	# Let scene-tree-owned defeat tweens/timers settle before ending the process;
	# this keeps a successful lifecycle test from manufacturing shutdown warnings.
	await get_tree().process_frame
	await VerificationClock.wait(self, 1.25)
	await get_tree().process_frame
	_finish(failures)


func _find_room_id(graph: NodeGraph, room_type: RoomData.RoomType) -> int:
	if graph == null:
		return -1
	for node in graph.get_all_nodes():
		if node.room_data != null and node.room_data.room_type == room_type:
			return int(node.id)
	return -1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _has_unlocked_boss_extraction(director: ExtractionDirector) -> bool:
	if director == null:
		return false
	return not director.get_points_by_type(
		ExtractionDirector.ExtractionType.BOSS_KILL, true
	).is_empty()


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BOSS_COMPLETION_FLOW_OK: player bullet settles boss, rewards and BOSS_KILL extraction")
		VerificationQuitter.schedule(self, 0)
	else:
		for failure in failures:
			push_error(failure)
		VerificationQuitter.schedule(self, 1)
