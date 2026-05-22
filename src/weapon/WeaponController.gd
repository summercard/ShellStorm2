extends Node2D
class_name WeaponController

# WeaponController.gd — 武器射击控制
# 挂载在 Player 下，接收输入并调用 WeaponAssemblyTree 射击
# T03: 重构使用 WeaponAssemblyTree.fire_from(muzzle_pos, dir) 接口

@onready var player: CharacterBody2D = get_parent()

## 武器装配树引用（从 Player 获取）
var weapon_tree: WeaponAssemblyTree = null

## 本地冷却计时器（委托给 weapon_tree.tick 更新）
var fire_cooldown: float = 0.0

func _ready() -> void:
	# 从 Player 获取 weapon_tree
	if player and player.has_method("get_weapon_tree"):
		weapon_tree = player.get_weapon_tree()

func _process(delta: float) -> void:
	# 更新 weapon_tree 的冷却（内部会处理 _fire_cooldown）
	if weapon_tree:
		weapon_tree.tick(delta)
	
	# 检查射击输入
	if Input.is_action_pressed("shoot"):
		# WeaponAssemblyTree 内部已处理自己的冷却
		if weapon_tree and weapon_tree._fire_cooldown <= 0:
			fire()

func fire() -> void:
	# 从枪口位置发射
	var aim_dir = player.get_aim_direction() if player.has_method("get_aim_direction") else Vector2.RIGHT
	var muzzle_pos = player.global_position + aim_dir * 35.0

	if weapon_tree:
		weapon_tree.fire_from(muzzle_pos, aim_dir)
	else:
		# Fallback: 无装配树时直接生成子弹（不应该发生）
		_spawn_bullet_fallback(muzzle_pos, aim_dir)

func _spawn_bullet_fallback(muzzle_pos: Vector2, direction: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var bullet = bullet_scene.instantiate()
	bullet.fire(muzzle_pos, direction, 600.0, 10)
	get_tree().root.add_child(bullet)

func get_fire_rate() -> float:
	if weapon_tree:
		return weapon_tree.fire_rate
	return 4.0