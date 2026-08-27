extends Node
## 12只唯一精英的跨局档案事实源：预约、成长、逃脱、死亡与夺械转译。
## 静态身份、投放与表现配置由 EliteContentCatalog 独立持有。

signal roster_changed(elite_id: String, record: Dictionary)
signal elite_reserved(elite_id: String, encounter_id: String)
signal elite_settled(elite_id: String, outcome: String, record: Dictionary)

const ROSTER_VERSION := 1
const VALID_STATES := [
	"Newborn", "Escaped", "Equipped", "Growing", "RevengeHunter",
	"RegionalBoss", "QuasiBoss", "Killed",
]

const DEFINITIONS := EliteContentCatalog.DEFINITIONS

var _definitions_by_id: Dictionary = {}
var _reservations_by_encounter: Dictionary = {}


func _ready() -> void:
	add_to_group("elite_archive")
	for definition in DEFINITIONS:
		_definitions_by_id[str(definition["elite_id"])] = definition.duplicate(true)
	_ensure_roster()
	_clear_stale_reservations()


func get_definition(elite_id: String) -> Dictionary:
	return (_definitions_by_id.get(elite_id, {}) as Dictionary).duplicate(true)


func get_all_elites() -> Array[Dictionary]:
	_ensure_roster()
	var result: Array[Dictionary] = []
	for definition in DEFINITIONS:
		var elite_id := str(definition["elite_id"])
		var merged := definition.duplicate(true)
		merged.merge(_get_record(elite_id), true)
		result.append(merged)
	return result


func get_record(elite_id: String) -> Dictionary:
	if not _definitions_by_id.has(elite_id):
		return {}
	var merged := get_definition(elite_id)
	merged.merge(_get_record(elite_id), true)
	return merged


func get_bounty_currency(elite_id: String) -> int:
	var definition := get_definition(elite_id)
	var record := _get_record(elite_id)
	return _bounty_currency(
		definition.get("growth_profile", {}) as Dictionary,
		clampi(int(record.get("bounty_reward_level", 0)), 0, 5)
	)


func select_and_reserve(seed_value: int, floor_number: int, encounter_id: String) -> Dictionary:
	_ensure_roster()
	if encounter_id.is_empty():
		return {"success": false, "reason": "missing_encounter_id"}
	if _reservations_by_encounter.has(encounter_id):
		return get_record(str(_reservations_by_encounter[encounter_id]))
	var eligible: Array[String] = []
	for definition in EliteContentCatalog.get_deployable_for_floor(floor_number, seed_value):
		var elite_id := str(definition["elite_id"])
		var record := _get_record(elite_id)
		if str(record.get("state", "Newborn")) == "Killed":
			continue
		var reserved_encounter := str(record.get("reserved_encounter_id", ""))
		if reserved_encounter.is_empty():
			eligible.append(elite_id)
	if eligible.is_empty():
		return {"success": false, "reason": "roster_exhausted_or_reserved"}
	eligible.sort()
	var mixed_seed := seed_value ^ hash(encounter_id) ^ (floor_number * 104729)
	var index := posmod(mixed_seed, eligible.size())
	var elite_id := eligible[index]
	if not reserve(elite_id, encounter_id, floor_number):
		return {"success": false, "reason": "reservation_failed"}
	return get_record(elite_id)


func reserve(elite_id: String, encounter_id: String, floor_number: int) -> bool:
	if not _definitions_by_id.has(elite_id) or encounter_id.is_empty():
		return false
	var record := _get_record(elite_id)
	var current := str(record.get("reserved_encounter_id", ""))
	if not current.is_empty() and current != encounter_id:
		return false
	var previous := record.duplicate(true)
	record["reserved_encounter_id"] = encounter_id
	record["reservation_confirmed"] = false
	record["last_floor_number"] = floor_number
	record["last_outcome"] = "reserved"
	_set_record(elite_id, record)
	_reservations_by_encounter[encounter_id] = elite_id
	if not _persist("elite_reserve:%s" % elite_id):
		_set_record(elite_id, previous)
		_reservations_by_encounter.erase(encounter_id)
		return false
	elite_reserved.emit(elite_id, encounter_id)
	return true


func confirm_reservation(elite_id: String, encounter_id: String) -> bool:
	var record := _get_record(elite_id)
	if str(record.get("reserved_encounter_id", "")) != encounter_id:
		return false
	if bool(record.get("reservation_confirmed", false)):
		return true
	var previous := record.duplicate(true)
	record["reservation_confirmed"] = true
	record["encounter_count"] = int(record.get("encounter_count", 0)) + 1
	record["last_encounter_at_unix"] = int(Time.get_unix_time_from_system())
	record["last_outcome"] = "active"
	_set_record(elite_id, record)
	if _persist("elite_confirm:%s" % elite_id):
		return true
	_set_record(elite_id, previous)
	return false


