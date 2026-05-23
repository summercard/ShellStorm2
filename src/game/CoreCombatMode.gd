class_name CoreCombatMode
extends Node2D
## CoreCombatMode — 临时但完整的顶视角射击主循环
## 目的：先把移动、瞄准、射击、刷怪、血条、波次、死亡这些核心手感接起来。
## 旧的 RoomGameMode / MapManager 仍保留，后续可以再把房间地图系统逐步接回来。

signal room_cleared(room_data)
signal game_over(reason: String)
signal extraction_ready()
signal kill_recorded()
signal wave_progress_changed(killed: int, total: int, wave: int)

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SOUL_ORB_SCENE := preload("res://scenes/SoulOrb.tscn")
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")

@export var arena_size: Vector2 = Vector2(1800, 1100)
@export var start_delay: float = 0.9
@export var wave_clear_delay: float = 1.35
@export var spawn_radius_min: float = 430.0
@export var spawn_radius_max: float = 690.0
@export var max_wave: int = 999

@onready var game_camera: Camera2D = get_node_or_null("../Camera2D") as Camera2D
@onready var ui_layer: CanvasLayer = get_node_or_null("../GameUIManager") as CanvasLayer
@onready var hp_bar: ProgressBar = get_node_or_null("../GameUIManager/GameHUD/HPBarBG/HPBar") as ProgressBar
@onready var score_label: Label = get_node_or_null("../GameUIManager/GameHUD/TopRightPanel/VBox/ScoreLabel") as Label
@onready var wave_label: Label = get_node_or_null("../GameUIManager/GameHUD/TopRightPanel/VBox/WaveLabel") as Label
@onready var currency_label: Label = get_node_or_null("../GameUIManager/GameHUD/CurrencyLabel") as Label
@onready var room_info_label: Label = get_node_or_null("../GameUIManager/GameHUD/RoomInfoLabel") as Label
@onready var clearing_progress: ProgressBar = get_node_or_null("../GameUIManager/GameHUD/ClearingProgress") as ProgressBar
@onready var wave_indicator: Label = get_node_or_null("../GameUIManager/GameHUD/WaveIndicatorLabel") as Label
@onready var screen_shake: Node = get_node_or_null("../Camera2D/ScreenShake")

var player: Player = null
var current_wave: int = 0
var score: int = 0
var kills: int = 0
var wave_total: int = 0
var wave_killed: int = 0
var active_enemies: Array[Node] = []
var wave_active: bool = false
var game_is_over: bool = false
var rng := RandomNumberGenerator.new()
var _waiting_for_next_wave: bool = false
var _message_tween: Tween = null
var inventory_module: InventoryModule = null
var insurance_module: InsuranceModule = null

func _ready() -> void:
	rng.randomize()
	_reset_run_state()
	_spawn_player()
	_setup_camera(true)
	_bind_ui()
	_update_ui()
	_show_message("WASD移动  鼠标左键射击  Shift闪避", 1.4)
	await get_tree().create_timer(start_delay).timeout
	if not game_is_over:
		_start_next_wave()

func _reset_run_state() -> void:
	Global.start_game()
	GameManager.reset()
	GameManager.currency = 0
	GameManager.currency_changed.emit(GameManager.currency)
	current_wave = 0
	score = 0
	kills = 0
	wave_total = 0
	wave_killed = 0
	wave_active = false
	game_is_over = false
	_waiting_for_next_wave = false
	active_enemies.clear()
	inventory_module = InventoryModule.new(12)
	insurance_module = InsuranceModule.new(2)
	if not Global.game_over.is_connected(_on_global_game_over):
		Global.game_over.connect(_on_global_game_over)
	if not GameManager.currency_changed.is_connected(_on_currency_changed):
		GameManager.currency_changed.connect(_on_currency_changed)

func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = Vector2.ZERO
	if player.has_signal("hp_changed"):
		player.hp_changed.connect(_on_player_hp_changed)
	if FateCardGameBridge.has_method("set_player"):
		FateCardGameBridge.set_player(player)

