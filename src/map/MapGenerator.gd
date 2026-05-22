class_name MapGenerator
## 随机地图生成器 — 根据楼层生成节点图结构的地图

signal map_generated(graph: NodeGraph)

## 地图生成配置
var _rng: RandomNumberGenerator
var _current_floor: int = 1

## 生成配置
const MIN_PATH_LENGTH := 4   # 最短路径长度（房间数）
const MAX_PATH_LENGTH := 8   # 最长路径长度

## 楼层配置
const FLOOR_ROOM_CONFIG = {
	1: { "path_len": 4, "elite_chance": 0.1, "scavenge_chance": 0.15, "merchant_chance": 0.1, "event_chance": 0.1, "boss_exists": true },
	2: { "path_len": 5, "elite_chance": 0.2, "scavenge_chance": 0.15, "merchant_chance": 0.12, "event_chance": 0.12, "boss_exists": true },
	3: { "path_len": 6, "elite_chance": 0.3, "scavenge_chance": 0.12, "merchant_chance": 0.15, "event_chance": 0.15, "boss_exists": true },
	4: { "path_len": 7, "elite_chance": 0.35, "scavenge_chance": 0.1, "merchant_chance": 0.1, "event_chance": 0.2, "boss_exists": true },
}

## 生成地图
func generate(floor: int, seed_value: int = -1) -> NodeGraph:
	_current_floor = floor
	
	# 初始化随机数生成器
	_rng = RandomNumberGenerator.new()
	if seed_value < 0:
		seed_value = Time.get_ticks_msec()
	_rng.seed = seed_value
	
	# 获取楼层配置
	var config: Dictionary = FLOOR_ROOM_CONFIG.get(floor, FLOOR_ROOM_CONFIG[4])
	
	# 创建节点图
	var graph := NodeGraph.new()
	
	# 生成主路径
	var path_length: int = config["path_len"]
	var main_path: Array[int] = _generate_main_path(graph, path_length)
	
	# 在主路径节点之间插入特殊房间
	_generate_special_rooms(graph, main_path, config)
	
	# 确保Boss房存在且在末端
	_ensure_boss_room(graph, main_path)
	
	# 设置房间层级
	_set_floor_levels(graph, main_path)
	
	map_generated.emit(graph)
	return graph

## 生成主路径
func _generate_main_path(graph: NodeGraph, length: int) -> Array[int]:
	var path_ids: Array[int] = []
	
	# 起始房间（玩家出生）
	var start_data := RoomData.new(RoomData.RoomType.PLAYER_SPAWN, _current_floor)
	start_data.floor_level = RoomData.FloorLevel.SHALLOW
	var start_id := graph.add_node(start_data, Vector2(0, 0))
	path_ids.append(start_id)
	
	# 中间房间
	var last_pos := Vector2(0, 0)
	var last_id := start_id
	
	for i in range(1, length - 1):
		var room_type := _choose_path_room_type(i, length)
		var room_data := RoomData.new(room_type, _current_floor)
		
		# 计算位置（向右扩展，随机上下偏移）
		var offset := Vector2(300, _rng.randf_range(-100, 100))
		var new_pos := last_pos + offset
		
		var node_id := graph.add_node(room_data, new_pos)
		graph.add_edge(last_id, node_id, true)
		
		path_ids.append(node_id)
		last_id = node_id
		last_pos = new_pos
	
	# 末端房间（Boss前一个）
	var pre_boss_data := RoomData.new(RoomData.RoomType.COMBAT, _current_floor)
	var pre_boss_pos := last_pos + Vector2(300, 0)
	var pre_boss_id := graph.add_node(pre_boss_data, pre_boss_pos)
	graph.add_edge(last_id, pre_boss_id, true)
	path_ids.append(pre_boss_id)
	
	return path_ids

