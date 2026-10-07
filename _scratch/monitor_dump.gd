extends SceneTree
func _initialize() -> void:
	var scene := load("res://assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/enm_boss_monitor002_visual_top3d.glb") as PackedScene
	var model := scene.instantiate()
	var skeleton := model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var names: Array[String] = []
	for i in range(skeleton.get_bone_count()):names.append(skeleton.get_bone_name(i))
	print("MONITOR_BONES ",names)
	for name in ["root_2","monitor_tilt_2","hand.L","face_large_eye_2"]:
		print("MONITOR_REST ",name," ",skeleton.get_bone_global_rest(skeleton.find_bone(name)))
	for node in model.find_children("*","MeshInstance3D",true,false):
		if "Texture" in str(node.name) or "Screen" in str(node.name):print("MONITOR_MESH ",node.name," ",node.transform)
	model.free();quit()
