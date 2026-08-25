extends Node

const GALLERY_SCENE: PackedScene = preload("res://scenes/Player3DStateGallery.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var gallery := GALLERY_SCENE.instantiate() as Player3DStateGallery
	add_child(gallery)
	await get_tree().process_frame
	await get_tree().process_frame
	gallery.set_physics_process(false)
	gallery.player.set_physics_process(false)
	gallery.player.avatar.set_process(false)

	gallery.player.avatar.call("_process", 0.10)
	var snapshot := gallery.player.avatar.get_component_snapshot()
	if str(snapshot.get("assembly_version", "")) != "v008":
		failures.append("Bunny v008 is not the active Player3D asset")
	if (
		float(snapshot.get("left_hand_ring_to_joint_global_distance", 999.0)) > 0.001
		or float(snapshot.get("right_hand_ring_to_joint_global_distance", 999.0)) > 0.001
	):
		failures.append("HandJointL/R are not centered on their cuff rings")
	if (
		float(snapshot.get("ear_l_root_to_socket_global_distance", 999.0)) > 0.001
		or float(snapshot.get("ear_r_root_to_socket_global_distance", 999.0)) > 0.001
	):
		failures.append("EarSocketL/R are not centered on the ear-base contact points")
	if (
		gallery.player.get_state_machine_state() != "idle"
		or not bool(snapshot.get("idle_animation_active", false))
		or not bool(snapshot.get("idle_state_machine_owned", false))
	):
		failures.append("The current avatar idle state does not own the standing animation")
	if (
		not bool(snapshot.get("weapon_grip_pose_active", false))
		or str(snapshot.get("weapon_pose_state", "")) != "sidearm_hold"
		or int(snapshot.get("active_grip_hand_count", 0)) != 1
			or float(snapshot.get("hand_r_to_socket_global_distance", 999.0)) > 0.189
			or float(snapshot.get("hand_l_to_socket_global_distance", 0.0)) < 0.180
	):
		failures.append("Pistol does not keep its one-hand right-side grip and free left hand")
	if not gallery.player.equip_weapon("bp_rifle", "mod_bullet_standard"):
		failures.append("Rifle could not be equipped for the two-hand grip check")
	else:
		gallery.player.avatar.call("_process", 0.10)
		snapshot = gallery.player.avatar.get_component_snapshot()
		if (
			str(snapshot.get("weapon_pose_state", "")) != "longgun_hold"
			or int(snapshot.get("active_grip_hand_count", 0)) != 2
				or float(snapshot.get("hand_l_to_socket_global_distance", 999.0)) > 0.255
				or float(snapshot.get("hand_r_to_socket_global_distance", 999.0)) > 0.189
		):
			failures.append("Rifle does not converge on right grip plus left support")

	gallery.run_player_action("dashing")
	# v0.1 的翻滚周期为位移周期的 1.3 倍；90 ms 才进入约 34% 的收腹关键帧。
	gallery.player.avatar.call("_process", 0.09)
	snapshot = gallery.player.avatar.get_component_snapshot()
	var dash_scale := snapshot.get("visual_scale", Vector3.ONE) as Vector3
	if (
		not bool(snapshot.get("dash_roll_active", false))
		or float(snapshot.get("dash_roll_progress", 0.0)) < 0.30
		or absf(float(snapshot.get("visual_pitch", 0.0))) < 1.0
		or dash_scale.y > 0.82
		or dash_scale.z < 1.35
	):
		failures.append("Dash does not show the exaggerated full-roll tuck key pose")

	gallery.run_player_action("hurt")
	gallery.player.avatar.call("_process", 0.06)
	snapshot = gallery.player.avatar.get_component_snapshot()
	var hurt_scale := snapshot.get("visual_scale", Vector3.ONE) as Vector3
	var head_rotation := snapshot.get("head_rotation", Vector3.ZERO) as Vector3
	var foot_l_rotation := snapshot.get("foot_l_rotation", Vector3.ZERO) as Vector3
	var foot_r_rotation := snapshot.get("foot_r_rotation", Vector3.ZERO) as Vector3
	if (
		not bool(snapshot.get("hurt_keyframe_active", false))
		or float(snapshot.get("hurt_animation_progress", 0.0)) <= 0.10
		or hurt_scale.y > 0.90
		or head_rotation.length() < 0.25
		or maxf(foot_l_rotation.length(), foot_r_rotation.length()) < 0.20
	):
		failures.append("Hurt animation lacks the squash, head whip, and foot recoil key pose")

	gallery.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BUNNY_V008_ANIMATION_FLOW_OK: ring-centered hands, hood-contact-centered ears, idle, grip, dash, and hurt key poses pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
