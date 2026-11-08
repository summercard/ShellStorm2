extends "res://tests/verification/verify_second_elite_state_visual.gd"

const REAL_DUNGEON_SCENE := preload("res://scenes/ExpeditionLevel03_3D.tscn")
const ROAMING_DIRECTOR := preload("res://src/enemy3d/RoamingEliteRunDirector.gd")
const ARMS_TAKER_ID := "elite_arms_taker"

var _room_by_id: Dictionary = {}
var observations: Dictionary = {}
var representative_frames: Array[String] = []
var not_executed: Array[String] = []
var renderer_available := false
var spawned_projectiles := 0
var confirmed_player_hits := 0
var shots_by_slot: Dictionary = {}
var escaped_events: Array = []

func _ready() -> void:
	output = OS.get_environment("ELITE_QA_DIR")
	if output.is_empty() or output.begins_with("res://") or not output.is_absolute_path():
		push_error("ARMS_TAKER_REVISION_OUTPUT_REQUIRED：必须由 workspace_paths.py 提供工程外绝对路径")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	if BaseManager != null:
		BaseManager.save_path = "user://arms_taker_revision_visual.json"
		BaseManager.data = BaseData.new()
		BaseManager.force_save_failure_for_test = false
	if EliteRosterService != null and EliteRosterService.has_method("reset_roster_for_test"):
		EliteRosterService.reset_roster_for_test()
	renderer_available = DisplayServer.get_name() != "headless"
	if not renderer_available:
		not_executed.append("无头运行：全部真实渲染与 PNG 视觉验收未执行")
	setup_ground()
	setup_visual_stage()
	await get_tree().physics_frame
	if "--defeat-only" not in OS.get_cmdline_user_args():
		await verify_revision_guns()
		await verify_revision_healing()
		await verify_revision_transfer()
		await verify_revision_kneel()
		await verify_revision_escape()
	await verify_revision_real_defeat_transaction()
	clean_effects()
	await get_tree().process_frame
	write_revision_report("finished")
	print("ARMS_TAKER_REVISION_%s checks=%d failures=%d display=%s gpu=%s" % ["VISUAL_DONE" if renderer_available else "HEADLESS_DONE", checks, failures.size(), DisplayServer.get_name(), RenderingServer.get_video_adapter_name()])
	finish("ARMS_TAKER_REVISION_VISUAL_OK" if renderer_available else "ARMS_TAKER_REVISION_LOGIC_OK")

func revision_camera(center: Vector3, size_value := 7.5) -> void:
	camera.size = size_value
	camera.position = center + Vector3(6, 4.5, -8)
	camera.look_at(center + Vector3.UP * 1.2)
	camera.make_current()

func capture_revision(stage: String, detail: String) -> void:
	label.text = "收租人真实链路 QA / %s\n%s" % [stage, detail]
	if renderer_available:
		await RenderingServer.frame_post_draw
		var path := output + "/" + stage + ".png"
		var image := get_viewport().get_texture().get_image()
		check(image != null and not image.is_empty(), "代表帧为空：" + stage)
		if image != null and not image.is_empty():
			check(image.save_png(path) == OK, "代表帧保存失败：" + stage)
			representative_frames.append(path)
	write_revision_report(stage)

func write_revision_report(stage: String) -> void:
	var report := {"stage":stage, "gpu":RenderingServer.get_video_adapter_name(),
		"display_server":DisplayServer.get_name(), "rendering_method":RenderingServer.get_current_rendering_method(),
		"visual_executed":renderer_available, "checks":checks, "failures":failures,
		"not_executed":not_executed, "representative_frames":representative_frames,
		"observations":observations, "user_data_dir":OS.get_user_data_dir()}
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	else:
		check(false, "无法写出专项报告")

func revision_player(at: Vector3) -> Player3D:
	var player := preload("res://scenes/Player3D.tscn").instantiate() as Player3D
	player.start_with_weapon = false
	player.position = at
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.camera.current = false
	player.aim_cursor.hide()
	camera.make_current()
	return player

func enable_revision_visual(enemy: Enemy3D) -> void:
	enemy.avatar.set_process(true)
	enemy.avatar._formal_elite_root.set_process(true)
	enemy.set_process(true)

