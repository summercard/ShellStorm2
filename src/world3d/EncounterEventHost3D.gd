class_name EncounterEventHost3D
extends RefCounted
## EncounterEventDirector3D 的 Dungeon 窄适配器。
## 所有场景私有状态访问集中在这里，Director 不反向读取 Dungeon。

var dungeon: Dungeon3D
var _elite_spawn_serial := 0

func _init(owner: Dungeon3D = null) -> void:
	dungeon = owner

func encounter_event_current_room_id() -> String:
	return dungeon._current_room_id if _valid() else ""

func encounter_event_room_busy(room_id: String) -> bool:
	if not _valid():
		return true
	for value in dungeon._encounter_event_director.get_snapshot_rows():
		if str(value.get("room_id", "")) == room_id and not bool(value.get("terminal", false)):
			return true
	return false

func encounter_event_context(room_id: String, _instance_id: String) -> Dictionary:
	if not _valid():
		return {}
	var room := dungeon._room_by_id.get(room_id) as DungeonRoom3D
	var flags: Dictionary = {}
	if NarrativeDirector != null and NarrativeDirector.has_method("get_flags_snapshot"):
		flags = NarrativeDirector.get_flags_snapshot()
	return {
		"player_alive": dungeon.player != null and dungeon.player.current_hp > 0,
		"run_active": not dungeon._completed,
		"current_room_id": dungeon._current_room_id,
		"room_cleared": room != null and room.cleared,
		"flags": flags,
		"completed_events": dungeon._encounter_event_completed_history.duplicate(),
	}

func encounter_event_spawn(instance_id: String, room_id: String, monster_spec: Dictionary, count: int) -> Dictionary:
	if not _valid():
		return {"ok": false, "reason": "host_unavailable"}
	var room := dungeon._room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not room.is_streamed():
		return {"ok": false, "reason": "room_not_streamed"}
	var configs: Array[Dictionary] = []
	var positions: Array = []
	for index in count:
		_elite_spawn_serial += 1
		var elite_reservation_id := "%s:elite:%d" % [instance_id, _elite_spawn_serial]
		var generated := dungeon._make_box_enemy(
			str(monster_spec.get("type", "")),
			maxi(1, dungeon.visual_theme.difficulty_rank),
			dungeon._record_index(room_id),
			room,
			elite_reservation_id
		)
		if generated.is_empty():
			_settle_unspawned_elites(configs)
			return {"ok": false, "reason": "spawn_config_failed"}
		# 精英的 encounter_instance_id 属于 EliteRosterService，不能覆盖；
		# Encounter Event 自己使用独立字段，普通怪才复用旧字段作为兼容值。
		generated["encounter_event_instance_id"] = instance_id
		if str(generated.get("encounter_instance_id", "")).is_empty():
			generated["encounter_instance_id"] = instance_id
		generated["encounter_event_reserved"] = true
		generated["room_id"] = room_id
		var persistent_base := str(monster_spec.get("_persistent_id_base", ""))
		if not persistent_base.is_empty():
			generated["persistent_id"] = "%s:%d" % [persistent_base, index]
		if monster_spec.has("content_id"):
			generated["content_id"] = monster_spec["content_id"]
		configs.append(generated)
		positions.append(room.spawn_point_for_index(index))
	var spawned := dungeon._spawn_enemy_batch(room, configs, true, false, positions)
	if spawned < 0:
		_settle_unspawned_elites(configs)
		return {"ok": false, "reason": "spawn_position_failed", "failed": true}
	if spawned != count:
		_settle_unspawned_elites(configs, spawned)
		return {"ok": false, "spawned": spawned, "reason": "spawn_partial", "failed": true}
	return {"ok": true, "spawned": spawned}

