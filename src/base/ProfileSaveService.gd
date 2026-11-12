class_name ProfileSaveService
extends RefCounted
## 基地长期档的版本封套、校验与旧档迁移。文件 IO 仍委托 AtomicJsonStore。

const MANIFEST_VERSION := 1
const CHECKSUM_ALGORITHM := "canonical_json_v3"
const LEGACY_CHECKSUM_ALGORITHM := "canonical_json_v2"

# 单槽不可变快照供各线程复用；锁只保护整快照引用，不覆盖计算或 IO。
static var _write_cache_mutex := Mutex.new()
static var _write_cache_snapshot: Dictionary = {"path": "", "fields": {}}


static func read_profile(path: String) -> Dictionary:
	var accepted := {}
	AtomicJsonStore.load_dictionary(path, func(candidate: Dictionary) -> bool:
		var decoded := unpack(candidate)
		if not bool(decoded.get("success", false)):
			return false
		accepted.assign(decoded)
		return true
	)
	return accepted


## Takes ownership of payload. No Node, mutable BaseData or scene-tree access.
static func write_profile(path: String, payload: Dictionary, baseline: int, reason: String, fail_write: bool, previous_digest := "", previous_revision := -1) -> Dictionary:
	var disk_revision := previous_revision
	# Only identical bytes can reuse the revision confirmed by our last successful read-back.
	if previous_digest.is_empty() or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != previous_digest:
		disk_revision = int(read_profile(path).get("revision", -1))
	if disk_revision > baseline:
		push_error("[BaseManager] Refusing stale save: memory revision %d < disk revision %d (%s)" % [baseline, disk_revision, reason])
		return {"success":false, "stale":true}
	var revision := baseline + 1
	var timestamp := int(Time.get_unix_time_from_system())
	payload["save_revision"] = revision
	payload["last_saved_at_unix"] = timestamp
	payload["last_save_reason"] = reason
	var serialized := _serialize_for_write(path, payload, revision, reason)
	if fail_write or not AtomicJsonStore.save_json_text(path, serialized):
		return {"success":false}
	var digest := serialized.sha256_text()
	if FileAccess.get_sha256(path) != digest:
		push_error("[BaseManager] Save write completed but read-back validation failed")
		return {"success":false}
	return {"success":true, "revision":revision, "time":timestamp, "reason":reason, "file_digest":digest}


static func build_envelope(payload: Dictionary, revision: int, reason: String) -> Dictionary:
	# JSON只保留字符串对象键。先把运行时Dictionary规范成实际落盘形态，确保
	# 枚举整数键（例如武器装配槽3）与高精度数值不会在写入后改变校验输入。
	var stored_payload := _normalize_for_storage(payload)
	return _stored_envelope(stored_payload, revision, reason, checksum_payload(stored_payload))


static func _stored_envelope(stored_payload: Dictionary, revision: int, reason: String, checksum: String) -> Dictionary:
	return {
		"manifest_version": MANIFEST_VERSION,
		"profile_schema": str(stored_payload.get("save_version", BaseData.SAVE_VERSION)),
		"revision": maxi(1, revision),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"reason": reason if not reason.is_empty() else "unspecified",
		"payload_checksum_algorithm": CHECKSUM_ALGORITHM,
		"payload_checksum": checksum,
		"payload": stored_payload,
	}


# 已发布的快照、字段、原始深副本和规范化子树均不再修改，也不向外部暴露。
static func _serialize_for_write(path: String, payload: Dictionary, revision: int, reason: String) -> String:
	_write_cache_mutex.lock()
	var snapshot := _write_cache_snapshot
	_write_cache_mutex.unlock()
	var cached_fields: Dictionary = snapshot.fields if snapshot.path == path else {}
	for key in payload:
		if not key is String:
			return JSON.stringify(build_envelope(payload, revision, reason))
	var keys: Array = payload.keys()
	keys.sort()
	var next_fields: Dictionary = {}
	var stored_payload: Dictionary = {}
	var canonical_entries: Array[String] = []
	var encoded_entries: Array[String] = []
	for key in keys:
		var raw: Variant = payload[key]
		var field: Dictionary = cached_fields.get(key, {})
		var trail: Array[String] = [key]
		field = _write_chunk(raw, field, trail, 1 if key == "active_run_snapshot" else 0)
		if field.is_empty():
			return JSON.stringify(build_envelope(payload, revision, reason))
		next_fields[key] = field
		stored_payload[key] = field.stored
		var encoded_key := JSON.stringify(key)
		canonical_entries.append(encoded_key + ":" + str(field.canonical))
		encoded_entries.append(encoded_key + ":" + str(field.encoded))
	var checksum := ("{" + ",".join(canonical_entries) + "}").sha256_text()
	var header := _stored_envelope(stored_payload, revision, reason, checksum)
	header.erase("payload")
	var encoded_header := JSON.stringify(header)
	var serialized := encoded_header.left(-1) + ",\"payload\":{" + ",".join(encoded_entries) + "}}"
	var next_snapshot := {"path": path, "fields": next_fields}
	var retired_snapshot: Dictionary
	_write_cache_mutex.lock()
	retired_snapshot = _write_cache_snapshot
	_write_cache_snapshot = next_snapshot
	_write_cache_mutex.unlock()
	# 持有被替换快照直到解锁，避免锁内释放整棵旧树。
	retired_snapshot = {}
	return serialized


