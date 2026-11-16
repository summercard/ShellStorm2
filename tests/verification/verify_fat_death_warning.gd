extends Node3D
## 专项：预爆生命周期、实例材质、级联、原房间快照与流送。
const ENEMY := preload("res://scenes/enemies/fat_zombie03.tscn")
const LEVEL_PATH := "res://scenes/ExpeditionLevel01_3D.tscn"
var failures: Array[String] = []
var checks := 0
var kill_ids: Array[String] = []
var serial := 0
var tower: TowerDescent3D

class Target extends Node3D:
	var damage := 0
	func take_damage(amount: int, _critical: bool, _direction: Vector3) -> void:
		damage += amount

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func spec(warning := 1.0) -> Dictionary:
	return {"enabled":true, "damage":180, "radius_m":5.0, "sfx_radius_m":0.0,
		"warning_sec":warning, "zone":{"enabled":true, "damage_per_tick":7, "duration_sec":3.0, "tick_interval_sec":0.5}}

func spawn(kind := "fat_zombie03", config: Dictionary = {}, point := Vector3.ZERO) -> Enemy3D:
	serial += 1
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.configure_from_enemy_data({"enemy_type":kind, "persistent_id":"warning_%d" % serial,
		"death_explosion":config, "override_hp":100})
	enemy.room_id = "warning_room"
	enemy.global_position = point
	GameplaySpatialRegistry3D.register_node(enemy, GameplaySpatialRegistry3D.KIND_ENEMY, enemy.room_id)
	GameplaySpatialRegistry3D.update_node(enemy, enemy.room_id)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.killed.connect(func(actor: Enemy3D, _data: Dictionary): kill_ids.append(actor.get_persistent_id()))
	return enemy

func stop_clock(enemy: Enemy3D) -> void:
	enemy.set_process(false)
	enemy.avatar._formal_normal_root.set_process(false)