func verify_revision_guns() -> void:
	var enemy := make_enemy(true)
	var player := revision_player(Vector3(0, 0.05, -5))
	revision_camera(Vector3(0, 0, -2), 8.0)
	enable_revision_visual(enemy)
	await get_tree().process_frame
	var controller := enemy.elite_equipment
	check(controller != null, "正式 Enemy3D 未创建 EliteArmsTakerEquipment")
	var weapon_nodes: Array[WeaponModel3D] = []
	for node in enemy.find_children("ArmsTakerStolenWeapon*", "Node3D", true, false):
		if node is WeaponModel3D:
			weapon_nodes.append(node)
	check(weapon_nodes.size() == 2, "没有两把真实 WeaponModel3D")
	for index in weapon_nodes.size():
		var weapon := weapon_nodes[index]
		check(weapon.get_parent().name in ["WeaponMountLeft", "WeaponMountRight"], "枪械没有挂在正式悬浮挂点")
		check(weapon.is_visible_in_tree() and weapon.find_children("*", "MeshInstance3D", true, false).size() > 0, "枪械缺少真实可见网格")
		weapon.projectile_spawned.connect(_on_revision_projectile.bind(index, player))
	var hp_before := player.current_hp
	bind_target(enemy, player)
	enemy.transition_to("chase")
	enemy._attack_timer = 100.0
	enemy.set_physics_process(true)
	for frame in 100:
		await get_tree().physics_frame
		if frame == 3:
			await capture_revision("01_formal_dual_guns", "正式模型、双悬浮枪与控制器实际开火")
		if confirmed_player_hits > 0:
			break
	enemy.set_physics_process(false)
	check(spawned_projectiles >= 2 and shots_by_slot.size() == 2, "双枪控制器没有分别生成真实 Projectile3D")
	check(confirmed_player_hits > 0 and player.current_hp < hp_before, "真实 Projectile3D 未命中真实 Player3D 并扣血")
	observations["guns"] = {"controller":controller.get_presentation_snapshot() if controller != null else {},
		"projectiles":spawned_projectiles, "shots_by_slot":shots_by_slot, "confirmed_player_hits":confirmed_player_hits,
		"hp_before":hp_before, "hp_after":player.current_hp, "actual_damage":hp_before-player.current_hp,
		"actual_state":enemy.ai_state}
	await capture_revision("02_projectile_hit_player", "子弹命中事件 %d，玩家 HP %d → %d" % [confirmed_player_hits, hp_before, player.current_hp])
	enemy.queue_free()
	player.queue_free()
	clean_effects()
	await get_tree().process_frame

func _on_revision_projectile(projectile: Projectile3D, slot: int, player: Player3D) -> void:
	if not is_instance_valid(projectile):
		check(false, "正式枪械发出空 projectile_spawned，真实子弹创建失败")
		return
	spawned_projectiles += 1
	shots_by_slot[str(slot)] = int(shots_by_slot.get(str(slot), 0)) + 1
	check(projectile.hostile and projectile.target_group == "player_3d", "真实枪弹阵营配置错误")
	projectile.hit_confirmed.connect(func(target: Node, _damage: int, _critical: bool):
		if target == player:
			confirmed_player_hits += 1)

func live_heal_labels() -> Array[Label3D]:
	var result: Array[Label3D] = []
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if node is VfxHealNumber3D and node._active:
			var heal_label := node.get_node_or_null("HealLabel") as Label3D
			if heal_label != null:
				result.append(heal_label)
	return result

func verify_revision_healing() -> void:
	var player := revision_player(Vector3(-1.5, 0.05, 0))
	var enemy := make_enemy()
	enemy.position.x = 1.5
	enable_revision_visual(enemy)
	revision_camera(Vector3.ZERO, 6.8)
	for kind in ["player", "elite"]:
		clean_effects()
		await get_tree().process_frame
		var before := 0
		var after := 0
		if kind == "player":
			player.current_hp = player.max_hp - 7
			before = player.current_hp
			player.heal(23)
			after = player.current_hp
		else:
			enemy.current_hp = enemy.max_hp - 7
			before = enemy.current_hp
			enemy.receive_healing(23)
			after = enemy.current_hp
		await get_tree().create_timer(0.14).timeout
		var texts: Array[String] = []
		var green := false
		for heal_label in live_heal_labels():
			texts.append(heal_label.text)
			green = green or (heal_label.modulate.is_equal_approx(Color(0.4, 1.0, 0.55, 1.0)) and heal_label.transparency < 0.1)
		check(after-before == 7, kind + "治疗实际恢复值没有受最大 HP 截断")
		check(texts.has("+7") and green, kind + "治疗未显示绿色实际恢复值 +7（实际飘字 %s）" % str(texts))
		observations[kind+"_healing"] = {"requested":23, "hp_before":before, "hp_after":after, "actual_recovery":after-before, "labels":texts, "green_visible":green}
		await capture_revision("03_"+kind+"_healing", "%s HP %d → %d；实际飘字 %s" % [kind, before, after, str(texts)])
	enemy.queue_free()
	player.queue_free()
	clean_effects()
	await get_tree().process_frame

