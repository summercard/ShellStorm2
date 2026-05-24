class_name RoomTileMapInitializer
extends Node2D
## 房间 TileMap 初始化器 — 用于非 Combat 房间
## 读取 room_type 配置，构建 TileSet 并填充 TileMap
## 挂载在每个房间场景的 Visualizer 节点上

@export var room_type: RoomData.RoomType = RoomData.RoomType.COMBAT
@export var room_size: Vector2 = Vector2(800, 600)

@onready var floor_layer: TileMapLayer = $"../FloorLayer" as TileMapLayer

var _tile_set_builder: RoomTileSetBuilder = RoomTileSetBuilder.new()
var _built: bool = false
var _door_info: Array[Dictionary] = []


func _ready() -> void:
	if floor_layer != null and room_type != RoomData.RoomType.INVALID:
		build()


## 构建 TileMap（运行时构建纯色占位 TileSet）
func build() -> void:
	if _built:
		return
	_built = true
	
	if floor_layer == null:
		push_warning("[RoomTileMapInitializer] FloorLayer not found, skipping tile map build")
		return
	
	_tile_set_builder.build_tile_set(floor_layer, room_type)
	_tile_set_builder.populate_room_tilemap(floor_layer, room_size, room_type)
	
	# 应用氛围主题（角落暗角）
	_apply_ambient()
	_ensure_boundary_collision()


## 应用氛围主题（角落暗角装饰）
func _apply_ambient() -> void:
	var theme: Dictionary = _tile_set_builder.get_room_theme_colors(room_type)
	var ambient: Node2D = $"../AmbientDecoration"
	if ambient == null:
		return
	
	# 动态设置角落阴影颜色（基于地板色）
	var floor_color: Color = theme.get("floor", Color.GRAY)
	
	# 遍历角落阴影节点，应用色调
	for i in range(ambient.get_child_count()):
		var child: Node = ambient.get_child(i)
		if child is ColorRect and child.name.begins_with("CornerShadow"):
			var shadow: ColorRect = child as ColorRect
			shadow.color = Color(floor_color.r * 0.4, floor_color.g * 0.3, floor_color.b * 0.2, 0.45)


## 重置视觉（房间重新进入时）
func reset_visual() -> void:
	_built = false


func configure(p_room_type: RoomData.RoomType, p_room_size: Vector2, p_door_info: Array[Dictionary] = []) -> void:
	room_type = p_room_type
	room_size = p_room_size
	_door_info = p_door_info
	var boundary_collision := get_node_or_null("BoundaryCollision")
	if boundary_collision != null:
		boundary_collision.queue_free()
	if floor_layer != null:
		_built = false
		floor_layer.clear()
		build()


func set_open_doors(p_door_info: Array[Dictionary]) -> void:
	_door_info = p_door_info
	var boundary_collision := get_node_or_null("BoundaryCollision")
	if boundary_collision != null:
		boundary_collision.queue_free()
	_ensure_boundary_collision()


func _ensure_boundary_collision() -> void:
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
	_add_horizontal_boundary(body, "Top", -half.y - thickness * 0.5, room_size.x + thickness * 2.0, thickness, _has_open_door(Vector2.UP), door_width)
	_add_horizontal_boundary(body, "Bottom", half.y + thickness * 0.5, room_size.x + thickness * 2.0, thickness, _has_open_door(Vector2.DOWN), door_width)
	_add_vertical_boundary(body, "Left", -half.x - thickness * 0.5, room_size.y + thickness * 2.0, thickness, _has_open_door(Vector2.LEFT), door_width)
	_add_vertical_boundary(body, "Right", half.x + thickness * 0.5, room_size.y + thickness * 2.0, thickness, _has_open_door(Vector2.RIGHT), door_width)


func _has_open_door(direction: Vector2) -> bool:
	for info in _door_info:
		if not bool(info.get("is_open", false)):
			continue
		var door_direction: Vector2 = info.get("direction", Vector2.ZERO)
		if door_direction == direction:
			return true
	return false


func _add_horizontal_boundary(parent: Node, prefix: String, y: float, total_width: float, thickness: float, has_gap: bool, gap_width: float) -> void:
	if not has_gap:
		_add_boundary_wall(parent, prefix, Vector2(0, y), Vector2(total_width, thickness))
		return
	var side_width: float = max(1.0, (total_width - gap_width) * 0.5)
	var offset: float = gap_width * 0.5 + side_width * 0.5
	_add_boundary_wall(parent, prefix + "Left", Vector2(-offset, y), Vector2(side_width, thickness))
	_add_boundary_wall(parent, prefix + "Right", Vector2(offset, y), Vector2(side_width, thickness))


func _add_vertical_boundary(parent: Node, prefix: String, x: float, total_height: float, thickness: float, has_gap: bool, gap_width: float) -> void:
	if not has_gap:
		_add_boundary_wall(parent, prefix, Vector2(x, 0), Vector2(thickness, total_height))
		return
	var side_height: float = max(1.0, (total_height - gap_width) * 0.5)
	var offset: float = gap_width * 0.5 + side_height * 0.5
	_add_boundary_wall(parent, prefix + "Top", Vector2(x, -offset), Vector2(thickness, side_height))
	_add_boundary_wall(parent, prefix + "Bottom", Vector2(x, offset), Vector2(thickness, side_height))


func _add_boundary_wall(parent: Node, wall_name: String, wall_position: Vector2, wall_size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	shape.name = wall_name
	var rect := RectangleShape2D.new()
	rect.size = wall_size
	shape.shape = rect
	shape.position = wall_position
	parent.add_child(shape)
