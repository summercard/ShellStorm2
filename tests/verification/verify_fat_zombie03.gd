extends Node3D
const ENEMY := preload("res://scenes/enemies/fat_zombie03.tscn")
class Target extends Node3D:
	var hits := 0
	var damage := 0
	func take_damage(amount: int, _critical: bool, _direction: Vector3) -> void:
		hits += 1
		damage += amount
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _ready() -> void:
	var e := ENEMY.instantiate() as Enemy3D
	add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	var injector := MonsterInjector.new()
	var data := injector.generate_box_enemy("fat_zombie03", 1, RoomData.FloorLevel.SHALLOW)
	check(data.get("enemy_type") == "fat_zombie03", "explicit spawn ID")
	check("fat_zombie03" in SpawnBoxCatalog.ALLOWED_BOX_TYPES, "trigger catalog accepts fat zombie")
	var explicit := injector.generate_enemies({"type":"fat_zombie03", "count":2, "floor":1, "floor_level":0})
	check(explicit.size() == 2 and explicit[0].enemy_type == "fat_zombie03", "general explicit injector")
	check(injector.generate_box_enemy("invalid_fat", 1, 0).is_empty(), "unknown ID rejected")
	e.configure_from_enemy_data(data)
	await get_tree().process_frame
	check(e.enemy_kind == "fat_zombie03" and e.avatar.has_formal_normal(), "formal route")
	check(e.max_hp == 696 and e.contact_damage == 19, "baseline stats")
	check(absf(e.move_speed - 0.6) < 0.001, "run speed")
	check(absf(e.move_speed * float(Enemy3D.PROFILES.fat_zombie03.patrol_multiplier) - 0.3) < 0.001, "patrol speed")
	check(absf(e.collision_shape.shape.height * e.scale.y - 2.2) < 0.001, "world height")
	check(absf(e.collision_shape.shape.radius * e.scale.x - 0.77) < 0.001, "world radius")
	var waves := injector.build_waves_from_plan({"waves":[{"monsters":[{"type":"fat_zombie03", "count":2}]}]}, 1, 0, 1)
	check(waves.size() == 1 and waves[0].size() == 2 and waves[0][0].enemy_type == "fat_zombie03", "fixed wave spawn")
	var visual = e.avatar._formal_normal_root
	visual.set_process(false)
	var durations := {"idle":3.2,"walking":2.0,"running":1.2,"attack":2.5,"hurt":0.8,"dead":2.6,"awaken":1.2,"alert":0.6,"turn_l":0.8,"turn_r":0.8,"move_start":0.4,"move_stop":0.6,"hit_light":0.3}
	if OS.get_cmdline_user_args().has("--negative-loop"):
		visual._player.get_animation("attack").loop_mode = Animation.LOOP_LINEAR
	for clip in durations:
		check(visual._player.has_animation(clip), "missing " + clip)
		var a: Animation = visual._player.get_animation(clip)
		check(absf(a.length - durations[clip]) < 0.001, "duration " + clip)
		check(a.loop_mode == (Animation.LOOP_LINEAR if clip in ["idle","walking","running"] else Animation.LOOP_NONE), "loop " + clip)
	for state in Enemy3D.VALID_STATES:
		visual.sync_state(state, 0.1, 0.6, 1.2, 1.3)
		check(visual.get_presentation_snapshot().state == state, "state " + state)
		if state in ["chase","search","return"]:
			check(visual._clip == "running", "locomotion " + state)
	visual.sync_state("telegraph", 1.2, 0.0, 1.2, 1.3)
	check(is_equal_approx(visual._sample, 1.2), "telegraph boundary")
	visual.sync_state("attack", 0.0, 0.0, 1.2, 1.3)
	check(is_equal_approx(visual._sample, 1.2), "hit frame")
	visual.sync_state("recovery", 1.3, 0.0, 1.2, 1.3)
	check(is_equal_approx(visual._sample, 2.5), "recovery boundary")
	visual.sync_state("dormant", 0.0, 0.0, 1.2, 1.3)
	visual.sync_state("idle", 0.0, 0.0, 1.2, 1.3)
	check(visual._clip == "awaken", "activation clip")
	visual.sync_state("patrol", 0.0, 0.3, 1.2, 1.3)
	check(visual._clip == "move_start", "move start")
	visual.sync_state("idle", 0.0, 0.0, 1.2, 1.3)
	check(visual._clip == "move_stop", "move stop")
	visual._event_time = 1.0
	visual.sync_state("idle", 1.0, 0.0, 1.2, 1.3)
	e.rotation.y += 0.6
	visual.sync_state("idle", 1.0, 0.0, 1.2, 1.3)
	check(visual._clip == "turn_l", "left turn")
	visual.sync_state("chase", 0.0, 0.6, 1.2, 1.3)
	e.rotation.y -= 1.0
	visual.sync_state("idle", 0.0, 0.0, 1.2, 1.3)
	check(visual._clip == "turn_r", "right turn")
	visual.sync_state("chase", 0.1, 0.6, 1.2, 1.3)
	visual._locomotion_phase = 0.36
	visual.sync_state("chase", 0.1, 0.6, 1.2, 1.3)
	# 比较所有非上半身骨骼，防止误用全身hurt覆盖步态。
	var lower: Dictionary = {}
	for bone in visual._skeleton.get_bone_count():
		if visual._skeleton.get_bone_name(bone) not in visual.UPPER_BONES:
			lower[bone] = visual._skeleton.get_bone_pose(bone)
	visual.flash_hit()
	visual._light_time = 0.1
	visual.sync_state("chase", 0.1, 0.6, 1.2, 1.3)
	for bone in lower:
		check(lower[bone].is_equal_approx(visual._skeleton.get_bone_pose(bone)), "light hit changed lower bone " + str(bone))
	visual.sync_state("dead", 2.6, 0.0, 1.2, 1.3)
	var skin: MeshInstance3D = visual._meshes[0]
	var shape := skin.find_blend_shape_by_name("BellyGroundCompression")
	check(shape >= 0 and skin.get_blend_shape_value(shape) > 0.99, "dead belly compression")
	visual.sync_state("idle", 0.0, 0.0, 1.2, 1.3)
	check(skin.get_blend_shape_value(shape) < 0.001, "belly reset")
	var target := Target.new()
	add_child(target)
	e.rotation.y = 0.0
	e._target = target
	target.position = Vector3(0, 0, -1.4)
	await get_tree().physics_frame
	e._perform_attack(target.position, 1.4)
	check(target.hits == 1 and target.damage == 19 and e._external_velocity == Vector3.ZERO, "front clap damage without lunge")
	target.position = Vector3(0, 0, 1.4)
	e._perform_attack(target.position, 1.4)
	check(target.hits == 1, "behind target missed")
	target.position = Vector3(0, 0, -2.0)
	e._perform_attack(target.position, 2.0)
	check(target.hits == 1, "range miss")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.1)
	collider.shape = box
	wall.add_child(collider)
	add_child(wall)
	wall.position = Vector3(0, 0.8, -0.7)
	target.position = Vector3(0, 0, -1.4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	e._perform_attack(target.position, 1.4)
	check(target.hits == 1, "wall blocked hit")
	wall.free()
	e.transition_to("chase")
	e.take_damage(5)
	check(e.ai_state == "chase", "light hit staggered")
	e.take_damage(60)
	check(e.ai_state == "stagger" and is_equal_approx(float(Enemy3D.PROFILES.fat_zombie03.stagger), 0.8), "heavy stagger")
	var saved := e.export_runtime_state()
	check(saved.get("enemy_data", {}).get("enemy_type") == "fat_zombie03", "persistent ID")
	var scale_before := e.scale
	e._die()
	check(e.collision_layer == 0 and not e.is_in_group("enemy_3d") and not e.is_in_group("damageable_3d"), "death immediate removal")
	await get_tree().create_timer(2.45).timeout
	check(is_instance_valid(e) and e.scale.is_equal_approx(scale_before), "full death retained")
	await get_tree().create_timer(0.25).timeout
	check(not is_instance_valid(e), "death recycled")
	target.free()
	await verify_live_fsm(false)
	await verify_live_fsm(true)
	var report := {"passed":failures.is_empty(), "checks":checks, "failures":failures}
	DirAccess.make_dir_recursive_absolute("res://outputs/fat_zombie03_integration")
	var report_name := "negative_loop.json" if OS.get_cmdline_user_args().has("--negative-loop") else "runtime_verification.json"
	var output := FileAccess.open("res://outputs/fat_zombie03_integration/" + report_name, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	print("FAT_ZOMBIE03_RUNTIME_", "OK" if failures.is_empty() else "FAILED", " ", checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_live_fsm(dodge: bool) -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(15, 0.2, 15)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.1
	add_child(floor_body)
	var player := load("res://scenes/Player3D.tscn").instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(0, 0, -1.4)
	add_child(player)
	player.set_physics_process(false)
	var live := ENEMY.instantiate() as Enemy3D
	add_child(live)
	var states: Array[String] = []
	var damage_events: Array[int] = []
	live.state_changed.connect(func(_old: String, state: String): states.append(state))
	player.hp_changed.connect(func(hp: int, _maximum: int): damage_events.append(hp))
	live.notify_attacked_by(player)
	var before := player.current_hp
	await get_tree().create_timer(1.7).timeout
	var locked_yaw := live.rotation.y
	if dodge:
		player.position = Vector3(0, 0, 1.4)
	await get_tree().create_timer(0.4).timeout
	check("telegraph" in states and "attack" in states and "recovery" in states, "live FSM attack cycle")
	if dodge:
		check(damage_events.is_empty() and player.current_hp == before, "live dodge avoided clap")
		check(absf(wrapf(live.rotation.y - locked_yaw, -PI, PI)) < 0.01, "late telegraph facing locked")
	else:
		check(damage_events.size() == 1 and player.current_hp == before - 19, "live FSM one hit per clap")
	check(live.avatar._formal_normal_root.get_presentation_snapshot().clip == "attack", "live animation sampled attack")
	live.free()
	player.free()
	floor_body.free()
