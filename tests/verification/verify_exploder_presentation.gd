extends Node3D
## 运行方必须在 Autoload 启动前隔离 APPDATA 等用户数据目录；场景内 test_mode 不等于存档隔离。
## 本专项使用正式 Enemy 预制体及运行时快照，不复制玩法实现，不重复 CPU 蒙皮验收。

const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const FORMAL_SCENE := "res://assets/art/enemies/normal_enemy_3d/exploder/runtime/enm_bomber_fruit01_root_top3d.tscn"
const PROXIES := ["egt_pinhead", "egt_nitra", "egt_bullat", "egt_king_bullat", "egt_shotgat", "egt_grenat", "egt_spirat"]
var failures: Array[String] = []
var checks := 0
var killed_events := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func near(actual: float, expected: float, message: String, tolerance := 0.0001) -> void:
	check(absf(actual - expected) <= tolerance, "%s：实际 %.6f，预期 %.6f" % [message, actual, expected])


func _enemy(kind := "exploder", elite := false) -> Enemy3D:
	var enemy := ENEMY.instantiate() as Enemy3D
	enemy.enemy_kind = kind
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.configure_from_enemy_data({"enemy_type": kind, "name": "专项验证", "is_elite": elite})
	enemy.avatar.set_process(false)
	if enemy.avatar.has_formal_normal():
		enemy.avatar._formal_normal_root.set_process(false)
	return enemy


func _presentation(enemy: Enemy3D) -> Dictionary:
	return enemy.get_state_snapshot().get("component_snapshot", {}).get("presentation", {}) as Dictionary


func _projectiles() -> Array[Projectile3D]:
	var result: Array[Projectile3D] = []
	for child in get_children():
		if child is Projectile3D:
			result.append(child as Projectile3D)
	return result


func _on_killed(_enemy_node: Enemy3D, _data: Dictionary) -> void:
	killed_events += 1


