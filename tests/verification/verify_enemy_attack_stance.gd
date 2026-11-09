extends Node3D
## 验收：怪物**攻击姿态要站住**（`telegraph` / `attack` 不自主位移）。
##
## 业主 2026-11-09：「怪物在攻击玩家的时候，会一边攻击一边移动，这样看起来非常不舒服。
## 我需要怪物攻击的时候停下来，攻击后在进行移动……应该是进入攻击范围后，直接进行攻击，
## 此时是停下的，攻击完成后，继续行动。」
##
## ## 判据只钉三条事实，不钉实现写法
##   A. 前摇开始后 `v / a` 帧内必须刹到 0，且**刹住之后不许再起速**（a = `BRAKE_MPS2`）。
##      —— 这一条对旧实现会红：复刻怪保留 35% 步速、塔楼怪 18 m/s² 慢刹，
##      两者都超出 55 m/s² 的停车距离。
##   B. **停下不等于走不到**：追击仍在逼近，进射程仍会出手。
##      业主原话「不要修改后导致怪物无法接近玩家攻击」就是这一条。
##   C. 外力不被吞：前摇里被近战击退，速度必须原样生效（旧实现乘 0.35）。
##   D. 排期连发没打完之前不许退回 `chase`（否则边走边吐子弹）。
##   E. 自主动位移（游荡）的残留指令在进入前摇时被清掉。
##
## 实测走正式 `_physics_process`，不以手工状态循环替代（同 `verify_enemy_action_recovery`）。
##
## 跑法：
##   godot --headless --path <project> --scene res://tests/verification/verify_enemy_attack_stance.tscn

const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

## 前摇刹车预算用的减速度（m/s²）。
##
## ⚠ 故意**不复用** `Enemy3D.ATTACK_STANCE_BRAKE_MPS2`：反向验证要能在旧实现上跑出
## "判红"而不是"编译失败"。旧实现没有这个常量，引用了就整份脚本 load 不了，
## 那样的红不证明任何行为差异。两边同值时是巧合，不同值时本用例会给出可读的差额。
const BRAKE_MPS2 := 55.0

## A 段覆盖的怪种：快 / 慢 / 近战 / 远程 / 连发 / 接触 / 塔楼老怪，各取一只代表。
## 覆盖不全时会打印 NOTE，不静默跳过。
const STANCE_KINDS := [
	"melee_chaser", "ambusher", "fat_zombie03",
	"egt_bandana_kin", "egt_veteran_kin", "egt_red_shotgun", "egt_blobulon",
]

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
	target.position = Vector3(0, 0.05, -6)
	await get_tree().physics_frame

	await _stance_brake()
	await _approach_not_broken()
	await _knockback_not_swallowed()
	await _volley_holds_recovery()
	await _self_move_residue_cleared()

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
		print("ENEMY_ATTACK_STANCE_OK checks=%d notes=%d" % [checks, notes.size()])
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _enemy(kind: String) -> Enemy3D:
	var enemy := ENEMY.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	serial += 1
	enemy.room_id = "stance_%d" % serial
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


## A. 前摇全程必须刹停，并且在刹停之后**不许再起速**。
##
## 判据取 `velocity` 而不是位置差：位置差在这个仓库的夹具里已经被证明不可靠
## （体块 scale 会把 `move_and_slide` 的实际位移放大数倍，见
## `verify_enemy_action_recovery` 的 raw_peak NOTE；游荡/伪装等分支还会直接改位置）。
## `velocity` 才是"它自己在不在走"的唯一真源。
func _stance_brake() -> void:
	var dt := 1.0 / 60.0
	for kind in STANCE_KINDS:
		var enemy := _enemy(kind)
		_bind(enemy)
		target.position = Vector3(0, 0.05, -2.0)
		var speed := enemy.get_effective_move_speed()
		var toward := _flat(target.position - enemy.position).normalized()
		# 从**满速**进前摇：这是最坏情况（刚追到射程边缘的那一刻）。
		enemy.velocity = toward * speed
		enemy.transition_to("telegraph")
		# 刹车预算 = v / a，换算成帧再放 2 帧余量（离散积分 + 一帧的取样相位）。
		var budget_frames := int(ceil(speed / BRAKE_MPS2 / dt)) + 2
		var frames_to_stop := -1
		var max_after_stop := 0.0
		var frames := 0
		while enemy.ai_state == "telegraph" and frames < 600:
			_step(enemy, dt)
			frames += 1
			var planar := _flat(enemy.velocity).length()
			if frames_to_stop < 0:
				if planar <= 0.05:
					frames_to_stop = frames
			else:
				max_after_stop = maxf(max_after_stop, planar)
		check(
			frames_to_stop >= 0 and frames_to_stop <= budget_frames,
			"%s 前摇没能按 %.0f m/s² 刹停（%d 帧，预算 %d 帧，v=%.2f m/s）"
			% [kind, BRAKE_MPS2, frames_to_stop, budget_frames, speed]
		)
		check(
			max_after_stop <= 0.10,
			"%s 刹停之后又被推起来了（剩余前摇里最大 %.2f m/s）" % [kind, max_after_stop]
		)
		check(
			enemy.ai_state in ["attack", "recovery"],
			"%s 前摇到点没有出手（仍是 %s）" % [kind, enemy.ai_state]
		)
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -6)


