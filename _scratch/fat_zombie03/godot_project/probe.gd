extends SceneTree
var report = {"meshes":0,"bones":0,"animation_count":0,"collision_nodes":0,"mesh_bounds":[]}
func walk(n: Node) -> void:
	if n is MeshInstance3D:
		report.meshes += 1
		var box: AABB = n.get_aabb()
		report.mesh_bounds.append({"size":[box.size.x,box.size.y,box.size.z],"origin":[box.position.x,box.position.y,box.position.z]})
	if n is Skeleton3D:
		report.bones += n.get_bone_count()
	if n is AnimationPlayer:
		for clip in n.get_animation_list():
			if clip != "RESET": report.animation_count += 1
	if n is CollisionObject3D or n is CollisionShape3D: report.collision_nodes += 1
	for c in n.get_children(): walk(c)
func _initialize() -> void:
	var packed = load("res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var obj = packed.instantiate()
	root.add_child(obj)
	walk(obj)
	report["root_scale"] = [obj.scale.x,obj.scale.y,obj.scale.z]
	FileAccess.open("res://godot_audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	var ok = report.meshes == 1 and report.bones == 65 and report.animation_count == 0 and report.collision_nodes == 0 and obj.scale == Vector3.ONE
	print("FAT_ZOMBIE03_IMPORT_", "OK" if ok else "FAILED", " ",JSON.stringify(report))
	quit(0 if ok else 1)
