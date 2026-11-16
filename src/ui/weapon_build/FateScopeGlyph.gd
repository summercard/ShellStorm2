extends Control

const INK := Color(0.025, 0.038, 0.062, 0.96)
var scope_id: int = FateCard.Scope.WEAPON

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func configure(scope: int) -> void:
	scope_id = scope
	set_meta("scope_id", scope)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.35
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	match scope_id:
		FateCard.Scope.CHARACTER:
			# 两段圆弧组成月牙，不用底色圆片遮挡其他笔画。
			var points := PackedVector2Array()
			for i in range(25):
				var angle := PI * 0.5 + PI * float(i) / 24.0
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			for i in range(25):
				var angle := -PI * 0.5 - PI * float(i) / 24.0
				points.append(center + Vector2(radius * 0.48 + cos(angle) * radius * 0.78, sin(angle) * radius))
			draw_colored_polygon(points, Color(0.58, 0.82, 1.0))
		FateCard.Scope.WORLD:
			var gold := Color(1.0, 0.79, 0.35)
			draw_circle(center, radius * 0.53, gold)
			for i in range(8):
				var direction := Vector2.from_angle(TAU * float(i) / 8.0)
				draw_line(center + direction * radius * 0.73, center + direction * radius, gold, 1.7, true)
		_:
			var points := PackedVector2Array()
			for i in range(10):
				var angle := -PI * 0.5 + TAU * float(i) / 10.0
				points.append(center + Vector2.from_angle(angle) * radius * (1.0 if i % 2 == 0 else 0.43))
			draw_colored_polygon(points, Color(0.79, 0.64, 1.0))
