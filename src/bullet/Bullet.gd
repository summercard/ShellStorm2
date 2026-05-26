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
var _trail_points: Array[Vector2] = []
const MAX_TRAIL_POINTS: int = 30

## 子弹挂载枪视觉多边形（Bullet飞行时，背上的枪渲染为多边形）
## 挂载枪多边形通过 _render_attached_gun() 动态设置 polygon/color

## 命运卡片视觉反馈状态
var _fate_scale: float = 1.0       # fate_scale > 1 时子弹放大
var _fate_has_eyes: bool = false   # 加眼睛
var _fate_has_legs: bool = false   # 加脚
var _eye_nodes: Array[Node2D] = []  # 眼睛节点引用
var _leg_nodes: Array[Node2D] = []  # 脚节点引用
var _leg_anim_timer: float = 0.0

## 命运卡片行为状态（追踪弹 / 返弹 / 落地炮台）
var _fate_homing: bool = false          # 追踪敌人
var _fate_homing_strength: float = 0.3  # 追踪力度 [0,1]
var _fate_return_to_player: bool = false  # 飞出后返回玩家
var _fate_return_damage_mult: float = 0.6  # 返弹伤害倍率
var _fate_return_triggered: bool = false   # 返弹阶段已触发
var _fate_spawn_turret_on_land: bool = false  # 落地变炮台
var _fate_turret_duration: float = 5.0   # 炮台存活时间

## 命运卡片行为：乱射（管不住了）/ 子弹变大（火力暴食）
var _fate_uncontrolled_gun: bool = false  # 乱射模式
var _fate_aim_randomness: float = 0.5     # 乱射随机角度 [0,1]
var _fate_uncontrolled_damage_scale: float = 0.8  # 乱射子弹伤害缩放
var _fate_size_growth: bool = false       # 子弹变大模式
var _fate_growth_per_hit: float = 0.2     # 每次命中增长比例
var _fate_max_scale: float = 3.0          # 最大缩放上限
var _fate_attachment_hit_trigger: bool = false  # 配件寄生命中触发标记

## 挂载枪型 → 多边形顶点映射（与 WeaponDisplay.gd 保持一致）
## 格式：[p1, p2, ...] 组成 Polygon2D polygon，按顺时针/逆时针均可
## 信号：命中时若有配件寄生标记则派发 attachment_hit_triggered
signal attachment_hit_triggered(damage: int, is_crit: bool, direction: Vector2)
static var GUN_SHAPES: Dictionary = {
	"GunBody_Pistol": {
		"polygon": PackedVector2Array([
			Vector2(-6, -4), Vector2(14, -4), Vector2(18, -2),
			Vector2(18, 2), Vector2(14, 4), Vector2(-6, 4),
		]),
		"color": Color(0.55, 0.57, 0.62, 1.0),
	},
	"GunBody_Rifle": {
		"polygon": PackedVector2Array([
			Vector2(-10, -5), Vector2(16, -4), Vector2(22, -3),
			Vector2(24, 0), Vector2(22, 3), Vector2(16, 4), Vector2(-10, 5),
		]),
		"color": Color(0.38, 0.42, 0.38, 1.0),
	},
	"GunBody_Shotgun": {
		"polygon": PackedVector2Array([
			Vector2(-8, -6), Vector2(8, -5), Vector2(20, -4),
			Vector2(24, 0), Vector2(20, 4), Vector2(8, 5), Vector2(-8, 6),
		]),
		"color": Color(0.45, 0.35, 0.22, 1.0),
	},
	"GunBody_SMG": {
		"polygon": PackedVector2Array([
			Vector2(-7, -4), Vector2(10, -4), Vector2(16, -2),
			Vector2(18, 0), Vector2(16, 2), Vector2(10, 4), Vector2(-7, 4),
		]),
		"color": Color(0.30, 0.30, 0.32, 1.0),
	},
	"GunBody_Sniper": {
		"polygon": PackedVector2Array([
			Vector2(-12, -4), Vector2(22, -3), Vector2(30, -1),
			Vector2(32, 0), Vector2(30, 1), Vector2(22, 3), Vector2(-12, 4),
		]),
		"color": Color(0.22, 0.25, 0.28, 1.0),
	},
	"GunBody_Launcher": {
		"polygon": PackedVector2Array([
			Vector2(-10, -7), Vector2(6, -7), Vector2(14, -5),
			Vector2(18, 0), Vector2(14, 5), Vector2(6, 7), Vector2(-10, 7),
		]),
		"color": Color(0.50, 0.42, 0.18, 1.0),
	},
	"GunBody_Machinegun": {
		"polygon": PackedVector2Array([
			Vector2(-12, -6), Vector2(14, -5), Vector2(22, -3),
			Vector2(26, 0), Vector2(22, 3), Vector2(14, 5), Vector2(-12, 6),
		]),
		"color": Color(0.28, 0.28, 0.25, 1.0),
	},
	"GunBody_Charge": {
		"polygon": PackedVector2Array([
			Vector2(-8, -6), Vector2(4, -6), Vector2(12, -4),
			Vector2(18, -2), Vector2(20, 0), Vector2(18, 2),
			Vector2(12, 4), Vector2(4, 6), Vector2(-8, 6),
		]),
		"color": Color(0.60, 0.30, 0.60, 1.0),
	},
	# 挂载枪通用外形（命运卡片"子弹背枪"等机制创建的枪身节点）
	# 匹配模式：AttachedGun_* 前缀节点名，统一渲染为紧凑多边形
	"AttachedGun": {
		"polygon": PackedVector2Array([
			Vector2(-5, -4),
			Vector2(8, -3),
			Vector2(12, 0),
			Vector2(8, 3),
			Vector2(-5, 4),
		]),
		"color": Color(0.70, 0.65, 0.20, 1.0),   # 暗金色（与子弹背枪视觉风格匹配）
	},
}