func _ready() -> void:
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		push_error("EXPLODER_PRESENTATION_TIMEOUT：专项未完成")
		get_tree().quit(1)
	)
	print("EXPLODER_PRESENTATION_ENV user_data_dir=", OS.get_user_data_dir(), " APPDATA=", OS.get_environment("APPDATA"))
	var enemy := _enemy()
	check(enemy.get_script().resource_path == "res://src/enemy3d/Enemy3D.gd", "必须使用正式 Enemy3D")
	check(enemy.avatar.has_formal_normal(), "configure exploder 未挂正式模型")
	if not enemy.avatar.has_formal_normal():
		enemy.free()
		_finish()
		return
	var visual := enemy.avatar._formal_normal_root as Node3D
	check(visual.scene_file_path == FORMAL_SCENE, "未使用炸弹果新正式包装")
	var material_count := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		check(mesh_instance.mesh != null, "正式网格资源缺失：" + str(node.name))
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			material_count += 1
			var label := "%s 面%d" % [node.name, surface]
			var material := mesh_instance.get_active_material(surface) as StandardMaterial3D
			check(material != null, "正式表面缺少 StandardMaterial3D：" + label)
			if material == null:
				continue
			var texture := material.albedo_texture
			check(texture != null, "正式材料 albedo_texture 为空，存在白模：" + label)
			if texture != null:
				check(texture.get_width() > 0 and texture.get_height() > 0, "正式材料纹理尺寸必须大于0：" + label)
	check(material_count > 0, "正式模型没有可验证的材料表面")
	var snapshot := _presentation(enemy)
	check(int(snapshot.get("bone_count", 0)) == 14, "正式模型必须为14骨")
	near(float(snapshot.get("visual_height", 0.0)), 1.15, "源高度契约")
	near(float(snapshot.get("death_duration", 0.0)), 0.34, "死亡快照时长")
	near(enemy.avatar.get_formal_death_duration(), 0.34, "Enemy 消费的死亡回收时长")
	var shape := enemy.collision_shape.shape as CylinderShape3D
	check(shape != null, "原碰撞必须为圆柱")
	if shape != null:
		near(shape.radius, 0.88, "原碰撞半径")
		near(shape.height, 1.28, "原碰撞高度")
	check(enemy.scale.is_equal_approx(Vector3.ONE * 0.546), "根缩放必须保持0.546")
	near(float(enemy.get_state_snapshot().get("world_collision_radius", 0.0)), 0.48048, "世界碰撞半径")
	var skeletons := visual.find_children("*", "Skeleton3D", true, false)
	check(skeletons.size() == 1, "正式模型必须恰好一个骨架")
	var player := visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(player != null, "正式模型缺少 AnimationPlayer")
	if skeletons.size() != 1 or player == null:
		enemy.free()
		_finish()
		return
	var skeleton := skeletons[0] as Skeleton3D
	check(skeleton.get_bone_count() == 14, "实际骨架必须为14骨")
	var root_bone := skeleton.find_bone("Root")
	check(root_bone >= 0, "缺少 Root 骨")
	check(player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "动画必须手动采样")
	check(player.root_motion_track.is_empty(), "不得启用根运动")
	var clips: Array[String] = []
	for clip in player.get_animation_list():
		if clip != "RESET":
			clips.append(str(clip))
	check(clips.size() == 2 and "move" in clips and "explode" in clips, "仅允许 move/explode 两段动作")
	for clip in ["move", "explode"]:
		check(player.has_animation(clip), "缺少动作 " + clip)
		if not player.has_animation(clip):
			continue
		var animation := player.get_animation(clip)
		near(animation.length, 0.5 if clip == "move" else 0.9, "实际导入时长 " + clip, 0.001)
		check(animation.loop_mode == (Animation.LOOP_LINEAR if clip == "move" else Animation.LOOP_NONE), "循环模式错误 " + clip)
		near(animation.step, 1.0 / 60.0, "动作采样步长 " + clip)
	near(float(snapshot.get("actual_move_duration", 0.0)), 0.5, "快照 move 时长", 0.001)
	near(float(snapshot.get("actual_explode_duration", 0.0)), 0.9, "快照 explode 时长", 0.001)
	var model_root := visual.get_node("VisualGLB") as Node3D
	var root_transform := model_root.transform
	for state in ["idle", "patrol", "alert", "chase", "search", "return"]:
		enemy.avatar.sync_presentation(state, 0.1, 1.8445, 0.9, 0.48, 1.8445)
		check(_presentation(enemy).get("clip") == "move", "移动状态必须使用 move：" + state)
	var before := float(_presentation(enemy).get("sample_time", -1.0))
	visual.call("_process", 0.1)
	near(float(_presentation(enemy).get("sample_time", -1.0)), fposmod(before + 0.1, 0.5), "满速步态时间")
	enemy.avatar.sync_presentation("chase", 0.0, 0.18445, 0.9, 0.48, 0.18445)
	before = float(_presentation(enemy).get("sample_time", -1.0))
	visual.call("_process", 0.1)
	near(float(_presentation(enemy).get("sample_time", -1.0)), fposmod(before + 0.01, 0.5), "减速步频不得随 base_speed 复原")
	enemy.avatar.sync_presentation("idle", 0.0, 0.0, 0.9, 0.48)
	before = float(_presentation(enemy).get("sample_time", -1.0))
	visual.call("_process", 0.25)
	near(float(_presentation(enemy).get("sample_time", -1.0)), before, "静止不得原地踏步")
	for duration in [0.9, 1.2]:
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			enemy.avatar.sync_presentation("telegraph", duration * fraction, 0.0, duration, 0.48)
			check(_presentation(enemy).get("clip") == "explode", "前摇必须采样 explode")
			near(float(_presentation(enemy).get("sample_time", -1.0)), 0.9 * fraction, "前摇时间映射")
			_check_root(skeleton, root_bone, model_root, root_transform, "telegraph")
	for state in ["attack", "recovery"]:
		enemy.avatar.sync_presentation(state, 0.0, 0.0, 0.9, 0.48)
		near(float(_presentation(enemy).get("sample_time", -1.0)), 0.9, "出手/收招必须保持末帧：" + state)
	for clip in clips:
		for fraction in [0.0, 0.48, 1.0]:
			player.play(clip)
			player.seek(player.get_animation(clip).length * fraction, true)
			_check_root(skeleton, root_bone, model_root, root_transform, clip)
	# 验证正式 Enemy._process 的同步链，而非只验证包装的手动接口。
	enemy.transition_to("telegraph")
	enemy.set("_state_time", 0.45)
	enemy.call("_process", 0.0)
	check(_presentation(enemy).get("state") == "telegraph", "Enemy 未向包装同步状态")
	near(float(_presentation(enemy).get("sample_time", -1.0)), 0.45, "Enemy 状态时间未驱动采样")
	enemy.free()
	for kind in PROXIES:
		var proxy := _enemy(kind)
		check(proxy.enemy_kind == kind, "代理未成功 configure：" + kind)
		check(not proxy.avatar.has_formal_normal(), "代理错误挂载新模型：" + kind)
		check(bool(proxy.avatar.get_component_snapshot().get("procedural_pose", false)), "代理必须保留程序模型：" + kind)
		proxy.free()
	var elite := _enemy("exploder", true)
	check(not elite.avatar.has_formal_normal(), "精英与正式普通模型必须互斥")
	elite.free()
	await _check_speed30()
	await _check_death(false)
	await _check_death(true)
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.clear_all()
	await get_tree().process_frame
	_finish()


