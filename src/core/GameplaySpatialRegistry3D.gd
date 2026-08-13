extends Node
## 运行时近场空间注册表。只保存弱引用和稳定空间键，不拥有任何玩法节点。

signal node_registered(node: Node3D, kind: String)

const BUCKET_SIZE_M := 16.0
const KIND_ENEMY := "enemy"
const KIND_LOCAL_LIGHT := "local_light"
const KIND_SUN := "sun"
const KIND_CONNECTOR := "connector"

var _records: Dictionary = {}
var _buckets: Dictionary = {}
var _query_count := 0
var _candidate_count := 0
var _stale_pruned := 0


func register_node(node: Node3D, kind: String, room_id := "", segment_id := "runtime") -> void:
	if node == null or not is_instance_valid(node) or kind.is_empty():
		return
	var instance_id := node.get_instance_id()
	_remove_from_bucket(instance_id)
	var resolved_room := room_id if not room_id.is_empty() else _infer_room_id(node)
	var spatial_position := _spatial_position(node)
	var bucket_key := _bucket_key(spatial_position)
	_records[instance_id] = {
		"ref": weakref(node),
		"kind": kind,
		"room_id": resolved_room,
		"segment_id": segment_id,
		"floor_index": _floor_index(spatial_position),
		"bucket_key": bucket_key,
	}
	_add_to_bucket(bucket_key, instance_id)
	node_registered.emit(node, kind)


func update_node(node: Node3D, room_id := "") -> void:
	if node == null or not is_instance_valid(node):
		return
	var instance_id := node.get_instance_id()
	if not _records.has(instance_id):
		return
	var record := _records[instance_id] as Dictionary
	var spatial_position := _spatial_position(node)
	var next_bucket := _bucket_key(spatial_position)
	if str(record.get("bucket_key", "")) != next_bucket:
		_remove_from_bucket(instance_id)
		record["bucket_key"] = next_bucket
		_add_to_bucket(next_bucket, instance_id)
	record["floor_index"] = _floor_index(spatial_position)
	if not room_id.is_empty():
		record["room_id"] = room_id
	_records[instance_id] = record


func unregister_node(node: Node) -> void:
	if node != null:
		unregister_instance_id(node.get_instance_id())


func unregister_instance_id(instance_id: int) -> void:
	_remove_from_bucket(instance_id)
	_records.erase(instance_id)


func query_radius(
	world_position: Vector3,
	radius: float,
	kinds: Array[String] = [],
	room_ids: Array[String] = []
) -> Array[Node3D]:
	_query_count += 1
	var result: Array[Node3D] = []
	var seen: Dictionary = {}
	var bucket_radius := maxi(1, ceili(maxf(0.0, radius) / BUCKET_SIZE_M) + 1)
	var center := _bucket_coords(world_position)
	var radius_squared := radius * radius
	for floor_offset in range(-1, 2):
		for x_offset in range(-bucket_radius, bucket_radius + 1):
			for z_offset in range(-bucket_radius, bucket_radius + 1):
				var key := _coords_key(center + Vector3i(x_offset, floor_offset, z_offset))
				var ids := _buckets.get(key, {}) as Dictionary
				for instance_id_value in ids.keys():
					var instance_id := int(instance_id_value)
					if seen.has(instance_id):
						continue
					seen[instance_id] = true
					var node := _resolve(instance_id)
					if node == null:
						continue
					var record := _records.get(instance_id, {}) as Dictionary
					if not kinds.is_empty() and str(record.get("kind", "")) not in kinds:
						continue
					if not room_ids.is_empty() and str(record.get("room_id", "")) not in room_ids:
						continue
					_candidate_count += 1
					if _spatial_position(node).distance_squared_to(world_position) <= radius_squared:
						result.append(node)
	return result


func query_kind(kind: String) -> Array[Node3D]:
	_query_count += 1
	var result: Array[Node3D] = []
	for instance_id_value in _records.keys().duplicate():
		var instance_id := int(instance_id_value)
		var record := _records.get(instance_id, {}) as Dictionary
		if str(record.get("kind", "")) != kind:
			continue
		var node := _resolve(instance_id)
		if node != null:
			_candidate_count += 1
			result.append(node)
	return result


func get_record(node: Node) -> Dictionary:
	if node == null:
		return {}
	var record := _records.get(node.get_instance_id(), {}) as Dictionary
	var result := record.duplicate(true)
	result.erase("ref")
	return result


func prune_stale() -> int:
	var before := _stale_pruned
	for instance_id_value in _records.keys().duplicate():
		_resolve(int(instance_id_value))
	return _stale_pruned - before


func clear_runtime_records() -> void:
	_records.clear()
	_buckets.clear()


func get_snapshot() -> Dictionary:
	prune_stale()
	var by_kind: Dictionary = {}
	var by_room: Dictionary = {}
	for record_value in _records.values():
		var record := record_value as Dictionary
		var kind := str(record.get("kind", "unknown"))
		var room_id := str(record.get("room_id", ""))
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		if not room_id.is_empty():
			by_room[room_id] = int(by_room.get(room_id, 0)) + 1
	return {
		"record_count": _records.size(),
		"bucket_count": _buckets.size(),
		"by_kind": by_kind,
		"by_room": by_room,
		"query_count": _query_count,
		"candidate_count": _candidate_count,
		"stale_pruned": _stale_pruned,
		"bucket_size_m": BUCKET_SIZE_M,
	}


func _resolve(instance_id: int) -> Node3D:
	var record := _records.get(instance_id, {}) as Dictionary
	if record.is_empty():
		return null
	var reference := record.get("ref") as WeakRef
	var node := reference.get_ref() as Node3D if reference != null else null
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		unregister_instance_id(instance_id)
		_stale_pruned += 1
		return null
	return node


func _spatial_position(node: Node3D) -> Vector3:
	if node != null and node.has_meta("spatial_registry_position"):
		return node.get_meta("spatial_registry_position") as Vector3
	return node.global_position if node != null else Vector3.ZERO


func _remove_from_bucket(instance_id: int) -> void:
	var record := _records.get(instance_id, {}) as Dictionary
	if record.is_empty():
		return
	var key := str(record.get("bucket_key", ""))
	var ids := _buckets.get(key, {}) as Dictionary
	ids.erase(instance_id)
	if ids.is_empty():
		_buckets.erase(key)
	else:
		_buckets[key] = ids


func _add_to_bucket(key: String, instance_id: int) -> void:
	var ids := _buckets.get(key, {}) as Dictionary
	ids[instance_id] = true
	_buckets[key] = ids


func _infer_room_id(node: Node) -> String:
	var cursor: Node = node
	while cursor != null:
		if cursor is DungeonRoom3D:
			return (cursor as DungeonRoom3D).room_id
		cursor = cursor.get_parent()
	if node is Enemy3D:
		return (node as Enemy3D).room_id
	return ""


func _floor_index(position: Vector3) -> int:
	return int(round(-position.y / 9.0))


func _bucket_key(position: Vector3) -> String:
	return _coords_key(_bucket_coords(position))


func _bucket_coords(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / BUCKET_SIZE_M),
		_floor_index(position),
		floori(position.z / BUCKET_SIZE_M)
	)


func _coords_key(coords: Vector3i) -> String:
	return "%d:%d:%d" % [coords.x, coords.y, coords.z]
