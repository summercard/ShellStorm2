class_name MainStoryProgress
extends RefCounted

const SCHEMA_VERSION := 1
const KEY_RARE_EARTH := "mq_key_rare_earth"
const KEY_MANOR := "mq_key_manor"
const KEY_HOTEL := "mq_key_hotel"
const KEY_SECTOR_04 := "mq_key_sector_04"

const BRIEFING_ID := "nar_main_031_green_briefing"
const BOSS_ID := "nar_main_032_monitor_audience"
const DEPOSIT_ID := "nar_main_033_key_install"

const STATE_NOT_ACQUIRED := "not_acquired"
const STATE_ACQUIRED := "acquired"
const STATE_DEPOSITED := "deposited"
const KEY_IDS: Array[String] = [KEY_RARE_EARTH, KEY_MANOR, KEY_HOTEL, KEY_SECTOR_04]

static func key_for_level(level_id: String) -> String:
	match level_id:
		"01", "expedition_01":
			return KEY_RARE_EARTH
		"03", "expedition_03":
			return KEY_MANOR
		"02", "expedition_02":
			return KEY_HOTEL
		"04", "expedition_04":
			return KEY_SECTOR_04
	return ""

static func installed_count(state: Dictionary) -> int:
	var keys := _keys_from_state(state)
	var count := 0
	for key_id in keys.keys():
		if key_state(state, str(key_id)) == STATE_DEPOSITED:
			count += 1
	return count

static func key_state(state: Dictionary, key_id: String) -> String:
	var keys := _keys_from_state(state)
	var record: Variant = keys.get(key_id, null)
	if not record is Dictionary:
		return STATE_NOT_ACQUIRED
	var value := str((record as Dictionary).get("state", STATE_NOT_ACQUIRED))
	return value if value in [STATE_ACQUIRED, STATE_DEPOSITED] else STATE_NOT_ACQUIRED

static func default_state() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "accepted": false, "keys": {}}

static func normalize_state(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return default_state()
	var source := raw as Dictionary
	var state := default_state()
	state["accepted"] = bool(source.get("accepted", false))
	var raw_keys: Variant = source.get("keys", {})
	if not raw_keys is Dictionary:
		return state
	for raw_key in (raw_keys as Dictionary).keys():
		var key_id := str(raw_key)
		if key_id not in KEY_IDS:
			continue
		var raw_record: Variant = (raw_keys as Dictionary).get(raw_key, null)
		if not raw_record is Dictionary:
			continue
		var record := _normalize_record(raw_record as Dictionary)
		if not record.is_empty():
			state["keys"][key_id] = record
	return state

static func validate_key_source(source: Dictionary) -> Dictionary:
	for field in ["level_id", "boss_content_id", "room_id", "chest_id", "run_id"]:
		if str(source.get(field, "")).is_empty():
			return {"success": false, "reason": "主线钥匙来源缺少 %s" % field}
	var level_id := str(source.get("level_id", ""))
	var run_id := str(source.get("run_id", ""))
	if level_id != "expedition_01" or run_id != "expedition_01":
		return {"success": false, "reason": "主线钥匙来源不是本轮数据库行动"}
	if str(source.get("boss_content_id", "")) != "boss_monitor002":
		return {"success": false, "reason": "主线钥匙来源首领不匹配"}

	var floor := _load_floor(level_id)
	var boss_room := {}
	for raw_room in floor.get("rooms", []):
		if not raw_room is Dictionary:
			continue
		var room := raw_room as Dictionary
		if str(room.get("room_id", "")) == str(source.get("room_id", "")):
			boss_room = room
			break
	if boss_room.is_empty() or str(boss_room.get("room_type", "")) != "BOSS_ROOM":
		return {"success": false, "reason": "主线钥匙来源房间不是数据库首领房"}
	if str(boss_room.get("boss_content_id", "")) != "boss_monitor002":
		return {"success": false, "reason": "首领房目录内容不匹配"}

	var level_plan := _load_level_plan(level_id)
	var clear_drops: Variant = level_plan.get("clear_drops", {})
	var boss_drop := (clear_drops as Dictionary).get("boss", {}) as Dictionary if clear_drops is Dictionary else {}
	if int(boss_drop.get("chest_count", 0)) <= 0:
		return {"success": false, "reason": "数据库首领目录未声明高级箱保底"}
	var expected_chest_id := "drop_%s" % str(source.get("room_id", ""))
	if str(source.get("chest_id", "")) != expected_chest_id:
		return {"success": false, "reason": "主线钥匙来源宝箱不是首领高级箱"}
	if str(source.get("chest_tier", "")) != "advanced":
		return {"success": false, "reason": "主线钥匙来源宝箱不是高级档"}
	return {"success": true}

static func _normalize_record(raw: Dictionary) -> Dictionary:
	var state := str(raw.get("state", STATE_NOT_ACQUIRED))
	if state not in [STATE_ACQUIRED, STATE_DEPOSITED]:
		return {}
	var record := {"state": state}
	if raw.has("acquired_at_unix"):
		record["acquired_at_unix"] = maxi(0, int(raw.get("acquired_at_unix", 0)))
	if raw.get("acquired_source", {}) is Dictionary:
		record["acquired_source"] = (raw.get("acquired_source", {}) as Dictionary).duplicate(true)
	if state == STATE_DEPOSITED and raw.has("deposited_at_unix"):
		record["deposited_at_unix"] = maxi(0, int(raw.get("deposited_at_unix", 0)))
	return record

static func _keys_from_state(state: Dictionary) -> Dictionary:
	var raw_keys: Variant = state.get("keys", state)
	return raw_keys as Dictionary if raw_keys is Dictionary else {}

static func _load_level_plan(level_id: String) -> Dictionary:
	var path := "res://data/level_plans/%s/level_plan.json" % level_id
	return _read_json(path)

static func _load_floor(level_id: String) -> Dictionary:
	var level_plan := _load_level_plan(level_id)
	var floors: Variant = level_plan.get("floors", [])
	if not floors is Array or (floors as Array).is_empty():
		return {}
	for raw_entry in floors as Array:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var relative := str(entry.get("plan", ""))
		if relative.is_empty():
			continue
		var floor := _read_json("res://data/level_plans/%s/%s" % [level_id, relative])
		if not floor.is_empty():
			return floor
	return {}

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}
