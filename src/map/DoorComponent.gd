class_name DoorComponent
## 门组件 — 独立碰撞体的物理门
## 门洞处的 StaticBody2D + Area2D，实现玩家通过但不穿透墙体

extends RoomComponent

## 门方向（世界坐标系）
@export var direction: Vector2 = Vector2.RIGHT

## 门是否已开启
var _is_open: bool = false

## 门是否已解锁（清怪后解锁）
var _is_unlocked: bool = false

## 门洞宽度（格子数）
var _door_width_cells: int = 2

## 静态碰撞体节点（玩家通过门洞）
var _static_body: StaticBody2D = null

## 交互区域（玩家按 E 交互）
var _interaction_area: Area2D = null

## 信号
signal door_opened(direction: Vector2)
signal door_closed(direction: Vector2)
signal player_entered(door: DoorComponent)


func _on_initialize() -> void:
	# 读取配置
	direction = component_config.get("direction", Vector2.RIGHT)
	_door_width_cells = component_config.get("door_width_cells", 2)
	_is_unlocked = component_config.get("unlocked", false)
	_is_open = component_config.get("open", false)

	_setup_door_collision()


## 构建门的物理碰撞体
func _setup_door_collision() -> void:
	# 创建 StaticBody2D（玩家穿过门洞时不会撞墙）
	_static_body = StaticBody2D.new()
	_static_body.name = "DoorStaticBody"
	_static_body.collision_layer = 1
	_static_body.collision_mask = 0
	add_child(_static_body)

	# 根据门方向计算碰撞体形状和位置
	var door_pixel_width: float = _door_width_cells * GridConstants.CELL_SIZE
	var wall_thickness: float = GridConstants.BOUNDARY_THICKNESS

	if direction == Vector2.LEFT or direction == Vector2.RIGHT:
		# 垂直门洞（左右侧）：碰撞体是竖长条，中间留门洞
		var half_height: float = (GridConstants.ROOM_PIXEL_HEIGHT + wall_thickness * 2.0) * 0.5
		var gap_height: float = door_pixel_width
		var side_height: float = max(1.0, (half_height * 2.0 - gap_height) * 0.5)

		# 上半段
		var top_shape := CollisionShape2D.new()
		top_shape.name = "DoorTopPart"
		var top_rect := RectangleShape2D.new()
		top_rect.size = Vector2(wall_thickness, side_height)
		top_shape.shape = top_rect
		top_shape.position = Vector2(0, -half_height * 0.5 - side_height * 0.5)
		_static_body.add_child(top_shape)

		# 下半段
		var bottom_shape := CollisionShape2D.new()
		bottom_shape.name = "DoorBottomPart"
		var bottom_rect := RectangleShape2D.new()
		bottom_rect.size = Vector2(wall_thickness, side_height)
		bottom_shape.shape = bottom_rect
		bottom_shape.position = Vector2(0, half_height * 0.5 + side_height * 0.5)
		_static_body.add_child(bottom_shape)

		# 交互区域（门洞中间，垂直方向）
		_setup_interaction_area(wall_thickness, gap_height, true)

	else:
		# 水平门洞（上下侧）：碰撞体是横长条，中间留门洞
		var half_width: float = (GridConstants.ROOM_PIXEL_WIDTH + wall_thickness * 2.0) * 0.5
		var gap_width: float = door_pixel_width
		var side_width: float = max(1.0, (half_width * 2.0 - gap_width) * 0.5)

		# 左半段
		var left_shape := CollisionShape2D.new()
		left_shape.name = "DoorLeftPart"
		var left_rect := RectangleShape2D.new()
		left_rect.size = Vector2(side_width, wall_thickness)
		left_shape.shape = left_rect
		left_shape.position = Vector2(-half_width * 0.5 - side_width * 0.5, 0)
		_static_body.add_child(left_shape)

		# 右半段
		var right_shape := CollisionShape2D.new()
		right_shape.name = "DoorRightPart"
		var right_rect := RectangleShape2D.new()
		right_rect.size = Vector2(side_width, wall_thickness)
		right_shape.shape = right_rect
		right_shape.position = Vector2(half_width * 0.5 + side_width * 0.5, 0)
		_static_body.add_child(right_shape)

		# 交互区域
		_setup_interaction_area(gap_width, wall_thickness, false)


func _setup_interaction_area(width: float, height: float, is_vertical: bool) -> void:
	_interaction_area = Area2D.new()
	_interaction_area.name = "DoorInteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 2  # 检测玩家层
	add_child(_interaction_area)

	var shape := CollisionShape2D.new()
	shape.name = "DoorInteractionShape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	shape.shape = rect
	_interaction_area.add_child(shape)

	# 连接交互信号
	_interaction_area.body_entered.connect(_on_interaction_body_entered)


func _on_interaction_body_entered(body: Node2D) -> void:
	if not _is_unlocked:
		# 门未解锁，播放锁定提示
		_show_locked_feedback()
		return

	if body is Node2D and body.has_method("is_player"):
		# 玩家进入门区域，触发房间切换逻辑
		player_entered.emit(self)
		door_opened.emit(direction)


func _show_locked_feedback() -> void:
	# 播放锁定提示（门还亮着红色，等清怪）
	pass


## 解锁门（清怪后调用）
func unlock() -> void:
	_is_unlocked = true
	_update_door_visual_state()


## 开启门（玩家可以进入）
func open() -> void:
	_is_open = true
	_hide_collision()
	door_opened.emit(direction)


## 关闭门
func close() -> void:
	_is_open = false
	_show_collision()
	door_closed.emit(direction)


func _hide_collision() -> void:
	if _static_body != null:
		_static_body.process_mode = Node.PROCESS_MODE_DISABLED
		_static_body.visible = false


func _show_collision() -> void:
	if _static_body != null:
		_static_body.process_mode = Node.PROCESS_MODE_INHERIT
		_static_body.visible = true


func _update_door_visual_state() -> void:
	# 门解锁后视觉反馈（颜色从红变绿）
	# 具体实现依赖装饰节点
	pass


func is_unlocked() -> bool:
	return _is_unlocked


func is_open() -> bool:
	return _is_open


func _on_reset() -> void:
	_is_open = false
	_is_unlocked = false
	_show_collision()