extends Node3D
const PLAYER = preload("res://scenes/Player3D.tscn")
const ENEMY = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
var checks := 0
var out := OS.get_environment("BUNNY_VERIFICATION_OUTPUT") + "/"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _ready() -> void:
	var visual := "--visual" in OS.get_cmdline_user_args()
	var p := PLAYER.instantiate() as Player3D
	add_child(p)
	p.set_physics_process(false); p.set_process(false); p.avatar.set_process(false)
	await get_tree().process_frame
	p.position = Vector3.ZERO; p.aim_direction = Vector3.FORWARD; p.aim_yaw = 0
	p.combat_enabled = true
	p.get_node("Camera3D").current = false; p.get_node("AimCursor").visible = false
	var camera := Camera3D.new(); add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4.5
	camera.position = Vector3(3,3,4); camera.look_at(Vector3(0,.6,0)); camera.current = true
	var w := WorldEnvironment.new(); w.environment = Environment.new()
	w.environment.background_mode = Environment.BG_COLOR; w.environment.background_color = Color("34414b")
	w.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; w.environment.ambient_light_energy = .9
	add_child(w)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-30,0); add_child(light)
	for ui in get_tree().root.find_children("*", "Control", true, false): ui.visible = false
	var motion: CharacterMotionLibrary3D = p.avatar.get("_authored_motion")
	var cache: Dictionary = motion.get("_cache")
	check(cache.version == "v041", "current library")
	for family: String in {"bat":"baseball_bat","blade":"greatblade","axe":"waraxe"}:
		var slug: String = {"bat":"baseball_bat","blade":"greatblade","axe":"waraxe"}[family]
		check(p.equip_weapon("bp_"+slug,""),"equip "+family)
		await get_tree().process_frame
		p.weapon.set_process(false)
		p.set("_presentation_state","idle");p.avatar.call("_process",.3)
		check(motion.active_clip == "melee_"+family+"_idle","held idle "+family)
		for step in range(1,4):
			p.melee_combat.set("_combo_index",step-1)
			var low := INF; var high := -INF
			for phase: String in ["windup","active","recovery"]:
				p.melee_combat.set("_phase",phase);p.melee_combat.set("_phase_duration",1.0)
				for i in range(21):
					p.melee_combat.set("_phase_elapsed",i/20.0)
					p.avatar.call("_process",.02)
					var snap := p.avatar.get_component_snapshot()
					check(motion.active_clip == "melee_%s_%d_%s" % [family,step,phase],"selected exact action")
					check(snap.right_hand_palm_to_socket_global_distance < .001,"palm grip")
					check(motion.palm_global(p.avatar,"l").distance_to(p.avatar.weapon_socket.global_transform * Vector3(0,0,.18)) < .002,"support palm grip")
					check(not snap.legacy_procedural_motion_enabled,"no procedural motion")
					var force_axis: float = p.avatar.body.rotation.x if family == "axe" else p.avatar.body.rotation.y
					low=minf(low,force_axis);high=maxf(high,force_axis)
					if visual and (i in [0,9,20] or step==3):
						await get_tree().process_frame; await RenderingServer.frame_post_draw
						get_viewport().get_texture().get_image().save_png(out+"%s_%d_%s_%02d.png" % [family,step,phase,i])
						if phase=="active" and i==9:
							camera.position=Vector3(4,1.4,0);camera.look_at(Vector3(0,.6,0))
							await get_tree().process_frame;await RenderingServer.frame_post_draw
							get_viewport().get_texture().get_image().save_png(out+"%s_%d_side.png" % [family,step])
							camera.position=Vector3(3,3,4);camera.look_at(Vector3(0,.6,0))
			check(rad_to_deg(high-low)>(14 if family == "axe" else 45),"torso force "+family)
		p.melee_combat.cancel("test_reset")
		for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
			p.velocity=direction*5;p.set("_presentation_state","moving");p.avatar.call("_process",.3)
			check(motion.active_overlay=="melee_"+family+"_idle","moving held pose")
		p.velocity=Vector3.ZERO;p.set("_presentation_state","idle")
	# Real combat state progression, hit timing, repeat prevention and local freeze.
	p.equip_weapon("bp_baseball_bat","")
	await get_tree().process_frame
	var machine: StateMachine = p.get("_state_machine"); machine.stop();machine.start("idle")
	var enemy := ENEMY.instantiate() as Enemy3D; enemy.enemy_kind="melee_chaser"; add_child(enemy)
	enemy.set_physics_process(false); enemy.position=Vector3(0,0,-1.3); enemy.max_hp=10000;enemy.current_hp=10000
	var second := ENEMY.instantiate() as Enemy3D; second.enemy_kind="melee_chaser";add_child(second)
	second.set_physics_process(false);second.position=Vector3(.25,0,-1.4);second.max_hp=10000;second.current_hp=10000
	p.melee_combat.cancel("test_reset");check(p.request_melee_attack(),"attack accepted")
	var hp := enemy.current_hp
	p.melee_combat.physics_update(1.0)
	check(enemy.current_hp==hp,"no damage on active entry")
	var duration: float=p.melee_combat.get_snapshot().phase_duration_s
	p.melee_combat.physics_update(duration*.45)
	check(enemy.current_hp<hp and second.current_hp<10000,"contact beat damages multiple targets")
	check(enemy.ai_state=="stagger" and float(enemy.get("_melee_stagger_remaining"))>0,"enemy stagger")
	hp=enemy.current_hp;p.melee_combat.resolve_active_hit();check(enemy.current_hp==hp,"one resolve per swing")
	var progress := p.melee_combat.get_phase_progress();var position := p.position
	p.call("_physics_process",1.0/60)
	check(is_equal_approx(p.melee_combat.get_phase_progress(),progress) and p.position==position,"freeze one physics update")
	check(p.is_melee_hit_stopped(),"freeze visible to avatar")
	await get_tree().physics_frame; await get_tree().process_frame
	p.call("_physics_process",1.0/60)
	check(p.melee_combat.get_phase_progress()>progress,"resume following tick")
	p.melee_combat.cancel("test_reset");check(not p.is_melee_hit_stopped(),"cancel clears freeze")
	enemy.apply_melee_stagger(.3);enemy.apply_melee_stagger(.2)
	check(is_equal_approx(float(enemy.get("_melee_stagger_remaining")),.3),"stagger max not sum")
	enemy.call("_physics_process",.31)
	check(is_zero_approx(float(enemy.get("_melee_stagger_remaining"))),"stagger expires")
	machine.stop();machine.start("idle");p.position=Vector3.ZERO;p.aim_direction=Vector3.FORWARD
	second.position=Vector3(0,0,12);enemy.position=Vector3(0,0,10);p.clear_melee_hit_stop();check(p.request_melee_attack(),"fresh test attack accepted");p.melee_combat.physics_update(1);p.melee_combat.physics_update(float(p.melee_combat.get_snapshot().phase_duration_s)*.5)
	check(not bool(p.get("_melee_hit_stop_pending")),"whiff no stop")
	p.melee_combat.cancel("whiff_done")
	machine.stop();machine.start("idle");p.position=Vector3.ZERO;p.aim_direction=Vector3.FORWARD
	enemy.position=Vector3(0,0,-1.3);enemy.current_hp=1
	check(p.request_melee_attack(),"fresh test attack accepted");p.melee_combat.physics_update(1);p.melee_combat.physics_update(float(p.melee_combat.get_snapshot().phase_duration_s)*.5)
	check(enemy.ai_state=="dead" and bool(p.get("_melee_hit_stop_pending")),"lethal hit stops player without reviving target")
	p.melee_combat.cancel("death_test_done")
	second.enemy_kind="boss";second.set("_melee_stagger_remaining",0.0);second.apply_melee_stagger(.3)
	check(is_zero_approx(float(second.get("_melee_stagger_remaining"))),"boss policy preserved")
	p.melee_combat.cancel("done")
	var file:=FileAccess.open(out+"melee_runtime_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	if failures.is_empty():print("BUNNY_MELEE_MOTION_OK checks=",checks)
	else:
		for f in failures:push_error(f)
	get_tree().quit(0 if failures.is_empty() else 1)
