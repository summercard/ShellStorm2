class_name BossActor
extends CharacterBody2D
## 真正的 Boss 实体 — 整合 BossPhaseDirector + 技能节点执行
## 替换 DemoBoss 的空洞 HP box，提供完整的阶段切换、技能施放、Boss 体型表现
## 
## 设计：
## - 引用 BossPhaseDirector 管理阶段和技能树
## - 技能节点通过 BossSkillNode._execute_skill() 实际施放效果
## - 监听 phase_started / skill_triggered 信号，执行对应技能逻辑
## - 体型（scale）联动碰撞半径、房间边界约束、HP 放大
## - 死亡时派发粒子爆炸 + 震屏 + 通知 BossRoomLogic

signal boss_damaged(boss_id: String, damage: float, new_hp: float, max_hp: float)
signal boss_defeated()
signal boss_phase_changed(boss_id: String, phase: int)
signal boss_skill_executed(skill_id: String)

const BOSS_AVATAR_RENDERER_SCRIPT := preload("res://src/enemy/BossAvatarRenderer.gd")

## Boss 配置
@export var boss_id: String = "boss_actor_01"
@export var max_hp: float = 800.0
@export var current_hp: float = 800.0
@export var damage_cooldown: float = 0.3
## Boss 体型缩放（1.0=正常，2.0=双倍体型）
@export var boss_scale: float = 1.0

## 视觉
@onready var shape: ColorRect = $Shape as ColorRect
@onready var hp_bar_bg: PanelContainer = $HPBarBG as PanelContainer
@onready var hp_bar: ProgressBar = $HPBarBG/HPBar as ProgressBar
@onready var boss_name_label: Label = $BossNameLabel as Label
@onready var _phase_director: Node = $BossPhaseDirector as Node
@onready var collision_shape: CollisionShape2D = $CollisionShape2D as CollisionShape2D
var avatar_renderer: Node = null

var _current_hp: float = 800.0
var _damage_cooldown_timer: float = 0.0
var _is_dead: bool = false
var _invulnerable: bool = false
var _activated: bool = false
var _current_scale: float = 1.0
var _room_bounds: Rect2 = Rect2(-400, -300, 800, 600)
## 外置 boss_scale 覆盖（由 MonsterInjector._generate_boss 根据楼层计算，RoomGameMode 注入）
## 在 _ready() 之后通过 set_boss_scale_override() 注入，用于实现第二关体型显著增大
var _boss_scale_override: float = -1.0
var _base_max_hp: float = 800.0
var _completion_notified := false

func set_boss_scale_override(scale: float) -> void:
	## 体型只影响轮廓、碰撞和技能范围。最终 HP 由 BossRoomDirector
	## 在 configure_encounter() 中给出，不能在这里再乘一次倍率。
	_boss_scale_override = scale
	_current_scale = maxf(0.75, scale)
	_apply_shape_scale()
	_setup_hp_bar()


func configure_encounter(encounter: Dictionary) -> void:
	## Map progress owns final HP/rewards; this actor owns collision and feedback.
	## Keeping the values identical is what makes "hit → defeat → extraction" atomic.
	boss_id = str(encounter.get("boss_id", boss_id))
	_current_scale = maxf(0.75, float(encounter.get("boss_scale", boss_scale)))
	_base_max_hp = maxf(1.0, float(encounter.get("base_max_hp", encounter.get("max_hp", max_hp))))
	max_hp = maxf(1.0, float(encounter.get("max_hp", max_hp)))
	_current_hp = max_hp
	current_hp = max_hp
	_damage_cooldown_timer = 0.0
	_is_dead = false
	_completion_notified = false
	_apply_shape_scale()
	_setup_hp_bar()

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("enemy")
	add_to_group("boss")
	
	_base_max_hp = max_hp
	_current_hp = max_hp
	current_hp = max_hp
	_current_scale = boss_scale
	_setup_hp_bar()
	_connect_phase_signals()
	_apply_shape_scale()
	_ensure_avatar_renderer()
	z_index = 100
	_init_state_machine()
	print("[BossActor] Ready - HP: %d/%d scale: %.1f" % [_current_hp, max_hp, _current_scale])


