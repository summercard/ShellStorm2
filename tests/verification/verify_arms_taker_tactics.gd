extends "res://tests/verification/support/SecondEliteStateFixture.gd"

const PLAYER = preload("res://scenes/Player3D.tscn")
const MANSION = preload("res://scenes/ExpeditionLevel03_3D.tscn")
var camera: Camera3D
var projectile_pool: ProjectilePool3D
var rendered := false

class EquipmentTickProbe extends EliteArmsTakerEquipment:
	var calls := 0
	func _init(enemy: Node3D) -> void:
		super(enemy)
	func tick(_delta: float, _target: Node3D) -> void:
		calls += 1


func _ready() -> void:
	BaseManager.save_path = "user://arms_taker_tactics_verification.json"
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()
	rendered = DisplayServer.get_name() != "headless"
	setup_ground()
	_build_stage()
	await get_tree().physics_frame
	await _verify_melee()
	await _verify_enemy_melee()
	await _verify_electric()
	await _verify_electric_effect_lifecycle()
	await _verify_electric_range_and_cooldown()
	await _verify_phase()
	await _verify_equipment_tick_guards()
	_verify_unpooled_healing()
	for child in get_children():
		child.free()
	await _verify_mansion()
	clean_effects()
	await get_tree().process_frame
	finish("ARMS_TAKER_TACTICS_OK")


func _build_stage() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.0
	add_child(camera)
	_aim_camera(Vector3(0, 1.35, -3.1), Vector3(5.2, 5.1, -9.5))
	projectile_pool = ProjectilePool3D.new()
	add_child(projectile_pool)
	if not rendered:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.074, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.76, 0.95)
	env.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-56.0, -35.0, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100.0, 100.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.13, 0.17, 0.23)
	plane.material = floor_material
	floor_mesh.mesh = plane
	add_child(floor_mesh)


func _aim_camera(focus: Vector3, offset: Vector3) -> void:
	camera.global_position = focus + offset
	camera.look_at(focus)
	camera.make_current()


