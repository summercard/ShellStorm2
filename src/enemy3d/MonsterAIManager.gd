extends Node
## 全局怪物 AI 调度器：统一感知、记忆、目标合法性、群体令牌和可诊断快照。

signal decision_changed(enemy_instance_id: int, decision: Dictionary)

const VISION_SCRIPT := preload("res://src/enemy3d/MonsterVisionSystem3D.gd")
const UPDATE_INTERVAL_MSEC := 110
const MEMORY_DURATION_MSEC := 1150
const DAMAGE_AGGRO_DURATION_MSEC := 8000
const SOUND_MEMORY_DURATION_MSEC := 3200
const ALLY_ALERT_DURATION_MSEC := 1500
const STIMULUS_LIMIT := 12
const TARGET_SWITCH_MARGIN := 1.15
const ALERT_SHARE_RADIUS := 10.0
const MAX_MELEE_TOKENS_PER_TARGET := 2
const MAX_RANGED_TOKENS_PER_TARGET := 2
const SOUND_DEDUPE_MSEC := 500
const MAX_EVALUATIONS_PER_TICK := 8
const LIGHT_HUNTER_KINDS := ["melee_chaser", "shielded", "exploder", "boss"]
const DARKNESS_SEEKER_KINDS := ["ranged_caster", "summoner", "ambusher"]
const RANGED_KINDS := ["ranged_caster", "summoner", "boss"]

var _vision: MonsterVisionSystem3D = VISION_SCRIPT.new()
var _records: Dictionary = {}
var _attack_tokens: Dictionary = {}
var _stimulus_sequence := 0
var _evaluation_count := 0
var _cache_hit_count := 0
var _maximum_updates_in_tick := 0
var _updates_this_tick := 0
var _update_tick_msec := -1


