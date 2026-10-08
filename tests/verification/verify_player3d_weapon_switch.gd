extends Node3D
const PLAYER = preload("res://scenes/Player3D.tscn")
const OUT = "res://outputs/character_pipeline/switch_v032/"
var failures: Array[String] = []
var checks := 0
var player: Player3D
var visual := false
var frame_id := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func step(delta: float) -> void:
	player.call("_tick_weapon_transition",delta)
	player.avatar.call("_process",delta)
	if player.get_weapon_transition_snapshot().active:
		check(player.avatar.get_component_snapshot().right_hand_palm_to_socket_global_distance<.001,"transition grip remains attached")
	await get_tree().process_frame
	if visual:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT+"switch/%03d.png"%frame_id)
		frame_id += 1

func finish() -> void:
	for i in range(21): await step(.05)

func _ready() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUT+"switch")
	player=PLAYER.instantiate() as Player3D;add_child(player)
	player.set_process(false);player.set_physics_process(false);player.avatar.set_process(false)
	await get_tree().process_frame
	player.position=Vector3.ZERO;player.set("_presentation_state","idle")
	player.aim_yaw=0;player.avatar.visual_root.rotation.y=0
	player.get_node("Camera3D").set("current",false);player.get_node("AimCursor").set("visible",false)
	var camera:=Camera3D.new();add_child(camera);camera.position=Vector3(2.8,1.5,3.4);camera.look_at(Vector3(0,.65,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.0;camera.current=true
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("34414b");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=1.0;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,30,0);add_child(light)
	for ui in get_tree().root.find_children("*","Control",true,false):ui.visible=false
	check(player.equip_weapon("bp_rifle","mod_bullet_standard"),"equip primary")
	var rifle:=player.get_equipped_weapon_item_for_slot(0)
	check(player.equip_weapon("bp_pistol","mod_bullet_standard"),"create secondary")
	var pistol:=player.get_equipped_weapon_item_for_slot(0)
	player.clear_all_equipped_weapons()
	check(player.equip_weapon_item_to_slot(rifle,0).success,"restore primary")
	check(player.equip_weapon_item_to_slot(pistol,1).success,"equip secondary")
	await get_tree().process_frame;player.weapon.set_process(false)
	player.weapon.current_ammo=3
	var primary_id:=player.get_equipped_weapon_instance_id_for_slot(0)
	var secondary_id:=player.get_equipped_weapon_instance_id_for_slot(1)
	player.avatar.call("_process",.3)
	check(player.request_weapon_slot(0).success,"same key begins holster")
	check(not player.request_weapon_slot(1).success,"repeat during transition rejected")
	check(not player.weapon.try_fire(Vector3.FORWARD,player),"no shot during stow")
	var start:=player.avatar.bunny_hand_r.position
	for i in range(7):await step(.05)
	check(start.distance_to(player.avatar.bunny_hand_r.position)>.2,"right hand moves rearward")
	await finish()
	check(player.weapon_holstered,"primary holstered")
	check(player.get_weapon_loadout_snapshot().stowed_count==2,"both weapons on back")
	check(player.get_weapon_loadout_snapshot().held_slot==-1,"no held slot")
	check(player.get_weapon_snapshot().gun_id=="","unarmed snapshot")
	check(not player.weapon.try_fire(Vector3.FORWARD,player),"no shot while holstered")
	check(not player.request_reload(),"no reload while holstered")
	check(not player.get_weapon_loadout_snapshot().slots[0].active and not player.get_weapon_loadout_snapshot().slots[1].active,"no active HUD weapon when stowed")
	for direction in [Vector3.FORWARD,Vector3.BACK]:
		player.set("_presentation_state","moving");player.velocity=direction*5
		var lows:=Vector2(INF,INF);var highs:=Vector2(-INF,-INF)
		for i in range(24):
			await step(.04)
			lows.x=minf(lows.x,player.avatar.bunny_hand_l.position.z);highs.x=maxf(highs.x,player.avatar.bunny_hand_l.position.z)
			lows.y=minf(lows.y,player.avatar.bunny_hand_r.position.z);highs.y=maxf(highs.y,player.avatar.bunny_hand_r.position.z)
		check(highs.x-lows.x>.2 and highs.y-lows.y>.2,"front/back unarmed arm swing")
	player.set("_presentation_state","idle");player.velocity=Vector3.ZERO
	check(player.request_weapon_slot(1).success,"draw secondary from empty hands")
	await finish()
	check(not player.weapon_holstered and player.active_weapon_slot==1,"secondary held")
	check(player.request_weapon_slot(0).success,"switch secondary to primary")
	await finish()
	check(player.active_weapon_slot==0 and not player.weapon_holstered,"primary held after switch")
	check(player.weapon.current_ammo==3,"ammo preserved")
	check(player.get_equipped_weapon_instance_id_for_slot(0)==primary_id and player.get_equipped_weapon_instance_id_for_slot(1)==secondary_id,"identities preserved")
	check(player.request_weapon_slot(1).success,"switch to secondary again");await finish()
	check(player.request_weapon_slot(1).success,"key2 holsters secondary");await finish()
	check(player.weapon_holstered and player.get_weapon_loadout_snapshot().stowed_count==2,"key2 leaves both on back")
	check(player.request_weapon_slot(1).success,"draw secondary again");await step(.1)
	player.input_locked=true;await step(.05)
	check(not player.get_weapon_transition_snapshot().active,"input lock cancels transition")
	player.input_locked=false
	player.set_weapon_holstered(true)
	var saved_holstered: bool=player.get_weapon_loadout_snapshot().holstered
	player.set_weapon_holstered(false)
	player.set_weapon_holstered(saved_holstered)
	check(player.weapon_holstered and player.get_weapon_loadout_snapshot().stowed_count==2,"holstered state restoration")
	player.set_weapon_holstered(false)
	player.unequip_weapon_item_from_slot(0)
	check(not player.request_weapon_slot(0).success,"empty slot rejected")
	var file:=FileAccess.open(OUT+"switch_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	player.queue_free();await get_tree().process_frame
	if failures.is_empty():print("BUNNY_WEAPON_SWITCH_OK checks=",checks);get_tree().quit(0)
	else:
		for failure in failures:push_error(failure)
		get_tree().quit(1)