func _save_shot(file_name: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered frame unavailable")
	if image != null and not image.is_empty():
		check(image.save_png(VerificationOutput.path(file_name + ".png")) == OK, "Could not save " + file_name)


func _verify_melee() -> void:
	var enemy := make_enemy()
	var target := make_target(Vector3(0, 0.05, -1.6))
	bind_target(enemy, target)
	var combat := enemy.arms_taker_combat
	var kinds: Array[String] = []
	var hp := target.current_hp
	for index in 3:
		enemy.transition_to("chase")
		enemy._attack_timer = 0.0
		step(enemy)
		kinds.append(combat.action)
		var count_before := target.damage_events
		var hit_frame := 44 if index == 2 else 81
		for frame in hit_frame - 1:
			step(enemy)
		check(target.damage_events == count_before, "Melee damage fired before its authored contact")
		for frame in 3:
			step(enemy)
		check(target.damage_events == count_before + 1, "Melee did not resolve exactly one contact")
		if index == 2:
			check(enemy.avatar._formal_elite_root.get_presentation_snapshot().clip == "attack_heavy", "Third melee did not use heavy animation")
		enemy.transition_to("chase")
	check(kinds == ["swipe", "swipe", "heavy"], "Melee selection did not vary")
	check(hp - target.current_hp == enemy.contact_damage * 2 + roundi(enemy.contact_damage * 1.35), "Heavy damage used the wrong scale")
	enemy.free()
	target.free()
	await get_tree().physics_frame


func _verify_enemy_melee() -> void:
	var enemy := make_enemy()
	var target := make_enemy_target(Vector3(0, 0.05, -1.6), enemy.contact_damage + 1)
	enemy._target = target
	enemy.rotation.y = 0.0
	var selected := MonsterAIManager._select_visible_target(enemy, MonsterAIManager._records[enemy.get_instance_id()], 8.5)
	check(selected.get("target") == target, "收租人未选择普通怪近战目标")
	var combat := enemy.arms_taker_combat
	combat.cast_direction = Vector3.FORWARD
	combat._next_action = "swipe"
	check(combat.try_chase_action(Vector3(0, 0, -1.6), 1.6, 0.0), "收租人未进入普通怪近战动作")
	combat.active = true
	combat.action = "swipe"
	combat.elapsed = EliteArmsTakerCombat.HIT_TIME
	combat.committed = false
	combat.commit_attack()
	check(target.current_hp < enemy.contact_damage + 1, "收租人近战未对普通怪造成真实伤害")
	check(target.last_damage_source == enemy, "普通怪未记录收租人真实受击来源")
	check(not target.is_in_group("player_3d"), "普通怪误带玩家目标组")
	enemy.free()
	target.free()
	await get_tree().physics_frame


func _verify_electric() -> void:
	var enemy := make_enemy()
	var player := PLAYER.instantiate() as Player3D
	player.position = Vector3(0, 0.035, -7.5)
	add_child(player)
	camera.make_current()
	var combat := enemy.arms_taker_combat
	await get_tree().physics_frame
	bind_target(enemy, player)
	enemy.transition_to("chase")
	enemy._attack_timer = 0.0
	step(enemy)
	check(combat.action == "electric" and enemy.ai_state == "telegraph", "Midrange did not select the ranged action")
	check(is_instance_valid(combat._reticle), "Locked floor lacked its telegraph")
	var locked_floor := combat._cast_floor
	check(absf(locked_floor.y) < 0.02 and absf(locked_floor.z + 7.5) < 0.04, "Cast did not lock the player's actual floor")
	player.global_position = locked_floor + Vector3(1.6, 0.04, 0)
	for frame in 34:
		step(enemy)
	check(projectile_pool.get_snapshot().active == 0, "Mother projectile released before windup")
	check(enemy.avatar._formal_elite_root.get_presentation_snapshot().screen_charge > 0.5, "Charging screen was not driven by action progress")
	await _save_shot("01_screen_charge")
	var stage_camera := camera.global_transform
	_aim_camera(Vector3(0, 2.0, 0), Vector3(0, 1.5, -8.0))
	camera.size = 5.5
	await _save_shot("01b_screen_front")
	camera.size = 9.0
	camera.global_transform = stage_camera
	for frame in 12:
		step(enemy)
	check(combat.attack_attempts == 1 and projectile_pool.get_snapshot().active == 1, "Expected exactly one mother projectile")
	for node in projectile_pool.get_children():
		var mother := node as Projectile3D
		if mother != null and mother.visible:
			_check_electric_light_and_size(mother._visual, true)
	var before_hp := player.current_hp
	var children: Array[Projectile3D] = []
	for frame in 95:
		await get_tree().physics_frame
		if combat.active:
			step(enemy)
		children = _electric_children()
		if not children.is_empty():
			break
	check(children.size() == 8, "Physical floor contact did not produce eight electric children (got %d)" % children.size())
	check(player.current_hp == before_hp, "Mother projectile dealt direct damage")
	var directions := {}
	for projectile in children:
		check(absf(projectile.speed - 4.4) < 0.001 and absf(projectile.direction.y) < 0.001, "Electric child did not use a slow planar velocity")
		check(absf(projectile.global_position.y - 0.26) < 0.05, "Electric child was not launched from floor height")
		directions[roundi(rad_to_deg(atan2(projectile.direction.x, projectile.direction.z)) / 45.0)] = true
	check(directions.size() == 8, "Electric children were not spaced by 45 degrees")
	for child in children:
		_check_electric_light_and_size(child._visual, true)
		check(absf((child._collision_shape.shape as SphereShape3D).radius - 0.12) < 0.001, "Visual enlargement changed electric hit radius")
	if rendered:
		for frame in 8:
			await get_tree().physics_frame
			if combat.active:
				step(enemy)
		await _save_shot("02_electric_radial")
	for frame in 90:
		if player._electric_root_remaining > 0.0:
			break
		await get_tree().physics_frame
		if combat.active:
			step(enemy)
	check(player.current_hp < before_hp and player._electric_root_remaining > 0.95, "Physical electric hit did not root for one second")
	check(is_instance_valid(player._electric_root_fx) and player._electric_root_fx.has_follow_target(), "Electric arc did not follow the hit player")
	if is_instance_valid(player._electric_root_fx):
		_check_electric_light_and_size(player._electric_root_fx, false)
	player.set_test_move_direction(Vector3.RIGHT)
	player.request_dash()
	check(not player.apply_knockback(Vector3.RIGHT), "Root queued horizontal knockback")
	check(enemy.avatar._formal_elite_root.get_presentation_snapshot().screen_charge < 0.01, "Screen stayed charged after recovery")
	var rooted_position := player.global_position
	var held_frames := 0
	if rendered:
		_save_shot("03_player_electric_root")
	while player._electric_root_remaining > 0.0 and held_frames < 72:
		held_frames += 1
		await get_tree().physics_frame
		check(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(rooted_position.x, rooted_position.z)) < 0.025, "Movement leaked while rooted")
		check(not player.is_dashing, "Dash started while rooted")
	check(held_frames >= 58 and held_frames <= 62 and player._electric_root_fx == null, "Root/visual did not expire after one second (%d physics frames)" % held_frames)
	for frame in 12:
		await get_tree().physics_frame
	check(player.global_position.x > rooted_position.x + 0.1, "Walking did not resume after root")
	player.set_test_move_direction(null)
	await _verify_wall_and_invulnerability(enemy, player)
	enemy.free()
	player.free()
	for node in projectile_pool.get_children():
		var projectile := node as Projectile3D
		if projectile != null and projectile.visible:
			projectile._retire()
	clean_effects()
	await get_tree().physics_frame