func _connect_phase_signals() -> void:
	if _phase_director and _phase_director.has_signal("phase_started"):
		_phase_director.phase_started.connect(_on_phase_started)
	if _phase_director and _phase_director.has_signal("skill_triggered"):
		_phase_director.skill_triggered.connect(_on_skill_triggered)


## 设置阶段技能树（由外部调用，配置 BossPhaseDirector）
func configure_phases(skill_trees: Dictionary) -> void:
	if _phase_director == null:
		return
	_phase_director.configure(skill_trees.size(), skill_trees)
	print("[BossActor] 配置了 %d 个阶段的技能树" % skill_trees.size())


func activate() -> void:
	if _activated:
		return
	if _state_machine and _state_machine_initialized:
		_state_machine.transition_to("combat")
	else:
		_activated = true
	_notify_game_ui_spawn()


## ================================================
## 阶段 & 技能 信号处理
## ================================================

func _on_phase_started(b_id: String, phase: int) -> void:
	if b_id != boss_id and b_id != "":
		return
	boss_phase_changed.emit(boss_id, phase)
	print("[BossActor] 阶段切换 -> Phase %d" % phase)
	# 阶段切换时触发视觉反馈：Boss 闪烁
	_flash_phase_change(phase)
	if avatar_renderer != null and avatar_renderer.has_method("set_phase"):
		avatar_renderer.call("set_phase", phase)
	# 阶段切换时触发全屏震屏（Boss 威压感）
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null and shake.has_method("trigger"):
		var intensity := 12.0 + phase * 2.0  # 阶段越高震动越强
		shake.call("trigger", intensity, 0.25)


func _on_skill_triggered(b_id: String, skill_id: String, phase: int) -> void:
	if b_id != boss_id and b_id != "":
		return
	print("[BossActor] 触发技能 [%s] (Phase %d)" % [skill_id, phase])
	boss_skill_executed.emit(skill_id)
	_execute_skill_by_id(skill_id)
	_notify_game_ui_spawn()


## 根据 skill_id 实际执行技能效果
## 这里直接路由到 BossSkillNode 的预置技能执行逻辑
func _execute_skill_by_id(skill_id: String) -> void:
	match skill_id:
		"spawn_minions":
			_skill_spawn_minions()
		"aoe_damage":
			_skill_aoe_damage()
		"telegraphed_shot":
			_skill_telegraphed_shot()
		"debuff_zone":
			_skill_debuff_zone()
		"charge":
			_skill_charge()
		"enrage":
			_skill_enrage()
		_:
			print("[BossActor] 未知技能ID: %s（跳过）" % skill_id)


## ================================================
## 具体技能执行
## ================================================

func _skill_spawn_minions() -> void:
	## 在 Boss 周围生成 3 只小怪
	var minion_scene: PackedScene = load("res://scenes/Enemy.tscn") as PackedScene
	if minion_scene == null:
		print("[BossActor] spawn_minions: Enemy.tscn 未找到")
		return
	var count: int = 3
	for i in range(count):
		var angle: float = TAU * i / count + randf_range(-0.2, 0.2)
		var spawn_offset: Vector2 = Vector2(cos(angle), sin(angle)) * 55.0
		var minion: Node = minion_scene.instantiate()
		var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		parent.add_child(minion)
		minion.global_position = global_position + spawn_offset
		minion.set("max_hp", max(15, int(max_hp * 0.04)))
		minion.set("current_hp", minion.get("max_hp"))
		minion.set("damage", max(6, int(max_hp * 0.5)))
		minion.set("speed", 90.0)
		if minion.has_method("set_visuals"):
			minion.set_visuals("👾", Color(0.65, 0.10, 0.10, 1.0), 0.85)
	print("[BossActor] 生成了 %d 只小怪" % count)


func _skill_aoe_damage() -> void:
	## 以 Boss 为中心释放一圈 AOE 伤害
	var aoe_radius: float = 180.0 * _current_scale
	var aoe_damage: int = 30
	var player: Node = get_tree().get_first_node_in_group("player") as Node
	if player == null or not is_instance_valid(player):
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= aoe_radius:
		if player.has_method("take_damage"):
			player.take_damage(aoe_damage)
	_spawn_aoe_ring(aoe_radius)


