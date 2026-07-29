extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.get_node("Camera3D").current = false

	player.avatar.call("_process", 0.10)
	var idle_a := player.avatar.get_component_snapshot()
	player.avatar.call("_process", 0.55)
	var idle_b := player.avatar.get_component_snapshot()
	if player.get_state_machine_state() != "idle" or str(idle_b.get("state", "")) != "idle":
		failures.append("Standing player is not owned by the top-level idle state")
	if not bool(idle_b.get("idle_animation_active", false)) or not bool(idle_b.get("idle_state_machine_owned", false)):
		failures.append("Idle state does not activate the formal standing animation")
	if absf(float(idle_b.get("idle_loop_duration_s", 0.0)) - 2.380952) > 0.01:
		failures.append("Idle loop duration is not the approved approximately 2.38 seconds")
	if is_equal_approx(float(idle_a.get("idle_cycle", 0.0)), float(idle_b.get("idle_cycle", 0.0))):
		failures.append("Idle animation cycle does not advance while standing")
	if (
		(idle_a.get("body_scale", Vector3.ONE) as Vector3)
		.distance_to(idle_b.get("body_scale", Vector3.ONE) as Vector3) < 0.012
	):
		failures.append("Idle animation lacks readable body breathing squash")
	if (
		(idle_a.get("head_rotation", Vector3.ZERO) as Vector3)
		.distance_to(idle_b.get("head_rotation", Vector3.ZERO) as Vector3) < 0.014
	):
		failures.append("Idle animation lacks delayed head weight shift")
	if maxf(
		(idle_a.get("ear_l_rotation", Vector3.ZERO) as Vector3)
			.distance_to(idle_b.get("ear_l_rotation", Vector3.ZERO) as Vector3),
		(idle_a.get("ear_r_rotation", Vector3.ZERO) as Vector3)
			.distance_to(idle_b.get("ear_r_rotation", Vector3.ZERO) as Vector3)
	) < 0.012:
		failures.append("Idle animation lacks asymmetric ear follow/flick")
	if (
		(idle_a.get("foot_l_position", Vector3.ZERO) as Vector3)
		.distance_to(idle_b.get("foot_l_position", Vector3.ZERO) as Vector3) < 0.003
		and (idle_a.get("foot_r_position", Vector3.ZERO) as Vector3)
		.distance_to(idle_b.get("foot_r_position", Vector3.ZERO) as Vector3) < 0.003
	):
		failures.append("Idle animation lacks the standing weight transfer between feet")
	if (
		str(idle_b.get("weapon_pose_state", "")) != "sidearm_hold"
		or int(idle_b.get("active_grip_hand_count", 0)) != 1
		or float(idle_b.get("hand_r_to_socket_global_distance", 999.0)) > 0.32
	):
		failures.append("Idle breathing separates the pistol's right-hand hold")

	var machine := player.get("_state_machine") as StateMachine
	player.velocity = Vector3(4.0, 0.0, 0.0)
	if not machine.transition_to("moving"):
		failures.append("Idle state could not transition to moving")
	player.avatar.call("_process", 0.10)
	var moving := player.avatar.get_component_snapshot()
	if (
		player.get_state_machine_state() != "moving"
		or bool(moving.get("idle_animation_active", true))
		or not bool(moving.get("moving_animation_active", false))
		or absf(float(moving.get("idle_breath", 1.0))) > 0.0001
	):
		failures.append("Movement does not immediately exit and zero the idle animation")

	player.velocity = Vector3.ZERO
	if not machine.transition_to("idle"):
		failures.append("Moving state could not return to idle")
	player.avatar.call("_process", 0.10)
	var returned_idle := player.avatar.get_component_snapshot()
	if (
		player.get_state_machine_state() != "idle"
		or not bool(returned_idle.get("idle_animation_active", false))
		or bool(returned_idle.get("moving_animation_active", true))
	):
		failures.append("Standing still does not reactivate idle after locomotion")

	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BUNNY_IDLE_ANIMATION_OK: state-owned standing loop, breathing, weight shift, ear follow, grip stability, and locomotion exit pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

