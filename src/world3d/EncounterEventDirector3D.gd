class_name EncounterEventDirector3D
extends RefCounted
## 独立运行时遭遇事件 Owner。
## Host 只通过下列窄接口提供上下文、生成、结果动作和存档数据；本类不读取 Dungeon 私有成员。
## Host methods:
## encounter_event_context(room_id, instance_id) -> Dictionary
## encounter_event_spawn(instance_id, room_id, monster_spec, count) -> Dictionary
## encounter_event_live_count(instance_id) -> int
## encounter_event_apply_result(action) -> Dictionary

signal encounter_event_started(snapshot: Dictionary)
signal encounter_event_stage_started(snapshot: Dictionary, stage_index: int)
signal encounter_event_finished(snapshot: Dictionary)

const SCHEMA_VERSION := 1
const COMPLETIONS := ["timer", "clear", "timer_and_clear"]
const LEAVE_POLICIES := ["pause", "cancel", "follow_current_room"]
const PROGRESS_MODES := ["tick", "external"]
const PREREQ_KEYS := [
	"player_alive", "run_active", "room_cleared", "current_room", "flags", "completed_events",
]
const ACTION_KEYS := ["type", "key", "value", "room_id", "on", "text"]
const CONFIG_KEYS := [
	"schema_version", "event_id", "room_id", "duration_sec", "completion", "stages", "monsters",
	"count", "interval_sec", "total_count", "max_alive", "prereqs", "on_completed", "on_cancelled",
	"leave_policy", "progress_mode", "follow_current_room",
]
const STAGE_KEYS := ["at_sec", "at_ratio", "monsters"]
const MONSTER_KEYS := ["type", "count", "content_id"]

var _host: Object
var _instances: Dictionary = {}
var _next_instance_number := 1


func _init(host: Object = null) -> void:
	_host = host


func set_host(host: Object) -> void:
	_host = host


func start(config: Dictionary) -> Dictionary:
	var validation := validate_config(config)
	if not bool(validation.get("ok", false)):
		return validation
	if _host == null or not is_instance_valid(_host):
		return _reject("host_unavailable")
	var normalized := validation.get("config", {}) as Dictionary
	var room_id := str(normalized.get("room_id", ""))
	if room_id.is_empty():
		room_id = str(_host_call("encounter_event_current_room_id", [], ""))
	if room_id.is_empty():
		return _reject("room_required")
	normalized["room_id"] = room_id
	var context: Dictionary = _context(room_id, "")
	var prereq_result: Dictionary = _check_prereqs(normalized.get("prereqs", {}) as Dictionary, context, room_id)
	if not bool(prereq_result.get("ok", false)):
		return prereq_result
	var busy: Variant = _host_call("encounter_event_room_busy", [room_id], false)
	if bool(busy):
		return _reject("room_busy")
	var instance_id := "%s#%d" % [str(normalized["event_id"]), _next_instance_number]
	_next_instance_number += 1
	var stages: Array = normalized.get("stages", []) as Array
	var state := {
		"schema_version": SCHEMA_VERSION,
		"instance_id": instance_id,
		"event_id": str(normalized["event_id"]),
		"room_id": room_id,
		"config": normalized.duplicate(true),
		"elapsed": 0.0,
		"paused": false,
		"terminal": false,
		"status": "active",
		"completion": str(normalized["completion"]),
		"stage_states": [],
		"requested": 0,
		"spawned": 0,
		# Stable per-event serial for persistent enemy IDs. This is part of the
		# runtime snapshot so resumed events never reuse IDs already emitted.
		"spawn_serial": 0,
		"pending": 0,
		"dropped": 0,
		"escaped": 0,
		"failed": [],
		"result_actions": [],
		"result_applied": false,
		"partial_execution": false,
	}
	for stage_value in stages:
		var stage := stage_value as Dictionary
		var stage_state := {"started": false, "complete": false, "pending": []}
		for monster_value in stage.get("monsters", []) as Array:
			var monster := (monster_value as Dictionary).duplicate(true)
			var count := int(monster["count"])
			state["requested"] = int(state["requested"]) + count
			(stage_state["pending"] as Array).append(monster)
		(state["stage_states"] as Array).append(stage_state)
	_instances[instance_id] = state
	encounter_event_started.emit(get_snapshot(instance_id))
	return {"ok": true, "instance_id": instance_id, "snapshot": get_snapshot(instance_id)}