## 默认外形
static var DEFAULT_GUN_SHAPE: Dictionary = {
	"polygon": PackedVector2Array([
		Vector2(-8, -4), Vector2(12, -4), Vector2(16, 0), Vector2(12, 4), Vector2(-8, 4),
	]),
	"color": Color(0.5, 0.5, 0.5, 1.0),
}

## 原始碰撞半径（恢复时用）
var _base_collision_radius: float = 8.0

@onready var shape: ColorRect = $Shape
@onready var glow: ColorRect = $Shape/Glow
@onready var _attached_gun_polygon: Polygon2D = $AttachedGunPolygon

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
	_trail_points.clear()
	add_child(_trail_line)

func _process(delta: float) -> void:
	if not is_active:
		return
	_life_timer += delta

	# === 行为阶段机 ===
	# 返弹模式：飞行超过 max_distance 的一半后进入返回阶段
	if _fate_return_to_player and not _fate_return_triggered:
		if _travelled >= max_distance * 0.5:
			_fate_return_triggered = true
			# 立即朝向玩家
			var player: Node = get_tree().get_first_node_in_group("player")
			if player != null:
				direction = (player.global_position - global_position).normalized()
			else:
				direction = Vector2.ZERO

	if _fate_return_to_player and _fate_return_triggered:
		# 返弹：朝向玩家飞回
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null:
			var to_player: Vector2 = (player.global_position - global_position).normalized()
			direction = to_player
		# 返回时速度略慢，伤害打折扣
		var return_speed: float = speed * 0.85
		var step: float = return_speed * delta
		_travelled += step
		global_position += direction * step
		rotation = direction.angle()
		# 超出往返总距离上限时消失
		if _travelled >= max_distance * 1.5:
			queue_free()
			return
	else:
		# 正常/追踪飞行
		var current_speed: float = speed
		# 追踪：如果有目标，轻微转向
		# _fate_homing_strength 直接作为 lerp factor（0.0~1.0）
		# 设计意图：0.3 = 轻度追踪（轻微曲线）, 0.6 = 中度追踪, 1.0 = 几乎完全跟随
		if _fate_homing:
			var target: Node = _find_nearest_enemy()
			if target != null:
				var to_target: Vector2 = (target.global_position - global_position).normalized()
				direction = direction.lerp(to_target, _fate_homing_strength).normalized()
		var step: float = current_speed * delta
		_travelled += step
		global_position += direction * step
		rotation = direction.angle()

	# 轨迹：记录每帧位置（相对子弹本地空间，向后延伸）
	_trail_points.append(Vector2.ZERO)
	if _trail_points.size() > MAX_TRAIL_POINTS:
		_trail_points.pop_front()
	if _trail_points.size() >= 2:
		var world_trail: PackedVector2Array = PackedVector2Array()
		for i in range(_trail_points.size()):
			# 轨迹点在本地空间向枪尾（-X）延伸
			var local_pt: Vector2 = Vector2(-i * 3.0, 0.0).rotated(rotation)
			world_trail.append(global_position + local_pt)
		_trail_line.points = world_trail
		# 只在非暴击时每帧重置为橙色——暴击颜色由 fire() 设置，应保持不变
		if not is_crit:
			_trail_line.default_color = Color(1.0, 0.7, 0.1, 0.45)
	else:
		_trail_line.points = PackedVector2Array([Vector2.ZERO, Vector2(-36, 0)])

	if _attached_gun_node != null:
		_process_attached_gun_firing(delta)

	# 腿部动画（脚在子弹尾部，绕子弹旋转）
	if _fate_has_legs and not _leg_nodes.is_empty():
		_leg_anim_timer += delta * 8.0
		for i in range(_leg_nodes.size()):
			var leg: Node2D = _leg_nodes[i]
			var phase: float = (float(i) / float(_leg_nodes.size())) * TAU
			leg.rotation = leg.rotation + sin(_leg_anim_timer + phase) * 0.3 * delta

	# 炮台模式：持续朝敌人射击（由 _spawn_fate_turret 注入的炮台节点执行）
	if _turret_mode:
		if _life_timer >= max_lifetime:
			queue_free()
			return
		_turret_loop(delta)
		return

	# 落地炮台：超出射程或超时，生成炮台
	if (_life_timer >= max_lifetime or _travelled >= max_distance) and not _fate_return_to_player:
		if _fate_spawn_turret_on_land:
			_spawn_fate_turret()
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

	# 计算最终伤害（乱射时缩放）
	var final_damage: int = gun_damage
	if _fate_uncontrolled_gun:
		final_damage = int(float(gun_damage) * _fate_uncontrolled_damage_scale)

	# 乱射模式：随机方向偏移，不一定瞄准敌人
	var aim_dir: Vector2
	if _fate_uncontrolled_gun:
		# 完全随机方向（加上乱射角度扰动）
		var random_angle: float = randf() * TAU
		var random_strength: float = _fate_aim_randomness * (1.0 + randf() * 0.5)
		# 以子弹飞行方向为基准，偏移随机角度
		var base_dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
		var offset_angle: float = (randf() - 0.5) * random_strength * PI
		aim_dir = base_dir.rotated(offset_angle)
	else:
		var nearest_enemy: Node = _find_nearest_enemy()
		if nearest_enemy == null:
			return
		aim_dir = (nearest_enemy.global_position - global_position).normalized()

	_spawn_attached_gun_bullet(final_damage, aim_dir, gun_bullet_count)

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
	# 重置命运卡片状态（每次发射时清零，防止状态泄漏到下一发）
	_fate_scale = 1.0
	_fate_homing = false
	_fate_return_triggered = false
	# 重置轨迹数据
	_trail_points.clear()
	_trail_line.points = PackedVector2Array([Vector2.ZERO, Vector2(-36, 0)])
	_trail_line.width = 3.0
	if shape:
		shape.rotation = 0.0
		shape.scale = Vector2.ONE
		glow.scale = Vector2.ONE
		if crit:
			shape.color = Color(1.0, 0.88, 0.15, 1.0)  # 金黄色，与暴击尾迹/伤害文字一致
			glow.color = Color(1.0, 0.9, 0.2, 0.75)
			if _trail_line:
				_trail_line.default_color = Color(1.0, 0.9, 0.2, 0.65)
				_trail_line.width = 4.5
		else:
			if _trail_line:
				_trail_line.default_color = Color(1.0, 0.7, 0.1, 0.45)
				_trail_line.width = 3.0

