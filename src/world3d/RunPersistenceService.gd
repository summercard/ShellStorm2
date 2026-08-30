class_name RunPersistenceService
extends RefCounted
## 局内存档 schema 的纯数据边界。场景负责采集/应用节点状态，本服务负责兼容、
## 深拷贝和拓扑白名单合并，避免 Dungeon/Tower 各自解释同一份存档结构。

const CURRENT_SCHEMA := "runtime_player_state_v2"
const SUPPORTED_SCHEMAS: Array[String] = ["runtime_player_state_v1", CURRENT_SCHEMA]


static func supports_runtime_snapshot(snapshot: Dictionary) -> bool:
	return bool(snapshot.get("valid", false)) and str(snapshot.get("schema", "")) in SUPPORTED_SCHEMAS


static func finalize_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result["valid"] = true
	result["schema"] = CURRENT_SCHEMA
	result["checkpoint_id"] = CURRENT_SCHEMA
	result["layout_id"] = CURRENT_SCHEMA
	result["saved_at_unix"] = maxi(0, int(result.get("saved_at_unix", Time.get_unix_time_from_system())))
	result["run_seed"] = int(result.get("run_seed", 1))
	result["current_room_id"] = str(result.get("current_room_id", ""))
	result["current_floor_index"] = int(result.get("current_floor_index", 0))
	result["scope"] = str(result.get("scope", "combat"))
	result["player_position"] = _normalize_position(result.get("player_position", []))
	result["inventory_slots"] = _array_copy(result.get("inventory_slots", []))
	result["insurance_slots"] = _array_copy(result.get("insurance_slots", []))
	result["equipped_weapon_items"] = _array_copy(result.get("equipped_weapon_items", []))
	result["quick_item_slots"] = _array_copy(result.get("quick_item_slots", []))
	result["quick_item_ids"] = _array_copy(result.get("quick_item_ids", ["", ""]))
	result["edge_states"] = (result.get("edge_states", {}) as Dictionary).duplicate(true)
	result["world_state"] = (result.get("world_state", {}) as Dictionary).duplicate(true)
	return result


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


static func _array_copy(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []
