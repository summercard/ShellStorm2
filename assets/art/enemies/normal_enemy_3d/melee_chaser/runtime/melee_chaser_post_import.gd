@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		for clip in node.get_animation_list():
			node.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in ["idle", "walking", "running"] else Animation.LOOP_NONE
	return scene