func encounter_event_live_count(instance_id: String) -> int:
	if not _valid():
		return 0
	var count := 0
	var instantiated_rooms: Dictionary = {}
	for room_id_value in dungeon._enemy_nodes_by_room.keys():
		var room_id := str(room_id_value)
		var room_count := 0
		for node in dungeon._enemy_nodes_by_room[room_id] as Array:
			var enemy := node as Enemy3D
			if enemy != null and is_instance_valid(enemy) and _encounter_owner_id(enemy.get_enemy_data()) == instance_id:
				room_count += 1
		if room_count > 0:
			instantiated_rooms[room_id] = true
			count += room_count
		# A hibernated room has no Enemy3D nodes; its stable runtime snapshot is
		# the authoritative live set until the room is streamed again.
		if room_count == 0 and not _room_is_streamed(room_id):
			var runtime_state := dungeon._segment_runtime_state.get(room_id, {}) as Dictionary
			for enemy_state_value in runtime_state.get("enemies", []) as Array:
				var enemy_state := enemy_state_value as Dictionary
				var enemy_data := enemy_state.get("enemy_data", {}) as Dictionary
				if _encounter_owner_id(enemy_data) == instance_id:
					count += 1
	for request_value in dungeon._reserved_room_spawns.values():
			for request in request_value as Array:
				for config in (request as Dictionary).get("configs", []) as Array:
					if _encounter_owner_id(config as Dictionary) == instance_id:
						count += 1
	for entry_value in dungeon._pending_delayed_spawns.values():
			for entry in entry_value as Array:
				var payload := (entry as Dictionary).get("config", {}) as Dictionary
				if _encounter_owner_id(payload) == instance_id:
					count += 1
	return count

## 事件猎杀：把玩家位置持续押给**事件归属的已实例化敌人**。
##
## 为什么只认已实例化的：预约 / 延迟队列里的条目还没有 `Enemy3D` 节点，
## 没有"记录"可写。它们实到之后的下一帧就会被盖上（本方法由 Director 每帧调用）
## —— 与其在三处队列里各写一遍、把同一事实存三份，不如让它晚一帧。
##
## 为什么走 `MonsterAIManager.set_hunt_target` 而不是直接改敌人字段：
## 感知、记忆、开火令牌的唯一真源都在那边；这里只做"谁算这个事件的怪"的判定。
func encounter_event_hunt(instance_id: String) -> Dictionary:
	if not _valid():
		return {"ok": false, "reason": "host_unavailable"}
	var target := _hunt_target()
	if target == null:
		return {"ok": false, "reason": "no_hunt_target"}
	if MonsterAIManager == null:
		return {"ok": false, "reason": "ai_manager_unavailable"}
	var stamped := 0
	for room_id_value in dungeon._enemy_nodes_by_room.keys():
		for node in dungeon._enemy_nodes_by_room[room_id_value] as Array:
			var enemy := node as Enemy3D
			if enemy == null or not is_instance_valid(enemy):
				continue
			if _encounter_owner_id(enemy.get_enemy_data()) != instance_id:
				continue
			if MonsterAIManager.set_hunt_target(enemy, target):
				stamped += 1
	return {"ok": true, "stamped": stamped}


## 猎杀目标 = 活着的玩家。死了就没有目标可押 —— 返回 null 让上层如实以"没有目标"收场，
## 而不是押给一具尸体（那会让怪围着尸体转）。
func _hunt_target() -> Node3D:
	var candidate := dungeon.player
	if candidate == null or not is_instance_valid(candidate):
		return null
	if float(candidate.current_hp) <= 0.0:
		return null
	return candidate as Node3D


