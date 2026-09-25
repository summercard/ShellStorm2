extends Node
## 正式波次入口回归；冻结自动AI，但移动真实玩家并调用正式进房/流送生命周期。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
var failures: Array[String] = []
var dungeon: Dungeon3D
var room: DungeonRoom3D
var away: DungeonRoom3D


func _ready() -> void:
	dungeon = DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 20260925
	add_child(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	# 基础波次用例隔离命运阈值；后面单独走真实阈值信号验证。
	for config in dungeon._map_fate_triggers._triggers:
		config.enabled = false
	away = dungeon._room_by_id.get("start") as DungeonRoom3D
	for candidate in dungeon._rooms:
		if candidate.room_type == "COMBAT":
			room = candidate
			break
	if room == null or away == null:
		_check(false, "找不到战斗房与切房目的地")
	else:
		await _verify_waves()
		await _verify_cancel_and_restore()
		await _verify_summon_reservation()
		await _verify_fate_wave()
		await _verify_spawn_failure()
		await _verify_exit()
	if is_instance_valid(dungeon):
		dungeon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("DUNGEON_WAVE_INTERMISSION_REGRESSION_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _enter(target: DungeonRoom3D) -> void:
	dungeon.player.global_position = target.global_position + Vector3(0, 0.05, 0)
	dungeon._on_room_entered(target)


func _enemies() -> Array:
	return dungeon._enemy_nodes_by_room.get(room.room_id, []) as Array


func _wave() -> int:
	return int(dungeon._room_wave_numbers.get(room.room_id, 0))


func _alive() -> int:
	return int(dungeon._alive_by_room.get(room.room_id, 0))


func _pending() -> bool:
	return dungeon._wave_spawn_pending.has(room.room_id)


func _prepare(sizes: Array[int]) -> bool:
	dungeon._room_spawn_blocked.erase(room.room_id)
	_enter(room)
	for enemy in _enemies().duplicate():
		if is_instance_valid(enemy):
			enemy.free()
	dungeon._enemy_nodes_by_room[room.room_id] = []
	dungeon._reserved_room_spawns.erase(room.room_id)
	dungeon._room_fate_wave_queued.erase(room.room_id)
	dungeon._segment_runtime_state.erase(room.room_id)
	room.cleared = false
	var waves: Array = []
	for size in sizes:
		var batch: Array[Dictionary] = []
		for index in size:
			batch.append({"enemy_type": "melee_chaser", "hp": 20, "damage": 1, "floor": 1})
		waves.append(batch)
	var ok := dungeon._commit_room_waves(room, waves)
	_check(ok, "测试遭遇提交失败")
	return ok


func _kill_all() -> void:
	for value in _enemies().duplicate():
		(value as Enemy3D)._die()


func _verify_waves() -> void:
	if not _prepare([3, 2, 2]):
		return
	_check(_enemies().size() == 3 and _wave() == 1, "首波必须整批生成三只")
	_check(dungeon._hud_wave_label.text.contains("1/3"), "HUD未显示首波/总波数")
	# 在击杀发布期间重入正式修复，覆盖旧实现先删成员、后扣计数的事务窗口。
	var repair_on_kill := func() -> void: dungeon._repair_hostile_room_progress(room)
	dungeon.kill_recorded.connect(repair_on_kill)
	var first := _enemies()[0] as Enemy3D
	first._die()
	var kills := dungeon._kills
	dungeon._on_enemy_killed(first, first.get_enemy_data())
	dungeon._on_enemy_escaped(first, {})
	_check(_alive() == 2 and _wave() == 1 and not _pending(), "单只死亡/重复离场提前推进或重复扣数")
	_check(dungeon._kills == kills, "重复死亡重复奖励/增加击杀数")
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 1 and _enemies().size() == 2, "只杀首只等待超过2秒仍推进")
	(_enemies()[0] as Enemy3D)._die()
	_check(_alive() == 1 and not _pending(), "第二只死亡提前推进")
	_kill_all()
	dungeon.kill_recorded.disconnect(repair_on_kill)
	_check(_pending() and _wave() == 1, "全清后未进入间歇")
	var token := int(dungeon._wave_spawn_pending.get(room.room_id, -1))
	dungeon._repair_hostile_room_progress(room)
	dungeon._spawn_next_room_wave(room.room_id)
	_check(int(dungeon._wave_spawn_pending.get(room.room_id, -2)) == token, "修复重设计时或直接生成绕过等待")
	dungeon.status_label.text = "普通交互提示"
	_check(dungeon._hud_wave_label.text.contains("1/3") and dungeon._hud_wave_label.text.contains("间歇"), "独立波次提示被普通消息覆盖")
	await get_tree().create_timer(1.90).timeout
	_check(_wave() == 1 and _enemies().is_empty(), "不足2秒已生成第二波")
	await get_tree().create_timer(0.25).timeout
	_check(_wave() == 2 and _enemies().size() == 2 and not _pending(), "2秒后没有一次生成第二整波")
	dungeon._on_room_wave_intermission_timeout(room.room_id, token)
	_check(_wave() == 2 and _enemies().size() == 2, "重复超时消费了下一波")
	_kill_all()
	_check(_pending() and _wave() == 2, "同帧全杀没有进入唯一间歇")
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 3 and _enemies().size() == 2, "第三波没有整批生成")
	_kill_all()
	_check(room.cleared and not _pending(), "最后波清空未稳定清房")
	_check(dungeon._hud_wave_label.text.contains("3/3") and dungeon._hud_wave_label.text.contains("肃清"), "终波HUD不正确")
	dungeon._repair_hostile_room_progress(room)
	await get_tree().create_timer(2.15).timeout
	_check(_enemies().is_empty() and _wave() == 3, "终波清房仍重复刷怪")