func _check_root(skeleton: Skeleton3D, root_bone: int, model_root: Node3D, initial: Transform3D, label: String) -> void:
	if root_bone >= 0:
		check(skeleton.get_bone_pose(root_bone).is_equal_approx(skeleton.get_bone_rest(root_bone)), "Root 偏离绑定静止矩阵：" + label)
	check(model_root.transform.is_equal_approx(initial), "VisualGLB 根变换漂移：" + label)


func _check_death(active: bool) -> void:
	var enemy := _enemy()
	var visual := enemy.avatar._formal_normal_root as Node3D
	check(visual != null, "死亡用例缺少正式模型")
	if visual == null:
		enemy.free()
		return
	killed_events = 0
	enemy.killed.connect(_on_killed)
	var before := _projectiles()
	var original_scale := enemy.scale
	if active:
		enemy.call("_explode")
	else:
		enemy.take_damage(enemy.max_hp + 1)
	var spawned: Array[Projectile3D] = []
	for projectile in _projectiles():
		if projectile not in before:
			spawned.append(projectile)
	check(enemy.ai_state == "dead", "死亡未进入 dead")
	check(killed_events == 1, "死亡必须只通知一次")
	check(bool(_presentation(enemy).get("active_explosion_committed", false)) == active, "主动爆炸标志错误")
	check(bool(_presentation(enemy).get("visual_visible", active)) == not active, "死亡当帧模型显隐错误")
	check(spawned.size() == (0 if active else 8), "主动爆炸应无碎片，普通击杀应恰好8碎片")
	for projectile in spawned:
		check(projectile.damage == 8, "击杀碎片伤害必须为8")
		projectile.queue_free()
	if active:
		# configure 同帧旧 VisualRoot 尚在 queue_free 队列，读取当前预警环而非同名旧节点。
		check(not (enemy.avatar.get("_tell_ring") as Node3D).visible, "主动爆炸当帧预警环未隐藏")
	enemy.call("_process", 0.0)
	check(visual.visible == not active, "后续 Enemy 同步错误还原死亡显隐")
	check(enemy.scale.is_equal_approx(original_scale), "死亡不得压扁根节点")
	near(enemy.avatar.get_formal_death_duration(), 0.34, "死亡回收窗口")
	await get_tree().create_timer(0.1).timeout
	check(is_instance_valid(enemy), "死亡不足0.34秒即回收")
	await get_tree().create_timer(0.3).timeout
	check(not is_instance_valid(enemy), "死亡超过0.34秒仍未回收")
	if is_instance_valid(enemy):
		enemy.free()


