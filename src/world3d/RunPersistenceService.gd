class_name RunPersistenceService
extends RefCounted
## 局内存档 schema 的纯数据边界。场景负责采集/应用节点状态，本服务负责兼容、
## 深拷贝和拓扑白名单合并，避免 Dungeon/Tower 各自解释同一份存档结构。

const CURRENT_SCHEMA := "runtime_player_state_v2"
const SUPPORTED_SCHEMAS: Array[String] = ["runtime_player_state_v1", CURRENT_SCHEMA]


static func supports_runtime_snapshot(snapshot: Dictionary) -> bool:
	return bool(snapshot.get("valid", false)) and str(snapshot.get("schema", "")) in SUPPORTED_SCHEMAS


static func generate_run_id(run_seed: int) -> String:
	return "run:%d:%016x:%08x" % [
		run_seed,
		int(Time.get_unix_time_from_system() * 1000000.0),
		Time.get_ticks_usec() & 0xFFFFFFFF,
	]


static func finalize_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result["valid"] = true
	result["schema"] = CURRENT_SCHEMA
	result["saved_at_unix"] = maxi(0, int(result.get("saved_at_unix", Time.get_unix_time_from_system())))
	result["run_seed"] = int(result.get("run_seed", 1))
	result["current_room_id"] = str(result.get("current_room_id", ""))
	result["current_floor_index"] = int(result.get("current_floor_index", 0))
	result["scope"] = str(result.get("scope", "combat"))
	result["run_id"] = _runtime_instance_id(
		str(result.get("run_id", "")), "run:%d" % int(result["run_seed"])
	)
	result["layout_id"] = _runtime_instance_id(
		str(result.get("layout_id", "")), _derive_layout_id(result)
	)
	result["checkpoint_id"] = _runtime_instance_id(
		str(result.get("checkpoint_id", "")), "checkpoint:%s" % str(result["run_id"])
	)
	result["player_position"] = _normalize_position(result.get("player_position", []))
	result["inventory_slots"] = _snapshot_array(result.get("inventory_slots", []))
	result["insurance_slots"] = _snapshot_array(result.get("insurance_slots", []))
	result["equipped_weapon_items"] = _snapshot_array(result.get("equipped_weapon_items", []))
	result["quick_item_slots"] = _snapshot_array(result.get("quick_item_slots", []))
	result["quick_item_ids"] = _snapshot_array(result.get("quick_item_ids", ["", ""]))
	result["edge_states"] = result.get("edge_states", {}) as Dictionary
	result["world_state"] = result.get("world_state", {}) as Dictionary
	# runtime_map_id：独立副本的存档隔离键。旧档缺省为空字符串，仍按旧塔楼/兼容处理。
	result["runtime_map_id"] = str(result.get("runtime_map_id", ""))
	return result


