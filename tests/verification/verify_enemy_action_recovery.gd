extends Node3D
## 验收：怪物动作收招 `recovery`（Enemy3D 共用状态机）。
## Runner 在 Autoload 前隔离 APPDATA；实测走正式 `_physics_process`，不以手工状态循环替代。
##
## ## 判据口径（2026-11-06 修订，业主「以现在游戏内的效果为基准」）
##
## 本用例 2026-11-02 首版是照当时（节奏重调前）的口径写的。之后 11-02 的 AI 节奏大改
## 把 EGT 33 只的收招从统一的 0.34s 压到 **0.08~0.18s**（按攻击方式分档），
## 于是那张「人人 0.34」的表整张作废，用例一直红着、也一直没登记。
## 现在按当前实现重写，并明确区分两类判据：
##
##   · **硬判据**：实现事实 —— 收招时长表、收招期间不自主位移、到点退出、
##     单次结算、击退不被吞掉也不逐帧叠加、冻结期间计时不抢跑、排期弹丸清空。
##   · **NOTE**：当前实现与旧稿意图不同、但属于**已落地设计变更**的几处，只打印不判红。
##
## 跑法：
##   godot --headless --path <project> --scene res://tests/verification/verify_enemy_action_recovery.tscn

const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

## 收招时长表（2026-11-06 实测登记）。
##
## 塔楼老怪来自 `_recovery_duration()` 缺省分支 + profile 的 `recovery` 键；
## EGT 复刻怪来自 `_egt_recovery_seconds()` 的**攻击方式分档**：
## volley 0.18（射程 >7m 时 0.12）/ contact 0.10 / explode·rush·grab·flee 0.08 /
## support 0.16 / 其它 0.12。改任何一档都必须同步改这张表 —— 这是本用例的核心。
const RECOVERY_SECONDS := {
	"fat_zombie03": 1.300, "melee_chaser": 0.340, "ranged_caster": 0.340,
	"summoner": 0.340, "shielded": 0.480, "exploder": 0.480, "ambusher": 0.340,
	"boss": 0.620,
	"egt_bullet_kin": 0.120, "egt_bandana_kin": 0.120, "egt_veteran_kin": 0.120,
	"egt_red_shotgun": 0.180, "egt_blue_shotgun": 0.180, "egt_veteran_shotgun": 0.180,
	"egt_blobulon": 0.100, "egt_blobuloid": 0.100, "egt_blobulin": 0.100,
	"egt_pinhead": 0.080, "egt_nitra": 0.080, "egt_bullat": 0.080,
	"egt_gunsinger": 0.160, "egt_cardinal": 0.120, "egt_hollowpoint": 0.120,
	"egt_king_bullat": 0.120, "egt_chancebulon": 0.120,
	"egt_bookllet": 0.120, "egt_blue_bookllet": 0.120, "egt_green_bookllet": 0.120,
	"egt_gunjurer": 0.120, "egt_gigi": 0.120,
	"egt_shotgat": 0.080, "egt_grenat": 0.080, "egt_spirat": 0.080,
	"egt_keybullet_kin": 0.080, "egt_chance_kin": 0.080,
	"egt_confirmed": 0.120, "egt_mimic": 0.120, "egt_gun_fairy": 0.120,
	"egt_gripmaster": 0.080, "egt_gun_nut": 0.120, "egt_chain_gunner": 0.100,
}

## 击退强度上限（`apply_melee_knockback` 的 `strength_cap` 缺省值）。
const KNOCKBACK_CAP := 10.5

var failures: Array[String] = []
var notes: Array[String] = []
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


func note(message: String) -> void:
	if not notes.has(message):
		notes.append(message)


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

	_recovery_table()
	await _recovery_windows()
	await _attack_settlement()
	await _knockback_during_recovery()
	await _freeze_holds_timer()
	await _continuous_skills()
	await _cancellation()

	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.clear_all()
	for node in get_children():
		if node is Projectile3D:
			node.queue_free()
	await get_tree().process_frame
	for line in notes:
		print("NOTE ", line)
	if failures.is_empty():
		print("ENEMY_ACTION_RECOVERY_OK checks=%d notes=%d" % [checks, notes.size()])
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


## A. 收招时长表：逐怪对齐 `RECOVERY_SECONDS`（`_strong` 变体取基准怪的值）。
func _recovery_table() -> void:
	var covered := 0
	for kind in Enemy3D.PROFILES:
		var enemy := _enemy(kind)
		var expected := _expected_recovery(kind)
		var actual := float(enemy.call("_recovery_duration"))
		check(
			expected >= 0.0 and is_equal_approx(actual, expected),
			"%s收招时长 %.3fs，登记值 %.3fs" % [kind, actual, expected]
		)
		enemy.queue_free()
		covered += 1
	for kind in ["melee_chaser_strong", "ranged_caster_strong", "fat_zombie03_strong"]:
		var enemy := _enemy(kind)
		var expected := _expected_recovery(kind)
		check(
			is_equal_approx(float(enemy.call("_recovery_duration")), expected),
			"%s收招时长与基准怪不一致" % kind
		)
		enemy.queue_free()
		covered += 1
	print("RECOVERY_PROFILE_COVERAGE %d" % covered)


