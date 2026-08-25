extends Node

const GALLERY_SCENE: PackedScene = preload("res://scenes/Player3DStateGallery.tscn")
const PREVIEW_PATH := "res://outputs/verification/player3d_chibi_head_accessory.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var gallery := GALLERY_SCENE.instantiate() as Player3DStateGallery
	add_child(gallery)
	await get_tree().process_frame
	gallery.set_preview_customization("head", "chibi_anime")
	gallery.set_preview_customization("hat", "none")
	gallery.set_preview_customization("glasses", "none")
	gallery.player.set_physics_process(false)
	gallery.player.aim_direction = Vector3.BACK
	gallery.player.aim_yaw = PI
	gallery.player.avatar.visual_root.rotation.y = PI
	# Match WardrobeMenu3D: character faces south and the camera is south of it.
	gallery.player.camera.position = Vector3(0.0, 0.82, 2.0)
	gallery.player.camera.fov = 30.0
	gallery.player.camera.look_at(gallery.player.global_position + Vector3.UP * 0.58, Vector3.UP)
	var inspection_light := OmniLight3D.new()
	inspection_light.light_energy = 2.0
	inspection_light.omni_range = 4.0
	inspection_light.position = Vector3(0.0, 1.05, 1.5)
	add_child(inspection_light)
	await get_tree().create_timer(0.32).timeout
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("二次元头部游戏预览为空")
	elif image.save_png(PREVIEW_PATH) != OK:
		failures.append("二次元头部游戏预览无法保存")
	var snapshot := gallery.player.avatar.get_component_snapshot()
	if not bool(snapshot.get("chibi_anime_head_visible", false)):
		failures.append("游戏预览没有启用二次元头部模型")
	gallery.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("PLAYER3D_HEAD_ACCESSORY_VISUAL_OK: in-game wardrobe head preview saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
