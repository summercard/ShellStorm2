extends Node2D
class_name WeaponController

# WeaponController.gd — 武器射击控制
# 挂载在 Player 下，接收输入并调用 WeaponAssemblyTree 射击。

@onready var player: CharacterBody2D = get_parent()

var weapon_tree: WeaponAssemblyTree = null
var _muzzle_flash: PointLight2D = null
var _recoil: Node = null
var _audio: AudioManager = null
var _audio_ready: bool = false

## MuzzleFlash 闪白覆盖层（用于在 muzzle 位置临时显示白色矩形）
var _muzzle_white_flash: ColorRect = null

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
		_connect_audio_signals_if_needed()
	if _is_gameplay_input_blocked():
		return
	if Input.is_action_pressed("shoot"):
		if weapon_tree == null:
			fire()
		elif weapon_tree._fire_cooldown <= 0.0:
			fire()


func _is_gameplay_input_blocked() -> bool:
	if player != null and is_instance_valid(player):
		var combat_enabled = player.get("combat_enabled")
		if combat_enabled is bool and not combat_enabled:
			return true
		var locked = player.get("input_locked")
		if locked is bool and locked:
			return true
		# 沉默状态阻止射击（被精英"抢枪"词缀命中时生效）
		var silenced = player.get("_is_silenced")
		if silenced is bool and silenced:
			return true
	var ui := get_tree().root.find_child("GameUIManager", true, false)
	if ui != null and ui.has_method("blocks_gameplay_input"):
		return bool(ui.call("blocks_gameplay_input"))
	return false

func _refresh_weapon_tree() -> void:
	if player and player.has_method("get_weapon_tree"):
		weapon_tree = player.get_weapon_tree()

func _connect_audio_signals_if_needed() -> void:
	if _audio == null or _audio_ready:
		return
	if weapon_tree == null:
		return
	if not weapon_tree.reload_started.is_connected(_on_reload_started):
		weapon_tree.reload_started.connect(_on_reload_started)
	if not weapon_tree.weapon_reloaded.is_connected(_on_reload_finished_impl):
		weapon_tree.weapon_reloaded.connect(_on_reload_finished_impl)
	_audio_ready = true

func _on_reload_started() -> void:
	if _audio:
		_audio.play_reload_sfx()

func _on_reload_finished() -> void:
	pass  # 已迁移到 _on_reload_finished_impl()

## 换弹完成时，检查 WeaponAssemblyTree 当前子弹节点是否标记了 explode_on_reload
## 若标记则在玩家位置触发范围爆炸
func _on_reload_finished_impl() -> void:
	if _audio:
		_audio.play_reload_sfx()
	if weapon_tree == null:
		return
	var bullet_node: AssemblyNode = _find_bullet_node_in_tree()
	if bullet_node == null:
		return
	var stats: Dictionary = bullet_node.get_base_stats()
	if not stats.get("explode_on_reload", false):
		return
	var radius: float = stats.get("explosion_radius", 150.0)
	var damage_scale: float = stats.get("explosion_damage_scale", 0.8)
	var bullet_dmg: int = weapon_tree.bullet_damage
	var explosion_damage: int = int(float(bullet_dmg) * damage_scale)
	var player_pos: Vector2 = player.global_position if player != null else Vector2.ZERO
	_explode_at(player_pos, explosion_damage, radius)

func _find_bullet_node_in_tree() -> AssemblyNode:
	if weapon_tree == null or weapon_tree.get_root() == null:
		return null
	var all_nodes: Array[AssemblyNode] = weapon_tree.get_root().get_all_descendants()
	all_nodes.append(weapon_tree.get_root())
	for node in all_nodes:
		if node.node_type == 1:  # BULLET = 1
			return node
	return null

## 换弹爆炸命运卡片：触发换弹爆炸（由外部事件调用）
## 参数 bullet_global_pos 用于定位爆炸中心；实际爆炸参数从 weapon_tree 当前子弹节点读取
func trigger_explosion_on_reload(bullet_damage: int, bullet_global_pos: Vector2) -> void:
	if weapon_tree == null:
		return
	var bullet_node: AssemblyNode = _find_bullet_node_in_tree()
	if bullet_node == null:
		return
	var stats: Dictionary = bullet_node.get_base_stats()
	if not stats.get("explode_on_reload", false):
		return
	var radius: float = stats.get("explosion_radius", 150.0)
	var damage_scale: float = stats.get("explosion_damage_scale", 0.8)
	var explosion_damage: int = int(float(bullet_damage) * damage_scale)
	_explode_at(bullet_global_pos, explosion_damage, radius)

var _pending_explode: Dictionary = {}  ## 预留（暂无外部写入方，保留以备将来外部事件触发爆炸用）

