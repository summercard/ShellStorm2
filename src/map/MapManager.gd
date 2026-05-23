class_name MapManager
extends Node2D
## 地图总管理器 — 整合所有地图模块，管理地图生成和房间切换

signal map_generated(graph: NodeGraph)
signal room_entered(room_data: RoomData)
signal room_exited(room_id: String)
signal floor_changed(old_floor: int, new_floor: int)
signal all_rooms_cleared()

var map_generator: MapGenerator
var room_factory: RoomFactory
var path_director: PathDirector
var content_injector: ContentInjector
var monster_injector: MonsterInjector
var extraction_director: ExtractionDirector
var boss_director: BossRoomDirector

var _current_graph: NodeGraph = null
var _current_room_id: int = -1
var _current_floor: int = 1
var _instantiated_rooms: Dictionary = {}  # node_id -> Node2D
var _spawned_enemies: Dictionary = {}  # room_id -> Array[Dictionary]

func _init():
	map_generator = MapGenerator.new()
	room_factory = RoomFactory.new()
	path_director = PathDirector.new()
	content_injector = ContentInjector.new()
	monster_injector = MonsterInjector.new()
	extraction_director = ExtractionDirector.new()
	boss_director = BossRoomDirector.new()
	boss_director.set_extraction_director(extraction_director)

	path_director.set_graph(null)

## 生成地图
func generate_map(floor: int, seed_value: int = -1) -> NodeGraph:
	_current_floor = floor
	_spawned_enemies.clear()
	_current_graph = map_generator.generate(floor, seed_value)
	path_director.set_graph(_current_graph)

	# 为每个节点添加路径连接
	_add_all_connections()

	# 为每个房间注入可交互物、事件和敌人计划
	_inject_content_for_all_rooms()

	# 注册Boss房
	_register_boss_rooms()

	# 添加撤离点
	_setup_extraction_points()

	map_generated.emit(_current_graph)
	return _current_graph

## 添加所有房间的路径连接
func _add_all_connections() -> void:
	if _current_graph == null:
		return

	var nodes: Array = _current_graph.get_all_nodes()
	for node in nodes:
		for conn_id in node.connections:
			path_director.add_connection(node.id, conn_id, true)

func _inject_content_for_all_rooms() -> void:
	if _current_graph == null:
		return

	var nodes: Array = _current_graph.get_all_nodes()
	for node in nodes:
		var room_data: RoomData = node.room_data
		var content_config: ContentInjector.ContentConfig = content_injector.inject(room_data)
		room_data.set_content_config(content_config.to_dict())
		_spawned_enemies[node.id] = _spawn_enemies_from_config(content_config, node)

## 注册所有Boss房
func _register_boss_rooms() -> void:
	if _current_graph == null:
		return

	var nodes: Array = _current_graph.get_all_nodes()
	for node in nodes:
		var data: RoomData = node.room_data
		if data.room_type == RoomData.RoomType.BOSS:
			boss_director.register_boss_room(data.room_id, "boss_%d" % [_current_floor])

## 设置撤离点
func _setup_extraction_points() -> void:
	# 添加基础撤离点
	extraction_director.add_extraction_point(ExtractionDirector.ExtractionType.STANDARD)

	# 中层以上预设精英撤离点（由精英击杀事件触发 unlock_elite_extraction）
	if _current_floor >= 2:
		extraction_director.add_extraction_point(
			ExtractionDirector.ExtractionType.ELITE_KILL,
			{"floor_min": 2, "pre_placed": true}
		)
		# 初始为 LOCKED，等待精英击杀后由 ExtractionDirector.unlock_elite_extraction() 解锁
		# 不调用 unlock_extraction()，让它保持 is_unlocked=false

	# Boss房撤离由 BossRoomDirector 在击败后通过注入的 extraction_director 引用解锁

## 实例化地图到场景
func instantiate_map(parent: Node2D) -> void:
	if _current_graph == null:
		return

	var nodes: Array = _current_graph.get_all_nodes()
	for node in nodes:
		var room_instance: Node2D = room_factory.create_room(node.room_data, parent)
		_instantiated_rooms[node.id] = room_instance

		# 注入内容
		var content_config: ContentInjector.ContentConfig = content_injector.inject(node.room_data)
		_spawned_enemies[node.id] = _spawn_enemies_from_config(content_config, node)

## 从配置生成敌人
func _spawn_enemies_from_config(config: ContentInjector.ContentConfig, node) -> Array[Dictionary]:
	var spawned: Array[Dictionary] = []

	for enemy_config in config.enemies:
		if not enemy_config.has("floor"):
			enemy_config["floor"] = node.room_data.floor
		if not enemy_config.has("floor_level"):
			enemy_config["floor_level"] = node.room_data.floor_level
		var enemies: Array[Dictionary] = monster_injector.generate_enemies(enemy_config)
		for enemy_data in enemies:
			spawned.append(enemy_data)

	return spawned

