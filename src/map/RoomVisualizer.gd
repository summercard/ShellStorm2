class_name RoomVisualizer
extends Node2D
## 房间视觉化组件
## 负责：TileMap 地面/墙体 + 氛围装饰 + 房间过渡视觉
## 由 RoomGameMode 在进入房间时根据 room_type 配置并触发构建

signal visual_ready

@export var room_type: RoomData.RoomType = RoomData.RoomType.COMBAT
@export
var room_size: Vector2 = Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)  # 默认房间尺寸 960×768

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var ambient: Node2D = $AmbientDecoration
@onready var door_visualizer: Node2D = $DoorVisualizer

var _tile_set_builder: RoomTileSetBuilder = RoomTileSetBuilder.new()
var _is_built: bool = false
var _door_info: Array[Dictionary] = []
var _boundary_collision_enabled := true


func _ready() -> void:
	# 等待 RoomGameMode 调用 configure(room_type, room_size)
	# 暂时在此处用默认值构建（演示用）
	if room_type != RoomData.RoomType.INVALID:
		build_visual()


## 配置房间视觉（由 RoomGameMode 调用，进入房间时）
## p_room_type: 房间类型
## p_room_size: 房间像素尺寸
## p_door_info: 可选，Array[Dictionary] 包含门方向信息（来自 PathDirector.get_open_door_info）
func configure(
	p_room_type: RoomData.RoomType, p_room_size: Vector2, p_door_info: Array[Dictionary] = []
) -> void:
	room_type = p_room_type
	room_size = p_room_size
	_door_info = p_door_info
	if _is_built:
		reset_visual()
	build_visual()


func set_open_doors(p_door_info: Array[Dictionary]) -> void:
	_door_info = p_door_info
	_apply_door_visualization()
	if not _boundary_collision_enabled:
		return
	var boundary_collision := get_node_or_null("BoundaryCollision")
	if boundary_collision != null:
		boundary_collision.queue_free()
	call_deferred("_ensure_boundary_collision")


func set_boundary_collision_enabled(enabled: bool) -> void:
	_boundary_collision_enabled = enabled
	if not enabled:
		var boundary_collision := get_node_or_null("BoundaryCollision")
		if boundary_collision != null:
			boundary_collision.queue_free()
	elif _is_built:
		call_deferred("_ensure_boundary_collision")


## 构建房间视觉（TileMap + 氛围装饰 + 门过渡视觉）
func build_visual() -> void:
	if _is_built:
		return
	_is_built = true

	# 构建 TileSet 并填充 TileMap
	_tile_set_builder.build_tile_set(floor_layer, room_type)
	_tile_set_builder.populate_room_tilemap(floor_layer, room_size, room_type)

	# 根据房间类型配置氛围装饰
	_apply_ambient_theme()

	# 门过渡视觉（如果有门信息）
	_apply_door_visualization()

	_ensure_boundary_collision()

	visual_ready.emit()


## 应用房间氛围主题（设置装饰节点颜色/可见性）
func _apply_ambient_theme() -> void:
	var theme: Dictionary = _tile_set_builder.get_room_theme_colors(room_type)

	# 更新边界叠加层颜色（与房间主色调呼应）
	var boundary: ColorRect = get_node_or_null("BoundaryOverlay") as ColorRect
	if boundary:
		var floor_color: Color = theme.get("floor", Color.GRAY)
		boundary.color = Color(floor_color.r * 0.5, floor_color.g * 0.5, floor_color.b * 0.55, 0.25)

	# 更新区域标记颜色
	var zone: ColorRect = get_node_or_null("ZoneMarker_Center") as ColorRect
	if zone:
		var accent_color: Color = theme.get("accent", Color.GRAY)
		zone.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.08)

	# 根据房间类型显示/隐藏特殊装饰
	match room_type:
		RoomData.RoomType.BOSS:
			# Boss 房：更暗的全局氛围 + 中央光圈
			_add_boss_center_glow()
		RoomData.RoomType.MERCHANT:
			# 商人房：暖色光斑
			_add_merchant_glow()
		RoomData.RoomType.TRAP:
			# 陷阱房：警告标记
			_show_trap_warnings()
		RoomData.RoomType.ELITE:
			# 精英房：暗红色氛围光斑（区别于普通战斗房）
			_add_elite_glow()
		_:
			pass


## 应用门过渡视觉（根据门信息显示方向标记）
func _apply_door_visualization() -> void:
	if _door_info.is_empty() or door_visualizer == null:
		return

	# 门标记已在场景中配置，直接配置门方向
	if door_visualizer.has_method("configure"):
		door_visualizer.configure(_door_info)


## Boss 房：中央深红光圈（提示 Boss 站位）
func _add_boss_center_glow() -> void:
	var glow := ColorRect.new()
	glow.name = "BossCenterGlow"
	glow.custom_minimum_size = Vector2(160, 160)
	glow.size = Vector2(160, 160)
	glow.position = Vector2(-80, -80)
	glow.z_index = -3
	glow.color = Color(0.5, 0.05, 0.02, 0.15)
	ambient.add_child(glow)


