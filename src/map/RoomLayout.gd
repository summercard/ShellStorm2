class_name RoomLayout
extends Node2D
## Runtime room shell: stable room number, wall collision, and door apertures.

signal occlusion_changed

const WALL_LAYER := 1
const OCCLUDER_MASK := 1
const WALL_THICKNESS := GridConstants.BOUNDARY_THICKNESS
const DOOR_WIDTH := GridConstants.DOOR_WIDTH
const WALL_COLOR := Color(0.16, 0.17, 0.19, 0.92)
const WALL_ACCENT := Color(0.24, 0.25, 0.28, 0.85)

var room_id: int = -1
var room_number: int = -1
var room_size: Vector2 = Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
var _door_info: Array[Dictionary] = []
var _wall_root: Node2D = null
var _occluder_root: Node2D = null
var _label: Label = null
var _rebuild_queued := false


func configure(p_room_id: int, p_room_data: RoomData, p_door_info: Array[Dictionary] = []) -> void:
	room_id = p_room_id
	if p_room_data != null:
		room_number = p_room_data.room_number
		room_size = p_room_data.size
	_door_info.clear()
	for info in p_door_info:
		if info is Dictionary:
			_door_info.append(info.duplicate(true))
	_rebuild()


func set_open_doors(p_door_info: Array[Dictionary]) -> void:
	_door_info.clear()
	for info in p_door_info:
		if info is Dictionary:
			_door_info.append(info.duplicate(true))
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_flush_rebuild")


func _flush_rebuild() -> void:
	_rebuild_queued = false
	_rebuild()


func get_safe_spawn_rect() -> Rect2:
	var margin := Vector2(120.0, 112.0)
	return Rect2(global_position - room_size * 0.5 + margin, room_size - margin * 2.0)


func _rebuild() -> void:
	if _wall_root != null and is_instance_valid(_wall_root):
		remove_child(_wall_root)
		_wall_root.free()
	if _occluder_root != null and is_instance_valid(_occluder_root):
		remove_child(_occluder_root)
		_occluder_root.free()
	# 统一的墙体根节点：每个墙壁段落包含碰撞+视觉+遮挡，统一管理
	_wall_root = Node2D.new()
	_wall_root.name = "Walls"
	add_child(_wall_root)
	_occluder_root = Node2D.new()
	_occluder_root.name = "Occluders"
	add_child(_occluder_root)
	_build_walls()
	_ensure_room_label()
	occlusion_changed.emit()


func _build_walls() -> void:
	var half := room_size * 0.5
	var t := WALL_THICKNESS
	_add_horizontal_wall(
		"Top", -half.y, room_size.x + t * 2.0, t, _has_open_door(Vector2.UP)
	)
	_add_horizontal_wall(
		"Bottom", half.y, room_size.x + t * 2.0, t, _has_open_door(Vector2.DOWN)
	)
	_add_vertical_wall(
		"Left", -half.x, room_size.y + t * 2.0, t, _has_open_door(Vector2.LEFT)
	)
	_add_vertical_wall(
		"Right", half.x, room_size.y + t * 2.0, t, _has_open_door(Vector2.RIGHT)
	)


func _has_open_door(direction: Vector2) -> bool:
	for info in _door_info:
		if not bool(info.get("is_open", false)):
			continue
		if _normalize_direction(info.get("direction", Vector2.ZERO)) == direction:
			return true
	return false


func _add_horizontal_wall(
	prefix: String, y: float, total_width: float, thickness: float, has_gap: bool
) -> void:
	if not has_gap:
		_add_wall_segment(prefix, Vector2(0, y), Vector2(total_width, thickness), false)
		return
	var side_width: float = max(1.0, (total_width - DOOR_WIDTH) * 0.5)
	var offset: float = DOOR_WIDTH * 0.5 + side_width * 0.5
	_add_wall_segment(prefix + "Left", Vector2(-offset, y), Vector2(side_width, thickness), true)
	_add_wall_segment(prefix + "Right", Vector2(offset, y), Vector2(side_width, thickness), true)


func _add_vertical_wall(
	prefix: String, x: float, total_height: float, thickness: float, has_gap: bool
) -> void:
	if not has_gap:
		_add_wall_segment(prefix, Vector2(x, 0), Vector2(thickness, total_height), false)
		return
	var side_height: float = max(1.0, (total_height - DOOR_WIDTH) * 0.5)
	var offset: float = DOOR_WIDTH * 0.5 + side_height * 0.5
	_add_wall_segment(prefix + "Top", Vector2(x, -offset), Vector2(thickness, side_height), true)
	_add_wall_segment(prefix + "Bottom", Vector2(x, offset), Vector2(thickness, side_height), true)


func _add_wall_segment(
	segment_name: String, local_pos: Vector2, segment_size: Vector2, near_door: bool
) -> void:
	# 统一墙壁段落：碰撞+视觉+遮挡都作为子节点
	var wall_node := Node2D.new()
	wall_node.name = segment_name
	wall_node.position = local_pos
	_wall_root.add_child(wall_node)

	# 1. 碰撞体（StaticBody2D + CollisionShape2D）
	var body := StaticBody2D.new()
	body.name = "Collision"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	wall_node.add_child(body)
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = segment_size
	shape.shape = rect
	body.add_child(shape)

	# 2. 视觉（ColorRect）
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.size = segment_size
	visual.position = -segment_size * 0.5
	visual.color = WALL_ACCENT if near_door else WALL_COLOR
	visual.z_index = 8
	wall_node.add_child(visual)

	# 3. 光照遮挡（LightOccluder2D）
	var occluder := LightOccluder2D.new()
	occluder.name = "Occluder"
	occluder.occluder_light_mask = OCCLUDER_MASK
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = PackedVector2Array([
		Vector2(-segment_size.x * 0.5, -segment_size.y * 0.5),
		Vector2(segment_size.x * 0.5, -segment_size.y * 0.5),
		Vector2(segment_size.x * 0.5, segment_size.y * 0.5),
		Vector2(-segment_size.x * 0.5, segment_size.y * 0.5),
	])
	polygon.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	occluder.occluder = polygon
	wall_node.add_child(occluder)


func _ensure_room_label() -> void:
	if _label == null or not is_instance_valid(_label):
		_label = Label.new()
		_label.name = "RoomNumberLabel"
		_label.z_index = 20
		_label.position = Vector2(-room_size.x * 0.5 + 22.0, -room_size.y * 0.5 + 18.0)
		_label.add_theme_font_size_override("font_size", 18)
		_label.modulate = Color(0.85, 0.9, 0.95, 0.72)
		add_child(_label)
	_label.text = "ROOM %03d" % max(room_number, room_id)


func _normalize_direction(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y > 0.0 else Vector2.UP
