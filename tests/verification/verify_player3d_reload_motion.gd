extends Node3D
const PLAYER = preload("res://scenes/Player3D.tscn")
var OUT = "res://outputs/character_pipeline/" + OS.get_environment("BUNNY_VERIFICATION_BATCH") + "/" if not OS.get_environment("BUNNY_VERIFICATION_BATCH").is_empty() else "res://outputs/character_pipeline/reload_v034/"
var failures: Array[String] = []
var checks := 0
var player: Player3D
var visual := false
var frame_id := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func advance(delta: float, capture := false) -> void:
	player.weapon.call("_process",delta)
	player.weapon.set_process(false)
	player.avatar.call("_process",delta)
	await get_tree().process_frame
	if capture and visual:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT+"frames/%03d.png"%frame_id)
		frame_id += 1

func begin(duration: float) -> void:
	player.weapon.cancel_reload();player.weapon.current_ammo=0;player.weapon.reload_time=duration
	check(player.request_reload(),"reload accepted")
	player.weapon.set_process(false);player.avatar.call("_process",0.0)

func _ready() -> void:
	visual="--visual" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUT+"frames")
	player=PLAYER.instantiate() as Player3D;add_child(player)
	player.set_process(false);player.set_physics_process(false);player.avatar.set_process(false)
	await get_tree().process_frame
	player.set("_presentation_state","idle");player.aim_yaw=0
	player.get_node("Camera3D").set("current",false);player.get_node("AimCursor").set("visible",false)
	# Same elevation as TowerDescent3D; orthographic enlargement for animation review.
	var review_target:=Vector3(0,.55,-.10)
	var camera:=Camera3D.new();add_child(camera);camera.position=review_target+Vector3(0,10.269009,4.787671);camera.look_at(review_target);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.4;camera.current=true
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("34414b");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.7;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=.7;add_child(light)
	for ui in get_tree().root.find_children("*","Control",true,false):ui.visible=false
	var families := {"bp_pistol":"sidearm","bp_rifle":"longgun","bp_machinegun":"machinegun"}
	for gun: String in families:
		check(player.equip_weapon(gun,"mod_bullet_standard"),"equip "+gun)
		await get_tree().process_frame;player.weapon.set_process(false)
		player.avatar.visual_root.rotation.y=0;player.avatar.call("_process",.3)
		var family: String=families[gun]
		var baseline:=Transform3D.IDENTITY
		for duration: float in [.4,1.5,4.0]:
			begin(duration)
			var actual:=float(player.get_reload_snapshot().duration)
			await advance(actual*.5)
			var snapshot:=player.avatar.get_component_snapshot()
			check(snapshot.authored_overlay_clip==family+"_reload","family reload selected")
			check(absf(snapshot.authored_overlay_progress-.5)<.0001,"real duration half phase")
			check(snapshot.missing_authored_action=="","reload not missing")
			check(snapshot.right_hand_palm_to_socket_global_distance<.001,"main grip attached")
			if family=="machinegun":
				var muzzle_direction:=player.avatar.weapon_socket.basis*Vector3.FORWARD
				var screen_up:float=-muzzle_direction.z*.9063+muzzle_direction.y*.4226
				check(muzzle_direction.x<-.6 and muzzle_direction.z<-.5 and muzzle_direction.y>.35 and absf(rad_to_deg(atan2(-muzzle_direction.x,screen_up))-45.0)<3.0,"machinegun left-forward screen diagonal about 45 degrees and muzzle raised")
				check(player.avatar.weapon_socket.position.y>.45,"machinegun reload grip raised")
			check(player.weapon.current_ammo==0,"no early ammo grant")
			check(not player.weapon.try_fire(Vector3.FORWARD,player),"no fire while reloading")
			if duration==.4: baseline=player.avatar.bunny_hand_l.transform
			else:check(player.avatar.bunny_hand_l.transform.is_equal_approx(baseline),"same phase same hand pose at different duration")
			await advance(actual*.49)
			check(player.is_reloading() and player.weapon.current_ammo==0,"still active at 99 percent")
			await advance(actual*.011)
			check(not player.is_reloading() and player.weapon.current_ammo==player.weapon.magazine_size,"gameplay timer alone completes reload")
			check(player.avatar.get_component_snapshot().authored_overlay_clip=="","overlay ends with reload")
		# Capture a complete normal-speed reload for each family.
		player.avatar.call("_process",.3)
		begin(2.0)
		var gun_start: Transform3D=player.avatar.weapon_socket.transform
		var gun_travel:=0.0
		var gun_rotation:=0.0
		for i in range(41):
			await advance(.05,true)
			gun_travel=maxf(gun_travel,gun_start.origin.distance_to(player.avatar.weapon_socket.position))
			gun_rotation=maxf(gun_rotation,gun_start.basis.get_rotation_quaternion().angle_to(player.avatar.weapon_socket.quaternion))
			if family=="machinegun":
				check(absf(player.avatar.weapon_socket.position.z-gun_start.origin.z)<.001,"machinegun stays close without forward translation")
		if family in ["longgun","machinegun"]:
			check(gun_travel>.20,"visible gun displacement during reload")
			check(gun_rotation>.45,"visible gun rotation during reload")
		# Moving overlay must not freeze lower-body motion or use locomotion rate as reload rate.
		for direction in [Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT,Vector3.BACK]:
			player.set("_presentation_state","moving");player.velocity=direction*5
			begin(2.0);await advance(.4)
			var foot:=player.avatar.foot_l.transform
			await advance(.4)
			check(absf(player.avatar.get_component_snapshot().authored_overlay_progress-.4)<.0001,"moving reload true progress")
			check(not player.avatar.foot_l.transform.is_equal_approx(foot),"feet continue while reloading")
			player.weapon.cancel_reload();await advance(.15)
			check(player.avatar.get_component_snapshot().authored_overlay_clip=="","cancel exits reload")
			check(player.weapon.current_ammo==0,"cancel does not refill")
		player.set("_presentation_state","idle");player.velocity=Vector3.ZERO
		begin(2.0);await advance(.6)
		check(player.request_weapon_slot(player.active_weapon_slot).success,"stow interrupts reload")
		check(not player.is_reloading(),"switch cancels gameplay reload")
		player.call("_tick_weapon_transition",.5);player.set_weapon_holstered(false);await advance(.2)
		check(player.avatar.get_component_snapshot().authored_overlay_clip=="","no stale overlay after stow")
	var file:=FileAccess.open(OUT+"reload_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	player.queue_free();await get_tree().process_frame
	if failures.is_empty():print("BUNNY_RELOAD_MOTION_OK checks=",checks);get_tree().quit(0)
	else:
		for failure in failures:push_error(failure)
		get_tree().quit(1)
