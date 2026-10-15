extends Node
## EncounterEventDirector3D 独立契约 + Dungeon3D 正式入口接缝专项。
## 使用 preload 取得脚本，避免 class cache 让独立测试误报。

const DIRECTOR_SCRIPT = preload("res://src/world3d/EncounterEventDirector3D.gd")
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


func _ready() -> void:
	await _run_fake_contract()
	await _run_formal_dungeon_contract()
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
