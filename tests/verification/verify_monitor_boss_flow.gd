extends Node3D
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
var checks := 0
class DummyPlayer extends Node3D:
	var current_hp := 100000
	var hits: Array[int] = []
	func take_damage(amount: int,_critical := false,_direction := Vector3.ZERO) -> void:
		hits.append(amount);current_hp -= amount
var enemy: Enemy3D
var player: DummyPlayer

func expect(ok: bool,message: String) -> void:
	checks += 1
	if not ok:failures.append(message)

func _ready() -> void:
	var ground := StaticBody3D.new();var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size = Vector3(80,0.2,80);shape.shape = box;ground.position.y = -0.1;ground.add_child(shape);add_child(ground)
	player = DummyPlayer.new();player.add_to_group("player_3d");add_child(player)
	var injector := MonsterInjector.new()
	var config: Dictionary = injector._generate_boss(1,0,{"boss_content_id":"boss_monitor002","floor_number":0})
	expect(str(config.get("boss_content_id","")) == "boss_monitor002","Catalog→Injector identity")
	enemy = ENEMY.instantiate();add_child(enemy);enemy.configure_from_enemy_data(config)
	enemy.set_physics_process(false);enemy.set_process(false);enemy._target = player
	await get_tree().physics_frame
	var presenter := enemy.avatar._formal_boss_root as MonitorBossPresentation
	expect(presenter != null,"Formal presentation scene loads")
	if presenter == null:finish();return
	expect(presenter.scale == Vector3.ONE,"Prefab root scale1")
	expect(presenter.skeleton.get_bone_count() == 64,"64 bone identity")
	expect(presenter.animation_player.get_animation_list().size() == 16,"16 registered source clips")
	expect(not enemy.avatar.get_component_snapshot().procedural_pose,"Procedural posing retired")
	expect(presenter.find_children("*","CollisionObject3D",true,false).is_empty(),"Visual prefab has no physics")
	expect(enemy.collision_shape.shape is CylinderShape3D,"Gameplay owns unchanged Boss cylinder")
	var probes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/source_pose_probes.json"))
	var source_bounds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/source_mesh_bounds.json"))
	for clip in presenter.motion.clips:
		var duration := float(presenter.motion.clips[clip].duration)
		for frame in [0,int(duration*15),int(duration*30)-1]:
			presenter.sync_context({"action_id":clip,"time":frame/30.0},false)
			for bone in ["hand.L","hand.R","cable_16","monitor_tilt"]:
				var p: Array = probes[clip][frame][bone]
				expect(presenter.bone_point(bone).distance_to(Vector3(p[0],p[1],p[2])) < 0.002,"Baked pose "+clip+" "+bone+" frame"+str(frame))
			for mesh_name in source_bounds[clip][str(frame)]:
				var mesh := presenter.find_child(mesh_name,true,false) as MeshInstance3D
				var expected: Array = source_bounds[clip][str(frame)][mesh_name]
				var actual := skinned_bounds(mesh,presenter.skeleton)
				expect(actual.position.distance_to(Vector3(expected[0][0],expected[0][1],expected[0][2])) < 0.008 and actual.end.distance_to(Vector3(expected[1][0],expected[1][1],expected[1][2])) < 0.008,"Deformed mesh bounds "+clip+" "+mesh_name+" frame"+str(frame))
	# 60fps frames between the 30Hz samples retain stretch/shear and valid arm matrices.
	var affine := Transform3D(Basis(Vector3(1.7,0,0),Vector3(0.3,1.0,0),Vector3(0,0.2,0.8)),Vector3(1,2,3))
	expect(MonitorBossPresentation.interpolate_affine(affine,affine,0.5).is_equal_approx(affine),"Identical sheared pose survives interpolation")
	for clip in presenter.motion.clips:
		presenter.sync_context({"action_id":clip,"time":0.5/30.0},false)
		var valid := true
		for name in ["hand.L","hand.R"]:
			var index := (presenter.motion.bones as Array).find(name)
			var a := MonitorBossPresentation.matrix(presenter.motion.clips[clip].frames[0].bones[index]);var b := MonitorBossPresentation.matrix(presenter.motion.clips[clip].frames[1].bones[index])
			valid = valid and presenter.bone_point(name).distance_to(a.origin.lerp(b.origin,0.5)) < 0.002
		for pose in presenter._blended:valid = valid and pose.basis.is_finite() and absf(pose.basis.determinant()) > 0.001
		expect(valid,"Fractional arm sampling "+clip)
	for state in Enemy3D.VALID_STATES:
		if state == "dead":continue
		enemy.ai_state = "idle";enemy.transition_to(state)
		enemy.avatar.sync_boss_presentation(enemy.monitor_combat.presentation_context())
		expect(presenter.motion.clips.has(presenter.action_id),"State binding "+state)
	# Timeline: no damage before contact; single damage after contact; never repeated during recovery.
	for skill in MonitorBossCombat.SKILLS:
		enemy.ai_state = "idle";enemy._boss_skill_bag.assign([skill]);enemy._boss_skill_index = 0
		enemy.monitor_combat.electric_cooldown = 0.0;enemy.rotation.y = 0.0;enemy.global_position = Vector3.ZERO
		player.position = Vector3(0,0,-3.2);player.hits.clear()
		enemy.transition_to("telegraph");var combat := enemy.monitor_combat
		if skill == "monitor_ground_current":player.global_position = combat.contact_point
		var contact := float(combat.SKILLS[skill].windup)
		combat.tick(contact-0.002);expect(player.hits.is_empty(),skill+" no early damage")
		combat.tick(0.003);expect(player.hits.size() == 1,skill+" contact damages once")
		combat.tick(0.01);expect(player.hits.size() == 1,skill+" no duplicate impact")
		if skill == "monitor_ground_current":
			combat.tick(0.8);expect(player.hits.size() == 2,"Current second pulse")
			combat.on_damage(1,true,0,true);expect(enemy.ai_state == "stagger" and not combat.presentation_context().electric_active,"Current interrupt stops electric")
	# Range and cone rejection.
	for target in [Vector3(0,0,-20),Vector3(0,0,3),Vector3(0,4,-3)]:
		player.position = target;player.hits.clear();enemy.monitor_combat.skill_id = "monitor_cable";enemy.monitor_combat.hit_ids.clear();enemy.monitor_combat.contact_point = Vector3.ZERO;enemy.monitor_combat.deal_damage()
		expect(player.hits.is_empty(),"Cable range/cone/floor rejection "+str(target))
	var wall := StaticBody3D.new();var wallshape := CollisionShape3D.new();var wallbox := BoxShape3D.new();wallbox.size = Vector3(8,4,0.3);wallshape.shape = wallbox;wall.add_child(wallshape);wall.position = Vector3(0,1,-1.5);add_child(wall)
	await get_tree().physics_frame
	player.position = Vector3(0,0,-3.2);player.hits.clear();enemy.monitor_combat.hit_ids.clear();enemy.monitor_combat.deal_damage();expect(player.hits.is_empty(),"Attack cannot cross wall");wall.queue_free()
	# Seated hands must retain their low authored pose despite more hits.
	enemy.ai_state = "chase";enemy.monitor_combat.poise_damage = 0.0
	enemy.monitor_combat.on_damage(int(enemy.max_hp*0.08)+1,false,0,true)
	expect(enemy.ai_state == "stagger" and enemy.monitor_combat.seated,"Poise stun")
	enemy._state_time = 2.0;enemy.monitor_combat.on_damage(12,false,0,true);expect(enemy._state_time == 2.0,"Hits do not restart seated stun")
	presenter.sync_context(enemy.monitor_combat.presentation_context());expect(presenter.action_id == "stun_loop" and presenter.expression == 5,"Seated double spirals")
	enemy._state_time = 4.81;enemy.monitor_combat.tick(0.0);expect(enemy.ai_state == "chase","Stun recovers")
	# Run the real Enemy3D physics path: perception, token, cast, recovery and next skill.
	await get_tree().physics_frame
	enemy.monitor_combat.cancel();enemy.global_position = Vector3.ZERO;enemy.rotation.y = 0.0;enemy.velocity = Vector3.ZERO
	enemy.set_runtime_active(true);enemy.set_physics_process(false);enemy.set_process(false)
	enemy._boss_skill_bag.assign(["monitor_keyboard","monitor_cable","monitor_spin_slam","monitor_ground_current"]);enemy._boss_skill_index = 0;enemy._attack_timer = 0.0
	enemy.monitor_combat.electric_cooldown = 0.0;enemy.ai_state = "chase";player.position = Vector3(0,0,-3.2);player.hits.clear()
	MonsterAIManager.notify_enemy_attacked(enemy,player)
	var observed_skills: Dictionary = {};var observed_states: Dictionary = {}
	for frame in range(630):
		MonsterAIManager.invalidate_enemy(enemy);enemy._physics_process(1.0/30.0);enemy._process(1.0/30.0)
		observed_states[enemy.ai_state] = true
		if not enemy.monitor_combat.skill_id.is_empty():observed_skills[enemy.monitor_combat.skill_id] = true
		if observed_skills.size() == 4 and enemy.monitor_combat.skill_id.is_empty():break
	expect(observed_skills.size() == 4,"Actual AI executes all four skills")
	for state in ["telegraph","attack","recovery","chase"]:expect(observed_states.has(state),"Actual AI traverses "+state)
	for amount in [24,20,36,12]:expect(player.hits.has(amount),"Actual AI damage "+str(amount))
	expect(presenter.action_id in presenter.motion.clips,"Actual AI drives authored pose")
	# Facing turns advance from the body root and cancel the authored visual yaw.
	enemy.monitor_combat.cancel();enemy.rotation.y = 0.0;enemy.monitor_combat.face_target(Vector3.RIGHT,0.4)
	expect(enemy.monitor_combat.turning and absf(enemy.rotation.y) > 0.3,"Logic turn advances with visible clip")
	presenter.sync_context(enemy.monitor_combat.presentation_context(),false)
	expect(presenter.action_id in ["turn_left","turn_right"],"Turning chooses authored left/right")
	# Phase bags and save cancellation.
	for pair in [[0.66,2],[0.33,3]]:
		enemy.current_hp = int(enemy.max_hp*pair[0]);enemy._update_boss_phase();expect(enemy.boss_phase == pair[1],"HP phase boundary "+str(pair[0]))
	var saved := enemy.export_runtime_state();saved.ai_state = "attack";enemy.monitor_combat.skill_id = "monitor_ground_current"
	expect(enemy.import_runtime_state(saved) and enemy.ai_state == "alert" and enemy.monitor_combat.skill_id.is_empty(),"Load cancels dangerous cast")
	enemy.ai_state = "idle";enemy._die();expect(enemy.ai_state == "dead" and enemy.collision_layer == 0,"Death owns disable/cancel")
	presenter.sync_context(enemy.monitor_combat.presentation_context());expect(presenter.action_id == "dead","Authored death binding")
	finish()