func _verify_cancel_and_restore() -> void:
	if not _prepare([1, 2]):
		return
	_kill_all()
	var old_token := int(dungeon._wave_spawn_pending.get(room.room_id, -1))
	_enter(away)
	_check(not _pending(), "正式切房没有取消间歇")
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 1 and _enemies().is_empty(), "离房后旧计时器仍刷怪")
	_enter(room)
	_check(_pending(), "回房未重建完整间歇")
	dungeon._on_room_wave_intermission_timeout(room.room_id, old_token)
	_check(_wave() == 1 and _pending(), "回房后旧token覆盖新间歇")
	await get_tree().create_timer(1.90).timeout
	_check(_wave() == 1, "回房等待不足2秒")
	await get_tree().create_timer(0.25).timeout
	_check(_wave() == 2 and _enemies().size() == 2, "回房未恢复原队列")
	if not _prepare([1, 2]):
		return
	_kill_all()
	dungeon._hibernate_room_entities(room.room_id)
	room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	dungeon._repair_hostile_room_progress(room)
	await get_tree().create_timer(2.15).timeout
	_check(not _pending() and _wave() == 1 and not room.cleared, "卸载间歇未取消或被当成清房")
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	dungeon._restore_room_runtime_state(room.room_id)
	_check(_pending(), "卸载恢复未重建间歇")
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 2 and _enemies().size() == 2, "卸载恢复丢失待发波次")


func _verify_summon_reservation() -> void:
	if not _prepare([1, 2]):
		return
	var source := _enemies()[0] as Enemy3D
	source.elite_modifier_id = "Elite.SpawnOnDeath"
	source._die()
	dungeon._repair_hostile_room_progress(room)
	_check(_alive() == 3 and not _pending(), "死亡召唤预约被修复覆盖，提前进入下一波")
	dungeon._hibernate_room_entities(room.room_id)
	room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	await get_tree().process_frame
	_check(_enemies().is_empty() and dungeon._reserved_spawn_count(room.room_id) == 3, "召唤预约在卸载后仍落地或丢失")
	var snapshot := JSON.parse_string(JSON.stringify(dungeon._segment_runtime_state)) as Dictionary
	dungeon._segment_runtime_state = snapshot
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	dungeon._restore_room_runtime_state(room.room_id)
	await get_tree().process_frame
	_check(_enemies().size() == 3 and _alive() == 3 and not _pending(), "快照JSON往返未恢复三只召唤物")
	_kill_all()
	_check(_pending(), "召唤物全清后未开始间歇")
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 2 and _enemies().size() == 2, "召唤物全清后未正常续波")


