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
## 受击体积用例的实测值，随验收报告一起落盘（业主可据此核对「盒子真的贴着模型」）。
var hit_volume_measurements: Dictionary = {}

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
	expect(presenter.animation_player.get_animation_list().size() == 17,"17 registered source clips")
	# Real activation ownership: no AI cast, pause/resume, save progress and one-time completion.
	expect(enemy.monitor_combat.presentation_context().action_id == "activate","Fresh boss starts black-screen activation")
	enemy.set_runtime_active(true);enemy.set_physics_process(false);enemy.set_process(false)
	player.global_position = enemy.global_position + Vector3(10.01,0,0)
	var initial_position := enemy.global_position
	enemy._physics_process(1.0)
	expect(not enemy.monitor_combat.activation_started and enemy.monitor_combat.activation_elapsed == 0.0,"Beyond 10m keeps black-screen frame zero")
	expect(enemy.global_position == initial_position and enemy.monitor_combat.skill_id.is_empty(),"Outside activation range cannot move or attack")
	enemy.take_damage(1);enemy._physics_process(0.1)
	expect(not enemy.monitor_combat.activation_started,"Remote nonlethal hit does not bypass proximity")
	player.global_position = enemy.global_position + Vector3(10.0,0,0);player.current_hp = 0
	enemy._physics_process(0.1)
	expect(not enemy.monitor_combat.activation_started,"Dead player cannot activate boss")
	player.current_hp = 100000
	enemy._physics_process(1.0)
	expect(enemy.monitor_combat.activation_started,"Exactly 10 world meters activates regardless of root scale")
	expect(enemy.ai_state == "alert" and enemy.monitor_combat.activation_elapsed == 1.0,"Activation owns alert before AI")
	expect(not enemy.transition_to("telegraph") and enemy.monitor_combat.skill_id.is_empty(),"Activation blocks attacks")
	var hp_before := enemy.current_hp;enemy.take_damage(1)
	expect(enemy.current_hp == hp_before-1 and enemy.ai_state == "alert","Activation damage applies without animation interrupt")
	enemy.set_runtime_active(false);enemy.monitor_combat.tick_activation(1.0)
	expect(enemy.monitor_combat.activation_elapsed == 1.0,"Dormant activation pauses")
	var intro_save := enemy.export_runtime_state()
	enemy.monitor_combat.activation_elapsed = 0.0;enemy.monitor_combat.activation_started = false;enemy.import_runtime_state(intro_save)
	expect(enemy.monitor_combat.activation_elapsed == 1.0 and not enemy.monitor_combat.activation_completed,"Activation save resumes exact progress")
	expect(enemy.monitor_combat.activation_started,"Started latch survives save/load")
	enemy.set_runtime_active(true);enemy.set_physics_process(false);enemy.set_process(false)
	player.global_position = enemy.global_position + Vector3(20,0,0)
	enemy.monitor_combat.tick_activation(5.39)
	expect(not enemy.monitor_combat.activation_completed and enemy.monitor_combat.skill_id.is_empty(),"Leaving range continues intro but cannot fight before its end")
	enemy.monitor_combat.tick_activation(0.02)
	expect(enemy.monitor_combat.activation_completed and enemy.ai_state == "idle","Activation ends at idle")
	enemy.set_runtime_active(false);enemy.set_runtime_active(true);enemy.set_physics_process(false);enemy.set_process(false)
	expect(enemy.monitor_combat.presentation_context().action_id != "activate","Reactivation never replays entrance")
	intro_save.erase("monitor_activation_completed");intro_save.erase("monitor_activation_elapsed");intro_save.erase("monitor_activation_started");enemy.import_runtime_state(intro_save)
	expect(enemy.monitor_combat.activation_completed,"Legacy save does not replay activation")
	for t in [0.0,1.0,3.5,5.0,6.4]:
		presenter.sync_context({"action_id":"activate","time":t},false)
		expect(presenter._faces.large_eye.mesh.visible == (t>=5.7),"Activation face visibility "+str(t))
		expect(float(presenter._code.get_shader_parameter("boot_reveal")) == clampf(floorf((t-0.6)*30.0)/27.0,0.0,1.0),"Boot reveal "+str(t))
	presenter.sync_context({"action_id":"idle","time":0.0},false)
	expect(presenter._faces.large_eye.mesh.visible and not presenter.activation_fx.visible,"Activation visuals reset on exit")
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
	await _verify_animated_hit_volumes(presenter)
	# Phase bags and save cancellation.
	for pair in [[0.66,2],[0.33,3]]:
		enemy.current_hp = int(enemy.max_hp*pair[0]);enemy._update_boss_phase();expect(enemy.boss_phase == pair[1],"HP phase boundary "+str(pair[0]))
	var saved := enemy.export_runtime_state();saved.ai_state = "attack";enemy.monitor_combat.skill_id = "monitor_ground_current"
	expect(enemy.import_runtime_state(saved) and enemy.ai_state == "alert" and enemy.monitor_combat.skill_id.is_empty(),"Load cancels dangerous cast")
	enemy.monitor_combat.activation_completed = false;enemy.monitor_combat.activation_elapsed = 2.0
	enemy.ai_state = "alert";enemy._die();expect(enemy.ai_state == "dead" and enemy.collision_layer == 0,"Death interrupts activation and disables collision")
	presenter.sync_context(enemy.monitor_combat.presentation_context());expect(presenter.action_id == "dead","Authored death binding")
	finish()

