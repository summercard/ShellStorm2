extends CharacterBody2D

const EnemyModifierScript := preload("res://src/enemy/EnemyModifier.gd")
const ENEMY_PROJECTILE_SCENE := preload("res://scenes/EnemyProjectile.tscn")

signal hp_changed(current: int, maximum: int)
signal enemy_died()
signal enemy_hit(hit_from: Vector2, damage: int, is_crit: bool)

@export var max_hp: int = 30
@export var speed: float = 80.0
@export var damage: int = 10
@export var contact_radius: float = 31.0
@export var contact_damage_interval: float = 0.62

var current_hp: int = 30
var player_ref: Node2D = null

var ai_type: String = "chase"       # chase / ranged / summoner / bomber / trapper
var use_default_chase: bool = true

var shoot_interval: float = 1.7
var summon_interval: float = 5.0
var explosion_radius: float = 82.0
var explosion_damage: int = 25
var trigger_radius: float = 120.0

var _shoot_timer: float = 0.0
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _triggered: bool = false
var _exploded: bool = false
var _is_dead: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO
var _modifiers: Array = []
var _enemy_data: Dictionary = {}

@onready var shape: ColorRect = $Shape
@onready var emoji_label: Label = get_node_or_null("Emoji") as Label
@onready var hp_bar: ProgressBar = get_node_or_null("HPBarBG/HPBar") as ProgressBar

func set_enemy_data(data: Dictionary) -> void:
	_enemy_data = data.duplicate(true)
	if data.has("emoji") or data.has("color"):
		set_visuals(data.get("emoji", "👾"), data.get("color", Color(1.0, 0.25, 0.25, 1.0)), float(data.get("scale", 1.0)))

func get_enemy_data() -> Dictionary:
	return _enemy_data

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemy")
	z_as_relative = false
	_fire_timers()
	_update_hp_bar(true)
	_update_z_index()

func _fire_timers() -> void:
	_shoot_timer = randf_range(0.25, shoot_interval)
	_summon_timer = summon_interval

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _contact_timer > 0.0:
		_contact_timer -= delta
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node2D
		if player_ref == null:
			return
	match ai_type:
		"chase":
			_behavior_chase(delta)
		"ranged":
			_behavior_ranged(delta)
		"summoner":
			_behavior_summoner(delta)
		"bomber":
			_behavior_bomber(delta)
		"trapper":
			_behavior_trapper(delta)
		_:
			_behavior_chase(delta)
	velocity += _separation_velocity()
	velocity += _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	_try_contact_damage()
	_update_z_index()

func _behavior_chase(_delta: float) -> void:
	var direction := (player_ref.global_position - global_position).normalized()
	velocity = direction * speed

func _behavior_ranged(delta: float) -> void:
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()
	var preferred_dist := 310.0
	var tangent := Vector2(-dir.y, dir.x)
	if dist < preferred_dist - 55.0:
		velocity = -dir * speed
	elif dist > preferred_dist + 120.0:
		velocity = dir * speed * 0.55
	else:
		velocity = tangent * speed * 0.34
	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_shoot_timer = shoot_interval
		_ranged_shoot(dir)

func _behavior_summoner(delta: float) -> void:
	var direction := (player_ref.global_position - global_position).normalized()
	velocity = direction * speed * 0.65
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_summon_timer = summon_interval
		_spawn_minion()

func _behavior_bomber(_delta: float) -> void:
	if _exploded:
		return
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()
	velocity = dir * speed
	if dist < 28.0:
		_exploded = true
		_trigger_explosion()

func _behavior_trapper(_delta: float) -> void:
	if _triggered:
		var direction := (player_ref.global_position - global_position).normalized()
		velocity = direction * speed * 2.6
		return
	var to_player := player_ref.global_position - global_position
	if to_player.length() < trigger_radius:
		_triggered = true
		velocity = to_player.normalized() * speed * 2.6
	else:
		velocity = Vector2.ZERO

func _separation_velocity() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var delta: Vector2 = global_position - other.global_position
		var d: float = delta.length()
		if d > 0.01 and d < 42.0:
			push += delta.normalized() * (42.0 - d)
	return push * 0.8  # 降低分离强度，避免挤压时弹飞 + 减少粘附

func _try_contact_damage() -> void:
	if _contact_timer > 0.0 or player_ref == null or not is_instance_valid(player_ref):
		return
	if global_position.distance_to(player_ref.global_position) <= contact_radius:
		if player_ref.has_method("take_damage"):
			player_ref.take_damage(damage)
		_contact_timer = contact_damage_interval

func _ranged_shoot(dir: Vector2) -> void:
	var projectile: Node = ENEMY_PROJECTILE_SCENE.instantiate()
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(projectile)
	var spawn_pos := global_position + dir * 28.0
	if projectile.has_method("launch"):
		projectile.launch(spawn_pos, dir, 315.0, damage)