func register_enemy(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var instance_id := enemy.get_instance_id()
	_records[instance_id] = _new_record(enemy)
	if GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.register_node(
			enemy,
			GameplaySpatialRegistry3D.KIND_ENEMY,
			str(enemy.get("room_id"))
		)


func unregister_enemy(enemy: Node3D) -> void:
	if enemy == null:
		return
	release_attack_token(enemy)
	_records.erase(enemy.get_instance_id())
	if GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.unregister_node(enemy)


func update_enemy_spatial(enemy: Node3D) -> void:
	if enemy != null and GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.update_node(enemy, str(enemy.get("room_id")))


func evaluate_enemy(enemy: CharacterBody3D, force := false) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return _empty_decision()
	var instance_id := enemy.get_instance_id()
	if not _records.has(instance_id):
		register_enemy(enemy)
	var record := _records[instance_id] as Dictionary
	var now := Time.get_ticks_msec()
	if not force and now < int(record.get("next_update_msec", 0)):
		_cache_hit_count += 1
		return (record.get("decision", _empty_decision()) as Dictionary).duplicate(true)
	# 统一限制每个16ms窗口的重感知数量；超额对象顺延到下一帧，
	# 受击/灯光等 force 刷新仍保持即时，不牺牲玩法响应。
	if not force and _current_tick_update_count(now) >= MAX_EVALUATIONS_PER_TICK:
		record["next_update_msec"] = now + 1
		_records[instance_id] = record
		_cache_hit_count += 1
		return (record.get("decision", _empty_decision()) as Dictionary).duplicate(true)
	_track_update_budget(now)
	_evaluation_count += 1
	record["next_update_msec"] = now + UPDATE_INTERVAL_MSEC
	_update_spatial_record(enemy, record)
	_prune_stimuli(record, now)
	var decision := _build_decision(enemy, record, now)
	var previous := record.get("decision", {}) as Dictionary
	decision["decision_sequence"] = int(record.get("decision_sequence", 0)) + 1
	decision["decision_age"] = 0.0
	record["decision_sequence"] = int(decision["decision_sequence"])
	record["decision"] = decision
	_records[instance_id] = record
	if str(previous.get("awareness", "")) != str(decision.get("awareness", "")):
		decision_changed.emit(instance_id, decision.duplicate(true))
	return decision.duplicate(true)


func force_refresh_enemy(enemy: CharacterBody3D) -> Dictionary:
	return evaluate_enemy(enemy, true)


func invalidate_enemy(enemy: CharacterBody3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not _records.has(enemy.get_instance_id()):
		register_enemy(enemy)
	var record := _records[enemy.get_instance_id()] as Dictionary
	record["next_update_msec"] = 0
	_records[enemy.get_instance_id()] = record


func notify_enemy_attacked(enemy: CharacterBody3D, attacker: Node3D) -> void:
	if enemy == null or attacker == null or not is_instance_valid(enemy) or not is_instance_valid(attacker):
		return
	if not attacker.is_in_group("player_3d"):
		return
	var instance_id := enemy.get_instance_id()
	if not _records.has(instance_id):
		register_enemy(enemy)
	var now := Time.get_ticks_msec()
	var record := _records[instance_id] as Dictionary
	record["forced_target_instance_id"] = attacker.get_instance_id()
	record["forced_target_until_msec"] = now + DAMAGE_AGGRO_DURATION_MSEC
	record["last_known_target_position"] = attacker.global_position
	record["last_contact_msec"] = now
	record["next_update_msec"] = 0
	_append_stimulus(
		record, "damage_contact", attacker.global_position, attacker.get_instance_id(),
		1.0, DAMAGE_AGGRO_DURATION_MSEC, true, "actual_damage"
	)
	_records[instance_id] = record
	_share_ally_alert(enemy, attacker.global_position, now, instance_id)


func broadcast_sound_stimulus(
	world_position: Vector3,
	radius: float,
	stimulus_kind := "interaction",
	_source: Node3D = null
) -> int:
	var alerted := 0
	var now := Time.get_ticks_msec()
	var candidates: Array[Node3D] = []
	if GameplaySpatialRegistry3D != null:
		candidates = GameplaySpatialRegistry3D.query_radius(
			world_position, radius, [GameplaySpatialRegistry3D.KIND_ENEMY]
		)
	else:
		for instance_id_value in _records.keys():
			var fallback := instance_from_id(int(instance_id_value)) as Node3D
			if fallback != null:
				candidates.append(fallback)
	for candidate in candidates:
		var enemy := candidate as CharacterBody3D
		if enemy == null or not is_instance_valid(enemy) or float(enemy.get("current_hp")) <= 0.0:
			continue
		var offset := world_position - enemy.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if absf(offset.y) > 4.5 or distance > radius:
			continue
		if not _sound_reaches_enemy(enemy, world_position, radius, distance):
			continue
		var instance_id := enemy.get_instance_id()
		if not _records.has(instance_id):
			register_enemy(enemy)
		var record := _records[instance_id] as Dictionary
		var signature := "%s:%d:%d" % [stimulus_kind, roundi(world_position.x * 2.0), roundi(world_position.z * 2.0)]
		if (
			signature == str(record.get("last_sound_signature", ""))
			and now - int(record.get("last_sound_msec", -100000)) < SOUND_DEDUPE_MSEC
		):
			continue
		record["last_sound_signature"] = signature
		record["last_sound_msec"] = now
		record["sound_stimulus_position"] = world_position
		record["sound_stimulus_kind"] = stimulus_kind
		record["sound_until_msec"] = now + SOUND_MEMORY_DURATION_MSEC
		record["next_update_msec"] = 0
		_append_stimulus(
			record, "sound_contact", world_position, 0,
			clampf(1.0 - distance / maxf(radius, 0.01), 0.1, 1.0),
			SOUND_MEMORY_DURATION_MSEC, true, stimulus_kind
		)
		_records[instance_id] = record
		if enemy.has_method("activate_from_stimulus"):
			enemy.call("activate_from_stimulus", world_position, stimulus_kind)
		alerted += 1
	return alerted


func request_attack_token(enemy: Node3D, target: Node3D, channel := "melee") -> bool:
	if enemy == null or target == null or not is_instance_valid(enemy) or not is_instance_valid(target):
		return false
	var enemy_id := enemy.get_instance_id()
	var target_id := target.get_instance_id()
	var normalized_channel := "ranged" if channel == "ranged" else "melee"
	var existing := _records.get(enemy_id, {}) as Dictionary
	if (
		int(existing.get("attack_token_target_id", 0)) == target_id
		and str(existing.get("attack_token_channel", "")) == normalized_channel
	):
		return true
	var target_tokens := _attack_tokens.get(target_id, {"melee": {}, "ranged": {}}) as Dictionary
	var holders := target_tokens.get(normalized_channel, {}) as Dictionary
	var limit := MAX_RANGED_TOKENS_PER_TARGET if normalized_channel == "ranged" else MAX_MELEE_TOKENS_PER_TARGET
	_prune_token_holders(holders)
	if holders.size() >= limit:
		return false
	release_attack_token(enemy)
	holders[enemy_id] = weakref(enemy)
	target_tokens[normalized_channel] = holders
	_attack_tokens[target_id] = target_tokens
	existing["attack_token_target_id"] = target_id
	existing["attack_token_channel"] = normalized_channel
	_records[enemy_id] = existing
	return true


func release_attack_token(enemy: Node) -> void:
	if enemy == null:
		return
	var enemy_id := enemy.get_instance_id()
	var record := _records.get(enemy_id, {}) as Dictionary
	var target_id := int(record.get("attack_token_target_id", 0))
	var channel := str(record.get("attack_token_channel", ""))
	if target_id > 0 and _attack_tokens.has(target_id):
		var target_tokens := _attack_tokens[target_id] as Dictionary
		var holders := target_tokens.get(channel, {}) as Dictionary
		holders.erase(enemy_id)
		target_tokens[channel] = holders
		if (target_tokens.get("melee", {}) as Dictionary).is_empty() and (target_tokens.get("ranged", {}) as Dictionary).is_empty():
			_attack_tokens.erase(target_id)
		else:
			_attack_tokens[target_id] = target_tokens
	record["attack_token_target_id"] = 0
	record["attack_token_channel"] = ""
	if _records.has(enemy_id):
		_records[enemy_id] = record


func get_enemy_snapshot(enemy: Node3D) -> Dictionary:
	if enemy == null or not _records.has(enemy.get_instance_id()):
		return _empty_decision()
	var record := _records[enemy.get_instance_id()] as Dictionary
	var snapshot := (record.get("decision", _empty_decision()) as Dictionary).duplicate(true)
	snapshot["memory"] = (record.get("stimuli", []) as Array).duplicate(true)
	snapshot["attack_token_channel"] = str(record.get("attack_token_channel", ""))
	snapshot["attack_token_target_id"] = int(record.get("attack_token_target_id", 0))
	snapshot["room_id"] = str(record.get("room_id", ""))
	snapshot["floor_index"] = int(record.get("floor_index", 0))
	return snapshot


func get_manager_snapshot() -> Dictionary:
	_prune_records()
	var token_counts := {"melee": 0, "ranged": 0}
	for target_tokens_value in _attack_tokens.values():
		var target_tokens := target_tokens_value as Dictionary
		for channel in ["melee", "ranged"]:
			var holders := target_tokens.get(channel, {}) as Dictionary
			_prune_token_holders(holders)
			token_counts[channel] = int(token_counts[channel]) + holders.size()
	return {
		"registered_enemy_count": _records.size(),
		"evaluation_count": _evaluation_count,
		"cache_hit_count": _cache_hit_count,
		"update_interval_msec": UPDATE_INTERVAL_MSEC,
		"maximum_updates_in_tick": _maximum_updates_in_tick,
		"max_evaluations_per_tick": MAX_EVALUATIONS_PER_TICK,
		"attack_tokens": token_counts,
		"target_token_buckets": _attack_tokens.size(),
		"spatial_registry": GameplaySpatialRegistry3D.get_snapshot() if GameplaySpatialRegistry3D != null else {},
	}


func _build_decision(enemy: CharacterBody3D, record: Dictionary, now: int) -> Dictionary:
	var enemy_kind := str(enemy.get("enemy_kind"))
	var policy := "darkness_seeker" if enemy_kind in DARKNESS_SEEKER_KINDS else "light_hunter"
	var illumination := enemy.call("get_illumination_snapshot") as Dictionary if enemy.has_method("get_illumination_snapshot") else {}
	var light_state := str(illumination.get("illumination_state", "darkness"))
	var vision_range := _vision_range_for_light_state(light_state)
	var forced_target_id := int(record.get("forced_target_instance_id", 0))
	if forced_target_id > 0 and now <= int(record.get("forced_target_until_msec", 0)):
		var forced_target := instance_from_id(forced_target_id) as Node3D
		if _target_is_legal(enemy, forced_target):
			record["last_known_target_position"] = forced_target.global_position
			return _decision(
				"damage_contact", forced_target_id, false, forced_target.global_position,
				forced_target.global_position, "damage", policy, true, "combat", vision_range,
				"damage_target_locked", 1000.0
			)
		record["forced_target_instance_id"] = 0
		record["forced_target_until_msec"] = 0

	var selected := _select_visible_target(enemy, record, vision_range)
	if not selected.is_empty():
		var visible_target := selected.get("target") as Node3D
		var visible_position := visible_target.global_position
		record["last_known_target_position"] = visible_position
		record["last_contact_msec"] = now
		record["selected_target_instance_id"] = visible_target.get_instance_id()
		record["selected_target_score"] = float(selected.get("score", 0.0))
		_append_stimulus(record, "visual_contact", visible_position, visible_target.get_instance_id(), 1.0, MEMORY_DURATION_MSEC, true, "vision")
		_share_ally_alert(enemy, visible_position, now, enemy.get_instance_id())
		return _decision(
			"visual_contact", visible_target.get_instance_id(), true, visible_position,
			visible_position, "vision", policy, true, "combat", vision_range,
			str(selected.get("reason_code", "nearest_visible_target")), float(selected.get("score", 0.0))
		)

	var light_kind := str(illumination.get("dominant_light_kind", "none"))
	var light_instance_id := int(illumination.get("dominant_light_instance_id", 0))
	var light := instance_from_id(light_instance_id) as Light3D if light_instance_id > 0 else null
	var light_position := light.global_position if is_instance_valid(light) else enemy.global_position
	var previous_light_state := str(record.get("last_illumination_state", "darkness"))
	var previous_light_id := int(record.get("last_light_instance_id", 0))
	record["last_illumination_state"] = light_state
	record["last_light_instance_id"] = light_instance_id
	if light_state == "artificial_light" and light_kind == "flashlight":
		var owner_player := _resolve_light_owner(light)
		if _target_is_legal(enemy, owner_player):
			record["last_known_target_position"] = owner_player.global_position
			record["last_contact_msec"] = now
			if policy == "light_hunter":
				return _decision(
					"flashlight_contact", owner_player.get_instance_id(), false,
					owner_player.global_position, owner_player.global_position,
					"flashlight", policy, true, "combat", vision_range,
					"flashlight_owner_confirmed", 850.0
				)
			return _decision(
				"seek_darkness", 0, false, Vector3.ZERO,
				_find_dark_position(enemy, light_position), "flashlight", policy, false,
				"combat", vision_range, "light_survival_priority", 900.0
			)

	if light_state == "sunlight" and policy == "darkness_seeker":
		return _decision(
			"seek_darkness", 0, false, Vector3.ZERO,
			_find_dark_position(enemy, light_position), "sun", policy, false,
			"combat", vision_range, "sun_survival_priority", 950.0
		)
	if light_state == "artificial_light" and light_kind != "flashlight" and policy == "darkness_seeker":
		return _decision(
			"seek_darkness", 0, false, Vector3.ZERO,
			_find_dark_position(enemy, light_position), light_kind, policy, false,
			"alert", vision_range, "room_light_survival", 700.0
		)

	var players := enemy.get_tree().get_nodes_in_group("player_3d")
	var proximity := _vision.find_proximity_player(enemy, players)
	if bool(proximity.get("detected", false)):
		return _decision(
			"proximity_contact", 0, false, Vector3.ZERO,
			proximity.get("stimulus_position", enemy.global_position) as Vector3,
			"proximity", policy, false, "alert", vision_range,
			"occlusion_checked_proximity", 400.0
		)
	if now <= int(record.get("sound_until_msec", 0)):
		return _decision(
			"sound_contact", 0, false, Vector3.ZERO,
			record.get("sound_stimulus_position", enemy.global_position) as Vector3,
			str(record.get("sound_stimulus_kind", "interaction")), policy, false,
			"alert", vision_range, "sound_position_only", 320.0
		)
	if now <= int(record.get("ally_alert_until_msec", 0)):
		return _decision(
			"ally_alert", 0, false, Vector3.ZERO,
			record.get("ally_alert_position", enemy.global_position) as Vector3,
			"ally", policy, false, "alert", vision_range,
			"limited_ally_share", 280.0
		)
	if light_state == "artificial_light" and light_kind != "flashlight":
		if previous_light_state != "artificial_light" or previous_light_id != light_instance_id:
			record["room_light_search_until_msec"] = now + 4000
		if now < int(record.get("room_light_search_until_msec", 0)):
			return _decision(
				"room_light_search", 0, false, Vector3.ZERO,
				_room_light_search_position(enemy, light_position), light_kind, policy,
				false, "alert", vision_range, "room_light_has_no_player_target", 240.0
			)

	var last_contact := int(record.get("last_contact_msec", -100000))
	if now - last_contact <= MEMORY_DURATION_MSEC:
		return _decision(
			"lost_contact", 0, false, Vector3.ZERO,
			record.get("last_known_target_position", enemy.global_position) as Vector3,
			"memory", policy, false, "alert", vision_range,
			"last_known_position_only", 200.0
		)
	return _decision(
		"unaware", 0, false, Vector3.ZERO, Vector3.ZERO, "none", policy,
		false, "idle", vision_range, "no_valid_stimulus", 0.0
	)


func _select_visible_target(enemy: CharacterBody3D, record: Dictionary, vision_range: float) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var current_id := int(record.get("selected_target_instance_id", 0))
	for value in enemy.get_tree().get_nodes_in_group("player_3d"):
		var player := value as Node3D
		if not _target_is_legal(enemy, player):
			continue
		var vision := _vision.evaluate_target(enemy, player, vision_range)
		if not bool(vision.get("visible", false)):
			continue
		var distance := float(vision.get("distance", vision_range))
		var score := 500.0 + maxf(0.0, vision_range - distance) * 8.0
		candidates.append({"target": player, "score": score, "distance": distance})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["score"]), float(b["score"])):
			return int((a["target"] as Node3D).get_instance_id()) < int((b["target"] as Node3D).get_instance_id())
		return float(a["score"]) > float(b["score"])
	)
	var best := candidates[0] as Dictionary
	# 对当前候选使用与此帧相同的未加成评分；只有新目标高出15%才切换。
	# 不使用旧帧分数，也不额外给当前目标加常量，避免迟滞被距离变化永久锁死。
	for candidate in candidates:
		var target := candidate.get("target") as Node3D
		if target.get_instance_id() != current_id:
			continue
		if (
			(best.get("target") as Node3D).get_instance_id() != current_id
			and float(best.get("score", 0.0)) < float(candidate.get("score", 0.0)) * TARGET_SWITCH_MARGIN
		):
			candidate["reason_code"] = "target_lock_hysteresis"
			return candidate
	best["reason_code"] = "highest_threat_visible"
	return best


