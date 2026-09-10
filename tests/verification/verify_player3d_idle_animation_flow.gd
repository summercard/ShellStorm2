extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	# 本专项没有地面；必须在首个物理帧前冻结，保持顶层状态为 idle。
	player.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
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
	if str(idle_b.get("authored_motion_clip", "")) != "armed_idle":
		failures.append("Standing armed player is not sampling the authored armed_idle clip")
	if bool(idle_b.get("legacy_procedural_motion_enabled", true)):
		failures.append("Standing player still enables the legacy procedural idle generator")
	if (
		(idle_a.get("body_position", Vector3.ZERO) as Vector3)
		.distance_to(idle_b.get("body_position", Vector3.ZERO) as Vector3) < 0.002
	):
		failures.append("Authored idle lacks readable body breathing motion")
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
	) < 0.008:
		failures.append("Idle animation lacks asymmetric ear follow/flick")
	if (
		str(idle_b.get("weapon_pose_state", "")) != "sidearm_hold"
		or int(idle_b.get("active_grip_hand_count", 0)) != 1
		or float(idle_b.get("hand_r_to_socket_global_distance", 999.0)) > 0.195
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
		or str(moving.get("authored_motion_clip", "")) != "armed_moving"
	):
		failures.append("Movement does not immediately switch from authored idle to authored jog")

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
		print("BUNNY_IDLE_ANIMATION_OK: Blender-only idle motion, ear follow, grip stability, and locomotion exit pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