## 仅追加30%提速回归：冻结v002标定，不改源动画，不把移动倍率带入蓄爆。
func _check_speed30() -> void:
	var initial_checks := checks
	var initial_failures := failures.size()
	var enemy := _enemy()
	enemy.apply_profile("exploder", false)
	near(enemy.move_speed, 2.39785, "apply_profile提速仅一次")
	near(enemy.move_speed / 1.8445, 1.3, "profile相对v002速度比")
	var default_data := {"enemy_type": "exploder"}
	for iteration in range(3):
		enemy.configure_from_enemy_data(default_data)
		near(enemy.move_speed, 2.39785, "无speed重复configure不得叠乘%d" % iteration)
	var injector := MonsterInjector.new()
	near(float(MonsterInjector.BASE_ENEMY_TYPES["exploder"]["speed"]), 91.0, "Injector基础字段")
	var injected := injector.generate_box_enemy("exploder", 1, 1)
	near(float(injected["speed"]), 91.0, "Injector生成字段")
	for iteration in range(3):
		enemy.configure_from_enemy_data(injected)
		near(enemy.move_speed, 2.256041667, "注入重复configure不得叠乘%d" % iteration)
	near(enemy.move_speed / 1.735416667, 1.3, "Injector相对v002速度比")
	for multiplier in [0.8, 1.2]:
		var source_data := injected.duplicate(true)
		source_data["speed"] = float(injected["speed"]) * multiplier
		enemy.configure_from_enemy_data(source_data)
		near(enemy.move_speed, 2.256041667 * multiplier, "source速度倍率正常")
		var theme := MapThemeProfile.new()
		theme.enemy_rules = {"speed_multiplier": multiplier}
		injector.set_theme_profile(theme)
		var themed := injector.generate_box_enemy("exploder", 1, 1)
		near(float(themed["speed"]), 91.0 * multiplier, "主题只乘一次生成字段")
		enemy.configure_from_enemy_data(themed)
		near(enemy.move_speed, 2.256041667 * multiplier, "主题注入速度正常")
	injector.set_theme_profile(null)
	var unchanged_profiles := {
		"fat_zombie03": 0.857142857, "melee_chaser": 3.7, "ranged_caster": 2.25,
		"summoner": 1.65, "shielded": 2.0, "ambusher": 4.65, "boss": 1.72,
		"egt_bullet_kin": 2.857, "egt_bandana_kin": 2.857, "egt_veteran_kin": 3.714,
		"egt_red_shotgun": 2.857, "egt_blue_shotgun": 2.857, "egt_blobulon": 3.143,
		"egt_blobuloid": 3.429, "egt_blobulin": 4.857, "egt_pinhead": 3.429,
		"egt_nitra": 3.429, "egt_bullat": 3.429, "egt_gunsinger": 1.429,
		"egt_cardinal": 2.857, "egt_hollowpoint": 2.571, "egt_veteran_shotgun": 2.857,
		"egt_king_bullat": 0.857, "egt_chancebulon": 3.429, "egt_bookllet": 2.286,
		"egt_blue_bookllet": 2.286, "egt_green_bookllet": 2.286, "egt_gunjurer": 2.143,
		"egt_gigi": 5.143, "egt_shotgat": 3.429, "egt_grenat": 3.429, "egt_spirat": 3.429,
		"egt_keybullet_kin": 4.286, "egt_chance_kin": 4.286, "egt_confirmed": 3.143,
		"egt_mimic": 3.143, "egt_gun_fairy": 4.286, "egt_gripmaster": 2.857,
		"egt_gun_nut": 2.571, "egt_chain_gunner": 3.0,
	}
	for kind in unchanged_profiles:
		near(float(Enemy3D.PROFILES[kind]["speed"]), float(unchanged_profiles[kind]), "其它怪/7proxy的profile不得改：" + kind)
		enemy.apply_profile(kind, false)
		near(enemy.move_speed, float(unchanged_profiles[kind]) * 0.595, "其它怪实际profile速度不得改：" + kind)
	var unchanged_injector := {
		"fat_zombie03": 20.5714286, "melee_chaser": 80.0, "ranged_caster": 50.0,
		"summoner": 40.0, "ambusher": 90.0, "boss": 42.0,
		"melee_chaser_strong": 80.0, "fat_zombie03_strong": 20.5714286, "ranged_caster_strong": 50.0,
		"egt_bullet_kin": 69.0, "egt_bandana_kin": 69.0, "egt_veteran_kin": 89.0,
		"egt_red_shotgun": 69.0, "egt_blue_shotgun": 69.0, "egt_blobulon": 75.0,
		"egt_blobuloid": 82.0, "egt_blobulin": 117.0, "egt_pinhead": 82.0,
		"egt_nitra": 82.0, "egt_bullat": 82.0, "egt_gunsinger": 34.0,
		"egt_cardinal": 69.0, "egt_hollowpoint": 62.0, "egt_veteran_shotgun": 69.0,
		"egt_king_bullat": 21.0, "egt_chancebulon": 82.0, "egt_bookllet": 55.0,
		"egt_blue_bookllet": 55.0, "egt_green_bookllet": 55.0, "egt_gunjurer": 51.0,
		"egt_gigi": 123.0, "egt_shotgat": 82.0, "egt_grenat": 82.0, "egt_spirat": 82.0,
		"egt_keybullet_kin": 103.0, "egt_chance_kin": 103.0, "egt_confirmed": 75.0,
		"egt_mimic": 75.0, "egt_gun_fairy": 103.0, "egt_gripmaster": 69.0,
		"egt_gun_nut": 62.0, "egt_chain_gunner": 72.0,
	}
	for kind in unchanged_injector:
		near(float(MonsterInjector.BASE_ENEMY_TYPES[kind]["speed"]), float(unchanged_injector[kind]), "其它怪/7proxy的Injector不得改：" + kind)
	enemy.free()
	await _check_speed30_motion(default_data, 2.39785, 1.8445, "profile")
	await _check_speed30_motion(injected, 2.256041667, 1.735416667, "injector")
	await _check_speed30_explosion()
	if failures.size() == initial_failures:
		print("EXPLODER_SPEED30_OK checks_added=%d profile=2.39785 injector=2.256041667 speed_ratio=1.3 gait_ratio=1.3 sample_0.1=0.13 light_ratio=0.4 stopped=0 telegraph=0.9" % (checks - initial_checks))