## 商人房：暖色环境光斑
func _add_merchant_glow() -> void:
	var glow := ColorRect.new()
	glow.name = "MerchantGlow"
	glow.custom_minimum_size = Vector2(200, 200)
	glow.size = Vector2(200, 200)
	glow.position = Vector2(-100, -100)
	glow.z_index = -3
	glow.color = Color(0.9, 0.75, 0.20, 0.08)
	ambient.add_child(glow)


## 精英房：暗红色压迫光斑（区别于普通战斗房）
func _add_elite_glow() -> void:
	var glow := ColorRect.new()
	glow.name = "EliteGlow"
	glow.custom_minimum_size = Vector2(240, 240)
	glow.size = Vector2(240, 240)
	glow.position = Vector2(-120, -120)
	glow.z_index = -3
	glow.color = Color(0.45, 0.08, 0.03, 0.12)
	ambient.add_child(glow)


## 陷阱房：显示警告标记
func _show_trap_warnings() -> void:
	# 陷阱房已有 TrapWarningLabel，在 RoomTrap.tscn 中
	pass


## 获取当前房间的主题色（供其他组件使用）
func get_theme_colors() -> Dictionary:
	return _tile_set_builder.get_room_theme_colors(room_type)


## 重置视觉（房间重新进入时调用）
func reset_visual() -> void:
	_is_built = false
	if floor_layer != null:
		floor_layer.clear()
	var boundary_collision := get_node_or_null("BoundaryCollision")
	if boundary_collision != null:
		boundary_collision.queue_free()
	# 清理氛围子节点（保留 AmbientDecoration 本身）
	if ambient != null:
		for child in ambient.get_children():
			child.queue_free()
	if door_visualizer != null and door_visualizer.has_method("_reset"):
		door_visualizer.call("_reset")


func _ensure_boundary_collision() -> void:
	if not _boundary_collision_enabled:
		return
	if get_node_or_null("BoundaryCollision") != null:
		return
	var body := StaticBody2D.new()
	body.name = "BoundaryCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var half := room_size * 0.5
	var thickness := 40.0
	var door_width := 132.0
	_add_horizontal_boundary(
		body,
		"Top",
		-half.y - thickness * 0.5,
		room_size.x + thickness * 2.0,
		thickness,
		_has_open_door(Vector2.UP),
		door_width
	)
	_add_horizontal_boundary(
		body,
		"Bottom",
		half.y + thickness * 0.5,
		room_size.x + thickness * 2.0,
		thickness,
		_has_open_door(Vector2.DOWN),
		door_width
	)
	_add_vertical_boundary(
		body,
		"Left",
		-half.x - thickness * 0.5,
		room_size.y + thickness * 2.0,
		thickness,
		_has_open_door(Vector2.LEFT),
		door_width
	)
	_add_vertical_boundary(
		body,
		"Right",
		half.x + thickness * 0.5,
		room_size.y + thickness * 2.0,
		thickness,
		_has_open_door(Vector2.RIGHT),
		door_width
	)


func _has_open_door(direction: Vector2) -> bool:
	for info in _door_info:
		if not bool(info.get("is_open", false)):
			continue
		var door_direction: Vector2 = info.get("direction", Vector2.ZERO)
		if door_direction == direction:
			return true
	return false


func _add_horizontal_boundary(
	parent: Node,
	prefix: String,
	y: float,
	total_width: float,
	thickness: float,
	has_gap: bool,
	gap_width: float
) -> void:
	if not has_gap:
		_add_boundary_wall(parent, prefix, Vector2(0, y), Vector2(total_width, thickness))
		return
	var side_width: float = max(1.0, (total_width - gap_width) * 0.5)
	var offset: float = gap_width * 0.5 + side_width * 0.5
	_add_boundary_wall(parent, prefix + "Left", Vector2(-offset, y), Vector2(side_width, thickness))
	_add_boundary_wall(parent, prefix + "Right", Vector2(offset, y), Vector2(side_width, thickness))


func _add_vertical_boundary(
	parent: Node,
	prefix: String,
	x: float,
	total_height: float,
	thickness: float,
	has_gap: bool,
	gap_width: float
) -> void:
	if not has_gap:
		_add_boundary_wall(parent, prefix, Vector2(x, 0), Vector2(thickness, total_height))
		return
	var side_height: float = max(1.0, (total_height - gap_width) * 0.5)
	var offset: float = gap_width * 0.5 + side_height * 0.5
	_add_boundary_wall(parent, prefix + "Top", Vector2(x, -offset), Vector2(thickness, side_height))
	_add_boundary_wall(
		parent, prefix + "Bottom", Vector2(x, offset), Vector2(thickness, side_height)
	)


func _add_boundary_wall(
	parent: Node, wall_name: String, wall_position: Vector2, wall_size: Vector2
) -> void:
	var shape := CollisionShape2D.new()
	shape.name = wall_name
	var rect := RectangleShape2D.new()
	rect.size = wall_size
	shape.shape = rect
	shape.position = wall_position
	# Godot 4 不允许在物理查询flush期间改变碰撞体状态，必须延迟添加
	parent.call_deferred("add_child", shape)