func _expected_recovery(kind: String) -> float:
	return float(RECOVERY_SECONDS.get(kind.trim_suffix("_strong"), -1.0))


## B. 收招窗口：进入后按登记时长保持，到点退出；期间不受普通受击 / 光照切换影响。
##
## 不再要求「反复强制重决策也不得打断」—— `force_refresh_enemy()` 是调试接口，
## 当前实现下它会把状态改回 chase，属设计变更（NOTE），不进判据。
func _recovery_windows() -> void:
	for kind in RECOVERY_SECONDS:
		if not Enemy3D.PROFILES.has(kind):
			check(false, "登记怪种未在 PROFILES：%s" % kind)
			continue
		var duration := float(RECOVERY_SECONDS[kind])
		for fps in [30, 60, 120]:
			var enemy := _enemy(kind)
			_bind(enemy)
			# 逃跑 / 游荡 / 抓取 / 不动的怪：位移**本来就由 `_tick_egt_state()` 写在
			# `_external_velocity` 上**（逃跑型收招期间照样往外跑），不收招拦。
			var self_moving := _self_moving_kind(enemy)
			if self_moving:
				note("%s 属逃跑/游荡/抓取/不动型，收招期间仍有外推位移（设计如此）" % kind)
			# 抓取者（gripmaster）的 profile 带 `die_when_others_dead`：本夹具里只有它一只，
			# 一进 `_tick_egt_state` 就按原作规则自灭，收招窗口无从测量 —— 需要同伴才算，
			# 单列 NOTE，不在这一支里记红。
			if bool((enemy.get("_active_profile") as Dictionary).get("die_when_others_dead", false)):
				note("%s 单人夹具里会按 die_when_others_dead 自灭，收招窗口未测" % kind)
				enemy.queue_free()
				await get_tree().process_frame
				continue
			enemy.transition_to("recovery")
			var initial := _flat(enemy.position)
			var dt := 1.0 / float(fps)
			var elapsed := 0.0
			var frames := 0
			# 边界帧不判：`_state_time >= duration` 就是在**这一帧**退出收招的，
			# 提前一帧判红等于要求「别按自己的时长退出」。
			while elapsed < duration - 0.000001:
				# 真实事件：普通受击 + 光照切换。两者都不得打断或延长收招。
				if frames == 2:
					enemy.take_damage(1, false, Vector3.ZERO, 0.0, false)
				if frames == 4 and enemy.illumination_sensor != null:
					enemy.illumination_sensor.illumination_state = EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
				_step(enemy, dt)
				elapsed += dt
				frames += 1
				if elapsed >= duration - 0.000001:
					break
				check(
					enemy.ai_state == "recovery",
					"%s/%dHz收招被受击或光照打断" % [kind, fps]
				)
				if not self_moving:
					check(
						_flat(enemy.position).distance_to(initial) < 0.01,
						"%s/%dHz收招期间自主位移" % [kind, fps]
					)
			# 到点必须退出：再多给 2 帧，不允许还卡在 recovery。
			for _i in range(2):
				if enemy.ai_state == "recovery":
					_step(enemy, dt)
			check(
				enemy.ai_state in ["chase", "search", "idle", "patrol"],
				"%s/%dHz收招到点未退出（仍是 %s）" % [kind, fps, enemy.ai_state]
			)
			enemy.queue_free()
			await get_tree().process_frame
	print("RECOVERY_WINDOWS 30/60/120Hz damage+light checked")


## 位移由 `_tick_egt_state()` 接管的那几类（逃跑 / 游荡 / 抓取 / 明确不动）。
func _self_moving_kind(enemy: Enemy3D) -> bool:
	var profile := enemy.get("_active_profile") as Dictionary
	if profile.has("wander") or bool(profile.get("immobile", false)):
		return true
	if not enemy.call("_is_egt_kind"):
		return false
	return str(enemy.call("_egt_attack_style")) in ["flee", "grab"]


## C. 一次攻击只结算一次；收招全程速度不超击退上限；外部推力结束后必须停住。
func _attack_settlement() -> void:
	for kind in ["melee_chaser", "melee_chaser_strong", "ambusher", "egt_blobulon", "egt_blobulin", "shielded"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		target.position = Vector3(0, 0.05, -1.5)
		var hits := target.damage_events
		enemy.transition_to("attack")
		_step(enemy, 1.0 / 60.0)
		check(enemy.ai_state == "recovery", "%s攻击后未进入收招" % kind)
		check(
			target.damage_events == hits + 1,
			"%s一次攻击未单次结算（%d 次）" % [kind, target.damage_events - hits]
		)
		var peak := 0.0
		var elapsed := 0.0
		var dt := 1.0 / 60.0
		var prev_speed := -1.0
		var monotonic := true
		var raw_peak := 0.0
		while enemy.ai_state == "recovery" and elapsed < 2.0:
			var before := _flat(enemy.position)
			_step(enemy, dt)
			elapsed += dt
			var speed := _flat(enemy.velocity).length()
			peak = maxf(peak, speed)
			if prev_speed >= 0.0 and speed > prev_speed + 1e-3:
				monotonic = false
			prev_speed = speed
			raw_peak = maxf(raw_peak, before.distance_to(_flat(enemy.position)) / dt)
		check(peak <= KNOCKBACK_CAP + 0.5, "%s收招段速度逐帧叠加：峰值 %.2f m/s" % [kind, peak])
		# 收招段速度只能单调下降（刹车），不许再被外推顶上去。
		check(monotonic, "%s收招段速度中途回升（外推被重复累加）" % kind)
		# 位移与速度对不上 ⇒ 体型缩放把 `move_and_slide` 的位移放大了（NOTE，见文档）。
		if raw_peak > peak * 3.0:
			note("%s 体型 scale=%s 让实际位移 %.1f m/s 远高于 velocity %.1f m/s（move_and_slide 受缩放放大）"
				% [kind, enemy.scale.x, raw_peak, peak])
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -8)
	print("ATTACK_SETTLEMENT single-hit + speed-cap checked")


