class_name RoomBlueprint
## 房间模板 — 持有房间组件配置列表
## 用于快速实例化标准房间（战斗房/精英房/搜刮房等）

extends Resource

## 房间类型
@export var room_type: RoomData.RoomType = RoomData.RoomType.COMBAT

## 房间像素尺寸
@export var room_size: Vector2 = Vector2(960, 768)

## 组件配置列表（JSON-serializable）
## 每个元素是 Dictionary：{ "type": "FLOOR", "position": [x, y], "config": {...} }
@export var components: Array[Dictionary] = []

## 房间名称（用于调试）
@export var blueprint_name: String = "UnnamedBlueprint"

## 是否为玩家出生房
@export var is_spawn_room: bool = false

## 是否可以搜刮
@export var is_scavengeable: bool = false

## 默认 Blueprint 工厂方法

## 创建普通战斗房模板
static func create_combat_blueprint() -> RoomBlueprint:
	var bp := RoomBlueprint.new()
	bp.blueprint_name = "Combat"
	bp.room_type = RoomData.RoomType.COMBAT
	bp._build_combat_components()
	return bp


## 创建精英战斗房模板
static func create_elite_blueprint() -> RoomBlueprint:
	var bp := RoomBlueprint.new()
	bp.blueprint_name = "Elite"
	bp.room_type = RoomData.RoomType.ELITE
	bp._build_elite_components()
	return bp


## 创建搜刮房模板
static func create_scavenge_blueprint() -> RoomBlueprint:
	var bp := RoomBlueprint.new()
	bp.blueprint_name = "Scavenge"
	bp.room_type = RoomData.RoomType.SCAVENGE
	bp.is_scavengeable = true
	bp._build_scavenge_components()
	return bp


## 创建撤离房模板
static func create_extraction_blueprint() -> RoomBlueprint:
	var bp := RoomBlueprint.new()
	bp.blueprint_name = "Extraction"
	bp.room_type = RoomData.RoomType.EXTRACTION
	bp._build_extraction_components()
	return bp


## 创建玩家出生房模板
static func create_spawn_blueprint() -> RoomBlueprint:
	var bp := RoomBlueprint.new()
	bp.blueprint_name = "Spawn"
	bp.room_type = RoomData.RoomType.PLAYER_SPAWN
	bp.is_spawn_room = true
	bp._build_spawn_components()
	return bp


func _build_combat_components() -> void:
	# 地板格：ROOM_CELLS_X × ROOM_CELLS_Y 内部格
	for cy in range(1, GridConstants.ROOM_CELLS_Y - 1):
		for cx in range(1, GridConstants.ROOM_CELLS_X - 1):
			components.append({
				"type": "FLOOR",
				"cell": [cx, cy],
				"variant": (cx + cy) % 3 == 0,
			})

	# 墙体格：边缘一圈（除去门洞位置）
	for cx in range(GridConstants.ROOM_CELLS_X):
		# 上边墙
		components.append({ "type": "WALL", "cell": [cx, 0], "wall_side": "top" })
		# 下边墙
		components.append({ "type": "WALL", "cell": [cx, GridConstants.ROOM_CELLS_Y - 1], "wall_side": "bottom" })
	for cy in range(GridConstants.ROOM_CELLS_Y):
		# 左边墙
		components.append({ "type": "WALL", "cell": [0, cy], "wall_side": "left" })
		# 右边墙
		components.append({ "type": "WALL", "cell": [GridConstants.ROOM_CELLS_X - 1, cy], "wall_side": "right" })

	# 门洞（左/右边缘中间格，留门洞）
	var door_cell_y: int = GridConstants.ROOM_CELLS_Y / 2
	# 左墙门洞
	components.append({ "type": "DOOR", "direction": Vector2.LEFT, "cell": [0, door_cell_y], "door_side": "left" })
	# 右墙门洞
	components.append({ "type": "DOOR", "direction": Vector2.RIGHT, "cell": [GridConstants.ROOM_CELLS_X - 1, door_cell_y], "door_side": "right" })

	# 敌人出生点（房间中心偏下）
	components.append({ "type": "SPAWN", "cell": [GridConstants.ROOM_CELLS_X / 2, GridConstants.ROOM_CELLS_Y / 2 + 1] })


func _build_elite_components() -> void:
	# 与战斗房类似，但有不同配置
	_build_combat_components()
	# 精英房特殊：地板使用金属风格（variant=true 的地板格）
	# 添加一个强化区装饰（中心格标记）
	components.append({ "type": "DECORATION", "cell": [GridConstants.ROOM_CELLS_X / 2, GridConstants.ROOM_CELLS_Y / 2], "style": "elite_glow" })


func _build_scavenge_components() -> void:
	_build_combat_components()
	# 搜刮房额外：添加容器组件
	var container_cells := [
		Vector2i(GridConstants.ROOM_CELLS_X / 2 - 2, GridConstants.ROOM_CELLS_Y / 2 - 1),
		Vector2i(GridConstants.ROOM_CELLS_X / 2 + 2, GridConstants.ROOM_CELLS_Y / 2 + 1),
		Vector2i(GridConstants.ROOM_CELLS_X / 2, 3),
	]
	for cell in container_cells:
		components.append({ "type": "INTERACT", "cell": [cell.x, cell.y], "interact_type": "container" })


func _build_extraction_components() -> void:
	_build_combat_components()
	# 撤离房特殊：中心撤离点
	components.append({ "type": "TRIGGER", "cell": [GridConstants.ROOM_CELLS_X / 2, GridConstants.ROOM_CELLS_Y / 2], "trigger_type": "extraction" })


func _build_spawn_components() -> void:
	_build_combat_components()
	# 出生房额外：玩家出生点
	components.append({ "type": "SPAWN", "cell": [GridConstants.ROOM_CELLS_X / 2, GridConstants.ROOM_CELLS_Y / 2], "spawn_type": "player" })


## 获取指定类型的组件配置列表
func get_components_by_type(component_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for comp in components:
		if comp.get("type", "") == component_type:
			result.append(comp)
	return result


## 获取门组件列表
func get_door_components() -> Array[Dictionary]:
	return get_components_by_type("DOOR")


## 获取出生点组件列表
func get_spawn_components() -> Array[Dictionary]:
	return get_components_by_type("SPAWN")


## 验证 Blueprint 完整性
func validate() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	# 检查是否有地板格
	var floor_count: int = get_components_by_type("FLOOR").size()
	if floor_count == 0:
		errors.append("No floor tiles in blueprint")

	# 检查是否有墙体格
	var wall_count: int = get_components_by_type("WALL").size()
	if wall_count == 0:
		errors.append("No wall tiles in blueprint")

	# 检查是否有至少一个门
	var door_count: int = get_components_by_type("DOOR").size()
	if door_count == 0:
		warnings.append("No doors in blueprint (room may be isolated)")

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"floor_count": floor_count,
		"wall_count": wall_count,
		"door_count": door_count,
	}