extends Node3D
## Runner在Autoload前隔离APPDATA；实测正式_physics_process，禁止以手工状态循环替代。
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
var target: Target
var serial := 0
var checks := 0

class Target extends CharacterBody3D:
	var current_hp := 100000
	var damage_events := 0
	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO, _forced := false, _strength := 0.0) -> void:
		current_hp -= amount
		damage_events += 1

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.4, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.2
	add_child(floor_body)
	target = Target.new()
	target.add_to_group("player_3d")
	add_child(target)
	target.position = Vector3(0, 0.05, -8)
	await get_tree().physics_frame
	await _all_profiles()
	await _recovery_windows()
	await _melee_effects()
	await _continuous_skills()
	await _blink_sequence()
	await _blocked_melee()
	await _cancellation()
	await _forced_motion_and_freeze()
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.clear_all()
	for node in get_children():
		if node is Projectile3D:
			node.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ENEMY_ACTION_RECOVERY_OK checks=%d" % checks)
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _enemy(kind: String) -> Enemy3D:
	var enemy := ENEMY.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	serial += 1
	enemy.room_id = "recovery_%d" % serial
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.position = Vector3(0, 0.05, 0)
	enemy.set("_home_position", enemy.position)
	enemy.set("_home_initialized", true)
	enemy.set("_ambush_triggered", true)
	return enemy

func _bind(enemy: Enemy3D) -> void:
	enemy.set("_target", target)
	MonsterAIManager.notify_enemy_attacked(enemy, target)
	enemy.set("_ai_decision", MonsterAIManager.force_refresh_enemy(enemy))

func _step(enemy: Enemy3D, delta: float) -> void:
	enemy.call("_physics_process", delta)

func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0, point.z)

func _all_profiles() -> void:
	var covered := 0
	for kind in Enemy3D.PROFILES:
		var enemy := _enemy(kind)
		var duration := float(enemy.call("_recovery_duration"))
		check(duration > 0.0, "%s恢复时间非法" % kind)
		if kind == "fat_zombie03":
			check(is_equal_approx(duration, 1.3), "胖子专用收招被缩短")
		elif kind == "melee_chaser":
			check(is_equal_approx(duration, 0.34), "小僵尸收招不为0.34秒")
		if kind in ["egt_blobulon", "egt_blobuloid", "egt_blobulin"]:
			check(is_equal_approx(duration, 0.34), "%s接触收招不为0.34秒" % kind)
		enemy.queue_free()
		await get_tree().process_frame
		covered += 1
	print("RECOVERY_PROFILE_COVERAGE %d" % covered)

func _recovery_windows() -> void:
	var expected := {"melee_chaser":0.34, "melee_chaser_strong":0.34, "ranged_caster":0.34, "ranged_caster_strong":0.34, "fat_zombie03":1.3,
		"fat_zombie03_strong":1.3, "ambusher":0.4, "shielded":0.48,
		"egt_blobulon":0.34, "egt_blobuloid":0.34, "egt_blobulin":0.34,
		"egt_chain_gunner":0.35, "egt_gunjurer":0.3}
	# 族ID以注册值为准，不能静默漏掉一个用例。
	for kind in expected:
		check(Enemy3D.PROFILES.has(kind) or kind.ends_with("_strong"), "测试怪种未登记：%s" % kind)
		if not Enemy3D.PROFILES.has(kind) and not kind.ends_with("_strong"):
			continue
		for fps in [30, 60, 120]:
			var enemy := _enemy(kind)
			enemy.transition_to("recovery")
			var initial := _flat(enemy.position)
			var duration := float(expected[kind])
			var elapsed := 0.0
			var dt := 1.0 / float(fps)
			while elapsed + dt < duration - 0.00001:
				# 有目标/失去目标、反复受光切换与普通受击均不能越过收招。
				if int(elapsed * fps) % 2 == 0:
					_bind(enemy)
				else:
					MonsterAIManager.unregister_enemy(enemy)
					enemy.set("_target", null)
					enemy.illumination_sensor.illumination_state = EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
				if elapsed > 0.1 and elapsed < 0.1 + dt:
					enemy.take_damage(1, false, Vector3.ZERO, 0.0, false)
				_step(enemy, dt)
				elapsed += dt
				check(enemy.ai_state == "recovery", "%s/%dHz提前结束恢复" % [kind, fps])
				check(_flat(enemy.position).distance_to(initial) < 0.005, "%s/%dHz恢复时自主移动" % [kind, fps])
			for frame in 3:
				if enemy.ai_state == "recovery":
					_step(enemy, dt)
			check(enemy.ai_state in ["chase", "search"], "%s/%dHz恢复结束未退出" % [kind, fps])
			enemy.queue_free()
			await get_tree().process_frame
	print("RECOVERY_WINDOWS 30/60/120Hz targets/light/hit checked")

