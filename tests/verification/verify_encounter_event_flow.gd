extends Node
## EncounterEventDirector3D 独立契约 + Dungeon3D 正式入口接缝专项。
## 使用 preload 取得脚本，避免 class cache 让独立测试误报。

const DIRECTOR_SCRIPT = preload("res://src/world3d/EncounterEventDirector3D.gd")
const VALIDATOR_SCRIPT = preload("res://src/map/LevelPlanValidator.gd")
const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")

var failures: Array[String] = []
var samples := 0


class FakeHost extends RefCounted:
	var current_room := "room_a"
	var player_alive := true
	var run_active := true
	var room_cleared := false
	var flags := {"alarm": true}
	var completed_events: Array = []
	var live_by_instance: Dictionary = {}
	var spawn_log: Array[Dictionary] = []
	var actions: Array[Dictionary] = []
	var busy_rooms: Dictionary = {}
	var retry_next_spawn := false
	var last_min_player_distance := -1.0

	func encounter_event_current_room_id() -> String:
		return current_room

	func encounter_event_room_busy(room_id: String) -> bool:
		return bool(busy_rooms.get(room_id, false))

	func encounter_event_context(room_id: String, _instance_id: String) -> Dictionary:
		return {
			"player_alive": player_alive,
			"run_active": run_active,
			"current_room_id": current_room,
			"room_cleared": room_cleared,
			"flags": flags.duplicate(true),
			"completed_events": completed_events.duplicate(),
		}

	func encounter_event_spawn(instance_id: String, room_id: String, spec: Dictionary, count: int) -> Dictionary:
		last_min_player_distance = float(spec.get("min_player_distance_m", -1.0))
		if retry_next_spawn:
			retry_next_spawn = false
			return {"ok": true, "spawned": 0, "retryable": true}
		spawn_log.append({"instance_id": instance_id, "room_id": room_id, "type": spec.get("type", ""), "count": count})
		live_by_instance[instance_id] = int(live_by_instance.get(instance_id, 0)) + count
		return {"ok": true, "spawned": count}

	func encounter_event_live_count(instance_id: String) -> int:
		return int(live_by_instance.get(instance_id, 0))

	func encounter_event_despawn(instance_id: String, _reason: String) -> Dictionary:
		live_by_instance.erase(instance_id)
		return {"ok": true}

	func encounter_event_apply_result(action: Dictionary) -> Dictionary:
		actions.append(action.duplicate(true))
		return {"ok": true}


class ClosingHost extends FakeHost:
	var close_calls := 0
	var reserved := 0

	func encounter_event_close_dispatch(instance_id: String) -> Dictionary:
		close_calls += 1
		var dropped := reserved
		reserved = 0
		live_by_instance[instance_id] = maxi(0, encounter_event_live_count(instance_id) - dropped)
		return {"dropped": dropped}


func _ready() -> void:
	_run_boss_reinforcement_count_contract()
	_run_legacy_completion_contract()
	_run_timed_loop_contract()
	var fake_samples_before := samples
	var fake_failures_before := failures.size()
	await _run_fake_contract()
	if failures.size() == fake_failures_before:
		print("ENCOUNTER_EVENT_FAKE_CONTRACT_OK samples=%d" % (samples - fake_samples_before))
	var formal_samples_before := samples
	var formal_failures_before := failures.size()
	await _run_formal_dungeon_contract()
	if failures.size() == formal_failures_before:
		print("ENCOUNTER_EVENT_FORMAL_CONTRACT_OK samples=%d" % (samples - formal_samples_before))
	if failures.is_empty():
		print("ENCOUNTER_EVENT_FLOW_OK samples=%d" % samples)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check(ok: bool, message: String) -> void:
	samples += 1
	if not ok:
		failures.append(message)


func _config(event_id := "event_alpha", completion := "clear") -> Dictionary:
	return {
		"schema_version": 1,
		"event_id": event_id,
		"room_id": "room_a",
		"duration_sec": 10.0,
		"completion": completion,
		"max_alive": 2,
		"prereqs": {"player_alive": true, "run_active": true, "flags": {"alarm": true}},
		"stages": [
			{"at_sec": 0.0, "monsters": [{"type": "melee_chaser", "count": 3}]},
			{"at_ratio": 0.5, "monsters": [{"type": "fat_zombie03", "count": 2}]},
		],
		"on_completed": [{"type": "flag", "key": "event_alpha_done", "value": true}],
	}


