extends Node

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const DAMAGE_NUMBER_SCRIPT := preload("res://src/fx/CombatDamageNumber3D.gd")

var _summon_count := 0


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame
	# 本专项没有搭建地面；冻结玩家物理，避免重力让视线射线从墙下穿过。
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	await _verify_ai_visibility_and_hp(player, failures)
	await _verify_hit_profiles(failures)
	await _verify_ambusher(player, failures)
	await _verify_ranged_volley(failures)
	await _verify_summoner_support(failures)
	await _verify_shield_facing(failures)
	await _verify_exploder_fragments(failures)
	_verify_damage_number_presentation(failures)
	for child in get_children():
		if child is Projectile3D or child is Enemy3D or child.get_script() == DAMAGE_NUMBER_SCRIPT:
			child.queue_free()
	if failures.is_empty():
		print("3D_ENEMY_BEHAVIOR_FLOW_OK: line-of-sight AI, scaled 3D HP, matched hit volumes, buried ambush, ranged volley, summon/heal support, frontal shield and death fragments pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_ai_visibility_and_hp(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3.ZERO
	var source_hp := {
		"melee_chaser": 25, "ranged_caster": 15, "summoner": 30,
		"shielded": 40, "exploder": 10, "ambusher": 18, "boss": 200,
	}
	var source_damage := {
		"melee_chaser": 5, "ranged_caster": 8, "summoner": 0,
		"shielded": 3, "exploder": 15, "ambusher": 7, "boss": 20,
	}
	var size_multipliers: Dictionary = {}
	for kind in source_hp.keys():
		var enemy := _make_enemy(str(kind), Vector3(70 + source_hp.keys().find(kind) * 2, 0, 70))
		await get_tree().process_frame
		enemy.configure_from_enemy_data({
			"enemy_type": kind, "hp": source_hp[kind], "max_hp": source_hp[kind],
			"damage": source_damage[kind], "speed": 60,
		})
		var expected_multiplier := Enemy3D.BOSS_HP_MULTIPLIER if kind == "boss" else Enemy3D.NORMAL_HP_MULTIPLIER
		var expected_hp := int(round(float(Enemy3D.PROFILES[kind]["hp"]) * expected_multiplier))
		if enemy.max_hp != expected_hp:
			failures.append("3D HP balance multiplier mismatch: %s=%d expected=%d" % [kind, enemy.max_hp, expected_hp])
		var expected_speed := 60.0 / 24.0 * Enemy3D.GLOBAL_MOVE_SPEED_MULTIPLIER
		if not is_equal_approx(enemy.move_speed, expected_speed):
			failures.append("3D enemy speed is not 70%% baseline: %s=%.3f" % [kind, enemy.move_speed])
		var state := enemy.get_state_snapshot()
		var expected_size := float(Enemy3D.BODY_SCALE_BY_KIND.get(kind, 1.0))
		var expected_bar_size := Enemy3D.HEALTH_BAR_SIZE_BY_KIND.get(kind, Vector2.ZERO) as Vector2
		size_multipliers[kind] = enemy.scale.x
		if (
			not is_equal_approx(enemy.scale.x, expected_size)
			or not bool(state.get("overhead_health_bar", false))
			or not bool(state.get("overhead_health_world_locked", false))
			or not bool(state.get("overhead_health_camera_billboard", false))
			or not (state.get("overhead_health_bar_size", Vector2.ZERO) as Vector2).is_equal_approx(expected_bar_size)
			or not is_equal_approx(float(state.get("overhead_health_ratio", 0.0)), 1.0)
		):
			failures.append("%s lacks a correctly sized, full, camera-facing overhead health bar" % kind)
		var health_sprite := enemy.get_node_or_null("OverheadHealthBar/HealthBarSprite") as Sprite3D
		if health_sprite == null or health_sprite.texture == null:
			failures.append("%s overhead health bar is not the single-texture HUD-style sprite" % kind)
		if kind == "boss":
			if (
				not is_equal_approx(enemy.scale.x, Enemy3D.BOSS_SIZE_MULTIPLIER)
				or not bool(state.get("overhead_health_bar", false))
				or float(state.get("world_collision_radius", 0.0)) < 2.85
			):
				failures.append("Boss does not have its reduced large volume, matched collision and overhead HP bar")
		enemy.apply_health_multiplier(1.5)
		health_sprite = enemy.get_node_or_null("OverheadHealthBar/HealthBarSprite") as Sprite3D
		if enemy.current_hp != enemy.max_hp or health_sprite == null or not is_equal_approx(float(enemy.get_state_snapshot().get("overhead_health_ratio", 0.0)), 1.0):
			failures.append("%s HP modifier did not keep actual HP and overhead bar synchronized" % kind)
		enemy.rotation.y = 1.37
		enemy.take_damage(maxi(1, enemy.max_hp / 2), false, Vector3.RIGHT)
		state = enemy.get_state_snapshot()
		if (
			not is_equal_approx(float(state.get("overhead_health_ratio", 0.0)), float(enemy.current_hp) / float(enemy.max_hp))
			or not is_zero_approx((enemy.get_node("OverheadHealthBar") as Node3D).global_rotation.length())
		):
			failures.append("%s rotated enemy has a desynchronized or inherited-rotation health bar" % kind)
		var damage_numbers_before := _count_damage_numbers()
		# 这里只验证飘字，不验证护盾格挡；零方向避免 shielded 的 15% 随机
		# 完全格挡让整套回归产生非确定性。
		enemy.take_damage(26, false, Vector3.ZERO)
		await get_tree().process_frame
		if _count_damage_numbers() <= damage_numbers_before:
			failures.append("Enemy damage does not create a 3D floating number: %s" % kind)
		if enemy.ai_state == "dead":
			failures.append("Full-health 3D enemy is still one-shot by the starting pistol: %s" % kind)
		enemy.queue_free()
		await get_tree().process_frame
	if (
		float(size_multipliers.get("exploder", 1.0)) >= float(size_multipliers.get("melee_chaser", 1.0))
		or float(size_multipliers.get("shielded", 1.0)) <= float(size_multipliers.get("melee_chaser", 1.0))
		or float(size_multipliers.get("boss", 1.0)) <= float(size_multipliers.get("summoner", 1.0))
	):
		failures.append("Enemy species body scales do not create a readable small/standard/heavy/boss hierarchy")

	var seeker := _make_enemy("melee_chaser", Vector3(0, 0, -6))
	seeker.look_at(player.global_position + Vector3.UP * 0.7, Vector3.UP)
	await get_tree().physics_frame
	if not bool(seeker.call("_has_line_of_sight", player)):
		failures.append("Enemy ray treats the player collider as an occluding wall")
	await get_tree().create_timer(0.36).timeout
	if seeker.ai_state not in ["alert", "chase", "telegraph", "attack"]:
		var vision_debug := MonsterVisionSystem3D.new().evaluate_target(seeker, player)
		failures.append("Enemy with a clear target does not leave idle/patrol for combat: decision=%s vision=%s forward=%s players=%d" % [str(seeker.get_state_snapshot().get("ai_decision", {})), str(vision_debug), str(-seeker.global_transform.basis.z), get_tree().get_nodes_in_group("player_3d").size()])
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	blocker.position = Vector3(0, 0.9, -3.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.0, 0.35)
	collision.shape = shape
	blocker.add_child(collision)
	add_child(blocker)
	await get_tree().physics_frame
	if bool(seeker.call("_has_line_of_sight", player)):
		failures.append("Enemy line-of-sight ignores a physical layer-1 wall")
	seeker.queue_free()
	blocker.queue_free()
	await get_tree().process_frame


func _verify_damage_number_presentation(failures: Array[String]) -> void:
	var normal := CombatDamageNumber3D.new()
	add_child(normal)
	normal.configure(12, false)
	var heavy := CombatDamageNumber3D.new()
	add_child(heavy)
	heavy.configure(48, false)
	var critical := CombatDamageNumber3D.new()
	add_child(critical)
	critical.configure(48, true)
	for sample in [normal, heavy, critical]:
		var label := sample.get_node_or_null("DamageText") as Label3D
		if label == null or not label.font is SystemFont:
			failures.append("3D damage number does not use the selected terminal-style system font")
			continue
		var system_font := label.font as SystemFont
		if (
			system_font.font_names != PackedStringArray(CombatDamageNumber3D.TECH_FONT_FAMILIES)
			or system_font.font_weight != 700
		):
			failures.append("3D damage number terminal font configuration drifted")
	if (
		(normal.get_node("DamageText") as Label3D).font_size != CombatDamageNumber3D.NORMAL_FONT_SIZE
		or (heavy.get_node("DamageText") as Label3D).font_size != CombatDamageNumber3D.HEAVY_FONT_SIZE
		or (critical.get_node("DamageText") as Label3D).font_size != CombatDamageNumber3D.CRITICAL_FONT_SIZE
	):
		failures.append("3D damage number font sizes are not the requested 150%% scale")


func _verify_hit_profiles(failures: Array[String]) -> void:
	for kind in EnemyAvatar3D.FOOTPRINT_PROFILES.keys():
		var enemy := _make_enemy(str(kind), Vector3(60 + failures.size(), 0, 60))
		await get_tree().process_frame
		var state := enemy.get_state_snapshot()
		var collision := state.get("collision_profile", {}) as Dictionary
		var visual := state.get("component_snapshot", {}).get("footprint", {}) as Dictionary
		if not is_equal_approx(float(collision.get("radius", 0.0)), float(visual.get("radius", -1.0))):
			failures.append("Hit radius mismatch: %s" % kind)
		if not is_equal_approx(float(collision.get("height", 0.0)), float(visual.get("height", -1.0))):
			failures.append("Hit height mismatch: %s" % kind)
		enemy.queue_free()
		await get_tree().process_frame


func _verify_ambusher(player: Player3D, failures: Array[String]) -> void:
	player.position = Vector3.ZERO
	var enemy := _make_enemy("ambusher", Vector3(0, 0, -8))
	await get_tree().physics_frame
	var initial := enemy.get_state_snapshot()
	if bool(initial.get("ambush_triggered", true)) or bool(initial.get("component_snapshot", {}).get("ambush_revealed", true)):
		failures.append("Ambusher does not begin buried and dormant")
	player.position = Vector3(0, 0, -5.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var triggered := enemy.get_state_snapshot()
	if not bool(triggered.get("ambush_triggered", false)) or str(triggered.get("state", "")) not in ["telegraph", "attack", "chase"]:
		failures.append("Ambusher does not reveal and enter its lunge telegraph near the player: %s" % str(triggered))
	enemy.queue_free()
	await get_tree().process_frame


func _verify_ranged_volley(failures: Array[String]) -> void:
	var enemy := _make_enemy("ranged_caster", Vector3(20, 0, 20))
	await get_tree().process_frame
	var before := _count_projectiles()
	enemy.call("_perform_attack", Vector3.FORWARD * 5.0, 5.0)
	await get_tree().process_frame
	if _count_projectiles() - before != 3:
		failures.append("Ranged caster does not emit its distinct three-shot volley")
	enemy.queue_free()
	await get_tree().process_frame


func _verify_summoner_support(failures: Array[String]) -> void:
	var summoner := _make_enemy("summoner", Vector3(30, 0, 30))
	var ally := _make_enemy("melee_chaser", Vector3(31, 0, 30))
	await get_tree().process_frame
	ally.current_hp = maxi(1, ally.max_hp / 2)
	var before_hp := ally.current_hp
	_summon_count = 0
	summoner.summon_requested.connect(_on_summon_requested)
	summoner.call("_perform_attack", Vector3.FORWARD * 4.0, 4.0)
	if _summon_count <= 0 or ally.current_hp <= before_hp:
		failures.append("Summoner does not combine minion request with nearby ally healing")
	summoner.queue_free()
	ally.queue_free()
	await get_tree().process_frame


func _verify_shield_facing(failures: Array[String]) -> void:
	var enemy := _make_enemy("shielded", Vector3(40, 0, 40))
	await get_tree().process_frame
	var start_hp := enemy.current_hp
	enemy.take_projectile_damage(30, false, Vector3.BACK, [], {})
	var front_loss := start_hp - enemy.current_hp
	enemy.current_hp = start_hp
	enemy.take_projectile_damage(30, false, Vector3.BACK, ["piercing"], {"pierce_shield": true})
	var piercing_loss := start_hp - enemy.current_hp
	if front_loss >= piercing_loss or piercing_loss < 30:
		failures.append("Shielded enemy does not reduce frontal fire or allow piercing bypass")
	enemy.queue_free()
	await get_tree().process_frame


func _verify_exploder_fragments(failures: Array[String]) -> void:
	var enemy := _make_enemy("exploder", Vector3(50, 0, 50))
	await get_tree().process_frame
	var before := _count_projectiles()
	enemy.call("_explode")
	await get_tree().process_frame
	if _count_projectiles() - before < 8 or enemy.ai_state != "dead":
		failures.append("Exploder does not detonate and emit its eight death fragments")


func _make_enemy(kind: String, position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	enemy.position = position
	add_child(enemy)
	return enemy


func _count_projectiles() -> int:
	var count := 0
	for child in get_children():
		if child is Projectile3D:
			count += 1
	return count


func _count_damage_numbers() -> int:
	var count := 0
	for child in get_children():
		if child.get_script() == DAMAGE_NUMBER_SCRIPT:
			count += 1
	return count


func _on_summon_requested(_enemy: Enemy3D, count: int) -> void:
	_summon_count += count
