extends Area2D

# Bullet - 子弹投射物
# 使用 ColorRect 作为占位图形，带尾迹效果

@export var speed: float = 600.0
@export var damage: int = 10
@export var is_crit: bool = false  # 暴击标记

var direction: Vector2 = Vector2.RIGHT
var is_active: bool = false
var _lifetime: float = 0.0

# 尾迹节点（Line2D 渲染子弹历史位置）
var _trail_line: Line2D = null
var _trail_points: Array = []
const TRAIL_MAX_POINTS: int = 6
const TRAIL_INTERVAL: float = 0.02  # 每多少秒记录一个点

@onready var shape: ColorRect = $Shape
@onready var glow: ColorRect = $Shape/Glow

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_setup_trail()

func _setup_trail() -> void:
	# 创建尾迹 Line2D
	_trail_line = Line2D.new()
	_trail_line.width = 3.0
	_trail_line.default_color = Color(1.0, 0.7, 0.1, 0.5)
	_trail_line.z_index = -1
	add_child(_trail_line)

	# 预填尾迹点（当前点位置，防止初始空白）
	for i in range(TRAIL_MAX_POINTS):
		_trail_points.append(global_position)

func _process(delta: float) -> void:
	if not is_active:
		return

	_lifetime += delta
	global_position += direction * speed * delta

	# 更新尾迹
	if _lifetime >= TRAIL_INTERVAL:
		_lifetime = 0.0
		_trail_points.push_back(global_position)
		if _trail_points.size() > TRAIL_MAX_POINTS:
			_trail_points.pop_front()
		_sync_trail()

	# 出屏检测
	var vp = get_viewport_rect()
	if not vp.has_point(global_position):
		queue_free()

func _sync_trail() -> void:
	if _trail_line and _trail_points.size() >= 2:
		var pts = PackedVector2Array(_trail_points)
		_trail_line.points = pts

func fire(pos: Vector2, dir: Vector2, spd: float, dmg: int, crit: bool = false) -> void:
	global_position = pos
	direction = dir.normalized()
	speed = spd
	damage = dmg
	is_active = true
	is_crit = crit
	if shape:
		shape.rotation = dir.angle()
		# 暴击时子弹更大更亮
		if crit:
			shape.color = Color(1.0, 0.3, 0.1, 1.0)
			glow.color = Color(1.0, 0.9, 0.2, 0.7)
			_trail_line.default_color = Color(1.0, 0.9, 0.2, 0.6)

func _on_body_entered(body: Node) -> void:
	if not is_active:
		return

	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(damage, is_crit)
	elif body.has_method("take_damage"):
		body.take_damage(damage)

	queue_free()