func cancel(instance_id: String, reason: String = "cancelled", despawn := false) -> Dictionary:
	var state := _instances.get(instance_id, {}) as Dictionary
	if state.is_empty():
		return _reject("unknown_instance")
	if bool(state.get("terminal", false)):
		return {"ok": true, "already_terminal": true, "snapshot": get_snapshot(instance_id)}
	if despawn:
		_host_call("encounter_event_despawn", [instance_id, reason], {})
	state["status"] = "cancelled"
	state["terminal"] = true
	state["cancel_reason"] = reason
	state["dropped"] = int(state.get("pending", 0))
	state["pending"] = 0
	state["partial_execution"] = int(state.get("spawned", 0)) > 0
	state["result"] = {
		"status": "cancelled", "reason": reason, "requested": state["requested"],
		"spawned": state["spawned"], "pending": 0, "dropped": state["dropped"],
	}
	_apply_result_actions(state, "on_cancelled")
	_instances[instance_id] = state
	encounter_event_finished.emit(get_snapshot(instance_id))
	return {"ok": true, "snapshot": get_snapshot(instance_id)}


func get_snapshot(instance_id: String) -> Dictionary:
	return (_instances.get(instance_id, {}) as Dictionary).duplicate(true)


func get_snapshot_rows() -> Array:
	var rows: Array = []
	for value in _instances.values():
		rows.append((value as Dictionary).duplicate(true))
	return rows


func cancel_all(reason: String) -> void:
	for instance_id_value in _instances.keys():
		cancel(str(instance_id_value), reason, true)


func has_active_room(room_id: String) -> bool:
	for value in _instances.values():
		var state := value as Dictionary
		if str(state.get("room_id", "")) == room_id and not bool(state.get("terminal", false)):
			return true
	return false


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for instance_id_value in _instances.keys():
		var instance_id := str(instance_id_value)
		var state := _instances[instance_id] as Dictionary
		if bool(state.get("terminal", false)):
			continue
		if str((state.get("config", {}) as Dictionary).get("progress_mode", "tick")) == "external":
			continue
		_step_instance(instance_id, state, delta)


func advance_external(instance_id: String, progress: float) -> Dictionary:
	var state := _instances.get(instance_id, {}) as Dictionary
	if state.is_empty():
		return _reject("unknown_instance")
	if str((state.get("config", {}) as Dictionary).get("progress_mode", "tick")) != "external":
		return _reject("external_progress_not_enabled")
	var duration := maxf(0.001, float((state.get("config", {}) as Dictionary).get("duration_sec", 0.0)))
	var target := clampf(progress, 0.0, 1.0) * duration
	var delta := maxf(0.0, target - float(state.get("elapsed", 0.0)))
	_step_instance(instance_id, state, delta)
	return {"ok": true, "snapshot": get_snapshot(instance_id)}


func notify_enemy_departed(instance_id: String, outcome: String) -> void:
	var state := _instances.get(instance_id, {}) as Dictionary
	if state.is_empty() or bool(state.get("terminal", false)):
		return
	if outcome == "escaped":
		state["escaped"] = int(state.get("escaped", 0)) + 1
		if str(state.get("completion", "")) in ["clear", "timer_and_clear"]:
			_fail_instance(instance_id, state, "enemy_escaped")
			return
	_try_finish_clear(instance_id, state)


func export_snapshot() -> Dictionary:
	var instances: Array = []
	for value in _instances.values():
		instances.append((value as Dictionary).duplicate(true))
	return {
		"schema_version": SCHEMA_VERSION,
		"next_instance_number": _next_instance_number,
		"instances": instances,
	}


