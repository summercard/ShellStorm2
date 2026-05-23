extends Area2D

# Bullet - 玩家子弹投射物。
# 修正点：不再用 viewport_rect 判断出屏（相机移动时会误删），改为寿命/射程；
# 命中敌人时传递命中方向，给敌人一个轻微击退，手感更像顶视角射击。

@export var speed: float = 650.0
@export var damage: int = 10
@export var max_lifetime: float = 1.45
@export var max_distance: float = 950.0
@export var is_crit: bool = false

var direction: Vector2 = Vector2.RIGHT
var is_active: bool = false
var _life_timer: float = 0.0
var _travelled: float = 0.0

var _attached_gun_node: AssemblyNode = null
var _attached_gun_cooldown: float = 0.0
var _attached_gun_fire_rate: float = 4.0

var _trail_line: Line2D = null

@onready var shape: ColorRect = $Shape
@onready var glow: ColorRect = $Shape/Glow

func _ready() -> void:
	z_as_relative = false
	z_index = 900
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_setup_trail()
	monitoring = true

func _setup_trail() -> void:
	_trail_line = Line2D.new()
	_trail_line.width = 3.0
	_trail_line.default_color = Color(1.0, 0.7, 0.1, 0.45)
	_trail_line.z_index = -1
	_trail_line.points = PackedVector2Array([Vector2.ZERO, Vector2(-36, 0)])
	add_child(_trail_line)

func _process(delta: float) -> void:
	if not is_active:
		return
	_life_timer += delta
	var step: float = speed * delta
	_travelled += step
	global_position += direction * step
	rotation = direction.angle()
	if _attached_gun_node != null:
		_process_attached_gun_firing(delta)
	if _life_timer >= max_lifetime or _travelled >= max_distance:
		queue_free()

func _process_attached_gun_firing(delta: float) -> void:
	if _attached_gun_cooldown > 0.0:
		_attached_gun_cooldown -= delta
		return
	var gun_stats: Dictionary = _attached_gun_node.get_base_stats()
	var gun_fire_rate: float = gun_stats.get("fire_rate", _attached_gun_fire_rate)
	var gun_damage: int = gun_stats.get("damage", 5)
	var gun_bullet_count: int = gun_stats.get("bullet_count", 1)
	var fire_interval: float = 1.0 / gun_fire_rate if gun_fire_rate > 0 else 0.25
	_attached_gun_cooldown = fire_interval
	var nearest_enemy: Node = _find_nearest_enemy()
	if nearest_enemy == null:
		return
	var aim_dir: Vector2 = (nearest_enemy.global_position - global_position).normalized()
	_spawn_attached_gun_bullet(gun_damage, aim_dir, gun_bullet_count)

func _find_nearest_enemy() -> Node:
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

func _spawn_attached_gun_bullet(dmg: int, aim_dir: Vector2, bullet_count: int) -> void:
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	for i in range(bullet_count):
		var spread_angle: float = 0.0
		if bullet_count > 1:
			var step_angle: float = 0.15 / float(bullet_count - 1)
			spread_angle = -0.075 + step_angle * i
		var spawn_dir: Vector2 = aim_dir.rotated(spread_angle)
		var bullet: Node = bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		if bullet.has_method("fire"):
			bullet.fire(global_position, spawn_dir, speed * 0.9, dmg, false)

func fire(pos: Vector2, dir: Vector2, spd: float, dmg: int, crit: bool = false) -> void:
	global_position = pos
	direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	speed = spd
	damage = dmg
	is_active = true
	is_crit = crit
	_life_timer = 0.0
	_travelled = 0.0
	rotation = direction.angle()
	if shape:
		shape.rotation = 0.0
		if crit:
			shape.color = Color(1.0, 0.3, 0.1, 1.0)
			glow.color = Color(1.0, 0.9, 0.2, 0.75)
			if _trail_line:
				_trail_line.default_color = Color(1.0, 0.9, 0.2, 0.65)

func set_attached_gun(gun_node: AssemblyNode) -> void:
	if gun_node == null:
		return
	_attached_gun_node = gun_node
	var stats: Dictionary = gun_node.get_base_stats()
	_attached_gun_fire_rate = stats.get("fire_rate", 4.0)
	_attached_gun_cooldown = 0.0

func get_attached_gun() -> AssemblyNode:
	return _attached_gun_node

func _on_body_entered(body: Node) -> void:
	if not is_active:
		return
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.call("take_damage", damage, is_crit, direction)
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	# 保留扩展入口，后续可用于打爆炸桶/盾牌等 Area。
	pass
