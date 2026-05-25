extends Node2D
class_name WallOccluderComponent

# WallOccluderComponent — 墙体遮挡组件
# 给任意墙体节点添加本组件，即可在 VisionDarknessLayer 的 Light2D 下产生实时阴影
# 原理：LightOccluder2D 使用多边形遮罩，在光源下产生阴影
# 使用方式：
#   1. 创建 Polygon2D 或 StaticBody2D + CollisionShape2D 的墙体节点
#   2. 在其下添加 WallOccluderComponent 作为子节点
#   3. 配置 occluder_polygon 为墙体的实际多边形顶点

@export var occluder_polygon: PackedVector2Array = PackedVector2Array() :
	set(v):
		occluder_polygon = v
		_update_occluder()

## 是否在编辑器中预览时更新（提升编辑体验）
@export var editor_preview: bool = true

var _occluder: LightOccluder2D = null

func _ready() -> void:
	_ensure_occluder()
	_apply_polygon()

func _ensure_occluder() -> void:
	_occluder = get_node_or_null("OccluderShape")
	if _occluder == null:
		_occluder = LightOccluder2D.new()
		_occluder.name = "OccluderShape"
		_occluder.occluder_light_mask = 1
		add_child(_occluder)

## 设置多边形顶点（外部调用，传入墙体坐标）
## 典型用法：在 RoomTileMapInitializer.gd 中，墙体放置完成后遍历墙体 TileMap 的 CellQuad
## 生成对应的 occluder 多边形，调用本方法批量注入
func set_polygon_from_rect(rect: Rect2) -> void:
	var poly := PackedVector2Array([
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	])
	occluder_polygon = poly

func _update_occluder() -> void:
	if _occluder == null or occluder_polygon.size() < 3:
		return
	var polygon := OccluderPolygon2D.new()
	polygon.polygon = occluder_polygon
	polygon.cull_mode = OccluderPolygon2D.CULL_CCW
	_occluder.occluder = polygon

func _apply_polygon() -> void:
	_update_occluder()

## 工厂方法：从 Rect2 创建带 occluder 的单个墙体节点
static func create_wall_node(rect: Rect2, parent: Node2D) -> Node2D:
	var wall := StaticBody2D.new()
	wall.name = "WallOccluder"
	
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	col.position = rect.position + rect.size * 0.5
	wall.add_child(col)
	
	var occluder_node := WallOccluderComponent.new()
	occluder_node.occluder_polygon = PackedVector2Array([
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
	])
	wall.add_child(occluder_node)
	
	parent.add_child(wall)
	return wall

## 工厂方法：从线段创建（用于斜墙/不规则墙体）
static func create_segment_wall(p1: Vector2, p2: Vector2, thickness: float, parent: Node2D) -> Node2D:
	var mid := (p1 + p2) * 0.5
	var length := p1.distance_to(p2)
	var angle := p1.angle_to_point(p2)
	
	var wall := StaticBody2D.new()
	wall.name = "WallOccluder"
	wall.position = mid
	wall.rotation = angle
	
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length, thickness)
	col.shape = shape
	wall.add_child(col)
	
	# 创建occluder多边形（墙体矩形）
	var half_l := length * 0.5
	var half_t := thickness * 0.5
	var poly := PackedVector2Array([
		Vector2(-half_l, -half_t),
		Vector2(half_l, -half_t),
		Vector2(half_l, half_t),
		Vector2(-half_l, half_t),
	])
	var occluder_node := WallOccluderComponent.new()
	occluder_node.occluder_polygon = poly
	wall.add_child(occluder_node)
	
	parent.add_child(wall)
	return wall