func _skill_telegraphed_shot() -> void:
	## 蓄力后向玩家发射一颗高伤害子弹（预警 1 秒）
	var player: Node = get_tree().get_first_node_in_group("player") as Node
	if player == null or not is_instance_valid(player):
		return
	# 先显示预警区域
	_spawn_telegraph_warning(player.global_position)
	# 1秒后发射
	await get_tree().create_timer(1.0).timeout
	var dir: Vector2 = (player.global_position - global_position).normalized()
	var spawn_pos: Vector2 = global_position + dir * 38.0
	var bullet_scene: PackedScene = load("res://scenes/EnemyProjectile.tscn") as PackedScene
	if bullet_scene != null:
		var proj: Node = bullet_scene.instantiate()
		var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		parent.add_child(proj)
		proj.z_as_relative = false
		proj.z_index = 890
		if proj.has_method("launch"):
			proj.launch(spawn_pos, dir, 320.0, 40)


func _skill_debuff_zone() -> void:
	## 在玩家当前位置留下一个减益区域（持续 3 秒）
	var player: Node = get_tree().get_first_node_in_group("player") as Node
	if player == null or not is_instance_valid(player):
		return
	var zone_pos: Vector2 = player.global_position
	var zone: ColorRect = ColorRect.new()
	zone.custom_minimum_size = Vector2(140, 140)
	zone.size = Vector2(140, 140)
	zone.pivot_offset = zone.size * 0.5
	zone.color = Color(0.5, 0.1, 0.8, 0.22)
	zone.z_index = 50
	zone.z_as_relative = false
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(zone)
	zone.global_position = zone_pos - zone.size * 0.5
	# 脉冲动画
	var t: Tween = zone.create_tween()
	t.set_loop(true)
	t.tween_property(zone, "modulate:a", 0.35, 0.5)
	t.tween_property(zone, "modulate:a", 0.12, 0.5)
	# 3秒后消失
	await get_tree().create_timer(3.0).timeout
	t.kill()
	zone.queue_free()
	print("[BossActor] 减益区域消散")


func _skill_charge() -> void:
	## Boss 冲向玩家方向（冲刺 200px）
	var player: Node = get_tree().get_first_node_in_group("player") as Node
	if player == null or not is_instance_valid(player):
		return
	var dir: Vector2 = (player.global_position - global_position).normalized()
	var charge_target: Vector2 = global_position + dir * 200.0
	# 限制在房间边界内
	charge_target = _clamp_to_room_bounds(charge_target)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", charge_target, 0.45).set_trans(Tween.TRANS_QUAD)
	# 冲刺过程中留下残影
	_spawn_charge_trail(dir)
	await tween.finished
	# 落地冲击（附近玩家受伤）
	var impact_radius: float = 70.0 * _current_scale
	if player.global_position.distance_to(global_position) <= impact_radius:
		if player.has_method("take_damage"):
			player.take_damage(25)


func _skill_enrage() -> void:
	## 狂暴：攻速翻倍，Boss 身上冒红烟，颜色加深
	if shape:
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(shape, "color", Color(0.95, 0.08, 0.08, 1.0), 0.3)
		shape.scale = Vector2.ONE * _current_scale * 1.15
		tween.tween_property(shape, "scale", Vector2.ONE * _current_scale, 0.5).set_trans(Tween.TRANS_BOUNCE)
	# 通知 GameUIManager 显示狂暴状态
	_notify_boss_damaged(0.0)
	print("[BossActor] 狂暴触发，Boss 进入高攻速状态")


## ================================================
## 辅助：视觉 & 反馈
## ================================================