func import_snapshot(snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("schema_version", -1)) != SCHEMA_VERSION:
		return _reject("encounter_snapshot_schema_invalid")
	var imported: Dictionary = {}
	var rows: Variant = snapshot.get("instances", [])
	if not rows is Array:
		return _reject("encounter_snapshot_instances_invalid")
	for value in rows as Array:
		if not value is Dictionary:
			return _reject("encounter_snapshot_row_invalid")
		var row := (value as Dictionary).duplicate(true)
		var instance_id := str(row.get("instance_id", ""))
		if instance_id.is_empty() or bool(row.get("terminal", false)):
			continue
		var config := row.get("config", {}) as Dictionary
		var validation := validate_config(config)
		if not bool(validation.get("ok", false)):
			continue
		# 只恢复纯计划数据；不凭空恢复已不存在的实体。Host 会在已有 enemy_data
		# 恢复后通过 encounter_instance_id 提供 live/reserved 归属。
		row["config"] = validation["config"]
		row["room_id"] = str(row.get("room_id", config.get("room_id", "")))
		row["stage_states"] = _normalize_stage_states(row, validation["config"] as Dictionary)
		row["terminal"] = false
		row["status"] = "active"
		imported[instance_id] = row
	_instances = imported
	_next_instance_number = maxi(_next_instance_number, int(snapshot.get("next_instance_number", 1)))
	return {"ok": true, "restored": _instances.size()}


static func validate_config(config: Dictionary) -> Dictionary:
	if config == null:
		return _reject("config_invalid")
	var unknown := _unknown_keys(config, CONFIG_KEYS)
	if not unknown.is_empty():
		return _reject("unknown_config_field:%s" % ",".join(unknown))
	if int(config.get("schema_version", -1)) != SCHEMA_VERSION:
		return _reject("schema_version_invalid")
	var event_id := str(config.get("event_id", ""))
	if event_id.is_empty():
		return _reject("event_id_required")
	var duration := float(config.get("duration_sec", 0.0))
	if duration <= 0.0:
		return _reject("duration_sec_invalid")
	var completion := str(config.get("completion", ""))
	if completion not in COMPLETIONS:
		return _reject("completion_invalid")
	var leave_policy := str(config.get("leave_policy", "pause"))
	if leave_policy not in LEAVE_POLICIES:
		return _reject("leave_policy_invalid")
	var progress_mode := str(config.get("progress_mode", "tick"))
	if progress_mode not in PROGRESS_MODES:
		return _reject("progress_mode_invalid")
	if config.has("follow_current_room") and not (config["follow_current_room"] is bool):
		return _reject("follow_current_room_invalid")
	var prereqs: Variant = config.get("prereqs", {})
	if not prereqs is Dictionary:
		return _reject("prereqs_invalid")
	unknown = _unknown_keys(prereqs as Dictionary, PREREQ_KEYS)
	if not unknown.is_empty():
		return _reject("unknown_prereq_field:%s" % ",".join(unknown))
	var stages: Array = []
	if config.has("stages"):
		if not config["stages"] is Array or (config["stages"] as Array).is_empty():
			return _reject("stages_invalid")
		for value in config["stages"] as Array:
			var stage_result := _validate_stage(value)
			if not bool(stage_result.get("ok", false)):
				return stage_result
			stages.append(stage_result["stage"])
	else:
		var compiled := _compile_convenience(config)
		if not bool(compiled.get("ok", false)):
			return compiled
		stages = compiled["stages"]
	var action_result: Dictionary = _validate_actions(config.get("on_completed", []))
	if not bool(action_result.get("ok", false)):
		return action_result
	var cancelled_action_result: Dictionary = _validate_actions(config.get("on_cancelled", []))
	if not bool(cancelled_action_result.get("ok", false)):
		return cancelled_action_result
	var normalized := config.duplicate(true)
	normalized["stages"] = stages
	normalized["leave_policy"] = leave_policy
	normalized["progress_mode"] = progress_mode
	normalized["prereqs"] = (prereqs as Dictionary).duplicate(true)
	normalized["on_completed"] = action_result["actions"]
	normalized["on_cancelled"] = cancelled_action_result["actions"]
	if config.has("max_alive"):
		if int(config["max_alive"]) <= 0:
			return _reject("max_alive_invalid")
		normalized["max_alive"] = int(config["max_alive"])
	return {"ok": true, "config": normalized}