func set_attached_gun(gun_node: AssemblyNode) -> void:
	if gun_node == null:
		return
	_attached_gun_node = gun_node
	var stats: Dictionary = gun_node.get_base_stats()
	_attached_gun_fire_rate = stats.get("fire_rate", 4.0)
	_attached_gun_cooldown = 0.0
	# 渲染挂载枪的多边形外形
	_render_attached_gun(gun_node.node_name)
	# 读取枪身节点上记录的 fate_scale（来自"变大了"等卡片对子弹的应用）
	if stats.has("fate_scale"):
		_apply_fate_visual_from_scale(stats.get("fate_scale", 1.0))

## 渲染挂载枪的多边形外形
func _render_attached_gun(gun_name: String) -> void:
	if _attached_gun_polygon == null:
		return
	# 优先精确匹配，兜底前缀匹配（AttachedGun_<card_id> → AttachedGun）
	var shape: Dictionary
	if GUN_SHAPES.has(gun_name):
		shape = GUN_SHAPES[gun_name]
	elif gun_name.begins_with("AttachedGun"):
		# 子弹背枪等命运卡片创建的挂载枪，前缀匹配到 AttachedGun 类型
		shape = GUN_SHAPES.get("AttachedGun", DEFAULT_GUN_SHAPE)
	else:
		shape = DEFAULT_GUN_SHAPE
	_attached_gun_polygon.polygon = shape.get("polygon", PackedVector2Array())
	_attached_gun_polygon.color = shape.get("color", Color.WHITE)
	_attached_gun_polygon.visible = true