## 进入房间
func enter_room(node_id: int) -> RoomData:
	if _current_graph == null:
		return null

	var node := _current_graph.get_node(node_id)
	if node == null:
		return null

	_current_room_id = node_id
	var data: RoomData = node.room_data

	# 开启该房间的门
	path_director.open_doors_from(node_id)

	# 如果是Boss房，生成Boss
	if data.room_type == RoomData.RoomType.BOSS:
		boss_director.spawn_boss(data.room_id, _current_floor, {})

	room_entered.emit(data)
	return data

## 离开房间
func exit_room() -> void:
	if _current_room_id < 0:
		return

	var node := _current_graph.get_node(_current_room_id)
	if node != null:
		room_exited.emit(node.room_data.room_id)

	_current_room_id = -1

## 获取当前房间数据
func get_current_room_data() -> RoomData:
	if _current_room_id < 0 or _current_graph == null:
		return null

	var node := _current_graph.get_node(_current_room_id)
	if node == null:
		return null

	return node.room_data

## 获取当前房间的怪物列表
func get_current_room_enemies() -> Array[Dictionary]:
	if _current_room_id < 0:
		return []

	var enemies: Array[Dictionary] = _spawned_enemies.get(_current_room_id, [])
	# 只返回还存活的
	var alive: Array[Dictionary] = []
	for e in enemies:
		if e.get("hp", 0) > 0:
			alive.append(e)
	return alive

func get_current_room_enemy_plan() -> Array[Dictionary]:
	if _current_room_id < 0:
		return []
	var result: Array[Dictionary] = []
	for enemy_data in _spawned_enemies.get(_current_room_id, []):
		if enemy_data is Dictionary:
			result.append(enemy_data.duplicate(true))
	return result

## 获取当前房间已击杀的敌人数量
func get_current_room_killed_count() -> int:
	if _current_room_id < 0:
		return 0

	var enemies: Array[Dictionary] = _spawned_enemies.get(_current_room_id, [])
	var killed: int = 0
	for e in enemies:
		if e.get("hp", 0) <= 0:
			killed += 1
	return killed

## 检查房间是否已清理（所有敌人死亡）
func is_current_room_cleared() -> bool:
	var alive_enemies: Array[Dictionary] = get_current_room_enemies()

	# 如果是Boss房，需要Boss也被击败
	var room_data: RoomData = get_current_room_data()
	if room_data != null and room_data.room_type == RoomData.RoomType.BOSS:
		return boss_director.is_boss_defeated() and alive_enemies.is_empty()

	return alive_enemies.is_empty()

## 前进到下一层
func advance_to_next_floor() -> NodeGraph:
	var new_floor: int = _current_floor + 1
	floor_changed.emit(_current_floor, new_floor)
	return generate_map(new_floor)

## 获取可用撤离点列表
func get_available_extractions() -> Array:
	return extraction_director.get_available_extractions()

## 使用撤离点
func use_extraction(point_id: String) -> bool:
	return extraction_director.start_extraction(point_id)

## 获取地图节点图
func get_graph() -> NodeGraph:
	return _current_graph

## 获取当前楼层
func get_current_floor() -> int:
	return _current_floor

## 获取已实例化的房间节点
func get_instantiated_room(node_id: int) -> Node2D:
	return _instantiated_rooms.get(node_id)

## 登记外部实例化的房间节点（供 RoomGameMode 手动布置房间时同步状态）
func register_instantiated_room(node_id: int, room_node: Node2D) -> void:
	if room_node == null:
		return
	_instantiated_rooms[node_id] = room_node

## 清除所有房间
func clear_all_rooms() -> void:
	for room_node in _instantiated_rooms.values():
		if is_instance_valid(room_node):
			room_node.queue_free()

	_instantiated_rooms.clear()
	_spawned_enemies.clear()
	_current_graph = null
	_current_room_id = -1

	extraction_director.clear()
	boss_director.clear()

	all_rooms_cleared.emit()

## 调试：打印地图状态
func debug_status() -> String:
	var lines: Array[String] = [
		"MapManager Floor %d" % [_current_floor],
		"Rooms: %d instantiated" % [_instantiated_rooms.size()]
	]

	if _current_graph != null:
		lines.append(_current_graph.debug_print())

	lines.append("")
	lines.append(extraction_director.debug_status())
	lines.append("")
	lines.append(boss_director.debug_status())

	return "\n".join(lines)