func _melee_effects() -> void:
	for kind in ["melee_chaser", "melee_chaser_strong", "ambusher", "egt_blobulon", "egt_blobuloid", "egt_blobulin"]:
		var enemy := _enemy(kind)
		target.position = Vector3(0, 0.05, -1.5)
		_bind(enemy)
		enemy.transition_to("attack")
		var hits := target.damage_events
		var peak := 0.0
		var active := 0.0
		for frame in 60:
			_step(enemy, 1.0 / 60.0)
			peak = maxf(peak, _flat(enemy.velocity).length())
			if enemy.ai_state == "recovery":
				break
			active += 1.0 / 60.0
		check(enemy.ai_state == "recovery", "%s突进完成未进入收招" % kind)
		check(active >= (0.26 if kind == "ambusher" else 0.14), "%s突进未完整释放" % kind)
		check(peak <= 9.5, "%s突进速度逐帧累加：%.2f" % [kind, peak])
		check(target.damage_events == hits + 1, "%s一轮近战未单次结算" % kind)
		var landing := _flat(enemy.position)
		for frame in 14:
			_step(enemy, 1.0 / 60.0)
		check(enemy.ai_state == "recovery" and _flat(enemy.position).distance_to(landing) < 0.005,
			"%s突进之后没有静止反击窗口" % kind)
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -8)

func _continuous_skills() -> void:
	for kind in ["egt_bandana_kin", "egt_chain_gunner", "egt_gripmaster"]:
		if not Enemy3D.PROFILES.has(kind):
			check(false, "持续测试怪种未登记：%s" % kind)
			continue
		var enemy := _enemy(kind)
		var companion: Enemy3D
		if kind == "egt_gripmaster":
			companion = _enemy("melee_chaser")
			companion.room_id = enemy.room_id
			MonsterAIManager.unregister_enemy(companion)
			MonsterAIManager.register_enemy(companion)
			companion.position = Vector3(15, 0.05, 15)
		_bind(enemy)
		enemy.transition_to("attack")
		_step(enemy, 1.0 / 60.0)
		check(enemy.ai_state == "attack", "%s持续技能尚在生效却进入恢复" % kind)
		var frames := 0
		while enemy.ai_state == "attack" and frames < 360:
			_step(enemy, 1.0 / 60.0)
			frames += 1
		check(enemy.ai_state == "recovery", "%s持续技能未正常结束" % kind)
		check(not bool(enemy.get_state_snapshot().skill_effect_active), "%s恢复段仍有未完成技能" % kind)
		check(int(enemy.get("_egt_attack_count")) == 1, "%s一轮持续技能重复启动" % kind)
		print("CONTINUOUS %s active_frames=%d" % [kind, frames])
		if companion != null:
			companion.queue_free()
		enemy.queue_free()
		await get_tree().process_frame

