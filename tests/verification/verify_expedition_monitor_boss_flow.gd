extends Node
## 正式远征场景进房 → 触发盒 → Boss → 自动续波 → 清房 → 撤离门。
## Runner 必须在 Autoload 前隔离 user://；不手工实例化 Boss、不预开门。
const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
var tower: TowerDescent3D
var room: DungeonRoom3D
var failures: Array[String] = []
var checks := 0
var clear_count := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("EXPEDITION_MONITOR_FAIL ", message)

func enemies() -> Array[Enemy3D]:
	var out: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		if is_instance_valid(value) and not value.is_queued_for_deletion() and value.current_hp > 0:
			out.append(value)
	return out

func _ready() -> void:
	tower = SCENE.instantiate()
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	# 关闭命运追加兵以单独检查房间编成；保留正式门策略。
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	room = tower._room_by_id.get("boss") as DungeonRoom3D
	check(room != null, "正式场景存在 Boss 房")
	if room == null:
		finish()
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	await get_tree().physics_frame
	check(str(room.get_meta("boss_content_id", "")) == "boss_monitor002", "房间身份经过正式规划传递")
	check(enemies().is_empty(), "未进入 Boss 房不提前生成")
	tower.room_cleared.connect(func(value: DungeonRoom3D):
		if value == room: clear_count += 1)
	tower.player.global_position = room.global_position + Vector3(0, 0.5, 0)
	tower._on_room_entered(room)
	await get_tree().physics_frame
	check(int(tower._room_wave_totals.get(room.room_id, 0)) == 3, "使用房间设计源三波 encounter")
	var bosses: Array[Enemy3D] = []
	for enemy in enemies():
		if str(enemy.enemy_data.get("boss_content_id", "")) == "boss_monitor002": bosses.append(enemy)
	check(bosses.size() == 1, "首波触发盒生成且只生成一个显示器 Boss")
	check(not tower._try_open_room_door("extraction"), "战斗未清时撤离方向门拒绝开启")
	if not bosses.is_empty():
		var boss := bosses[0]
		check(boss.max_hp == 5200, "正式刷怪生命为5200")
		check(boss.monitor_combat != null, "正式技能策略已绑定")
		check(boss.avatar._formal_boss_root is MonitorBossPresentation, "正式显示器资产已绑定")
		check(boss.killed.is_connected(tower._on_enemy_killed), "Boss 死亡接入房间结算")
		check(boss.boss_phase_changed.is_connected(tower._on_boss_phase_changed), "Boss 阶段接入正式 HUD/音效")
		boss.take_damage(1800)
		check(boss.boss_phase == 2, "实伤进入第二阶段")
		boss.take_damage(1800)
		check(boss.boss_phase == 3, "实伤进入第三阶段")
		boss.take_damage(100000)
		check(boss.ai_state == "dead", "实伤触发正式死亡状态")
		check(not room.cleared, "只击败 Boss 不跳过随从和后续波次")
	# 等待盒子延迟随从，逐波实际击杀；自动推进，不触碰门。
	var deadline := Time.get_ticks_msec() + 18000
	while not room.cleared and Time.get_ticks_msec() < deadline:
		for enemy in enemies(): enemy.take_damage(100000)
		await get_tree().create_timer(0.1).timeout
	check(room.cleared, "三波清完自动清房")
	check(clear_count == 1, "清房事件只结算一次")
	check(int(tower._alive_by_room.get(room.room_id, -1)) == 0, "死亡与延迟刷怪存活账归零")
	check(tower._boss_descent_key_count == 0, "远征不授予塔楼下行权限")
	check(not tower._conditional_extractions.has("BOSS_KILL"), "远征不额外生成塔楼 Boss 撤离信标")
	var beacon := tower._conditional_extractions.get("STANDARD") as ExtractionBeacon3D
	check(beacon != null and beacon.beacon_type == "STANDARD", "终点保留正式 STANDARD 撤离")
	# 清房钥匙仍按原正式拾取/开门规则，不免费越过钥匙或命运卡。
	check(bool(tower._door_policy_towards(room.room_id, "extraction").get("requires_clear", false)), "撤离方向门保留清房门策略")
	tower._on_room_entered(room)
	await get_tree().process_frame
	check(enemies().is_empty() and clear_count == 1, "重进已清 Boss 房不重复生成和结算")
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value.room_id == room.room_id: value._on_body_entered(tower.player)
	check(tower._try_open_room_door("extraction"), "清房并拾取正式奖励钥匙后可开启撤离方向门")
	check(bool(tower._open_edges.get(tower._edge_key(room.room_id, "extraction"), false)), "撤离连接实际开启")
	finish()

func finish() -> void:
	print("EXPEDITION_MONITOR_REPORT ", JSON.stringify({"checks":checks,"failures":failures}))
	if is_instance_valid(tower): tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty(): print("EXPEDITION_MONITOR_BOSS_FLOW_OK")
	get_tree().quit(0 if failures.is_empty() else 1)
