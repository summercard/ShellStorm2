extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path != "res://scenes/TowerDescent3D.tscn":
		failures.append("Project entry is not the PH34 tower-descent scene")

	var base_scene := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	if base_scene == null:
		failures.append("BaseWorld3D scene does not load")
		_finish(failures, 0)
		return

	LevelSelect.return_entrance_id = "spore_depths_gate"
	var base_world := base_scene.instantiate() as BaseWorld3D
	add_child(base_world)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var node_count := _count_nodes(base_world)
	# Bunny01 v002 adds evaluated left/right hands, two ear sockets and independent feet.
	# Keep a small, deliberate ceiling above the measured 391-node baseline.
	if node_count > 405:
		failures.append("BaseWorld3D first slice is unexpectedly heavy: %d nodes" % node_count)
	if base_world.get_facility_count() != 8:
		failures.append("BaseWorld3D does not expose seven lobby functions plus the training range")
	if base_world.get_dungeon_entrance_count() != 4:
		failures.append("BaseWorld3D does not expose four roadside dungeon entrances")
	if base_world.player == null or base_world.player.combat_enabled:
		failures.append("BaseWorld3D player is missing or can shoot inside the hub")
	if base_world.player.camera.get_parent() != base_world.player or not base_world.player.camera.current:
		failures.append("3D camera does not follow the CharacterBody3D player")

	var environment_snapshot := base_world.get_environment_snapshot()
	if not bool(environment_snapshot.get("is_3d", false)):
		failures.append("Base world environment is not a 3D kit")
	if int(environment_snapshot.get("module_count", 0)) < 70:
		failures.append("BaseWorld3D environment kit has too few modular pieces")
	if int(environment_snapshot.get("ruin_count", 0)) < 6:
		failures.append("BaseWorld3D wilderness lacks ruin silhouettes")
	if int(environment_snapshot.get("barrier_count", 0)) < 4:
		failures.append("BaseWorld3D wilderness lacks roadside barriers")
	if int(environment_snapshot.get("light_count", 0)) < 8:
		failures.append("BaseWorld3D lacks sparse navigation lights")

	var player_snapshot := base_world.player.get_state_machine_snapshot()
	if int(player_snapshot.get("states", []).size()) != 8:
		failures.append("Player3D state machine does not expose eight top-level states")
	if not bool(player_snapshot.get("rules_enabled", false)):
		failures.append("Player3D state machine does not use explicit transition rules")
	var avatar_snapshot := base_world.player.avatar.get_component_snapshot()
	if int(avatar_snapshot.get("component_count", 0)) != 4:
		failures.append("Player3D avatar does not preserve four modular visual components")
	if int(avatar_snapshot.get("visible_hand_count", 0)) != 2 or not bool(avatar_snapshot.get("has_weapon_socket", false)):
		failures.append("Player3D avatar does not preserve the two-hand/weapon-socket contract")

	var return_gate := base_world.get_node_or_null("DungeonEntrances/Dungeon03") as DungeonEntrance3D
	if return_gate == null or base_world.player.global_position.distance_to(return_gate.global_position + Vector3(0, 0, 2.8)) > 0.05:
		failures.append("Returning from a dungeon does not restore Player3D outside its entrance")
	if not LevelSelect.return_entrance_id.is_empty():
		failures.append("Dungeon return entrance state is not consumed")

	var entrance_ids: Dictionary = {}
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if not entrance is DungeonEntrance3D or not base_world.is_ancestor_of(entrance):
			continue
		if entrance_ids.has(entrance.entrance_id):
			failures.append("Two 3D dungeon entrances share id %s" % entrance.entrance_id)
		entrance_ids[entrance.entrance_id] = true
		if not ResourceLoader.exists(entrance.target_scene_path, "PackedScene"):
			failures.append("3D dungeon entrance points to missing scene: %s" % entrance.target_scene_path)

	var training_range := base_world.get_node_or_null("Facilities/TrainingRange") as BaseFacility3D
	if training_range == null or training_range.activation_type != BaseFacility3D.ActivationType.LOAD_SCENE or training_range.target_scene_path != "res://scenes/TrainingRange3D.tscn":
		failures.append("3D training facility does not point to the independent 3D training scene")
	var base_console := base_world.get_node_or_null("Facilities/BaseConsole") as BaseFacility3D
	if base_console == null:
		failures.append("3D base management terminal is missing")
	else:
		base_world.call("_on_facility_activated", base_console)
		await get_tree().process_frame
		var console_menu := base_world.get_active_menu()
		if console_menu == null or not console_menu is BaseMenu:
			failures.append("3D base terminal does not open the existing management overlay")
		else:
			if not console_menu.overlay_mode or not console_menu.close_overlay_button.visible:
				failures.append("3D base management overlay cannot return to the world")
			await _tap_action("pause")
			await get_tree().process_frame
			if base_world.get_active_menu() != null or get_tree().paused:
				failures.append("Esc does not close the base facility menu before pausing")
		if base_world.player.input_locked:
			failures.append("Closing a 3D facility menu leaves player input locked")
	var pause_overlay := base_world.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	if pause_overlay == null:
		failures.append("BaseWorld3D has no reusable visible pause overlay")
	else:
		await _tap_action("pause")
		if not get_tree().paused or not pause_overlay.is_pause_open():
			failures.append("BaseWorld3D Esc does not open a visible real pause")
		await _tap_action("pause")
		if get_tree().paused or pause_overlay.is_pause_open():
			failures.append("BaseWorld3D second Esc does not resume")

	# 八态动态契约：地面动作、下落、落地与死亡都由同一个 StateMachine 驱动表现。
	base_world.player.set_test_move_direction(Vector3.RIGHT)
	await get_tree().physics_frame
	await get_tree().process_frame
	if base_world.player.get_state_machine_state() != "moving":
		failures.append("Player3D does not enter moving from 3D input")
	var moving_before := base_world.player.avatar.get_component_snapshot()
	await get_tree().create_timer(0.14).timeout
	var moving_after := base_world.player.avatar.get_component_snapshot()
	if (
		not bool(moving_after.get("moving_animation_active", false))
		or is_equal_approx(float(moving_before.get("locomotion_cycle", 0.0)), float(moving_after.get("locomotion_cycle", 0.0)))
		or (moving_before.get("body_scale", Vector3.ONE) as Vector3).distance_to(moving_after.get("body_scale", Vector3.ONE) as Vector3) < 0.005
	):
		failures.append("Player3D moving state has no independent locomotion animation cycle")
	if (
		str(moving_after.get("weapon_pose_state", "")) != "sidearm_run"
		or int(moving_after.get("active_grip_hand_count", 0)) != 1
		or float(moving_before.get("hand_r_to_socket_global_distance", 999.0)) > 0.36
		or float(moving_after.get("hand_r_to_socket_global_distance", 999.0)) > 0.36
	):
		failures.append("Locomotion animation breaks the pistol's independent right-hand run grip")
	base_world.player.request_dash()
	await get_tree().process_frame
	await get_tree().process_frame
	if base_world.player.get_state_machine_state() != "dashing" or not base_world.player.avatar.get_component_snapshot().get("dash_trail_visible", false):
		failures.append("Player3D dash state does not drive the 3D trail")
	await get_tree().create_timer(0.24).timeout
	base_world.player.set_test_move_direction(Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().process_frame
	if base_world.player.get_state_machine_state() != "idle":
		failures.append("Player3D does not return to idle after locomotion")
	base_world.player.set_input_locked(true)
	await get_tree().process_frame
	if base_world.player.get_state_machine_state() != "locked" or not base_world.player.avatar.get_component_snapshot().get("lock_ring_visible", false):
		failures.append("Player3D locked state does not drive the amber ring")
	base_world.player.set_input_locked(false)
	await get_tree().physics_frame
	await get_tree().create_timer(0.28).timeout
	base_world.player.take_damage(12)
	await get_tree().process_frame
	if base_world.player.get_state_machine_state() != "hurt":
		failures.append("Player3D damage does not enter hurt state")
	await get_tree().create_timer(0.30).timeout
	base_world.player.take_damage(999)
	await get_tree().process_frame
	if base_world.player.get_state_machine_state() != "dead":
		failures.append("Player3D lethal damage does not enter dead state")
	var machine := base_world.player.get("_state_machine") as StateMachine
	if machine.can_transition_to("idle") or machine.transition_to("idle"):
		failures.append("Player3D dead terminal state accepts an illegal transition")

	base_world.queue_free()
	await get_tree().process_frame
	_finish(failures, node_count)


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _tap_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame


func _finish(failures: Array[String], node_count: int) -> void:
	if failures.is_empty():
		print("BASE_WORLD_3D_FLOW_OK: compatibility hub, modular environment, four-component player, eight-state contract, facilities, gates, and return flow pass (nodes=%d)" % node_count)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