func _bind_ui() -> void:
	if ui_layer != null:
		if ui_layer.has_method("set_player"):
			ui_layer.call("set_player", player)
		if ui_layer.has_method("set_room_game_mode"):
			ui_layer.call("set_room_game_mode", self)
		if ui_layer.has_method("set_inventory_module"):
			ui_layer.call("set_inventory_module", inventory_module)
		if ui_layer.has_method("set_insurance_module"):
			ui_layer.call("set_insurance_module", insurance_module)
	if clearing_progress:
		clearing_progress.visible = true
	if wave_indicator:
		wave_indicator.visible = true
		wave_indicator.text = ""
	_update_hp_bar(player.current_hp, player.max_hp)

func _setup_camera(force: bool = false) -> void:
	if game_camera == null or player == null:
		return
	game_camera.enabled = true
	game_camera.make_current()
	game_camera.position_smoothing_enabled = true
	game_camera.position_smoothing_speed = 10.0
	if force:
		game_camera.global_position = player.global_position

func _process(delta: float) -> void:
	if game_is_over:
		return
	_follow_camera(delta)
	_clamp_player_to_arena()
	_prune_dead_enemies()
	if wave_active and active_enemies.is_empty():
		_on_wave_cleared()

func _follow_camera(delta: float) -> void:
	if game_camera == null or player == null or not is_instance_valid(player):
		return
	# 固定顶视角：相机只平滑跟随玩家，不再按房间节点突然跳。
	var target := player.global_position
	game_camera.global_position = game_camera.global_position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))

func _clamp_player_to_arena() -> void:
	if player == null or not is_instance_valid(player):
		return
	var half := arena_size * 0.5 - Vector2(32, 32)
	player.global_position.x = clamp(player.global_position.x, -half.x, half.x)
	player.global_position.y = clamp(player.global_position.y, -half.y, half.y)

func _start_next_wave() -> void:
	if game_is_over or _waiting_for_next_wave:
		return
	current_wave += 1
	wave_active = true
	wave_killed = 0
	var plan := _build_wave_plan(current_wave)
	wave_total = plan.size()
	active_enemies.clear()
	_update_ui()
	_show_message("第 %d 波" % current_wave, 0.75)
	wave_progress_changed.emit(wave_killed, wave_total, current_wave)
	for i in range(plan.size()):
		_spawn_enemy(plan[i], i)
		if i < plan.size() - 1:
			await get_tree().create_timer(0.12).timeout