func _run_boss_reinforcement_count_contract() -> void:
	var samples_before := samples
	var failures_before := failures.size()
	var room := {
		"key": "boss", "role": "boss", "content_type": "BOSS", "size": Vector2(40.0, 80.0),
		"boss_reinforcement_plan": {
			"enabled": true, "boss_spawn_local_m": [0.0, 0.0], "activation_delay_sec": 12.0,
			"spawn_rows": [
				{"side": "west", "x_m": -10.0, "z_m": [-5.0, 0.0, 5.0], "height_m": 3.0},
				{"side": "east", "x_m": 10.0, "z_m": [-5.0, 0.0, 5.0], "height_m": 3.0},
			],
			"enemy_request_type": "ambush", "initial_count": 3, "count_step": 0,
			"max_count_per_round": 3, "max_reinforcement_alive": 6,
			"initial_interval_sec": 9.0, "interval_step_sec": 0.0, "min_interval_sec": 9.0,
			"launch_speed_mps": 8.5, "launch_duration_sec": 0.38,
		},
	}
	for step in [0, 0.0, 1, 1.0]:
		var probe := room.duplicate(true)
		probe["boss_reinforcement_plan"]["count_step"] = step
		var errors: Array = VALIDATOR_SCRIPT._validate_boss_reinforcement_plan(probe)
		_check(errors.is_empty(), "合法增援count_step=%s被拒绝：%s" % [str(step), str(errors)])
	var json_probe: Variant = JSON.parse_string(JSON.stringify(room["boss_reinforcement_plan"]))
	var restored_room := room.duplicate(true)
	restored_room["boss_reinforcement_plan"] = json_probe
	_check(VALIDATOR_SCRIPT._validate_boss_reinforcement_plan(restored_room).is_empty(), "固定3只增援计划JSON往返被拒绝")
	for step in [-1, -0.5, 0.5, 0.000001, "0", false, true, null, INF, NAN]:
		var probe := room.duplicate(true)
		probe["boss_reinforcement_plan"]["count_step"] = step
		var errors: Array = VALIDATOR_SCRIPT._validate_boss_reinforcement_plan(probe)
		_check(errors == ["boss_reinforcement_count_step_invalid:boss"], "非法增援count_step=%s未精确拒绝：%s" % [str(step), str(errors)])
	for field in ["initial_count", "max_count_per_round", "max_reinforcement_alive"]:
		for invalid_count in [0, -1, 0.5, "3", false, INF, NAN]:
			var probe := room.duplicate(true)
			probe["boss_reinforcement_plan"][field] = invalid_count
			var errors: Array = VALIDATOR_SCRIPT._validate_boss_reinforcement_plan(probe)
			_check(errors.has("boss_reinforcement_%s_invalid:boss" % field), "%s=%s未保留正整数约束：%s" % [field, str(invalid_count), str(errors)])
	if failures.size() == failures_before:
		print("BOSS_REINFORCEMENT_COUNT_CONTRACT_OK samples=%d" % (samples - samples_before))


func _run_legacy_completion_contract() -> void:
	var samples_before := samples
	var failures_before := failures.size()
	for completion in ["timer", "clear", "timer_and_clear"]:
		var host := FakeHost.new()
		var director = DIRECTOR_SCRIPT.new(host)
		var config := _config("legacy_%s" % completion, completion)
		config["stages"] = [{"at_sec": 0.0, "monsters": [{"type": "melee_chaser", "count": 1}]}]
		var result := director.start(config)
		_check(bool(result.get("ok", false)), "%s旧正duration配置未启动" % completion)
		var instance_id := str(result.get("instance_id", ""))
		director.tick(0.1)
		host.live_by_instance[instance_id] = 0
		director.notify_enemy_departed(instance_id, "killed")
		var cleared := director.get_snapshot(instance_id)
		if completion == "timer":
			_check(cleared.get("status") == "active" and host.actions.is_empty(), "旧timer清怪时被提前完成")
			director.tick(9.9)
			_check(director.get_snapshot(instance_id).get("status") == "completed" and host.actions.size() == 1, "旧timer到点完成行为变化")
		else:
			# 锁定现有Owner事实：timer_and_clear目前清空可提前完成，不在本补丁修正旧语义。
			_check(cleared.get("status") == "completed" and float(cleared.get("elapsed", 0.0)) < 10.0 and host.actions.size() == 1, "旧timer_and_clear提前清空行为变化")
		var deadline_host := FakeHost.new()
		var deadline_director = DIRECTOR_SCRIPT.new(deadline_host)
		var deadline_result := deadline_director.start(config)
		var deadline_id := str(deadline_result.get("instance_id", ""))
		deadline_director.tick(0.1)
		deadline_director.tick(9.9)
		var expired := deadline_director.get_snapshot(deadline_id)
		if completion == "timer":
			_check(expired.get("status") == "completed" and deadline_host.encounter_event_live_count(deadline_id) == 1, "旧timer到点不要求清怪行为变化")
		else:
			_check(expired.get("status") == "failed" and (expired.get("failed", []) as Array).has("timer_expired_before_clear") and deadline_host.actions.is_empty(), "旧timer_and_clear到点存活失败行为变化")
	if failures.size() == failures_before:
		print("ENCOUNTER_EVENT_LEGACY_COMPLETION_OK samples=%d" % (samples - samples_before))


