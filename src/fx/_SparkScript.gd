extends Polygon2D
## _SparkScript — SparkParticles 内部使用的火花节点脚本
## 负责随机方向移动 + 衰减淡出

var _lifetime: float = 0.2
var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0


func _ready() -> void:
	_age = 0.0


func _process(delta: float) -> void:
	_age += delta
	# 移动
	position += _velocity * delta
	# 减速
	_velocity = _velocity.move_toward(Vector2.ZERO, delta * 280.0)
	# 淡出
	var t: float = clampf(_age / _lifetime, 0.0, 1.0)
	modulate.a = 1.0 - t
	if _age >= _lifetime:
		queue_free()