func settle(elite_id: String, encounter_id: String, outcome: String, context: Dictionary = {}) -> bool:
	if outcome not in ["killed", "escaped", "despawned"]:
		return false
	var record := _get_record(elite_id)
	if str(record.get("reserved_encounter_id", "")) != encounter_id:
		return false
	var previous := record.duplicate(true)
	if outcome == "killed":
		record["state"] = "Killed"
		record["death_count"] = int(record.get("death_count", 0)) + 1
		record["bounty_reward_level"] = maxi(1, int(record.get("bounty_reward_level", 0)))
	elif outcome == "escaped":
		var escape_count := int(record.get("escape_count", 0)) + 1
		var level := mini(12, int(record.get("level", 1)) + 1)
		record["escape_count"] = escape_count
		record["level"] = level
		record["state"] = _state_for_growth(level, escape_count)
		record["bounty_reward_level"] = mini(5, 1 + int(escape_count / 2))
		_capture_stolen_module(record, context.get("weapon_snapshot", {}) as Dictionary)
	else:
		record["state"] = str(record.get("state", "Newborn"))
	record["last_outcome"] = outcome
	record["last_settled_at_unix"] = int(Time.get_unix_time_from_system())
	record["reserved_encounter_id"] = ""
	record["reservation_confirmed"] = false
	var history := (record.get("history", {}) as Dictionary).duplicate(true)
	if bool(context.get("killed_player", false)):
		history["killed_player_count"] = int(history.get("killed_player_count", 0)) + 1
	history["last_context"] = _sanitize_context(context)
	record["history"] = history
	_set_record(elite_id, record)
	_reservations_by_encounter.erase(encounter_id)
	if not _persist("elite_settle:%s:%s" % [elite_id, outcome]):
		_set_record(elite_id, previous)
		_reservations_by_encounter[encounter_id] = elite_id
		return false
	roster_changed.emit(elite_id, get_record(elite_id))
	elite_settled.emit(elite_id, outcome, get_record(elite_id))
	return true


func apply_archive_to_enemy_config(config: Dictionary, elite_snapshot: Dictionary) -> Dictionary:
	if elite_snapshot.is_empty() or bool(elite_snapshot.get("success", true)) == false:
		return config
	var result := config.duplicate(true)
	var level := clampi(int(elite_snapshot.get("level", 1)), 1, 12)
	var growth_profile := (elite_snapshot.get("growth_profile", {}) as Dictionary).duplicate(true)
	var bounty_tier := clampi(int(elite_snapshot.get("bounty_reward_level", 0)), 0, 5)
	result["is_elite"] = true
	result["elite_id"] = str(elite_snapshot.get("elite_id", ""))
	result["elite_behavior_id"] = str(elite_snapshot.get("behavior_id", ""))
	result["elite_level"] = level
	result["encounter_instance_id"] = str(elite_snapshot.get("reserved_encounter_id", ""))
	result["enemy_type"] = str(elite_snapshot.get("base_enemy_id", result.get("enemy_type", "melee_chaser")))
	result["name"] = str(elite_snapshot.get("name", result.get("name", "唯一精英")))
	result["modifier_id_en"] = str(elite_snapshot.get("modifier_id", "Elite.Huge"))
	result["elite_growth_hp_mult"] = 1.0 + float(level - 1) * float(growth_profile.get("hp_per_level", 0.08))
	result["elite_growth_damage_mult"] = 1.0 + float(level - 1) * float(growth_profile.get("damage_per_level", 0.045))
	result["elite_growth_profile"] = growth_profile
	result["elite_translation_id"] = str(elite_snapshot.get("translation", ""))
	result["stolen_modules"] = (elite_snapshot.get("stolen_modules", []) as Array).duplicate(true)
	result["elite_archive_state"] = str(elite_snapshot.get("state", "Newborn"))
	result["elite_escape_count"] = int(elite_snapshot.get("escape_count", 0))
	result["elite_bounty_tier"] = bounty_tier
	result["elite_bounty_currency"] = _bounty_currency(growth_profile, bounty_tier)
	result["presentation_asset_id"] = str(elite_snapshot.get("presentation_asset_id", ""))
	result["presentation_scene"] = str(elite_snapshot.get("presentation_scene", ""))
	result["elite_health_bar_profile"] = (elite_snapshot.get("health_bar_profile", {}) as Dictionary).duplicate(true)
	result["elite_deployment_status"] = str(elite_snapshot.get("deployment_status", EliteContentCatalog.DESIGN_ONLY))
	result["elite_eligible_floor_numbers"] = (elite_snapshot.get("eligible_floor_numbers", []) as Array).duplicate()
	return result


func reset_roster_for_test() -> void:
	if BaseManager == null or BaseManager.data == null:
		return
	BaseManager.data.elite_archive_records.clear()
	_reservations_by_encounter.clear()
	_ensure_roster()


func _ensure_roster() -> void:
	if BaseManager == null:
		return
	BaseManager.call("_ensure_data")
	if BaseManager.data == null:
		return
	for definition in DEFINITIONS:
		var elite_id := str(definition["elite_id"])
		if not BaseManager.data.elite_archive_records.has(elite_id):
			BaseManager.data.elite_archive_records[elite_id] = _default_record(elite_id)


