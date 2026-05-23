extends Area2D
class_name EnemyProjectile

@export var speed: float = 310.0
@export var damage: int = 8
@export var max_lifetime: float = 2.4

var direction: Vector2 = Vector2.RIGHT
var _life_timer: float = 0.0
var _active: bool = false

@onready var shape: ColorRect = $Shape

func _ready() -> void:
	z_as_relative = false
	z_index = 890
	body_entered.connect(_on_body_entered)
	monitoring = true

func launch(pos: Vector2, dir: Vector2, spd: float, dmg: int) -> void:
	global_position = pos
	direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	speed = spd
	damage = dmg
	rotation = direction.angle()
	_active = true
	_life_timer = 0.0

func _process(delta: float) -> void:
	if not _active:
		return
	_life_timer += delta
	global_position += direction * speed * delta
	if _life_timer >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if not _active:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