func _timed_config(completion := "clear") -> Dictionary:
	return {
		"schema_version": 1, "event_id": "timed_loop", "room_id": "room_a",
		"duration_sec": 60.0, "completion": completion, "progress_mode": "tick",
		"deadline_behavior": "close_dispatch_and_clear", "repeat_last_stage": true,
		"stage_advance": "clear", "preparation_sec": 0.0, "intermission_sec": 1.0,
		"alert_style": "red_eva", "hud_countdown": true, "max_alive": 99,
		"stages": [
			{"at_sec": 2.0, "monsters": [{"type": "melee_chaser", "count": 1}]},
			{"at_sec": 2.0, "monsters": [{"type": "fat_zombie03", "count": 2}]},
			{"at_sec": 2.0, "monsters": [{"type": "melee_chaser", "count": 3}]},
		],
		"on_completed": [{"type": "flag", "key": "timed_done", "value": true}],
	}


func _roundtrip(director) -> Dictionary:
	return director.import_snapshot(JSON.parse_string(JSON.stringify(director.export_snapshot())) as Dictionary)


func _run_timed_loop_contract() -> void:
	var samples_before := samples
	var failures_before := failures.size()
	for completion in ["clear", "timer_and_clear"]:
		var host := FakeHost.new()
		var director = DIRECTOR_SCRIPT.new(host)
		var result: Dictionary = director.start(_timed_config(completion))
		_check(bool(result.get("ok", false)), "定时循环合法配置未启动：" + completion)
		var id := str(result.get("instance_id", ""))
		var initial: Dictionary = director.get_room_countdown_snapshot("room_a")
		_check(initial.get("alert_phase") == "battle" and initial.get("alert_remaining_sec") == 60.0 and not initial.has("preparation_active"), "封门即开始60秒总计时，不得补准备期")
		director.tick(1.99)
		_check(host.spawn_log.is_empty() and is_equal_approx(float(director.get_snapshot(id).get("alert_remaining_sec", 0.0)), 58.01), "1.99秒首批提前或总倒计时未推进")
		_check(bool(_roundtrip(director).get("ok", false)), "首批前读档失败")
		director.tick(0.01)
		_check(host.spawn_log.size() == 1 and director.get_snapshot(id).get("spawned") == 1, "第2秒未派首批或越过清波门控")
		director.tick(0.5)
		_check(host.spawn_log.size() == 1, "前批存活时派发下一批")
		for wave in range(7):
			host.live_by_instance[id] = 0
			director.notify_enemy_departed(id, "killed")
			var cleared: Dictionary = director.get_snapshot(id)
			_check(cleared.get("status") == "active" and host.actions.is_empty(), "时间未到清空提前完成：%s/%d" % [completion, wave])
			_check(cleared.get("alert_phase") == "battle" and cleared.get("intermission_remaining_sec") == 1.0, "清空后间歇必须重新计1秒且HUD仍battle")
			var spawn_count := host.spawn_log.size()
			var serial := int(cleared.get("spawn_serial", 0))
			var requested := int(cleared.get("requested", 0))
			_check(bool(_roundtrip(director).get("ok", false)), "循环间歇JSON读档失败")
			director.notify_enemy_departed(id, "killed")
			director.tick(0.5)
			var middle: Dictionary = director.get_snapshot(id)
			_check(host.spawn_log.size() == spawn_count and middle.get("requested") == requested and middle.get("spawn_serial") == serial and middle.get("intermission_remaining_sec") == 0.5, "循环间歇读档重发、重复入账或重置间歇")
			director.tick(0.5)
			var next: Dictionary = director.get_snapshot(id)
			_check(host.spawn_log.size() == spawn_count + 1 and (next.get("stage_states", []) as Array).size() == 3, "下一批未派发或循环扩张stage_states")
			var spawned := int(next.get("spawned", 0))
			_check(bool(_roundtrip(director).get("ok", false)), "末批在场读档失败")
			director.tick(0.01)
			_check(director.get_snapshot(id).get("spawned") == spawned and host.spawn_log.size() == spawn_count + 1, "已出生末波读档重新生成")
		var looping: Dictionary = director.get_snapshot(id)
		_check(int(looping.get("repeat_stage_sequence", 0)) >= 5 and host.spawn_log.size() == 8, "快清未循环超过原三波")
		_check(int(looping.get("requested", 0)) == 21 and looping.get("spawned") == 21 and looping.get("spawn_serial") == 21, "循环累计requested/spawn_serial错误")
		var before_deadline_spawns := host.spawn_log.size()
		director.tick(59.99 - float(looping.get("elapsed", 0.0)))
		var almost: Dictionary = director.get_snapshot(id)
		_check(almost.get("status") == "active" and not bool(almost.get("dispatch_closed", false)) and float(almost.get("alert_remaining_sec", 0.0)) > 0.0, "60秒前错误关闭或完成")
		director.tick(0.02)
		var expired: Dictionary = director.get_snapshot(id)
		_check(expired.get("elapsed") == 60.0 and expired.get("stage_elapsed_sec") == 60.0 and expired.get("dispatch_closed") == true and expired.get("status") == "active", "60秒总时长错误包含额外等待或残怪被判失败")
		_check(expired.get("alert_phase") == "cleanup" and expired.get("alert_remaining_sec") == 0.0 and expired.get("pending") == 0, "到点未进入cleanup或pending未清")
		_check(bool(_roundtrip(director).get("ok", false)), "截止JSON读档失败")
		director.tick(20.0)
		_check(host.spawn_log.size() == before_deadline_spawns and director.get_snapshot(id).get("status") == "active", "截止恢复后重派发或残怪未清就完成")
		host.live_by_instance[id] = 0
		director.notify_enemy_departed(id, "killed")
		director.notify_enemy_departed(id, "killed")
		_check(director.get_snapshot(id).get("status") == "completed" and host.actions.size() == 1, "残怪清零未完成或结果动作重放")

	_run_timed_deadline_contract()
	_run_timed_validation_contract()
	if failures.size() == failures_before:
		print("ENCOUNTER_EVENT_TIMED_LOOP_OK samples=%d" % (samples - samples_before))


