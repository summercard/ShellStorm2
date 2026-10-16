extends Node3D
const PLAYER=preload("res://scenes/Player3D.tscn")
var failures:Array[String]=[]
func _ready() -> void:
	var p:=PLAYER.instantiate() as Player3D;add_child(p)
	p.set_physics_process(false);p.set_process(false);p.avatar.set_process(false)
	await get_tree().process_frame
	p.position=Vector3.ZERO;p.aim_direction=Vector3.FORWARD;p.aim_yaw=0
	p.get_node("Camera3D").current=false;p.get_node("AimCursor").visible=false
	var camera:=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6
	camera.position=Vector3(3,3,4);camera.look_at(Vector3(0,.65,0));camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("34414b");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.9;add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);add_child(light)
	for ui in get_tree().root.find_children("*","Control",true,false):ui.visible=false
	var motion:CharacterMotionLibrary3D=p.avatar.get("_authored_motion")
	var pool:=get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	var cases=[
		["axe","charging","charging","melee_axe_charge",VfxPool3D.FX01_AXE_CHARGE,.8,1.0],
		["axe","charged","windup","melee_axe_charged_windup","",1,.08],
		["axe","charged","active","melee_axe_charged_active",VfxPool3D.FX01_AXE_CLEAVE,1.2,.18],
		["axe","charged","recovery","melee_axe_charged_recovery",VfxPool3D.FX01_AXE_IMPACT,1.5,.7],
		["blade","charging","charging","melee_blade_charge","",1,.35],
		["blade","spin","spinning","melee_blade_spin",VfxPool3D.FX01_BLADE_WHIRLWIND,2.65,.55],
		["blade","spin","recovery","melee_blade_spin_recovery","",1,.3],
		["blade","normal","active","melee_blade_1_active",VfxPool3D.FX01_BLADE_SWEEP,1.2,.14]]
	for c in cases:
		p.equip_weapon("bp_waraxe" if c[0]=="axe" else "bp_greatblade","");await get_tree().process_frame
		p.weapon.set_process(false);p.melee_combat.set("_attack_mode",c[1]);p.melee_combat.set("_phase",c[2]);p.melee_combat.set("_combo_index",0);p.melee_combat.set("_phase_duration",1.0)
		var fx:VfxEffectBase3D=null
		if c[4]!="":
			fx=pool.acquire(c[4],Vector3(0,.65,0),Color.WHITE,c[5],{"duration":c[6]});fx.set_process(false)
		for i in range(33):
			var t:=i/32.0
			p.melee_combat.set("_phase_elapsed",t);p.melee_combat.set("_spin_elapsed",t*.55)
			p.avatar.call("_process",.02)
			if motion.active_clip!=c[3]:failures.append("wrong clip "+str(c[3]))
			if motion.palm_global(p.avatar,"l").distance_to(p.avatar.weapon_socket.global_transform*Vector3(0,0,.18))>.002:failures.append("support grip "+str(c[3]))
			if fx!=null:fx.call("_on_tick",t*float(c[6]),float(c[6]))
			await get_tree().process_frame;await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("BUNNY_VERIFICATION_OUTPUT")+"/%s_%02d.png"%[c[3],i])
		if fx!=null:fx.finish()
	p.melee_combat.cancel("test_done")
	if failures.is_empty():print("BUNNY_MELEE_SPECIAL_VISUAL_OK frames=264")
	else:push_error(str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