func _verify_wall_and_invulnerability(enemy: Enemy3D, player: Player3D) -> void:
	var combat := enemy.arms_taker_combat
	for projectile in _electric_children():
		projectile._retire()
	enemy.transition_to("chase")
	enemy._attack_timer = 0.0
	combat.electric_cooldown = 0.0
	player.global_position = Vector3(0, 0.04, -7.5)
	bind_target(enemy, player)
	step(enemy)
	check(enemy.ai_state == "telegraph", "Wall test could not start the cast")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 8.0, 0.4)
	collision.shape = shape
	wall.position = Vector3(0, 4.0, -3.6)
	wall.add_child(collision)
	add_child(wall)
	await get_tree().physics_frame
	for frame in 45:
		enemy.arms_taker_combat.tick(1.0 / 60.0)
	for frame in 45:
		await get_tree().physics_frame
	check(_electric_children().is_empty() and projectile_pool.get_snapshot().active == 0, "Wall impact spread eight projectiles")
	wall.free()
	player.is_invincible = true
	player._invincible_remaining = 5.0
	var hp := player.current_hp
	var projectile := projectile_pool.acquire({"hostile": true, "damage": 5, "shooter": enemy,
		"direction": Vector3.FORWARD, "speed": 4.4, "behavior": {"electric_root_seconds": 1.0}}, player.global_position + Vector3(0, 0.29, 1.0))
	for frame in 30:
		await get_tree().physics_frame
	check(not projectile.visible and player.current_hp == hp and player._electric_root_remaining == 0.0, "Invulnerable contact applied electric root")


func _check_electric_light_and_size(effect: VfxEffectBase3D, projectile: bool) -> void:
	var light := effect.get_node("ElectricLight") as OmniLight3D
	check(light != null and light.visible and light.light_energy > 0.70 and not light.shadow_enabled, "Electric effect did not activate its blue local light")
	if light != null:
		check(is_equal_approx(light.omni_range, (2.6 if projectile else 3.0) * effect.effect_size), "Electric light used an incorrect range")
	var arc := effect.get_node("Arc0") as Node3D
	var expected_size := (Vector3.ONE if projectile else Vector3(2.4, 2.4, 2.9)) * effect.effect_size * 2.0
	var ratio := arc.scale.x / expected_size.x
	check(ratio >= 0.75 and ratio <= 1.001, "Electric geometry did not double its visual dimensions")


func _electric_children() -> Array[Projectile3D]:
	var children: Array[Projectile3D] = []
	for node in projectile_pool.get_children():
		var projectile := node as Projectile3D
		if projectile != null and projectile.visible and projectile.bullet_tags.has("electric"):
			children.append(projectile)
	return children