func _verify_fate_wave() -> void:
	if not _prepare([2, 1]):
		return
	var triggers := dungeon._map_fate_triggers
	triggers._reset_counters()
	for config in triggers._triggers:
		if config.fate_card_id == "fate_reinforce":
			config.enabled = true
	triggers._counters[int(MapFateTriggers.TriggerType.KILL_COUNT)] = 2
	(_enemies()[0] as Enemy3D)._die()
	_check(_alive() == 1 and _enemies().size() == 1 and _wave() == 1 and not _pending(), "首杀触发命运时并发刷怪")
	_check(int(dungeon._room_wave_totals[room.room_id]) == 3, "命运增援没有追加到总波数")
	for index in 4:
		triggers._last_trigger_time.clear()
		triggers._on_kill_recorded()
	_check(int(dungeon._room_wave_totals[room.room_id]) == 3, "命运增援重复阈值无限追加")
	_kill_all()
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 2 and _enemies().size() == 1, "命运增援改变了原波队列顺序")
	_kill_all()
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 3 and _enemies().size() == 3, "命运整波未在原队列后生成")
	_enter(away)
	_enter(room)
	dungeon.trigger_extra_wave()
	_check(int(dungeon._room_wave_totals[room.room_id]) == 3, "流送恢复丢失命运追加幂等标记")
	_kill_all()
	dungeon.trigger_extra_wave()
	_check(room.cleared and not _pending(), "命运终波全清后重启遭遇")
	for config in triggers._triggers:
		config.enabled = false


func _verify_spawn_failure() -> void:
	if not _prepare([1, 2]):
		return
	var configs: Array[Dictionary] = [{"enemy_type": "melee_chaser"}, {"enemy_type": "melee_chaser"}]
	var before := dungeon.get_node("ActiveEnemies").get_child_count()
	var alive_before := _alive()
	var result := dungeon._spawn_enemy_batch(room, configs, true, false, [room.global_position, Vector3.INF])
	_check(result < 0 and dungeon.get_node("ActiveEnemies").get_child_count() == before and _alive() == alive_before, "批次后段INF导致半波实例或修改存活数")
	for enemy in dungeon.get_node("ActiveEnemies").get_children():
		_check((enemy as Node3D).global_position.is_finite(), "INF进入敌人transform")
	dungeon._room_spawn_blocked.erase(room.room_id)
	# 真实落点算法无候选时返回INF，不用替身伪造返回值。
	var candidates := room._spawn_candidates.duplicate()
	var edges := room._spawn_edge_candidates.duplicate()
	room._spawn_candidates.clear()
	room._spawn_edge_candidates.clear()
	_kill_all()
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 1 and _enemies().is_empty() and not room.cleared and not _pending(), "后续波落点失败仍推进/假清房")
	_check((dungeon._room_wave_queues[room.room_id] as Array).size() == 1, "后续波落点失败丢失队列")
	for index in 3:
		dungeon._repair_hostile_room_progress(room)
	await get_tree().create_timer(2.15).timeout
	_check(not _pending() and _wave() == 1, "落点失败被修复入口无限重试")
	dungeon._capture_room_runtime_state(room.room_id)
	dungeon._restore_room_runtime_state(room.room_id)
	_check(dungeon._room_spawn_blocked.has(room.room_id) and not room.cleared, "落点失败状态未随快照保留")
	_check(dungeon._hud_wave_label.text.contains("无合法落点"), "失败HUD未保持")
	# 首波失败必须保留首波在内的全部计划，已生成波号为0。
	dungeon._room_spawn_blocked.erase(room.room_id)
	var waves: Array = [configs.duplicate(true), configs.duplicate(true)]
	_check(not dungeon._commit_room_waves(room, waves), "首波无落点仍报告成功")
	_check(_wave() == 0 and (dungeon._room_wave_queues[room.room_id] as Array).size() == 2 and not room.cleared, "首波失败未保留完整队列")
	# 预约失败必须保留请求及预约计数，不能被flush吞掉。
	dungeon._room_spawn_blocked.erase(room.room_id)
	dungeon._reserve_room_spawn(room.room_id, configs)
	await get_tree().process_frame
	_check(dungeon._reserved_spawn_count(room.room_id) == 2 and _alive() == 2 and _enemies().is_empty(), "预约落点失败丢失请求或生成非法实体")
	room._spawn_candidates.assign(candidates)
	room._spawn_edge_candidates.assign(edges)
	print("DUNGEON_SPAWN_FAILURE_OK")


func _verify_exit() -> void:
	if not _prepare([1, 1]):
		return
	_kill_all()
	await get_tree().process_frame
	remove_child(dungeon)
	_check(not _pending(), "场景退出没有取消间歇")
	await get_tree().create_timer(2.15).timeout
	_check(_wave() == 1, "退出场景后计时器仍消费队列")
	dungeon.free()
