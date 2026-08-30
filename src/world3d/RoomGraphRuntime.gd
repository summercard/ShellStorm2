class_name RoomGraphRuntime
extends RefCounted
## 房间拓扑和流送决策的数据层。只保存可序列化数据，不引用场景节点。

var _records: Array[Dictionary] = []
var _neighbors: Dictionary = {}
var _edge_states: Dictionary = {}
var _stream_states: Dictionary = {}


func configure(records: Array[Dictionary], neighbors: Dictionary, edge_states: Dictionary) -> void:
	_records.clear()
	for record in records:
		_records.append(record.duplicate(true))
	_neighbors = neighbors.duplicate(true)
	sync_edge_states(edge_states)


func sync_edge_states(edge_states: Dictionary) -> void:
	_edge_states = edge_states.duplicate(true)


func set_edge_open(a: String, b: String, opened: bool) -> bool:
	var key := edge_key(a, b)
	if not _edge_states.has(key):
		return false
	_edge_states[key] = opened
	return true


func is_edge_open(a: String, b: String) -> bool:
	return bool(_edge_states.get(edge_key(a, b), false))


func get_neighbors(room_id: String) -> Array:
	return (_neighbors.get(room_id, []) as Array).duplicate()


func resolve_stream_state(
	room_id: String,
	current_room_id: String,
	data_only_state: int,
	shell_ready_state: int,
	active_state: int
) -> int:
	if room_id == current_room_id:
		return active_state
	if room_id in (_neighbors.get(current_room_id, []) as Array) and is_edge_open(current_room_id, room_id):
		return shell_ready_state
	return data_only_state


func commit_stream_state(room_id: String, next_state: int, data_only_state: int) -> Dictionary:
	var previous := int(_stream_states.get(room_id, data_only_state))
	_stream_states[room_id] = next_state
	return {
		"changed": previous != next_state,
		"previous": previous,
		"current": next_state,
		"hibernate": previous != data_only_state and next_state == data_only_state,
	}


func get_stream_states_snapshot() -> Dictionary:
	return _stream_states.duplicate(true)


func erase_stream_state(room_id: String) -> void:
	_stream_states.erase(room_id)


func get_topology_snapshot() -> Dictionary:
	return {
		"schema": "room_graph_runtime_v1",
		"records": _records.duplicate(true),
		"neighbors": _neighbors.duplicate(true),
		"edge_states": _edge_states.duplicate(true),
		"stream_states": _stream_states.duplicate(true),
	}


static func edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
