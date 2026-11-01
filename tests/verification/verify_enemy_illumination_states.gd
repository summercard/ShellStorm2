extends Node3D
## 怪物/Boss 三态受光、太阳投影、局部灯范围/锥体/遮挡与优先级专项。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
## 表现层预制体（小僵尸）。手电阶跃 → 步态那条判据直接驱动它，理由见
## `_verify_light_step_does_not_flip_gait()` 的头注。
const ZOMBIE_VISUAL: PackedScene = preload("res://assets/art/enemies/normal_enemy_3d/melee_chaser/runtime/enm_melee_fungboar01_root_top3d.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const WASTELAND_LIGHT_SCRIPT := preload("res://src/world3d/WastelandLight3D.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var enemy := _make_enemy("melee_chaser", Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().process_frame
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "no-light baseline", failures)

	var sun := DirectionalLight3D.new()
	sun.name = "TestGameplaySun"
	sun.light_energy = 1.0
	sun.light_cull_mask = 1
	add_child(sun)
	sun.add_to_group(EnemyIllumination3D.SUN_GROUP)
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_SUNLIGHT, "unoccluded sunlight", failures)

	# 只让头顶一条采样漏光，模拟楼梯洞/门缝/碰撞接缝；不能把整只怪判为太阳。
	var seam_blocker := _make_blocker("SunSeamBlocker", Vector3(0, 0.45, 3.0), Vector3(5.0, 0.90, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "single-sample sunlight seam", failures)
	seam_blocker.queue_free()
	await get_tree().physics_frame

	# 挡住脚边、让身体中心与头部两条射线通过，模拟低层墙面开窗/破墙的
	# 有效采光口；修复接缝误判时不能反过来封死真正进入室内的太阳。
	var window_sill := _make_blocker("SunWindowSill", Vector3(0, 0.18, 3.0), Vector3(5.0, 0.36, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_SUNLIGHT, "two-sample window sunlight", failures)
	window_sill.queue_free()
	await get_tree().physics_frame

	var sun_blocker := _make_blocker("SunBlocker", Vector3(0, 1.0, 3.0), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "sun shadow", failures)
	if float(enemy.get_state_snapshot().get("illumination", {}).get("sun_exposure_ratio", 1.0)) != 0.0:
		failures.append("Sun shadow still reports non-zero body exposure")

	sun.light_energy = 0.0
	var omni := OmniLight3D.new()
	omni.name = "TestRoomLamp"
	omni.position = Vector3(0, 1.2, -3.0)
	omni.light_energy = 4.0
	omni.omni_range = 9.0
	omni.omni_attenuation = 1.0
	omni.light_cull_mask = 1
	add_child(omni)
	omni.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	sun.light_energy = 1.0
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "room light under sun shadow", failures)
	sun.light_energy = 0.0

	var lamp_blocker := _make_blocker("LampBlocker", Vector3(0, 1.0, -1.5), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "room light wall shadow", failures)
	lamp_blocker.queue_free()
	await get_tree().physics_frame

	omni.light_energy = 0.0
	var spot := SpotLight3D.new()
	spot.name = "TestFlashlight"
	spot.position = Vector3(0, 1.0, -4.0)
	spot.light_energy = 7.2
	spot.spot_range = 10.0
	spot.spot_angle = 32.0
	spot.spot_attenuation = 0.5
	spot.spot_angle_attenuation = 1.0
	spot.light_cull_mask = 1
	add_child(spot)
	spot.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	spot.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	spot.set_meta("gameplay_light_kind", "flashlight")
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "flashlight cone", failures)
	var illumination := enemy.get_state_snapshot().get("illumination", {}) as Dictionary
	if str(illumination.get("dominant_light_kind", "")) != "flashlight":
		failures.append("Flashlight is not reported as the dominant artificial light")
	var flashlight_blocker := _make_blocker("FlashlightBlocker", Vector3(0, 1.0, -2.0), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "flashlight wall shadow", failures)
	flashlight_blocker.queue_free()
	await get_tree().physics_frame

	spot.look_at(Vector3(0, 1.0, -8.0), Vector3.UP)
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "flashlight facing away", failures)
	spot.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	spot.position = Vector3(0, 1.0, -14.0)
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "flashlight outside range", failures)
	spot.position = Vector3(0, 1.0, -4.0)
	spot.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	spot.light_energy = 0.0
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "depleted flashlight energy", failures)
	spot.light_energy = 7.2
	await _verify_ambusher_uses_real_light(failures)

	# Runtime samples require two identical candidates, preventing one-frame shadow-edge flicker.
	spot.light_energy = 0.0
	enemy.force_refresh_illumination()
	spot.light_energy = 7.2
	enemy.force_refresh_illumination(false)
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "hysteresis first sample", failures)
	enemy.force_refresh_illumination(false)
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "hysteresis second sample", failures)

	spot.light_energy = 0.0
	var fixture := WASTELAND_LIGHT_SCRIPT.new() as WastelandLight3D
	fixture.position = Vector3(0, -1.3, -3.0)
	fixture.configure(Color.WHITE, 4.6, 10.0, 7, true, false, "ceiling")
	add_child(fixture)
	await get_tree().process_frame
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT, "registered room fixture", failures)
	fixture.set_light_enabled(false)
	_verify_state(enemy, EnemyIllumination3D.STATE_DARKNESS, "room fixture switch off", failures)
	await _verify_player_flashlight_registration(failures)
	await _verify_real_player_flashlight_hit(failures)
	await _verify_player_spill_does_not_light_behind(failures)

	sun_blocker.queue_free()
	await get_tree().physics_frame
	sun.light_energy = 1.0
	enemy.force_refresh_illumination()
	_verify_state(enemy, EnemyIllumination3D.STATE_SUNLIGHT, "sun priority over flashlight", failures)

	_verify_all_enemy_kinds_share_contract(failures)
	await _verify_boss_phase_is_independent(failures)
	_verify_raycast_budget(enemy, failures)
	enemy.queue_free()
	await _verify_thirty_enemy_budget(failures)
	# 放在最后：这条用例要连跑 90 个物理帧，而无地面的用例怪会被判落地失败回收，
	# 先跑会把后面还依赖同一只怪的用例打空。
	await _verify_light_step_does_not_flip_gait(failures)

	if failures.is_empty():
		print("ENEMY_ILLUMINATION_STATES_OK: darkness, window sunlight, seam rejection, physical shadow, flashlight cone, priority, hysteresis and Boss isolation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 手电扫到怪物时，`get_effective_move_speed()` 会**阶跃**乘上 0.40，而真实速度
## 由 `_steer_planar()` 以 3.2~5.5/s 的权重指数衰减。分子分母不同步时，
## 表现层比值会在光扫到的那几帧冲过 0.62 阈值再落回来 ⇒ 段名在走路/跑步之间翻两次，
## 而换段时 `_sample = fmod(_clock, 新段长)` 且无混合 ⇒ **一帧内骨骼被硬拽 34~83°**。
## 业主报的原话是"走路动画向着一个方向抽搐一下，好像是在阴影下受到手电光照时"，
## 15 秒实测 8 次、全部落在手电扫到的瞬间。
##
## 这里直接驱动**表现层预制体**而不是整只 Enemy3D：后者在被照亮时会
## `set_runtime_active(true)` 并重建 Avatar，缓存下来的 Skeleton3D 指针会变成
## 已释放实例（实测 headless 直接 signal 11）。表现层才是这条判据的所有者。
##
## 判据三条：① 阶跃那一刻不许出现跑步段；② 单帧骨骼跳变 < 12°；
## ③ 稳态读数不变（暗处巡逻走路、被照巡逻走路、被照满速追击仍是跑步）——
## ③ 是为了防止"用把跑步段整体禁掉"的方式把①②蒙绿。
func _verify_light_step_does_not_flip_gait(failures: Array[String]) -> void:
	var visual := ZOMBIE_VISUAL.instantiate() as Node3D
	if visual == null:
		failures.append("gait-under-light: melee zombie visual failed to instantiate")
		return
	add_child(visual)
	await get_tree().process_frame
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		failures.append("gait-under-light: skeleton missing")
		visual.queue_free()
		return
	# 实机数值：小僵尸满速 2.590，手电照到后 `get_effective_move_speed()` = 1.036。
	var unlit_speed := 2.590
	var lit_speed := unlit_speed * 0.40
	const PATROL_MULTIPLIER := 0.32
	var speed := unlit_speed * PATROL_MULTIPLIER
	var base := unlit_speed
	var previous: Array = []
	var worst_jump := 0.0
	var run_frames := 0
	var lit_frames := 0
	for frame in range(90):
		# 前 30 帧在暗处走满一个循环，第 30 帧手电扫到（阶跃，与实机同）。
		if frame == 30:
			base = lit_speed
		# 实际速度按 `_tick_patrol` 的 `_steer_planar(delta*3.2)` 逼向新目标。
		speed = lerpf(speed, base * PATROL_MULTIPLIER, (1.0 / 60.0) * 3.2)
		visual.call("sync_state", "patrol", float(frame) / 60.0, speed, 0.38, 0.34, base)
		skeleton.force_update_all_bone_transforms()
		var current: Array = []
		for bone in range(skeleton.get_bone_count()):
			current.append(skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())
		if previous.size() == current.size():
			for bone in range(current.size()):
				worst_jump = maxf(worst_jump, rad_to_deg((previous[bone] as Quaternion).angle_to(current[bone])))
		previous = current
		if str(visual.get_presentation_snapshot().get("clip", "")) != "walking":
			run_frames += 1
		if base < unlit_speed * 0.5:
			lit_frames += 1
		await get_tree().physics_frame
	if lit_frames == 0:
		failures.append("gait-under-light: 没有进入被照阶段的帧，这条判据什么都没证明")
	if run_frames > 0:
		failures.append("手电扫到后走路段被切成跑步段 %d 帧（移速阶跃被当成步态变化）" % run_frames)
	if worst_jump >= 12.0:
		failures.append("手电扫到时单帧骨骼跳变 %.1f°，超过 12° 上限（换段硬拽）" % worst_jump)
	# 稳态读数：被照着的巡逻仍走路、暗处满速追击仍跑步。
	visual.call("sync_state", "patrol", 2.0, lit_speed * PATROL_MULTIPLIER, 0.38, 0.34, lit_speed)
	if str(visual.get_presentation_snapshot().get("clip", "")) != "walking":
		failures.append("被手电照着的巡逻不再用走路段（稳态语义被改坏）")
	visual.call("sync_state", "chase", 2.0, lit_speed, 0.38, 0.34, lit_speed)
	if str(visual.get_presentation_snapshot().get("clip", "")) != "running":
		failures.append("被手电照着的满速追击不再用跑步段（稳态语义被改坏）")
	# ② 换段本身不许抽（业主："走路动画为什么向着一个方向抽搐一下"）。
	#    走路段手臂自然垂摆、跑步段抬起，**相位对齐消不掉**这 35~67° 的差，
	#    只能靠 `play(name, blend)` 淡入。这里来回切 walking↔running，
	#    单帧跳变必须留在步态量级（旧实现 67°，硬化成 12° 上限）。
	var switch_worst := 0.0
	var switch_prev: Array = []
	for index in range(80):
		# 每 20 帧（0.33 s）切一次：必须长于 `CLIP_BLEND_SEC=0.16 s`，
		# 否则上一段淡化还没结束就被再次打断，量到的是叠加态而不是换段本身。
		var fast := (index / 20) % 2 == 1
		visual.call(
			"sync_state", "patrol", float(index) / 60.0,
			2.590 if fast else 0.829, 0.38, 0.34, 2.590
		)
		var mixing := visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if mixing != null:
			mixing.advance(0.0)
		if skeleton != null:
			skeleton.force_update_all_bone_transforms()
			var pose: Array = []
			for bone in range(skeleton.get_bone_count()):
				pose.append(skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())
			if switch_prev.size() == pose.size():
				for bone in range(pose.size()):
					switch_worst = maxf(
						switch_worst, rad_to_deg((switch_prev[bone] as Quaternion).angle_to(pose[bone]))
					)
			switch_prev = pose
		await get_tree().physics_frame
	if switch_worst >= 12.0:
		failures.append(
			"走路/跑步换段时单帧骨骼跳变 %.1f°，超过 12° 上限（缺交叉淡化）" % switch_worst
		)
	# 立即释放而不是排帧末：本用例后面还要用同一棵树做光照刷新，
	# 延迟释放会让已释放的骨架仍在渲染命令里被摸到（实测 headless signal 11）。
	remove_child(visual)
	visual.free()
	await get_tree().process_frame


func _verify_all_enemy_kinds_share_contract(failures: Array[String]) -> void:
	var kinds := ["melee_chaser", "ranged_caster", "summoner", "shielded", "exploder", "ambusher", "boss"]
	for index in range(kinds.size()):
		var candidate := _make_enemy(kinds[index], Vector3(30.0 + index * 3.0, 0.0, 30.0))
		candidate.force_refresh_illumination()
		var snapshot := candidate.get_state_snapshot()
		var valid := snapshot.get("illumination", {}).get("valid_illumination_states", []) as Array
		if (
			candidate.illumination_sensor == null
			or str(snapshot.get("illumination_state", "")) not in EnemyIllumination3D.VALID_STATES
			or valid.size() != 3
		):
			failures.append("Enemy kind lacks the shared three-state illumination contract: %s" % kinds[index])
		candidate.queue_free()


func _verify_boss_phase_is_independent(failures: Array[String]) -> void:
	var boss := _make_enemy("boss", Vector3(60.0, 0.0, 60.0))
	await get_tree().process_frame
	boss.current_hp = int(float(boss.max_hp) * 0.2)
	boss.call("_update_boss_phase")
	var phase_before := boss.boss_phase
	var cooldown_before := boss.attack_cooldown
	boss.force_refresh_illumination()
	if boss.boss_phase != phase_before or not is_equal_approx(boss.attack_cooldown, cooldown_before):
		failures.append("Boss illumination refresh mutates HP phase or attack timing")
	boss.queue_free()


func _verify_player_flashlight_registration(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(100.0, 0.0, 100.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D if flashlight != null else null
	var spill := flashlight.get_node_or_null("FlashlightKit/EnvironmentSpill") as OmniLight3D if flashlight != null else null
	var fill := flashlight.get_node_or_null("FlashlightKit/AvatarFrontFill") as SpotLight3D if flashlight != null else null
	if (
		flashlight == null
		or beam == null
		or spill == null
		or fill == null
		or not beam.is_in_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		or spill.is_in_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		or fill.is_in_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
		or str(beam.get_meta("gameplay_light_kind", "")) != "flashlight"
	):
		failures.append("Only the player's forward spotlight may register as gameplay illumination")
	player.queue_free()


func _verify_real_player_flashlight_hit(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(120.0, 0.0, -6.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.aim_direction = Vector3.BACK
	var target := _make_enemy("melee_chaser", Vector3(120.0, 0.0, 0.0))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("Real player flashlight hit test cannot find PlayerFlashlight3D")
		target.queue_free()
		player.queue_free()
		return
	flashlight.set_light_enabled(true)
	flashlight.force_sync()
	await get_tree().physics_frame
	target.force_refresh_illumination()
	var illumination := target.get_state_snapshot().get("illumination", {}) as Dictionary
	if (
		target.get_illumination_state() != EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
		or str(illumination.get("dominant_light_kind", "")) != "flashlight"
	):
		failures.append(
			"Real player spotlight is blocked by its owner's collision or misses illumination: %s"
			% str(illumination)
		)
	target.queue_free()
	player.queue_free()


func _verify_player_spill_does_not_light_behind(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(150.0, 0.0, 0.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.aim_direction = Vector3.FORWARD
	var target := _make_enemy("melee_chaser", Vector3(150.0, 0.0, 3.0))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	flashlight.set_light_enabled(true)
	flashlight.force_sync()
	await get_tree().physics_frame
	target.force_refresh_illumination()
	if target.get_illumination_state() != EnemyIllumination3D.STATE_DARKNESS:
		failures.append("Player environment spill incorrectly lights a monster behind the spotlight")
	target.queue_free()
	player.queue_free()


func _verify_ambusher_uses_real_light(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(20.0, 0.0, -8.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var ambusher := _make_enemy("ambusher", Vector3(20.0, 0.0, 0.0))
	ambusher.set_runtime_active(true)
	var beam := SpotLight3D.new()
	beam.position = Vector3(20.0, 1.0, -4.0)
	beam.light_energy = 7.2
	beam.spot_range = 10.0
	beam.spot_angle = 32.0
	beam.light_cull_mask = 1
	add_child(beam)
	beam.look_at(Vector3(20.0, 0.7, 0.0), Vector3.UP)
	beam.add_to_group(EnemyIllumination3D.LOCAL_LIGHT_GROUP)
	beam.set_meta("gameplay_light_kind", "flashlight")
	var wall := _make_blocker("AmbusherFlashlightWall", Vector3(20.0, 1.0, -2.0), Vector3(5.0, 4.0, 0.6))
	await get_tree().physics_frame
	ambusher.force_refresh_illumination()
	await get_tree().physics_frame
	if bool(ambusher.get_state_snapshot().get("ambush_triggered", false)):
		failures.append("Ambusher reveals from a flashlight through a wall")
	wall.queue_free()
	await get_tree().physics_frame
	ambusher.force_refresh_illumination()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not bool(ambusher.get_state_snapshot().get("ambush_triggered", false)):
		failures.append("Ambusher does not reveal when a real unobstructed flashlight beam reaches it")
	ambusher.queue_free()
	beam.queue_free()
	player.queue_free()


func _verify_state(enemy: Enemy3D, expected: String, label: String, failures: Array[String]) -> void:
	var actual := enemy.get_illumination_state()
	if actual != expected:
		failures.append("Illumination mismatch (%s): got %s expected %s" % [label, actual, expected])


func _verify_raycast_budget(enemy: Enemy3D, failures: Array[String]) -> void:
	enemy.force_refresh_illumination()
	var illumination := enemy.get_state_snapshot().get("illumination", {}) as Dictionary
	if (
		int(illumination.get("last_sun_raycast_count", 99)) > 3
		or int(illumination.get("last_local_raycast_count", 99)) > 4
	):
		failures.append("Per-sample illumination raycast budget exceeded: %s" % str(illumination))


func _verify_thirty_enemy_budget(failures: Array[String]) -> void:
	var enemies: Array[Enemy3D] = []
	var total_rays := 0
	for index in range(30):
		var enemy := _make_enemy("melee_chaser", Vector3(100.0 + index * 2.0, 0.0, 120.0))
		enemy.force_refresh_illumination()
		var illumination := enemy.get_state_snapshot().get("illumination", {}) as Dictionary
		total_rays += int(illumination.get("last_sun_raycast_count", 0))
		total_rays += int(illumination.get("last_local_raycast_count", 0))
		if enemy.get_child_count() > 3:
			failures.append("Illumination implementation adds per-enemy scene nodes")
		enemies.append(enemy)
	if total_rays > 30 * 7:
		failures.append("Thirty-enemy illumination ray budget exceeded: %d" % total_rays)
	for enemy in enemies:
		enemy.queue_free()
	await get_tree().process_frame


func _make_enemy(kind: String, world_position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	enemy.position = world_position
	add_child(enemy)
	enemy.set_runtime_active(false, true)
	return enemy


func _make_blocker(node_name: String, world_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = world_position
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body
