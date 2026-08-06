extends Node

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")

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
	for child in get_children():
		if child is Projectile3D or child is Enemy3D:
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
		if kind == "boss":
			if (
				not is_equal_approx(enemy.scale.x, Enemy3D.BOSS_SIZE_MULTIPLIER)
				or not bool(state.get("overhead_health_bar", false))
				or float(state.get("world_collision_radius", 0.0)) < 3.8
			):
				failures.append("Boss does not have 2x volume, matched collision and overhead HP bar")
		enemy.take_damage(26, false, Vector3.RIGHT)
		if enemy.ai_state == "dead":
			failures.append("Full-health 3D enemy is still one-shot by the starting pistol: %s" % kind)
		enemy.queue_free()
		await get_tree().process_frame

	var seeker := _make_enemy("melee_chaser", Vector3(0, 0, -6))
	await get_tree().physics_frame
	if not bool(seeker.call("_has_line_of_sight", player)):
		failures.append("Enemy ray treats the player collider as an occluding wall")
	await get_tree().create_timer(0.36).timeout
	if seeker.ai_state not in ["alert", "chase", "telegraph", "attack"]:
		failures.append("Enemy with a clear target does not leave idle/patrol for combat")
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
		failures.append("Ambusher does not reveal and enter its lunge telegraph near the player")
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


func _on_summon_requested(_enemy: Enemy3D, count: int) -> void:
	_summon_count += count