func finish() -> void:
	var report := {"checks":checks,"failures":failures,"exit_code":0 if failures.is_empty() else 1,"expected_errors":[],"unexpected_script_errors":[],"not_executed":[]}
	var file := FileAccess.open("res://assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/flow_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	for failure in failures:push_error(failure)
	if failures.is_empty():print("MONITOR_BOSS_FLOW_OK checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func skinned_bounds(mesh: MeshInstance3D,rig: Skeleton3D) -> AABB:
	var bounds := AABB()
	var initialized := false
	var bind_transforms: Array[Transform3D] = []
	if mesh.skin:
		for i in range(mesh.skin.get_bind_count()):
			var bone := mesh.skin.get_bind_bone(i)
			if bone < 0:bone = rig.find_bone(mesh.skin.get_bind_name(i))
			bind_transforms.append(rig.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(i))
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var stride := int(bones.size()/vertices.size())
		for i in range(vertices.size()):
			var point := vertices[i]
			if stride > 0:
				point = Vector3.ZERO
				for j in range(stride):point += (bind_transforms[bones[i*stride+j]]*vertices[i])*weights[i*stride+j]
			else:point = rig.global_transform.affine_inverse()*mesh.global_transform*point
			if not initialized:bounds = AABB(point,Vector3.ZERO);initialized = true
			else:bounds = bounds.expand(point)
	return bounds
