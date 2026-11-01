extends Node3D
## 启动前由runner隔离APPDATA。真实物理/导航、33种怪受光数值和三套骨动画回归。
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []

class Target extends CharacterBody3D:
	var current_hp := 100000
	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		current_hp -= amount

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _ready() -> void:
	_box(Vector3(0, -0.2, 0), Vector3(100, 0.4, 100))
	await get_tree().physics_frame
	await _slow_progress()
	await _stable_avoidance()
	await _navigation_and_contact()
	await _light_values()
	await _visuals()
	if failures.is_empty():
		print("ENEMY_LIGHT_MOTION_REGRESSION_OK")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _enemy(kind: String) -> Enemy3D:
	var enemy := ENEMY.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body

func _slow_progress() -> void:
	var enemy := _enemy("egt_bullet_kin")
	# 物理帧率与速度相互独立；正常慢走不能产生恢复侧推。
	for fps in [30, 60, 120]:
		for speed in [0.12, 0.4, 1.2]:
			enemy.position = Vector3.ZERO
			enemy.set("_last_motion_position", Vector3.ZERO)
			enemy.set("_stuck_time", 0.0)
			enemy.set("_stuck_recovery_count", 0)
			for frame in range(fps * 2):
				enemy.position.x += speed / float(fps)
				enemy.call("_track_stuck_recovery", 1.0 / fps, Vector3.RIGHT * speed)
			check(int(enemy.get("_stuck_recovery_count")) == 0,
				"正常慢走误报卡住：fps=%d speed=%.2f count=%d" % [fps, speed, enemy.get("_stuck_recovery_count")])
	# 真实堵死仍须被发现，不能靠关闭恢复消除抖动。
	enemy.set("_stuck_time", 0.0)
	enemy.set("_stuck_recovery_count", 0)
	for frame in range(55):
		enemy.call("_track_stuck_recovery", 1.0 / 60.0, Vector3.RIGHT)
	check(int(enemy.get("_stuck_recovery_count")) == 1, "真实堵死未在0.8秒触发一次恢复")
	enemy.queue_free()
	await get_tree().process_frame

func _stable_avoidance() -> void:
	var wall := _box(Vector3(0, 1.5, -0.8), Vector3(4, 3, 0.3))
	var enemy := _enemy("egt_bullet_kin")
	await get_tree().physics_frame
	enemy.set("_stuck_time", 0.4)
	enemy.set("_avoidance_sign", 1.0)
	var first := enemy.call("_apply_local_avoidance", Vector3.FORWARD, Vector3.FORWARD) as Vector3
	for frame in 8:
		var next := enemy.call("_apply_local_avoidance", Vector3.FORWARD, Vector3.FORWARD) as Vector3
		check(first.dot(next) > 0.9, "同一障碍前避障方向逐帧翻转")
	enemy.queue_free()
	wall.queue_free()
	await get_tree().process_frame

func _navigation_and_contact() -> void:
	# 四块面围成有洞的导航环：墙体与洞对齐，必须绕两端而非直接顶墙。
	var region := NavigationRegion3D.new()
	var nav := NavigationMesh.new()
	nav.vertices = PackedVector3Array([
		Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, -3), Vector3(-10, 0, -3),
		Vector3(-10, 0, 3), Vector3(10, 0, 3), Vector3(10, 0, 10), Vector3(-10, 0, 10),
		Vector3(-2, 0, -3), Vector3(-2, 0, 3), Vector3(2, 0, -3), Vector3(2, 0, 3)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 10, 8, 3]))
	nav.add_polygon(PackedInt32Array([4, 9, 11, 5, 6, 7]))
	nav.add_polygon(PackedInt32Array([3, 8, 9, 4]))
	nav.add_polygon(PackedInt32Array([10, 2, 5, 11]))
	region.navigation_mesh = nav
	add_child(region)
	NavigationServer3D.map_set_active(get_world_3d().navigation_map, true)
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)
	var wall := _box(Vector3(0, 1.5, 0), Vector3(1, 3, 4))
	for frame in 5:
		await get_tree().physics_frame
	var enemy := _enemy("egt_bullet_kin")
	enemy.position = Vector3(-5, 0.05, 0)
	var target := Target.new()
	add_child(target)
	target.position = Vector3(5, 0.05, 0)
	enemy.set("_target", target)
	enemy.set("_attack_timer", 100.0)
	var offset := target.position - enemy.position
	var route := enemy.call("_navigation_direction", target.position, offset) as Vector3
	print("NAV_ROUTE %s" % route)
	await get_tree().physics_frame
	route = enemy.call("_navigation_direction", target.position, offset) as Vector3
	check(absf(route.z) > 0.2, "绕障验收缺少有效导航路径")
	enemy.velocity = Vector3.ZERO
	enemy.call("_tick_chase", offset, offset.length(), 1.0 / 60.0)
	var velocity := Vector3(enemy.velocity.x, 0, enemy.velocity.z).normalized()
	check(velocity.dot(route) > 0.95, "远程逼近覆盖导航方向，仍然直冲墙体：route=%s velocity=%s" % [route, velocity])
	# 攻击已开始后落下的门，也要在接触结算这一帧遮挡伤害。
	enemy.queue_free()
	await get_tree().process_frame
	enemy = _enemy("egt_blobulon")
	enemy.position = Vector3(-0.9, 0.05, 0)
	target.position = Vector3(0.9, 0.05, 0)
	enemy.set("_target", target)
	var hp := target.current_hp
	var contact := target.position - enemy.position
	enemy.call("_perform_egt_contact", contact, contact.length())
	check(target.current_hp == hp, "布洛布接触攻击隔墙扣血")
	wall.free()
	await get_tree().physics_frame
	enemy.call("_perform_egt_contact", contact, contact.length())
	check(target.current_hp < hp, "无遮挡接触攻击没有正常命中")
	enemy.queue_free()
	target.queue_free()
	region.queue_free()
	await get_tree().process_frame