func _verify_electric_effect_lifecycle() -> void:
	var effect := VfxPool3D.create_unpooled(VfxPool3D.FX01_BULLET_ELECTRIC)
	add_child(effect)
	var light := effect.get_node("ElectricLight") as OmniLight3D
	effect.activate(Vector3(3, 1, 2), Color.CYAN, 1.0, {"projectile": true})
	effect.deactivate()
	check(light.light_energy == 0.0 and not light.visible, "Projectile return left a live electric light")
	effect.activate(Vector3(4, 1, 3), Color.CYAN, 1.0, {"projectile": true})
	check(light.light_energy > 0.7 and light.visible, "Reused electric effect failed to relight")
	effect.deactivate()
	effect.activate(Vector3(4, 1, 3), Color.CYAN, 1.0, {"follow": self, "duration": 1.0})
	check(effect.has_follow_target(), "Sustained electric effect lost its follow attachment")
	effect.finish()
	check(light.light_energy == 0.0 and not light.visible, "Root completion left a live electric light")
	await get_tree().process_frame


func _verify_electric_range_and_cooldown() -> void:
	var enemy := make_enemy()
	var target := make_target(Vector3.ZERO)
	var combat := enemy.arms_taker_combat
	bind_target(enemy, target)
	for test: Vector3 in [Vector3(3.99, 0, 0), Vector3(4.0, 0, 1), Vector3(12.0, 0, 1), Vector3(12.01, 0, 0), Vector3(7.0, 1.51, 0)]:
		enemy.transition_to("chase")
		target.global_position = enemy.global_position + Vector3(0, test.y, -test.x)
		enemy._attack_timer = 0.0
		var started := combat.try_chase_action(Vector3.FORWARD * test.x, test.x, 0.0)
		check(started == (test.z > 0.0), "Electric range/height boundary failed at %s" % test)
	enemy.transition_to("chase")
	target.global_position = enemy.global_position + Vector3.FORWARD * 7.0
	check(combat.try_chase_action(Vector3.FORWARD * 7.0, 7.0, 0.0), "Cooldown test could not begin cast")
	combat.tick(0.70)
	check(is_equal_approx(combat.electric_cooldown, 8.0), "Mother projectile did not start an eight-second cooldown")
	var saved := enemy.export_runtime_state()
	combat.electric_cooldown = 0.0
	enemy.import_runtime_state(saved)
	check(is_equal_approx(combat.electric_cooldown, 8.0), "Room restore lost the electric cooldown")
	enemy.transition_to("chase")
	enemy._attack_timer = 0.0
	combat.tick(7.99)
	check(not combat.try_chase_action(Vector3.FORWARD * 7.0, 7.0, 0.0), "Electric cast began before eight seconds")
	combat.tick(0.01)
	check(combat.try_chase_action(Vector3.FORWARD * 7.0, 7.0, 0.0), "Electric cast was blocked at eight seconds")
	for node in projectile_pool.get_children():
		var projectile := node as Projectile3D
		if projectile != null and projectile.visible:
			projectile._retire()
	enemy.free()
	target.free()
	await get_tree().physics_frame