func _ready() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	var isolated := appdata.contains("2026-11-16_exp01_combat/fat_warning/") or appdata.contains("2026-11-16_exp01_combat/warning_followup/")
	if not isolated:
		push_error("必须在Autoload前隔离APPDATA")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--warning-followup"):
		await followup_visual()
		print("FAT_WARNING_FOLLOWUP checks=%d failures=%d" % [checks, failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	await units()
	if OS.get_cmdline_user_args().has("--integration"):
		await integration()
	print("FAT_DEATH_WARNING checks=%d failures=%d" % [checks, failures.size()])
	for message in failures:
		print("FAILED ", message)
	get_tree().quit(0 if failures.is_empty() else 1)

func units() -> void:
	var player := Target.new()
	add_child(player)
	player.add_to_group("player_3d")
	var enemy := spawn("fat_zombie03", spec())
	var peer := spawn("fat_zombie03", {}, Vector3(20, 0, 0))
	var visual = enemy.avatar._formal_normal_root
	var other_visual = peer.avatar._formal_normal_root
	var origin := enemy.global_transform
	enemy.take_damage(100000)
	stop_clock(enemy)
	check(enemy.ai_state == "death_warning" and enemy.current_hp == 0, "致死进入HP0预爆")
	check(not enemy.is_queued_for_deletion() and kill_ids.is_empty() and player.damage == 0, "预爆不先爆炸或结算掉落")
	check(enemy.collision_layer == 0 and enemy.collision_mask == 0 and not enemy.is_physics_processing(), "预爆关闭碰撞和物理AI")
	check(visual._clip == "idle", "致死当帧保持站姿")
	for material in visual._materials:
		check(material.emission_enabled and is_zero_approx(material.emission_energy_multiplier), "预爆起点额外能量0且无致死闪白残留")
	enemy.take_damage(9, true, Vector3.RIGHT, 20.0)
	enemy.take_projectile_damage(9)
	enemy.receive_healing(1000)
	check(enemy.current_hp == 0 and not enemy.transition_to("chase"), "后续伤害/治疗/状态切换被拒绝")
	enemy.set_runtime_active(false)
	check(enemy.is_processing() and not enemy.is_physics_processing(), "AI休眠不暂停预爆")
	stop_clock(enemy)
	enemy._process(0.25)
	var shake_a: Vector3 = visual.position
	var energy_a: float = visual._materials[0].emission_energy_multiplier
	check(is_equal_approx(energy_a, 0.021875), "四分之一秒二次曲线材质能量0.021875")
	check(visual._materials[0] != other_visual._materials[0] and is_zero_approx(other_visual._materials[0].emission_energy_multiplier), "实例材质不污染另一只")
	if OS.get_cmdline_user_args().has("--render"):
		await capture(enemy, "warning_025.png")
	enemy._process(0.5)
	check(visual.position.distance_to(shake_a) > 0.001 and enemy.global_transform == origin, "实际表现根颤抖而物理原点不动")
	check(is_equal_approx(visual._materials[0].emission_energy_multiplier, 0.196875), "四分之三秒二次曲线实际材质渐亮")
	for mesh in visual._meshes:
		for index in mesh.mesh.get_surface_count():
			check(mesh.get_surface_override_material(index) in visual._materials, "渐亮材质确实绑定实际网格surface")
	if OS.get_cmdline_user_args().has("--render"):
		await capture(enemy, "warning_075.png")
	var saved := enemy.export_runtime_state()
	check(saved.ai_state == "death_warning" and is_equal_approx(saved.death_warning_remaining_sec, 0.25), "快照保留HP0待结算者剩余时间")
	enemy._process(0.24)
	check(kill_ids.is_empty() and player.damage == 0, "0.99秒仍未爆炸")
	enemy._process(0.011)
	check(enemy.ai_state == "dead" and kill_ids.count(enemy.get_persistent_id()) == 1 and player.damage == 180, "满1秒原180爆炸后恰好一次killed")
	enemy._die()
	enemy._process(1.0)
	check(player.damage == 180 and kill_ids.count(enemy.get_persistent_id()) == 1, "重复死亡调用不重复爆炸和结算")
	check(not enemy.import_runtime_state(saved), "终态不能被旧预爆快照复活")
	var zones := find_children("*", "DeathBlastZone3D", true, false)
	check(not zones.is_empty(), "原地面持续伤害场仍生成")
	player.remove_from_group("player_3d")
	player.queue_free()
	peer.queue_free()
	await get_tree().process_frame

	var restored := spawn("fat_zombie03", spec(), Vector3(30, 0, 0))
	restored.enemy_data["persistent_id"] = saved.persistent_id
	check(restored.import_runtime_state(JSON.parse_string(JSON.stringify(saved))), "JSON往返恢复预爆")
	stop_clock(restored)
	restored._process(0.1)
	check(restored.import_runtime_state(saved) and is_equal_approx(restored.export_runtime_state().death_warning_remaining_sec, 0.15), "重复恢复不重置计时")
	restored._process(0.151)
	check(restored.ai_state == "dead", "恢复只等待剩余0.25秒")
	await get_tree().process_frame

	var a := spawn("fat_zombie03", spec(), Vector3(40, 0, 0))
	var b := spawn("fat_zombie03_strong", spec(), Vector3(41, 0, 0))
	b.current_hp = 100
	await get_tree().physics_frame
	a.take_damage(100000)
	stop_clock(a)
	a._process(1.0)
	check(b.ai_state == "death_warning", "级联强化胖子进入自己的预爆")
	stop_clock(b)
	b._process(0.99)
	check(b.ai_state == "death_warning", "级联不继承上一只已耗时间")
	b._process(0.011)
	check(b.ai_state == "dead", "级联独立满1秒爆炸")
	await get_tree().process_frame
	for entry in [
		["fat_zombie03", {}], ["fat_zombie03", spec(0.0)],
		["fat_zombie03", {"enabled":false, "damage":180, "warning_sec":1.0}],
		["exploder", spec()], ["egt_mimic", spec()]]:
		var legacy := spawn(entry[0], entry[1], Vector3(60, 0, 0))
		legacy.take_damage(100000)
		check(legacy.ai_state == "dead", "缺省/禁用/非胖子不进入预爆：" + str(entry[0]))
		legacy.queue_free()
		await get_tree().process_frame
	var timed := spawn("fat_zombie03", spec(), Vector3(80, 0, 0))
	timed.take_damage(100000)
	await get_tree().create_timer(0.3).timeout
	check(timed.ai_state == "death_warning", "真实帧时钟0.3秒不提前爆炸")
	var before_pause: float = timed.export_runtime_state().death_warning_remaining_sec
	get_tree().paused = true
	await get_tree().create_timer(0.15, true).timeout
	check(is_equal_approx(timed.export_runtime_state().death_warning_remaining_sec, before_pause), "暂停不消耗预爆时间")
	get_tree().paused = false
	await get_tree().create_timer(0.9).timeout
	check(not is_instance_valid(timed), "真实帧时钟满时爆炸并回收")

func capture(enemy: Enemy3D, filename: String) -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = enemy.global_position + Vector3(4.5, 3.3, -6.0)
	camera.look_at(enemy.global_position + Vector3(0, 1.0, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 0.45
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var out := OS.get_environment("FAT_WARNING_EVIDENCE").path_join(filename)
	check(image.save_png(out) == OK, "保存真实渲染证据")
	print("FAT_WARNING_RENDER ", out)
	camera.queue_free()
	light.queue_free()

func integration() -> void:
	tower = (load(LEVEL_PATH) as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	check(not tower._expedition_bootstrap_failed and tower._room_by_id.has("room_10"), "正式关卡初始化")
	if not tower._room_by_id.has("room_10"):
		return
	tower.set_process(false)
	tower.set_physics_process(false)
	var room := tower._room_by_id["room_03"] as DungeonRoom3D
	room.ensure_shell_built()
	room.ensure_detail_built()
	var enemy := spawn("fat_zombie03", spec(), room.global_position)
	enemy.reparent(tower.get_node("ActiveEnemies"))
	enemy.room_id = room.room_id
	tower._enemy_nodes_by_room[room.room_id] = [enemy]
	tower._alive_by_room[room.room_id] = 1
	enemy.killed.connect(tower._on_enemy_killed)
	enemy.take_damage(100000)
	stop_clock(enemy)
	enemy._process(0.4)
	tower._capture_room_runtime_state(room.room_id)
	var state: Dictionary = tower._segment_runtime_state[room.room_id]
	check(state.enemies.size() == 1 and state.alive_count == 1 and not state.cleared, "正式捕获保留HP0预爆者和清房计数")
	check(is_equal_approx(state.enemies[0].death_warning_remaining_sec, 0.6), "正式房间快照剩余0.6秒")
	var save_path := OS.get_environment("FAT_WARNING_EVIDENCE").path_join("warning_room_snapshot.json")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	var disk_state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(disk_state.enemies.size() == 1 and disk_state.enemies[0].hp == 0, "预爆中的真实房间快照写盘回读不漏HP0实体")
	tower._hibernate_room_entities(room.room_id)
	await get_tree().process_frame
	check((tower._enemy_nodes_by_room[room.room_id] as Array).is_empty(), "正式流送卸载实体")
	tower._restore_room_runtime_state(room.room_id)
	var actors: Array = tower._enemy_nodes_by_room[room.room_id]
	check(actors.size() == 1, "正式流送只恢复一个预爆者")
	if actors.size() == 1:
		var actor := actors[0] as Enemy3D
		stop_clock(actor)
		check(actor.ai_state == "death_warning" and is_equal_approx(actor.export_runtime_state().death_warning_remaining_sec, 0.6), "正式流送恢复不重置1秒")
		actor._process(0.59)
		check(int(tower._alive_by_room[room.room_id]) == 1 and not room.cleared, "预爆结束前不清房")
		actor._process(0.011)
		check(actor.ai_state == "dead" and int(tower._alive_by_room[room.room_id]) == 0, "爆炸后正式清房账只减一次")
	tower.queue_free()
	await get_tree().process_frame

func frozen_lighting() -> Array:
	var result: Array = []
	for node in tower.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		result.append({"path":str(light.get_path()), "transform":str(light.global_transform),
			"visible":light.is_visible_in_tree(), "energy":light.light_energy,
			"color":str(light.light_color), "indirect":light.light_indirect_energy})
	for node in tower.find_children("*", "WorldEnvironment", true, false):
		var world := node as WorldEnvironment
		if world.environment != null:
			result.append({"environment":str(world.get_path()), "exposure":world.environment.tonemap_exposure,
				"tonemapper":world.environment.tonemap_mode, "ambient_energy":world.environment.ambient_light_energy})
	return result

func followup_visual() -> void:
	get_tree().current_scene = self
	tower = (load(LEVEL_PATH) as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	check(not tower._expedition_bootstrap_failed and tower._main_story_gameplay_started, "正式场景初始化用于同光照对照")
	if not tower._main_story_gameplay_started:
		return
	var room := tower._room_by_id["room_03"] as DungeonRoom3D
	room.ensure_shell_built()
	room.ensure_detail_built()
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	room.process_mode = Node.PROCESS_MODE_INHERIT
	var stage = tower._floor_stages.get(tower._room_floor_index.get(room.room_id, 0))
	if stage != null:
		stage.process_mode = Node.PROCESS_MODE_INHERIT
		stage.call("set_render_state", true, true)
	tower._current_room_id = room.room_id
	tower.set_process(false)
	tower.set_physics_process(false)
	var point := room.to_global(Vector3(1.3703308, 0.0, 7.3529434))
	tower.player.global_position = point + Vector3(0, 0.05, 4.0)
	tower.player.set_process(false)
	tower.player.set_physics_process(false)
	var camera := tower.player.camera
	camera.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3(0, 0.49994138, -0.8660593), Vector3(0, 0.8660593, 0.49994135)), point + Vector3(0, 10.3126593, 8.9144554))
	camera.current = true
	# 全场暂停冻结日照、灯光控制器和Tween；本探针仅手动采样预爆表现。
	process_mode = Node.PROCESS_MODE_ALWAYS
	tower.process_mode = Node.PROCESS_MODE_PAUSABLE
	GameTimeManager.set_clock_running(false)
	for node in tower.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	get_tree().paused = true
	var lighting := frozen_lighting()
	var camera_pose := camera.global_transform
	var report := {"renderer":RenderingServer.get_current_rendering_method(), "adapter":RenderingServer.get_video_adapter_name(),
		"formula":"E_added=0.35*clamp(t/T,0,1)^2", "color":[0.32,0.55,0.10], "duration_sec":1.0,
		"lighting":lighting, "camera":str(camera_pose), "camera_fov":camera.fov, "captures":[], "no_added_lights":true,
		"daylight_and_light_controllers_frozen_by_tree_pause":true}
	check(report.renderer == "forward_plus", "真实Forward+渲染器")
	for kind in ["fat_zombie03", "fat_zombie03_strong"]:
		var enemy := spawn(kind, spec(), point)
		enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
		enemy.reparent(tower.get_node("ActiveEnemies"))
		enemy.room_id = room.room_id
		enemy.rotation.y = PI
		enemy.visible = true
		enemy.take_damage(100000)
		stop_clock(enemy)
		var visual = enemy.avatar._formal_normal_root
		var origin := enemy.global_transform
		var previous := 0.0
		for t in [0.0, 0.25, 0.75, 0.95]:
			enemy._process(t - previous)
			previous = t
			var energy: float = visual._materials[0].emission_energy_multiplier
			check(is_equal_approx(energy, 0.35 * t * t), "二次能量公式：%s %.2f" % [kind,t])
			check(enemy.ai_state == "death_warning" and enemy.global_transform == origin, "保持1秒原地待结算：%s %.2f" % [kind,t])
			check(visual._materials[0].emission == Color(0.32, 0.55, 0.10), "暖绿不漂白")
			for frame in 16:
				await RenderingServer.frame_post_draw
			check(frozen_lighting() == lighting and camera.global_transform == camera_pose, "同固定光照日照及机位")
			var name := "%s_%03d.png" % [kind, int(round(t * 100.0))]
			var out := OS.get_environment("FAT_WARNING_EVIDENCE").path_join(name)
			check(get_viewport().get_texture().get_image().save_png(out) == OK, "真实渲染证据保存")
			report.captures.append({"kind":kind, "time":t, "energy":energy, "image":out,
				"lighting_equal":frozen_lighting() == lighting, "lighting_actual":frozen_lighting(),
				"camera_actual":str(camera.global_transform), "shake_position":str(visual.position)})
			print("FAT_WARNING_FOLLOWUP_CAPTURE ", name, " energy=", energy)
		enemy.queue_free()
		await get_tree().process_frame
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open(OS.get_environment("FAT_WARNING_EVIDENCE").path_join("comparison.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().paused = false
