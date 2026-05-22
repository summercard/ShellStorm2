extends Area2D

# Bullet - 子弹投射物
# 使用 ColorRect 作为占位图形

@export var speed: float = 600.0
@export var damage: int = 10

var direction: Vector2 = Vector2.RIGHT
var is_active: bool = false

@onready var shape: ColorRect = $Shape

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if not is_active:
		return

	global_position += direction * speed * delta

	# 出屏检测
	var vp = get_viewport_rect()
	if not vp.has_point(global_position):
		queue_free()

func fire(pos: Vector2, dir: Vector2, spd: float, dmg: int) -> void:
	global_position = pos
	direction = dir.normalized()
	speed = spd
	damage = dmg
	is_active = true
	if shape:
		shape.rotation = dir.angle()

func _on_body_entered(body: Node) -> void:
	if not is_active:
		return

	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(damage)

	queue_free()