# 只拆固定的大字典层级；叶块独立冻结，祖先由子块的冻结引用组装。
static func _write_chunk(raw: Variant, cached: Dictionary, trail: Array[String], layer: int) -> Dictionary:
	if not cached.is_empty() and cached.cacheable and typeof(raw) == typeof(cached.raw) and raw == cached.raw:
		return cached
	var split := layer > 0 and raw is Dictionary
	if split:
		for key in raw:
			if not key is String:
				split = false
				break
	if not split:
		var mode := _raw_cache_mode(raw, trail.size() - 1)
		if mode == 0:
			return {}
		# 保持原 JSON 深度；碰撞子树仍由原规范化函数按插入顺序处理。
		var wrapped: Variant = raw
		for index in range(trail.size() - 1, -1, -1):
			wrapped = {trail[index]: wrapped}
		var normalized: Variant = _normalize_for_storage(wrapped)
		for key in trail:
			normalized = normalized[key]
		return {
			"raw": _freeze_write_raw(raw) if mode == 2 else null,
			"cacheable": mode == 2,
			"stored": normalized,
			"canonical": _canonical_json(normalized),
			"encoded": JSON.stringify(normalized),
		}
	var keys: Array = raw.keys()
	keys.sort()
	var previous_children: Dictionary = cached.get("children", {})
	var children: Dictionary = {}
	var frozen: Dictionary = {}
	var stored: Dictionary = {}
	var canonical: Array[String] = []
	var encoded: Array[String] = []
	var cacheable := true
	for key in keys:
		var child_layer := 0
		if layer == 1 and key == "world_state":
			child_layer = 2
		elif layer == 2 and key == "segment_runtime_state":
			child_layer = 3
		elif layer == 3:
			child_layer = 4
		var child_trail: Array[String] = trail.duplicate()
		child_trail.append(key)
		var child := _write_chunk(raw[key], previous_children.get(key, {}), child_trail, child_layer)
		if child.is_empty():
			return {}
		children[key] = child
		frozen[key] = child.raw
		stored[key] = child.stored
		cacheable = cacheable and bool(child.cacheable)
		var prefix := JSON.stringify(key) + ":"
		canonical.append(prefix + str(child.canonical))
		encoded.append(prefix + str(child.encoded))
	return {"raw": frozen, "cacheable": cacheable, "stored": stored, "canonical": "{" + ",".join(canonical) + "}", "encoded": "{" + ",".join(encoded) + "}", "children": children}


# 容器深拷贝；PackedArray显式duplicate，其嵌套副本由原生COW隔离。
static func _freeze_write_raw(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY:
		return value.duplicate()
	return value


# 0：深度超限，整体旧路径；1：碰撞或引用类型，仅该叶块按旧规范化重算。
# 只缓存字符串键树和无对象引用的builtin值，保持原JSON表示而非转换数值精度。
static func _raw_cache_mode(value: Variant, depth := 0) -> int:
	if depth > 64:
		return 0
	if value is Dictionary:
		var mode := 2
		for key in value:
			if not key is String:
				mode = 1
			var child_mode := _raw_cache_mode(value[key], depth + 1)
			if child_mode == 0:
				return 0
			mode = mini(mode, child_mode)
		return mode
	if value is Array:
		var mode := 2
		for child in value:
			var child_mode := _raw_cache_mode(child, depth + 1)
			if child_mode == 0:
				return 0
			mode = mini(mode, child_mode)
		return mode
	return 2 if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR, TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY] else 1


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
