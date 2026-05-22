class_name PathDirector
## 路径与门管理 — 管理房间之间的连接和门的开关状态

signal door_opened(from_room: String, to_room: String)
signal door_closed(from_room: String, to_room: String)

## 门连接数据
class DoorConnection:
	var from_id: int
	var to_id: int
	var is_bidirectional: bool = true
	var is_open: bool = false  # 初始关闭，需要开启
	var door_type: String = "normal"  # normal/boss/extraction
	
	func _init(p_from: int, p_to: int, p_bi: bool = true, p_type: String = "normal"):
		from_id = p_from
		to_id = p_to
		is_bidirectional = p_bi
		door_type = p_type

var _connections: Array[DoorConnection] = []
var _node_to_doors: Dictionary = {}  # node_id -> [door_indices]

## 添加连接（创建门）
func add_connection(from_id: int, to_id: int, bidirectional: bool = true, door_type: String = "normal") -> int:
	var conn := DoorConnection.new(from_id, to_id, bidirectional, door_type)
	var conn_idx := _connections.size()
	_connections.append(conn)
	
	# 更新索引
	if not _node_to_doors.has(from_id):
		_node_to_doors[from_id] = []
	_node_to_doors[from_id].append(conn_idx)
	
	if bidirectional:
		if not _node_to_doors.has(to_id):
			_node_to_doors[to_id] = []
		_node_to_doors[to_id].append(conn_idx)
	
	return conn_idx

## 开启指定房间间的门
func open_door(from_id: int, to_id: int) -> bool:
	var conn_idx := _find_connection(from_id, to_id)
	if conn_idx < 0:
		return false
	
	var conn: DoorConnection = _connections[conn_idx]
	conn.is_open = true
	
	var from_data: RoomData = _get_room_data(from_id)
	var to_data: RoomData = _get_room_data(to_id)
	
	door_opened.emit(from_data.room_id, to_data.room_id)
	return true

## 关闭指定房间间的门
func close_door(from_id: int, to_id: int) -> bool:
	var conn_idx := _find_connection(from_id, to_id)
	if conn_idx < 0:
		return false
	
	var conn: DoorConnection = _connections[conn_idx]
	conn.is_open = false
	
	var from_data: RoomData = _get_room_data(from_id)
	var to_data: RoomData = _get_room_data(to_id)
	
	door_closed.emit(from_data.room_id, to_data.room_id)
	return true

## 开启从指定房间出发的所有门
func open_doors_from(node_id: int) -> void:
	var door_indices: Array = _node_to_doors.get(node_id, [])
	for idx in door_indices:
		var conn: DoorConnection = _connections[idx]
		if not conn.is_open:
			conn.is_open = true
			var other_id: int = conn.to_id if conn.from_id == node_id else conn.from_id
			var from_data: RoomData = _get_room_data(node_id)
			var to_data: RoomData = _get_room_data(other_id)
			door_opened.emit(from_data.room_id, to_data.room_id)

## 检查两个房间之间是否连通（门是否开启）
func are_connected(from_id: int, to_id: int) -> bool:
	var conn_idx := _find_connection(from_id, to_id)
	if conn_idx < 0:
		return false
	return _connections[conn_idx].is_open

## 获取从某房间出发可以到达的房间ID列表
func get_connected_rooms(node_id: int) -> Array[int]:
	var result: Array[int] = []
	var door_indices: Array = _node_to_doors.get(node_id, [])
	
	for idx in door_indices:
		var conn: DoorConnection = _connections[idx]
		if conn.is_open:
			if conn.from_id == node_id:
				result.append(conn.to_id)
			elif conn.is_bidirectional and conn.to_id == node_id:
				result.append(conn.from_id)
	
	return result

## 检查从某房间是否可以进入目标房间（门开启且路径存在）
func can_reach(from_id: int, to_id: int, graph: NodeGraph) -> bool:
	if not are_connected(from_id, to_id):
		return false
	# 通过图连接检查（门开启且图中有边）
	var node := graph.get_node(from_id)
	return to_id in node.connections

## 根据房间类型自动开启对应门
func auto_open_for_type(room_data: RoomData, node_id: int, graph: NodeGraph) -> void:
	match room_data.room_type:
		RoomData.RoomType.PLAYER_SPAWN:
			open_doors_from(node_id)  # 出生房自动开所有门
		RoomData.RoomType.BOSS:
			# Boss击败后开门
			open_doors_from(node_id)
		RoomData.RoomType.EXTRACTION:
			# 撤离房始终可进入
			open_doors_from(node_id)
		_:
			pass

## 手动开门（玩家交互触发）
func player_request_open_door(from_id: int, to_id: int) -> bool:
	# 检查是否有特殊条件（如道具、击杀要求等）
	# 目前简化处理：直接开门
	return open_door(from_id, to_id)

## 获取门的数量
func door_count() -> int:
	return _connections.size()

## 获取开启的门数量
func open_door_count() -> int:
	var count := 0
	for conn in _connections:
		if conn.is_open:
			count += 1
	return count

## 查找连接索引
func _find_connection(from_id: int, to_id: int) -> int:
	for i in range(_connections.size()):
		var conn: DoorConnection = _connections[i]
		if (conn.from_id == from_id and conn.to_id == to_id) or \
		   (conn.is_bidirectional and conn.from_id == to_id and conn.to_id == from_id):
			return i
	return -1

## 临时获取房间数据（通过graph节点）
var _cached_graph: NodeGraph = null

func set_graph(graph: NodeGraph) -> void:
	_cached_graph = graph

func _get_room_data(node_id: int) -> RoomData:
	if _cached_graph != null:
		var node := _cached_graph.get_node(node_id)
		if node != null:
			return node.room_data
	return null

## 调试：打印所有门状态
func debug_doors() -> String:
	var lines: Array[String] = ["PathDirector [%d doors, %d open]" % [_connections.size(), open_door_count()]]
	for i in range(_connections.size()):
		var conn: DoorConnection = _connections[i]
		var status := "OPEN" if conn.is_open else "CLOSED"
		lines.append("  Door#%d %s -> %s [%s] (%s)" % [i, conn.from_id, conn.to_id, status, conn.door_type])
	return "\n".join(lines)

## 清除所有连接
func clear() -> void:
	_connections.clear()
	_node_to_doors.clear()