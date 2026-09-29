extends Node

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
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
	if int(record.get("bucket_key", BUCKET_KEY_NONE)) != next_bucket:
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
	# 桶坐标半径恰好覆盖查询半径即可：相邻桶心相距 BUCKET_SIZE_M，所以
	# ceili(radius / BUCKET_SIZE_M) 个桶就够（半径 3m ⇒ 1 个桶 ⇒ 3×3×3）。
	# 原来的 `+1` 会让 3m 的查询去扫 5×5×3 = 75 个桶，多扫的 48 个桶永远是空的。
	var bucket_radius := maxi(1, ceili(maxf(0.0, radius) / BUCKET_SIZE_M))
	var center := _bucket_coords(world_position)
	var radius_squared := radius * radius
	for floor_offset in range(-1, 2):
		for x_offset in range(-bucket_radius, bucket_radius + 1):
			for z_offset in range(-bucket_radius, bucket_radius + 1):
				var key := _coords_key(center + Vector3i(x_offset, floor_offset, z_offset))
				var ids := _buckets.get(key, {}) as Dictionary
				# 直接迭代字典取 key；`ids.keys()` 会为每个桶额外新建一个数组。
				for instance_id_value in ids:
					var instance_id := int(instance_id_value)
					if seen.has(instance_id):
						continue
					seen[instance_id] = true
					var node := _resolve(instance_id)
					if node == null:
						continue
					var record := _records.get(instance_id, {}) as Dictionary
					if not kinds.is_empty() and not kinds.has(record.get("kind", "")):
						continue
					if not room_ids.is_empty() and not room_ids.has(record.get("room_id", "")):
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
	var key := int(record.get("bucket_key", BUCKET_KEY_NONE))
	if key == BUCKET_KEY_NONE:
		return
	var ids := _buckets.get(key, {}) as Dictionary
	ids.erase(instance_id)
	if ids.is_empty():
		_buckets.erase(key)
	else:
		_buckets[key] = ids


func _add_to_bucket(key: int, instance_id: int) -> void:
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
	return int(round(-position.y / TOWER_GEOMETRY.FLOOR_HEIGHT_M))


func _bucket_key(position: Vector3) -> int:
	return _coords_key(_bucket_coords(position))


func _bucket_coords(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / BUCKET_SIZE_M),
		_floor_index(position),
		floori(position.z / BUCKET_SIZE_M)
	)


## 桶 key 用整数位打包，不用 `"%d:%d:%d"` 字符串。
## 一次半径查询要扫几十个桶，而字符串格式化每次约 1~4 微秒且每次新建一个 String；
## 对每帧每怪都要查询一次的调用方（怪物同类分离）来说，这一项就占掉查询成本的大半。
## 位运算版本没有分配、没有格式化，语义与原来的三元组字符串一一对应。
const BUCKET_KEY_OFFSET := 512
const BUCKET_KEY_MASK := 0x3FF
## 尚未写入任何桶时的哨兵 key。打包结果恒为非负，所以 -1 不会与真实 key 冲突。
const BUCKET_KEY_NONE := -1


func _coords_key(coords: Vector3i) -> int:
	return (
		((coords.x + BUCKET_KEY_OFFSET) & BUCKET_KEY_MASK)
		| (((coords.y + BUCKET_KEY_OFFSET) & BUCKET_KEY_MASK) << 10)
		| (((coords.z + BUCKET_KEY_OFFSET) & BUCKET_KEY_MASK) << 20)
	)