func encounter_event_despawn(instance_id: String, _reason: String) -> Dictionary:
	if not _valid():
		return {"ok": false, "error": "host_unavailable"}
	var removed := 0
	for room_id_value in dungeon._enemy_nodes_by_room.keys():
		var room_id := str(room_id_value)
		var members := dungeon._enemy_nodes_by_room[room_id] as Array
		for value in members.duplicate():
			var enemy := value as Enemy3D
			if enemy == null or not is_instance_valid(enemy):
				continue
			var enemy_data := enemy.get_enemy_data()
			if _encounter_owner_id(enemy_data) != instance_id:
				continue
			_settle_elite_for_despawn(enemy_data, room_id)
			members.erase(enemy)
			dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - 1)
			if MonsterAIManager != null:
				MonsterAIManager.unregister_enemy(enemy)
			enemy.set_process(false)
			enemy.queue_free()
			removed += 1
	for room_id_value in dungeon._reserved_room_spawns.keys():
		var room_id := str(room_id_value)
		var requests := dungeon._reserved_room_spawns[room_id] as Array
		for request_value in requests.duplicate():
			var request := request_value as Dictionary
			var configs := request.get("configs", []) as Array
			var kept_configs: Array = []
			var kept_positions: Array = []
			for index in configs.size():
				var config := configs[index] as Dictionary
				if _encounter_owner_id(config) == instance_id:
					dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - 1)
					_settle_unspawned_elites([config])
					removed += 1
					continue
				kept_configs.append(config)
				var positions := request.get("positions", []) as Array
				if index < positions.size():
					kept_positions.append(positions[index])
			if kept_configs.is_empty():
				requests.erase(request)
			else:
				request["configs"] = kept_configs
				request["positions"] = kept_positions
		if requests.is_empty():
			dungeon._reserved_room_spawns.erase(room_id)
	for room_id_value in dungeon._pending_delayed_spawns.keys():
		var room_id := str(room_id_value)
		var entries := dungeon._pending_delayed_spawns[room_id] as Array
		for entry_value in entries.duplicate():
			var entry := entry_value as Dictionary
			var payload := entry.get("config", {}) as Dictionary
			if _encounter_owner_id(payload) != instance_id:
				continue
			entries.erase(entry)
			dungeon._alive_by_room[room_id] = maxi(0, int(dungeon._alive_by_room.get(room_id, 0)) - 1)
			_settle_unspawned_elites([payload])
			removed += 1
		if entries.is_empty():
			dungeon._pending_delayed_spawns.erase(room_id)
	return {"ok": true, "removed": removed}

func encounter_event_apply_result(action: Dictionary) -> Dictionary:
	if not _valid():
		return {"ok": false, "error": "host_unavailable"}
	match str(action.get("type", "")):
		"flag":
			if NarrativeDirector == null or not NarrativeDirector.has_method("set_flag"):
				return {"ok": false, "error": "result_action_failed"}
			NarrativeDirector.set_flag(str(action["key"]), action.get("value", true))
			return {"ok": true}
		"hint":
			if dungeon.status_label == null:
				return {"ok": false, "error": "result_action_failed"}
			dungeon.status_label.text = str(action["text"])
			return {"ok": true}
		"light":
			# 房间灯光的所有权仍在房间系统（`DungeonRoom3D.set_room_light_on()`），
			# 这里只做转发 —— 不自己开关 Light3D、也不猜房间有没有灯。
			# 房间不存在或没有可控灯 ⇒ 如实返回失败，不假装成功。
			var light_room := dungeon._room_by_id.get(str(action.get("room_id", ""))) as DungeonRoom3D
			if light_room == null or not light_room.has_method("set_room_light_on"):
				return {"ok": false, "error": "light_room_unavailable"}
			if not bool(light_room.call("set_room_light_on", bool(action.get("on", true)))):
				return {"ok": false, "error": "light_room_unavailable"}
			return {"ok": true}
	return {"ok": false, "error": "result_action_failed"}

func _settle_unspawned_elites(configs: Array, from_index := 0) -> void:
	if EliteRosterService == null:
		return
	for index in range(clampi(from_index, 0, configs.size()), configs.size()):
		var config := configs[index] as Dictionary
		_settle_elite_for_despawn(config, str(config.get("room_id", "")))

func _settle_elite_for_despawn(enemy_data: Dictionary, room_id: String) -> void:
	var elite_id := str(enemy_data.get("elite_id", ""))
	var encounter_id := str(enemy_data.get("encounter_instance_id", ""))
	if elite_id.is_empty() or encounter_id.is_empty() or EliteRosterService == null:
		return
	EliteRosterService.settle(elite_id, encounter_id, "despawned", {
		"floor_number": int(enemy_data.get("floor_number", enemy_data.get("floor", 0))),
		"room_id": room_id,
	})

func _encounter_owner_id(enemy_data: Dictionary) -> String:
	var event_id := str(enemy_data.get("encounter_event_instance_id", ""))
	return event_id if not event_id.is_empty() else str(enemy_data.get("encounter_instance_id", ""))

func _room_is_streamed(room_id: String) -> bool:
	var room := dungeon._room_by_id.get(room_id) as DungeonRoom3D
	return room != null and is_instance_valid(room) and room.is_streamed()

func _valid() -> bool:
	return dungeon != null and is_instance_valid(dungeon)