func _check_speed30_motion(data: Dictionary, expected: float, old_speed: float, label: String) -> void:
	var enemy := _enemy()
	enemy.configure_from_enemy_data(data)
	enemy.avatar.set_process(false)
	var visual := enemy.avatar._formal_normal_root as Node3D
	visual.set_process(false)
	near(float(visual.get("move_reference_speed")), 1.8445, label + "标定冻结不跟改")
	var target := Node3D.new()
	add_child(target)
	enemy.position = Vector3(100.0, 100.0, 100.0)
	target.position = Vector3(200.0, 100.0, 100.0)
	enemy.set("_target", target)
	enemy.transition_to("chase")
	var distances: Array[float] = []
	var advances: Array[float] = []
	var configured_speed := enemy.move_speed
	near(configured_speed, expected, label + "真实来源配置速度")
	for speed in [old_speed, configured_speed]:
		enemy.move_speed = speed
		# 预置稳态，随后由真实追击、重力和碰撞提交推进，不把起步加速混入同比。
		enemy.velocity = Vector3(speed, 0.0, 0.0)
		var start := enemy.global_position
		for frame in range(6):
			await get_tree().physics_frame
			enemy.call("_tick_chase", target.global_position - enemy.global_position, 100.0, 1.0 / float(Engine.physics_ticks_per_second))
		near(enemy.velocity.x, speed, label + "真实追击velocity")
		near(enemy.get_real_velocity().x, speed, label + "真实物理速度", 0.002)
		var distance := enemy.global_position.x - start.x
		distances.append(distance)
		near(distance, speed * 6.0 / float(Engine.physics_ticks_per_second), label + "六物理帧直线位移", 0.002)
		near(enemy.global_position.z, 100.0, label + "直线路径不得侧移")
		enemy.call("_process", 0.0)
		near(float(_presentation(enemy).get("locomotion_speed", -1.0)), speed, label + "真实速度传动画", 0.002)
		var before := float(_presentation(enemy).get("sample_time", -1.0))
		visual.call("_process", 0.1)
		var advance := fposmod(float(_presentation(enemy).get("sample_time", -1.0)) - before, 0.5)
		advances.append(advance)
		near(advance, 0.1 * speed / 1.8445, label + "实际步频采样", 0.0002)
	near(distances[1] / distances[0], 1.3, label + "实际位移同比1.3", 0.002)
	near(advances[1] / advances[0], 1.3, label + "实际步频同比1.3", 0.002)
	if label == "profile":
		near(advances[1], 0.13, "0.1秒推进0.13而非0.169", 0.0002)
	enemy.illumination_sensor.illumination_state = EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
	near(enemy.get_effective_move_speed(), expected * 0.4, label + "光照速度40%")
	enemy.velocity = Vector3(enemy.get_effective_move_speed(), 0.0, 0.0)
	await get_tree().physics_frame
	enemy.call("_tick_chase", target.global_position - enemy.global_position, 100.0, 1.0 / float(Engine.physics_ticks_per_second))
	near(enemy.get_real_velocity().x, expected * 0.4, label + "光照真实速度", 0.002)
	enemy.call("_process", 0.0)
	var before := float(_presentation(enemy).get("sample_time", -1.0))
	visual.call("_process", 0.1)
	near(fposmod(float(_presentation(enemy).get("sample_time", -1.0)) - before, 0.5) / advances[1], 0.4, label + "光照动画相位同比40%", 0.002)
	await get_tree().physics_frame
	enemy.call("_stop_planar")
	enemy.call("_commit_motion", 1.0 / float(Engine.physics_ticks_per_second))
	enemy.call("_process", 0.0)
	near(float(_presentation(enemy).get("locomotion_speed", -1.0)), 0.0, label + "停步真实速度传0")
	before = float(_presentation(enemy).get("sample_time", -1.0))
	visual.call("_process", 0.1)
	near(float(_presentation(enemy).get("sample_time", -1.0)), before, label + "停步相位不推进")
	enemy.transition_to("telegraph")
	enemy.set("_state_time", 0.45)
	enemy.call("_process", 0.0)
	visual.call("_process", 0.1)
	near(float(_presentation(enemy).get("sample_time", -1.0)), 0.45, label + "explode不乘1.3也不随光照减速")
	near(float(enemy.call("_telegraph_duration")), 0.9, label + "前摇时长冻结")
	near(enemy.attack_range, 2.85, label + "原攻击范围")
	near(enemy.attack_cooldown, 3.0, label + "原攻击冷却")
	check(enemy.contact_damage == 30, label + "原攻击伤害30")
	print("EXPLODER_SPEED30_MOTION ", JSON.stringify({"source": label, "actual_speed": configured_speed, "distances": distances, "advances_0.1": advances, "speed_ratio": distances[1] / distances[0], "gait_ratio": advances[1] / advances[0]}))
	enemy.free()
	target.free()


