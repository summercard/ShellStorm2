extends Node

const GALLERY_SCENE: PackedScene = preload("res://scenes/Player3DStateGallery.tscn")
const PREVIEW_PATH := "res://outputs/019f8417-e7f4-7bc3-aded-c62dfd1d1462/PH33_猫型模块角色预览场.png"


func _ready() -> void:
	var failures: Array[String] = []
	var gallery := GALLERY_SCENE.instantiate() as Player3DStateGallery
	add_child(gallery)
	await get_tree().process_frame
	gallery.set_preview_customization("body", "cat_orange")
	gallery.set_preview_customization("head", "cat_orange")
	gallery.set_preview_customization("hand", "cat_orange")
	gallery.set_preview_customization("feet", "cat_orange")
	gallery.set_preview_customization("hat", "none")
	gallery.set_preview_customization("glasses", "none")
	gallery.run_player_action("moving")
	gallery.begin_preview_charge()
	gallery.spawn_enemy("ranged_caster")
	gallery.select_npc(1)
	gallery.interact_with_npc()
	gallery.player.set_physics_process(false)
	gallery.player.aim_direction = Vector3.BACK
	gallery.player.aim_yaw = PI
	gallery.player.avatar.visual_root.rotation.y = PI
	await get_tree().create_timer(0.32).timeout
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("Player3DStateGallery viewport preview is empty")
	elif image.save_png(PREVIEW_PATH) != OK:
		failures.append("Player3DStateGallery preview cannot be saved")
	var snapshot := gallery.get_preview_snapshot()
	if int((snapshot.get("controls", []) as Array).size()) < 24:
		failures.append("Player3DStateGallery does not render the expected test controls")
	if not bool((snapshot.get("player", {}).get("overlays", {}) as Dictionary).get("charging", false)):
		failures.append("Player3DStateGallery visual test cannot show charge overlay")
	var avatar_snapshot := gallery.player.avatar.get_component_snapshot()
	if int(avatar_snapshot.get("visible_foot_count", 0)) != 2:
		failures.append("Player3DStateGallery visual test cannot show the bunny feet modules")
	if str(avatar_snapshot.get("avatar_profile", "")) != "bunny01" or int(avatar_snapshot.get("ear_socket_count", 0)) != 2:
		failures.append("Player3DStateGallery visual test cannot show bunny head-ear accessory sockets")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PLAYER3D_STATE_GALLERY_VISUAL_OK: interactive player, enemy and NPC preview saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
