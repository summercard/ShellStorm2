extends Node2D
class_name WeaponCore

# WeaponCore.gd — 武器核心接口
# 武器系统的基础接口，定义所有武器的通用属性和射击行为模板

## 武器基础属性
@export var fire_rate: float = 4.0        # 每秒射击次数
@export var projectile_count: int = 1     # 每次射击的投射物数量
@export var spread: float = 0.0          # 扩散角度（弧度），0=精准
@export var reload_time: float = 2.0     # 换弹时间（秒）
@export var magazine_size: int = 30      # 弹夹容量
@export var current_ammo: int = 30       # 当前弹药
@export var damage: int = 10             # 基础伤害

## 武器状态
var _fire_cooldown: float = 0.0
var _is_reloading: bool = false
var _is_active: bool = true

## 子弹配置
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@export var bullet_speed: float = 600.0
@export var bullet_damage: int = 10

## 信号
signal weapon_fired(position: Vector2, direction: Vector2, count: int)
signal weapon_reloaded()
signal ammo_changed(current: int, max: int)
signal reload_started()

## 虚拟方法（子类重写）
func _ready() -> void:
	pass

func _process(delta: float) -> void:
	# 更新射击冷却
	if _fire_cooldown > 0:
		_fire_cooldown -= delta

## 核心射击方法 — 带世界坐标（用于枪口偏移）
func fire_from(spawn_pos: Vector2, direction: Vector2) -> bool:
	"""
	执行射击，从指定世界坐标生成子弹（支持枪口偏移）
	参数: spawn_pos — 子弹生成的世界坐标（通常是枪口位置）
	参数: direction — 射击方向（归一化向量）
	返回: 是否成功发射
	"""
	if not _can_fire():
		return false

	_fire_cooldown = 1.0 / fire_rate

	if not _is_reloading and current_ammo > 0:
		_spawn_projectiles_from(spawn_pos, direction)
		current_ammo -= 1
		ammo_changed.emit(current_ammo, magazine_size)
		weapon_fired.emit(spawn_pos, direction, projectile_count)

		if current_ammo <= 0:
			start_reload()

		return true
	return false

## 兼容旧接口（无位置参数，使用当前节点位置）
func fire(direction: Vector2) -> bool:
	"""兼容旧接口，内部调用 fire_from(global_position, direction)"""
	return fire_from(global_position, direction)

func _can_fire() -> bool:
	"""检查是否可以射击"""
	return _is_active and _fire_cooldown <= 0 and not _is_reloading and current_ammo > 0

func _spawn_projectiles_from(spawn_pos: Vector2, direction: Vector2) -> void:
	"""从指定位置生成投射物（子类可重写）"""
	for i in range(projectile_count):
		var spread_angle := _calculate_spread(i)
		var spawn_dir := direction.rotated(spread_angle)
		_spawn_bullet_from(spawn_pos, spawn_dir)

func _calculate_spread(index: int) -> float:
	"""计算单个投射物的扩散角度"""
	if projectile_count <= 1 or spread <= 0:
		return 0.0

	var step := spread / float(projectile_count - 1)
	var offset := -spread * 0.5
	return offset + step * index

func _spawn_bullet_from(spawn_pos: Vector2, direction: Vector2) -> void:
	"""从指定位置实际生成子弹（子类重写可自定义子弹行为）"""
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		_setup_bullet(bullet, spawn_pos, direction)
		get_tree().root.add_child(bullet)

func _setup_bullet(bullet: Node, spawn_pos: Vector2, direction: Vector2) -> void:
	"""配置子弹属性"""
	if bullet.has_method("fire"):
		bullet.fire(spawn_pos, direction, bullet_speed, bullet_damage)

## 换弹
func start_reload() -> void:
	"""开始换弹"""
	if _is_reloading or current_ammo == magazine_size:
		return
	_is_reloading = true
	reload_started.emit()
	await get_tree().create_timer(reload_time).timeout
	current_ammo = magazine_size
	_is_reloading = false
	weapon_reloaded.emit()
	ammo_changed.emit(current_ammo, magazine_size)

## 激活/停用
func activate() -> void:
	_is_active = true

func deactivate() -> void:
	_is_active = false

## 获取武器信息（调试用）
func get_weapon_info() -> Dictionary:
	return {
		"fire_rate": fire_rate,
		"projectile_count": projectile_count,
		"spread": spread,
		"reload_time": reload_time,
		"ammo": "%d/%d" % [current_ammo, magazine_size],
		"damage": damage,
		"reloading": _is_reloading
	}