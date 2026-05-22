class_name RoomFactory
## 房间工厂 — 将 RoomData 实例化为游戏场景节点

## 场景预制件映射（未来会从外部配置加载）
## 目前先用占位符场景名称
const SCENE_MAP := {
	RoomData.RoomType.PLAYER_SPAWN: "res://scenes/RoomSpawn.tscn",
	RoomData.RoomType.COMBAT: "res://scenes/RoomCombat.tscn",
	RoomData.RoomType.ELITE: "res://scenes/RoomElite.tscn",
	RoomData.RoomType.SCAVENGE: "res://scenes/RoomScavenge.tscn",
	RoomData.RoomType.MERCHANT: "res://scenes/RoomMerchant.tscn",
	RoomData.RoomType.UPGRADE: "res://scenes/RoomUpgrade.tscn",
	RoomData.RoomType.EVENT: "res://scenes/RoomEvent.tscn",
	RoomData.RoomType.EXTRACTION: "res://scenes/RoomExtraction.tscn",
	RoomData.RoomType.BOSS: "res://scenes/RoomBoss.tscn",
}

var _scene_cache: Dictionary = {}

## 创建房间实例
func create_room(room_data: RoomData, parent: Node = null) -> Node2D:
	var scene_path: String = SCENE_MAP.get(room_data.room_type, SCENE_MAP[RoomData.RoomType.COMBAT])
	var room_instance: Node2D
	
	# 尝试加载场景
	var scene: PackedScene = _scene_cache.get(scene_path)
	if scene == null:
		if ResourceLoader.exists(scene_path):
			scene = load(scene_path) as PackedScene
			_scene_cache[scene_path] = scene
	
	if scene != null:
		room_instance = scene.instantiate() as Node2D
	else:
		# 场景不存在，创建占位符节点
		room_instance = _create_placeholder_room(room_data)
	
	room_instance.name = "Room_%s_%d" % [RoomData.get_type_name(room_data.room_type), room_data.floor]
	room_instance.position = room_data.position
	
	if parent != null:
		parent.add_child(room_instance)
	
	return room_instance

## 创建占位符房间节点（场景不存在时的回退）
func _create_placeholder_room(room_data: RoomData) -> Node2D:
	var node := Node2D.new()
	node.set_meta("room_data", room_data)
	node.set_meta("room_id", room_data.room_id)
	
	# 根据房间类型设置不同颜色用于调试
	var color := _get_room_debug_color(room_data.room_type)
	
	# 添加一个可见的调试精灵
	var debug_sprite := ColorRect.new()
	debug_sprite.size = room_data.size
	debug_sprite.color = color
	debug_sprite.name = "DebugRect"
	node.add_child(debug_sprite)
	
	return node

## 获取房间调试颜色
func _get_room_debug_color(room_type: RoomData.RoomType) -> Color:
	match room_type:
		RoomData.RoomType.PLAYER_SPAWN: return Color(0.2, 0.8, 0.2, 0.3)
		RoomData.RoomType.COMBAT: return Color(0.8, 0.2, 0.2, 0.3)
		RoomData.RoomType.ELITE: return Color(0.9, 0.5, 0.1, 0.3)
		RoomData.RoomType.SCAVENGE: return Color(0.3, 0.7, 0.9, 0.3)
		RoomData.RoomType.MERCHANT: return Color(0.9, 0.9, 0.2, 0.3)
		RoomData.RoomType.UPGRADE: return Color(0.6, 0.3, 0.9, 0.3)
		RoomData.RoomType.EVENT: return Color(0.4, 0.2, 0.6, 0.3)
		RoomData.RoomType.EXTRACTION: return Color(0.1, 0.9, 0.5, 0.3)
		RoomData.RoomType.BOSS: return Color(0.7, 0.1, 0.1, 0.5)
		_: return Color(0.5, 0.5, 0.5, 0.3)

## 根据房间标签过滤场景
func get_scene_for_tags(tags: Array[String]) -> String:
	# 优先匹配标签的场景
	for tag in tags:
		# 特定标签对应的场景（可扩展）
		pass
	# 默认返回普通战斗房
	return SCENE_MAP[RoomData.RoomType.COMBAT]

## 预加载所有房间场景
func preload_scenes() -> void:
	for scene_path in SCENE_MAP.values():
		if not _scene_cache.has(scene_path) and ResourceLoader.exists(scene_path):
			var scene := load(scene_path) as PackedScene
			if scene != null:
				_scene_cache[scene_path] = scene