## 选择路径上的房间类型
func _choose_path_room_type(index: int, total: int) -> RoomData.RoomType:
	var roll := _rng.randf()
	
	# 浅层/前段：普通战斗为主
	if index < total / 2:
		if roll < 0.75:
			return RoomData.RoomType.COMBAT
		else:
			return RoomData.RoomType.SCAVENGE
	# 深层/后段：更多精英和事件
	else:
		if roll < 0.55:
			return RoomData.RoomType.COMBAT
		elif roll < 0.75:
			return RoomData.RoomType.ELITE
		else:
			return RoomData.RoomType.EVENT

## 在路径节点之间插入特殊房间
func _generate_special_rooms(graph: NodeGraph, path_ids: Array[int], config: Dictionary) -> void:
	# 在相邻节点之间添加分支
	var branch_chance: float = config["elite_chance"] + config["scavenge_chance"] + config["merchant_chance"] + config["event_chance"]
	
	for i in range(path_ids.size() - 1):
		var from_id: int = path_ids[i]
		var to_id: int = path_ids[i + 1]
		var from_node := graph.get_node(from_id)
		var to_node := graph.get_node(to_id)
		
		# 随机决定是否插入分支
		if _rng.randf() > branch_chance:
			continue
		
		# 选择分支房间类型
		var branch_type: RoomData.RoomType = _choose_special_room_type(config)
		var branch_data := RoomData.new(branch_type, _current_floor)
		
		# 放置在主路径旁边
		var offset_pos := from_node.position + Vector2(150, _rng.randf_range(-200, 200))
		var branch_id := graph.add_node(branch_data, offset_pos)
		
		# 连接：from → branch → to（把原来直连打断）
		# 移除 from-to 的直接连接（临时做法，实际上应该保留双向通道，这里仅添加分支）
		graph.add_edge(from_id, branch_id, true)
		graph.add_edge(branch_id, to_id, true)

## 选择特殊房间类型
func _choose_special_room_type(config: Dictionary) -> RoomData.RoomType:
	var roll := _rng.randf()
	var elite_chance: float = config["elite_chance"]
	var scavenge_chance: float = config["scavenge_chance"]
	var merchant_chance: float = config["merchant_chance"]
	var event_chance: float = config["event_chance"]
	
	if roll < elite_chance:
		return RoomData.RoomType.ELITE
	elif roll < elite_chance + scavenge_chance:
		return RoomData.RoomType.SCAVENGE
	elif roll < elite_chance + scavenge_chance + merchant_chance:
		return RoomData.RoomType.MERCHANT
	else:
		return RoomData.RoomType.UPGRADE

## 确保Boss房存在
func _ensure_boss_room(graph: NodeGraph, path_ids: Array[int]) -> void:
	var last_id: int = path_ids[path_ids.size() - 1]
	var last_node := graph.get_node(last_id)
	
	# 如果最后一个不是Boss房，创建Boss房
	var last_data: RoomData = last_node.room_data
	if last_data.room_type != RoomData.RoomType.BOSS:
		var boss_data := RoomData.new(RoomData.RoomType.BOSS, _current_floor)
		boss_data.floor_level = RoomData.FloorLevel.DEEP
		var boss_pos := last_node.position + Vector2(300, 0)
		var boss_id := graph.add_node(boss_data, boss_pos)
		graph.add_edge(last_id, boss_id, true)
		path_ids.append(boss_id)
	else:
		# 已经是Boss房，设置为深层
		last_data.floor_level = RoomData.FloorLevel.DEEP

## 设置房间层级
func _set_floor_levels(graph: NodeGraph, path_ids: Array[int]) -> void:
	var n := path_ids.size()
	
	for i in range(n):
		var node := graph.get_node(path_ids[i])
		var data: RoomData = node.room_data
		
		# 根据位置（从起点到末端）设置层级
		var progress := float(i) / float(max(1, n - 1))
		
		if progress < 0.33:
			data.floor_level = RoomData.FloorLevel.SHALLOW
		elif progress < 0.66:
			data.floor_level = RoomData.FloorLevel.MEDIUM
		else:
			data.floor_level = RoomData.FloorLevel.DEEP

## 获取当前楼层
func get_current_floor() -> int:
	return _current_floor

## 调试：打印生成的地图
func debug_map(graph: NodeGraph) -> String:
	return graph.debug_print()