func _light_values() -> void:
	var count := 0
	for kind in Enemy3D.PROFILES:
		if not str(kind).begins_with("egt_"):
			continue
		print("LIGHT_VALUE kind=%s" % kind)
		var enemy := _enemy(kind)
		var baseline := [enemy.move_speed, enemy.attack_cooldown, enemy.contact_damage, enemy.attack_range, enemy.max_hp, enemy.call("_telegraph_duration"), enemy.call("_recovery_duration")]
		for cycle in 4:
			enemy.illumination_sensor.illumination_state = EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
			check(is_equal_approx(enemy.get_effective_move_speed(), enemy.move_speed * 0.4), "%s照射移速不为40%%" % kind)
			check(is_equal_approx(enemy.get_attack_frequency_multiplier(), 1.0), "%s照射改变攻击频率" % kind)
			enemy.illumination_sensor.illumination_state = EnemyIllumination3D.STATE_DARKNESS
			check(is_equal_approx(enemy.get_effective_move_speed(), enemy.move_speed), "%s离光未恢复移速" % kind)
		check(baseline == [enemy.move_speed, enemy.attack_cooldown, enemy.contact_damage, enemy.attack_range, enemy.max_hp, enemy.call("_telegraph_duration"), enemy.call("_recovery_duration")], "%s照射写坏基础数值" % kind)
		enemy.queue_free()
		await get_tree().process_frame
		count += 1
	check(count == 33, "怪物受光覆盖数不为33：%d" % count)
	print("LIGHT_VALUES kinds=%d" % count)

func _visuals() -> void:
	var render := "--visual" in OS.get_cmdline_user_args()
	var lamp: SpotLight3D
	if render:
		var camera := Camera3D.new()
		add_child(camera)
		camera.position = Vector3(4, 4, 7)
		camera.look_at(Vector3(0, 1.2, 0))
		camera.current = true
		var fill := OmniLight3D.new()
		fill.position = Vector3(-3, 4, 3)
		fill.light_energy = 2.0
		fill.omni_range = 15
		add_child(fill)
		lamp = SpotLight3D.new()
		lamp.position = Vector3(0, 2, 5)
		lamp.spot_range = 12
		lamp.spot_angle = 45
		lamp.light_color = Color(1, 0.7, 0.4)
		lamp.light_energy = 6
		add_child(lamp)
		lamp.look_at(Vector3(0, 1, 0))
	for kind in ["melee_chaser", "ranged_caster", "fat_zombie03"]:
		var scene := load(EnemyAvatar3D.FORMAL_NORMAL_SCENES[kind]) as PackedScene
		var visual := scene.instantiate() as Node3D
		add_child(visual)
		visual.set_process(false)
		var mixer := visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
		var last: Array[Quaternion] = []
		var worst := 0.0
		var switches := 0
		var previous := ""
		var speed := 0.83
		for frame in 240:
			var lit := frame >= 100 and frame < 160
			var base := 2.59 * (0.4 if lit else 1.0)
			speed = lerpf(speed, base * 0.32, 3.2 / 60.0)
			visual.call("_process", 1.0 / 60.0)
			visual.call("sync_state", "patrol", 3.0 + frame / 60.0, speed, 0.38, 0.34, base)
			mixer.advance(0.0)
			var snapshot: Dictionary = visual.call("get_presentation_snapshot")
			var clip := str(snapshot["clip"])
			if frame >= 90:
				if previous != clip:
					switches += 1
				for bone in skeleton.get_bone_count():
					var pose := skeleton.get_bone_pose_rotation(bone)
					if last.size() > bone:
						worst = maxf(worst, rad_to_deg(last[bone].angle_to(pose)))
			last.clear()
			for bone in skeleton.get_bone_count():
				last.append(skeleton.get_bone_pose_rotation(bone))
			previous = clip
			if render:
				lamp.visible = lit
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				if frame in [90, 140, 200]:
					var path := OS.get_environment("ENEMY_AI_VISUAL_OUTPUT")
					check(not path.is_empty(), "视觉验收未配置截图输出目录")
					if not path.is_empty():
						get_viewport().get_texture().get_image().save_png(path.path_join("%s_%03d.png" % [kind, frame]))
		check(switches == 0, "%s手电扫射引起%d次走跑切换" % [kind, switches])
		check(worst < 12.0, "%s手电扫射单帧骨骼跳变%.2f度" % [kind, worst])
		# 在淡化未结束时进入攻击，实际播放器必须立即服从战斗态。
		if kind != "fat_zombie03":
			visual.call("sync_state", "patrol", 5.0, 0.83, 0.38, 0.34, 2.59)
			visual.call("sync_state", "patrol", 5.01, 2.59, 0.38, 0.34, 2.59)
			visual.call("sync_state", "telegraph", 0.05, 0.5, 0.38, 0.34, 2.59)
			var expected := "shoot" if kind == "ranged_caster" else "attack"
			check(mixer.assigned_animation == expected, "%s淡化期忽略攻击，实际仍播%s" % [kind, mixer.assigned_animation])
		print("LIGHT_VISUAL kind=%s switches=%d worst_deg=%.3f" % [kind, switches, worst])
		visual.free()
