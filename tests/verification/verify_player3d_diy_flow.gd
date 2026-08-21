extends Node

const GALLERY_SCENE: PackedScene = preload("res://scenes/Player3DStateGallery.tscn")
const EXPECTED_LOADOUT := {
	"body": "suit_cobalt",
	"head": "plated_amber",
	"hand": "gauntlet_teal",
	"feet": "boot_teal",
	"hat": "hard_hat",
	"glasses": "dual_goggles",
}


func _ready() -> void:
	var failures: Array[String] = []
	var gallery := GALLERY_SCENE.instantiate() as Player3DStateGallery
	add_child(gallery)
	await get_tree().process_frame
	await get_tree().process_frame
	for control_id in ["DiyNextHat", "DiyNextGlasses", "DiyReset"]:
		if control_id not in gallery.get_control_ids():
			failures.append("Missing DIY gallery control: %s" % control_id)
	var options := gallery.player.get_avatar_customization_options()
	for slot_id in EXPECTED_LOADOUT:
		if str(EXPECTED_LOADOUT[slot_id]) not in (options.get(slot_id, []) as Array):
			failures.append("DIY option is not registered: %s/%s" % [slot_id, EXPECTED_LOADOUT[slot_id]])
		elif not gallery.set_preview_customization(slot_id, str(EXPECTED_LOADOUT[slot_id])):
			failures.append("DIY option cannot be applied: %s/%s" % [slot_id, EXPECTED_LOADOUT[slot_id]])
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	var avatar_snapshot := gallery.player.avatar.get_component_snapshot()
	var current_loadout := avatar_snapshot.get("customization", {}) as Dictionary
	for slot_id in EXPECTED_LOADOUT:
		if str(current_loadout.get(slot_id, "")) != str(EXPECTED_LOADOUT[slot_id]):
			failures.append("DIY snapshot does not retain %s" % slot_id)
	var material_counts := avatar_snapshot.get("customization_material_counts", {}) as Dictionary
	var material_colors := avatar_snapshot.get("customization_material_colors", {}) as Dictionary
	for slot_id in ["body", "head", "hand", "feet"]:
		if int(material_counts.get(slot_id, 0)) <= 0:
			failures.append("Bunny DIY slot has no live GLB material mapping: %s" % slot_id)
	var expected_colors := {
		"body": PlayerAvatar3D.BODY_COLORS[EXPECTED_LOADOUT["body"]],
		"head": PlayerAvatar3D.HEAD_COLORS[EXPECTED_LOADOUT["head"]],
		"hand": PlayerAvatar3D.HAND_COLORS[EXPECTED_LOADOUT["hand"]],
		"feet": PlayerAvatar3D.FEET_COLORS[EXPECTED_LOADOUT["feet"]],
	}
	for slot_id in expected_colors:
		var actual_color := material_colors.get(slot_id, Color.TRANSPARENT) as Color
		if not actual_color.is_equal_approx(expected_colors[slot_id] as Color):
			failures.append("Bunny DIY slot did not recolor the live GLB material: %s" % slot_id)
	if int(avatar_snapshot.get("wearable_count", 0)) < 8:
		failures.append("Hat/glasses wearable nodes were not constructed")
	if int(avatar_snapshot.get("component_count", 0)) != 4:
		failures.append("Bunny avatar does not expose head/body/hand/feet as four primary modules")
	if str(avatar_snapshot.get("avatar_profile", "")) != "bunny01":
		failures.append("Player3D does not load the registered bunny01 avatar profile")
	if str(avatar_snapshot.get("assembly_version", "")) != "v006" or str(avatar_snapshot.get("rig_type", "")) != "rigid_node_skeleton" or str(avatar_snapshot.get("component_space", "")) != "pivot_local":
		failures.append("Bunny v006 is not assembled from pivot-local parts on the Godot rigid-node skeleton")
	if int(avatar_snapshot.get("ear_count", 0)) != 2 or int(avatar_snapshot.get("ear_socket_count", 0)) != 2 or not bool(avatar_snapshot.get("ears_parented_to_head", false)):
		failures.append("Bunny ears are not two head-parented accessories on named sockets")
	if int(avatar_snapshot.get("visible_foot_count", 0)) != 2:
		failures.append("Bunny feet module does not expose two independent feet")
	if int(avatar_snapshot.get("visible_hand_count", 0)) != 2 or not bool(avatar_snapshot.get("independent_hand_animation", false)):
		failures.append("Bunny hands are not exported as two independently animated visual parts")
	if absf(float(avatar_snapshot.get("authored_scale_m", 0.0)) - 1.5) > 0.001:
		failures.append("Bunny v006 does not use the approved 1.50 m authored height")
	if absf(
		float(avatar_snapshot.get("runtime_scale_multiplier", 0.0))
		- Player3D.DEFAULT_BASE_SIZE_MULTIPLIER
	) > 0.001:
		failures.append("Bunny v006 did not apply the approved 70% entity-size baseline")
	if (
		int(avatar_snapshot.get("authored_forward_correction_degrees", 0)) != 90
		or str(avatar_snapshot.get("raw_forward_blender", "")) != "+X"
		or str(avatar_snapshot.get("runtime_forward_godot", "")) != "-Z"
		or not bool(avatar_snapshot.get("forward_contract_pass", false))
	):
		failures.append("Bunny v006 does not enforce the Blender +X to Godot -Z forward-axis contract")
	if str(avatar_snapshot.get("tail_style", "")) != "none":
		failures.append("Bunny source unexpectedly retains the legacy cat tail")
	for required_path in [
		"VisualRoot/BunnyRig/HeadJoint/Ears/EarSocketL",
		"VisualRoot/BunnyRig/HeadJoint/Ears/EarSocketR",
		"VisualRoot/BunnyRig/HandRoot/HandJointL",
		"VisualRoot/BunnyRig/HandRoot/HandJointR",
		"VisualRoot/BunnyRig/FeetRoot/FootJointL",
		"VisualRoot/BunnyRig/FeetRoot/FootJointR",
	]:
		if not gallery.player.avatar.has_node(required_path):
			failures.append("Bunny modular node is missing: %s" % required_path)
	if not gallery.player.avatar.get_node("VisualRoot/BunnyRig/HeadJoint/Wearables/HatHardHat").visible:
		failures.append("Selected hard hat is not visible")
	if not gallery.player.avatar.get_node("VisualRoot/BunnyRig/HeadJoint/Wearables/GlassesDualGoggles").visible:
		failures.append("Selected goggles are not visible")
	for wearable_path in [
		"VisualRoot/BunnyRig/HeadJoint/Wearables/HatHardHat",
		"VisualRoot/BunnyRig/HeadJoint/Wearables/GlassesDualGoggles",
	]:
		var wearable := gallery.player.avatar.get_node(wearable_path) as Node3D
		for mesh in wearable.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh as MeshInstance3D
			if mesh_instance.layers != 2:
				failures.append("DIY wearable left the avatar-only light layer: %s" % wearable_path)
			if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				failures.append("DIY wearable cannot cast shadows from external scene lights: %s" % wearable_path)
			if mesh_instance.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
				failures.append("DIY wearable can inject indirect light: %s" % wearable_path)
	var avatar_mesh_count := 0
	for mesh in gallery.player.avatar.visual_root.find_children("*", "MeshInstance3D", true, false):
		var avatar_mesh := mesh as MeshInstance3D
		avatar_mesh_count += 1
		if avatar_mesh.layers != 2:
			failures.append("Avatar mesh left the avatar-only fill-light layer: %s" % avatar_mesh.get_path())
		if avatar_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			failures.append("Avatar mesh cannot cast shadows from external scene lights: %s" % avatar_mesh.get_path())
		if avatar_mesh.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
			failures.append("Avatar mesh can inject indirect lighting: %s" % avatar_mesh.get_path())
	if (
		avatar_mesh_count <= 0
		or int(avatar_snapshot.get("avatar_shadow_caster_count", -1)) != avatar_mesh_count
	):
		failures.append("Avatar external-light shadow caster contract is incomplete")
	if not bool(avatar_snapshot.get("weapon_grip_pose_active", false)):
		failures.append("Bunny weapon grip pose is not active with an equipped gun")
	if (
		str(avatar_snapshot.get("weapon_pose_state", "")) != "sidearm_hold"
		or int(avatar_snapshot.get("active_grip_hand_count", 0)) != 1
		or float(avatar_snapshot.get("hand_r_to_socket_global_distance", 999.0)) > 0.189
		or float(avatar_snapshot.get("hand_l_to_socket_global_distance", 0.0)) < 0.180
	):
		failures.append("Bunny pistol pose does not preserve the right grip and free left hand")
	if float(avatar_snapshot.get("hand_position", Vector3.ZERO).x) >= 0.263:
		failures.append("DIY grip hand did not use the improved inward weapon hold position")
	gallery.run_player_action("moving")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	var moving_snapshot := gallery.player.avatar.get_component_snapshot()
	if (
		str(moving_snapshot.get("weapon_pose_state", "")) != "sidearm_run"
		or float(moving_snapshot.get("hand_r_to_socket_global_distance", 999.0)) > 0.207
	):
		failures.append("Moving animation does not preserve the independent sidearm run grip")
	if absf((moving_snapshot.get("foot_l_position", Vector3.ZERO) as Vector3).y - (moving_snapshot.get("foot_r_position", Vector3.ZERO) as Vector3).y) <= 0.001:
		failures.append("Bunny feet do not alternate during the moving animation")
	if not gallery.request_preview_fire():
		failures.append("DIY player cannot fire the real equipped weapon")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	avatar_snapshot = gallery.player.avatar.get_component_snapshot()
	if not bool(avatar_snapshot.get("firing_animation_active", false)) or (avatar_snapshot.get("action_rotation", Vector3.ZERO) as Vector3).length() <= 0.001:
		failures.append("DIY avatar does not preserve expressive firing animation")
	if (
		str(avatar_snapshot.get("weapon_pose_state", "")) != "sidearm_fire"
		or float(avatar_snapshot.get("hand_r_to_socket_global_distance", 999.0)) > 0.36
		or int(avatar_snapshot.get("active_grip_hand_count", 0)) != 1
	):
		failures.append("Firing animation does not preserve the pistol's single right grip")
	gallery.reset_preview_customization()
	if gallery.player.get_avatar_customization() != PlayerAvatar3D.DEFAULT_CUSTOMIZATION:
		failures.append("DIY reset did not restore the default modular loadout")
	gallery.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PLAYER3D_DIY_FLOW_OK: bunny parts, head-parented ear sockets, weapon-class grip FSM, and expressive actions pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