func _run_timed_deadline_contract() -> void:
	# 首tick跨过整个窗口：截止必须先于任何阶段（包括恰好60秒的阶段）。
	for delta in [60.0, 600.0]:
		var host := FakeHost.new()
		var director = DIRECTOR_SCRIPT.new(host)
		var config := _timed_config()
		(config["stages"] as Array)[2]["at_sec"] = 60.0
		var id := str(director.start(config).get("instance_id", ""))
		director.tick(delta)
		var row: Dictionary = director.get_snapshot(id)
		_check(host.spawn_log.is_empty() and row.get("dropped") == 6 and row.get("requested") == 6 and row.get("pending") == 0 and row.get("status") == "completed", "大delta到点前仍dispatch或未丢所有未开始计划")

	var host := ClosingHost.new()
	var director = DIRECTOR_SCRIPT.new(host)
	var config := _timed_config()
	config["max_alive"] = 2
	config["stages"] = [
		{"at_sec": 2.0, "monsters": [{"type": "melee_chaser", "count": 5}]},
		{"at_sec": 60.0, "monsters": [{"type": "fat_zombie03", "count": 4}]},
	]
	var id := str(director.start(config).get("instance_id", ""))
	director.tick(2.0)
	host.reserved = 1
	_check(director.get_snapshot(id).get("pending") == 3, "已开始批容量积压未保留")
	director.tick(58.0)
	var row: Dictionary = director.get_snapshot(id)
	_check(row.get("requested") == 9 and row.get("spawned") == 1 and row.get("spawn_serial") == 2 and row.get("dropped") == 8 and row.get("pending") == 0, "截止未丢已开始批pending/未开始批/Host预约，或重复requested")
	_check(host.close_calls == 1 and host.encounter_event_live_count(id) == 1 and row.get("status") == "active", "Host关闭派发未调用一次或错误清除已出生怪")
	for stage_value in row.get("stage_states", []) as Array:
		var stage := stage_value as Dictionary
		_check(stage.get("complete") == true and stage.get("dropped") == true and (stage.get("pending", []) as Array).is_empty(), "截止阶段complete/drop/pending标记不完整")
	_check(bool(_roundtrip(director).get("ok", false)), "截止残怪快照恢复失败")
	var saved: Dictionary = director.export_snapshot()
	_check((saved["instances"] as Array)[0].get("dispatch_closed") == true, "dispatch_closed未写快照")
	director.tick(100.0)
	row = director.get_snapshot(id)
	_check(host.close_calls == 1 and row.get("dropped") == 8 and host.spawn_log.size() == 1, "截止读档非幂等或normalize复活dropped")
	host.live_by_instance[id] = 0
	director.notify_enemy_departed(id, "killed")
	_check(director.get_snapshot(id).get("status") == "completed" and host.actions.size() == 1, "积压取消后残怪清空未完成")

	# schema1修复档：elapsed已到点但尚无dispatch_closed，下一tick只关不派。
	var repair_host := ClosingHost.new()
	var repair_director = DIRECTOR_SCRIPT.new(repair_host)
	var repair_id := str(repair_director.start(config).get("instance_id", ""))
	repair_director.tick(2.0)
	var repair_save: Dictionary = repair_director.export_snapshot()
	var repair_row := (repair_save["instances"] as Array)[0] as Dictionary
	repair_row["elapsed"] = 60.0
	repair_row.erase("dispatch_closed")
	repair_host.live_by_instance[repair_id] = 0
	_check(bool(repair_director.import_snapshot(repair_save).get("ok", false)), "截止缺字段schema1修复档未恢复")
	repair_director.notify_enemy_departed(repair_id, "killed")
	repair_director.tick(0.1)
	var repaired: Dictionary = repair_director.get_snapshot(repair_id)
	_check(repair_host.spawn_log.size() == 1 and repair_host.close_calls == 1 and repaired.get("dispatch_closed") == true and repaired.get("dropped") == 7 and repaired.get("status") == "completed", "修复档下一tick未先关闭派发")

	var retry_host := FakeHost.new()
	retry_host.retry_next_spawn = true
	var retry_director = DIRECTOR_SCRIPT.new(retry_host)
	var retry_id := str(retry_director.start(config).get("instance_id", ""))
	retry_director.tick(2.0)
	retry_director.tick(58.0)
	var retry_row: Dictionary = retry_director.get_snapshot(retry_id)
	_check(retry_host.spawn_log.is_empty() and retry_row.get("dropped") == 9 and retry_row.get("status") == "completed", "retryable积压到点仍补发")

	# 单模板循环在末次清空后原地复用，间歇跨截止只丢未实到的下一批。
	var single_host := FakeHost.new()
	var single_director = DIRECTOR_SCRIPT.new(single_host)
	var single := _timed_config()
	single["stages"] = [{"at_sec": 2.0, "monsters": [{"type": "melee_chaser", "count": 2}]}]
	var single_id := str(single_director.start(single).get("instance_id", ""))
	single_director.tick(2.0)
	single_host.live_by_instance[single_id] = 0
	single_director.notify_enemy_departed(single_id, "killed")
	_check(bool(_roundtrip(single_director).get("ok", false)), "单模板循环间歇未恢复")
	single_director.tick(1.0)
	_check(single_host.spawn_log.size() == 2 and single_director.get_snapshot(single_id).get("spawn_serial") == 4, "单模板末波未循环")
	single_director.tick(56.5)
	single_host.live_by_instance[single_id] = 0
	single_director.notify_enemy_departed(single_id, "killed")
	var waiting: Dictionary = single_director.get_snapshot(single_id)
	_check(waiting.get("requested") == 6 and waiting.get("pending") == 2 and waiting.get("repeat_stage_sequence") == 2, "循环待发未累计或末波状态不正确")
	_check(bool(_roundtrip(single_director).get("ok", false)), "循环跨截止间歇未恢复")
	single_director.tick(0.5)
	var single_closed: Dictionary = single_director.get_snapshot(single_id)
	_check(single_host.spawn_log.size() == 2 and single_closed.get("dropped") == 2 and single_closed.get("requested") == 6 and single_closed.get("spawned") == 4 and single_closed.get("status") == "completed", "循环间歇到点仍派发、漏丢pending或等待无意义间歇")

	var partial_host := FakeHost.new()
	var partial_director = DIRECTOR_SCRIPT.new(partial_host)
	var partial := single.duplicate(true)
	partial["max_alive"] = 1
	partial["intermission_sec"] = 0.0
	var partial_id := str(partial_director.start(partial).get("instance_id", ""))
	partial_director.tick(2.0)
	_check(bool(_roundtrip(partial_director).get("ok", false)), "分批pending读档失败")
	partial_director.tick(0.1)
	_check(partial_director.get_snapshot(partial_id).get("spawned") == 1 and partial_host.spawn_log.size() == 1, "分批pending读档重发已出生怪")
	partial_host.live_by_instance[partial_id] = 0
	partial_director.tick(0.1)
	partial_host.live_by_instance[partial_id] = 0
	partial_director.notify_enemy_departed(partial_id, "killed")
	partial_director.tick(0.1)
	_check(partial_director.get_snapshot(partial_id).get("spawned") == 3 and partial_director.get_snapshot(partial_id).get("pending") == 1, "零间歇循环未按容量分批")
	_check(bool(_roundtrip(partial_director).get("ok", false)), "循环末批部分派发状态未恢复")
	partial_director.tick(0.1)
	_check(partial_host.spawn_log.size() == 3 and partial_director.get_snapshot(partial_id).get("spawn_serial") == 3, "循环末批pending恢复后重复生成")
	partial_host.live_by_instance[partial_id] = 0
	partial_director.tick(60.0)
	var partial_closed: Dictionary = partial_director.get_snapshot(partial_id)
	_check(partial_host.spawn_log.size() == 3 and partial_closed.get("requested") == 4 and partial_closed.get("dropped") == 1 and partial_closed.get("status") == "completed", "末波部分pending跨截止未丢弃")

	# 未要求循环的固定窗口也不能提前完成；默认repeat=false。
	var finite_host := FakeHost.new()
	var finite_director = DIRECTOR_SCRIPT.new(finite_host)
	var finite := _timed_config()
	finite.erase("repeat_last_stage")
	finite["stages"] = [{"at_sec": 2.0, "monsters": [{"type": "melee_chaser", "count": 1}]}]
	var finite_id := str(finite_director.start(finite).get("instance_id", ""))
	finite_director.tick(2.0)
	finite_host.live_by_instance[finite_id] = 0
	finite_director.notify_enemy_departed(finite_id, "killed")
	_check(finite_director.get_snapshot(finite_id).get("status") == "active" and finite_host.actions.is_empty(), "非循环固定窗口清空时提前完成")
	finite_director.tick(58.0)
	_check(finite_director.get_snapshot(finite_id).get("status") == "completed" and finite_host.spawn_log.size() == 1, "repeat默认false或固定窗口完成错误")