func get_attached_gun() -> AssemblyNode:
	return _attached_gun_node

## 应用命运卡片视觉缩放（由 WeaponAssemblyTree 触发）
## 从 bullet_node 的 base_stats 读取 scale/eyes/legs 等视觉标签
func apply_fate_stats_from_node(bullet_node: AssemblyNode) -> void:
	if bullet_node == null:
		return
	var node_stats: Dictionary = bullet_node.get_base_stats()
	# fate_scale（"变大了"等卡片）
	if node_stats.has("fate_scale"):
		_apply_fate_visual_from_scale(float(node_stats.get("fate_scale", 1.0)))
	# 视觉标签（眼睛、脚）
	if node_stats.has("visual_has_eyes") or node_stats.has("visual_has_legs"):
		_apply_visual_effects(node_stats)
	# 命运卡片行为：追踪弹 / 返弹 / 落地炮台
	if node_stats.get("homing", false):
		_fate_homing = true
		_fate_homing_strength = float(node_stats.get("homing_strength", 0.3))
	if node_stats.get("return_to_player", false):
		_fate_return_to_player = true
		_fate_return_damage_mult = float(node_stats.get("return_damage_multiplier", 0.6))
	if node_stats.get("spawn_turret_on_land", false):
		_fate_spawn_turret_on_land = true
		_fate_turret_duration = float(node_stats.get("turret_duration", 5.0))
	# 命运卡片行为：乱射（管不住了）/ 子弹变大（火力暴食）
	if node_stats.get("uncontrolled_gun", false):
		_fate_uncontrolled_gun = true
		_fate_aim_randomness = float(node_stats.get("aim_randomness", 0.5))
		_fate_uncontrolled_damage_scale = float(node_stats.get("uncontrolled_damage_scale", 0.8))
	if node_stats.get("size_growth", false):
		_fate_size_growth = true
		_fate_growth_per_hit = float(node_stats.get("growth_per_hit", 0.2))
		_fate_max_scale = float(node_stats.get("max_fate_scale", 3.0))
	# 配件寄生命中触发（三叉枪口等命中时分裂/强化）
	if node_stats.get("fate_attachment_hit_trigger", false):
		_fate_attachment_hit_trigger = true

## 根据 scale 值应用命运视觉（子弹放大）
func _apply_fate_visual_from_scale(scale: float) -> void:
	if scale <= 1.0:
		return
	_fate_scale = scale
	# 缩放子弹外观（ColorRect offset 基于锚点，scale 直接放大）
	if shape:
		shape.scale = Vector2(scale, scale)
		glow.scale = Vector2(scale, scale)
	# 缩放碰撞体
	var col: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.shape is CircleShape2D:
		var circle: CircleShape2D = col.shape as CircleShape2D
		circle.radius = _base_collision_radius * scale

## 应用完整视觉改造（眼睛、脚等）
func _apply_visual_effects(node_stats: Dictionary) -> void:
	# 加眼睛
	if node_stats.get("visual_has_eyes", false):
		_fate_has_eyes = true
		_add_eye_nodes(int(node_stats.get("visual_eyes", 2)))
	# 加脚
	if node_stats.get("visual_has_legs", false):
		_fate_has_legs = true
		_add_leg_nodes(int(node_stats.get("visual_leg_count", 4)))

func _add_eye_nodes(count: int) -> void:
	for i in range(count):
		var eye: Node2D = Node2D.new()
		eye.name = "Eye_" + str(i)
		var circle: ColorRect = ColorRect.new()
		circle.color = Color(1.0, 1.0, 0.2, 1.0)
		circle.size = Vector2(4, 4)
		eye.add_child(circle)
		# 分布在子弹前方
		var angle: float = (float(i) / float(count)) * TAU - TAU * 0.25
		var dist: float = 8.0
		eye.position = Vector2(cos(angle) * dist, sin(angle) * dist)
		add_child(eye)
		_eye_nodes.append(eye)

