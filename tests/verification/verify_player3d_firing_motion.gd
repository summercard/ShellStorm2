extends Node3D

const PLAYER = preload("res://scenes/Player3D.tscn")
var OUT: String = "res://outputs/character_pipeline/" + (OS.get_environment("BUNNY_VERIFICATION_BATCH") if not OS.get_environment("BUNNY_VERIFICATION_BATCH").is_empty() else "firing_v030") + "/"
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var visual := "--visual" in OS.get_cmdline_user_args()
	var player := PLAYER.instantiate() as Player3D
	add_child(player)
	player.set_process(false); player.set_physics_process(false); player.avatar.set_process(false)
	await get_tree().process_frame
	player.position = Vector3.ZERO
	player.get_node("Camera3D").set("current", false)
	player.get_node("AimCursor").set("visible", false)
	var camera := Camera3D.new(); add_child(camera)
	camera.position = Vector3(2.8,1.3,-3.5); camera.look_at(Vector3(0,0.62,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 1.8; camera.current = true
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color("34414b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = 0.9
	add_child(world)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-30,0); light.light_energy = 1.2; add_child(light)
	for ui in get_tree().root.find_children("*","Control",true,false): ui.visible = false
	var shape := player.get_node("VirtualCollisionCapsule").get("shape") as CapsuleShape3D
	var dimensions := Vector2(shape.radius,shape.height)
	var dirs := {"forward":Vector3.FORWARD,"strafe_left":Vector3.LEFT,"strafe_right":Vector3.RIGHT,"backward":Vector3.BACK}
	var families := {"sidearm":"bp_pistol","longgun":"bp_rifle","machinegun":"bp_sprinkler"}
	for family: String in families:
		check(player.equip_weapon(families[family],"mod_bullet_standard"),"equip "+family)
		await get_tree().process_frame
		player.weapon.set_process(false)
		player.set("_fire_animation_remaining",0.0); player.set("_presentation_state","idle")
		player.velocity=Vector3.ZERO; player.aim_yaw=0.0; player.avatar.visual_root.rotation.y=0.0
		player.avatar.call("_process",0.3)
		check(player.avatar.get_component_snapshot().authored_motion_clip==family+"_idle","carry before shot")
		# Use the real weapon event connection, not a direct avatar pose override.
		check(player.weapon.try_fire(Vector3.FORWARD,player),"real first shot "+family)
		player.avatar.call("_process",0.08)
		verify_pose(player,family+"_fire_idle")
		if visual:
			await get_tree().process_frame; await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT+family+"_fire_idle.png")
		for yaw in [0.0,1.2]:
			player.aim_yaw=yaw; player.avatar.visual_root.rotation.y=yaw
			for speed in [2.0,5.0]:
				for direction: String in dirs:
					player.velocity=(dirs[direction] as Vector3).rotated(Vector3.UP,yaw)*speed
					player.set("_presentation_state","moving")
					player.weapon.emit_signal("shot_fired",1)
					player.avatar.call("_process",0.08)
					var expected := "%s_fire_%s_%s" % [family,"walking" if speed<3.2 else "moving",direction]
					verify_pose(player,expected)
					var ear := player.avatar.ear_socket_l.quaternion
					player.avatar.call("_process",0.08)
					check(ear.angle_to(player.avatar.ear_socket_l.quaternion)>0.002,"moving ears "+expected)
					if visual and yaw==0.0 and speed==5.0:
						DirAccess.make_dir_recursive_absolute(OUT+family+"_"+direction)
						for frame in range(16):
							player.avatar.call("_process",0.8/1.3/16.0)
							await get_tree().process_frame; await RenderingServer.frame_post_draw
							get_viewport().get_texture().get_image().save_png(OUT+family+"_"+direction+"/%03d.png"%frame)
		player.set("_fire_animation_remaining",0.0)
		player.avatar.call("_process",0.08)
		check("_fire_" in player.avatar.get_component_snapshot().authored_motion_clip,"short shot gap keeps raised")
		player.avatar.call("_process",0.3)
		check(not "_fire_" in player.avatar.get_component_snapshot().authored_motion_clip,"stop returns to carry")
		player.weapon.emit_signal("shot_fired",1); player.set("_presentation_state","hurt")
		player.avatar.call("_process",0.3)
		check(player.avatar.get_component_snapshot().authored_motion_clip=="hurt","hurt wins over firing")
	check(Vector2(shape.radius,shape.height)==dimensions,"collision unchanged")
	var file := FileAccess.open(OUT+"firing_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  ")); file.close()
	player.queue_free(); await get_tree().process_frame
	if failures.is_empty(): print("BUNNY_FIRING_MOTION_OK checks=",checks); get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)

func verify_pose(player: Player3D, expected: String) -> void:
	var snap := player.avatar.get_component_snapshot()
	check(snap.authored_motion_clip==expected,"clip "+expected+" actual "+snap.authored_motion_clip)
	check(snap.missing_authored_action=="","registered firing "+expected)
	check(not snap.legacy_procedural_motion_enabled,"authored only")
	check(snap.right_hand_palm_to_socket_global_distance<0.001,"main palm "+expected)
	check(snap.weapon_support_error_m>=0.0 and snap.weapon_support_error_m<0.02,"support "+expected)
	var muzzle := player.weapon.find_child("MuzzleSocket",true,false) as Node3D
	var wanted := Vector3.FORWARD.rotated(Vector3.UP,player.aim_yaw)
	check(muzzle!=null and (-muzzle.global_basis.z.normalized()).dot(wanted)>0.999,"raised muzzle aim "+expected)
