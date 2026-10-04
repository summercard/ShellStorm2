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
	for clip in ["idle","walking","running","attack"]:
		var anim=player.get_animation(clip)
		if negative and clip=="attack":anim.loop_mode=Animation.LOOP_LINEAR
		var duration={"idle":3.2,"walking":2.0,"running":1.2,"attack":2.5}[clip]
		var first=pose(0,clip);var middle=pose(duration/2,clip);var last=pose(duration,clip)
		var seam=error(first,last);var motion=error(first,middle)
		var ok=absf(anim.length-duration)<.001 and anim.loop_mode==(Animation.LOOP_NONE if clip=="attack" else Animation.LOOP_LINEAR) and seam<.001 and motion>.01 and skeleton.get_bone_count()==66 and player.autoplay=="idle"
		report["clips"][clip]={"length":anim.length,"loop_mode":anim.loop_mode,"tracks":anim.get_track_count(),"loop_error":seam,"motion_amplitude":motion,"passed":ok}
		report["passed"]=report["passed"] and ok
	var final_pose=pose(2.5,"attack")
	var held_pose=pose(3.0,"attack")
	report["attack_end_hold_error"]=error(final_pose,held_pose)
	report["attack_idle_transition_error"]=error(final_pose,pose(0,"idle"))
	report["attack_impact_hold_error"]=error(pose(1.2,"attack"),pose(38.0/30.0,"attack"))
	report["passed"]=report["passed"] and report["attack_end_hold_error"]<.001 and report["attack_idle_transition_error"]<.001 and report["attack_impact_hold_error"]<.001
	var filename="godot_negative_loop.json" if negative else "godot_validation.json"
	FileAccess.open("I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/fat_zombie03/previews/attack_v004/"+filename,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FAT_ZOMBIE03_ATTACK_", "OK" if report["passed"] else "FAILED", " ",JSON.stringify(report))
	quit(0 if report["passed"] else 1)
