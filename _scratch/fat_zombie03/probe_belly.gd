extends SceneTree
var player: AnimationPlayer
var skeleton: Skeleton3D
func walk(n: Node):
	if n is AnimationPlayer:player=n
	if n is Skeleton3D:skeleton=n
	for c in n.get_children():walk(c)
func pose(t:float,clip:String)->Array:
	player.play(clip)
	player.seek(t,true)
	skeleton.force_update_all_bone_transforms()
	var result=[]
	for i in skeleton.get_bone_count():result.append(skeleton.get_bone_pose(i))
	return result
func error(a:Array,b:Array)->float:
	var e=0.0
	for i in a.size():
		e=maxf(e,a[i].origin.distance_to(b[i].origin))
		for axis in 3:e=maxf(e,a[i].basis[axis].distance_to(b[i].basis[axis]))
	return e
func _initialize():call_deferred("run")
func run():
	var scene=load("res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn").instantiate()
	root.add_child(scene);walk(scene)
	if player==null or skeleton==null or not player.has_animation("walking"):
		printerr("FAT_ZOMBIE03_WALK_FAILED missing animation")
		quit(1);return
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var negative=OS.get_cmdline_user_args().has("--negative-loop")
	var report={"clips":{},"bone_count":skeleton.get_bone_count(),"autoplay":player.autoplay,"passed":true}
	for clip in ["idle", "walking", "running", "attack", "hurt", "dead", "awaken", "alert", "turn_l", "turn_r", "move_start", "move_stop", "hit_light"]:
		var anim=player.get_animation(clip)
		if negative and clip=="attack":anim.loop_mode=Animation.LOOP_LINEAR
		var duration={"idle": 3.2, "walking": 2.0, "running": 1.2, "attack": 2.5, "hurt": 0.8, "dead": 2.6, "awaken": 1.2, "alert": 0.6, "turn_l": 0.8, "turn_r": 0.8, "move_start": 0.4, "move_stop": 0.6, "hit_light": 0.3}[clip]
		var first=pose(0,clip);var middle=pose(duration/2,clip);var last=pose(duration,clip)
		var seam=error(first,last);var motion=error(first,middle)
		var ok=absf(anim.length-duration)<.001 and anim.loop_mode==(Animation.LOOP_LINEAR if clip in ["idle","walking","running"] else Animation.LOOP_NONE) and (seam<.001 if clip in ["idle","walking","running","attack","hurt","awaken","turn_l","turn_r","hit_light"] else true) and motion>.0001 and skeleton.get_bone_count()==66 and player.autoplay=="idle"
		report["clips"][clip]={"length":anim.length,"loop_mode":anim.loop_mode,"tracks":anim.get_track_count(),"loop_error":seam,"motion_amplitude":motion,"passed":ok}
		report["passed"]=report["passed"] and ok
	var final_pose=pose(2.5,"attack")
	var held_pose=pose(3.0,"attack")
	report["attack_end_hold_error"]=error(final_pose,held_pose)
	report["attack_idle_transition_error"]=error(final_pose,pose(0,"idle"))
	report["attack_impact_hold_error"]=error(pose(1.2,"attack"),pose(38.0/30.0,"attack"))
	report["passed"]=report["passed"] and report["attack_end_hold_error"]<.001 and report["attack_idle_transition_error"]<.001 and report["attack_impact_hold_error"]<.001
	var light=player.get_animation("hit_light")
	if OS.get_cmdline_user_args().has("--negative-upper"):
		var index=light.add_track(Animation.TYPE_ROTATION_3D)
		light.track_set_path(index,NodePath("Skeleton3D:Root"))
	var upper_only=true
	for index in light.get_track_count():
		var path=light.track_get_path(index)
		upper_only=upper_only and path.get_subname_count()>0 and str(path.get_subname(path.get_subname_count()-1)) in ["Waist","Spine01","Spine02","Neck","Head","HeadTop_End"]
	report["hit_light_upper_only"]=upper_only
	report["dead_hold_error"]=error(pose(2.0,"dead"),pose(3.0,"dead"))
	report["move_start_walking_error"]=error(pose(.4,"move_start"),pose(0,"walking"))
	report["move_stop_idle_error"]=error(pose(.6,"move_stop"),pose(0,"idle"))
	report["passed"]=report["passed"] and upper_only and light.get_track_count()>0 and report["dead_hold_error"]<.001 and report["move_start_walking_error"]<.001 and report["move_stop_idle_error"]<.001
	var meshes=scene.find_children("*","MeshInstance3D",true,false)
	var skin:MeshInstance3D=meshes[0]
	pose(2.0,"dead")
	report["dead_compression"]=skin.get_blend_shape_value(0)
	pose(0,"idle")
	report["idle_compression"]=skin.get_blend_shape_value(0)
	report["passed"]=report["passed"] and report["dead_compression"]>.99 and abs(report["idle_compression"])<.001
	var filename="godot_negative_loop.json" if negative else "godot_validation.json"
	if OS.get_cmdline_user_args().has("--negative-upper"):filename="godot_negative_upper.json"
	FileAccess.open("I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/fat_zombie03/previews/belly_v008/"+filename,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FAT_ZOMBIE03_COMPLETE_", "OK" if report["passed"] else "FAILED", " ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)