func _target_is_legal(enemy: CharacterBody3D, target: Node3D) -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if not target.is_in_group("player_3d") or float(target.get("current_hp")) <= 0.0:
		return false
	if absf(target.global_position.y - enemy.global_position.y) > 4.5:
		return false
	var enemy_room := str(enemy.get("room_id"))
	if enemy_room.is_empty():
		return true
	var cursor: Node = enemy
	while cursor != null:
		if cursor is Dungeon3D:
			var current_room := str(cursor.get("_current_room_id"))
			return current_room.is_empty() or current_room == enemy_room
		cursor = cursor.get_parent()
	return true


func _share_ally_alert(source: CharacterBody3D, position: Vector3, now: int, source_id: int) -> void:
	if GameplaySpatialRegistry3D == null:
		return
	var source_room := str(source.get("room_id"))
	var room_filter: Array[String] = []
	if not source_room.is_empty():
		room_filter.append(source_room)
	for candidate in GameplaySpatialRegistry3D.query_radius(
		position, ALERT_SHARE_RADIUS, [GameplaySpatialRegistry3D.KIND_ENEMY], room_filter
	):
		var ally := candidate as CharacterBody3D
		if ally == null or ally == source or float(ally.get("current_hp")) <= 0.0:
			continue
		var ally_id := ally.get_instance_id()
		if not _records.has(ally_id):
			register_enemy(ally)
		var record := _records[ally_id] as Dictionary
		if int(record.get("last_ally_source_id", 0)) == source_id and now - int(record.get("last_ally_alert_msec", -100000)) < SOUND_DEDUPE_MSEC:
			continue
		record["last_ally_source_id"] = source_id
		record["last_ally_alert_msec"] = now
		record["ally_alert_position"] = position
		record["ally_alert_until_msec"] = now + ALLY_ALERT_DURATION_MSEC
		record["next_update_msec"] = 0
		_append_stimulus(record, "ally_alert", position, 0, 0.55, ALLY_ALERT_DURATION_MSEC, false, "limited_share")
		_records[ally_id] = record


