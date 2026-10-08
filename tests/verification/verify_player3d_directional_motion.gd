extends Node3D

const PLAYER = preload("res://scenes/Player3D.tscn")
var OUT: String = "res://outputs/character_pipeline/" + (OS.get_environment("BUNNY_VERIFICATION_BATCH") if not OS.get_environment("BUNNY_VERIFICATION_BATCH").is_empty() else "runtime_v029") + "/"
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
	player.set_process(false); player.set_physics_process(false)
	player.avatar.set_process(false)
	await get_tree().process_frame
	player.position = Vector3.ZERO
	player.get_node("Camera3D").set("current", false)
	player.get_node("AimCursor").set("visible", false)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1.25, -3.6)
	camera.look_at(Vector3(0, 0.65, 0)); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 1.8; camera.current = true
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR; world.environment.background_color = Color("34414b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color = Color.WHITE; world.environment.ambient_light_energy = 0.9
	add_child(world)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-30,0); light.light_energy = 1.2; add_child(light)
	for ui in get_tree().root.find_children("*", "Control", true, false): ui.visible = false
	var shape := player.get_node("VirtualCollisionCapsule").get("shape") as CapsuleShape3D
	var dimensions := Vector2(shape.radius, shape.height)
	var directions := {"forward": Vector3.FORWARD, "strafe_left": Vector3.LEFT, "strafe_right": Vector3.RIGHT, "backward": Vector3.BACK}
	var families := {"sidearm":"bp_pistol", "longgun":"bp_rifle", "machinegun":"bp_sprinkler"}
	var support_errors := {}
	for family: String in families:
		check(player.equip_weapon(families[family], "mod_bullet_standard"), "equip " + family)
		await get_tree().process_frame
		player.weapon.set_process(false)
		player.set("_presentation_state", "idle"); player.velocity = Vector3.ZERO; player.aim_yaw = 0.0; player.avatar.visual_root.rotation.y = 0.0
		player.avatar.call("_process", 0.3)
		var snapshot := player.avatar.get_component_snapshot()
		check(snapshot.authored_motion_clip == family+"_idle", "idle " + family)
		check(snapshot.motion_library_version == str(player.avatar.get_meta("motion_library_version")), "library matches registered prefab")
		check(snapshot.active_grip_hand_count == (1 if family=="sidearm" else 2), "hand count " + family)
		support_errors[family] = snapshot.weapon_support_error_m
		check(snapshot.weapon_support_error_m < 0.02 and snapshot.weapon_support_error_m >= 0.0, "representative support " + family + " " + str(snapshot.weapon_support_error_m))
		if visual:
			camera.position=Vector3(0,3,-2.2);camera.look_at(Vector3(0,0.6,0))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(OUT+family+"_idle_top.png")==OK,"top carry screenshot")
		for yaw in [0.0, 1.2]:
			player.aim_yaw=yaw;player.avatar.visual_root.rotation.y=yaw
			for speed in [2.0,5.0]:
				for direction: String in directions:
					player.velocity=(directions[direction] as Vector3).rotated(Vector3.UP,yaw)*speed
					player.set("_presentation_state","moving")
					player.avatar.call("_process",0.3)
					var expected := "%s_%s_%s" % [family,"walking" if speed<3.2 else "moving",direction]
					snapshot=player.avatar.get_component_snapshot()
					check(snapshot.authored_motion_clip==expected,"clip "+expected+" actual "+snapshot.authored_motion_clip)
					check(snapshot.right_hand_palm_to_socket_global_distance<0.001,"main palm grip "+expected)
					check(snapshot.weapon_support_error_m>=0.0 and snapshot.weapon_support_error_m<0.02,"support grip "+expected)
					check(not snapshot.legacy_procedural_motion_enabled,"no procedural")
					var ear_before := player.avatar.ear_socket_l.quaternion
					player.avatar.call("_process",0.08)
					check(ear_before.angle_to(player.avatar.ear_socket_l.quaternion)>0.002,"ear motion "+expected)
					if visual and yaw==0.0 and speed==5.0:
						camera.position=Vector3(3.6,1.2,0) if direction in ["forward","backward"] else Vector3(0,1.25,-3.6)
						camera.look_at(Vector3(0,0.65,0))
						await get_tree().process_frame
						await RenderingServer.frame_post_draw
						check(get_viewport().get_texture().get_image().save_png(OUT+expected+".png")==OK,"screenshot")
						if direction == "strafe_left":
							DirAccess.make_dir_recursive_absolute(OUT+family)
							for frame in range(20):
								player.avatar.call("_process", 0.8 / 1.3 / 20.0)
								await get_tree().process_frame
								await RenderingServer.frame_post_draw
								check(get_viewport().get_texture().get_image().save_png(OUT+family+"/%03d.png"%frame)==OK,"animation frame")
	# Secondary longguns retain their family clip and expose the actual support mismatch.
	for gun in ["bp_shotgun","bp_sniper","bp_launcher","bp_charge","bp_machinegun"]:
		check(player.equip_weapon(gun,"mod_bullet_standard"),"equip "+gun)
		await get_tree().process_frame
		player.set("_presentation_state","idle");player.avatar.call("_process",0.3)
		support_errors[gun]=player.avatar.get_component_snapshot().weapon_support_error_m
	# No weapon: read state normally, then explicitly detach its mount for this probe.
	player.weapon.reparent(self); player.set("_presentation_state","moving")
	for direction: String in directions:
		player.velocity=directions[direction]*2.0;player.aim_yaw=0.0;player.avatar.visual_root.rotation.y=0.0
		player.avatar.call("_process",0.3)
		check(player.avatar.get_component_snapshot().authored_motion_clip=="unarmed_walking_"+direction,"unarmed "+direction)
	check(Vector2(shape.radius,shape.height)==dimensions,"collision unchanged")
	check(CharacterMotionLibrary3D.select_direction(Vector3(1,0,-1),"strafe_right")=="strafe_right","diagonal hysteresis")
	check(CharacterMotionLibrary3D.select_direction(Vector3.ZERO,"backward")=="backward","zero speed stable")
	var interchange := load("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_bunny01_motion/anim_bunny01_library.glb") as PackedScene
	check(interchange != null, "standard GLB loads")
	if interchange != null:
		var glb := interchange.instantiate()
		add_child(glb)
		check(glb.find_children("*","MeshInstance3D",true,false).is_empty(),"no preview weapon or geometry exported")
		check(glb.find_children("*","CollisionObject3D",true,false).is_empty(),"no visual collisions")
		glb.queue_free()
	var file := FileAccess.open(OUT+"runtime_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"support_errors_m":support_errors,"collision":dimensions},"  "));file.close()
	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BUNNY_DIRECTIONAL_MOTION_OK checks=",checks);get_tree().quit(0)
	else:
		for failure in failures:push_error(failure)
		get_tree().quit(1)
