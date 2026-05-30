class_name RoomTileMapInitializer
extends Node2D
## 房间 TileMap 初始化器 — 用于非 Combat 房间
## 读取 room_type 配置，构建 TileSet 并填充 TileMap
## 挂载在每个房间场景的 Visualizer 节点上
## P2: 集成门过渡视觉（DoorVisualizer）+ 边界碰撞体门洞支持

# WorldPlaceholder is the black void at z=-20; walkable floor must remain above it
# while still drawing underneath walls, entities, and interaction markers.
const FLOOR_Z_INDEX := -12
const AMBIENT_Z_INDEX := -11

@export var room_type: RoomData.RoomType = RoomData.RoomType.COMBAT
@export
var room_size: Vector2 = Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)  # 默认房间尺寸 960×768

@onready var floor_layer: TileMapLayer = $"../FloorLayer" as TileMapLayer

var _tile_set_builder: RoomTileSetBuilder = RoomTileSetBuilder.new()
var _built: bool = false
var _door_info: Array[Dictionary] = []
var _boundary_collision_enabled := true
var _current_floor: int = 1  ## 当前楼层，用于楼层感知配色

## 门过渡视觉引用（由场景中 DoorVisualizer 子节点赋值）
@onready var door_visualizer: Node2D = $"../DoorVisualizer" as Node2D


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

	floor_layer.z_index = FLOOR_Z_INDEX
	_tile_set_builder.build_tile_set(floor_layer, room_type, _current_floor)
	_tile_set_builder.populate_room_tilemap(floor_layer, room_size, room_type, _current_floor, _door_info)

	# 应用氛围主题（角落暗角）
	_apply_ambient()
	# 碰撞由 RoomLayout 统一提供，不再创建 BoundaryCollision

	# 应用门过渡视觉
	_apply_door_visualization()

	# FloorLayer 是地面表现层。结构墙与门洞的遮挡由 RoomLayout 统一建立，
	# 实体物品则通过显式遮挡组件接入，避免装饰砖块投出假阴影。


## 应用氛围主题（角落暗角装饰）
func _apply_ambient() -> void:
	var theme: Dictionary = _tile_set_builder.get_room_theme_colors(room_type, _current_floor)
	var ambient: Node2D = get_node_or_null("../AmbientDecoration")
	if ambient == null:
		return
	ambient.z_index = AMBIENT_Z_INDEX

	# 动态设置角落阴影颜色（基于地板色）
	var floor_color: Color = theme.get("floor", Color.GRAY)

	# 遍历角落阴影节点，应用色调
	for i in range(ambient.get_child_count()):
		var child: Node = ambient.get_child(i)
		if child is ColorRect and child.name.begins_with("CornerShadow"):
			var shadow: ColorRect = child as ColorRect
			shadow.color = Color(
				floor_color.r * 0.4, floor_color.g * 0.3, floor_color.b * 0.2, 0.45
			)


## 应用门过渡视觉（根据门信息显示方向标记）
func _apply_door_visualization() -> void:
	if _door_info.is_empty() or door_visualizer == null:
		return
	if door_visualizer.has_method("configure"):
		door_visualizer.configure(_door_info)


## 重置视觉（房间重新进入时）
func reset_visual() -> void:
	_built = false


func configure(
	p_room_type: RoomData.RoomType,
	p_room_size: Vector2,
	p_door_info: Array[Dictionary] = [],
	p_floor: int = 1
) -> void:
	room_type = p_room_type
	room_size = p_room_size
	_door_info = p_door_info
	_current_floor = p_floor
	var boundary_collision := get_node_or_null("BoundaryCollision")
	if boundary_collision != null:
		boundary_collision.queue_free()
	if floor_layer != null:
		_built = false
		floor_layer.clear()
		build()


func set_open_doors(p_door_info: Array[Dictionary]) -> void:
	_door_info = p_door_info
	_apply_door_visualization()
	# 墙体碰撞由 TileSet 的 physics_layer_0 提供，不再使用独立的 BoundaryCollision StaticBody2D


func set_boundary_collision_enabled(enabled: bool) -> void:
	_boundary_collision_enabled = enabled
	if not enabled:
		var boundary_collision := get_node_or_null("BoundaryCollision")
		if boundary_collision != null:
			boundary_collision.queue_free()
	# 碰撞由 RoomLayout 统一提供，不再创建 BoundaryCollision


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
	parent.add_child(shape)

## 更新玩家光源位置（每帧调用，或通过信号驱动）
static func update_player_light_position(parent: Node2D, player_pos: Vector2) -> void:
	var light: PointLight2D = parent.find_child("PlayerVisionLight", true, false) as PointLight2D
	if light and is_instance_valid(light):
		light.global_position = player_pos
