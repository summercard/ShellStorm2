extends Node

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const DAMAGE_NUMBER_SCRIPT := preload("res://src/fx/CombatDamageNumber3D.gd")

var _summon_count := 0


func _ready() -> void:
	var failures: Array[String] = []
	# 怪物已与玩家共用同一套重力/地面口径。验收台必须提供承重面，
	# 否则被验证的怪会一路下坠，位置类断言全部失去意义。
	add_child(_make_support(Vector3(0.0, -0.15, 0.0), Vector3(200.0, 0.30, 200.0)))
	var vfx_pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if vfx_pool != null:
		vfx_pool.clear_all()
	# 重力与分离专项在玩家入场前跑：没有可追击的目标，怪只按巡逻和分离力运动，
	# 断言口径不会被「全部扑向玩家」污染。
	await _verify_vertical_physics_and_separation(failures)
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame
	# 本专项没有搭建完整碰撞世界；冻结玩家物理，避免重力让视线射线从墙下穿过。
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	await _verify_ai_visibility_and_hp(player, failures)
	await _verify_hit_profiles(failures)
	await _verify_ambusher(player, failures)
	await _verify_ranged_volley(failures)
	await _verify_summoner_support(failures)
	await _verify_shield_facing(failures)
	await _verify_exploder_fragments(failures)
	await _verify_pool_reuse_after_shooter_freed(failures)
	_verify_damage_number_presentation(failures)
	for child in get_children():
		if child is Projectile3D or child is Enemy3D or child.get_script() == DAMAGE_NUMBER_SCRIPT:
			child.queue_free()
	if failures.is_empty():
		print("3D_ENEMY_BEHAVIOR_FLOW_OK: line-of-sight AI, scaled 3D HP, matched hit volumes, buried ambush, ranged volley, summon/heal support, frontal shield, death fragments, shared gravity/floor contract, weighted enemy separation and fall-out death below 15m pass")
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
		var expected_size := (
			Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER
			* float(Enemy3D.BODY_SCALE_BY_KIND.get(kind, 1.0))
		)
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
				not is_equal_approx(enemy.scale.x, Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER * Enemy3D.BOSS_SIZE_MULTIPLIER)
				or not bool(state.get("overhead_health_bar", false))
				or float(state.get("world_collision_radius", 0.0)) < 1.995
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
	if _count_projectiles() != before or enemy.ai_state != "dead":
		failures.append("Committed active explosion incorrectly reused the weaker death-fragment path")
	var killed_enemy := _make_enemy("exploder", Vector3(54, 0, 50))
	await get_tree().process_frame
	before = _count_projectiles()
	killed_enemy.take_damage(killed_enemy.max_hp + 1)
	await get_tree().process_frame
	if _count_projectiles() - before < 8:
		failures.append("Killed exploder does not emit its distinct eight weaker death fragments")


func _verify_pool_reuse_after_shooter_freed(failures: Array[String]) -> void:
	var pool := ProjectilePool3D.new()
	add_child(pool)
	var first_shooter := CharacterBody3D.new()
	add_child(first_shooter)
	var config := {
		"direction": Vector3.FORWARD,
		"hostile": true,
		"shooter": first_shooter,
	}
	var projectile := pool.acquire(config, Vector3(80.0, 1.0, 80.0))
	projectile.call("_retire")
	first_shooter.queue_free()
	await get_tree().process_frame
	var second_shooter := CharacterBody3D.new()
	add_child(second_shooter)
	config["shooter"] = second_shooter
	var reused := pool.acquire(config, Vector3(80.0, 1.0, 80.0))
	if reused != projectile or int(pool.get_snapshot().get("active", -1)) != 1:
		failures.append("Projectile pool did not safely reuse a projectile after its previous shooter was freed")
	reused.call("_retire")
	second_shooter.queue_free()
	pool.queue_free()
	await get_tree().process_frame