func _spawn_minion() -> void:
	var minion_scene: PackedScene = preload("res://scenes/Enemy.tscn")
	var minion = minion_scene.instantiate()
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(minion)
	var offset := Vector2(randf_range(-48, 48), randf_range(-48, 48))
	minion.global_position = global_position + offset
	minion.max_hp = max(10, int(max_hp * 0.35))
	minion.current_hp = minion.max_hp
	minion.damage = max(4, int(damage * 0.65))
	minion.speed = speed * 1.08
	if minion.has_method("set_visuals"):
		minion.set_visuals("🦇", Color(0.85, 0.25, 0.95, 1.0), 0.82)

func _trigger_explosion() -> void:
	if player_ref and is_instance_valid(player_ref):
		var to_player := player_ref.global_position - global_position
		if to_player.length() < explosion_radius and player_ref.has_method("take_damage"):
			player_ref.take_damage(explosion_damage)
	_spawn_explosion_flash()
	die()

func take_damage(amount: int, is_crit: bool = false, hit_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	current_hp = max(0, current_hp - amount)
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * (95.0 if not is_crit else 150.0)
	_update_hp_bar()
	flash_damage(is_crit)
	enemy_hit.emit(global_position, amount, is_crit)
	_spawn_damage_number(global_position, amount, is_crit)
	if current_hp <= 0:
		die()

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	enemy_died.emit()
	_spawn_death_flash()
	emit_death_screen_effect()
	if hp_bar:
		hp_bar.visible = false
	var target: CanvasItem = emoji_label if emoji_label != null else shape
	if target:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(target, "scale", Vector2(0.1, 0.1), 0.22).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(target, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func set_visuals(emoji: String, color: Color, scale_mult: float = 1.0) -> void:
	if emoji_label:
		emoji_label.text = emoji
		emoji_label.scale = Vector2.ONE * scale_mult
	if shape:
		shape.color = color
		shape.scale = Vector2.ONE * scale_mult
	_update_hp_bar(true)

func _spawn_explosion_flash() -> void:
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 950
	flash.size = Vector2(explosion_radius * 2.0, explosion_radius * 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.color = Color(1.0, 0.45, 0.12, 0.42)
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(flash)
	flash.global_position = global_position - flash.size * 0.5
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.25, 0.25), 0.18)
	t.tween_property(flash, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(flash.queue_free)

func _spawn_death_flash() -> void:
	# 颜色随敌人类型变化：从 _enemy_data.color 或当前 shape.color 读取
	var flash_color: Color = Color(1.0, 1.0, 0.8, 0.85)  # 默认淡黄白
	if _enemy_data.has("color") and _enemy_data["color"] is Color:
		flash_color = _enemy_data["color"]
	elif shape and shape.color != Color.WHITE:
		flash_color = shape.color
	# 略微提亮、增强饱和度，让死亡爆炸更醒目
	flash_color = Color(
		min(flash_color.r * 1.2, 1.0),
		min(flash_color.g * 1.2, 1.0),
		min(flash_color.b * 1.2, 1.0),
		0.85
	)
	var flash := ColorRect.new()
	flash.z_as_relative = false
	flash.z_index = 960
	flash.size = Vector2(46, 46)
	flash.pivot_offset = flash.size * 0.5
	flash.color = flash_color
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(flash)
	flash.global_position = global_position - flash.size * 0.5
	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.12).set_trans(Tween.TRANS_QUAD)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_LINEAR)
	flash_tween.chain().tween_callback(flash.queue_free)

func emit_death_screen_effect() -> void:
	var shake := get_tree().root.find_child("ScreenShake", true, false) as Node
	if shake and shake.has_method("trigger"):
		var intensity := 4.0
		if max_hp >= 80:
			intensity = 11.0
		elif max_hp >= 40:
			intensity = 7.0
		shake.trigger(intensity, 0.12)
	var audio: Node = get_node_or_null("/root/AudioManager") as Node
	if audio and audio.has_method("play_enemy_die_sfx"):
		audio.play_enemy_die_sfx()

func _update_hp_bar(force: bool = false) -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
		hp_bar.visible = force or current_hp < max_hp
	hp_changed.emit(current_hp, max_hp)