func _explode_at(pos: Vector2, dmg: int, radius: float) -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var dist: float = pos.distance_to(e.global_position)
		if dist <= radius and e.has_method("take_damage"):
			e.call("take_damage", dmg, false, Vector2.ZERO)
	# 播放爆炸特效
	_spawn_explosion_effect(pos, radius)

func _spawn_explosion_effect(pos: Vector2, radius: float) -> void:
	var scene := preload("res://scenes/ExplosionEffect.tscn") as PackedScene
	if scene != null:
		var effect: Node2D = scene.instantiate() as Node2D
		if effect != null:
			effect.global_position = pos
			if effect.has_node("ExplosionEffect") or effect is GPUParticles2D:
				var particles: GPUParticles2D = effect as GPUParticles2D
				if particles and particles.process_material:
					particles.process_material.set("scale_min", radius / 80.0)
					particles.process_material.set("scale_max", radius / 60.0)
			get_tree().current_scene.add_child(effect)
		else:
			_fallback_explosion_flash(pos, radius)
	else:
		_fallback_explosion_flash(pos, radius)

func _fallback_explosion_flash(pos: Vector2, radius: float) -> void:
	# 回退：ColorRect 淡出光效
	var flash: ColorRect = ColorRect.new()
	flash.color = Color(1.0, 0.5, 0.1, 0.6)
	flash.size = Vector2(radius * 2.0, radius * 2.0)
	flash.position = pos - Vector2(radius, radius)
	flash.z_index = 950
	get_tree().current_scene.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.tween_callback(flash.queue_free)

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
	var muzzle_pos: Vector2 = player.global_position + player.get_aim_direction() * 38.0
	if _muzzle_flash:
		_muzzle_flash.visible = true
		_muzzle_flash.global_position = muzzle_pos
		var tween := _muzzle_flash.create_tween()
		tween.tween_interval(0.055)
		tween.tween_callback(func():
			if _muzzle_flash and is_instance_valid(_muzzle_flash):
				_muzzle_flash.visible = false
		)
	# 闪白覆盖层（仅在 WeaponController 自己的子树中生成，避免污染 Player 场景）
	_spawn_white_flash(muzzle_pos)


## 在 muzzle 位置生成 0.04s 闪白覆盖矩形
func _spawn_white_flash(muzzle_pos: Vector2) -> void:
	if _muzzle_white_flash != null and is_instance_valid(_muzzle_white_flash):
		_muzzle_white_flash.queue_free()
	_muzzle_white_flash = ColorRect.new()
	_muzzle_white_flash.color = Color(1.0, 1.0, 1.0, 0.85)
	_muzzle_white_flash.size = Vector2(18, 18)
	_muzzle_white_flash.position = muzzle_pos - Vector2(9, 9)
	_muzzle_white_flash.z_index = 960
	_muzzle_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 挂到当前场景的根节点（避免跟随 Player 移动）
	var host := get_tree().current_scene
	if host != null:
		host.add_child(_muzzle_white_flash)
	else:
		add_child(_muzzle_white_flash)
	var tween := _muzzle_white_flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_muzzle_white_flash, "modulate:a", 0.0, 0.04)
	tween.chain().tween_callback(_muzzle_white_flash.queue_free)
	# 烟雾粒子
	_spawn_muzzle_smoke(muzzle_pos)


## 在 muzzle 位置生成 4-5 颗灰色烟雾粒子（向外扩散并淡出）
func _spawn_muzzle_smoke(muzzle_pos: Vector2) -> void:
	var aim_dir: Vector2 = player.get_aim_direction() if player and player.has_method("get_aim_direction") else Vector2.RIGHT
	var host := get_tree().current_scene
	if host == null:
		return
	for i in 5:
		var smoke := Polygon2D.new()
		smoke.color = Color(0.7, 0.7, 0.72, 0.55)
		smoke.polygon = PackedVector2Array([
			Vector2(0, -3),
			Vector2(2.5, 1.5),
			Vector2(-2.5, 1.5),
		])
		smoke.position = muzzle_pos
		smoke.z_index = 955
		host.add_child(smoke)
		# 沿射击方向 + 横向散开
		var spread_angle: float = randf_range(-PI / 4.0, PI / 4.0)
		var vel: Vector2 = aim_dir.rotated(spread_angle) * randf_range(60.0, 110.0)
		var t := smoke.create_tween()
		t.set_parallel(true)
		t.tween_property(smoke, "position", muzzle_pos + vel * 0.35, 0.35)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(smoke, "scale", Vector2(1.8, 1.8), 0.35)
		t.tween_property(smoke, "modulate:a", 0.0, 0.35)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(smoke.queue_free)

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
