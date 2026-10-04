extends SceneTree
var player: AnimationPlayer
var skeleton: Skeleton3D
func walk(n: Node):
	if n is AnimationPlayer:player=n
	if n is Skeleton3D:skeleton=n
	for c in n.get_children():walk(c)
func pose(t:float)->Array:
	player.play("idle")
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
	if player==null or skeleton==null or not player.has_animation("idle"):
		printerr("FAT_ZOMBIE03_IDLE_FAILED missing animation")
		quit(1);return
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var anim=player.get_animation("idle")
	var negative=OS.get_cmdline_user_args().has("--negative-loop")
	if negative:anim.loop_mode=Animation.LOOP_NONE
	var first=pose(0);var middle=pose(1.6);var last=pose(3.2)
	var seam=error(first,last);var motion=error(first,middle)
	var root_bone=skeleton.find_bone("Root")
	var report={"clip":"idle","length":anim.length,"loop_mode":anim.loop_mode,"tracks":anim.get_track_count(),"bone_count":skeleton.get_bone_count(),"loop_error":seam,"motion_amplitude":motion,"root_pose":str(skeleton.get_bone_pose(root_bone)),"animation_list":player.get_animation_list(),"animation_player_path":str(player.get_path())}
	report["autoplay"]=player.autoplay
	var ok=absf(anim.length-3.2)<.001 and anim.loop_mode==Animation.LOOP_LINEAR and seam<.001 and motion>.01 and skeleton.get_bone_count()==66 and player.autoplay=="idle"
	report["passed"]=ok
	var report_file="godot_negative_loop.json" if negative else "godot_idle_validation.json"
	FileAccess.open("I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/fat_zombie03/previews/idle_walk_v002/"+report_file,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FAT_ZOMBIE03_IDLE_", "OK" if ok else "FAILED", " ",JSON.stringify(report))
	quit(0 if ok else 1)