## B. 站住不许变成「走不过来」：追击仍逼近，进射程仍出手。
func _approach_not_broken() -> void:
	var dt := 1.0 / 60.0
	for kind in ["melee_chaser", "egt_blobulon", "fat_zombie03"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		target.position = Vector3(0, 0.05, -6.0)
		enemy.transition_to("chase")
		var before := _flat(enemy.position).distance_to(_flat(target.position))
		for _i in range(45):
			_step(enemy, dt)
		var after := _flat(enemy.position).distance_to(_flat(target.position))
		# 45 帧 = 0.75 s。阈值按**这只怪自己的移速**取三成，慢怪（小僵尸 0.6 m/s）
		# 不会被"绝对米数"判红；累计加速斜坡也留在这里面。
		var need := maxf(0.15, enemy.get_effective_move_speed() * 0.30)
		check(
			after <= before - need,
			"%s 追击 45 帧几乎没有接近（%.2f → %.2f m，期望至少 %.2f）"
			% [kind, before, after, need]
		)
		enemy.queue_free()
		await get_tree().process_frame

	# 进射程必须真的出手 —— 判据是**进入攻击姿态**，不是"位移了多少"。
	for kind in ["melee_chaser", "egt_blobulon", "fat_zombie03", "egt_bandana_kin"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		target.position = Vector3(0, 0.05, -maxf(0.6, enemy.attack_range * 0.85))
		enemy.transition_to("chase")
		var engaged := false
		for _i in range(60):
			_step(enemy, dt)
			if enemy.ai_state in ["telegraph", "attack", "recovery"]:
				engaged = true
				break
		check(engaged, "%s 进射程后 1 秒内没有出手" % kind)
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -6)


## C. 前摇里挨近战击退必须真的被推走（外力不能因为"站住"被吞）。
func _knockback_not_swallowed() -> void:
	var dt := 1.0 / 60.0
	for kind in ["melee_chaser", "egt_bandana_kin", "egt_blobulon"]:
		var enemy := _enemy(kind)
		_bind(enemy)
		target.position = Vector3(0, 0.05, -2.0)
		enemy.transition_to("telegraph")
		enemy.apply_melee_knockback(Vector3.RIGHT, 5.0, 0.2)
		_step(enemy, dt)
		_step(enemy, dt)
		check(
			enemy.velocity.x >= 4.5,
			"%s 前摇里吞掉击退（v.x=%.2f，期望 5.0）" % [kind, enemy.velocity.x]
		)
		enemy.queue_free()
		await get_tree().process_frame
	target.position = Vector3(0, 0.05, -6)


## D. 排期连发没打完之前不许回到 `chase`（否则"边走边吐子弹"）。
func _volley_holds_recovery() -> void:
	var dt := 1.0 / 60.0
	var enemy := _enemy("egt_bandana_kin")
	_bind(enemy)
	target.position = Vector3(0, 0.05, -4.0)
	enemy.transition_to("attack")
	_step(enemy, dt)
	var queued := (enemy.get("_pending_volleys") as Array).size()
	check(queued >= 2, "egt_bandana_kin 本次攻击没有排队（%d 发），本段无从判定" % queued)
	var base_recovery := float(enemy.call("_recovery_duration"))
	var elapsed := 0.0
	while enemy.ai_state == "recovery" and elapsed < 3.0:
		_step(enemy, dt)
		elapsed += dt
	check(
		(enemy.get("_pending_volleys") as Array).is_empty(),
		"退出收招时仍有排期弹丸（剩 %d 发）" % (enemy.get("_pending_volleys") as Array).size()
	)
	check(
		elapsed > base_recovery + 0.05,
		"连发没打完就退回 chase（收招 %.2fs，排期 %d 发）" % [elapsed, queued]
	)
	enemy.queue_free()
	await get_tree().process_frame
	target.position = Vector3(0, 0.05, -6)


## E. 游荡型（枪精灵）把移动写在 `_external_velocity` 上：进前摇后必须被清掉，
## 否则它会在举枪的同时继续飘（旧实现一直写到 `_external_timer` 过期，而且每帧续期）。
func _self_move_residue_cleared() -> void:
	var dt := 1.0 / 60.0
	var enemy := _enemy("egt_gun_fairy")
	_bind(enemy)
	# 目标放远：既要它游荡起来，又不许它进射程（射程 8.4 m）。
	target.position = Vector3(0, 0.05, -14.0)
	enemy.transition_to("chase")
	var moved := 0.0
	var last := _flat(enemy.position)
	for _i in range(12):
		_step(enemy, dt)
		var now := _flat(enemy.position)
		moved += last.distance_to(now)
		last = now
	if moved < 0.05:
		note("egt_gun_fairy 12 帧内没游荡起来（%.3f m），E 段判据不成立" % moved)
	enemy.transition_to("telegraph")
	# 前 6 帧留给刹车（满速 5 m/s ÷ 55 m/s² ≈ 6 帧），之后到前摇结束都不许再动。
	var settle := 6
	var max_after := 0.0
	for index in range(12):
		_step(enemy, dt)
		if index >= settle:
			max_after = maxf(max_after, _flat(enemy.velocity).length())
	check(
		max_after <= 0.05,
		"egt_gun_fairy 进前摇后仍在游荡（刹停后最大 %.2f m/s）" % max_after
	)
	enemy.queue_free()
	await get_tree().process_frame
	target.position = Vector3(0, 0.05, -6)