func _default_record(elite_id: String) -> Dictionary:
	var definition := get_definition(elite_id)
	return {
		"elite_id": elite_id, "archive_version": ROSTER_VERSION,
		"level": 1, "state": "Newborn",
		"modifiers": [str(definition.get("modifier_id", ""))], "stolen_modules": [],
		"encounter_count": 0, "escape_count": 0, "death_count": 0,
		"bounty_reward_level": 0, "reserved_encounter_id": "",
		"reservation_confirmed": false, "last_floor_number": 0,
		"last_outcome": "unseen", "last_encounter_at_unix": 0,
		"last_settled_at_unix": 0, "history": {"killed_player_count": 0},
	}


func _get_record(elite_id: String) -> Dictionary:
	_ensure_roster()
	if BaseManager == null or BaseManager.data == null:
		return _default_record(elite_id)
	return (BaseManager.data.elite_archive_records.get(elite_id, _default_record(elite_id)) as Dictionary).duplicate(true)


func _set_record(elite_id: String, record: Dictionary) -> void:
	BaseManager.data.elite_archive_records[elite_id] = record.duplicate(true)


func _persist(reason: String) -> bool:
	return BaseManager != null and BaseManager.save_base(reason)


func _clear_stale_reservations() -> void:
	if BaseManager == null or BaseManager.data == null:
		return
	var active_checkpoint := BaseManager.get_active_run_checkpoint()
	var active_run_id := str(active_checkpoint.get("checkpoint_id", ""))
	var changed := false
	for definition in DEFINITIONS:
		var elite_id := str(definition["elite_id"])
		var record := _get_record(elite_id)
		var encounter_id := str(record.get("reserved_encounter_id", ""))
		if encounter_id.is_empty():
			continue
		if not active_run_id.is_empty() and encounter_id.begins_with(active_run_id + ":"):
			_reservations_by_encounter[encounter_id] = elite_id
			continue
		record["reserved_encounter_id"] = ""
		record["reservation_confirmed"] = false
		record["last_outcome"] = "stale_reservation_released"
		_set_record(elite_id, record)
		changed = true
	if changed:
		_persist("elite_stale_reservation_cleanup")


func _state_for_growth(level: int, escape_count: int) -> String:
	if level >= 10: return "QuasiBoss"
	if level >= 8: return "RegionalBoss"
	if escape_count >= 4: return "RevengeHunter"
	if level >= 4: return "Growing"
	return "Escaped"


func _capture_stolen_module(record: Dictionary, weapon_snapshot: Dictionary) -> void:
	if weapon_snapshot.is_empty():
		return
	var content_id := str(weapon_snapshot.get(
		"content_id",
		weapon_snapshot.get("weapon_id", weapon_snapshot.get("gun_id", ""))
	))
	if content_id.is_empty():
		return
	if content_id.begins_with("bp_"):
		content_id = content_id.replace("bp_", "weapon_")
	var safe_traits: Array[String] = []
	for value in weapon_snapshot.get("bullet_tags", []) as Array:
		var bullet_trait := str(value)
		if bullet_trait in ["explosive", "piercing", "bounce", "homing"] and bullet_trait not in safe_traits:
			safe_traits.append(bullet_trait)
	var fire_rate := maxf(0.0, float(weapon_snapshot.get("fire_rate", 0.0)))
	var module := {
		"module_id": content_id,
		"source_kind": str(weapon_snapshot.get("source_kind", weapon_snapshot.get("weapon_kind", "gun_body"))),
		"content_version": int(weapon_snapshot.get("content_version", 1)),
		"translated_skill_id": str(get_definition(str(record.get("elite_id", ""))).get("translation", "")),
		"shot_count_budget": clampi(int(weapon_snapshot.get("projectile_count", 1)), 1, 3),
		"fire_rate_band": "fast" if fire_rate >= 5.0 else "standard" if fire_rate >= 2.0 else "slow",
		"bullet_traits": safe_traits,
	}
	var modules := (record.get("stolen_modules", []) as Array).duplicate(true)
	for existing in modules:
		if existing is Dictionary and str((existing as Dictionary).get("module_id", "")) == content_id:
			return
	modules.append(module)
	while modules.size() > 3:
		modules.pop_front()
	record["stolen_modules"] = modules
	if str(record.get("state", "")) not in ["RegionalBoss", "QuasiBoss"]:
		record["state"] = "Equipped"


func _bounty_currency(growth_profile: Dictionary, bounty_tier: int) -> int:
	if bounty_tier <= 0:
		return 0
	var rewards := growth_profile.get("bounty_currency_by_tier", []) as Array
	if rewards.is_empty():
		return bounty_tier * 40
	return maxi(0, int(rewards[mini(bounty_tier, rewards.size()) - 1]))


func _sanitize_context(context: Dictionary) -> Dictionary:
	return {
		"floor_number": int(context.get("floor_number", 0)),
		"room_id": str(context.get("room_id", "")),
		"killed_player": bool(context.get("killed_player", false)),
	}
