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
	if int(avatar_snapshot.get("wearable_count", 0)) < 8:
		failures.append("Hat/glasses wearable nodes were not constructed")
	if int(avatar_snapshot.get("component_count", 0)) != 4:
		failures.append("Cat avatar does not expose head/body/hand/feet as four primary modules")
	if int(avatar_snapshot.get("eye_count", 0)) != 2 or int(avatar_snapshot.get("ear_count", 0)) != 2:
		failures.append("Cat head does not expose two eyes and two ears")
	if int(avatar_snapshot.get("visible_foot_count", 0)) != 2:
		failures.append("Cat feet module does not expose two short feet")
	if str(avatar_snapshot.get("tail_style", "")) != "round_stub":
		failures.append("Cat body does not expose the round tail stub")
	for required_path in [
		"VisualRoot/Head/Eyes/EyeL",
		"VisualRoot/Head/Eyes/EyeR",
		"VisualRoot/Head/Ears/EarL",
		"VisualRoot/Head/Ears/EarR",
		"VisualRoot/Body/TailStub",
		"VisualRoot/Feet/FootL",
		"VisualRoot/Feet/FootR",
	]:
		if not gallery.player.avatar.has_node(required_path):
			failures.append("Cat modular node is missing: %s" % required_path)
	if not gallery.player.avatar.get_node("VisualRoot/Head/Wearables/HatHardHat").visible:
		failures.append("Selected hard hat is not visible")
	if not gallery.player.avatar.get_node("VisualRoot/Head/Wearables/GlassesDualGoggles").visible:
		failures.append("Selected goggles are not visible")
	for wearable_path in [
		"VisualRoot/Head/Wearables/HatHardHat",
		"VisualRoot/Head/Wearables/GlassesDualGoggles",
	]:
		var wearable := gallery.player.avatar.get_node(wearable_path) as Node3D
		for mesh in wearable.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh as MeshInstance3D
			if mesh_instance.layers != 2:
				failures.append("DIY wearable left the avatar-only light layer: %s" % wearable_path)
			if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				failures.append("DIY wearable can block the avatar light: %s" % wearable_path)
			if mesh_instance.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
				failures.append("DIY wearable can inject indirect light: %s" % wearable_path)
	var avatar_mesh_count := 0
	for mesh in gallery.player.avatar.visual_root.find_children("*", "MeshInstance3D", true, false):
		var avatar_mesh := mesh as MeshInstance3D
		avatar_mesh_count += 1
		if avatar_mesh.layers != 2:
			failures.append("Avatar mesh left the avatar-only fill-light layer: %s" % avatar_mesh.get_path())
		if avatar_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("Avatar mesh can self-shadow the head/body front lighting: %s" % avatar_mesh.get_path())
		if avatar_mesh.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
			failures.append("Avatar mesh can inject indirect lighting: %s" % avatar_mesh.get_path())
	if avatar_mesh_count <= 0 or int(avatar_snapshot.get("avatar_shadow_caster_count", -1)) != 0:
		failures.append("Avatar lighting isolation did not disable every model self-shadow")
	var idle_offset := avatar_snapshot.get("hand_socket_offset", Vector3.ZERO) as Vector3
	if float(avatar_snapshot.get("hand_position", Vector3.ZERO).x) >= 0.65:
		failures.append("DIY grip hand did not use the improved inward weapon hold position")
	gallery.run_player_action("moving")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	var moving_snapshot := gallery.player.avatar.get_component_snapshot()
	if not (moving_snapshot.get("hand_socket_offset", Vector3.ZERO) as Vector3).is_equal_approx(idle_offset):
		failures.append("Moving animation separates the hand and weapon socket")
	if absf((moving_snapshot.get("foot_l_position", Vector3.ZERO) as Vector3).y - (moving_snapshot.get("foot_r_position", Vector3.ZERO) as Vector3).y) <= 0.001:
		failures.append("Cat feet do not alternate during the moving animation")
	if not gallery.request_preview_fire():
		failures.append("DIY player cannot fire the real equipped weapon")
	await get_tree().physics_frame
	await get_tree().process_frame
	gallery.player.avatar.call("_process", 0.016)
	avatar_snapshot = gallery.player.avatar.get_component_snapshot()
	if not bool(avatar_snapshot.get("firing_animation_active", false)) or (avatar_snapshot.get("action_rotation", Vector3.ZERO) as Vector3).length() <= 0.001:
		failures.append("DIY avatar does not preserve expressive firing animation")
	if not (avatar_snapshot.get("hand_socket_offset", Vector3.ZERO) as Vector3).is_equal_approx(idle_offset):
		failures.append("Firing animation separates the hand and weapon socket")
	gallery.reset_preview_customization()
	if gallery.player.get_avatar_customization() != PlayerAvatar3D.DEFAULT_CUSTOMIZATION:
		failures.append("DIY reset did not restore the default modular loadout")
	gallery.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PLAYER3D_DIY_FLOW_OK: cat head/body/hand/feet, eyes/ears/round tail, grip socket, and expressive actions pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