func _verify_phase() -> void:
	var enemy := make_enemy()
	var target := make_target(Vector3(0, 0.05, -8.0))
	enemy.set_room_bounds(Transform3D.IDENTITY, Vector2(17.5, 17.5))
	enemy.move_speed = 0.12
	enemy._attack_timer = 90.0
	bind_target(enemy, target)
	enemy.transition_to("chase")
	for frame in 359:
		await get_tree().physics_frame
		step(enemy)
	check(enemy.ai_state == "chase" and enemy.arms_taker_combat.chase_elapsed > 5.95, "Phase began before six seconds of chase")
	await get_tree().physics_frame
	step(enemy)
	var combat := enemy.arms_taker_combat
	check(combat.action == "phase" and enemy.ai_state == "telegraph", "Six-second chase did not initiate phase windup")
	for frame in 22:
		step(enemy)
	check(enemy.visible and not combat.phase_intangible, "Windup disabled combat too early")
	check(enemy.avatar._formal_elite_root.get_presentation_snapshot().glitch > 0.5, "Body glitch missing during departure")
	await _save_shot("04_phase_glitch_out")
	for frame in 5:
		step(enemy)
	check(combat.phased_out and not enemy.visible and enemy.is_concealed_in_world(), "Enemy remained visible after phase windup")
	check(enemy.get_animated_hit_volume_body().collision_layer == 0 and enemy.collision_mask == 0 and not enemy.is_in_group("damageable_3d"), "Hidden enemy still had combat collision")
	var hp := enemy.current_hp
	enemy.take_damage(200)
	check(enemy.current_hp == hp, "A hidden phase consumed HP")
	var origin := enemy.global_position
	for frame in 179:
		step(enemy)
	check(combat.phased_out and enemy.global_position.is_equal_approx(origin), "Enemy returned before three seconds")
	# A completely visible room has no safe return. Reopen off-camera space and re-evaluate.
	var previous_camera := camera.global_transform
	camera.size = 180.0
	_aim_camera(Vector3(0, 0, -8.0), Vector3(0, 48.0, 0.5))
	step(enemy)
	check(combat.phased_out, "Enemy appeared inside a fully visible room")
	camera.size = 9.0
	camera.global_transform = previous_camera
	for frame in 17:
		await get_tree().physics_frame
		step(enemy)
		if not combat.phased_out:
			break
	check(not combat.phased_out and enemy.ai_state == "recovery" and combat.phase_intangible, "Enemy failed to materialize after a legal spot opened")
	check(enemy._is_point_inside_room_hint(enemy.global_position) and enemy.global_position.distance_to(target.global_position) >= 4.0, "Phase violated room bounds or player clearance at %s (distance %.3f)" % [enemy.global_position, enemy.global_position.distance_to(target.global_position)])
	check(not camera.is_position_in_frustum(enemy.global_position + Vector3.UP), "Phase destination was on screen")
	if not combat.phased_out:
		_aim_camera(enemy.global_position + Vector3.UP * 1.6, Vector3(4.6, 3.6, -7.0))
		# Move the player during reentry to exercise the fresh range and facing check.
		target.global_position = enemy.global_position + Vector3(0, 0, -6.0)
		bind_target(enemy, target)
		for frame in 16:
			step(enemy)
		await _save_shot("05_phase_glitch_in")
		for frame in 10:
			step(enemy)
		check(enemy.ai_state == "recovery" and not is_instance_valid(combat._reticle), "Follow-up began while still materializing")
		step(enemy)
		check(enemy.ai_state == "telegraph" and combat.action == "electric" and is_instance_valid(combat._reticle), "Reentry did not start electric windup on its completion frame")
		check(enemy._attack_timer > 1.0 and is_zero_approx(combat.elapsed), "Follow-up waited for the ordinary attack timer or skipped its windup")
		check(combat._cast_floor.distance_to(Vector3(target.global_position.x, 0, target.global_position.z)) < 0.03, "Reentry failed to aim at the player's latest floor")
		for frame in 28:
			step(enemy)
		await _save_shot("07_phase_followup_charge")
	check(not combat.phase_intangible and enemy.get_animated_hit_volume_body().collision_layer == 4 and enemy.collision_mask == 1, "Hit volume/movement collision was not restored")
	_verify_phase_followup_rejections(enemy, target)
	# Loss of runtime activity clears the temporary phase without death or a new spawn.
	combat._next_action = "phase"
	enemy.transition_to("telegraph")
	for frame in 27:
		step(enemy)
	enemy.set_runtime_active(false, true)
	check(not combat.phased_out and not combat.active and enemy.ai_state == "dormant", "Room dormancy did not cancel phase")
	check(enemy.get_animated_hit_volume_body().collision_layer == 4 and enemy.current_hp == hp, "Dormancy altered the phase actor's combat identity")
	enemy.free()
	target.free()
	await get_tree().physics_frame