## Migrate validated saves without re-rolling frozen rewards or interpreting assembly IDs as item IDs.
static func without_retired_item_records(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	for field in ["inventory_slots", "insurance_slots", "quick_item_slots", "equipped_weapon_items"]:
		_filter_item_array(result, field, true)
	if result.get("quick_item_ids") is Array:
		var ids := result["quick_item_ids"] as Array
		for index in ids.size():
			if ItemRegistry.is_retired_item_id(str(ids[index])):
				ids[index] = ""
	result.erase("room_key_count")
	if result.get("world_state") is Dictionary:
		_filter_world_item_records(result["world_state"])
	return result


static func _filter_item_array(owner: Dictionary, field: String, preserve_slots := false) -> void:
	if owner.get(field) is Array:
		owner[field] = ItemRegistry.without_retired_items(owner[field], preserve_slots)


static func _filter_world_item_records(world: Dictionary) -> void:
	for record in _snapshot_dictionary(world.get("segment_runtime_state")).values():
		if not record is Dictionary:
			continue
		var room := record as Dictionary
		room.erase("room_keys")
		_filter_item_array(room, "ground_items")
		if room.get("clear_drop_plan") is Dictionary:
			_filter_clear_drop(room["clear_drop_plan"])
		for pending in _snapshot_dictionary(room.get("pending_chest_grants")).values():
			if pending is Dictionary:
				_filter_item_array(pending, "grants")
		for chest in _snapshot_dictionary(room.get("treasure_chests")).values():
			if chest is Dictionary:
				_filter_chest_config(chest)
				if chest.get("config") is Dictionary:
					_filter_chest_config(chest["config"])
	for plan in _snapshot_dictionary(world.get("clear_drop_plans")).values():
		if plan is Dictionary:
			_filter_clear_drop(plan)
	for delivery in _snapshot_dictionary(world.get("clear_drop_delivery")).values():
		if delivery is Dictionary:
			for field in ["grants_pending", "additional_weapon_pending", "item_pending"]:
				_filter_item_array(delivery, field)
	var legacy_config := _snapshot_dictionary(world.get("clear_drop_config"))
	_filter_item_array(legacy_config, "fallback_pool")
	for guarantee in _snapshot_array(legacy_config.get("room_guarantees")):
		if guarantee is Dictionary:
			_filter_item_array(guarantee, "items")


static func _filter_chest_config(config: Dictionary) -> void:
	_filter_item_array(config, "guaranteed_items")
	if config.get("grants") is Array and not (config["grants"] as Array).is_empty():
		# Preserve fixed-reward semantics when every old grant was retired.
		config["explicit_reward_mode"] = true
		_filter_item_array(config, "grants")


static func _filter_clear_drop(plan: Dictionary) -> void:
	_filter_item_array(plan, "grants")
	var additional := _snapshot_dictionary(plan.get("additional_weapon"))
	if ItemRegistry.is_retired_item_id(str(additional.get("weapon_id", ""))):
		plan.erase("additional_weapon")
	if ItemRegistry.is_retired_item_entry(plan.get("item")):
		plan.erase("item")
		if str(plan.get("kind", "")) == "item":
			plan["kind"] = "none"
	if plan.get("chest") is Dictionary:
		_filter_chest_config(plan["chest"])


static func _runtime_instance_id(candidate: String, fallback: String) -> String:
	if not candidate.is_empty() and candidate not in SUPPORTED_SCHEMAS:
		return candidate
	return fallback


static func _derive_layout_id(snapshot: Dictionary) -> String:
	var world_state := snapshot.get("world_state", {}) as Dictionary
	var floor_layout_ids := world_state.get("floor_layout_ids", {}) as Dictionary
	var floor_key := str(int(snapshot.get("current_floor_index", 0)))
	var floor_layout_id := str(floor_layout_ids.get(floor_key, ""))
	if not floor_layout_id.is_empty():
		return floor_layout_id
	return "layout:%d:%s" % [int(snapshot.get("run_seed", 1)), floor_key]


static func build_world_state(
	schema: String,
	segment_runtime_state: Dictionary,
	extra_fields: Dictionary = {}
) -> Dictionary:
	var result := extra_fields.duplicate(true)
	result["schema"] = schema
	result["segment_runtime_state"] = segment_runtime_state.duplicate(true)
	return result


static func read_segment_runtime_state(snapshot: Dictionary) -> Dictionary:
	var world_state := snapshot.get("world_state", {}) as Dictionary
	var segment_state: Variant = world_state.get("segment_runtime_state", {})
	return (segment_state as Dictionary).duplicate(true) if segment_state is Dictionary else {}


static func merge_known_edge_states(current_edges: Dictionary, saved_edges: Variant) -> Dictionary:
	var result := current_edges.duplicate(true)
	if not saved_edges is Dictionary:
		return result
	for edge_value in (saved_edges as Dictionary).keys():
		var edge := str(edge_value)
		if result.has(edge):
			result[edge] = bool((saved_edges as Dictionary)[edge_value])
	return result


static func _normalize_position(value: Variant) -> Array:
	if not value is Array or (value as Array).size() < 3:
		return []
	return [float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2])]


static func _snapshot_array(value: Variant) -> Array:
	return value as Array if value is Array else []


static func _snapshot_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}