func _run_timed_validation_contract() -> void:
	for patch in [
		{"duration_sec": 0.0}, {"duration_sec": -1.0}, {"duration_sec": INF},
		{"progress_mode": "external"}, {"completion": "timer"}, {"stage_advance": "time"},
		{"preparation_sec": 1.0}, {"preparation_sec": "0"}, {"preparation_sec": false},
		{"stages": []}, {"stages": null}, {"stages": {}},
		{"deadline_behavior": "typo"}, {"deadline_behavior": null},
		{"repeat_last_stage": "true"}, {"repeat_last_stage": 1},
	]:
		var config := _timed_config()
		config.merge(patch, true)
		_check(not bool(DIRECTOR_SCRIPT.validate_config(config).get("ok", false)), "无效定时循环组合未拒绝：" + str(patch))
	var convenience := _timed_config()
	convenience.erase("stages")
	convenience["monsters"] = [{"type": "melee_chaser", "count": 1}]
	_check(not bool(DIRECTOR_SCRIPT.validate_config(convenience).get("ok", false)), "定时循环允许了非显式stages便利编排")
	for feature in ["deadline_behavior", "repeat_last_stage"]:
		var config := _timed_config()
		config.erase("repeat_last_stage" if feature == "deadline_behavior" else "deadline_behavior")
		config["preparation_sec"] = 1.0
		_check(not bool(DIRECTOR_SCRIPT.validate_config(config).get("ok", false)), "单独启用%s绕过组合限制" % feature)


