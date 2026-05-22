class_name NodeGraph
## 节点图结构 — 管理房间节点列表和连接关系

var _nodes: Array[RoomNode] = []
var _edges: Array[GraphEdge] = []

class RoomNode:
	var id: int
	var room_data: RoomData
	var position: Vector2
	var connections: Array[int] = []  # 连接的节点ID
	
	func _init(p_id: int, p_data: RoomData, p_pos: Vector2 = Vector2.ZERO):
		id = p_id
		room_data = p_data
		position = p_pos

class GraphEdge:
	var from_id: int
	var to_id: int
	var bidirectional: bool = true
	
	func _init(p_from: int, p_to: int, p_bi: bool = true):
		from_id = p_from
		to_id = p_to
		bidirectional = p_bi

## 添加节点
func add_node(data: RoomData, pos: Vector2 = Vector2.ZERO) -> int:
	var node_id := _nodes.size()
	var node := RoomNode.new(node_id, data, pos)
	_nodes.append(node)
	return node_id

## 添加边（连接两个节点）
func add_edge(from_id: int, to_id: int, bidirectional: bool = true) -> bool:
	if from_id < 0 or from_id >= _nodes.size() or to_id < 0 or to_id >= _nodes.size():
		return false
	if from_id == to_id:
		return false
	
	_edges.append(GraphEdge.new(from_id, to_id, bidirectional))
	
	if bidirectional:
		_nodes[from_id].connections.append(to_id)
		_nodes[to_id].connections.append(from_id)
	else:
		_nodes[from_id].connections.append(to_id)
	
	return true

## 获取节点
func get_node(id: int) -> RoomNode:
	if id >= 0 and id < _nodes.size():
		return _nodes[id]
	return null

## 获取所有节点
func get_all_nodes() -> Array[RoomNode]:
	return _nodes

## 获取节点数量
func node_count() -> int:
	return _nodes.size()

## 获取边的数量
func edge_count() -> int:
	return _edges.size()

## 深度优先遍历
func dfs(start_id: int, callback: Callable) -> void:
	var visited: Dictionary = {}
	var stack: Array[int] = [start_id]
	
	while stack.size() > 0:
		var current: int = stack.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		
		var node := get_node(current)
		if node != null:
			var should_continue = callback.call(node)
			if should_continue == false:
				return
		
		for conn_id in node.connections:
			if not visited.has(conn_id):
				stack.append(conn_id)

## 广度优先遍历
func bfs(start_id: int, callback: Callable) -> void:
	var visited: Dictionary = {}
	var queue: Array[int] = [start_id]
	visited[start_id] = true
	
	while queue.size() > 0:
		var current: int = queue.pop_front()
		
		var node := get_node(current)
		if node != null:
			var should_continue = callback.call(node)
			if should_continue == false:
				return
		
		for conn_id in node.connections:
			if not visited.has(conn_id):
				visited[conn_id] = true
				queue.append(conn_id)

## 获取从起点到终点的路径（深度优先搜索）
func find_path(start_id: int, end_id: int) -> Array[int]:
	if start_id < 0 or end_id < 0 or start_id >= _nodes.size() or end_id >= _nodes.size():
		return []
	
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array[int] = [start_id]
	visited[start_id] = true
	
	while queue.size() > 0:
		var current: int = queue.pop_front()
		
		if current == end_id:
			# 重建路径
			var path: Array[int] = []
			var node := end_id
			while parent.has(node):
				path.push_front(node)
				node = parent[node]
			path.push_front(start_id)
			return path
		
		var node := get_node(current)
		for conn_id in node.connections:
			if not visited.has(conn_id):
				visited[conn_id] = true
				parent[conn_id] = current
				queue.append(conn_id)
	
	return []

## 获取某节点的所有邻居
func get_neighbors(node_id: int) -> Array[int]:
	var node := get_node(node_id)
	if node == null:
		return []
	return node.connections.duplicate()

## 随机获取一个节点
func get_random_node(rng: RandomNumberGenerator = null) -> RoomNode:
	if _nodes.size() == 0:
		return null
	var idx := 0
	if rng != null:
		idx = rng.randi() % _nodes.size()
	return _nodes[idx]

## 获取最深路径的末端节点（用于找Boss房）
func get_deepest_node() -> RoomNode:
	if _nodes.size() == 0:
		return null
	
	var max_depth := 0
	var deepest_node: RoomNode = null
	
	for node in _nodes:
		var depth := _calc_depth(node.id, [])
		if depth > max_depth:
			max_depth = depth
			deepest_node = node
	
	return deepest_node

func _calc_depth(node_id: int, visited: Array[int]) -> int:
	if node_id in visited:
		return 0
	visited.append(node_id)
	
	var node := get_node(node_id)
	if node == null:
		return 0
	
	if node.connections.size() == 0:
		return 1
	
	var max_child_depth := 0
	for conn_id in node.connections:
		var d := _calc_depth(conn_id, visited.duplicate())
		if d > max_child_depth:
			max_child_depth = d
	
	return max_child_depth + 1

## 清除所有节点和边
func clear() -> void:
	_nodes.clear()
	_edges.clear()

## 打印图结构（调试用）
func debug_print() -> String:
	var lines: Array[String] = []
	lines.append("NodeGraph [%d nodes, %d edges]" % [_nodes.size(), _edges.size()])
	for node in _nodes:
		var data: RoomData = node.room_data
		var conns := ",".join(node.connections as Array[String])
		lines.append("  Node#%d [%s] pos=%v conns=[%s]" % [node.id, data.room_type, node.position, conns])
	return "\n".join(lines)