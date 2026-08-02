extends Node

const PREVIEW_PATH := "res://outputs/verification/player_2d_states.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout

	var gallery := get_node_or_null("PlayerPresentationGallery") as PlayerPresentationGallery
	if gallery == null or gallery.get_display_count() != 6:
		failures.append("presentation gallery does not expose six player states")
	else:
		for player_node in get_tree().get_nodes_in_group("player"):
			var player := player_node as Player
			if player == null:
				continue
			var renderer := player.get_node_or_null("Components/Body/AvatarRenderer") as PlayerAvatarRenderer
			if renderer == null:
				failures.append("player is missing PlayerAvatarRenderer")
				continue
			var snapshot := renderer.get_visual_state_snapshot()
			if not bool(snapshot.get("pixel_assets_loaded", false)):
				failures.append("pixel component textures are not loaded")
			if int(snapshot.get("component_count", 0)) != 4:
				failures.append("renderer does not expose four modular parts")
			if int(snapshot.get("visible_hand_count", 0)) != 1:
				failures.append("renderer does not expose exactly one visible hand")
			if bool(snapshot.get("hand_tracks_aim", true)):
				failures.append("visible hand still tracks aim rotation")
			var hand_position: Vector2 = snapshot.get("hand_position", Vector2.ZERO)
			if not is_equal_approx(absf(hand_position.x), 19.0):
				failures.append("visible hand is not using the inward mirrored body socket")
			if absf(float(snapshot.get("hand_rotation", 99.0))) > 0.01:
				failures.append("visible hand rotates with the crosshair")
			var facing_sign := float(snapshot.get("facing_sign", 0.0))
			if not is_equal_approx(signf(hand_position.x), facing_sign):
				failures.append("visible hand does not follow the body's left/right facing")
			if player.components == null or player.components.hand == null or player.components.left_hand != null:
				failures.append("semantic component system is not using the single-hand player contract")

	var aim_test_player: Player = null
	for player_node in get_tree().get_nodes_in_group("player"):
		var candidate := player_node as Player
		if candidate != null and candidate.get_state_machine_state() == "idle":
			aim_test_player = candidate
			break
	if aim_test_player == null:
		failures.append("gallery does not contain an idle player for aim isolation test")
	else:
		var aim_node := aim_test_player.get_node_or_null("Aim") as Node
		if aim_node != null:
			aim_node.set_process(false)
		var renderer := aim_test_player.get_node_or_null("Components/Body/AvatarRenderer") as PlayerAvatarRenderer
		var weapon_anchor := aim_test_player.get_node_or_null("WeaponAnchor") as Marker2D
		var weapon_display := aim_test_player.get_node_or_null("WeaponAnchor/WeaponDisplay") as Node2D
		if renderer == null or weapon_anchor == null or weapon_display == null:
			failures.append("aim isolation test cannot resolve hand renderer, weapon socket, or weapon display")
		else:
			aim_test_player.set_aim_direction(Vector2.RIGHT)
			await get_tree().process_frame
			await get_tree().process_frame
			var right_snapshot := renderer.get_visual_state_snapshot()
			var right_socket_x := weapon_anchor.position.x
			aim_test_player.set_aim_direction(Vector2.LEFT)
			await get_tree().process_frame
			await get_tree().process_frame
			var left_snapshot := renderer.get_visual_state_snapshot()
			var left_socket_x := weapon_anchor.position.x
			var left_weapon_rotation := weapon_display.rotation
			aim_test_player.set_aim_direction(Vector2.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			var up_snapshot := renderer.get_visual_state_snapshot()
			var right_hand_position: Vector2 = right_snapshot.get("hand_position", Vector2.ZERO)
			var left_hand_position: Vector2 = left_snapshot.get("hand_position", Vector2.ZERO)
			var up_hand_position: Vector2 = up_snapshot.get("hand_position", Vector2.ZERO)
			if not is_equal_approx(right_hand_position.x, 19.0) or not is_equal_approx(right_socket_x, 24.0):
				failures.append("right-facing body does not place hand and weapon in right-side sockets")
			if not is_equal_approx(left_hand_position.x, -19.0) or not is_equal_approx(left_socket_x, -24.0):
				failures.append("left-facing body does not mirror hand and weapon sockets")
			if not bool(left_snapshot.get("hand_flipped", false)):
				failures.append("left-facing hand texture is not mirrored with the body")
			if not is_equal_approx(up_hand_position.x, -19.0) or not is_equal_approx(weapon_anchor.position.x, -24.0):
				failures.append("vertical aim does not preserve the body's previous facing side")
			if absf(float(right_snapshot.get("hand_rotation", 99.0))) > 0.01 or absf(float(left_snapshot.get("hand_rotation", 99.0))) > 0.01 or absf(float(up_snapshot.get("hand_rotation", 99.0))) > 0.01:
				failures.append("crosshair direction still rotates the visible hand")
			if absf(angle_difference(left_weapon_rotation, Vector2.LEFT.angle())) > 0.01:
				failures.append("weapon display no longer aims left after socket mirroring")
			if absf(angle_difference(weapon_display.rotation, Vector2.UP.angle())) > 0.01:
				failures.append("weapon display no longer rotates independently toward the crosshair")

	var dead_player: Player = null
	for player_node in get_tree().get_nodes_in_group("player"):
		var candidate := player_node as Player
		if candidate != null and candidate.get_state_machine_state() == "dead":
			dead_player = candidate
			break
	if dead_player == null:
		failures.append("gallery does not contain terminal dead state")
	else:
		var machine := dead_player.get("_state_machine") as StateMachine
		if machine.can_transition_to("idle") or machine.transition_to("idle"):
			failures.append("dead terminal state accepts an illegal transition to idle")
		var state_snapshot := dead_player.get_state_machine_snapshot()
		if not bool(state_snapshot.get("rules_enabled", false)):
			failures.append("player state transition whitelist is not enabled")

	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("viewport preview image is empty")
	else:
		var save_error := image.save_png(PREVIEW_PATH)
		if save_error != OK:
			failures.append("cannot save pixel art preview")

	if failures.is_empty():
		print("PLAYER_PIXEL_ART_FLOW_OK: four sprite components, one inward mirrored hand socket, weapon-only continuous aim rotation, six-state preview, terminal-state guard")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