## D. 收招期间玩家近战击退必须真的推得动，且不得逐帧叠加。
func _knockback_during_recovery() -> void:
	for kind in ["melee_chaser", "egt_blobulin", "shielded"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		enemy.transition_to("recovery")
		enemy.apply_melee_knockback(Vector3.RIGHT, 5.0, 0.2)
		_step(enemy, 1.0 / 60.0)
		check(
			enemy.ai_state == "recovery" and is_equal_approx(enemy.velocity.x, 5.0),
			"%s收招段吞掉玩家击退（v.x=%.2f）" % [kind, enemy.velocity.x]
		)
		_step(enemy, 1.0 / 60.0)
		check(
			enemy.velocity.x <= 5.05,
			"%s收招段击退速度逐帧叠加（v.x=%.2f）" % [kind, enemy.velocity.x]
		)
		enemy.queue_free()
		await get_tree().process_frame
	print("KNOCKBACK 5.0 m/s held for 2 frames")


## E. 冻结（命运冰）期间收招计时不得抢跑。
func _freeze_holds_timer() -> void:
	var enemy := _enemy("melee_chaser")
	_bind(enemy)
	enemy.transition_to("recovery")
	_step(enemy, 1.0 / 60.0)
	var elapsed := float(enemy.get("_state_time"))
	enemy.set("_fate_freeze_remaining", 0.5)
	_step(enemy, 0.2)
	check(
		enemy.ai_state == "recovery" and is_equal_approx(float(enemy.get("_state_time")), elapsed),
		"冻结期间收招计时抢跑"
	)
	enemy.queue_free()
	await get_tree().process_frame
	print("FREEZE recovery timer held")


## F. 持续技能（连发 / 链炮）：一次攻击只派发一次，排期弹丸必须在 3 秒内清空。
##
## **口径变更（2026-11）**：旧稿要求「收招时不得还有未完成技能」，实现早已改成
## 连发队列（`_pending_volleys`）—— 排期弹丸本来就要在收招期间陆续打出。
## 现在的判据换成「只派发一次 + 排期最终清空」。
func _continuous_skills() -> void:
	for kind in ["egt_bandana_kin", "egt_chain_gunner"]:
		if not Enemy3D.PROFILES.has(kind):
			check(false, "持续测试怪种未登记：%s" % kind)
			continue
		var enemy := _enemy(kind)
		_bind(enemy)
		target.position = Vector3(0, 0.05, -4.0)
		enemy.transition_to("attack")
		_step(enemy, 1.0 / 60.0)
		var queued := (enemy.get("_pending_volleys") as Array).size()
		check(int(enemy.get("_egt_attack_count")) == 1, "%s一次攻击重复派发" % kind)
		var frames := 0
		while (enemy.get("_pending_volleys") as Array).size() > 0 and frames < 180:
			_step(enemy, 1.0 / 60.0)
			frames += 1
		check(
			(enemy.get("_pending_volleys") as Array).is_empty(),
			"%s排期弹丸 3 秒未清空（剩 %d）"
			% [kind, (enemy.get("_pending_volleys") as Array).size()]
		)
		if queued == 0:
			note("%s 本次攻击没有排队（射程档或攻击方式不产生连发）" % kind)
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -8)
	print("CONTINUOUS single-dispatch + queue-drain checked")


## G. 中断（硬直 / 休眠 / 死亡）必须清掉排期攻击。
func _cancellation() -> void:
	for stop in ["stagger", "dormant", "dead"]:
		var enemy := _enemy("egt_bandana_kin")
		_bind(enemy)
		target.position = Vector3(0, 0.05, -4.0)
		enemy.transition_to("attack")
		_step(enemy, 1.0 / 60.0)
		var queued := (enemy.get("_pending_volleys") as Array).size()
		enemy.transition_to(stop)
		check(
			(enemy.get("_pending_volleys") as Array).is_empty(),
			"%s后仍有排期攻击（进入时 %d 发）" % [stop, queued]
		)
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -8)
	print("CANCELLATION stagger/dormant/dead cleared queue")