func _build_wave_plan(wave: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var chaser_count := 3 + wave * 2
	var ranged_count: int = maxi(0, int(floor(float(wave - 1) / 2.0)))
	var bomber_count: int = maxi(0, int(floor(float(wave - 2) / 3.0)))
	chaser_count = min(chaser_count, 18)
	ranged_count = min(ranged_count, 6)
	bomber_count = min(bomber_count, 4)

	for i in range(chaser_count):
		plan.append({
			"enemy_type": "melee_chaser",
			"ai_type": "chase",
			"hp": 18 + wave * 4,
			"damage": 8 + int(wave * 0.8),
			"speed": 88.0 + min(wave * 4.0, 52.0),
			"xp_value": 10,
			"currency_value": 4,
			"emoji": "👾",
			"color": Color(0.95, 0.25, 0.28, 1.0),
		})
	for i in range(ranged_count):
		plan.append({
			"enemy_type": "ranged_caster",
			"ai_type": "ranged",
			"hp": 16 + wave * 3,
			"damage": 7 + int(wave * 0.7),
			"speed": 72.0 + min(wave * 2.0, 28.0),
			"shoot_interval": max(0.85, 1.85 - wave * 0.06),
			"xp_value": 18,
			"currency_value": 7,
			"emoji": "🧙",
			"color": Color(0.62, 0.35, 1.0, 1.0),
		})
	for i in range(bomber_count):
		plan.append({
			"enemy_type": "exploder",
			"ai_type": "bomber",
			"hp": 12 + wave * 2,
			"damage": 14 + wave,
			"speed": 118.0 + min(wave * 4.0, 50.0),
			"explosion_damage": 22 + wave * 2,
			"xp_value": 15,
			"currency_value": 6,
			"emoji": "💣",
			"color": Color(1.0, 0.62, 0.15, 1.0),
		})
	if wave % 4 == 0:
		plan.append({
			"enemy_type": "elite_brute",
			"ai_type": "chase",
			"hp": 90 + wave * 16,
			"damage": 16 + wave * 2,
			"speed": 78.0 + min(wave * 2.0, 38.0),
			"xp_value": 85,
			"currency_value": 24,
			"is_elite": true,
			"emoji": "👹",
			"scale": 1.35,
			"color": Color(1.0, 0.18, 0.08, 1.0),
		})
	plan.shuffle()
	return plan

func _spawn_enemy(data: Dictionary, index: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	add_child(enemy)
	enemy.global_position = _pick_spawn_position(index)
	_apply_enemy_data(enemy, data)
	active_enemies.append(enemy)
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(enemy, data))
	if enemy.has_signal("enemy_hit"):
		enemy.enemy_hit.connect(_on_enemy_hit)
	wave_progress_changed.emit(wave_killed, wave_total, current_wave)

func _apply_enemy_data(enemy: Node, data: Dictionary) -> void:
	if data.has("hp"):
		enemy.set("max_hp", int(data["hp"]))
		enemy.set("current_hp", int(data["hp"]))
	if data.has("damage"):
		enemy.set("damage", int(data["damage"]))
	if data.has("speed"):
		enemy.set("speed", float(data["speed"]))
	if data.has("ai_type"):
		enemy.set("ai_type", str(data["ai_type"]))
	# Main.tscn 的 CoreCombatMode 是直接刷怪的街机战斗循环，
	# 这里显式启用 ai_type 行为，避免所有怪都停留在警觉 AI 的 IDLE/ALERT 状态。
	if enemy.get("awareness_enabled") != null:
		enemy.set("awareness_enabled", false)
	if data.has("shoot_interval"):
		enemy.set("shoot_interval", float(data["shoot_interval"]))
	if data.has("explosion_damage"):
		enemy.set("explosion_damage", int(data["explosion_damage"]))
	if enemy.has_method("set_enemy_data"):
		enemy.call("set_enemy_data", data.duplicate(true))
	if enemy.has_method("set_visuals"):
		enemy.call("set_visuals", data.get("emoji", "👾"), data.get("color", Color(1, 0.25, 0.25, 1)), float(data.get("scale", 1.0)))

func _pick_spawn_position(index: int) -> Vector2:
	var center := player.global_position if player != null and is_instance_valid(player) else Vector2.ZERO
	var half := arena_size * 0.5 - Vector2(70, 70)
	for attempt in range(24):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector2(cos(angle), sin(angle)) * radius
		pos.x = clamp(pos.x, -half.x, half.x)
		pos.y = clamp(pos.y, -half.y, half.y)
		if pos.distance_to(center) >= 300.0:
			return pos
	# 保底：从场地边缘生成，避免刷在玩家脸上。
	var side := index % 4
	match side:
		0: return Vector2(rng.randf_range(-half.x, half.x), -half.y)
		1: return Vector2(rng.randf_range(-half.x, half.x), half.y)
		2: return Vector2(-half.x, rng.randf_range(-half.y, half.y))
		_: return Vector2(half.x, rng.randf_range(-half.y, half.y))

func _on_enemy_hit(_pos: Vector2, _damage: int, is_crit: bool) -> void:
	if screen_shake != null and screen_shake.has_method("trigger"):
		screen_shake.call("trigger", 5.0 if not is_crit else 9.0, 0.07 if not is_crit else 0.11)

func _on_enemy_died(enemy: Node, data: Dictionary) -> void:
	if active_enemies.has(enemy):
		active_enemies.erase(enemy)
	wave_killed = min(wave_total, wave_killed + 1)
	kills += 1
	score += int(data.get("xp_value", 10))
	var currency_gain := int(data.get("currency_value", 4))
	# 即时到账 + 显示魂数飘字
	GameManager.add_currency(currency_gain)
	if ui_layer != null and ui_layer.has_method("show_currency_popup"):
		ui_layer.call("show_currency_popup", currency_gain, enemy.global_position if is_instance_valid(enemy) else player.global_position)
	# 掉落魂魄（视觉表现）
	var enemy_pos: Vector2 = enemy.global_position if is_instance_valid(enemy) else player.global_position
	_spawn_soul_orb(enemy_pos, currency_gain)
	kill_recorded.emit()
	# 敌人死亡时触发额外屏幕震动（增强击杀反馈）
	if screen_shake != null and screen_shake.has_method("trigger"):
		var death_hp: int = int(data.get("hp", 30))
		var death_intensity := 5.0
		if death_hp >= 80:
			death_intensity = 13.0
		elif death_hp >= 40:
			death_intensity = 9.0
		screen_shake.call("trigger", death_intensity, 0.10)
	wave_progress_changed.emit(wave_killed, wave_total, current_wave)
	_update_ui()

func _prune_dead_enemies() -> void:
	for i in range(active_enemies.size() - 1, -1, -1):
		var e: Node = active_enemies[i]
		if e == null or not is_instance_valid(e):
			active_enemies.remove_at(i)

func _on_wave_cleared() -> void:
	if not wave_active or _waiting_for_next_wave:
		return
	wave_active = false
	_waiting_for_next_wave = true
	_show_message("第 %d 波清理完成" % current_wave, 0.85)
	room_cleared.emit({"wave": current_wave})
	if current_wave % 3 == 0 and player != null and is_instance_valid(player):
		player.heal(12)
	await get_tree().create_timer(wave_clear_delay).timeout
	_waiting_for_next_wave = false
	if not game_is_over:
		_start_next_wave()

func _on_player_hp_changed(current: int, maximum: int) -> void:
	_update_hp_bar(current, maximum)
	if current <= 0:
		_trigger_game_over("生命归零")

func _on_global_game_over() -> void:
	_trigger_game_over("生命归零")

func _trigger_game_over(reason: String) -> void:
	if game_is_over:
		return
	game_is_over = true
	wave_active = false
	if ui_layer != null:
		if ui_layer.has_method("set_death_stats"):
			ui_layer.call("set_death_stats", {"score": score, "kills": kills, "floor": max(1, current_wave)})
		if ui_layer.has_method("set_loot_info"):
			ui_layer.call("set_loot_info", 0, 0)
	game_over.emit(reason)

func _on_currency_changed(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount

func _update_hp_bar(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
	if ui_layer != null and ui_layer.has_method("update_hp"):
		ui_layer.call("update_hp", current, maximum)

func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d" % score
	if wave_label:
		wave_label.text = "Floor: 1  Wave: %d" % max(1, current_wave)
	if currency_label:
		currency_label.text = "魂: %d" % GameManager.currency
	if clearing_progress:
		clearing_progress.visible = true
		clearing_progress.max_value = max(1, wave_total)
		clearing_progress.value = wave_killed
	if room_info_label:
		room_info_label.text = "击杀 %d/%d   存活敌人 %d" % [wave_killed, max(1, wave_total), active_enemies.size()]

func _show_message(text: String, seconds: float = 1.0) -> void:
	if wave_indicator == null:
		if room_info_label:
			room_info_label.text = text
		return
	wave_indicator.visible = true
	wave_indicator.modulate.a = 1.0
	wave_indicator.text = text
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = wave_indicator.create_tween()
	_message_tween.tween_interval(seconds)
	_message_tween.tween_property(wave_indicator, "modulate:a", 0.0, 0.35)

func _spawn_soul_orb(world_pos: Vector2, amount: int) -> void:
	if amount <= 0 or not is_instance_valid(self):
		return
	var orb: SoulOrb = SOUL_ORB_SCENE.instantiate() as SoulOrb
	orb.amount = amount
	# 在尸体位置生成，略微偏移避免重叠
	orb.global_position = world_pos + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	orb.collected.connect(_on_soul_orb_collected)
	add_child(orb)

func _on_soul_orb_collected(amount: int, orb: SoulOrb) -> void:
	GameManager.add_currency(amount)

func get_inventory() -> InventoryModule:
	return inventory_module

func get_insurance() -> InsuranceModule:
	return insurance_module

func get_player() -> Player:
	return player

func get_map_manager():
	return null