func _append_stimulus(
	record: Dictionary,
	type_id: String,
	position: Vector3,
	source_instance_id: int,
	confidence: float,
	duration_msec: int,
	line_of_sight: bool,
	reason_code: String
) -> void:
	var now := Time.get_ticks_msec()
	var stimuli := record.get("stimuli", []) as Array
	_stimulus_sequence += 1
	stimuli.append({
		"stimulus_id": _stimulus_sequence,
		"type": type_id,
		"source_instance_id": source_instance_id,
		"world_position": position,
		"created_at_msec": now,
		"expires_at_msec": now + duration_msec,
		"line_of_sight": line_of_sight,
		"confidence": clampf(confidence, 0.0, 1.0),
		"reason_code": reason_code,
	})
	while stimuli.size() > STIMULUS_LIMIT:
		stimuli.pop_front()
	record["stimuli"] = stimuli


func _prune_stimuli(record: Dictionary, now: int) -> void:
	var live: Array = []
	for value in record.get("stimuli", []):
		var stimulus := value as Dictionary
		if now <= int(stimulus.get("expires_at_msec", 0)):
			live.append(stimulus)
	record["stimuli"] = live


func _update_spatial_record(enemy: CharacterBody3D, record: Dictionary) -> void:
	record["room_id"] = str(enemy.get("room_id"))
	record["floor_index"] = int(round(-enemy.global_position.y / 9.0))
	update_enemy_spatial(enemy)