func _step_instance(instance_id: String, state: Dictionary, delta: float) -> void:
	var config := state.get("config", {}) as Dictionary
	var room_id := str(state.get("room_id", ""))
	var context := _context(room_id, instance_id)
	var leave_policy := str(config.get("leave_policy", "pause"))
	var current_room := str(context.get("current_room_id", ""))
	var away := current_room != room_id
	if leave_policy == "cancel" and away:
		cancel(instance_id, "left_room", false)
		return
	if leave_policy in ["pause", "follow_current_room"] and away and not bool(config.get("follow_current_room", false)):
		state["paused"] = true
		_instances[instance_id] = state
		return
	state["paused"] = false
	state["elapsed"] = minf(float(config["duration_sec"]), float(state.get("elapsed", 0.0)) + delta)
	_dispatch_due_stages(instance_id, state)
	_try_finish_clear(instance_id, state)
	if bool(state.get("terminal", false)):
		return
	if float(state.get("elapsed", 0.0)) >= float(config["duration_sec"]):
		if str(config["completion"]) == "clear":
			_try_finish_clear(instance_id, state)
			if not bool(state.get("terminal", false)):
				_fail_instance(instance_id, state, "timer_expired_before_clear")
		elif str(config["completion"]) == "timer_and_clear":
			_try_finish_clear(instance_id, state)
			if not bool(state.get("terminal", false)):
				_fail_instance(instance_id, state, "timer_expired_before_clear")
		else:
			_finish_instance(instance_id, state, "completed")


func _dispatch_due_stages(instance_id: String, state: Dictionary) -> void:
	var config := state.get("config", {}) as Dictionary
	var stages: Array = config.get("stages", []) as Array
	var elapsed := float(state.get("elapsed", 0.0))
	for index in stages.size():
		var stage := stages[index] as Dictionary
		var stage_state := (state["stage_states"] as Array)[index] as Dictionary
		var threshold := float(stage.get("at_sec", 0.0))
		if stage.has("at_ratio"):
			threshold = float(stage["at_ratio"]) * float(config["duration_sec"])
		if not bool(stage_state.get("started", false)) and elapsed >= threshold:
			stage_state["started"] = true
			encounter_event_stage_started.emit(get_snapshot(instance_id), index)
		_spawn_pending_stage(instance_id, state, index)


func _spawn_pending_stage(instance_id: String, state: Dictionary, stage_index: int) -> void:
	var stage_state := (state["stage_states"] as Array)[stage_index] as Dictionary
	if not bool(stage_state.get("started", false)):
		return
	var config := state.get("config", {}) as Dictionary
	var max_alive := int(config.get("max_alive", 2147483647))
	var live := int(_host_call("encounter_event_live_count", [instance_id], 0))
	var capacity := maxi(0, max_alive - live)
	var pending_total := 0
	for monster_value in stage_state.get("pending", []) as Array:
		var monster := monster_value as Dictionary
		var requested := int(monster.get("count", 0))
		var spawned_for_monster := int(monster.get("_spawned", 0))
		var remaining := maxi(0, requested - spawned_for_monster)
		if remaining <= 0:
			continue
		if capacity <= 0:
			pending_total += remaining
			continue
		var amount := mini(remaining, capacity)
		# 只供本次调用推导 persistent_id 用：`<实例ID>:<spawn_serial>` 是本次派发的
		# 稳定前缀，Host 再拼批次内序号。用完立刻擦掉 —— 这既不是敌人数据、
		# 也不该顺着快照写进存档的阶段计划里。
		monster["_persistent_id_base"] = "%s:%d" % [
			instance_id,
			int(state.get("spawn_serial", 0))
		]
		var result := _host_call("encounter_event_spawn", [instance_id, str(state["room_id"]), monster, amount], {}) as Dictionary
		monster.erase("_persistent_id_base")
		var spawned := clampi(int(result.get("spawned", 0)), 0, amount)
		if not bool(result.get("ok", spawned > 0)) and spawned <= 0:
			_fail_instance(instance_id, state, str(result.get("reason", "spawn_failed")))
			return
		monster["_spawned"] = spawned_for_monster + spawned
		state["spawned"] = int(state.get("spawned", 0)) + spawned
		state["spawn_serial"] = int(state.get("spawn_serial", 0)) + spawned
		capacity -= spawned
		remaining = maxi(0, requested - int(monster["_spawned"]))
		pending_total += remaining
		if spawned < amount and bool(result.get("failed", false)):
			_fail_instance(instance_id, state, str(result.get("reason", "spawn_failed")))
			return
	stage_state["complete"] = pending_total == 0
	state["pending"] = _pending_total(state)
	_instances[instance_id] = state


