class_name RoomTileMapInitializer
extends Node2D
## 房间 TileMap 初始化器 — 用于非 Combat 房间
## 读取 room_type 配置，构建 TileSet 并填充 TileMap
## 挂载在每个房间场景的 Visualizer 节点上
## P2: 集成门过渡视觉（DoorVisualizer）+ 边界碰撞体门洞支持

@export var room_type: RoomData.RoomType = RoomData.RoomType.COMBAT
@export
var room_size: Vector2 = Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)  # 默认房间尺寸 960×768

@onready var floor_layer: TileMapLayer = $"../FloorLayer" as TileMapLayer

var _tile_set_builder: RoomTileSetBuilder = RoomTileSetBuilder.new()
var _built: bool = false
var _door_info: Array[Dictionary] = []
var _boundary_collision_enabled := true

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

	_tile_set_builder.build_tile_set(floor_layer, room_type)
	_tile_set_builder.populate_room_tilemap(floor_layer, room_size, room_type)

	# 应用氛围主题（角落暗角）
	_apply_ambient()
	_ensure_boundary_collision()

	# 应用门过渡视觉
	_apply_door_visualization()

	# 构建视野遮挡层（墙体 occluder + 暗色层）
	_build_vision_layer()


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
			shadow.color = Color(
				floor_color.r * 0.4, floor_color.g * 0.3, floor_color.b * 0.2, 0.45
			)


## 构建视野遮挡层：墙体 LightOccluder + CanvasModulate 暗色层
func _build_vision_layer() -> void:
	var parent: Node2D = get_parent() as Node2D
	if parent == null:
		return
	
	# 检查是否已有暗色层
	if parent.has_node("VisionDarkness"):
		return
	
	# 1. 创建暗色覆盖层（全局变暗，房间外全黑）
	var darkness := CanvasModulate.new()
	darkness.name = "VisionDarkness"
	darkness.color = Color(0.03, 0.02, 0.04, 0.92)
	parent.add_child(darkness)
	
	# 2. 创建玩家光源（跟随玩家移动，照亮周围）
	var light := PointLight2D.new()
	light.name = "PlayerVisionLight"
	light.light_mode = PointLight2D.LIGHT_MODE_OMNI
	light.texture = _make_light_texture()
	light.texture_scale = 280.0
	light.energy = 0.9
	light.shadow_enabled = true
	light.shadow_item_cull_mask = 1
	parent.add_child(light)
	
	# 3. 扫描本房间的墙体 TileMapLayer，生成 LightOccluder2D
	var wall_layer: TileMapLayer = parent.find_child("WallLayer", true, false) as TileMapLayer
	if wall_layer == null:
		# 尝试查找任意 TileMapLayer 作为墙体
		var candidates: Array[Node] = []
		for c in parent.get_children():
			if c is TileMapLayer and c != floor_layer:
				candidates.append(c)
		if candidates.size() > 0:
			wall_layer = candidates[0] as TileMapLayer
	
	if wall_layer != null:
		_build_wall_occluders(wall_layer, parent)
	
	# 4. 通知玩家光源在玩家存在时跟随
	light.set_meta("_tracked", true)

## 为墙体 TileMapLayer 的每个非空单元格生成 LightOccluder2D
func _build_wall_occluders(wall_layer: TileMapLayer, parent: Node2D) -> void:
	var used_cells: Array[Vector2i] = wall_layer.get_used_cells()
	if used_cells.is_empty():
		return
	
	var cell_size: Vector2i = wall_layer.tile_set.tile_size if wall_layer.tile_set else Vector2i(64, 64)
	
	for cell in used_cells:
		var tile_data: TileData = wall_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		
		# 获取该 tile 的几何信息（相对于 tile 的本地坐标）
		var tile_origin: Vector2 = wall_layer.map_to_local(cell) + Vector2(cell_size) * 0.5
		
		# 获取 tile 的 terrain set（0=floor, 1=wall, 2=wall_top 等）
		var terrain_id: int = tile_data.terrain
		var source_id: int = tile_data.source_id
		
		# 只处理墙体类 terrain（terrain=1 为墙体，terrain=2 为墙顶）
		if source_id == 1 and terrain_id == 1:
			# 墙体 tile：生成 LightOccluder2D
			_create_wall_occluder(wall_layer, cell, parent, cell_size)
		elif source_id == 1 and terrain_id == 2:
			# 墙顶：更薄但也遮挡光线
			_create_wall_occluder(wall_layer, cell, parent, Vector2i(cell_size.x, cell_size.y / 2))

## 创建单个墙体的 LightOccluder2D 节点
func _create_wall_occluder(wall_layer: TileMapLayer, cell: Vector2i, parent: Node2D, size: Vector2i) -> void:
	var occluder := LightOccluder2D.new()
	occluder.name = "WallOccluder_Cell_%d_%d" % [cell.x, cell.y]
	occluder.occluder_light_mask = 1
	
	# 多边形：矩形
	var polygon := OccluderPolygon2D.new()
	var cs := Vector2(size)
	polygon.polygon = PackedVector2Array([
		Vector2(-cs.x * 0.5, -cs.y * 0.5),
		Vector2(cs.x * 0.5, -cs.y * 0.5),
		Vector2(cs.x * 0.5, cs.y * 0.5),
		Vector2(-cs.x * 0.5, cs.y * 0.5),
	])
	polygon.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	occluder.occluder = polygon
	
	# 定位到 tile 中心
	var world_pos: Vector2 = wall_layer.map_to_local(cell)
	occluder.position = world_pos + Vector2(size) * 0.5
	
	parent.add_child(occluder)

## 生成玩家光源的圆形渐变纹理
func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.set_offset(0, 0.0)
	gradient.set_offset(1, 1.0)
	
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.origin_aligned = true
	return tex


## 重置视觉（房间重新进入时）
func reset_visual() -> void:
	_built = false


func configure(
	p_room_type: RoomData.RoomType, p_room_size: Vector2, p_door_info: Array[Dictionary] = []
) -> void:
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
	elif _built:
		call_deferred("_ensure_boundary_collision")


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