func _verify_equipment_tick_guards() -> void:
	var enemy := make_enemy()
	var target := make_target(Vector3(0, 0.05, -8.0))
	bind_target(enemy, target)
	enemy.transition_to("chase")
	var probe := EquipmentTickProbe.new(enemy)
	enemy.elite_equipment = probe
	step(enemy)
	check(probe.calls == 1, "装备 tick 探针未经过正式 Enemy tick")
	probe.calls = 0
	var combat := enemy.arms_taker_combat
	combat._next_action = EliteArmsTakerCombat.PHASE
	enemy.transition_to("telegraph")
	step(enemy)
	check(probe.calls == 0, "phase 前摇仍执行装备 tick")
	combat.phase_intangible = true
	step(enemy)
	check(probe.calls == 0, "phase 无实体期仍执行装备 tick")
	enemy.transition_to("chase")
	enemy._elite_escape_active = true
	step(enemy)
	check(probe.calls == 0, "撤退期间仍执行装备 tick")
	enemy._elite_escape_active = false
	enemy._elite_defeat_active = true
	step(enemy)
	check(probe.calls == 0, "跪地期间仍执行装备 tick")
	enemy.free()
	target.free()
	await get_tree().physics_frame


func _verify_unpooled_healing() -> void:
	# 工程 autoload 会常驻 VfxPool3D；这里验证正式 pooled 路径，不再把全局池
	# 的存在误报成 fallback 场景错误。独立无池分支由 VfxPool3D.create_unpooled
	# 直接验收，确保两条路径都产出同一正式 AssetID 和绿色实际数值。
	var pools := get_tree().get_nodes_in_group("vfx_pool_3d")
	check(not pools.is_empty(), "正式治疗验收缺少全局 VFX pool")
	var enemy := make_enemy()
	var pool := pools[0] as VfxPool3D
	if pool != null:
		pool.clear_all()
		var pooled := pool.acquire(VfxPool3D.FX02_HEAL_NUMBER, enemy.global_position + Vector3.UP * 1.55, VfxHealNumber3D.HEAL_COLOR, 1.0, {"text_value": "+7", "magnitude": 7})
		check(pooled is VfxHealNumber3D, "池化治疗未生成正式 VfxHealNumber3D")
		if pooled is VfxHealNumber3D:
			var pooled_label := pooled.get_node("HealLabel") as Label3D
			check(pooled_label.text == "+7" and pooled_label.modulate.is_equal_approx(VfxHealNumber3D.HEAL_COLOR), "池化治疗未使用正式绿色 +N 飘字")
		pool.clear_all()
	var unpooled := VfxPool3D.create_unpooled(VfxPool3D.FX02_HEAL_NUMBER)
	check(unpooled is VfxHealNumber3D, "无池治疗未生成正式 VfxHealNumber3D")
	if unpooled is VfxHealNumber3D:
		add_child(unpooled)
		unpooled.activate(enemy.global_position + Vector3.UP * 1.55, VfxHealNumber3D.HEAL_COLOR, 1.0, {"text_value": "+7", "magnitude": 7})
		var label := unpooled.get_node("HealLabel") as Label3D
		check(label.text == "+7" and label.modulate.is_equal_approx(VfxHealNumber3D.HEAL_COLOR), "无池治疗未使用正式绿色 +N 飘字")
		unpooled.free()
	enemy.free()


func _verify_phase_followup_rejections(enemy: Enemy3D, target: Node3D) -> void:
	var combat := enemy.arms_taker_combat
	for test: Vector2 in [Vector2(6.0, 1.0), Vector2(12.1, 0.0), Vector2(3.9, 0.0)]:
		enemy.transition_to("chase")
		target.global_position = enemy.global_position + Vector3.FORWARD * test.x
		combat._next_action = "phase"
		enemy.transition_to("telegraph")
		enemy.transition_to("recovery")
		combat.electric_cooldown = test.y
		combat.tick(0.45)
		check(enemy.ai_state == "chase" and not is_instance_valid(combat._reticle), "Reentry bypassed electric cooldown/range at %s" % test)


