extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var demo_scene: PackedScene = load("res://scenes/DemoRoomChain.tscn") as PackedScene
	if demo_scene == null:
		failures.append("DemoRoomChain scene does not load")
	else:
		var demo: Node = demo_scene.instantiate()
		add_child(demo)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.7).timeout
		await _validate_demo_flow(demo, failures)
		demo.queue_free()
		await get_tree().process_frame

	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		failures.append("Main scene does not load")
	else:
		var main: Node = main_scene.instantiate()
		add_child(main)
		await get_tree().process_frame
		await get_tree().process_frame
		var boss: Node = get_tree().root.find_child("BossActor", true, false)
		if boss == null:
			failures.append("Main flow does not instantiate a readable Boss encounter")
		main.queue_free()
		await get_tree().process_frame

	if failures.is_empty():
		print("P0_PLAYER_FLOW_OK: Demo chain starts, door flow advances, Boss encounter loads")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(1 if not failures.is_empty() else 0)

func _validate_demo_flow(demo: Node, failures: Array[String]) -> void:
	await _wait_for_demo_transition(demo)
	var player: Node = demo.get("_player")
	if player == null:
		failures.append("Demo starts without a player")
		return
	var camera := demo.get("_camera") as Camera2D
	if camera == null or camera.get_parent() != player:
		failures.append("Demo camera does not follow the player across rooms")
	var ui := demo.get_node_or_null("GameUIManager") as GameUIManager
	if ui == null or ui.get("_room_game_mode") != demo:
		failures.append("Demo does not bind its HUD to the active game mode")

	var room_zero: Node = demo.get("_room_instances").get(0)
	var first_door: Area2D = room_zero.get_node_or_null("Door_to_1") as Area2D if room_zero != null else null
	if first_door == null:
		failures.append("First room has no forward door")
		return

	demo.call("_on_waves_cleared", 0)
	var fate_controller: Control = demo.call("_get_fate_card_controller") as Control
	if fate_controller != null:
		fate_controller.call("hide_card_selection")
	demo.call("_on_door_body_entered", player, first_door, 0, 1)
	var near_door: Dictionary = demo.get("_near_door")
	if near_door.is_empty():
		failures.append("Player standing at a cleared-room door does not get an interaction target")
		return

	var opened: bool = bool(demo.call("_try_open_door", 0, 1))
	if not opened:
		failures.append("Cleared first-room door cannot be opened")
		return

	await _wait_for_demo_transition(demo)
	var current_room_id: int = int(demo.get("_current_room_id"))
	var key_count: int = int(demo.get("_room_key_count"))
	if current_room_id != 1:
		failures.append("Opening the first door does not advance the player to room 1")
	if key_count != 1:
		failures.append("Door progression does not preserve the expected key economy after room 1 entry")
	if camera != null and camera.global_position.distance_to(player.global_position) > 1.0:
		failures.append("Demo camera loses the player after advancing rooms")


func _wait_for_demo_transition(demo: Node) -> void:
	for i in range(40):
		await get_tree().create_timer(0.05).timeout
		if not bool(demo.get("_is_transitioning")):
			return