func verify_revision_transfer() -> void:
	var enemy := make_enemy(true)
	enemy.position.x = 2.5
	enable_revision_visual(enemy)
	var player := revision_player(Vector3(-2.5, 0.05, 0))
	revision_camera(Vector3.ZERO, 7.8)
	var transfer := EliteRentTransfer3D.new()
	add_child(transfer)
	transfer.configure(ItemRegistry.get_instance().get_item("weapon_pistol"), player.global_position+Vector3.UP*0.8, enemy.global_position+Vector3.UP*1.2)
	var reference: WeakRef = weakref(transfer)
	transfer.begin()
	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(transfer):
		var trail := transfer.get_node_or_null("PrivateRentTransferTrail") as EliteRentTransferTrail3D
		var item := transfer.get_node_or_null("TransferredItemModel") as Node3D
		var visible_segments := 0
		var trail_span := 0.0
		if trail != null:
			for segment in trail._segments:
				if segment.is_visible_in_tree():
					visible_segments += 1
			if trail._points.size() > 1:
				trail_span = trail._points[0].distance_to(trail._points[-1])
		check(item != null and item.is_visible_in_tree(), "收租飞行没有真实物品模型")
		check(visible_segments == 8 and trail_span > 0.05, "收租真实拖尾没有形成空间跨度")
		check(not transfer.is_in_group("ground_loot_3d"), "视觉转移污染了地面拾取事务")
		observations["rent_transfer"] = {"snapshot":transfer.get_visual_snapshot(), "phase":transfer._phase, "visible_segments":visible_segments, "trail_span_m":trail_span}
		await capture_revision("04_rent_item_flight_trail", "真实物品飞行阶段 %d，私有拖尾 %d 段，跨度 %.3f m" % [transfer._phase, visible_segments, trail_span])
	else:
		check(false, "收租视觉实体提前释放，未能采样飞行")
	await get_tree().create_timer(0.85).timeout
	check(reference.get_ref() == null, "收租转移视觉结束后未回收")
	enemy.queue_free()
	player.queue_free()
	await get_tree().process_frame

func verify_revision_kneel() -> void:
	var enemy := make_enemy()
	enable_revision_visual(enemy)
	revision_camera(Vector3.ZERO, 5.8)
	var hip_before := hip_position(enemy)
	enemy.take_damage(ceili(enemy.max_hp * 0.81))
	check(enemy._elite_defeat_active, "真实伤害没有触发收租人战败")
	# 只推进正式场景回调，不向视觉层注入动作或伪造结算返回值。
	enemy.set_physics_process(true)
	await get_tree().create_timer(1.8).timeout
	if is_instance_valid(enemy):
		var visual: Dictionary = enemy.avatar._formal_elite_root.get_presentation_snapshot()
		var kneel_active := bool(enemy.avatar._formal_elite_root.get("_defeat_kneel_active"))
		var hip_drop := hip_before.y - hip_position(enemy).y
		observations["kneel"] = {"actual_state":enemy.ai_state, "defeat_active":enemy._elite_defeat_active, "visual":visual, "kneel_pose_active":kneel_active, "hip_drop_m":hip_drop, "defeat_committed":enemy._elite_defeat_committed}
		check(kneel_active, "战败没有激活正式 kneel 姿态")
		check(str(visual.get("clip", "")) in ["kneel", "defeat_kneel"], "战败 kneel 动画片段回退（clip=%s）" % str(visual.get("clip", "")))
		await capture_revision("05_defeat_kneel", "state=%s clip=%s kneel=%s hip_drop=%.3f m" % [enemy.ai_state, str(visual.get("clip", "")), str(kneel_active), hip_drop])
		enemy.queue_free()
	else:
		check(false, "kneel 正式动画采样前已释放")
	# 正式 Dungeon3D 事务、失败重试与自然释放由后续真实关卡阶段覆盖。
	clean_effects()
	await get_tree().process_frame

