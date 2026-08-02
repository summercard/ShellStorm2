extends Node2D

const PROBE_SAVE_PATH := "user://framework_health_probe.json"

class FakeSynth:
	extends Node
	var calls: Array[String] = []

	func play_fate_card() -> void:
		calls.append("fate_card")

	func play_extraction_abort() -> void:
		calls.append("extraction_abort")

func _ready() -> void:
	var failures: Array[String] = []
	_verify_pause_ownership(failures)
	_verify_stairs_runtime_configuration(failures)
	_verify_seeded_map_contract(failures)
	_verify_atomic_json_recovery(failures)
	_verify_synth_audio_fallback(failures)
	_cleanup_probe_files()
	await get_tree().process_frame
	_finish(failures)

func _verify_pause_ownership(failures: Array[String]) -> void:
	Global.clear_pause_reasons()
	Global.acquire_pause("framework_probe_a")
	Global.acquire_pause("framework_probe_b")
	Global.release_pause("framework_probe_a")
	if not Global.is_paused or not get_tree().paused:
		failures.append("Releasing one pause owner resumed the tree while another owner remained")
	Global.release_pause("framework_probe_b")
	if Global.is_paused or get_tree().paused:
		failures.append("Releasing the final pause owner did not resume the tree")

func _verify_stairs_runtime_configuration(failures: Array[String]) -> void:
	var factory := RoomFactory.new()
	var mode := RoomGameMode.new()
	var up_data := RoomData.new(RoomData.RoomType.STAIRS_UP, 1)
	var down_data := RoomData.new(RoomData.RoomType.STAIRS_DOWN, 1)
	var up_room := factory.create_room(up_data, self)
	var down_room := factory.create_room(down_data, self)
	var up_stairs := up_room.get_node_or_null("StairsArea/StairsInteraction") as StairsInteraction
	var down_stairs := down_room.get_node_or_null("StairsArea/StairsInteraction") as StairsInteraction
	if up_stairs == null or up_stairs.direction != "up" or up_stairs.target_vertical != 1:
		failures.append("STAIRS_UP room did not configure its nested interaction for the upper level")
	if down_stairs == null or down_stairs.direction != "down" or down_stairs.target_vertical != -1:
		failures.append("STAIRS_DOWN room did not configure its nested interaction for the basement")
	var nested_stairs: Array = mode.call("_get_stairs_interactions", up_room)
	if nested_stairs.size() != 1 or nested_stairs[0] != up_stairs:
		failures.append("RoomGameMode did not discover nested stairs interactions")
	up_room.queue_free()
	down_room.queue_free()
	mode.free()

func _verify_seeded_map_contract(failures: Array[String]) -> void:
	var first := MapManager.new()
	var second := MapManager.new()
	var first_graph := first.generate_map(4, 424242)
	var second_graph := second.generate_map(4, 424242)
	if first.map_generator.debug_map(first_graph) != second.map_generator.debug_map(second_graph):
		failures.append("Fixed seed did not reproduce the same map graph")
	var before := _serialize_enemy_plans(first, first_graph)
	if before != _serialize_enemy_plans(second, second_graph):
		failures.append("Fixed seed did not reproduce the same injected enemy plans")
	first.instantiate_map(self)
	if before != _serialize_enemy_plans(first, first_graph):
		failures.append("Instantiating a generated map changed its enemy plans")
	first.clear_all_rooms()
	first.free()
	second.free()

func _serialize_enemy_plans(manager: MapManager, graph: NodeGraph) -> String:
	var plans: Dictionary = {}
	for node in graph.get_all_nodes():
		plans[node.id] = manager.get_room_enemy_plan(node.id)
	return JSON.stringify(plans)

func _verify_atomic_json_recovery(failures: Array[String]) -> void:
	_cleanup_probe_files()
	if not AtomicJsonStore.save_dictionary(PROBE_SAVE_PATH, {"generation": 1}):
		failures.append("Atomic JSON store could not create a probe save")
		return
	var main_path := ProjectSettings.globalize_path(PROBE_SAVE_PATH)
	var backup_path := ProjectSettings.globalize_path(PROBE_SAVE_PATH + ".bak")
	if DirAccess.rename_absolute(main_path, backup_path) != OK:
		failures.append("Atomic JSON probe could not prepare a backup")
		return
	var broken := FileAccess.open(PROBE_SAVE_PATH, FileAccess.WRITE)
	if broken == null:
		failures.append("Atomic JSON probe could not create a damaged primary file")
		return
	broken.store_string("{broken")
	broken.close()
	var recovered: Variant = AtomicJsonStore.load_dictionary(PROBE_SAVE_PATH)
	if not recovered is Dictionary or int(recovered.get("generation", 0)) != 1:
		failures.append("Atomic JSON store did not recover from its backup")

func _verify_synth_audio_fallback(failures: Array[String]) -> void:
	var original_synth = AudioManager.get("_synth")
	var fake := FakeSynth.new()
	add_child(fake)
	AudioManager.set("_synth", fake)
	AudioManager.play_sfx("fate_card")
	AudioManager.play_sfx("extraction_abort")
	if fake.calls != ["fate_card", "extraction_abort"]:
		failures.append("Empty-path procedural SFX do not reach the synth fallback")
	AudioManager.set("_synth", original_synth)
	fake.queue_free()

func _cleanup_probe_files() -> void:
	for path in [PROBE_SAVE_PATH, PROBE_SAVE_PATH + ".tmp", PROBE_SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _finish(failures: Array[String]) -> void:
	Global.clear_pause_reasons()
	if failures.is_empty():
		print("FRAMEWORK_HEALTH_FLOW_OK: pause, stairs, seeded injection, atomic saves, and synth SFX fallback are coherent")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