func _run_fake_contract() -> void:
	var host := FakeHost.new()
	var director = DIRECTOR_SCRIPT.new(host)
	var invalid := director.start({"schema_version": 1, "event_id": "bad", "duration_sec": 2.0, "completion": "clear", "prereqs": {"typo": true}, "stages": [{"at_sec": 0.0, "monsters": [{"type": "melee_chaser", "count": 1}]}]})
	_check(not bool(invalid.get("ok", false)) and str(invalid.get("error", "")).begins_with("unknown_prereq_field"), "未知前置条件未拒绝")
	_check(host.spawn_log.is_empty(), "非法请求产生了刷怪副作用")
	var boss := director.start({"schema_version": 1, "event_id": "boss", "duration_sec": 2.0, "completion": "clear", "stages": [{"at_sec": 0.0, "monsters": [{"type": "boss", "count": 1}]}]})
	_check(not bool(boss.get("ok", false)) and boss.get("error") == "boss_requires_dedicated_flow", "Boss未拒绝一般刷怪路径")
	var started := director.start(_config())
	_check(bool(started.get("ok", false)), "合法遭遇未启动")
	var instance_id := str(started.get("instance_id", ""))
	director.tick(0.1)
	var first := director.get_snapshot(instance_id)
	_check(first.get("requested") == 5 and first.get("spawned") == 2 and first.get("pending") == 1, "max_alive未挂起超额计划")
	_check(host.spawn_log.size() == 1 and host.spawn_log[0].get("type") == "melee_chaser", "定名普通怪编成错误")
	host.live_by_instance[instance_id] = 0
	director.tick(0.1)
	var second := director.get_snapshot(instance_id)
	_check(second.get("spawned") == 3 and second.get("pending") == 0, "存活限额释放后未补发挂起计划：%s" % str(second))
	host.live_by_instance[instance_id] = 0
	director.tick(5.0)
	var third := director.get_snapshot(instance_id)
	var fat_spawned := false
	for spawn_value in host.spawn_log:
		if str((spawn_value as Dictionary).get("type", "")) == "fat_zombie03":
			fat_spawned = true
			break
	_check(fat_spawned and third.get("stage_states", []).size() == 2 and (third.get("stage_states", [])[1] as Dictionary).get("started", false), "大delta未处理跨过的阶段：%s" % str(third))
	host.live_by_instance[instance_id] = 0
	director.notify_enemy_departed(instance_id, "killed")
	var completed := director.get_snapshot(instance_id)
	_check(completed.get("status") == "completed" and host.actions.size() == 1, "clear完成或结果动作未一次执行：%s" % str(completed))
	third = completed
	director.notify_enemy_departed(instance_id, "killed")
	_check(host.actions.size() == 1, "终态收到重复离场后重复执行结果")
	var cancelled := director.cancel(instance_id, "duplicate_cancel")
	_check(bool(cancelled.get("already_terminal", false)), "重复取消未保持幂等")

	var prereq_host := FakeHost.new()
	prereq_host.player_alive = false
	var prereq_director = DIRECTOR_SCRIPT.new(prereq_host)
	var rejected := prereq_director.start(_config("dead_player"))
	_check(not bool(rejected.get("ok", false)) and rejected.get("error") == "prereq_player_alive", "死亡前置未拒绝")
	prereq_host.player_alive = true
	var paused := prereq_director.start(_config("pause_case"))
	var paused_id := str(paused.get("instance_id", ""))
	prereq_host.current_room = "room_b"
	prereq_director.tick(4.0)
	_check(float(prereq_director.get_snapshot(paused_id).get("elapsed", -1.0)) == 0.0, "pause离房后错误推进")
	prereq_host.current_room = "room_a"
	prereq_director.tick(0.1)
	_check(float(prereq_director.get_snapshot(paused_id).get("elapsed", -1.0)) > 0.0, "返回房间后未恢复")

	var external_host := FakeHost.new()
	var external_director = DIRECTOR_SCRIPT.new(external_host)
	var external_config := _config("external_case", "timer")
	external_config["progress_mode"] = "external"
	var external := external_director.start(external_config)
	var external_id := str(external.get("instance_id", ""))
	external_director.advance_external(external_id, 0.7)
	_check(float(external_director.get_snapshot(external_id).get("elapsed", 0.0)) >= 7.0, "external tick未推进")
	_check(external_director.import_snapshot(external_director.export_snapshot()).get("ok", false), "restore快照失败")

	var interval_host := FakeHost.new()
	var interval_director = DIRECTOR_SCRIPT.new(interval_host)
	var interval_config := {
		"schema_version": 1,
		"event_id": "interval_case",
		"room_id": "room_a",
		"duration_sec": 10.0,
		"completion": "timer",
		"max_alive": 99,
		"monsters": [{"type": "melee_chaser", "count": 2}, {"type": "ambusher", "count": 2}],
		"total_count": 3,
		"interval_sec": 2.0,
		"prereqs": {"player_alive": true, "run_active": true},
		"on_completed": [],
	}
	var interval_started := interval_director.start(interval_config)
	var interval_id := str(interval_started.get("instance_id", ""))
	_check(bool(interval_started.get("ok", false)), "interval convenience配置未启动")
	var interval_snapshot := interval_director.get_snapshot(interval_id)
	_check(interval_snapshot.get("requested") == 3 and (interval_snapshot.get("config", {}).get("stages", []) as Array).size() == 3, "interval_sec未拆成精确阶段：%s" % str(interval_snapshot))
	interval_director.tick(0.1)
	_check(interval_director.get_snapshot(interval_id).get("spawned") == 1, "interval首只未按0秒派发")
	interval_director.tick(1.8)
	_check(interval_director.get_snapshot(interval_id).get("spawned") == 1, "interval提前派发")
	interval_director.tick(0.2)
	_check(interval_director.get_snapshot(interval_id).get("spawned") == 2, "interval第二只未按间隔派发")

	var cancelled_host := FakeHost.new()
	var cancelled_director = DIRECTOR_SCRIPT.new(cancelled_host)
	var cancelled_config := _config("cancelled_case", "timer")
	cancelled_config["on_cancelled"] = [{"type": "hint", "text": "遭遇已取消"}]
	var cancelled_started := cancelled_director.start(cancelled_config)
	var cancelled_id := str(cancelled_started.get("instance_id", ""))
	cancelled_director.tick(0.1)
	var cancelled_result := cancelled_director.cancel(cancelled_id, "test_cancel", true)
	_check(bool(cancelled_result.get("ok", false)) and cancelled_host.actions.size() == 1, "on_cancelled结果动作未执行一次")
	_check((cancelled_result.get("snapshot", {}) as Dictionary).get("status") == "cancelled", "取消后状态错误")
	var cancelled_again := cancelled_director.cancel(cancelled_id, "duplicate_cancel", true)
	_check(bool(cancelled_again.get("already_terminal", false)) and cancelled_host.actions.size() == 1, "重复取消重复执行结果动作")

	var no_deadline_host := FakeHost.new()
	var no_deadline_director = DIRECTOR_SCRIPT.new(no_deadline_host)
	var no_deadline_config := {
		"schema_version": 1,
		"event_id": "finite_clear_no_deadline",
		"room_id": "room_a",
		"duration_sec": 0.0,
		"completion": "clear",
		"stage_advance": "clear",
		"intermission_sec": 2.0,
		"max_alive": 1,
		"min_player_distance_m": 6.0,
		"prereqs": {"player_alive": true, "run_active": true},
		"stages": [
			{"at_sec": 0.0, "monsters": [{"type": "melee_chaser", "count": 2}]},
			{"at_sec": 0.0, "monsters": [{"type": "fat_zombie03", "count": 1, "min_player_distance_m": 8.0}]},
		],
		"on_completed": [],
	}
	var no_deadline_started := no_deadline_director.start(no_deadline_config)
	_check(bool(no_deadline_started.get("ok", false)), "duration=0有限stages未启动")
	var no_deadline_id := str(no_deadline_started.get("instance_id", ""))
	no_deadline_director.tick(10.0)
	var no_deadline_first := no_deadline_director.get_snapshot(no_deadline_id)
	_check(no_deadline_first.get("status") == "active" and no_deadline_first.get("spawned") == 1 and no_deadline_first.get("pending") == 1, "无截止模式错误按duration终止或丢pending")
	_check(is_equal_approx(no_deadline_host.last_min_player_distance, 6.0), "事件默认最小距离未传给Host")
	no_deadline_host.live_by_instance[no_deadline_id] = 0
	no_deadline_director.tick(0.1)
	_check(no_deadline_director.get_snapshot(no_deadline_id).get("spawned") == 2, "pending队列释放后未补发")
	no_deadline_host.live_by_instance[no_deadline_id] = 0
	no_deadline_director.notify_enemy_departed(no_deadline_id, "killed")
	var saved_no_deadline := no_deadline_director.export_snapshot()
	var remaining_snapshot := no_deadline_director.get_snapshot(no_deadline_id)
	_check(is_equal_approx(float(remaining_snapshot.get("intermission_remaining_sec", -1.0)), 2.0), "真实清空后未开始保存间歇")
	var no_deadline_roundtrip: Variant = JSON.parse_string(JSON.stringify(saved_no_deadline))
	_check(bool(no_deadline_director.import_snapshot(no_deadline_roundtrip as Dictionary).get("ok", false)), "间歇快照JSON往返失败")
	no_deadline_director.tick(1.0)
	var restored_intermission := no_deadline_director.get_snapshot(no_deadline_id)
	_check(
		restored_intermission.get("spawned") == 2
		and restored_intermission.get("pending") == 0
		and no_deadline_host.spawn_log.size() == 2
		and not bool((restored_intermission.get("stage_states", [])[1] as Dictionary).get("started", false))
		and is_equal_approx(float(restored_intermission.get("intermission_remaining_sec", -1.0)), 1.0),
		"恢复后累计派发应保持2、下一波未启动且间歇剩1秒：%s" % str(restored_intermission)
	)
	print("ENCOUNTER_EVENT_RESTORED_INTERMISSION spawned=%d remaining_sec=%.1f next_stage_started=%s" % [
		int(restored_intermission.get("spawned", -1)),
		float(restored_intermission.get("intermission_remaining_sec", -1.0)),
		str((restored_intermission.get("stage_states", [])[1] as Dictionary).get("started", false)),
	])
	no_deadline_director.tick(1.0)
	var no_deadline_second := no_deadline_director.get_snapshot(no_deadline_id)
	_check(no_deadline_second.get("spawned") == 3 and is_equal_approx(no_deadline_host.last_min_player_distance, 8.0), "间歇结束后未派发下一波或未传单条最小距离")
	no_deadline_host.live_by_instance[no_deadline_id] = 0
	no_deadline_director.notify_enemy_departed(no_deadline_id, "killed")
	_check(no_deadline_director.get_snapshot(no_deadline_id).get("status") == "completed", "有限stages最后一波清空后未立即完成")

	var zero_ratio := no_deadline_config.duplicate(true)
	zero_ratio["event_id"] = "zero_ratio_rejected"
	(zero_ratio["stages"] as Array)[1] = {"at_ratio": 0.5, "monsters": [{"type": "melee_chaser", "count": 1}]}
	var zero_ratio_result := DIRECTOR_SCRIPT.validate_config(zero_ratio)
	_check(not bool(zero_ratio_result.get("ok", false)) and zero_ratio_result.get("error") == "duration_zero_at_ratio_not_allowed", "无截止模式未拒绝at_ratio")

	var retry_host := FakeHost.new()
	retry_host.retry_next_spawn = true
	var retry_director = DIRECTOR_SCRIPT.new(retry_host)
	var retry_started := retry_director.start(no_deadline_config.duplicate(true))
	var retry_id := str(retry_started.get("instance_id", ""))
	retry_director.tick(0.1)
	_check(retry_director.get_snapshot(retry_id).get("status") == "active" and retry_director.get_snapshot(retry_id).get("pending") == 2, "retryable空点未保留pending")
	retry_director.tick(0.1)
	_check(retry_director.get_snapshot(retry_id).get("spawned") == 1, "retryable空点未在下一tick重试")