func verify_revision_escape() -> void:
	var room := DungeonRoom3D.new()
	room.room_id = "revision_escape_room"
	add_child(room)
	room.connection_ports = [{"port_id":"revision_north", "target_room_id":"revision_peer", "position_m":[0.0,-5.0], "outward":[0.0,-1.0]}]
	_room_by_id[room.room_id] = room
	var door := RoomDoor3D.new()
	room.add_child(door)
	door.configure("north", "revision_peer", Color(0.3,0.5,0.6))
	door.position = Vector3(0,0,-5)
	var enemy := make_enemy()
	enemy.room_id = room.room_id
	var encounter_id := "revision_escape_%d" % Time.get_ticks_usec()
	var reserved := EliteRosterService.reserve("elite_arms_taker", encounter_id, 1)
	check(reserved and EliteRosterService.confirm_reservation("elite_arms_taker", encounter_id), "撤退测试真实档案预约失败")
	enemy.elite_encounter_instance_id = encounter_id
	enable_revision_visual(enemy)
	revision_camera(Vector3(0,0,-2.5), 8.5)
	camera.position = Vector3(6, 4.5, 3.0)
	camera.look_at(Vector3(0, 1.2, -3.0))
	enemy.escaped.connect(func(_actor: Enemy3D, context: Dictionary): escaped_events.append(context.duplicate(true)))
	var reference: WeakRef = weakref(enemy)
	var start := enemy.global_position
	enemy.take_damage(ceili(enemy.max_hp * 0.1))
	check(enemy._elite_escape_active and enemy._elite_escape_target_valid, "伤害阈值撤退未解析真实房间门端口")
	enemy.set_physics_process(true)
	var vfx_seen := false
	var vfx_retired := false
	var arrived := false
	var door_distance := INF
	for frame in 300:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		arrived = arrived or enemy._elite_escape_arrived
		vfx_retired = vfx_retired or enemy._elite_escape_vfx_finished
		if enemy._elite_escape_arrived and not vfx_seen and is_instance_valid(enemy._elite_escape_vfx):
			vfx_seen = true
			door_distance = enemy.global_position.distance_to(enemy._elite_escape_door_position)
			observations["escape_at_door"] = {"actual_state":enemy.ai_state, "position":str(enemy.global_position), "target":str(enemy._elite_escape_door_position), "distance_to_target_m":door_distance, "travelled_m":start.distance_to(enemy.global_position), "vfx_active":enemy._elite_escape_vfx._active}
			enemy._elite_escape_vfx.retired.connect(func(_effect: VfxEffectBase3D): observations["teleport_retired_signal"] = true)
			await get_tree().create_timer(0.18).timeout
			await capture_revision("06_door_teleport_out", "真实门口抵达，正式 teleport-out VFX")
	check(arrived and vfx_seen and door_distance <= 1.01, "未抵达门边并播放真实 teleport-out")
	check(bool(observations.get("teleport_retired_signal", false)) or vfx_retired, "teleport-out 未自然完成")
	check(reference.get_ref() == null and escaped_events.size() == 1, "teleport-out 后未成功结算并释放")
	var record := EliteRosterService.get_record("elite_arms_taker")
	check(record.get("last_outcome", "") == "escaped" and str(record.get("reserved_encounter_id", "")).is_empty(), "撤退档案没有真实结算或释放预约")
	observations["escape_finished"] = {"arrived":arrived, "vfx_seen":vfx_seen, "actor_freed":reference.get_ref()==null, "escaped_events":escaped_events, "archive_last_outcome":record.get("last_outcome", ""), "reservation":record.get("reserved_encounter_id", "")}
	await capture_revision("07_teleport_finished", "结束后 actor_freed=%s escaped_events=%d" % [str(reference.get_ref()==null), escaped_events.size()])
	if is_instance_valid(enemy):
		enemy.queue_free()
	room.queue_free()
	_room_by_id.clear()
	await get_tree().process_frame


func transaction_pickups(marker: String) -> Array[GroundLootPickup3D]:
	var result: Array[GroundLootPickup3D] = []
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and not value.is_queued_for_deletion() and str(value.item_data.get("custom_marker", "")) == marker:
			result.append(value as GroundLootPickup3D)
	return result


func transaction_saved_items(checkpoint: Dictionary, room_id: String, marker: String) -> Array:
	var world := checkpoint.get("world_state", {}) as Dictionary
	var segments := world.get("segment_runtime_state", {}) as Dictionary
	var result: Array = []
	for entry: Dictionary in (segments.get(room_id, {}) as Dictionary).get("ground_items", []):
		var item := entry.get("item_data", {}) as Dictionary
		if str(item.get("custom_marker", "")) == marker:
			result.append(item.duplicate(true))
	return result


func wait_transaction_until(predicate: Callable, timeout_seconds := 60.0) -> bool:
	var started := Time.get_ticks_msec()
	while true:
		if bool(predicate.call()):
			return true
		if float(Time.get_ticks_msec() - started) >= timeout_seconds * 1000.0:
			return false
		await get_tree().physics_frame
	return false


func transaction_storage_equal(left: Variant, right: Variant) -> bool:
	# 复用正式存档语义：JSON 读盘将整数恢复成 float，不应误报为字段丢失。
	return preload("res://src/base/ProfileSaveService.gd").checksum_payload({"value": left}) == preload("res://src/base/ProfileSaveService.gd").checksum_payload({"value": right})


