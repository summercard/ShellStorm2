class_name ProfileSaveService
extends RefCounted
## 基地长期档的版本封套、校验与旧档迁移。文件 IO 仍委托 AtomicJsonStore。

const MANIFEST_VERSION := 1
const CHECKSUM_ALGORITHM := "canonical_json_v3"
const LEGACY_CHECKSUM_ALGORITHM := "canonical_json_v2"


static func build_envelope(payload: Dictionary, revision: int, reason: String) -> Dictionary:
	# JSON只保留字符串对象键。先把运行时Dictionary规范成实际落盘形态，确保
	# 枚举整数键（例如武器装配槽3）与高精度数值不会在写入后改变校验输入。
	var stored_payload := _normalize_for_storage(payload)
	return {
		"manifest_version": MANIFEST_VERSION,
		"profile_schema": str(stored_payload.get("save_version", BaseData.SAVE_VERSION)),
		"revision": maxi(1, revision),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"reason": reason if not reason.is_empty() else "unspecified",
		"payload_checksum_algorithm": CHECKSUM_ALGORITHM,
		"payload_checksum": checksum_payload(stored_payload),
		"payload": stored_payload,
	}


static func checksum_payload(payload: Dictionary) -> String:
	return _canonical_json(payload).sha256_text()


static func _canonical_json(value: Variant) -> String:
	var value_type := typeof(value)
	# Godot JSON解析会把整数字面量恢复为float；校验必须忽略这种无语义类型差异。
	if value_type == TYPE_INT or value_type == TYPE_FLOAT:
		return String.num(float(value), 12)
	if value is Dictionary:
		var values_by_string_key: Dictionary = {}
		var keys: Array[String] = []
		for raw_key in (value as Dictionary).keys():
			var string_key := str(raw_key)
			if not values_by_string_key.has(string_key):
				keys.append(string_key)
			values_by_string_key[string_key] = (value as Dictionary).get(raw_key)
		keys.sort()
		var entries: Array[String] = []
		for key in keys:
			entries.append("%s:%s" % [JSON.stringify(key), _canonical_json(values_by_string_key[key])])
		return "{%s}" % ",".join(entries)
	if value is Array:
		var entries: Array[String] = []
		for child in value as Array:
			entries.append(_canonical_json(child))
		return "[%s]" % ",".join(entries)
	return JSON.stringify(value)


static func _normalize_for_json(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for raw_key in (value as Dictionary).keys():
			normalized[str(raw_key)] = _normalize_for_json((value as Dictionary).get(raw_key))
		return normalized
	if value is Array:
		var normalized: Array = []
		for child in value as Array:
			normalized.append(_normalize_for_json(child))
		return normalized
	return value


static func _normalize_for_storage(payload: Dictionary) -> Dictionary:
	var normalized := _normalize_for_json(payload) as Dictionary
	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(normalized))
	return json_round_trip as Dictionary if json_round_trip is Dictionary else normalized


static func is_valid_envelope(candidate: Dictionary) -> bool:
	if int(candidate.get("manifest_version", 0)) != MANIFEST_VERSION:
		return false
	var algorithm := str(candidate.get("payload_checksum_algorithm", ""))
	if algorithm not in [CHECKSUM_ALGORITHM, LEGACY_CHECKSUM_ALGORITHM]:
		return false
	var payload: Variant = candidate.get("payload", null)
	if not payload is Dictionary:
		return false
	var stored_checksum := str(candidate.get("payload_checksum", ""))
	return not stored_checksum.is_empty() and stored_checksum == checksum_payload(payload as Dictionary)


static func unpack(candidate: Dictionary) -> Dictionary:
	if is_valid_envelope(candidate):
		var needs_checksum_upgrade := (
			str(candidate.get("payload_checksum_algorithm", "")) != CHECKSUM_ALGORITHM
		)
		return {
			"success": true,
			"legacy": needs_checksum_upgrade,
			"revision": int(candidate.get("revision", 0)),
			"saved_at_unix": int(candidate.get("saved_at_unix", 0)),
			"reason": str(candidate.get("reason", "")),
			"payload": (candidate.get("payload", {}) as Dictionary).duplicate(true),
		}
	# canonical_json_v2曾把Dictionary键先转成字符串，再用字符串回查原字典。
	# 武器装配槽使用枚举整数键时，写入可以成功，但重载后的校验必然失败。
	# 只对可精确复算出该旧缺陷校验值的封套放行一次，随后BaseManager会以v3重存。
	if _is_recoverable_v2_numeric_assembly_slot_envelope(candidate):
		return {
			"success": true,
			"legacy": true,
			"revision": int(candidate.get("revision", 0)),
			"saved_at_unix": int(candidate.get("saved_at_unix", 0)),
			"reason": "legacy_numeric_assembly_slot_checksum_upgrade",
			"payload": _normalize_for_json(candidate.get("payload", {})) as Dictionary,
		}
	# v2还曾直接摘要写盘前Variant；少量高精度数值经JSON序列化后会发生无语义
	# 表示变化。只接受封套/载荷元数据完全互证且核心BaseData类型完整的候选，
	# 并立刻重存为v3。截断、非SHA-256格式或元数据不一致的损坏档不会进入此分支。
	if _is_structurally_coherent_v2_envelope(candidate):
		return {
			"success": true,
			"legacy": true,
			"revision": int(candidate.get("revision", 0)),
			"saved_at_unix": int(candidate.get("saved_at_unix", 0)),
			"reason": "legacy_v2_json_representation_upgrade",
			"payload": _normalize_for_storage(candidate.get("payload", {}) as Dictionary),
		}
	# 2026-08-06开发过渡封套曾直接对HashMap JSON求摘要，重载后键序/数值类型会
	# 改变校验结果。仅允许“旧档迁移”原因且没有算法标记的这一批封套一次性恢复。
	if (
		int(candidate.get("manifest_version", 0)) == MANIFEST_VERSION
		and candidate.get("payload", null) is Dictionary
		and str(candidate.get("payload_checksum_algorithm", "")).is_empty()
		and str(candidate.get("reason", "")) == "migrate_legacy_profile"
	):
		return {
			"success": true,
			"legacy": true,
			"revision": int(candidate.get("revision", 0)),
			"saved_at_unix": int(candidate.get("saved_at_unix", 0)),
			"reason": "legacy_checksum_upgrade",
			"payload": (candidate.get("payload", {}) as Dictionary).duplicate(true),
		}
	# 1.2及更早版本为裸 BaseData JSON；仅把带存档特征的字典当旧档。
	if candidate.has("save_version") or candidate.has("total_runs") or candidate.has("vault_items"):
		return {
			"success": true,
			"legacy": true,
			"revision": 0,
			"saved_at_unix": 0,
			"reason": "legacy_import",
			"payload": candidate.duplicate(true),
		}
	return {"success": false, "reason": "存档封套或校验值无效"}