func _run_formal_dungeon_contract() -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	if dungeon == null:
		_check(false, "正式Dungeon场景无法实例化")
		return
	dungeon.test_mode = true
	dungeon.run_seed_override = 20261015
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(dungeon.has_method("start_encounter_event"), "Dungeon未暴露start_encounter_event")
	_check(dungeon.has_method("cancel_encounter_event"), "Dungeon未暴露cancel_encounter_event")
	_check(dungeon.has_method("get_encounter_event_snapshot"), "Dungeon未暴露snapshot查询")
	if dungeon._encounter_event_director == null:
		_check(false, "正式Dungeon未装配EncounterEventDirector")
	else:
		var formal_config := _config("formal_named", "timer")
		formal_config["prereqs"] = {"player_alive": true, "run_active": true}
		formal_config["room_id"] = str(dungeon._current_room_id)
		formal_config["max_alive"] = 10
		var result := dungeon.start_encounter_event(formal_config)
		_check(bool(result.get("ok", false)), "正式Dungeon合法遭遇启动失败：%s" % str(result))
		if bool(result.get("ok", false)):
			var snapshot := dungeon.get_encounter_event_snapshot(str(result.get("instance_id", "")))
			_check(snapshot.get("requested") == 5, "正式接口没有保留准确请求数量")
			await get_tree().process_frame
			_check(not dungeon._enemy_nodes_by_room.get(str(dungeon._current_room_id), []).is_empty(), "正式接口未通过MonsterInjector/Enemy批次入口生成")
			var formal_cancelled := dungeon.cancel_encounter_event(str(result.get("instance_id", "")), "test_cleanup", true)
			_check(bool(formal_cancelled.get("ok", false)), "正式接口取消失败")
	if is_instance_valid(dungeon):
		dungeon.queue_free()
	await get_tree().process_frame