func transaction_inventory(marker: String, counts: Array) -> Array:
	var result: Array = []
	for index in counts.size():
		var item := ItemRegistry.get_instance().get_item("weapon_pistol" if int(counts[index]) == 1 else "item_ammo_pack").duplicate(true)
		item["custom_marker"] = marker
		item["qa_entry_index"] = index
		if str(item.get("type", "")) == "weapon":
			item["weapon_instance_id"] = "%s:weapon:%d" % [marker, index]
			item["current_ammo"] = 3 + index
			item["durability"] = 41 + index
			item["attachments"] = {"probe": index}
			item = WeaponInstance.ensure_weapon_item(item)
		result.append({"item": item, "count": int(counts[index]), "receipt_id": "%s:receipt:%d" % [marker, index]})
	return result


func verify_revision_real_defeat_transaction() -> void:
	print("ARMS_TAKER_REAL_DEFEAT_BEGIN")
	var previous_scene := get_tree().current_scene
	# 摄影棚只退掉地面/环境，不替代关卡内的真实房间、掉落与自然回调。
	for child in get_children():
		if child is MeshInstance3D or child is Light3D:
			(child as Node3D).hide()
		elif child is WorldEnvironment:
			(child as WorldEnvironment).environment = null
		elif child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 0
	var dungeon := REAL_DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 20261108
	var generated: Array = []
	dungeon.generation_completed.connect(func(snapshot: Dictionary): generated.append(snapshot.duplicate(true)))
	get_tree().root.add_child.call_deferred(dungeon)
	var initialized := await wait_transaction_until(func(): return not generated.is_empty() and is_instance_valid(dungeon.player), 45.0)
	check(initialized and generated.size() == 1, "真实 Dungeon 初始化未完成或重复完成")
	if not initialized:
		dungeon.queue_free()
		return
	get_tree().current_scene = dungeon
	dungeon.set_process(false)
	dungeon.player.set_input_locked(true)
	dungeon.player.set_combat_enabled(false)
	dungeon.player.set_physics_process(false)
	dungeon.player.set_process(false)
	# 本阶段是事务观察机位：玩家远离掉落避免自动拾取，只停视野裁剪，
	# 不停敌人/掉落自然回调，也不改正式模型、碰撞、房间与保存入口。
	(dungeon.player.get_node("PlayerVision3D") as PlayerVision3D).set_process(false)
	observations["transaction_environment"] = {"spectator_vision_suspended": true, "real_dungeon_current_scene": true, "natural_enemy_and_pickup_processing": true}
	dungeon.player.camera.current = false
	dungeon.player.aim_cursor.hide()
	(dungeon.get_node("HUD") as CanvasLayer).hide()
	for config in dungeon._map_fate_triggers._triggers:
		config.enabled = false
	var room := dungeon._room_by_id.get("start") as DungeonRoom3D
	check(room != null and room.is_streamed() and dungeon._current_room_id == "start", "真实入口房未流送激活")
	check(bool(dungeon.build_runtime_save_snapshot().get("valid", false)), "真实战败宿主没有有效 runtime snapshot")
	if room != null:
		await verify_real_defeat_case(dungeon, room, "success", [1, 1, 1, 1, 1], false)
		await verify_real_defeat_case(dungeon, room, "rollback_retry", [1, 1, 1, 1, 1], true)
		await verify_real_defeat_case(dungeon, room, "stacked", [2, 3], false)
		await verify_real_defeat_case(dungeon, room, "single", [1], false)
	BaseManager.force_save_failure_for_test = false
	get_tree().current_scene = previous_scene
	BaseManager.unregister_runtime_checkpoint_provider(dungeon, false)
	dungeon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("ARMS_TAKER_REAL_DEFEAT_END")


