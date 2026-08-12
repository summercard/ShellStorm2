extends Node
## 全局怪物 AI 管理器：统一感知、记忆、光照刺激和策略；不直接移动或攻击怪物。

signal decision_changed(enemy_instance_id: int, decision: Dictionary)

const VISION_SCRIPT := preload("res://src/enemy3d/MonsterVisionSystem3D.gd")
const UPDATE_INTERVAL_MSEC := 110
const MEMORY_DURATION_MSEC := 1150
const DAMAGE_AGGRO_DURATION_MSEC := 8000
const SOUND_MEMORY_DURATION_MSEC := 3200
const LIGHT_HUNTER_KINDS := ["melee_chaser", "shielded", "exploder", "boss"]
const DARKNESS_SEEKER_KINDS := ["ranged_caster", "summoner", "ambusher"]

var _vision: MonsterVisionSystem3D = VISION_SCRIPT.new()
var _records: Dictionary = {}


func register_enemy(enemy: Node3D) -> void:
	if enemy == null:
		return
	var instance_id := enemy.get_instance_id()
	_records[instance_id] = _new_record(enemy)


func unregister_enemy(enemy: Node3D) -> void:
	if enemy != null:
		_records.erase(enemy.get_instance_id())


func evaluate_enemy(enemy: CharacterBody3D, force := false) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return _empty_decision()
	var instance_id := enemy.get_instance_id()
	if not _records.has(instance_id):
		register_enemy(enemy)
	var record: Dictionary = _records[instance_id]
	var now := Time.get_ticks_msec()
	if not force and now < int(record.get("next_update_msec", 0)):
		return (record.get("decision", _empty_decision()) as Dictionary).duplicate(true)
	record["next_update_msec"] = now + UPDATE_INTERVAL_MSEC
	var decision := _build_decision(enemy, record, now)
	var previous := record.get("decision", {}) as Dictionary
	record["decision"] = decision
	_records[instance_id] = record
	if str(previous.get("awareness", "")) != str(decision.get("awareness", "")):
		decision_changed.emit(instance_id, decision.duplicate(true))
	return decision.duplicate(true)


func force_refresh_enemy(enemy: CharacterBody3D) -> Dictionary:
	return evaluate_enemy(enemy, true)


func notify_enemy_attacked(enemy: CharacterBody3D, attacker: Node3D) -> void:
	if enemy == null or attacker == null or not is_instance_valid(enemy) or not is_instance_valid(attacker):
		return
	if not attacker.is_in_group("player_3d"):
		return
	var instance_id := enemy.get_instance_id()
	if not _records.has(instance_id):
		register_enemy(enemy)
	var record: Dictionary = _records[instance_id]
	record["forced_target_instance_id"] = attacker.get_instance_id()
	record["forced_target_until_msec"] = Time.get_ticks_msec() + DAMAGE_AGGRO_DURATION_MSEC
	record["last_known_target_position"] = attacker.global_position
	record["last_contact_msec"] = Time.get_ticks_msec()
	record["next_update_msec"] = 0
	_records[instance_id] = record


func broadcast_sound_stimulus(
	world_position: Vector3,
	radius: float,
	stimulus_kind := "interaction",
	_source: Node3D = null
) -> int:
	var alerted := 0
	var now := Time.get_ticks_msec()
	for instance_id in _records.keys():
		var record: Dictionary = _records[instance_id]
		var enemy := instance_from_id(int(instance_id)) as CharacterBody3D
		if not is_instance_valid(enemy) or float(enemy.get("current_hp")) <= 0.0:
			continue
		var offset := world_position - enemy.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if absf(offset.y) > 4.5 or distance > radius:
			continue
		if not _sound_reaches_enemy(enemy, world_position, radius, distance):
			continue
		record["sound_stimulus_position"] = world_position
		record["sound_stimulus_kind"] = stimulus_kind
		record["sound_until_msec"] = now + SOUND_MEMORY_DURATION_MSEC
		record["next_update_msec"] = 0
		_records[instance_id] = record
		if enemy.has_method("activate_from_stimulus"):
			enemy.call("activate_from_stimulus", world_position, stimulus_kind)
		alerted += 1
	return alerted


func get_enemy_snapshot(enemy: Node3D) -> Dictionary:
	if enemy == null or not _records.has(enemy.get_instance_id()):
		return _empty_decision()
	return (_records[enemy.get_instance_id()].get("decision", _empty_decision()) as Dictionary).duplicate(true)