func _verify_mansion() -> void:
	var tower := MANSION.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20261104
	get_tree().root.add_child(tower)
	for frame in 900:
		if tower._rooms.size() >= 10 and is_instance_valid(tower.player):
			break
		await get_tree().process_frame
	tower.set_physics_process(false)
	tower.set_process(false)
	tower.player.set_physics_process(false)
	get_tree().current_scene = tower
	tower._ensure_roaming_elite()
	var elite: Enemy3D
	var actor_room: DungeonRoom3D
	for room: DungeonRoom3D in tower._rooms:
		if room.room_type not in tower._roaming_elite.rules.room_types or room.authored_layout_peaceful:
			continue
		tower.player.global_position = room.global_position + Vector3.UP * 0.05
		tower._on_room_entered(room)
		tower._retry_roaming_elite()
		await get_tree().process_frame
		for member: Enemy3D in tower._enemy_nodes_by_room.get(room.room_id, []):
			if tower._roaming_elite.owns(member.enemy_data):
				elite = member
				actor_room = room
				break
		if elite != null:
			break
	check(elite != null and elite.arms_taker_combat != null, "Official mansion did not assemble the tactics controller")
	if elite != null:
		for member in tower.get_node("ActiveEnemies").get_children():
			if member is Enemy3D:
				member.set_physics_process(false)
		await _verify_mansion_cast(tower, elite, actor_room)
	BaseManager.unregister_runtime_checkpoint_provider(tower, false)
	get_tree().current_scene = self
	tower.queue_free()
	await get_tree().process_frame


func _verify_mansion_cast(tower: TowerDescent3D, elite: Enemy3D, room: DungeonRoom3D) -> void:
	var player := tower.player
	var player_camera := player.get_node("Camera3D") as Camera3D
	player_camera.make_current()
	var flashlight := player.get_node("PlayerFlashlight3D") as PlayerFlashlight3D
	flashlight.set_physics_process(false)
	var combat := elite.arms_taker_combat
	var anchor := elite.global_position
	var found := false
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var candidate := anchor + Vector3(cos(angle), 0, sin(angle)) * 6.2
		if not elite._is_point_inside_room_hint(candidate):
			continue
		var floor_hit := combat._floor_below(candidate, 0.6, 0.7, player)
		if floor_hit.is_empty():
			continue
		player.global_position = (floor_hit["position"] as Vector3) + Vector3.UP * 0.05
		await get_tree().physics_frame
		if elite._has_line_of_sight(player):
			found = true
			break
	check(found, "Official room did not expose a clear ranged attack lane")
	if not found:
		return
	var direction := player.global_position - elite.global_position
	direction.y = 0.0
	elite.rotation.y = atan2(-direction.x, -direction.z)
	player.aim_direction = -direction.normalized()
	flashlight.set_charge_ratio(1.0)
	flashlight.set_light_enabled(true)
	for room_light in room._room_lights:
		room_light.set_light_enabled(true)
	tower._apply_indoor_camera_pose()
	bind_target(elite, player)
	elite.transition_to("chase")
	elite._attack_timer = 0.0
	elite._tick_chase(direction, direction.length(), 1.0 / 60.0)
	check(combat.action == "electric" and is_instance_valid(combat._reticle), "Official room failed to start electric cast through chase")
	check(not tower._counts_for_room_clear(elite.enemy_data) and tower._roaming_elite.owns(elite.enemy_data), "Tactics changed room-clear or roaming ownership")
	elite.visible = true
	for frame in 35:
		combat.tick(1.0 / 60.0)
		elite._process(0.0)
	await _save_shot("06_expedition03_charge")
	var hp := elite.current_hp
	var appearances := int(tower._roaming_elite.state.appearances)
	elite.transition_to("chase")
	var destination: Variant = combat._find_phase_destination(player)
	check(destination is Vector3 and elite._is_point_inside_room_hint(destination as Vector3), "Official room had no valid off-camera phase destination")
	if destination is Vector3:
		combat._next_action = "phase"
		elite.transition_to("telegraph")
		for frame in 27 + 180:
			combat.tick(1.0 / 60.0)
		check(elite.ai_state == "recovery" and elite.room_id == room.room_id and elite.current_hp == hp, "Mansion phase changed room/HP or missed its return")
		check(int(tower._roaming_elite.state.appearances) == appearances, "Phase incorrectly added another encounter")