func _blink_sequence() -> void:
	for kind in ["egt_hollowpoint", "egt_gunjurer"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		enemy.transition_to("chase")
		enemy.set("_attack_timer", 100.0)
		var cfg: Dictionary = (enemy.get("_active_profile") as Dictionary).blink
		enemy.call("_begin_blink_telegraph", cfg)
		var before := _flat(enemy.position)
		for frame in 20:
			_step(enemy, 1.0 / 60.0)
			check(_flat(enemy.position).distance_to(before) < 0.005, "%s瞬移前摇被追击覆盖" % kind)
		check(float(enemy.get("_blink_telegraph")) > 0.0, "%s瞬移早于0.35秒发生" % kind)
		for frame in 3:
			if float(enemy.get("_blink_telegraph")) > 0.0:
				_step(enemy, 1.0 / 60.0)
		var landed := _flat(enemy.position)
		check(landed.distance_to(before) > 0.5, "%s未实际瞬移" % kind)
		check(enemy.ai_state == "recovery", "%s瞬移落地未进入恢复" % kind)
		for frame in 23:
			_step(enemy, 1.0 / 60.0)
			check(enemy.ai_state == "recovery" and _flat(enemy.position).distance_to(landed) < 0.005,
				"%s落地0.40秒内抢跑" % kind)
		for frame in 3:
			if enemy.ai_state == "recovery":
				_step(enemy, 1.0 / 60.0)
		check(enemy.ai_state == "chase", "%s瞬移恢复结束仍被锁定" % kind)
		enemy.queue_free()
		await get_tree().process_frame
	# 周期瞬移不得打断攻击；攻击后请求必须保留到恢复结束。
	var jurer := _enemy("egt_gunjurer")
	_bind(jurer)
	jurer.transition_to("attack")
	_step(jurer, 1.0 / 60.0)
	jurer.set("_blink_timer", 0.0)
	var start := _flat(jurer.position)
	for frame in 240:
		_step(jurer, 1.0 / 60.0)
		if jurer.ai_state == "attack":
			check(_flat(jurer.position).distance_to(start) < 0.005, "枪法师在弹幕中途瞬移")
		if int(jurer.get("_teleport_fx_in_count")) > 0:
			break
	check(int(jurer.get("_teleport_fx_in_count")) == 1, "枪法师出手后瞬移请求丢失")
	jurer.queue_free()
	await get_tree().process_frame

func _blocked_melee() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 4, 0.3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1, -0.75)
	add_child(wall)
	target.position = Vector3(0, 0.05, -1.5)
	await get_tree().physics_frame
	for kind in ["melee_chaser", "melee_chaser_strong", "ambusher", "shielded", "egt_blobulon"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		var hp := target.current_hp
		enemy.call("_perform_attack", Vector3.FORWARD * 1.5, 1.5)
		check(target.current_hp == hp, "%s结算帧穿墙命中" % kind)
		enemy.queue_free()
		await get_tree().process_frame
	wall.queue_free()
	target.position = Vector3(0, 0.05, -8)
	await get_tree().process_frame

func _cancellation() -> void:
	for stop in ["stagger", "dormant", "dead"]:
		var enemy := _enemy("egt_bandana_kin")
		_bind(enemy)
		enemy.transition_to("attack")
		_step(enemy, 1.0 / 60.0)
		check(bool(enemy.get_state_snapshot().skill_effect_active), "中断用例未真正启动连射")
		enemy.transition_to(stop)
		check(not bool(enemy.get_state_snapshot().skill_effect_active), "%s后仍有排期攻击" % stop)
		enemy.queue_free()
		await get_tree().process_frame

func _forced_motion_and_freeze() -> void:
	var enemy := _enemy("melee_chaser")
	_bind(enemy)
	enemy.transition_to("recovery")
	enemy.apply_melee_knockback(Vector3.RIGHT, 5.0, 0.2)
	_step(enemy, 1.0 / 60.0)
	check(enemy.ai_state == "recovery" and is_equal_approx(enemy.velocity.x, 5.0), "恢复段吞掉玩家击退")
	_step(enemy, 1.0 / 60.0)
	check(enemy.ai_state == "recovery" and enemy.velocity.x <= 5.001, "恢复段击退速度逐帧叠加")
	var elapsed := float(enemy.get("_state_time"))
	enemy.set("_fate_freeze_remaining", 0.5)
	_step(enemy, 0.2)
	check(enemy.ai_state == "recovery" and is_equal_approx(float(enemy.get("_state_time")), elapsed), "冻结期间收招计时抢跑")
	enemy.queue_free()
	await get_tree().process_frame