func _add_leg_nodes(count: int) -> void:
	for i in range(count):
		var leg: Node2D = Node2D.new()
		leg.name = "Leg_" + str(i)
		var rect: ColorRect = ColorRect.new()
		rect.color = Color(0.6, 0.4, 0.2, 1.0)
		rect.size = Vector2(3, 6)
		rect.position = Vector2(-1.5, 0)
		leg.add_child(rect)
		# 分布在子弹尾部
		var angle: float = PI + (float(i) / float(count)) * TAU - TAU * 0.1
		var dist: float = 10.0
		leg.position = Vector2(cos(angle) * dist, sin(angle) * dist)
		leg.rotation = angle - PI * 0.5
		add_child(leg)
		_leg_nodes.append(leg)

## 生成落地炮台（"不想飞"命运卡片效果）
## 炮台原地固定，通过计时循环持续朝最近敌人开火
var _turret_cooldown: float = 0.0
var _turret_mode: bool = false  # 炮台节点由 _spawn_fate_turret 注入后标记此标志，执行射击循环
var _turret_damage: int = 0
var _turret_fire_interval: float = 0.25

func _spawn_fate_turret() -> void:
	# 炮台用自己的 Bullet.tscn 实例，位置固定，通过 _process_turret_loop 持续射击
	var turret: Node = preload("res://scenes/Bullet.tscn").instantiate()
	get_tree().current_scene.add_child(turret)
	turret.global_position = global_position
	turret.set("speed", 0.0)
	turret.set("max_lifetime", _fate_turret_duration)
	# 炮台继承子弹部分伤害（降低）
	var turret_damage: int = maxi(1, int(float(damage) * 0.5))
	# 注入炮台循环逻辑：turret 自己通过 _process 持续射击
	# 注入后turret 通过内部计时器循环射击最近敌人直到超时自毁
	var turret_fire_rate: float = _attached_gun_fire_rate
	var turret_fire_interval: float = 1.0 / turret_fire_rate if turret_fire_rate > 0.0 else 0.25
	turret.set("_turret_cooldown", turret_fire_interval)
	turret.set("_turret_damage", turret_damage)
	turret.set("_turret_fire_interval", turret_fire_interval)
	turret.set("_turret_mode", true)  # 标记为炮台模式（_process 检测此标志执行射击循环）
	turret.is_active = true

## 炮台射击循环（_spawn_fate_turret 注入炮台节点后，由 _process 中的 _turret_mode 分支调用）
func _turret_loop(delta: float) -> void:
	# 炮台每帧减少冷却 → 冷却到0则查找最近敌人开火 → 重置冷却
	# 上限 delta（避免多帧跳跃导致炮台过速）
	var dt := minf(delta, 0.05)
	_turret_cooldown -= dt
	if _turret_cooldown > 0.0:
		return
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var nearest: Node = null
	var min_dist: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var dist: float = global_position.distance_to(e.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = e
	if nearest == null:
		# 找不到敌人时，每帧仍然减少冷却以便下次重新检测
		_turret_cooldown = _turret_fire_interval
		return
	var aim_dir: Vector2 = (nearest.global_position - global_position).normalized()
	_turret_cooldown = _turret_fire_interval
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var bullet: Node = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position
	if bullet.has_method("fire"):
		bullet.fire(global_position, aim_dir, 350.0, _turret_damage, false)

func _on_body_entered(body: Node) -> void:
	if not is_active:
		return
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.call("take_damage", damage, is_crit, direction)

		# 火力暴食：每次命中子弹变大（伤害同时增加）
		if _fate_size_growth:
			_fate_scale = mini(_fate_scale * (1.0 + _fate_growth_per_hit), _fate_max_scale)
			_apply_fate_visual_from_scale(_fate_scale)
			# 伤害也随 scale 增大
			damage = int(float(damage) * (1.0 + _fate_growth_per_hit))

		# 配件寄生命中触发
		if _fate_attachment_hit_trigger:
			attachment_hit_triggered.emit(damage, is_crit, direction)

		# 延迟一帧释放子弹，确保 enemy_died 信号在当前帧内完成派发
		# 这样 crit_on_kill 才能在本帧内消费堆栈（命中→击杀→堆栈-1→下一发暴击）
		call_deferred("queue_free")
	elif body is StaticBody2D:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	# 保留扩展入口，后续可用于打爆炸桶/盾牌等 Area。
	pass
