class_name MapGenerator
extends RefCounted
## 随机地图生成器 — 根据楼层生成节点图结构的地图

signal map_generated(graph: NodeGraph)

## 地图生成配置
var _rng: RandomNumberGenerator
var _current_floor: int = 1

## 生成配置
const MIN_PATH_LENGTH := 4   # 最短路径长度（房间数）
const MAX_PATH_LENGTH := 8   # 最长路径长度
const ROOM_SPACING := Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)  # 960×768

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

	# 确保本层存在至少一个撤离房，作为搜打撤的带出终点
	_ensure_extraction_room(graph, main_path)
	
	# 设置房间层级
	_set_floor_levels(graph, main_path)
	
	# 生成垂直关卡（地下室、二楼等）
	_generate_vertical_levels(graph, main_path)
	
	map_generated.emit(graph)
	return graph

## 生成主路径
func _generate_main_path(graph: NodeGraph, length: int) -> Array[int]:
	var path_ids: Array[int] = []
	
	# 起始房间（玩家出生）
	var start_data := RoomData.new(RoomData.RoomType.PLAYER_SPAWN, _current_floor)
	start_data.floor_level = RoomData.FloorLevel.SHALLOW
	start_data.auto_size()
	var start_id := graph.add_node(start_data, Vector2(0, 0))
	path_ids.append(start_id)

	var last_pos: Vector2 = Vector2(0, 0)
	var last_id: int = start_id
	var last_data: RoomData = start_data

	# 中间房间。物理房间按网格拼接，门洞才能成为真实通路。
	for i in range(1, length - 1):
		var room_type := _choose_path_room_type(i, length)
		var room_data := RoomData.new(room_type, _current_floor)
		var progress := float(i) / float(length - 1)
		if progress < 0.33:
			room_data.floor_level = RoomData.FloorLevel.SHALLOW
		elif progress < 0.66:
			room_data.floor_level = RoomData.FloorLevel.MEDIUM
		else:
			room_data.floor_level = RoomData.FloorLevel.DEEP
		room_data.auto_size()

		# 使用两房间宽度的一半作为间距，避免 LARGE 房间重叠或 SMALL 房间留缝
		var new_pos: Vector2 = last_pos + Vector2((last_data.size.x + room_data.size.x) * 0.5, 0)

		var node_id: int = graph.add_node(room_data, new_pos)
		graph.add_edge(last_id, node_id, true)

		path_ids.append(node_id)
		last_id = node_id
		last_pos = new_pos
		last_data = room_data

	# 末端房间（Boss前一个）
	var pre_boss_data := RoomData.new(RoomData.RoomType.COMBAT, _current_floor)
	pre_boss_data.floor_level = RoomData.FloorLevel.DEEP
	pre_boss_data.auto_size()
	var pre_boss_pos: Vector2 = last_pos + Vector2((last_data.size.x + pre_boss_data.size.x) * 0.5, 0)
	var pre_boss_id: int = graph.add_node(pre_boss_data, pre_boss_pos)
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
	
	for i in range(1, path_ids.size() - 1):
		var from_id: int = path_ids[i]
		var to_id: int = path_ids[i + 1]
		var from_node := graph.get_node(from_id)
		
		# 随机决定是否插入分支
		if _rng.randf() > branch_chance:
			continue
		
		# 选择分支房间类型
		var branch_type: RoomData.RoomType = _choose_special_room_type(config)
		var branch_data := RoomData.new(branch_type, _current_floor)
		branch_data.auto_size()
		
		# 分支房是物理侧房，只接在主路径房间上，避免生成无法对齐门洞的斜向连接。
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var offset_pos := from_node.position + Vector2(0, ROOM_SPACING.y * side)
		if _is_position_occupied(graph, offset_pos):
			offset_pos = from_node.position + Vector2(0, -ROOM_SPACING.y * side)
		if _is_position_occupied(graph, offset_pos):
			continue
		var branch_id := graph.add_node(branch_data, offset_pos)
		
		graph.add_edge(from_id, branch_id, true)

func _is_position_occupied(graph: NodeGraph, pos: Vector2) -> bool:
	for node in graph.get_all_nodes():
		if node.position.distance_to(pos) < 1.0:
			return true
	return false

## 选择特殊房间类型
func _choose_special_room_type(config: Dictionary) -> RoomData.RoomType:
	var roll := _rng.randf()
	var elite_chance: float = config["elite_chance"]
	var scavenge_chance: float = config["scavenge_chance"]
	var merchant_chance: float = config["merchant_chance"]
	var event_chance: float = config["event_chance"]
	# 深层额外：藏储室和陷阱房概率（各5%，仅深层出现）
	var storage_chance: float = 0.05
	var trap_chance: float = 0.05
	
	if roll < elite_chance:
		return RoomData.RoomType.ELITE
	elif roll < elite_chance + scavenge_chance:
		return RoomData.RoomType.SCAVENGE
	elif roll < elite_chance + scavenge_chance + merchant_chance:
		return RoomData.RoomType.MERCHANT
	elif roll < elite_chance + scavenge_chance + merchant_chance + event_chance:
		return RoomData.RoomType.EVENT
	elif roll < elite_chance + scavenge_chance + merchant_chance + event_chance + storage_chance:
		return RoomData.RoomType.STORAGE
	else:
		return RoomData.RoomType.TRAP

