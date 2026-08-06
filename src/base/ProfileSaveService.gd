class_name ProfileSaveService
extends RefCounted
## 基地长期档的版本封套、校验与旧档迁移。文件 IO 仍委托 AtomicJsonStore。

const MANIFEST_VERSION := 1
const CHECKSUM_ALGORITHM := "canonical_json_v2"


static func build_envelope(payload: Dictionary, revision: int, reason: String) -> Dictionary:
	var stored_payload := payload.duplicate(true)
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
		var keys: Array[String] = []
		for raw_key in (value as Dictionary).keys():
			keys.append(str(raw_key))
		keys.sort()
		var entries: Array[String] = []
		for key in keys:
			entries.append("%s:%s" % [JSON.stringify(key), _canonical_json((value as Dictionary).get(key))])
		return "{%s}" % ",".join(entries)
	if value is Array:
		var entries: Array[String] = []
		for child in value as Array:
			entries.append(_canonical_json(child))
		return "[%s]" % ",".join(entries)
	return JSON.stringify(value)


static func is_valid_envelope(candidate: Dictionary) -> bool:
	if int(candidate.get("manifest_version", 0)) != MANIFEST_VERSION:
		return false
	var payload: Variant = candidate.get("payload", null)
	if not payload is Dictionary:
		return false
	var stored_checksum := str(candidate.get("payload_checksum", ""))
	return not stored_checksum.is_empty() and stored_checksum == checksum_payload(payload as Dictionary)


static func unpack(candidate: Dictionary) -> Dictionary:
	if is_valid_envelope(candidate):
		return {
			"success": true,
			"legacy": false,
			"revision": int(candidate.get("revision", 0)),
			"saved_at_unix": int(candidate.get("saved_at_unix", 0)),
			"reason": str(candidate.get("reason", "")),
			"payload": (candidate.get("payload", {}) as Dictionary).duplicate(true),
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