func _vision_range_for_light_state(light_state: String) -> float:
	match light_state:
		"sunlight":
			return MonsterVisionSystem3D.SUNLIGHT_VISION_RANGE
		"artificial_light":
			return MonsterVisionSystem3D.ARTIFICIAL_LIGHT_VISION_RANGE
		_:
			return MonsterVisionSystem3D.DARKNESS_VISION_RANGE


func _sound_reaches_enemy(enemy: CharacterBody3D, position: Vector3, radius: float, distance: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		enemy.global_position + Vector3.UP * 0.55,
		position + Vector3.UP * 0.55,
		1,
		[enemy.get_rid()]
	)
	query.collide_with_areas = false
	var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_position := hit.get("position", enemy.global_position) as Vector3
	if hit_position.distance_to(position + Vector3.UP * 0.55) <= 0.9:
		return true
	return distance <= radius * 0.45


func _find_dark_position(enemy: CharacterBody3D, light_position: Vector3) -> Vector3:
	if enemy.has_method("find_nearby_dark_position"):
		var candidate := enemy.call("find_nearby_dark_position", 4.8, 8) as Vector3
		if candidate != Vector3.ZERO and _movement_path_clear(enemy, candidate):
			return candidate
	return _fallback_away_position(enemy, light_position)


func _fallback_away_position(enemy: CharacterBody3D, light_position: Vector3) -> Vector3:
	var away := enemy.global_position - light_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		var angle := float(enemy.get_instance_id() % 17) / 17.0 * TAU
		away = Vector3(cos(angle), 0.0, sin(angle))
	return enemy.global_position + away.normalized() * 3.2