## 确保Boss房存在
func _ensure_boss_room(graph: NodeGraph, path_ids: Array[int]) -> void:
	var last_id: int = path_ids[path_ids.size() - 1]
	var last_node := graph.get_node(last_id)

	# 如果最后一个不是Boss房，创建Boss房
	var last_data: RoomData = last_node.room_data
	if last_data.room_type != RoomData.RoomType.BOSS:
		var boss_data := RoomData.new(RoomData.RoomType.BOSS, _current_floor)
		boss_data.floor_level = RoomData.FloorLevel.DEEP
		boss_data.auto_size()
		# 使用两房间宽度的一半作为间距
		var boss_pos: Vector2 = last_node.position + Vector2((last_data.size.x + boss_data.size.x) * 0.5, 0)
		var boss_id: int = graph.add_node(boss_data, boss_pos)
		graph.add_edge(last_id, boss_id, true)
		path_ids.append(boss_id)
	else:
		# 已经是Boss房，设置为深层并重设尺寸
		last_data.floor_level = RoomData.FloorLevel.DEEP
		last_data.auto_size()

## 确保撤离房存在：默认接在 Boss 前节点附近，玩家可以用钥匙选择前往撤离。
func _ensure_extraction_room(graph: NodeGraph, path_ids: Array[int]) -> void:
	for node in graph.get_all_nodes():
		if node.room_data != null and node.room_data.room_type == RoomData.RoomType.EXTRACTION:
			return
	if path_ids.size() < 2:
		return
	var anchor_index: int = maxi(1, path_ids.size() - 2)
	var anchor_id: int = path_ids[anchor_index]
	var anchor_node := graph.get_node(anchor_id)
	if anchor_node == null:
		return
	var extraction_data := RoomData.new(RoomData.RoomType.EXTRACTION, _current_floor)
	extraction_data.floor_level = RoomData.FloorLevel.MEDIUM
	extraction_data.auto_size()
	var extraction_pos := anchor_node.position + Vector2(0, ROOM_SPACING.y)
	if _is_position_occupied(graph, extraction_pos):
		extraction_pos = anchor_node.position + Vector2(0, -ROOM_SPACING.y)
	var extraction_id := graph.add_node(extraction_data, extraction_pos)
	graph.add_edge(anchor_id, extraction_id, true)

## 设置房间层级
func _set_floor_levels(graph: NodeGraph, path_ids: Array[int]) -> void:
	var n := path_ids.size()
	
	for i in range(n):
		var node: NodeGraph.RoomNode = graph.get_node(path_ids[i])
		var data: RoomData = node.room_data
		
		# 根据位置（从起点到末端）设置层级
		var progress := float(i) / float(max(1, n - 1))
		
		if progress < 0.33:
			data.floor_level = RoomData.FloorLevel.SHALLOW
		elif progress < 0.66:
			data.floor_level = RoomData.FloorLevel.MEDIUM
		else:
			data.floor_level = RoomData.FloorLevel.DEEP


## 生成垂直关卡（地下室、二楼等）
## 每个垂直层都有自己的房间分支，通过楼梯/电梯连接
func _generate_vertical_levels(graph: NodeGraph, main_path: Array[int]) -> void:
	# 地下室概率：每层有30%概率在路径中某处生成地下室分支
	if _rng.randf() < 0.30:
		# 找到适合的分叉点（避开出生房和Boss房）
		var branch_candidates: Array[int] = []
		for j in range(2, main_path.size() - 1):
			var node: NodeGraph.RoomNode = graph.get_node(main_path[j])
			if node != null and node.room_data.room_type != RoomData.RoomType.PLAYER_SPAWN:
				branch_candidates.append(main_path[j])
		
		if not branch_candidates.is_empty():
			# 选择中间位置的一个房间作为地下室入口
			var anchor_idx: int = branch_candidates[branch_candidates.size() / 2]
			var anchor_node: NodeGraph.RoomNode = graph.get_node(anchor_idx)
			
			# 创建楼梯入口（STAIRS_DOWN）和地下室房间
			_add_vertical_branch(graph, anchor_node, RoomData.RoomType.STAIRS_DOWN, RoomData.VerticalLevel.BASEMENT, 1, 2)
		
	# 二楼概率：每层有20%概率生成二楼分支（更深楼层概率更高）
	var upper_chance: float = 0.10 + 0.05 * _current_floor
	if _rng.randf() < upper_chance:
		var branch_candidates: Array[int] = []
		for j in range(1, main_path.size() - 1):
			var node: NodeGraph.RoomNode = graph.get_node(main_path[j])
			if node != null and node.room_data.room_type != RoomData.RoomType.PLAYER_SPAWN:
				branch_candidates.append(main_path[j])
		
		if not branch_candidates.is_empty():
			var anchor_idx: int = branch_candidates[randi() % branch_candidates.size()]
			var anchor_node: NodeGraph.RoomNode = graph.get_node(anchor_idx)
			
			_add_vertical_branch(graph, anchor_node, RoomData.RoomType.STAIRS_UP, RoomData.VerticalLevel.UPPER, 1, 1)