func _try_finish_clear(instance_id: String, state: Dictionary) -> void:
	if bool(state.get("terminal", false)) or str(state.get("completion", "")) == "timer":
		return
	if int(state.get("pending", 0)) > 0:
		return
	var stages: Array = state.get("stage_states", []) as Array
	for stage_value in stages:
		if not bool((stage_value as Dictionary).get("complete", false)):
			return
	var live := int(_host_call("encounter_event_live_count", [instance_id], 0))
	if live > 0:
		return
	_finish_instance(instance_id, state, "completed")


func _finish_instance(instance_id: String, state: Dictionary, status: String) -> void:
	if bool(state.get("terminal", false)):
		return
	state["terminal"] = true
	state["status"] = status
	state["result"] = {
		"status": status, "requested": state["requested"], "spawned": state["spawned"],
		"pending": state.get("pending", 0), "dropped": state.get("dropped", 0),
		"escaped": state.get("escaped", 0), "partial_execution": state.get("partial_execution", false),
	}
	_apply_result_actions(state)
	_instances[instance_id] = state
	encounter_event_finished.emit(get_snapshot(instance_id))


func _fail_instance(instance_id: String, state: Dictionary, reason: String) -> void:
	if bool(state.get("terminal", false)):
		return
	(state["failed"] as Array).append(reason)
	state["status"] = "failed"
	state["partial_execution"] = int(state.get("spawned", 0)) > 0
	state["dropped"] = int(state.get("pending", 0))
	state["pending"] = 0
	_finish_instance(instance_id, state, "failed")


func _apply_result_actions(state: Dictionary, action_key := "on_completed") -> void:
	if bool(state.get("result_applied", false)):
		return
	if action_key == "on_completed" and state["status"] != "completed":
		return
	if not state.has("result"):
		state["result"] = {}
	for action_value in state.get("config", {}).get(action_key, []) as Array:
		var action := action_value as Dictionary
		var result := _host_call("encounter_event_apply_result", [action], {}) as Dictionary
		var row := action.duplicate(true)
		row["ok"] = bool(result.get("ok", false))
		if not row["ok"]:
			row["status"] = "failed"
			row["error"] = str(result.get("error", "result_action_failed"))
			(state["failed"] as Array).append("result_action_failed")
		else:
			row["status"] = "applied"
		(state["result_actions"] as Array).append(row)
	state["result_applied"] = true
	if not (state["failed"] as Array).is_empty():
		state["result_action_failed"] = true
		state["result"]["result_action_error"] = "result_action_failed"


func _pending_total(state: Dictionary) -> int:
	var total := 0
	for stage_value in state.get("stage_states", []) as Array:
		var stage_state := stage_value as Dictionary
		if not bool(stage_state.get("started", false)):
			continue
		for monster_value in stage_state.get("pending", []) as Array:
			var monster := monster_value as Dictionary
			total += maxi(0, int(monster.get("count", 0)) - int(monster.get("_spawned", 0)))
	return total


func _context(room_id: String, instance_id: String) -> Dictionary:
	var value: Variant = _host_call("encounter_event_context", [room_id, instance_id], {})
	return value as Dictionary if value is Dictionary else {}


func _check_prereqs(prereqs: Dictionary, context: Dictionary, room_id: String) -> Dictionary:
	if bool(prereqs.get("player_alive", true)) and not bool(context.get("player_alive", false)):
		return _reject("prereq_player_alive")
	if bool(prereqs.get("run_active", true)) and not bool(context.get("run_active", false)):
		return _reject("prereq_run_active")
	if prereqs.has("room_cleared") and bool(context.get("room_cleared", false)) != bool(prereqs["room_cleared"]):
		return _reject("prereq_room_cleared")
	if prereqs.has("current_room") and str(context.get("current_room_id", "")) != str(prereqs["current_room"]):
		return _reject("prereq_current_room")
	var flags := context.get("flags", {}) as Dictionary
	if prereqs.has("flags"):
		var wanted := prereqs["flags"] as Dictionary
		for key_value in wanted.keys():
			if not flags.has(key_value) or flags[key_value] != wanted[key_value]:
				return _reject("prereq_flag:%s" % str(key_value))
	if prereqs.has("completed_events"):
		var completed := context.get("completed_events", []) as Array
		for event_value in prereqs["completed_events"] as Array:
			if event_value not in completed:
				return _reject("prereq_completed_event:%s" % str(event_value))
	return {"ok": true, "room_id": room_id}