func finish() -> void:
	var report := {"checks":checks,"failures":failures,"exit_code":0 if failures.is_empty() else 1,"expected_errors":[],"unexpected_script_errors":[],"not_executed":[],"monitor_hit_volume":hit_volume_measurements}
	var file := FileAccess.open("res://assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/flow_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	for failure in failures:push_error(failure)
	if failures.is_empty():print("MONITOR_BOSS_FLOW_OK checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)


## ── 动画受击体积（2026-10-14 业主：「子弹要打在模型实体上」）─────────────────────
## 业主报的现象：屏幕总成在动画里歪出根节点那个固定圆柱，子弹从可见模型里穿过去、
## 在模型后面的空气里结算命中。下面把「受击盒跟着骨走、并且覆盖模型实体」钉成断言；
## 未覆盖时这些用例必须红 —— 它们就是那条「会失败的断言」。
func _verify_animated_hit_volumes(presenter: MonitorBossPresentation) -> void:
	var spec: Array = MonitorBossPresentation.get_hit_volume_spec()
	var hit_body := enemy.get_monitor_hit_volume_body()
	var hit_shapes := enemy.get_monitor_hit_volumes()
	expect(hit_body != null and hit_shapes.size() == spec.size() and spec.size() == 8,"Animated hit volumes build on the boss")
	if hit_body == null or hit_shapes.size() != spec.size():
		return
	# 代理体必须**另起一个体**：受击盒会伸进地面/墙里，挂在怪物自己身上时
	# `move_and_slide` 会把它顶起来（实测坐地抬高 0.42 m）。
	expect(hit_body != enemy and hit_body.get_parent() == enemy,"Hit volumes live on a separate passive body")
	expect(hit_body.collision_layer == 4 and hit_body.collision_mask == 0,"Hit volumes are on the bullet layer and block nobody")
	# 转发面：子弹拿到的 collider 是代理 ⇒ 伤害入口漏一个就会静默不掉血。
	for method in ["take_projectile_damage","take_damage","notify_attacked_by","can_absorb_projectile","on_projectile_absorbed","apply_slow","apply_damage_over_time","apply_pull","apply_fate_element"]:
		expect(hit_body.has_method(method),"Hit volume forwards "+method)
	var shapes_ok := true
	for index in range(spec.size()):
		var box_shape := hit_shapes[index].shape as BoxShape3D
		shapes_ok = shapes_ok and box_shape != null and box_shape.size.is_equal_approx(spec[index]["size"] as Vector3)
		shapes_ok = shapes_ok and hit_shapes[index].get_parent() == hit_body
	expect(shapes_ok,"Hit volume boxes carry the frozen bone-local sizes")
	# 盒子位置必须等于「骨世界姿态 × 骨局部中心」——用骨架重算一遍，不复用表现层的函数。
	var follow_ok := true
	for probe in [["idle",0.0],["move",0.4],["heavy_spin_slam",64.0/30.0],["melee_keyboard",33.0/30.0]]:
		presenter.sync_context({"action_id":str(probe[0]),"time":float(probe[1])},false)
		enemy._sync_monitor_hit_volumes()
		for index in range(spec.size()):
			var bone_index := presenter.hit_volume_bone_index(str(spec[index]["bone"]))
			var independent := presenter.skeleton.global_transform * presenter.skeleton.get_bone_global_pose(bone_index) * Transform3D(Basis(),spec[index]["center"] as Vector3)
			follow_ok = follow_ok and hit_shapes[index].global_transform.origin.distance_to(independent.origin) < 0.0005
	expect(follow_ok,"Hit volumes follow the sampled bone poses exactly")
	# 几何覆盖率：模型「实体块」顶点必须落在受击盒里。
	var body_vertices := _collect_hit_test_vertices(presenter)
	var face_planes := _collect_face_planes(presenter)
	expect(body_vertices.size() > 10000,"Hit test samples the model body vertices")
	var worst_volume_ratio := 1.0
	var worst_cylinder_ratio := 1.0
	var worst_detail := ""
	var worst_decal_gap := 0.0
	var screen_shape: CollisionShape3D = null
	for index in range(spec.size()):
		if str(spec[index]["bone"]) == "monitor_spin":
			screen_shape = hit_shapes[index]
	for probe in [["idle",0.0],["move",0.8],["melee_keyboard",33.0/30.0],["melee_cable",27.0/30.0],["heavy_spin_slam",64.0/30.0],["special_channel",20.0/30.0],["activate",150.0/30.0],["stun_loop",24.0/30.0],["dead",40.0/30.0],["turn_left",12.0/30.0]]:
		presenter.sync_context({"action_id":str(probe[0]),"time":float(probe[1])},false)
		enemy._sync_monitor_hit_volumes()
		var points := _deform_body_points(presenter,body_vertices)
		var report := _coverage_report(points,body_vertices,hit_shapes)
		if float(report["ratio"]) < worst_volume_ratio:
			worst_volume_ratio = float(report["ratio"])
			worst_detail = str(probe[0])+"@"+str(snappedf(float(probe[1]),0.001))+" 未被覆盖最多的件: "+str(report["worst"])
		worst_cylinder_ratio = minf(worst_cylinder_ratio,_coverage_ratio(points,[enemy.collision_shape]))
		worst_decal_gap = maxf(worst_decal_gap,_face_decal_gap(presenter,face_planes,screen_shape))
	expect(worst_volume_ratio >= 0.99,"Animated hit volumes cover the model body (worst "+str(snappedf(worst_volume_ratio*100.0,0.01))+"%, "+worst_detail+")")
	# 这条是本次改动的**动机**：只有圆柱时覆盖不住，覆盖得住才说明修的是真问题。
	expect(worst_cylinder_ratio < 0.90,"Static cylinder alone cannot cover the animated body (worst "+str(snappedf(worst_cylinder_ratio*100.0,0.01))+"%)")
	# 五官是**保持世界朝向的平面贴片**（设计规定「不跟屏幕局部旋转」），绕屏幕轴转一圈
	# 在屏幕骨空间里扫出的范围比屏幕本体还大 —— 给它做盒子只会得到一圈假体积。
	# 它本身没有厚度，真正该保证的是「固体屏幕总在它正后方」，那才是子弹落点：
	expect(worst_decal_gap <= 0.45,"Screen volume stays right behind the face decals (max gap "+str(snappedf(worst_decal_gap,0.001))+" m)")
	# 受击盒会伸进地面（坐地）与墙里（扑砸）：如果把它挂在怪物**自己身上**，
	# `move_and_slide` 会把这些盒子当承重面，把怪顶起来 —— 实测坐地抬高 0.417 m。
	# 这条断言就是那个架构决定的守卫：盒子必须待在独立被动体上。
	enemy.global_position = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	enemy.rotation.y = 0.0
	presenter.sync_context({"action_id":"stun_enter","time":0.6},false)
	enemy._sync_monitor_hit_volumes()
	await get_tree().physics_frame
	var rest_position := enemy.global_position
	var max_lift := 0.0
	for frame in range(40):
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
		enemy.velocity.y -= 22.0/60.0
		enemy.move_and_slide()
		max_lift = maxf(max_lift,absf(enemy.global_position.y-rest_position.y))
	expect(max_lift < 0.05,"Hit volumes never lift or sink the boss (max "+str(snappedf(max_lift,0.001))+" m over 40 frames)")
	hit_volume_measurements = {
		"volume_count":hit_shapes.size(),
		"body_vertex_samples":body_vertices.size(),
		"worst_body_coverage":worst_volume_ratio,
		"worst_coverage_frame":worst_detail,
		"worst_cylinder_only_coverage":worst_cylinder_ratio,
		"worst_face_decal_gap_m":worst_decal_gap,
	}
	hit_volume_measurements["boss_lift_over_40_frames_m"] = snappedf(max_lift,0.001)
	await _verify_bullet_lands_on_the_screen(presenter,spec,hit_shapes)


## 真子弹 A/B：屏幕在 `heavy_spin_slam` 砸地帧会砸到身前约 3.8 m，而根节点圆柱前脸
## 只有 2.0 m。开受击盒 ⇒ 子弹停在**屏幕上**；关掉 ⇒ 晚一米多才停（这就是「隔空击中」）。
func _verify_bullet_lands_on_the_screen(presenter: MonitorBossPresentation,spec: Array,hit_shapes: Array[CollisionShape3D]) -> void:
	var hit_body := enemy.get_monitor_hit_volume_body()
	if hit_body == null:
		return
	var screen_index := -1
	for index in range(spec.size()):
		if str(spec[index]["bone"]) == "monitor_spin":
			screen_index = index
	expect(screen_index >= 0,"Screen hit volume exists")
	if screen_index < 0:
		return
	enemy.global_position = Vector3.ZERO
	enemy.rotation.y = 0.0
	enemy.velocity = Vector3.ZERO
	presenter.sync_context({"action_id":"heavy_spin_slam","time":64.0/30.0},false)
	enemy._sync_monitor_hit_volumes()
	await get_tree().physics_frame
	var aim := hit_shapes[screen_index].global_transform.origin
	var shot_from := aim + Vector3(0,0,-6.0)
	var hp_before := enemy.current_hp
	var with_volumes: Variant = await _fire_test_bullet(shot_from,Vector3(0,0,1))
	expect(with_volumes != null,"Bullet reaches the boss with animated volumes enabled")
	expect(enemy.current_hp < hp_before,"Bullet damages the boss through the hit volume")
	# 判据用「停在模型前表面多深」，而不是「点是否落在盒内」：
	# 子弹是半径 0.12 m 的球 + `safe_margin` 0.035 m，碰撞点在盒面外约 0.16 m。
	var front_z := INF
	for shape in hit_shapes:
		front_z = minf(front_z,_shape_aabb(shape).position.z)
	var with_behind := (with_volumes as Vector3).z - front_z if with_volumes != null else 999.0
	expect(absf(with_behind) <= 0.30,"Bullet stops on the model front surface (offset "+str(snappedf(with_behind,0.01))+" m)")
	# 关掉受击盒：同一发子弹只能打到后面的圆柱 —— 落点比模型前表面晚 1.7 m 以上，
	# 命中特效就出现在模型身后的空气里，这正是业主看到的「隔空击中」。
	hit_body.collision_layer = 0
	enemy.current_hp = hp_before
	var without_volumes: Variant = await _fire_test_bullet(shot_from,Vector3(0,0,1))
	hit_body.collision_layer = 4
	var without_behind := (without_volumes as Vector3).z - front_z if without_volumes != null else INF
	var late_by := (without_volumes as Vector3).z - (with_volumes as Vector3).z if without_volumes != null and with_volumes != null else 999.0
	expect(without_behind >= 0.50,"Without volumes the same shot stops "+str(snappedf(without_behind,0.01))+" m behind the model front (the reported 隔空命中)")
	expect(late_by > 0.5,"Animated volumes pull the impact forward by "+str(snappedf(late_by,0.01))+" m")
	hit_volume_measurements["bullet_on_model_offset_m"] = snappedf(with_behind,0.01)
	hit_volume_measurements["bullet_without_volumes_offset_m"] = snappedf(without_behind,0.01)
	hit_volume_measurements["bullet_pulled_forward_m"] = snappedf(late_by,0.01)


## 从 `origin` 朝 `direction` 打一发真子弹，返回它停下时的世界位置；未命中返回 null。
func _fire_test_bullet(origin: Vector3,direction: Vector3) -> Variant:
	var bullet := Projectile3D.new()
	bullet.configure({"direction":direction.normalized(),"speed":40.0,"damage":12,"hostile":false})
	add_child(bullet)
	bullet.global_position = origin
	bullet.set_physics_process(false)
	for step in range(120):
		await get_tree().physics_frame
		bullet._physics_process(1.0/60.0)
		if not bullet._active:
			return bullet.global_position
	return null


## 受击盒只覆盖「有体积的实体块」；数据线、弹簧臂细段与手指刻意排除
## （它们的盒子会比可视几何粗一圈，等于把「打在实体上」换成「打在空气里」）。
const HIT_TEST_CABLE_PREFIXES := ["Long data cable whip","Luminous data plug","Plug contact","Connector alloy collar","Data connector body","Connector front inset","Cable strain relief","Relief rib"]
const HIT_TEST_ARM_PREFIXES := ["Continuous spring cable","Sculpted glove","White cuff","Wrist sleeve","Metal wrist ferrule"]
## 五官是保持世界朝向的平面贴片（设计规定不跟屏幕局部旋转），单独按「屏幕是否在它正后方」验。
const HIT_TEST_FACE_PREFIXES := ["Texture large_eye","Texture round_eye","Texture mouth"]


func _collect_hit_test_vertices(presenter: MonitorBossPresentation) -> Array:
	return _collect_vertices(presenter,false)


func _collect_face_planes(presenter: MonitorBossPresentation) -> Array:
	var flat: Array = _collect_vertices(presenter,true)
	var grouped: Dictionary = {}
	for value in flat:
		var entry: Dictionary = value
		var label := str(entry["mesh"])
		if not grouped.has(label):
			grouped[label] = []
		(grouped[label] as Array).append(entry)
	var planes: Array = []
	for label in grouped:
		planes.append({"mesh":label,"verts":grouped[label]})
	return planes


## `faces = true` ⇒ 只收五官平面贴片；`false` ⇒ 只收「有体积的实体块」顶点
## （数据线 / 弹簧臂细段 / 手指一律排除，五官贴片也排除）。
func _collect_vertices(presenter: MonitorBossPresentation,faces: bool) -> Array:
	var rig := presenter.skeleton
	var collected: Array = []
	for node in presenter.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		var label := str(mesh.name)
		var is_face := false
		for prefix in HIT_TEST_FACE_PREFIXES:
			if label.begins_with(prefix):
				is_face = true
		var is_appendage := false
		for prefix in HIT_TEST_CABLE_PREFIXES:
			if label.begins_with(prefix):
				is_appendage = true
		for prefix in HIT_TEST_ARM_PREFIXES:
			if label.begins_with(prefix):
				is_appendage = true
		if is_face != faces:
			continue
		if not faces and is_appendage:
			continue
		var bind_to_bone: Array = []
		for i in range(mesh.skin.get_bind_count()):
			var bone := mesh.skin.get_bind_bone(i)
			if bone < 0:
				bone = rig.find_bone(mesh.skin.get_bind_name(i))
			bind_to_bone.append(bone)
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var stride := int(bones.size()/maxi(1,vertices.size()))
			for index in range(vertices.size()):
				var entry_bones: Array = []
				var entry_weights: Array = []
				for slot in range(stride):
					var bind := bones[index*stride+slot]
					var weight := weights[index*stride+slot]
					if bind >= bind_to_bone.size() or weight <= 0.0 or int(bind_to_bone[bind]) < 0:
						continue
					entry_bones.append(int(bind_to_bone[bind]))
					entry_weights.append(weight)
				if entry_bones.is_empty():
					continue
				collected.append({"mesh":label,"pos":vertices[index],"bones":entry_bones,"weights":entry_weights})
	return collected


## 五官贴片中心距屏幕受击盒表面的最大距离（米，0 = 落在盒内）。
func _face_decal_gap(presenter: MonitorBossPresentation,planes: Array,screen_shape: CollisionShape3D) -> float:
	if screen_shape == null:
		return 0.0
	var worst := 0.0
	for value in planes:
		var plane: Dictionary = value
		var verts: Array = plane["verts"]
		var center := Vector3.ZERO
		for entry_value in verts:
			var entry: Dictionary = entry_value
			var point := Vector3.ZERO
			var entry_bones: Array = entry["bones"]
			var entry_weights: Array = entry["weights"]
			for slot in range(entry_bones.size()):
				var bone := int(entry_bones[slot])
				var rest_inv := presenter.skeleton.get_bone_global_rest(bone).affine_inverse()
				point += (presenter.skeleton.get_bone_global_pose(bone)*rest_inv*(entry["pos"] as Vector3))*float(entry_weights[slot])
			center += presenter.skeleton.global_transform*point
		center /= maxf(1.0,float(verts.size()))
		worst = maxf(worst,_distance_to_shape(center,screen_shape))
	return worst


func _shape_aabb(shape: CollisionShape3D) -> AABB:
	if shape == null or shape.shape == null:
		return AABB()
	var half := Vector3.ZERO
	if shape.shape is BoxShape3D:
		half = (shape.shape as BoxShape3D).size*0.5
	elif shape.shape is CylinderShape3D:
		var cylinder := shape.shape as CylinderShape3D
		half = Vector3(cylinder.radius,cylinder.height*0.5,cylinder.radius)
	elif shape.shape is CapsuleShape3D:
		var capsule := shape.shape as CapsuleShape3D
		half = Vector3(capsule.radius,capsule.height*0.5,capsule.radius)
	var bounds := AABB()
	var first := true
	for sx in [-1.0,1.0]:
		for sy in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var corner := shape.global_transform*Vector3(sx*half.x,sy*half.y,sz*half.z)
				if first:
					bounds = AABB(corner,Vector3.ZERO)
					first = false
				else:
					bounds = bounds.expand(corner)
	return bounds


func _distance_to_shape(point: Vector3,shape: CollisionShape3D) -> float:
	if shape == null or shape.shape == null:
		return 0.0
	var local := shape.global_transform.affine_inverse()*point
	var half := (shape.shape as BoxShape3D).size*0.5 if shape.shape is BoxShape3D else Vector3.ZERO
	if half == Vector3.ZERO:
		return local.length()
	var excess := Vector3(
		maxf(0.0,absf(local.x)-half.x),
		maxf(0.0,absf(local.y)-half.y),
		maxf(0.0,absf(local.z)-half.z)
	)
	return excess.length()



## 把绑定空间顶点按本帧骨姿态变形，并换算到**世界空间**。
func _deform_body_points(presenter: MonitorBossPresentation,vertices: Array) -> PackedVector3Array:
	var rig := presenter.skeleton
	var rest_inv: Array[Transform3D] = []
	var poses: Array[Transform3D] = []
	for index in range(rig.get_bone_count()):
		rest_inv.append(rig.get_bone_global_rest(index).affine_inverse())
		poses.append(rig.get_bone_global_pose(index))
	var to_world := rig.global_transform
	var points := PackedVector3Array()
	points.resize(vertices.size())
	for index in range(vertices.size()):
		var entry: Dictionary = vertices[index]
		var point := Vector3.ZERO
		var entry_bones: Array = entry["bones"]
		var entry_weights: Array = entry["weights"]
		for slot in range(entry_bones.size()):
			var bone := int(entry_bones[slot])
			point += (poses[bone]*rest_inv[bone]*(entry["pos"] as Vector3))*float(entry_weights[slot])
		points[index] = to_world*point
	return points


func _coverage_ratio(points: PackedVector3Array,shapes: Array) -> float:
	if points.is_empty():
		return 1.0
	var inside := 0
	for point in points:
		if _point_in_any(point,shapes):
			inside += 1
	return float(inside)/float(points.size())


## 覆盖率 + 「哪几个件漏得最多」——失败时直接告诉人该补哪根骨的盒子。
func _coverage_report(points: PackedVector3Array,vertices: Array,shapes: Array) -> Dictionary:
	var missed_by_mesh: Dictionary = {}
	var total_by_mesh: Dictionary = {}
	var inside := 0
	for index in range(points.size()):
		var mesh_name := str((vertices[index] as Dictionary)["mesh"])
		total_by_mesh[mesh_name] = int(total_by_mesh.get(mesh_name,0))+1
		if _point_in_any(points[index],shapes):
			inside += 1
		else:
			missed_by_mesh[mesh_name] = int(missed_by_mesh.get(mesh_name,0))+1
	var worst: Array = []
	for mesh_name in missed_by_mesh:
		worst.append({"mesh":mesh_name,"missed":int(missed_by_mesh[mesh_name]),"total":int(total_by_mesh[mesh_name])})
	worst.sort_custom(func(a,b):return int(a["missed"]) > int(b["missed"]))
	var summary: Array = []
	for entry in worst.slice(0,4):
		summary.append("%s %d/%d" % [entry["mesh"],entry["missed"],entry["total"]])
	return {"ratio":float(inside)/maxf(1.0,float(points.size())),"worst":summary}


func _point_in_any(point: Vector3,shapes: Array,tolerance := 0.0) -> bool:
	for value in shapes:
		if _point_in_shape(point,value as CollisionShape3D,tolerance):
			return true
	return false


func _point_in_shape(point: Vector3,shape: CollisionShape3D,tolerance := 0.0) -> bool:
	if shape == null or shape.disabled or shape.shape == null:
		return false
	# 容差按形状自身的尺度折算，所以要先量一下形状的局部单位长度对应的世界长度。
	var scale := shape.global_transform.basis.get_scale().length()/sqrt(3.0)
	var local := shape.global_transform.affine_inverse()*point
	var slack := tolerance/maxf(0.0001,scale)
	if shape.shape is BoxShape3D:
		var half := (shape.shape as BoxShape3D).size*0.5
		return absf(local.x) <= half.x+slack and absf(local.y) <= half.y+slack and absf(local.z) <= half.z+slack
	if shape.shape is CylinderShape3D:
		var cylinder := shape.shape as CylinderShape3D
		return absf(local.y) <= cylinder.height*0.5+slack and Vector2(local.x,local.z).length() <= cylinder.radius+slack
	if shape.shape is CapsuleShape3D:
		var capsule := shape.shape as CapsuleShape3D
		var half_height := maxf(0.0,capsule.height*0.5-capsule.radius)
		var clamped := clampf(local.y,-half_height,half_height)
		return (local-Vector3(0,clamped,0)).length() <= capsule.radius+slack
	return false

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