func _room_light_search_position(enemy: CharacterBody3D, light_position: Vector3) -> Vector3:
	var toward_light := light_position - enemy.global_position
	toward_light.y = 0.0
	if toward_light.length_squared() <= 0.001:
		var angle := float(enemy.get_instance_id() % 23) / 23.0 * TAU
		toward_light = Vector3(cos(angle), 0.0, sin(angle))
	return enemy.global_position + toward_light.normalized() * minf(3.0, toward_light.length())


func _movement_path_clear(enemy: CharacterBody3D, target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		enemy.global_position + Vector3.UP * 0.45,
		target + Vector3.UP * 0.45,
		1,
		[enemy.get_rid()]
	)
	query.collide_with_areas = false
	return enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _resolve_light_owner(light: Light3D) -> Node3D:
	if not is_instance_valid(light):
		return null
	var owner_id := int(light.get_meta("gameplay_light_owner_instance_id", 0))
	var owner_node := instance_from_id(owner_id) as Node3D if owner_id > 0 else null
	if is_instance_valid(owner_node) and owner_node.is_in_group("player_3d"):
		return owner_node
	var ancestor := light.get_parent()
	while ancestor != null:
		if ancestor is Node3D and ancestor.is_in_group("player_3d"):
			return ancestor as Node3D
		ancestor = ancestor.get_parent()
	return null


