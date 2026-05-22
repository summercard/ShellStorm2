extends Node2D
class_name WeaponController

# WeaponController.gd — 武器射击控制
# 挂载在 Player 下，接收输入并调用 WeaponCore 射击
# T02: 重构使用 WeaponCore.fire_from(muzzle_pos, dir) 接口

@export var weapon_core: Node2D = null

@onready var player: CharacterBody2D = get_parent()

var fire_cooldown: float = 0.0
var fire_rate: float = 4.0  # 默认每秒4发

func _ready() -> void:
	# 找到 WeaponCore
	if not weapon_core:
		weapon_core = get_node_or_null("../../../weapons/WeaponCore")
	if weapon_core and weapon_core.has_method("get_fire_rate"):
		fire_rate = weapon_core.get_fire_rate()

func _process(delta: float) -> void:
	if fire_cooldown > 0:
		fire_cooldown -= delta

	if Input.is_action_pressed("shoot") and fire_cooldown <= 0:
		fire()

func fire() -> void:
	# 使用 WeaponCore.fire_from() 从枪口位置发射
	var aim_dir = player.get_aim_direction() if player.has_method("get_aim_direction") else Vector2.RIGHT
	var muzzle_pos = player.global_position + aim_dir * 35.0

	fire_cooldown = 1.0 / fire_rate

	if weapon_core and weapon_core.has_method("fire_from"):
		weapon_core.fire_from(muzzle_pos, aim_dir)
	else:
		# Fallback: 旧版直接发射（无 WeaponCore 时）
		_spawn_bullet_fallback(muzzle_pos, aim_dir)

func _spawn_bullet_fallback(muzzle_pos: Vector2, direction: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var bullet = bullet_scene.instantiate()
	bullet.fire(muzzle_pos, direction, 600.0, 10)
	get_tree().root.add_child(bullet)

func get_fire_rate() -> float:
	return fire_rate