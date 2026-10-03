extends SceneTree
var report = {"meshes":0,"bones":0,"animation_count":0,"collision_nodes":0,"mesh_bounds":[],"textures":[],"missing_core":[],"root_parent":-2,"hip_parent":""}
func walk(n: Node) -> void:
	if n is MeshInstance3D:
		report.meshes += 1
		var box: AABB = n.get_aabb()
		report.mesh_bounds.append({"size":[box.size.x,box.size.y,box.size.z],"origin":[box.position.x,box.position.y,box.position.z]})
		for surface in n.mesh.get_surface_count():
			var mat = n.get_active_material(surface) as BaseMaterial3D
			if mat and mat.albedo_texture:
				report.textures.append([mat.albedo_texture.get_width(),mat.albedo_texture.get_height()])
	if n is Skeleton3D:
		report.bones += n.get_bone_count()
		var core = ["Root","Hip","Waist","Spine02","Neck","Head"]
		for side in ["L","R"]:
			for part in ["Clavicle","Upperarm","Forearm","Hand","Thumb1","Thumb2","Index1","Index2","Middle1","Middle2","Pinky1","Pinky2","Thigh","Calf","Foot"]: core.append(side+"_"+part)
		for bone in core:
			if n.find_bone(bone)<0:report.missing_core.append(bone)
		var rid = n.find_bone("Root")
		if rid>=0:report.root_parent=n.get_bone_parent(rid)
		var hip=n.find_bone("Hip")
		if hip>=0 and n.get_bone_parent(hip)>=0:report.hip_parent=n.get_bone_name(n.get_bone_parent(hip))
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
	FileAccess.open("I:/工作项目/shellstrom2/ShellStorm2/_scratch/fat_zombie03/godot_audit_v002.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	var height_ok = report.mesh_bounds.size()==1 and absf(float(report.mesh_bounds[0].size[1])*0.7-2.2)<0.0001
	var ok = report.meshes == 1 and report.bones == 66 and report.animation_count == 0 and report.collision_nodes == 0 and obj.scale == Vector3.ONE and report.missing_core.is_empty() and report.root_parent == -1 and report.hip_parent == "Root" and report.textures == [[512,512]] and height_ok
	print("FAT_ZOMBIE03_IMPORT_", "OK" if ok else "FAILED", " ",JSON.stringify(report))
	quit(0 if ok else 1)
