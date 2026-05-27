extends Node2D
## 程序占位主画面：不依赖素材，先提供清晰的战斗场地、网格和边界。

@export var arena_size: Vector2 = Vector2(1800, 1100)
@export var grid_size: int = 80
@export var debug_visuals: bool = false

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(-arena_size * 0.5, arena_size)
	# 房间外的世界只提供黑底；可行走表面由房间 TileMap 独占。
	draw_rect(rect, Color.BLACK, true)
	if not debug_visuals:
		return

	# 内圈区域
	draw_rect(Rect2(rect.position + Vector2(80, 80), rect.size - Vector2(160, 160)), Color(0.10, 0.11, 0.14, 1.0), true)

	# 网格线
	var left := int(rect.position.x)
	var right := int(rect.position.x + rect.size.x)
	var top := int(rect.position.y)
	var bottom := int(rect.position.y + rect.size.y)
	var grid_color := Color(0.22, 0.26, 0.34, 0.22)
	for x in range(left, right + 1, grid_size):
		draw_line(Vector2(x, top), Vector2(x, bottom), grid_color, 1.0)
	for y in range(top, bottom + 1, grid_size):
		draw_line(Vector2(left, y), Vector2(right, y), grid_color, 1.0)

	# 场地边界
	draw_rect(rect, Color(0.45, 0.60, 1.0, 0.35), false, 3.0)
	# 中心十字，方便判断相机/玩家是否在中心
	draw_line(Vector2(-24, 0), Vector2(24, 0), Color(0.8, 0.9, 1.0, 0.45), 2.0)
	draw_line(Vector2(0, -24), Vector2(0, 24), Color(0.8, 0.9, 1.0, 0.45), 2.0)