static func _validate_stage(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _reject("stage_invalid")
	var stage := value as Dictionary
	var unknown := _unknown_keys(stage, STAGE_KEYS)
	if not unknown.is_empty():
		return _reject("unknown_stage_field:%s" % ",".join(unknown))
	if stage.has("at_sec") == stage.has("at_ratio"):
		return _reject("stage_time_requires_exactly_one_of_at_sec_at_ratio")
	var at_sec := float(stage.get("at_sec", 0.0))
	var at_ratio := float(stage.get("at_ratio", 0.0))
	if stage.has("at_sec") and (at_sec < 0.0 or not is_finite(at_sec)):
		return _reject("stage_at_sec_invalid")
	if stage.has("at_ratio") and (at_ratio < 0.0 or at_ratio > 1.0 or not is_finite(at_ratio)):
		return _reject("stage_at_ratio_invalid")
	if not stage.get("monsters", null) is Array or (stage["monsters"] as Array).is_empty():
		return _reject("stage_monsters_invalid")
	var monsters: Array = []
	for monster_value in stage["monsters"] as Array:
		if not monster_value is Dictionary:
			return _reject("monster_invalid")
		var monster := monster_value as Dictionary
		var unknown_monster := _unknown_keys(monster, MONSTER_KEYS)
		if not unknown_monster.is_empty():
			return _reject("unknown_monster_field:%s" % ",".join(unknown_monster))
		var type_id := str(monster.get("type", ""))
		if type_id.is_empty() or (type_id != "elite" and type_id != "boss" and not MonsterInjector.is_authorable_enemy_type(type_id)):
			return _reject("enemy_type_not_authorable:%s" % type_id)
		if type_id == "boss":
			return _reject("boss_requires_dedicated_flow")
		var count := int(monster.get("count", 0))
		if count <= 0:
			return _reject("monster_count_invalid")
		var normalized_monster := monster.duplicate(true)
		normalized_monster["type"] = type_id
		normalized_monster["count"] = count
		monsters.append(normalized_monster)
	var normalized := stage.duplicate(true)
	normalized["monsters"] = monsters
	return {"ok": true, "stage": normalized}


static func _compile_convenience(config: Dictionary) -> Dictionary:
	var monsters_value: Variant = config.get("monsters", null)
	if not monsters_value is Array or (monsters_value as Array).is_empty():
		return _reject("stages_required")
	var interval := float(config.get("interval_sec", 0.0))
	var requested_total := int(config.get("total_count", config.get("count", 0)))
	if interval < 0.0:
		return _reject("convenience_schedule_invalid")
	var available_total := 0
	var raw_specs: Array = []
	for value in monsters_value as Array:
		if not value is Dictionary:
			return _reject("monster_invalid")
		var source := (value as Dictionary).duplicate(true)
		var type_id := str(source.get("type", ""))
		if type_id == "boss":
			return _reject("boss_requires_dedicated_flow")
		if type_id != "elite" and not MonsterInjector.is_authorable_enemy_type(type_id):
			return _reject("enemy_type_not_authorable:%s" % type_id)
		var count := int(source.get("count", 0))
		if count <= 0:
			return _reject("monster_count_invalid")
		available_total += count
		raw_specs.append({
			"type": type_id,
			"count": count,
			"content_id": str(source.get("content_id", "")),
		})
	var total := available_total if requested_total <= 0 else requested_total
	if total <= 0 or total > available_total:
		return _reject("convenience_total_count_invalid")
	var specs: Array = []
	var remaining := total
	for source_value in raw_specs:
		if remaining <= 0:
			break
		var source := source_value as Dictionary
		var amount := mini(remaining, int(source["count"]))
		specs.append({
			"type": source["type"],
			"count": amount,
			"content_id": source["content_id"],
		})
		remaining -= amount
	if remaining > 0:
		return _reject("convenience_total_count_underfilled")
	if interval <= 0.0:
		return {"ok": true, "stages": [{"at_sec": 0.0, "monsters": specs}]}
	var stages: Array = []
	var serial := 0
	for spec_value in specs:
		var spec := spec_value as Dictionary
		for _unit in int(spec["count"]):
			stages.append({
				"at_sec": float(serial) * interval,
				"monsters": [{
					"type": spec["type"],
					"count": 1,
					"content_id": spec["content_id"],
				}],
			})
			serial += 1
	return {"ok": true, "stages": stages}


static func _validate_actions(value: Variant) -> Dictionary:
	if not value is Array:
		return _reject("on_completed_invalid")
	var actions: Array = []
	for action_value in value as Array:
		if not action_value is Dictionary:
			return _reject("result_action_invalid")
		var action := action_value as Dictionary
		var unknown := _unknown_keys(action, ACTION_KEYS)
		if not unknown.is_empty():
			return _reject("unknown_result_action_field:%s" % ",".join(unknown))
		var type_id := str(action.get("type", ""))
		if type_id not in ["flag", "light", "hint"]:
			return _reject("result_action_not_allowed:%s" % type_id)
		if type_id == "flag" and str(action.get("key", "")).is_empty():
			return _reject("flag_action_key_required")
		if type_id == "light" and (str(action.get("room_id", "")).is_empty() or not action.has("on")):
			return _reject("light_action_invalid")
		if type_id == "hint" and not action.has("text"):
			return _reject("hint_action_text_required")
		actions.append(action.duplicate(true))
	return {"ok": true, "actions": actions}


static func _normalize_stage_states(row: Dictionary, config: Dictionary) -> Array:
	var saved: Variant = row.get("stage_states", [])
	var result: Array = []
	var stages := config.get("stages", []) as Array
	for index in stages.size():
		var stage := stages[index] as Dictionary
		var old := saved[index] as Dictionary if saved is Array and index < (saved as Array).size() and (saved as Array)[index] is Dictionary else {}
		var old_pending: Array = old.get("pending", []) as Array
		var consumed: Array[bool] = []
		consumed.resize(old_pending.size())
		consumed.fill(false)
		var pending: Array = []
		for monster_value in stage.get("monsters", []) as Array:
			var monster := (monster_value as Dictionary).duplicate(true)
			var matched_index := -1
			for old_index in old_pending.size():
				if consumed[old_index] or not old_pending[old_index] is Dictionary:
					continue
				var old_monster := old_pending[old_index] as Dictionary
				if str(old_monster.get("type", "")) != str(monster.get("type", "")):
					continue
				if str(old_monster.get("content_id", "")) != str(monster.get("content_id", "")):
					continue
				matched_index = old_index
				break
			if matched_index >= 0:
				consumed[matched_index] = true
				monster["_spawned"] = int((old_pending[matched_index] as Dictionary).get("_spawned", 0))
			else:
				monster["_spawned"] = 0
			pending.append(monster)
		var stage_complete := bool(old.get("complete", false)) and _stage_pending_total(pending) == 0
		result.append({
			"started": bool(old.get("started", false)),
			"complete": stage_complete,
			"pending": pending,
		})
	return result


static func _stage_pending_total(pending: Array) -> int:
	var total := 0
	for monster_value in pending:
		if not monster_value is Dictionary:
			continue
		var monster := monster_value as Dictionary
		total += maxi(0, int(monster.get("count", 0)) - int(monster.get("_spawned", 0)))
	return total


func _host_call(method: String, args: Array, fallback: Variant) -> Variant:
	if _host == null or not is_instance_valid(_host) or not _host.has_method(method):
		return fallback
	return _host.callv(method, args)


static func _unknown_keys(value: Dictionary, allowed: Array) -> Array[String]:
	var result: Array[String] = []
	for key_value in value.keys():
		var key := str(key_value)
		if key not in allowed:
			result.append(key)
	return result


static func _reject(error: String) -> Dictionary:
	return {"ok": false, "error": error}