func flash_damage(is_crit: bool = false) -> void:
	# 基础闪白（敌人受击的标准反馈）
	if shape:
		var original := shape.color
		var flash_color := Color(1.0, 1.0, 1.0, 1.0)  # 纯白闪
		var flash_duration := 0.045
		var scale_target := Vector2(1.0, 1.0)
		if is_crit:
			# 暴击：更亮、更久、伴随缩放脉冲
			flash_color = Color(1.0, 0.98, 0.6, 1.0)   # 亮黄白（暴击感）
			flash_duration = 0.10
			scale_target = Vector2(1.12, 1.12)          # 轻微放大脉冲
		shape.color = flash_color
		# 缩放脉冲（暴击时更明显）
		if scale_target != Vector2(1.0, 1.0):
			var orig_scale := shape.scale
			shape.scale = scale_target
			var scale_tween := create_tween()
			scale_tween.tween_property(shape, "scale", orig_scale, flash_duration * 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(flash_duration).timeout
		if shape and not _is_dead:
			shape.color = original
	if emoji_label:
		var old := emoji_label.modulate
		var emoji_flash := Color(1.0, 0.85, 0.85, 1.0) if not is_crit else Color(1.0, 0.98, 0.6, 1.0)
		var emoji_duration := 0.045 if not is_crit else 0.10
		emoji_label.modulate = emoji_flash
		await get_tree().create_timer(emoji_duration).timeout
		if emoji_label and not _is_dead:
			emoji_label.modulate = old

func _update_z_index() -> void:
	z_index = 1000 + int(global_position.y)  # 负Y区域也必须高于背景层

func add_modifier(modifier_id: String, tier: int = 1) -> void:
	var mod = EnemyModifierScript.Factory.create(modifier_id, tier)
	if mod:
		_modifiers.append(mod)
		mod.apply(self)

func _spawn_damage_number(world_pos: Vector2, dmg: int, is_crit: bool = false) -> void:
	get_tree().call_group("game_ui", "show_damage_popup", world_pos, dmg, is_crit)
	return
	var scene_path := "res://scenes/DamageNumber.tscn"
	var num_scene: PackedScene = load(scene_path)
	if num_scene:
		var label: Node = num_scene.instantiate()
		if label is Label:
			# 文本内容：暴击加 "!" 后缀
			label.text = str(dmg) + ("!" if is_crit else "")
			# 初始随机偏移，位置在敌人头顶
			var offset := Vector2(randf_range(-8, 8), -20)
			label.position = world_pos + offset
			label.z_index = 200
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			# --- 样式分层 ---
			var font_size := 18
			var base_color := Color(1.0, 0.35, 0.2, 1.0)   # 红橙
			var anim_duration := 0.8
			var float_range := 50.0

			if is_crit:
				# 暴击：金色，更大字号，更高飘幅
				font_size = 30
				base_color = Color(1.0, 0.92, 0.15, 1.0)   # 亮金
				float_range = 65.0
			elif dmg >= 50:
				# 大伤害：橙色，更大字号
				font_size = 24
				base_color = Color(1.0, 0.55, 0.1, 1.0)    # 橙红
				float_range = 58.0

			# 字号覆盖 & 颜色
			label.add_theme_font_size_override("font_size", font_size)
			label.modulate = base_color

			# 描边效果（通过暗色阴影模拟 Outline）
			# 在 label 下方叠加一个偏移暗色副本做描边
			var outline_label := Label.new()
			outline_label.text = label.text
			outline_label.add_theme_font_size_override("font_size", font_size)
			outline_label.modulate = Color(0.0, 0.0, 0.0, 0.7)
			outline_label.z_index = label.z_index - 1
			outline_label.position = label.position + Vector2(2, 2)
			outline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			outline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
			parent.add_child(outline_label)

			# --- 动画：飘字 + 透明度 + 缩放消失（与 DamageNumbers.gd 一致）---
			label.scale = Vector2(1.25, 1.25)   # 初始放大（弹入感）
			outline_label.scale = Vector2(1.25, 1.25)

			var tween := label.create_tween()
			tween.set_parallel(true)
			tween.tween_property(label, "position:y", world_pos.y - float_range + offset.y, anim_duration).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(label, "modulate:a", 0.0, anim_duration).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(label, "scale", Vector2(0.75, 0.75), anim_duration).set_trans(Tween.TRANS_LINEAR)

			var outline_tween := outline_label.create_tween()
			outline_tween.set_parallel(true)
			outline_tween.tween_property(outline_label, "position:y", world_pos.y - float_range + offset.y, anim_duration).set_trans(Tween.TRANS_LINEAR)
			outline_tween.tween_property(outline_label, "modulate:a", 0.0, anim_duration).set_trans(Tween.TRANS_LINEAR)
			outline_tween.tween_property(outline_label, "scale", Vector2(0.75, 0.75), anim_duration).set_trans(Tween.TRANS_LINEAR)

			# 弹入动画：快速收缩到正常大小
			var pop := label.create_tween()
			pop.tween_property(label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK)
			var outline_pop := outline_label.create_tween()
			outline_pop.tween_property(outline_label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK)

			# 完成后自毁
			tween.chain().tween_callback(label.queue_free)
			outline_tween.chain().tween_callback(outline_label.queue_free)