func _spawn_aoe_ring(radius: float) -> void:
	var ring := ColorRect.new()
	ring.custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	ring.size = Vector2(radius * 2.0, radius * 2.0)
	ring.pivot_offset = ring.size * 0.5
	ring.color = Color(0.9, 0.15, 0.15, 0.35)
	ring.z_index = 60
	ring.z_as_relative = false
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(ring)
	ring.global_position = global_position - ring.size * 0.5
	var t: Tween = ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(1.4, 1.4), 0.25)
	t.tween_property(ring, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(ring.queue_free)


func _spawn_telegraph_warning(target_pos: Vector2) -> void:
	var warn := ColorRect.new()
	var warn_size: float = 60.0
	warn.custom_minimum_size = Vector2(warn_size, warn_size)
	warn.size = Vector2(warn_size, warn_size)
	warn.pivot_offset = warn.size * 0.5
	warn.color = Color(1.0, 0.2, 0.2, 0.45)
	warn.z_index = 55
	warn.z_as_relative = false
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(warn)
	warn.global_position = target_pos - warn.size * 0.5
	var t: Tween = warn.create_tween()
	t.set_loops(-1)
	t.tween_property(warn, "modulate:a", 0.6, 0.2)
	t.tween_property(warn, "modulate:a", 0.15, 0.2)
	await get_tree().create_timer(0.9).timeout
	t.kill()
	warn.queue_free()


func _spawn_charge_trail(dir: Vector2) -> void:
	for i in range(4):
		var trail := ColorRect.new()
		trail.custom_minimum_size = Vector2(28, 28)
		trail.size = Vector2(28, 28)
		trail.color = Color(0.7, 0.08, 0.08, 0.4)
		trail.z_index = 95
		trail.z_as_relative = false
		var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		parent.add_child(trail)
		trail.global_position = global_position - dir * i * 25.0
		var t: Tween = trail.create_tween()
		t.set_parallel(true)
		t.tween_property(trail, "modulate:a", 0.0, 0.3)
		t.tween_property(trail, "size", Vector2(10, 10), 0.3)
		t.chain().tween_callback(trail.queue_free)


func _flash_phase_change(phase: int) -> void:
	if shape == null:
		return
	var flash_color := Color(1.0, 1.0, 0.6, 0.9)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shape, "color", flash_color, 0.08)
	tween.tween_property(shape, "scale", Vector2.ONE * _current_scale * 1.2, 0.1)
	tween.chain().tween_property(shape, "color", _get_shape_color_for_phase(phase), 0.25)
	tween.chain().tween_property(shape, "scale", Vector2.ONE * _current_scale, 0.3).set_trans(Tween.TRANS_BOUNCE)


func _get_shape_color_for_phase(phase: int) -> Color:
	match phase:
		1: return Color(0.75, 0.12, 0.12, 1.0)
		2: return Color(0.85, 0.18, 0.05, 1.0)
		3: return Color(0.95, 0.05, 0.05, 1.0)
		_: return Color(0.8, 0.1, 0.1, 1.0)


func _clamp_to_room_bounds(pos: Vector2) -> Vector2:
	var margin: float = 40.0 * _current_scale
	return Vector2(
		clampf(pos.x, _room_bounds.position.x + margin, _room_bounds.position.x + _room_bounds.size.x - margin),
		clampf(pos.y, _room_bounds.position.y + margin, _room_bounds.position.y + _room_bounds.size.y - margin)
	)


func _setup_hp_bar() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = _current_hp
		hp_bar.show_percentage = false
	if boss_name_label:
		boss_name_label.text = boss_id


func _apply_shape_scale() -> void:
	var base_size: float = 110.0
	var scaled_size: float = base_size * _current_scale
	if shape != null:
		shape.custom_minimum_size = Vector2(scaled_size, scaled_size)
		shape.offset_left = -scaled_size * 0.5
		shape.offset_top = -scaled_size * 0.5
		shape.offset_right = scaled_size * 0.5
		shape.offset_bottom = scaled_size * 0.5
		shape.scale = Vector2.ONE
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = scaled_size * 0.38
	if avatar_renderer != null and avatar_renderer.has_method("set_presentation_scale"):
		avatar_renderer.call("set_presentation_scale", _current_scale)


func _ensure_avatar_renderer() -> void:
	if avatar_renderer == null:
		avatar_renderer = get_node_or_null("AvatarRenderer") as Node
	if avatar_renderer == null:
		avatar_renderer = BOSS_AVATAR_RENDERER_SCRIPT.new() as Node
		avatar_renderer.name = "AvatarRenderer"
		add_child(avatar_renderer)
	if avatar_renderer.has_method("set_presentation_scale"):
		avatar_renderer.call("set_presentation_scale", _current_scale)
	# Scene Shape remains as an invisible backwards-compatible asset anchor.
	if shape != null:
		shape.visible = false