func _build_decision(enemy: CharacterBody3D, record: Dictionary, now: int) -> Dictionary:
	var enemy_kind := str(enemy.get("enemy_kind"))
	var policy := "darkness_seeker" if enemy_kind in DARKNESS_SEEKER_KINDS else "light_hunter"
	var illumination := {}
	if enemy.has_method("get_illumination_snapshot"):
		illumination = enemy.call("get_illumination_snapshot") as Dictionary
	var light_state := str(illumination.get("illumination_state", "darkness"))
	var vision_range := _vision_range_for_light_state(light_state)
	var forced_target_id := int(record.get("forced_target_instance_id", 0))
	if forced_target_id > 0 and now <= int(record.get("forced_target_until_msec", 0)):
		var forced_target := instance_from_id(forced_target_id) as Node3D
		if is_instance_valid(forced_target) and forced_target.is_in_group("player_3d") and float(forced_target.get("current_hp")) > 0.0:
			record["last_known_target_position"] = forced_target.global_position
			return _decision(
				"damage_contact", forced_target_id, false, forced_target.global_position,
				forced_target.global_position, "damage", policy, true, "combat", vision_range
			)
	var players := enemy.get_tree().get_nodes_in_group("player_3d")
	var vision_result := _vision.find_visible_player(enemy, players, vision_range)
	if bool(vision_result.get("visible", false)):
		var visible_id := int(vision_result.get("target_instance_id", 0))
		var visible_position := vision_result.get("target_position", enemy.global_position) as Vector3
		record["last_known_target_position"] = visible_position
		record["last_contact_msec"] = now
		return _decision(
			"visual_contact", visible_id, true, visible_position, visible_position,
			"vision", policy, true, "combat", vision_range
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
		if owner_player != null:
			record["last_known_target_position"] = owner_player.global_position
			record["last_contact_msec"] = now
			if policy == "light_hunter":
				return _decision(
					"flashlight_contact", owner_player.get_instance_id(), false,
					owner_player.global_position, owner_player.global_position,
					"flashlight", policy, true, "combat", vision_range
				)
			var dark_position := _find_dark_position(enemy, light_position)
			return _decision(
				"seek_darkness", 0, false, Vector3.ZERO, dark_position,
				"flashlight", policy, false, "combat", vision_range
			)

	if light_state == "sunlight" and policy == "darkness_seeker":
		return _decision(
			"seek_darkness", 0, false, Vector3.ZERO,
			_find_dark_position(enemy, light_position), "sun", policy, false, "combat", vision_range
		)
	if light_state == "artificial_light" and light_kind != "flashlight" and policy == "darkness_seeker":
		return _decision(
			"seek_darkness", 0, false, Vector3.ZERO,
			_find_dark_position(enemy, light_position), light_kind, policy, false, "alert", vision_range
		)

	# 接近和交互声比普通房间灯变化更具体，但仍只属于警惕层。
	var proximity := _vision.find_proximity_player(enemy, players)
	if bool(proximity.get("detected", false)):
		return _decision(
			"proximity_contact", 0, false, Vector3.ZERO,
			proximity.get("stimulus_position", enemy.global_position) as Vector3,
			"proximity", policy, false, "alert", vision_range
		)
	if now <= int(record.get("sound_until_msec", 0)):
		return _decision(
			"sound_contact", 0, false, Vector3.ZERO,
			record.get("sound_stimulus_position", enemy.global_position) as Vector3,
			str(record.get("sound_stimulus_kind", "interaction")), policy, false, "alert", vision_range
		)
	if light_state == "artificial_light" and light_kind != "flashlight":
		if previous_light_state != "artificial_light" or previous_light_id != light_instance_id:
			record["room_light_search_until_msec"] = now + 4000
		if now >= int(record.get("room_light_search_until_msec", 0)):
			return _decision("unaware", 0, false, Vector3.ZERO, Vector3.ZERO, "none", policy, false, "idle", vision_range)
		var search_position := _room_light_search_position(enemy, light_position)
		return _decision(
			"room_light_search", 0, false, Vector3.ZERO, search_position,
			light_kind, policy, false, "alert", vision_range
		)

	var last_contact := int(record.get("last_contact_msec", -100000))
	if now - last_contact <= MEMORY_DURATION_MSEC:
		var remembered := record.get("last_known_target_position", enemy.global_position) as Vector3
		return _decision(
			"lost_contact", 0, false, Vector3.ZERO, remembered,
			"memory", policy, false, "alert", vision_range
		)
	return _decision("unaware", 0, false, Vector3.ZERO, Vector3.ZERO, "none", policy, false, "idle", vision_range)


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
	# 射线终点附近命中被开启的容器/门自身，不应误判成隔墙。
	var hit_position := hit.get("position", enemy.global_position) as Vector3
	if hit_position.distance_to(position + Vector3.UP * 0.55) <= 0.9:
		return true
	return distance <= radius * 0.45


func _find_dark_position(enemy: CharacterBody3D, light_position: Vector3) -> Vector3:
	if not enemy.has_method("find_nearby_dark_position"):
		return _fallback_away_position(enemy, light_position)
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
	var from := enemy.global_position + Vector3.UP * 0.45
	var to := target + Vector3.UP * 0.45
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [enemy.get_rid()])
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
		"forced_target_instance_id": 0,
		"forced_target_until_msec": 0,
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
	vision_range := MonsterVisionSystem3D.DEFAULT_VISION_RANGE
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
		"decision_age": 0.0,
	}


func _empty_decision() -> Dictionary:
	return _decision("unaware", 0, false, Vector3.ZERO, Vector3.ZERO, "none", "light_hunter", false, "idle")
