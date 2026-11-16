@tool
extends EditorScenePostImport
## glTF 不保证传递循环标志；正式重导时统一原始动画资源，而非只在运行时补救。
func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		node.autoplay = ""
		for clip in node.get_animation_list():
			node.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip == "move" else Animation.LOOP_NONE
	return scene