## 添加垂直分支（楼梯口 + 目标垂直楼层的房间组）
func _add_vertical_branch(
	graph: NodeGraph,
	anchor_node: NodeGraph.RoomNode,
	stairs_type: RoomData.RoomType,
	target_vertical: RoomData.VerticalLevel,
	min_rooms: int,
	max_rooms: int
) -> void:
	# 生成楼梯入口房间
	var side_offset: float = -1.0 if _rng.randf() < 0.5 else 1.0
	var stairs_pos: Vector2 = anchor_node.position + Vector2(0, ROOM_SPACING.y * side_offset)
	if _is_position_occupied_by_level(graph, stairs_pos, anchor_node.room_data.vertical_level):
		stairs_pos = anchor_node.position + Vector2(0, -ROOM_SPACING.y * side_offset)
	if _is_position_occupied_by_level(graph, stairs_pos, anchor_node.room_data.vertical_level):
		return  # 无法放置
	
	var stairs_data := RoomData.new(stairs_type, _current_floor)
	stairs_data.vertical_level = anchor_node.room_data.vertical_level
	stairs_data.floor_level = anchor_node.room_data.floor_level
	stairs_data.auto_size()
	var stairs_id := graph.add_node(stairs_data, stairs_pos)
	graph.add_edge(anchor_node.id, stairs_id, true)
	
	# 生成目标垂直层的主房间
	var room_count: int = mini(max_rooms, _rng.randi() % (max_rooms - min_rooms + 1) + min_rooms)
	var target_vertical_level: int = target_vertical
	
	var last_id: int = stairs_id
	var last_pos: Vector2 = stairs_pos
	
	# 目标垂直层的房间位置（与原层平行，向下或向上偏移）
	var vertical_offset: float = 1.0 if target_vertical == RoomData.VerticalLevel.UPPER else -1.0
	
	for i in range(room_count):
		# 选择目标垂直层的房间类型
		var target_room_type: RoomData.RoomType = _choose_vertical_room_type()
		var target_data := RoomData.new(target_room_type, _current_floor)
		target_data.vertical_level = target_vertical
		target_data.floor_level = anchor_node.room_data.floor_level
		
		# 如果是地下室，提升难度（地下室总是更难）
		if target_vertical == RoomData.VerticalLevel.BASEMENT:
			target_data.floor_level = RoomData.FloorLevel.MEDIUM
		
		var target_pos := last_pos + Vector2(ROOM_SPACING.x * 0.5, ROOM_SPACING.y * vertical_offset)
		if _is_position_occupied_by_level(graph, target_pos, target_vertical):
			target_pos = last_pos + Vector2(ROOM_SPACING.x * 0.5, 0)
			if _is_position_occupied_by_level(graph, target_pos, target_vertical):
				continue
		
		var target_id := graph.add_node(target_data, target_pos)
		graph.add_edge(last_id, target_id, true)
		
		last_id = target_id
		last_pos = target_pos


## 选择垂直楼层的房间类型（主要生成搜刮房、战斗房、精英房）
func _choose_vertical_room_type() -> RoomData.RoomType:
	var roll := _rng.randf()
	
	if roll < 0.35:
		return RoomData.RoomType.SCAVENGE  # 地下室多搜刮房（资源更丰富）
	elif roll < 0.60:
		return RoomData.RoomType.COMBAT
	elif roll < 0.80:
		return RoomData.RoomType.ELITE
	elif roll < 0.90:
		return RoomData.RoomType.STORAGE
	else:
		return RoomData.RoomType.EVENT


## 检查指定垂直楼层的位置是否被占用
func _is_position_occupied_by_level(graph: NodeGraph, pos: Vector2, vertical_level: int) -> bool:
	for node in graph.get_all_nodes():
		if node.room_data != null and node.room_data.vertical_level == vertical_level:
			if node.position.distance_to(pos) < ROOM_SPACING.x * 0.3:
				return true
	return false

## 获取当前楼层
func get_current_floor() -> int:
	return _current_floor

## 调试：打印生成的地图
func debug_map(graph: NodeGraph) -> String:
	return graph.debug_print()