func _check_speed30_explosion() -> void:
	var player := (load("res://scenes/Player3D.tscn") as PackedScene).instantiate() as Player3D
	player.start_with_weapon = false
	player.position = Vector3(-100.0, 0.0, -101.5)
	add_child(player)
	player.set_physics_process(false)
	player.is_invincible = false
	var enemy := _enemy()
	enemy.position = Vector3(-100.0, 0.0, -100.0)
	enemy.set("_target", player)
	MonsterAIManager.notify_enemy_attacked(enemy, player)
	enemy.set("_ai_decision", MonsterAIManager.force_refresh_enemy(enemy))
	enemy.killed.connect(_on_killed)
	killed_events = 0
	var hp_before := player.current_hp
	var fragments_before := _projectiles().size()
	enemy.transition_to("telegraph")
	enemy.call("_physics_process", 0.899)
	check(enemy.ai_state == "telegraph" and player.current_hp == hp_before, "0.899秒不得提前爆炸/伤害")
	enemy.call("_process", 0.0)
	near(float(_presentation(enemy).get("sample_time", -1.0)), 0.899, "蓄爆相位按原始0.9秒不加速")
	enemy.call("_physics_process", 0.0011)
	check(enemy.ai_state == "attack", "0.9秒后才进入原攻击状态")
	enemy.call("_physics_process", 1.0 / 60.0)
	check(enemy.ai_state == "dead", "原攻击状态机完成主动爆炸")
	check(hp_before - player.current_hp == 30, "真实Player主动爆炸单次伤害30不变")
	check(killed_events == 1, "主动爆炸仅一次killed")
	check(_projectiles().size() == fragments_before, "主动爆炸不得产生击杀碎片")
	enemy.free()
	player.free()
	await get_tree().process_frame


func _finish() -> void:
	if failures.is_empty():
		print("EXPLODER_PRESENTATION_OK checks=%d bones=14 clips=2 move=0.5_loop explode=0.9_once root_fixed=true collision=0.88/1.28 root_scale=0.546 death=0.34 proxies=7 active_hidden=true killed_fragments=8" % checks)
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