func _notify_game_ui_spawn() -> void:
	if get_tree().get_first_node_in_group("room_game_mode") != null:
		return
	call_deferred("_notify_game_ui_spawn_deferred")


func _notify_game_ui_spawn_deferred() -> void:
	var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
	if gui != null and gui.has_method("on_boss_spawned"):
		gui.call("on_boss_spawned", {
			"boss_id": boss_id,
			"max_hp": max_hp,
			"current_hp": _current_hp,
		})


## ================================================
## 伤害 & 死亡
## ================================================

func _process(delta: float) -> void:
	# 转发给状态机，由当前状态决定每帧逻辑
	if _state_machine and _state_machine_initialized:
		_state_machine.physics_update(delta)


func take_damage(
	damage: float, is_crit: bool = false, _hit_direction: Vector2 = Vector2.ZERO
) -> void:
	## Match EnemyBase' public hit contract.  Player bullets always provide the
	## hit direction, even when this Boss currently only uses it for future
	## directional hit reactions.
	# 转发给状态机，由 combat 状态处理
	if _state_machine and _state_machine_initialized:
		_state_machine.dispatch_event("take_damage", {"damage": damage, "is_crit": is_crit})
		print("[BossActor] took %.0f damage, HP: %.0f/%d" % [damage, _current_hp, max_hp])
		return
	# 状态机未启动：兜底用原逻辑
	if _is_dead or _invulnerable:
		return
	if _damage_cooldown_timer > 0:
		return
	_current_hp -= damage
	_damage_cooldown_timer = damage_cooldown
	current_hp = _current_hp
	if hp_bar:
		hp_bar.value = max(0, _current_hp)
	_take_damage_feedback(is_crit)
	_spawn_damage_number(global_position, int(damage), is_crit)
	_trigger_hit_screen_shake(damage, is_crit)
	_notify_boss_damaged(damage)
	Global.trigger_hitstop(is_crit)
	if _current_hp <= 0:
		_trigger_death()
	print("[BossActor] took %.0f damage, HP: %.0f/%d" % [damage, _current_hp, max_hp])


func _take_damage_feedback(is_crit: bool) -> void:
	if avatar_renderer != null and avatar_renderer.has_method("flash_hit"):
		avatar_renderer.call("flash_hit", is_crit)
	if shape == null:
		return
	var original_color := shape.color
	shape.color = Color(1.0, 1.0, 1.0, 0.9)
	var tween := create_tween()
	tween.tween_property(shape, "color", original_color, 0.15)
	if is_crit:
		shape.scale = Vector2(1.25, 1.25)
		tween.set_parallel(true)
		tween.tween_property(shape, "scale", Vector2.ONE * _current_scale, 0.2).set_trans(Tween.TRANS_BOUNCE)


func _trigger_hit_screen_shake(damage: float, is_crit: bool) -> void:
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null and shake.has_method("trigger"):
		var intensity := 7.0
		if damage >= 40:
			intensity = 14.0
		elif damage >= 20:
			intensity = 10.0
		if is_crit:
			intensity *= 1.6
		var duration := 0.18 if not is_crit else 0.25
		shake.call("trigger", intensity, duration)


func _notify_boss_damaged(damage: float) -> void:
	boss_damaged.emit(boss_id, damage, maxf(0.0, _current_hp), max_hp)
	# RoomGameMode forwards this event to BossRoomDirector.  The standalone demo
	# has no room mode, so it keeps a direct UI fallback for scene-level previews.
	if get_tree().get_first_node_in_group("room_game_mode") == null:
		var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
		if gui != null and gui.has_method("on_boss_damaged"):
			gui.call("on_boss_damaged", boss_id, damage, _current_hp)


func _spawn_damage_number(world_pos: Vector2, dmg: int, is_crit: bool) -> void:
	get_tree().call_group("game_ui", "show_damage_popup", world_pos, dmg, is_crit)


func _trigger_death() -> void:
	# Public compatibility entry.  The state owns the one-time completion signal.
	if _state_machine and _state_machine_initialized:
		_state_machine.transition_to("dead", true)
	else:
		_complete_death()


