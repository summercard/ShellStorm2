extends Node3D
## 隔离user目录后运行：真实塔楼的剧情02—05、实体/存档/运镜/收口专项。

const FIND := "nar_tower_opening_02_1_find_owner"
const BOOM := "nar_tower_opening_02_2_outside_boom"
const FOUR := "nar_tower_opening_04_stair_zombies"
const CROWD := "nar_tower_opening_05_rooftop_crowd"
const FAT := "nar_tower_opening_05_bridge_fat"
var tower: TowerDescent3D
var actor: Player3D
var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	check(bool(BaseManager.reset_game_save().get("success", false)), "隔离新档复位成功")
	GameTimeManager.set_clock_running(false)
	GameTimeManager.set_elapsed_game_seconds(0.0)
	check(str(WorldTimeDomain.get_snapshot(0.0).get("clock_text")) == "09:00", "新档世界时间从09:00开始")
	BaseManager.replace_narrative_history_for_test({})
	NarrativeDirector.reset_for_test()
	tower = (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.force_new_game_opening_for_test = true
	tower.run_seed_override = 990098
	add_child(tower)
	await frames(10)
	actor = tower.get("player") as Player3D
	NarrativeDirector.reset_for_test()
	NarrativeDirector.bind_dungeon_for_test(tower)
	disarm_all()
	actor.is_invincible = true
	for id in NarrativeCatalog.all_ids():
		check(NarrativeScript3D.load_from_id(str(id)).is_valid(), "目录剧本合法:" + str(id))
	for id in ["stair_b_entry", "stair_b_bottom", "stair_b_up", "stair_b_middle", "base_west_exit", "stair_a_bottom", "stair_a_middle", "stair_a_upper", "rooftop_stair_exit", "rooftop_bridge_approach", "rooftop_bridge_guard"]:
		var anchor: Variant = tower.narrative_anchor(id)
		check(anchor is Vector3, "正式锚点存在:" + id)
		print("ANCHOR ", id, " = ", anchor)
	test_time_compatibility()
	test_base_welcome_removed()
	await test_two()
	await test_lobby()
	await test_find()
	await test_camera_angles()
	await test_boom()
	await test_four()
	await test_five()
	await test_invalid_spawn_and_old_roof_snapshot()
	test_history()
	await test_restore()
	await test_abort()
	NarrativeDirector.reset_for_test()
	tower.queue_free()
	await seconds(3.0) # 已销毁设施的2秒点灯计时器收尾，避免退出时悬空。
	await frames(8)
	if failures.is_empty():
		print("verify_narrative_opening_02_05_OK checks=", checks)
	else:
		for failure in failures: print("FAIL ", failure)
		print("verify_narrative_opening_02_05_FAIL checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func disarm_all() -> void:
	for id in NarrativeCatalog.all_ids(): NarrativeDirector.disarm(str(id))


func room(id: String) -> DungeonRoom3D:
	return (tower.get("_room_by_id") as Dictionary).get(id) as DungeonRoom3D


func enter(id: String, point: Vector3) -> void:
	actor.global_position = point + Vector3.UP * 0.06
	actor.velocity = Vector3.ZERO
	tower.call("_on_room_entered", room(id))


func living(id: String) -> Array[Enemy3D]:
	var result: Array[Enemy3D] = []
	for node in (tower.get("_enemy_nodes_by_room") as Dictionary).get(id, []) as Array:
		if is_instance_valid(node) and node is Enemy3D and node.ai_state != "dead" and not node.is_queued_for_deletion(): result.append(node)
	return result


func group_nodes(key: String) -> Array[Enemy3D]:
	var result: Array[Enemy3D] = []
	for id in ["floor_01_main_02", "floor_01_entry", "facility", "start"]:
		for enemy in living(id):
			if enemy.get_persistent_id().begins_with(key): result.append(enemy)
	return result


func finish(timeout := 25.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while NarrativeDirector.is_playing() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not NarrativeDirector.is_playing(), "演出在期限内收口")


func test_two() -> void:
	enter("floor_01_main_02", room("floor_01_main_02").to_global(Vector3(-14, 0, 0)))
	NarrativeDirector.arm("nar_tower_opening_02_zombies")
	NarrativeDirector.evaluate_point_for_test()
	await frames(4)
	check(living("floor_01_main_02").size() == 8, "剧情02真实生成8只小僵尸")
	var stationary: Array[Enemy3D] = []
	for enemy in living("floor_01_main_02"):
		if bool(enemy.enemy_data.get("narrative_stationary", false)): stationary.append(enemy)
	check(stationary.size() == 3, "其中3只不追击")
	for enemy in stationary:
		check(body_clear(enemy.global_position), "02原地怪出生避开实体设施:" + enemy.get_persistent_id())
		check(absf(enemy.global_position.y - room("floor_01_main_02").global_position.y) < .12, "02原地怪未被设施顶离地面:" + enemy.get_persistent_id())
		print("SPAWN02 ", enemy.get_persistent_id(), " ", enemy.global_position)
	while not NarrativeDirector.is_waiting_for_flashlight(): await get_tree().process_frame
	(actor.get_node("PlayerFlashlight3D") as PlayerFlashlight3D).set_light_enabled(true)
	NarrativeDirector.complete_flashlight_wait()
	await frames(3)
	disarm_all()
	check(not actor.input_locked, "剧情02手电完成归还操作")
	for enemy in stationary:
		var initial := enemy.global_position
		actor.global_position = initial + Vector3(1.2, 0, 0)
		enemy.notify_attacked_by(actor)
		await seconds(.5)
		check(Vector2(enemy.global_position.x - initial.x, enemy.global_position.z - initial.z).length() < .15, "原地怪近身/受击不移动")
	var before := living("floor_01_main_02").size()
	NarrativeDirector.play("nar_tower_opening_02_zombies")
	await frames(4)
	check(living("floor_01_main_02").size() == before, "重播剧情02不复制任何怪")
	NarrativeDirector.skip()
	await frames(2)


func test_lobby() -> void:
	NarrativeDirector.arm("nar_tower_opening_02_lobby")
	enter("floor_01_entry", room("floor_01_entry").global_position)
	await frames(6)
	check(NarrativeDirector.active_id() == "nar_tower_opening_02_lobby", "第四房间进入事件触发台词")
	check(group_nodes("nar_tower_opening_02_lobby:police").size() == 3, "第四房间3只警察")
	check(not actor.input_locked, "第四房间台词不锁操作")
	await finish()
	disarm_all()


func test_find() -> void:
	var entry: Vector3 = tower.narrative_anchor("stair_b_entry")
	var target: Vector3 = tower.narrative_anchor("stair_b_bottom")
	enter("floor_01_entry", entry)
	NarrativeDirector.arm(FIND)
	NarrativeDirector.evaluate_point_for_test()
	await frames(5)
	check(actor.input_locked and NarrativeDirector.is_camera_override_active(), "剧情2.1独占操作与镜头")
	var start := actor.global_position
	var min_elevation := 90.0
	var moved := 0.0
	var look_min := INF
	var look_max := -INF
	var count := 0
	var walk_checked := false
	var captured := false
	var camera_blocked_samples := 0
	while NarrativeDirector.is_playing():
		var t := NarrativeDirector.active_time()
		if not camera_clear(): camera_blocked_samples += 1
		var offset := actor.camera.global_position - actor.global_position
		min_elevation = minf(min_elevation, rad_to_deg(atan2(offset.y, Vector2(offset.x, offset.z).length())))
		moved = maxf(moved, actor.global_position.distance_to(start))
		if t > 3.8 and t < 5.4:
			look_min = minf(look_min, actor.aim_yaw)
			look_max = maxf(look_max, actor.aim_yaw)
		if t > 3.5 and not walk_checked:
			walk_checked = true
			print("WALK target=", target, " actual=", actor.global_position)
			check(actor.global_position.distance_to(target) < .45, "真实步行到楼梯下方")
		if t > 6.3 and not captured:
			captured = true
			await capture("opening_02_1")
		count += 1
		await get_tree().process_frame
	print("CAMERA WALL blocked_samples=", camera_blocked_samples)
	check(camera_blocked_samples == 0, "2.1镜头全程不进入墙体/楼板")
	check(count > 100 and moved > 1.0, "步行/镜头采样非空")
	check(min_elevation < 45, "镜头真正下压到约42度")
	check(look_max - look_min > .7, "角色左右张望")
	check(not actor.input_locked and not NarrativeDirector.is_camera_override_active(), "剧情2.1结束交还操作/镜头")
	disarm_all()


func test_boom() -> void:
	var middle: Vector3 = tower.narrative_anchor("stair_b_middle")
	NarrativeDirector.arm(BOOM)
	actor.global_position = middle + Vector3.UP * 12
	NarrativeDirector.evaluate_point_for_test()
	check(not NarrativeDirector.is_playing(), "正上方另一楼层不误触发平台")
	actor.global_position = middle + Vector3.UP * .05
	NarrativeDirector.evaluate_point_for_test()
	var sfx_before := int((AudioManager.get("_feedback_request_counts") as Dictionary).get("boss_phase", 0))
	var max_shake := 0.0
	var rest := Vector2(actor.camera.h_offset, actor.camera.v_offset)
	var unlocked := true
	while NarrativeDirector.is_playing():
		unlocked = unlocked and not actor.input_locked
		max_shake = maxf(max_shake, Vector2(actor.camera.h_offset, actor.camera.v_offset).distance_to(rest))
		await get_tree().process_frame
	check(unlocked and max_shake > .025, "平台不锁操作且真实震屏")
	check(int((AudioManager.get("_feedback_request_counts") as Dictionary).get("boss_phase", 0)) > sfx_before, "轰音效实际请求")
	check(Vector2(actor.camera.h_offset, actor.camera.v_offset).distance_to(rest) < .001, "震屏偏移归还")
	disarm_all()


func test_four() -> void:
	enter("facility", tower.narrative_anchor("base_west_exit"))
	NarrativeDirector.arm(FOUR)
	NarrativeDirector.evaluate_point_for_test()
	await frames(5)
	check(group_nodes(FOUR).size() == 3, "99→100楼梯3只小僵尸")
	check(not actor.input_locked, "剧情04不锁操作")
	for enemy in group_nodes(FOUR):
		var query := PhysicsRayQueryParameters3D.create(enemy.global_position + Vector3.UP * .5, enemy.global_position + Vector3.DOWN * 1.0, 1)
		check(not get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "楼梯怪落点下方有承重")
	await finish()
	disarm_all()


func test_five() -> void:
	enter("start", tower.narrative_anchor("rooftop_stair_exit"))
	NarrativeDirector.arm(CROWD)
	NarrativeDirector.evaluate_point_for_test()
	await frames(6)
	check(group_nodes(CROWD).size() == 15, "天台第一批15只剧情怪")
	var police := 0
	var small := 0
	for enemy in group_nodes(CROWD):
		var hit := floor_hit(enemy.global_position)
		check(not hit.is_empty() and absf((hit.get("position", Vector3.INF) as Vector3).y - room("start").global_position.y) < .25, "05怪物出生在天台可行走地面:" + enemy.get_persistent_id())
		check(body_clear(enemy.global_position), "05怪物出生避开实体障碍:" + enemy.get_persistent_id())
		print("SPAWN05 ", enemy.get_persistent_id(), " ", enemy.global_position, " support=", hit.get("position"), " collider=", hit.get("collider"))
		police += 1 if enemy.enemy_kind == "ranged_caster" else 0
		small += 1 if enemy.enemy_kind == "melee_chaser" else 0
	check(police == 5 and small == 10, "天台5警察+10小僵尸")
	await finish()
	disarm_all()
	actor.global_position = tower.narrative_anchor("rooftop_bridge_approach") + Vector3.UP * .05
	# 慢速验收播放增加真实渲染采样；生产JSON的1秒停留不变。
	var original_time_scale := Engine.time_scale
	Engine.time_scale = .4 if DisplayServer.get_name() != "headless" else original_time_scale
	NarrativeDirector.arm(FAT)
	NarrativeDirector.evaluate_point_for_test()
	await frames(6)
	check(group_nodes(FAT).size() == 6, "吊桥前1胖子+5警察")
	check(actor.input_locked, "剧情05锁操作")
	var fat: Enemy3D
	for enemy in group_nodes(FAT):
		if enemy.enemy_kind == "fat_zombie03": fat = enemy
	check(fat != null, "胖子正式模型与实体存在")
	var sampled := 0
	var max_angle := 0.0
	var focus_position := Vector3.ZERO
	var focus_rest := 0.0
	var captured := false
	while NarrativeDirector.is_playing():
		var t := NarrativeDirector.active_time()
		if t > 1.4 and t < 2.2 and fat != null:
			var direction := (fat.global_position + Vector3.UP * 1.0 - actor.camera.global_position).normalized()
			max_angle = maxf(max_angle, rad_to_deg(acos(clampf((-actor.camera.global_basis.z).dot(direction), -1, 1))))
			if sampled == 0: focus_position = actor.camera.global_position
			focus_rest = maxf(focus_rest, focus_position.distance_to(actor.camera.global_position))
			sampled += 1
		if t > 1.7 and not captured:
			captured = true
			await capture("opening_05_fat")
		await get_tree().process_frame
	Engine.time_scale = original_time_scale
	print("FAT CAMERA samples=", sampled, " max_angle_deg=", max_angle, " hold_drift=", focus_rest)
	check(sampled > 20 and max_angle < 15.0, "镜头胖子在中心构图带内")
	check(focus_rest < .1, "聚焦停留段相机稳定")
	check(not actor.input_locked and not NarrativeDirector.is_camera_override_active(), "剧情05回镜解锁")
	disarm_all()


func test_history() -> void:
	check(BaseManager.has_narrative_completed(FAT), "剧情05完整收口写入长期历史")
	NarrativeDirector.reset_run_state()
	disarm_all()
	NarrativeDirector.arm(FAT)
	actor.global_position = tower.narrative_anchor("rooftop_bridge_approach")
	NarrativeDirector.evaluate_point_for_test()
	check(not NarrativeDirector.is_playing(), "本局状态重建后长期历史仍拦截重播")
	disarm_all()


func test_restore() -> void:
	var id := "floor_01_main_02"
	enter(id, room(id).global_position)
	await frames(10)
	var originals := living(id)
	check(originals.size() == 8, "恢复测试前8只样本")
	if originals.is_empty(): return
	originals[0].take_damage(99999)
	await frames(4)
	tower.call("_capture_room_runtime_state", id)
	var snap := tower.build_runtime_save_snapshot()
	check((snap.get("world_state", {}) as Dictionary).has("narrative_spawned_keys"), "幂等键进入真实世界快照")
	var expected := living(id).size()
	var states: Dictionary = tower.get("_segment_runtime_state")
	for value in (states[id] as Dictionary).get("enemies", []):
		var saved := value as Dictionary
		var data := saved.get("enemy_data", {}) as Dictionary
		if bool(data.get("narrative_stationary", false)):
			data.erase("narrative_placement") # 修复前旧快照没有此字段。
			var invalid := room(id).to_global(Vector3(8.5, .7, -5))
			saved["position"] = [invalid.x, invalid.y, invalid.z]
			saved["hp"] = 7
	var nodes: Dictionary = tower.get("_enemy_nodes_by_room")
	for enemy in living(id): enemy.queue_free()
	nodes[id] = []
	await frames(4)
	tower.call("_restore_room_runtime_state", id)
	check(living(id).size() == expected and expected == 7, "和平区存活剧情怪恢复；死怪不恢复")
	var stationary := 0
	for enemy in living(id):
		check(bool(enemy.get_meta("narrative_spawned", false)), "恢复实体保留剧情归属")
		stationary += 1 if bool(enemy.enemy_data.get("narrative_stationary", false)) else 0
		if bool(enemy.enemy_data.get("narrative_stationary", false)):
			check(body_clear(enemy.global_position) and absf(enemy.global_position.y - room(id).global_position.y) < .12, "02旧档卡设施的原地怪修复落点")
			check(enemy.current_hp == 7, "修复旧档落点保留血量")
	check(stationary == 3, "恢复后原地怪策略保留")
	tower.call("_restore_narrative_spawned_keys", snap)
	NarrativeDirector.play("nar_tower_opening_02_zombies")
	await frames(5)
	check(living(id).size() == expected, "读档重播不补刷已击杀怪")
	NarrativeDirector.skip()
	await frames(2)


func test_abort() -> void:
	enter("floor_01_entry", tower.narrative_anchor("stair_b_entry"))
	NarrativeDirector.play(FIND)
	await seconds(1.8)
	check(actor.input_locked and float(actor.get("_narrative_walk_remaining")) > 0, "中断时正在真实步行")
	NarrativeDirector.abort("verification_walk")
	check(not actor.input_locked and float(actor.get("_narrative_walk_remaining")) == 0 and not NarrativeDirector.is_camera_override_active(), "中断归还行走/操作/镜头")


func capture(label: String) -> void:
	var output := OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	if DisplayServer.get_name() == "headless" or output.is_empty(): return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(output.path_join(label + ".png"))


func frames(count: int) -> void:
	for i in count: await get_tree().process_frame


func seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func check(ok: bool, label: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func floor_hit(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .3, point + Vector3.DOWN * .8, 1)
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func body_clear(point: Vector3) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(.8, 1.6, .8)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .88)
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


func camera_clear() -> bool:
	return camera_clear_at(actor.camera.global_position)


func camera_clear_at(point: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = .18
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1 | GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


func test_time_compatibility() -> void:
	var fresh := BaseData.new()
	var roundtrip := BaseData.from_dict(fresh._to_dict())
	check(WorldTimeDomain.get_snapshot(0, roundtrip.world_time_start_unix_seconds)["clock_text"] == "09:00", "新档起点经序列化仍为09:00")
	var legacy := BaseData.from_dict({"world_time_elapsed_game_seconds": 3600.0, "base_energy_last_synced_game_seconds": 3600.0})
	check(WorldTimeDomain.get_snapshot(legacy.world_time_elapsed_game_seconds, legacy.world_time_start_unix_seconds)["clock_text"] == "18:00", "旧档保留17:00起点和累计时间")
	check(legacy.base_energy_last_synced_game_seconds == 3600.0, "旧档能源时间基线不迁移")
	var legacy_roundtrip := BaseData.from_dict(legacy._to_dict())
	check(legacy_roundtrip.world_time_start_unix_seconds == WorldTimeDomain.LEGACY_START_UNIX_SECONDS, "旧档重存仍使用原起点")
	var old_data := BaseManager.data
	BaseManager.data = fresh
	var clock := GameTimeManager.get_persistence_snapshot()
	GameTimeManager.set_elapsed_game_seconds(0.0)
	check(GameTimeManager.get_time_snapshot()["clock_text"] == "09:00", "正式权威时钟读取新档09:00")
	BaseManager.data = old_data
	GameTimeManager.restore_from_persistence(clock)


func test_base_welcome_removed() -> void:
	for side in ["west", "east"]:
		var door := room("facility").get_door_node(side)
		var run_before := DialogueUI.current_run_id()
		if door != null: door.motion_finished.emit(false)
		check(DialogueUI.current_run_id() == run_before, "基地门关闭不产生系统对话:" + side)
		check(door != null and not door.motion_finished.is_connected(Callable(tower, "_on_facility_door_motion_finished")), "基地门关闭不再连接欢迎播报:" + side)


func test_camera_angles() -> void:
	var blocked_requests := 0
	var samples := 0
	for anchor in ["stair_b_entry", "stair_b_bottom"]:
		var point: Vector3 = tower.narrative_anchor(anchor)
		actor.global_position = point + Vector3.UP * .05
		await frames(2)
		for yaw in [-180.0, -135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0]:
			var offset := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, sin(deg_to_rad(42.0)) * 8.0, cos(deg_to_rad(42.0)) * 8.0)
			var desired := Transform3D(Basis.IDENTITY, actor.global_position + offset).looking_at(actor.global_position + Vector3.UP * .9)
			var safe := tower.constrain_narrative_camera_pose(desired, actor.global_position)
			if safe.origin.distance_to(desired.origin) > .05: blocked_requests += 1
			check(camera_clear_at(safe.origin), "楼梯镜头候选避墙:" + anchor + ":" + str(yaw))
			samples += 1
	print("CAMERA ANGLES samples=", samples, " blocked_requests=", blocked_requests)
	check(samples == 16 and blocked_requests > 0, "真实楼梯多角度碰撞样本非空")



func test_invalid_spawn_and_old_roof_snapshot() -> void:
	var id := "start"
	var invalid := room(id).to_global(Vector3(0, 0, -6))
	var before := living(id).size()
	var key := "verification:invalid_roof_point"
	var count := tower.narrative_spawn_enemies(id, "melee_chaser", 1, invalid, Vector3.RIGHT, 1.6, Vector3.ZERO, {"spawn_key": key, "placement": "room_floor", "max_adjustment_m": 0.0})
	check(count == 0 and living(id).size() == before, "天台孔洞落点拒绝且不生成半批")
	check(not (tower.get("_narrative_spawned_keys") as Dictionary).has(key), "失败落点不写一次性生成键")
	tower.call("_capture_room_runtime_state", id)
	var states: Dictionary = tower.get("_segment_runtime_state")
	var victim_id := ""
	for value in (states[id] as Dictionary).get("enemies", []):
		var saved := value as Dictionary
		if str(saved.get("persistent_id", "")).begins_with(CROWD):
			victim_id = str(saved["persistent_id"])
			(saved["enemy_data"] as Dictionary).erase("narrative_placement")
			saved["position"] = [invalid.x, -12.0, invalid.z]
			saved["hp"] = 7
			break
	check(not victim_id.is_empty(), "旧天台错误快照样本存在")
	tower.call("_restore_room_runtime_state", id)
	for enemy in living(id):
		if enemy.get_persistent_id() == victim_id:
			check(absf(enemy.global_position.y - room(id).global_position.y) < .12 and body_clear(enemy.global_position), "旧档误落基地的天台剧情怪回到安全天台")
			check(enemy.current_hp == 7, "旧天台落点修复保留血量和持久ID")
	check(living(id).size() == before, "修复旧天台快照不补刷或复制怪物")