func verify_real_defeat_case(dungeon: Dungeon3D, room: DungeonRoom3D, case_id: String, counts: Array, fail_first: bool) -> void:
	var marker := "real_defeat_" + case_id
	# 一房预算令 director 自然形成 pending；仍由正式预约/注入器/batch 完成生成。
	dungeon._run_id += ":" + case_id
	dungeon._roaming_elite = ROAMING_DIRECTOR.new()
	dungeon._roaming_elite.configure({"enabled": true, "elite_id": ARMS_TAKER_ID, "room_types": [room.room_type]}, dungeon.run_seed, dungeon._run_id, 1)
	dungeon._roaming_elite.observe_room(room.room_id)
	dungeon._retry_roaming_elite()
	var enemy: Enemy3D
	for value in dungeon._enemy_nodes_by_room.get(room.room_id, []):
		if is_instance_valid(value) and value is Enemy3D and dungeon._roaming_elite.owns(value.enemy_data):
			enemy = value as Enemy3D
	check(enemy != null, marker + "：真实收租人生成失败")
	if enemy == null:
		return
	check(enemy.elite_encounter_instance_id == str(dungeon._roaming_elite.state.session_id) and bool(EliteRosterService.get_record(ARMS_TAKER_ID).get("reservation_confirmed", false)), marker + "：真实预约没有确认")
	check(enemy.is_physics_processing() and PhysicsServer3D.body_get_space(enemy.get_rid()).is_valid(), marker + "：没有自然物理回调或有效 space")
	enemy.show()
	# 在精英之后添加真实成员，抓出失败回滚用 append 导致的顺序变更。
	var sentinel_data := dungeon._monster_injector.generate_box_enemy("melee_chaser", 1, 0)
	sentinel_data["persistent_id"] = marker + ":sentinel"
	var sentinel_configs: Array[Dictionary] = [sentinel_data]
	check(dungeon._spawn_enemy_batch(room, sentinel_configs, true) == 1, marker + "：真实成员顺序 fixture 生成失败")
	var sentinel: Enemy3D
	for value in dungeon._enemy_nodes_by_room.get(room.room_id, []):
		if is_instance_valid(value) and value is Enemy3D and value.get_persistent_id() == marker + ":sentinel":
			sentinel = value as Enemy3D
			sentinel.set_physics_process(false)
			sentinel.set_process(false)
			sentinel.hide()
			# 该真实成员只用于数组顺序回滚，避免全局可见性刷新将其带入代表帧。
			for geometry in sentinel.find_children("*", "GeometryInstance3D", true, false):
				(geometry as GeometryInstance3D).layers = 0
	var inventory := transaction_inventory(marker, counts)
	var record := BaseManager.get_elite_archive_record(ARMS_TAKER_ID)
	record["stolen_items"] = inventory.duplicate(true)
	check(BaseManager.commit_elite_archive_record(ARMS_TAKER_ID, record, marker + ":fixture"), marker + "：库存 fixture 写盘失败")
	# 玩家远离落点，禁止掉落验收时自动吸取；不关闭真实掉落自己的处理。
	dungeon.player.global_position = room.global_position + Vector3(-5.5, 0.05, -5.5)
	revision_camera(enemy.global_position, 7.0)
	# 从房间正上方看真实落点，避免贴墙出生被前景墙/家具完全挡住。
	camera.position = enemy.global_position + Vector3(0, 18, 0)
	camera.look_at(enemy.global_position, Vector3.FORWARD)
	var events := {"defeated": [], "killed": 0, "escaped": 0, "settled": []}
	enemy.defeated.connect(func(actor: Enemy3D, context: Dictionary): (events["defeated"] as Array).append({"state": actor.ai_state, "context": context.duplicate(true)}))
	enemy.killed.connect(func(_actor: Enemy3D, _loot: Dictionary): events["killed"] = int(events["killed"]) + 1)
	enemy.escaped.connect(func(_actor: Enemy3D, _context: Dictionary): events["escaped"] = int(events["escaped"]) + 1)
	var on_settled := func(elite_id: String, outcome: String, settled_record: Dictionary):
		if elite_id == ARMS_TAKER_ID:
			(events["settled"] as Array).append({"outcome": outcome, "record": settled_record.duplicate(true)})
	EliteRosterService.elite_settled.connect(on_settled)
	var reference: WeakRef = weakref(enemy)
	var persistent_id := enemy.get_persistent_id()
	var kills_before := dungeon._kills
	var alive_before := int(dungeon._alive_by_room.get(room.room_id, 0))
	var cleared_before := room.cleared
	var defeat_count_before := int(EliteRosterService.get_record(ARMS_TAKER_ID).get("defeat_count", 0))
	BaseManager.force_save_failure_for_test = fail_first
	enemy.take_damage(ceili(enemy.max_hp * 0.81))
	check(enemy._elite_defeat_active and enemy.ai_state != "dead" and not enemy._elite_escape_active, marker + "：真实伤害未优先触发战败")
	# take_damage 的 health_changed 会正常同步 journal；以伤害之后的实际状态为回滚基线。
	var archive_before := EliteRosterService.get_record(ARMS_TAKER_ID)
	var checkpoint_before := BaseManager.get_active_run_checkpoint()
	var journal_before := dungeon._roaming_elite.export_snapshot()
	var runtime_before := dungeon._segment_runtime_state.duplicate(true)
	var members_before := (dungeon._enemy_nodes_by_room.get(room.room_id, []) as Array).duplicate()
	var revision_before := BaseManager.data.save_revision
	var failed_elapsed := 0.0
	if fail_first:
		var kneel_duration := float(enemy._elite_growth_profile.get("kneel_duration", 2.6))
		var waited := await wait_transaction_until(func(): return not is_instance_valid(enemy) or enemy._elite_defeat_elapsed >= kneel_duration + 0.35)
		check(waited and is_instance_valid(enemy), marker + "：保存失败超过跪地时长后实体没有留场")
		if is_instance_valid(enemy):
			failed_elapsed = enemy._elite_defeat_elapsed
			check(not enemy._elite_defeat_committed and enemy._elite_defeat_active, marker + "：失败被标为已提交")
		check(EliteRosterService.get_record(ARMS_TAKER_ID) == archive_before and BaseManager.get_active_run_checkpoint() == checkpoint_before and BaseManager.data.save_revision == revision_before, marker + "：失败改变档案/checkpoint/revision")
		check(dungeon._roaming_elite.export_snapshot() == journal_before and dungeon._segment_runtime_state == runtime_before, marker + "：失败没有完整恢复 journal/runtime cache")
		check((dungeon._enemy_nodes_by_room.get(room.room_id, []) as Array) == members_before and int(dungeon._alive_by_room.get(room.room_id, 0)) == alive_before, marker + "：失败没有恢复成员原顺序/alive")
		check(transaction_pickups(marker).is_empty() and (events["settled"] as Array).is_empty() and (events["defeated"] as Array).is_empty(), marker + "：失败留下掉落或终态事件")
		await capture_revision("08_transaction_rollback_kneel", "真实保存失败 %.2fs，仍跪地；库存、成员原序、journal、checkpoint 均回滚" % failed_elapsed)
	BaseManager.force_save_failure_for_test = false
	var committed := await wait_transaction_until(func(): return dungeon._arms_taker_defeat_commits.has(persistent_id))
	check(committed, marker + "：故障解除后自然回调未提交")
	print("ARMS_TAKER_COMMIT_OBSERVATION %s expected=%s keys=%s live_id=%s" % [marker, persistent_id, str(dungeon._arms_taker_defeat_commits.keys()), enemy.get_persistent_id() if is_instance_valid(enemy) else "freed"])
	var idempotent := false
	if committed and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
		var saved_record := EliteRosterService.get_record(ARMS_TAKER_ID)
		var saved_checkpoint := BaseManager.get_active_run_checkpoint()
		var saved_revision := BaseManager.data.save_revision
		var saved_pickups := transaction_pickups(marker)
		check(dungeon.commit_arms_taker_defeat(enemy, enemy._elite_defeat_context), marker + "：重复提交未幂等返回成功")
		idempotent = saved_record == EliteRosterService.get_record(ARMS_TAKER_ID) and saved_checkpoint == BaseManager.get_active_run_checkpoint() and saved_revision == BaseManager.data.save_revision and saved_pickups == transaction_pickups(marker) and (events["settled"] as Array).size() == 1
		check(idempotent, marker + "：重复提交改变库存/掉落/checkpoint/revision/事件")
	if case_id == "success" and is_instance_valid(enemy):
		await get_tree().create_timer(0.65).timeout
		await capture_revision("09_transaction_committed_kneel_drops", "真实 Dungeon 已原子提交；5 件库存掉 3 留 2，跪地实体仍在场")
	var retired := await wait_transaction_until(func(): return reference.get_ref() == null)
	check(retired and (events["defeated"] as Array).size() == 1 and int(events["killed"]) == 0 and int(events["escaped"]) == 0, marker + "：未自然释放或终态信号错误")
	var final_record := EliteRosterService.get_record(ARMS_TAKER_ID)
	var checkpoint := BaseManager.get_active_run_checkpoint()
	var pickups := transaction_pickups(marker)
	var landed := await wait_transaction_until(func():
		for pickup: GroundLootPickup3D in pickups:
			if not is_instance_valid(pickup) or not pickup.is_pickup_available():
				return false
		return true
	, 10.0)
	check(landed, marker + "：真实掉落动画未自然结束")
	var expected_drops: Array = []
	var expected_remaining: Array = []
	var total := 0
	for entry: Dictionary in inventory:
		total += int(entry.count)
	var remaining_to_drop := ceili(float(total) / 2.0)
	for entry: Dictionary in inventory:
		var drop_count := mini(int(entry.count), remaining_to_drop)
		if drop_count > 0:
			var item := (entry.item as Dictionary).duplicate(true)
			item["count"] = drop_count
			expected_drops.append(item)
			remaining_to_drop -= drop_count
		if int(entry.count) > drop_count:
			var kept := entry.duplicate(true)
			kept["count"] = int(entry.count) - drop_count
			expected_remaining.append(kept)
	check(final_record.get("state", "") == "Defeated" and int(final_record.get("defeat_count", 0)) == defeat_count_before + 1 and str(final_record.get("reserved_encounter_id", "")).is_empty(), marker + "：档案未完成唯一战败结算")
	check(final_record.get("stolen_items", []) == expected_remaining and pickups.size() == expected_drops.size(), marker + "：掉落数量/剩余库存不符合总量向上取半")
	var dropped_count := 0
	for pickup in pickups:
		dropped_count += int(pickup.item_data.get("count", 1))
		check(pickup.visible, marker + "：成功掉落仍不可见")
		check(pickup.monitoring, marker + "：成功掉落 monitoring 未恢复")
		check(pickup.is_processing(), marker + "：成功掉落 process 未恢复")
		check(pickup.is_pickup_available(), marker + "：成功掉落动画结束后仍不可拾取")
		if not (pickup.visible and pickup.monitoring and pickup.is_processing() and pickup.is_pickup_available()):
			print("ARMS_TAKER_PICKUP_OBSERVATION %s %s visible=%s monitoring=%s processing=%s snapshot=%s" % [marker, str(pickup.item_data.get("qa_entry_index")), str(pickup.visible), str(pickup.monitoring), str(pickup.is_processing()), str(pickup.get_model_snapshot())])
		var index := int(pickup.item_data.get("qa_entry_index", -1))
		var expected: Dictionary = {}
		for item: Dictionary in expected_drops:
			if int(item.get("qa_entry_index", -2)) == index:
				expected = item
		check(not expected.is_empty(), marker + "：掉落身份不匹配")
		for key in expected:
			check(pickup.item_data.get(key) == expected[key], marker + "：完整物品属性丢失：" + str(key))
	check(dropped_count == ceili(float(total) / 2.0), marker + "：实际物品总数不是 ceil(total/2)")
	var saved_items := transaction_saved_items(checkpoint, room.room_id, marker)
	check(saved_items.size() == expected_drops.size(), marker + "：checkpoint 漏掉 pending pickups")
	var saved_world := checkpoint.get("world_state", {}) as Dictionary
	check((saved_world.get("roaming_elite", {}) as Dictionary) == dungeon._roaming_elite.export_snapshot() and dungeon._roaming_elite.state.status == "defeated", marker + "：档案与 roaming checkpoint 非原子终态")
	check(dungeon._kills == kills_before and int(dungeon._alive_by_room.get(room.room_id, 0)) == alive_before and room.cleared == cleared_before, marker + "：战败污染普通击杀/清房账")
	for saved_item: Dictionary in saved_items:
		var matched := false
		for expected_item: Dictionary in expected_drops:
			if int(saved_item.get("qa_entry_index", -1)) == int(expected_item.get("qa_entry_index", -2)):
				matched = transaction_storage_equal(saved_item, expected_item)
		check(matched, marker + "：checkpoint 未保留完整物品属性")
	var room_snapshot := (saved_world.get("segment_runtime_state", {}) as Dictionary).get(room.room_id, {}) as Dictionary
	for saved_enemy: Dictionary in room_snapshot.get("enemies", []):
		check(str(saved_enemy.get("persistent_id", "")) != persistent_id, marker + "：checkpoint 仍包含战败实体")
	check((events["defeated"] as Array)[0].state == "defeated", marker + "：defeated 信号状态错误")
	BaseManager.load_base()
	check(transaction_storage_equal(EliteRosterService.get_record(ARMS_TAKER_ID), final_record), marker + "：读盘未保留完整档案与库存")
	check(transaction_storage_equal(transaction_saved_items(BaseManager.get_active_run_checkpoint(), room.room_id, marker), saved_items), marker + "：读盘未保留完整掉落")
	observations[marker] = {"real_scene": dungeon.scene_file_path, "natural_physics": true, "failure_seconds": failed_elapsed, "inventory_total": total, "dropped_total": dropped_count, "pickup_nodes": pickups.size(), "checkpoint_pickups": saved_items.size(), "idempotent_checked": idempotent, "actor_freed": reference.get_ref() == null, "events": events, "archive_state": final_record.get("state", ""), "roaming_status": dungeon._roaming_elite.state.status, "save_revision": BaseManager.data.save_revision}
	if case_id == "success":
		await capture_revision("10_transaction_finished_real_drops", "正式 defeated 信号后自然消失；3 件真实掉落和磁盘 checkpoint 一致")
	EliteRosterService.elite_settled.disconnect(on_settled)
	for pickup in pickups:
		pickup.remove_from_group("ground_loot_3d")
		pickup.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(sentinel):
		(dungeon._enemy_nodes_by_room[room.room_id] as Array).erase(sentinel)
		dungeon._alive_by_room[room.room_id] = maxi(0, alive_before - 1)
		sentinel.queue_free()
	await get_tree().process_frame
	print("ARMS_TAKER_REAL_DEFEAT_CASE %s total=%d dropped=%d freed=%s" % [case_id, total, dropped_count, str(retired)])