func _make_enemy(kind: String, position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	enemy.position = position
	add_child(enemy)
	return enemy


func _make_support(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "VerificationSupport"
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


## 重力、地面口径与「怪与怪不叠加」的联合专项。
## 承重面覆盖 ±100m，所以下面拿 -150m 处当「脚下真的没有地板」的取样点。
func _verify_vertical_physics_and_separation(failures: Array[String]) -> void:
	# 1) 脚下没有承重面时必须掉下去，而不是悬空停在原地。
	var airborne := _make_enemy("melee_chaser", Vector3(-150.0, 3.0, 0.0))
	await get_tree().process_frame
	var airborne_start_y := airborne.global_position.y
	for _frame in range(30):
		await get_tree().physics_frame
	if airborne.global_position.y >= airborne_start_y - 0.5:
		failures.append(
			"Enemy without a floor does not fall: y=%.3f from %.3f" % [
				airborne.global_position.y, airborne_start_y
			]
		)
	airborne.queue_free()
	await get_tree().process_frame

	# 2) 有承重面时落到地板并停住，不会穿到地板以下。
	var grounded := _make_enemy("melee_chaser", Vector3(45.0, 3.0, 45.0))
	await get_tree().process_frame
	for _frame in range(120):
		await get_tree().physics_frame
	if not grounded.is_on_floor() or absf(grounded.global_position.y) > 0.08:
		failures.append(
			"Enemy does not settle on the floor: y=%.3f on_floor=%s" % [
				grounded.global_position.y, str(grounded.is_on_floor())
			]
		)
	# 3) 地面口径必须与 Player3D 同源：44° 以内算可走的坡，更陡的算墙。
	if (
		not is_equal_approx(grounded.floor_max_angle, deg_to_rad(44.0))
		or grounded.motion_mode != CharacterBody3D.MOTION_MODE_GROUNDED
		or not grounded.up_direction.is_equal_approx(Vector3.UP)
	):
		failures.append("Enemy floor contract drifted from Player3D (floor_max_angle/motion_mode/up_direction)")
	grounded.queue_free()
	await get_tree().process_frame

	# 4) 怪与怪不叠加：叠在同一点生成的两只必须被拆开到有效间距。
	var overlap_origin := Vector3(0.0, 0.0, 45.0)
	var first := _make_enemy("melee_chaser", overlap_origin)
	var second := _make_enemy("melee_chaser", overlap_origin + Vector3(0.05, 0.0, 0.0))
	await get_tree().process_frame
	var minimum_distance := (
		(first.get_world_body_radius() + second.get_world_body_radius())
		* Enemy3D.SEPARATION_RADIUS_SCALE
	)
	for _frame in range(180):
		await get_tree().physics_frame
	var separated := Vector2(
		first.global_position.x - second.global_position.x,
		first.global_position.z - second.global_position.z
	).length()
	if separated < minimum_distance * 0.9:
		failures.append(
			"Overlapping enemies were not separated: %.3f < %.3f" % [
				separated, minimum_distance * 0.9
			]
		)
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame

	# 5) 分离只作用于水平面：五只挤成一点时，谁都不会被顶起来，也不会穿到地板以下。
	var crowd_origin := Vector3(-45.0, 0.0, -45.0)
	var crowd: Array[Enemy3D] = []
	for index in range(5):
		var angle := TAU * float(index) / 5.0
		crowd.append(_make_enemy(
			"melee_chaser",
			crowd_origin + Vector3(cos(angle), 0.0, sin(angle)) * 0.45
		))
	await get_tree().process_frame
	for _frame in range(180):
		await get_tree().physics_frame
	for enemy in crowd:
		if enemy.global_position.y < -0.12:
			failures.append("A crowded enemy was pushed below the floor")
		elif absf(enemy.global_position.y) > 0.12:
			failures.append(
				"Crowd separation displaces enemies vertically: y=%.3f" % enemy.global_position.y
			)
		enemy.queue_free()
	await get_tree().process_frame

	# 6) 掉出可行走层的判死深度必须大于塔楼整层层高（12m）：
	#    怪沿楼梯/连接通道追玩家下一层时是 12m 级落差，不能被当成掉出世界。
	if Enemy3D.FALL_DEATH_DROP_M <= 12.0:
		failures.append(
			"Fall death depth %.2f is not deeper than a tower floor (12m); stair drops would kill" % (
				Enemy3D.FALL_DEATH_DROP_M
			)
		)

	# 7) 下落未达判死深度：不准死，也不准被拉回出生点，必须正常落在承重面上。
	#    承重面顶面取出生点下方 12m，正好是塔楼一层落差。
	var stair_column := Vector3(-60.0, 3.0, -140.0)
	add_child(_make_support(
		Vector3(stair_column.x, -9.15, stair_column.z), Vector3(16.0, 0.30, 16.0)
	))
	var stair_faller := _make_enemy("melee_chaser", stair_column)
	await get_tree().process_frame
	for _frame in range(240):
		await get_tree().physics_frame
	if stair_faller.ai_state == "dead":
		failures.append("Enemy died from a one-storey stair drop (within fall death depth)")
	elif not stair_faller.is_on_floor() or absf(stair_faller.global_position.y + 9.0) > 0.10:
		failures.append(
			"Enemy did not settle on the 12m-lower landing: y=%.3f on_floor=%s" % [
				stair_faller.global_position.y, str(stair_faller.is_on_floor())
			]
		)
	stair_faller.queue_free()
	await get_tree().process_frame

	# 8) 下落超过判死深度：必须直接判死（房间才清得掉），且不能是被拉回出生点的假恢复。
	#    承重面顶面放在出生点下方 23m，远深于判死深度，所以它到不了。
	var void_column := Vector3(60.0, 3.0, -140.0)
	add_child(_make_support(
		Vector3(void_column.x, -20.15, void_column.z), Vector3(16.0, 0.30, 16.0)
	))
	var deep_faller := _make_enemy("melee_chaser", void_column)
	await get_tree().process_frame
	var deepest_y := deep_faller.global_position.y
	var deep_dead := false
	for _frame in range(240):
		await get_tree().physics_frame
		if not is_instance_valid(deep_faller):
			deep_dead = true
			break
		if deep_faller.ai_state == "dead":
			deep_dead = true
			break
		deepest_y = minf(deepest_y, deep_faller.global_position.y)
	if not deep_dead:
		failures.append(
			"Enemy that fell past the death depth stayed alive: y=%.3f" % deepest_y
		)
	else:
		# 判死是每帧开头按「上一次位移后的位置」结算的，所以最后一次存活取样必然
		# 停在触发线以上不到一帧的下落距离（末端速度 32m/s ⇒ 约 0.53m）。留 1m 容差。
		var shallowest_allowed := (
			void_column.y - Enemy3D.FALL_DEATH_DROP_M + 1.0
		)
		if deepest_y > shallowest_allowed:
			failures.append(
				"Fall death triggered far above the declared depth: fell to %.3f, expected <= %.3f" % [
					deepest_y, shallowest_allowed
				]
			)
	if is_instance_valid(deep_faller):
		deep_faller.queue_free()
	await get_tree().process_frame

	# 9) 分离查询必须按 SEPARATION_INTERVAL_FRAMES 降频，不许退回「每帧每怪一次」。
	#    这是硬性能契约：`Dungeon3D.ENEMY_PREACTIVATION_RANGE = 38m` 下同时激活的怪
	#    可达数十只，而 `query_radius` 单次实测量级 10^2 微秒 —— 每帧每只一次会把
	#    60FPS 的物理预算吃光（实测 120 只 ⇒ 物理帧 42ms，掉到 24FPS）。
	#    断言用「查询次数」而不是「耗时」：计数是确定性的，不会因机器负载抖动。
	if Enemy3D.SEPARATION_INTERVAL_FRAMES <= 1:
		failures.append("Separation recompute interval fell back to every frame")
	else:
		var cadence_count := 32
		var cadence: Array[Enemy3D] = []
		for index in range(cadence_count):
			var angle := TAU * float(index) / float(cadence_count)
			var spawned_enemy := _make_enemy(
				"melee_chaser",
				Vector3(-70.0 + cos(angle) * 3.0, 0.0, 70.0 + sin(angle) * 3.0)
			)
			cadence.append(spawned_enemy)
		await get_tree().process_frame
		# 必须真的在跑物理，否则测到的是 0 次查询，断言会假绿。
		for enemy in cadence:
			enemy.set_runtime_active(true)
		var registry := GameplaySpatialRegistry3D
		var queries_before := int(registry.get_snapshot().get("query_count", 0))
		var cadence_frames := 60
		for _frame in range(cadence_frames):
			await get_tree().physics_frame
		var queries_after := int(registry.get_snapshot().get("query_count", 0))
		var measured_per_frame := float(queries_after - queries_before) / float(cadence_frames)
		# 余量给 2.0 倍：光照传感器等其他调用方也走同一个 query_radius（每 0.12s 一次）。
		# 降频一旦被去掉，实测会涨到约 1.0×N，远超该预算。
		var cadence_budget := (
			float(cadence_count) / float(Enemy3D.SEPARATION_INTERVAL_FRAMES) * 2.0
		)
		if measured_per_frame > cadence_budget:
			failures.append(
				"Separation queries are not throttled: %.1f per frame, budget %.1f (N=%d)" % [
					measured_per_frame, cadence_budget, cadence_count
				]
			)
		elif measured_per_frame < float(cadence_count) / float(
			Enemy3D.SEPARATION_INTERVAL_FRAMES
		) * 0.5:
			# 下界：夹具必须真的跑出分离查询，否则上界断言是恒真的假绿。
			failures.append(
				"Cadence fixture did not exercise separation queries: %.1f per frame (N=%d)" % [
					measured_per_frame, cadence_count
				]
			)
		for enemy in cadence:
			enemy.queue_free()
		await get_tree().process_frame


func _count_projectiles() -> int:
	var count := 0
	for child in get_children():
		if child is Projectile3D:
			count += 1
	return count


func _count_damage_numbers() -> int:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		return pool.active_count(VfxPool3D.FX02_DAMAGE_NUMBER)
	var count := 0
	for child in get_children():
		if child.get_script() == DAMAGE_NUMBER_SCRIPT:
			count += 1
	return count


func _on_summon_requested(_enemy: Enemy3D, count: int) -> void:
	_summon_count += count