func _new_record(enemy: Node3D) -> Dictionary:
	return {
		"next_update_msec": Time.get_ticks_msec() + int(enemy.get_instance_id() % UPDATE_INTERVAL_MSEC),
		"last_contact_msec": -100000,
		"last_known_target_position": enemy.global_position,
		"last_illumination_state": "darkness",
		"last_light_instance_id": 0,
		"room_light_search_until_msec": 0,
		"sound_until_msec": 0,
		"sound_stimulus_position": Vector3.ZERO,
		"sound_stimulus_kind": "none",
		"last_sound_signature": "",
		"last_sound_msec": -100000,
		"ally_alert_until_msec": 0,
		"ally_alert_position": Vector3.ZERO,
		"forced_target_instance_id": 0,
		"forced_target_until_msec": 0,
		"selected_target_instance_id": 0,
		"selected_target_score": 0.0,
		"attack_token_target_id": 0,
		"attack_token_channel": "",
		"room_id": str(enemy.get("room_id")),
		"floor_index": int(round(-enemy.global_position.y / 9.0)),
		"stimuli": [],
		"decision_sequence": 0,
		"decision": _empty_decision(),
	}


func _decision(
	awareness: String,
	target_instance_id: int,
	target_visible: bool,
	target_position: Vector3,
	stimulus_position: Vector3,
	stimulus_kind: String,
	policy: String,
	line_of_sight: bool,
	engagement := "idle",
	vision_range := MonsterVisionSystem3D.DEFAULT_VISION_RANGE,
	reason_code := "unspecified",
	threat_score := 0.0
) -> Dictionary:
	return {
		"awareness": awareness,
		"target_instance_id": target_instance_id,
		"target_visible": target_visible,
		"target_position": target_position,
		"last_known_target_position": target_position,
		"stimulus_position": stimulus_position,
		"stimulus_kind": stimulus_kind,
		"vision_range": vision_range,
		"vision_angle_degrees": MonsterVisionSystem3D.DEFAULT_VISION_ANGLE_DEGREES,
		"line_of_sight": line_of_sight,
		"light_response_policy": policy,
		"engagement": engagement,
		"reason_code": reason_code,
		"threat_score": threat_score,
		"decision_age": 0.0,
	}


func _empty_decision() -> Dictionary:
	return _decision(
		"unaware", 0, false, Vector3.ZERO, Vector3.ZERO, "none",
		"light_hunter", false, "idle", MonsterVisionSystem3D.DEFAULT_VISION_RANGE,
		"no_valid_stimulus", 0.0
	)


func _prune_records() -> void:
	for instance_id_value in _records.keys().duplicate():
		var enemy := instance_from_id(int(instance_id_value)) as Node
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			_records.erase(instance_id_value)


func _prune_token_holders(holders: Dictionary) -> void:
	for enemy_id_value in holders.keys().duplicate():
		var reference := holders[enemy_id_value] as WeakRef
		var enemy := reference.get_ref() as Node if reference != null else null
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			holders.erase(enemy_id_value)


func _track_update_budget(now: int) -> void:
	var tick := now / 16
	if tick != _update_tick_msec:
		_maximum_updates_in_tick = maxi(_maximum_updates_in_tick, _updates_this_tick)
		_update_tick_msec = tick
		_updates_this_tick = 0
	_updates_this_tick += 1


func _current_tick_update_count(now: int) -> int:
	return _updates_this_tick if now / 16 == _update_tick_msec else 0
