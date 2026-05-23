extends Area2D

# Bullet - 子弹投射物
# 使用 ColorRect 作为占位图形，带尾迹效果
# 支持命运卡片挂载枪械：子弹飞行时会检查自身的挂载枪节点并自动射击

@export var speed: float = 600.0
@export var damage: int = 10
@export var is_crit: bool = false  # 暴击标记

var direction: Vector2 = Vector2.RIGHT
var is_active: bool = false
var _lifetime: float = 0.0

# 命运卡片挂载枪（由 AssemblyNode 传入，子弹上挂枪身的机制）
var _attached_gun_node: AssemblyNode = null
var _attached_gun_cooldown: float = 0.0
var _attached_gun_fire_rate: float = 4.0  # 默认4发/秒

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

	# 处理挂载枪自动射击（子弹上挂枪身的核心机制）
	if _attached_gun_node != null:
		_process_attached_gun_firing(delta)

	# 出屏检测
	var vp = get_viewport_rect()
	if not vp.has_point(global_position):
		queue_free()

func _process_attached_gun_firing(delta: float) -> void:
	"""处理挂载在子弹上的枪械的自动射击"""
	if _attached_gun_cooldown > 0:
		_attached_gun_cooldown -= delta
		return

	# 获取挂载枪的基础属性
	var gun_stats: Dictionary = _attached_gun_node.get_base_stats()
	var gun_fire_rate: float = gun_stats.get("fire_rate", _attached_gun_fire_rate)
	var gun_damage: int = gun_stats.get("damage", 5)
	var gun_bullet_count: int = gun_stats.get("bullet_count", 1)

	# 计算射击间隔
	var fire_interval: float = 1.0 / gun_fire_rate if gun_fire_rate > 0 else 0.25
	_attached_gun_cooldown = fire_interval

	# 寻找最近敌人
	var nearest_enemy: Node = _find_nearest_enemy()
	if nearest_enemy == null:
		return

	# 计算从子弹位置到敌人的方向
	var aim_dir: Vector2 = (nearest_enemy.global_position - global_position).normalized()

	# 生成挂载枪的子弹
	_spawn_attached_gun_bullet(gun_damage, aim_dir, gun_bullet_count)

func _find_nearest_enemy() -> Node:
	"""找到最近的敌人节点"""
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var nearest: Node = null
	var min_dist: float = INF

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy

	return nearest

func _spawn_attached_gun_bullet(damage: int, aim_dir: Vector2, bullet_count: int) -> void:
	"""生成挂载枪发射的子弹"""
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	for i in range(bullet_count):
		var spread_angle: float = 0.0
		if bullet_count > 1:
			var step: float = 0.15 / float(bullet_count - 1)
			var offset: float = -0.15 * 0.5
			spread_angle = offset + step * i
		var spawn_dir: Vector2 = aim_dir.rotated(spread_angle)
		var bullet: Node = bullet_scene.instantiate()
		get_tree().root.add_child(bullet)
		if bullet.has_method("fire"):
			bullet.fire(global_position, spawn_dir, speed * 0.9, damage, false)

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

## 设置挂载枪节点（子弹上挂枪身的核心方法）
## 由 WeaponAssemblyTree 在生成子弹时调用，传入子弹节点的挂载枪 AssemblyNode
func set_attached_gun(gun_node: AssemblyNode) -> void:
	if gun_node == null:
		return
	_attached_gun_node = gun_node
	var stats: Dictionary = gun_node.get_base_stats()
	_attached_gun_fire_rate = stats.get("fire_rate", 4.0)
	_attached_gun_cooldown = 0.0

## 获取挂载枪节点（用于调试/UI）
func get_attached_gun() -> AssemblyNode:
	return _attached_gun_node

func _on_body_entered(body: Node) -> void:
	if not is_active:
		return

	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(damage, is_crit)
	elif body.has_method("take_damage"):
		body.take_damage(damage)

	queue_free()