func _complete_death() -> void:
	if _completion_notified:
		return
	_completion_notified = true
	_is_dead = true
	_current_hp = 0.0
	current_hp = 0.0
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	boss_defeated.emit()
	print("[BossActor] DEFEATED: %s" % boss_id)
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null:
		if shake.has_method("screen_shake_death"):
			shake.call("screen_shake_death")
		elif shake.has_method("trigger"):
			shake.call("trigger", 24.0, 0.5)
		if shake.has_method("screen_flash"):
			shake.call("screen_flash", Color(0.85, 0.94, 1.0, 0.75), 0.18)
	_play_death_presentation()


func _play_death_presentation() -> void:
	# Cosmetic work is intentionally separate from the progress signal: a slow
	# tween can never hold hostage extraction, rewards, or room completion.
	var boss_color: Color = shape.color if shape else Color(0.9, 0.12, 0.12, 1.0)
	SparkParticles.spawn_death_burst(global_position, boss_color, true)
	_spawn_death_particles()
	if avatar_renderer != null and avatar_renderer.has_method("play_defeat"):
		avatar_renderer.call("play_defeat")
	if shape:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shape, "modulate:a", 0.0, 0.5)
		tween.tween_property(shape, "scale", Vector2(1.6, 1.6), 0.5)


func _spawn_death_particles() -> void:
	if shape == null:
		return
	var boss_pos: Vector2 = shape.global_position
	var particle_count: int = 20
	var particle_parent: Node = shape.get_parent()
	var host := Node2D.new()
	host.name = "BossDeathParticleHost"
	particle_parent.add_child(host)
	for i in range(particle_count):
		var angle: float = TAU * i / particle_count
		var particle := ColorRect.new()
		particle.name = "DeathParticle_%d" % i
		particle.custom_minimum_size = Vector2(14, 14)
		particle.size = Vector2(14, 14)
		particle.color = Color(0.9, 0.12, 0.12, 0.9)
		particle.z_index = 150
		var start_pos: Vector2 = boss_pos + Vector2(cos(angle) * 22.0, sin(angle) * 22.0)
		particle.global_position = start_pos
		host.add_child(particle)
		var tween := particle.create_tween()
		tween.set_parallel(true)
		var end_pos: Vector2 = boss_pos + Vector2(cos(angle) * 110.0, sin(angle) * 110.0)
		tween.tween_property(particle, "global_position", end_pos, 0.38)
		tween.tween_property(particle, "modulate:a", 0.0, 0.38)
		tween.tween_property(particle, "size", Vector2(4, 4), 0.38)
	var cleanup_tween := host.create_tween()
	cleanup_tween.tween_interval(0.45)
	cleanup_tween.tween_callback(host.queue_free)


## ================================================
## 外部接口
## ================================================

func apply_damage(damage: float, is_crit: bool = false) -> void:
	take_damage(damage, is_crit)


func get_hp() -> float:
	return _current_hp


func get_max_hp() -> float:
	return max_hp


func set_room_bounds(bounds: Rect2) -> void:
	_room_bounds = bounds


func get_room_bounds() -> Rect2:
	return _room_bounds


# ========== 状态机改造 (2026-06-10 PHxx 通用状态机框架接入 - BossActor) ==========
## 3 个状态（idle/combat/dead）已拆为独立 State 子类：
##   src/enemy/states/boss/BossIdleState.gd / BossCombatState.gd / BossDeadState.gd
##
## 战斗阶段（phase1/2/3）由 BossPhaseDirector 独立管理，不纳入顶层状态机。
##
## 对外行为兼容：
## - _is_dead / _invulnerable / _activated 字段保留并由各 State.enter() 同步
## - activate() / take_damage() / _trigger_death() 外部调用不需改

## 状态机节点（_ready 末尾挂上）
var _state_machine: StateMachine = null

## 状态机启动标志
var _state_machine_initialized: bool = false

## 初始化状态机
func _init_state_machine() -> void:
	if _state_machine_initialized:
		return
	_state_machine = StateMachine.new()
	_state_machine.name = "StateMachine"
	_state_machine.owner_node = self
	add_child(_state_machine)
	# 注册 3 个状态
	_state_machine.register("idle", BossIdleState.new())
	_state_machine.register("combat", BossCombatState.new())
	_state_machine.register("dead", BossDeadState.new())
	# 启动到 idle（默认未激活）
	_state_machine.start("idle")
	_state_machine_initialized = true
