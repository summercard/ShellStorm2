extends Node2D
class_name WeaponController

# WeaponController.gd — 武器射击控制
# 挂载在 Player 下，接收输入并调用 WeaponAssemblyTree 射击。

@onready var player: CharacterBody2D = get_parent()

var weapon_tree: WeaponAssemblyTree = null
var _muzzle_flash: PointLight2D = null
var _recoil: Node = null
var _audio: AudioManager = null

func _ready() -> void:
	_refresh_weapon_tree()
	_muzzle_flash = get_node_or_null("../MuzzleFlash")
	_recoil = get_node_or_null("WeaponRecoil")
	if _recoil != null and not (_recoil is WeaponRecoil):
		push_warning("[WeaponController] WeaponRecoil node found but type mismatch, ignoring")
		_recoil = null
	_audio = get_node_or_null("/root/AudioManager") as AudioManager

func _process(delta: float) -> void:
	if weapon_tree == null or not is_instance_valid(weapon_tree):
		_refresh_weapon_tree()
	if weapon_tree:
		weapon_tree.tick(delta)
	if Input.is_action_pressed("shoot"):
		if weapon_tree == null:
			fire()
		elif weapon_tree._fire_cooldown <= 0.0:
			fire()

func _refresh_weapon_tree() -> void:
	if player and player.has_method("get_weapon_tree"):
		weapon_tree = player.get_weapon_tree()

func fire() -> void:
	if player == null or not is_instance_valid(player):
		return
	var aim_dir: Vector2 = player.get_aim_direction() if player.has_method("get_aim_direction") else Vector2.RIGHT
	var muzzle_pos: Vector2 = player.global_position + aim_dir * 35.0
	var fired := false
	if weapon_tree:
		var prev_ammo: int = weapon_tree.current_ammo
		fired = weapon_tree.fire_from(muzzle_pos, aim_dir)
		if fired and weapon_tree.current_ammo < prev_ammo and _audio:
			_audio.play_fire_sfx(weapon_tree.fire_rate, weapon_tree.projectile_count)
	else:
		_spawn_bullet_fallback(muzzle_pos, aim_dir)
		fired = true
	if fired:
		_trigger_muzzle_flash()
		if _recoil and weapon_tree:
			var root_tags: Array[String] = []
			if weapon_tree.get_root():
				root_tags = weapon_tree.get_root().tags
			_recoil.trigger(root_tags)

func _trigger_muzzle_flash() -> void:
	if _muzzle_flash:
		_muzzle_flash.visible = true
		_muzzle_flash.global_position = player.global_position + player.get_aim_direction() * 38.0
		var tween := _muzzle_flash.create_tween()
		tween.tween_property(_muzzle_flash, "visible", false, 0.055)

func get_fire_rate() -> float:
	if weapon_tree:
		return weapon_tree.fire_rate
	return 4.0

func _spawn_bullet_fallback(spawn_pos: Vector2, direction: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		if bullet.has_method("fire"):
			bullet.fire(spawn_pos, direction, 650.0, 8, false)
