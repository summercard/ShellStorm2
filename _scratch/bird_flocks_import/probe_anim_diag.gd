extends Node
## 诊断：多 AnimationPlayer 并行播放为何只有一只鸟在动。

const GROUND := "res://assets/art/vfx/environment_3d/bird_flocks/components/ground/vfx_env_birds_ground_visual.glb"
const PLAYBACK := preload("res://assets/art/vfx/environment_3d/bird_flocks/runtime/vfx_env_birds_playback.gd")


func _ready() -> void:
	var root := (load(GROUND) as PackedScene).instantiate() as Node3D
	add_child(root)
	var primary := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("PRIMARY path=%s parent=%s root_node=%s libs=%s" % [
		str(root.get_path_to(primary)), str(primary.get_parent().name),
		str(primary.root_node), str(primary.get_animation_library_list())])
	print("NAMES=%s" % str(primary.get_animation_list()))
	var ok := PLAYBACK.play_all(root)
	print("PLAY_ALL=%s" % str(ok))
	await get_tree().process_frame
	await get_tree().process_frame
	var parent := primary.get_parent()
	for child in parent.get_children():
		var player := child as AnimationPlayer
		if player == null:
			continue
		print("PLAYER %-20s current=%s playing=%s root_node=%s libs=%s anims=%d" % [
			player.name, str(player.current_animation), str(player.is_playing()),
			str(player.root_node), str(player.get_animation_library_list()),
			player.get_animation_list().size()])
	var skeleton := root.find_child("鸟群_整体移动缩放控制", true, false) as Node3D
	await get_tree().create_timer(3.0).timeout
	print("--- after 3s ---")
	for child in skeleton.get_children():
		var bird := child as Node3D
		if bird != null:
			print("  %s world=%s process_mode=%d" % [bird.name, str(bird.global_position), bird.process_mode])
	print("DIAG_DONE")
	get_tree().quit(0)
