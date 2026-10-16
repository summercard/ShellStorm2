extends Node3D
const PLAYER = preload("res://scenes/Player3D.tscn")
const ENEMY = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d.tscn")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _ready() -> void:
	var p := PLAYER.instantiate() as Player3D
	add_child(p);p.set_physics_process(false);p.set_process(false)
	await get_tree().process_frame
	p.position=Vector3.ZERO;p.aim_direction=Vector3.FORWARD;p.combat_enabled=true
	var machine: StateMachine=p.get("_state_machine");machine.stop();machine.start("idle")
	var combat:=p.melee_combat
	var pool:=get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	check(pool!=null,"runtime VFX pool")
	var targets:Array[Enemy3D]=[]
	for pos in [Vector3(0,0,-1.3),Vector3(0,0,1.3),Vector3(1.3,0,0)]:
		var e:=ENEMY.instantiate() as Enemy3D;e.enemy_kind="melee_chaser";add_child(e)
		e.set_physics_process(false);e.position=pos;e.current_hp=10000;e.max_hp=10000;targets.append(e)
	p.equip_weapon("bp_baseball_bat","");await get_tree().process_frame
	check(combat.begin_trigger(),"bat press")
	check(combat.get_snapshot().phase=="windup","bat immediate ordinary attack")
	var bat_duration:float=combat.get_snapshot().phase_duration_s
	combat.cancel("test")
	p.equip_weapon("bp_waraxe","");await get_tree().process_frame
	check(combat.begin_trigger(),"axe press")
	check(pool.active_count(VfxPool3D.FX01_AXE_CHARGE)==1,"axe charge effect")
	combat.physics_update(.1);combat.release_trigger()
	check(combat.get_snapshot().phase_duration_s>bat_duration,"axe slower than bat")
	check(combat.get_snapshot().attack_mode=="normal","short axe hold ordinary")
	combat.cancel("test")
	combat.begin_trigger();combat.physics_update(1.0);combat.release_trigger()
	check(combat.get_snapshot().attack_mode=="charged","full charge release")
	check(pool.active_count(VfxPool3D.FX01_AXE_CHARGE)==0,"charge effect ends")
	combat.physics_update(.08)
	check(pool.active_count(VfxPool3D.FX01_AXE_CLEAVE)==1,"vertical cleave effect")
	combat.physics_update(.09)
	check(targets[0].current_hp<10000 and targets[1].current_hp==10000,"axe directional damage")
	check((targets[0].get("_external_velocity") as Vector3).length()>10.5,"charged knockback exceeds ordinary cap")
	check(int(p.get("_melee_hit_stop_ticks"))==4,"charged heavy hitstop")
	check(pool.active_count(VfxPool3D.FX01_AXE_IMPACT)==1,"ground impact effect")
	combat.cancel("test")
	p.equip_weapon("bp_greatblade","");await get_tree().process_frame
	combat.begin_trigger();combat.physics_update(.1);combat.release_trigger()
	check(combat.get_snapshot().attack_mode=="normal","sword short release combo")
	check(combat.request_attack(),"queue sword second sweep")
	combat.physics_update(1);combat.physics_update(1);combat.physics_update(1)
	check(combat.get_snapshot().combo_step==2,"sword alternating combo advances")
	combat.cancel("test");combat.begin_trigger();combat.physics_update(.35)
	check(combat.get_snapshot().phase=="spinning","hold enters whirlwind")
	check(is_equal_approx(combat.movement_multiplier(),.45),"spin movement cost")
	check(pool.active_count(VfxPool3D.FX01_BLADE_WHIRLWIND)==1,"whirlwind sustained VFX")
	var hp:Array[int]=[]
	for e in targets:hp.append(e.current_hp)
	combat.physics_update(.24)
	check(targets[1].current_hp==hp[1],"no early spin damage")
	combat.physics_update(.01)
	for i in targets.size():check(targets[i].current_hp<hp[i],"spin hits all directions")
	var before:=targets[1].current_hp;combat.resolve_active_hit()
	check(targets[1].current_hp==before,"spin tick deduplicates")
	combat.physics_update(.25);check(targets[1].current_hp<before,"next spin tick damages again")
	combat.release_trigger();check(pool.active_count(VfxPool3D.FX01_BLADE_WHIRLWIND)==0,"release ends whirlwind VFX")
	check(combat.get_snapshot().phase=="recovery","spin release recovery")
	combat.physics_update(.3);check(combat.get_snapshot().phase=="ready","spin recovery completes")
	combat.begin_trigger();combat.physics_update(.35);p.input_locked=true;combat.physics_update(.01)
	check(combat.get_snapshot().phase=="ready" and pool.active_count(VfxPool3D.FX01_BLADE_WHIRLWIND)==0,"lock interrupts spin and VFX")
	p.input_locked=false
	for id in [VfxPool3D.FX01_AXE_CHARGE,VfxPool3D.FX01_AXE_CLEAVE,VfxPool3D.FX01_AXE_IMPACT,VfxPool3D.FX01_BLADE_SWEEP,VfxPool3D.FX01_BLADE_WHIRLWIND]:
		var fx:=pool.acquire(id,Vector3.ZERO,Color.WHITE,1.0,{"follow":p,"duration":1.0})
		p.position.x+=1;fx.call("_process",.1)
		check(fx.global_position.is_equal_approx(p.global_position),"effect follows player")
		fx.finish();check(not fx.visible,"effect retires")
		var reused:=pool.acquire(id,Vector3.ZERO,Color.WHITE,1.0,{"duration":.1})
		check(reused.visible,"effect reusable");reused.call("_process",.2);check(not reused.visible,"effect expires")
	var path:=OS.get_environment("BUNNY_VERIFICATION_OUTPUT")+"/melee_styles_report.json"
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	if failures.is_empty():print("BUNNY_MELEE_STYLES_OK checks=",checks)
	else:push_error(str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