static func _is_recoverable_v2_numeric_assembly_slot_envelope(candidate: Dictionary) -> bool:
	if int(candidate.get("manifest_version", 0)) != MANIFEST_VERSION:
		return false
	if str(candidate.get("payload_checksum_algorithm", "")) != LEGACY_CHECKSUM_ALGORITHM:
		return false
	var payload: Variant = candidate.get("payload", null)
	if not payload is Dictionary:
		return false
	var restored := _restore_numeric_assembly_slot_keys(payload)
	if not bool(restored.get("changed", false)):
		return false
	var legacy_checksum := _legacy_v2_canonical_json(restored.get("value", {})).sha256_text()
	return legacy_checksum == str(candidate.get("payload_checksum", ""))


static func _is_structurally_coherent_v2_envelope(candidate: Dictionary) -> bool:
	if int(candidate.get("manifest_version", 0)) != MANIFEST_VERSION:
		return false
	if str(candidate.get("payload_checksum_algorithm", "")) != LEGACY_CHECKSUM_ALGORITHM:
		return false
	var checksum := str(candidate.get("payload_checksum", "")).to_lower()
	if checksum.length() != 64:
		return false
	for index in checksum.length():
		if "0123456789abcdef".find(checksum[index]) < 0:
			return false
	var payload: Variant = candidate.get("payload", null)
	if not payload is Dictionary:
		return false
	var stored := payload as Dictionary
	if str(stored.get("save_version", "")).is_empty():
		return false
	if int(stored.get("save_revision", -1)) != int(candidate.get("revision", -2)):
		return false
	if str(stored.get("last_save_reason", "")) != str(candidate.get("reason", "")):
		return false
	if int(stored.get("last_saved_at_unix", -1)) != int(candidate.get("saved_at_unix", -2)):
		return false
	return (
		stored.get("vault_items", null) is Array
		and stored.get("active_run_snapshot", null) is Dictionary
		and stored.get("avatar_customization", null) is Dictionary
	)


static func _restore_numeric_assembly_slot_keys(value: Variant) -> Dictionary:
	if value is Array:
		var normalized_array: Array = []
		var array_changed := false
		for child in value as Array:
			var restored_child := _restore_numeric_assembly_slot_keys(child)
			normalized_array.append(restored_child.get("value"))
			array_changed = array_changed or bool(restored_child.get("changed", false))
		return {"value": normalized_array, "changed": array_changed}
	if not value is Dictionary:
		return {"value": value, "changed": false}
	var source := value as Dictionary
	var normalized_dictionary: Dictionary = {}
	var dictionary_changed := false
	for raw_key in source.keys():
		var restored_child := _restore_numeric_assembly_slot_keys(source.get(raw_key))
		normalized_dictionary[raw_key] = restored_child.get("value")
		dictionary_changed = dictionary_changed or bool(restored_child.get("changed", false))
	if source.has("node_type") and source.has("node_name") and source.get("slots") is Dictionary:
		var restored_slots: Dictionary = {}
		var slots := normalized_dictionary.get("slots", {}) as Dictionary
		for slot_key in slots.keys():
			var slot_key_text := str(slot_key)
			if slot_key_text.is_valid_int():
				restored_slots[int(slot_key_text)] = slots.get(slot_key)
				dictionary_changed = true
			else:
				restored_slots[slot_key] = slots.get(slot_key)
		normalized_dictionary["slots"] = restored_slots
	return {"value": normalized_dictionary, "changed": dictionary_changed}


static func _legacy_v2_canonical_json(value: Variant) -> String:
	var value_type := typeof(value)
	if value_type == TYPE_INT or value_type == TYPE_FLOAT:
		return String.num(float(value), 12)
	if value is Dictionary:
		var keys: Array[String] = []
		for raw_key in (value as Dictionary).keys():
			keys.append(str(raw_key))
		keys.sort()
		var entries: Array[String] = []
		for key in keys:
			entries.append("%s:%s" % [JSON.stringify(key), _legacy_v2_canonical_json((value as Dictionary).get(key))])
		return "{%s}" % ",".join(entries)
	if value is Array:
		var entries: Array[String] = []
		for child in value as Array:
			entries.append(_legacy_v2_canonical_json(child))
		return "[%s]" % ",".join(entries)
	return JSON.stringify(value)
