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
var run_risk: int = 0
var extracted: bool = false
var _reward_multiplier: float = 1.0
var _pending_post_wave_extraction: bool = false
var _base_manager: Node = null

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
	extracted = false
	run_risk = 0
	_reward_multiplier = 1.0
	_pending_post_wave_extraction = false
	_waiting_for_next_wave = false
	active_enemies.clear()
	inventory_module = InventoryModule.new(12)
	insurance_module = InsuranceModule.new(2)
	_base_manager = get_node_or_null("/root/BaseManager")
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
		_connect_ui_choice_signal("fate_choice_selected", "_on_fate_choice_selected")
		_connect_ui_choice_signal("extraction_choice_selected", "_on_extraction_choice_selected")
	# crit_on_kill 命运卡片：每次击杀后通知武器树增加暴击堆栈
	if kill_recorded.is_connected(_on_kill_for_crit_on_kill) == false:
		kill_recorded.connect(_on_kill_for_crit_on_kill)
	# 订阅 crit_stacks_changed 信号，暴击堆栈变化时更新 HUD
	if player != null:
		var wt: Node = player.get_weapon_tree()
		if wt != null and wt.has_signal("crit_stacks_changed"):
			if not wt.crit_stacks_changed.is_connected(_on_crit_stacks_changed):
				wt.crit_stacks_changed.connect(_on_crit_stacks_changed)
	if clearing_progress:
		clearing_progress.visible = true
	if wave_indicator:
		wave_indicator.visible = true
		wave_indicator.text = ""
	_update_hp_bar(player.current_hp, player.max_hp)

func _connect_ui_choice_signal(signal_name: StringName, method_name: StringName) -> void:
	if ui_layer == null or not ui_layer.has_signal(signal_name):
		return
	var callable := Callable(self, method_name)
	if not ui_layer.is_connected(signal_name, callable):
		ui_layer.connect(signal_name, callable)

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
	var pressure_hp := 1.0 + float(run_risk) * 0.12
	var pressure_damage := 1.0 + float(run_risk) * 0.08
	if data.has("hp"):
		var scaled_hp := maxi(1, int(round(float(data["hp"]) * pressure_hp)))
		enemy.set("max_hp", scaled_hp)
		enemy.set("current_hp", scaled_hp)
	if data.has("damage"):
		enemy.set("damage", maxi(1, int(round(float(data["damage"]) * pressure_damage))))
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
	var currency_gain := maxi(1, int(round(float(data.get("currency_value", 4)) * _reward_multiplier)))
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
	if not game_is_over:
		_run_post_wave_sequence()

func _run_post_wave_sequence() -> void:
	if game_is_over:
		return
	_pending_post_wave_extraction = _should_offer_extraction()
	if current_wave % 2 == 0:
		_present_fate_choice()
	elif _pending_post_wave_extraction:
		_present_extraction_choice()
	else:
		_continue_run()

func _should_offer_extraction() -> bool:
	return current_wave >= 3 and current_wave % 3 == 0

func _present_fate_choice() -> void:
	var choices := _build_fate_choices()
	if ui_layer != null and ui_layer.has_method("show_run_choice_panel"):
		ui_layer.call(
			"show_run_choice_panel",
			"fate",
			"命运介入",
			"选择一张阶段强化。越晚撤离，收益越高，战局压力也会增长。",
			choices
		)
		_show_message("选择命运卡牌", 1.2)
	else:
		_on_fate_choice_selected(str(choices[0].get("id", "piercing_oath")))

func _build_fate_choices() -> Array[Dictionary]:
	var pool: Array[Dictionary] = [
		{
			"id": "piercing_oath",
			"title": "穿甲誓约",
			"tag": "火力",
			"body": "子弹伤害提升，适合稳扎稳打清怪。"
		},
		{
			"id": "rapid_pulse",
			"title": "急速脉冲",
			"tag": "手感",
			"body": "射速提升，换弹略微加快。"
		},
		{
			"id": "split_chamber",
			"title": "分裂枪膛",
			"tag": "弹幕",
			"body": "每次射击增加投射物，但扩散也会上升。"
		},
		{
			"id": "field_mending",
			"title": "战地缝合",
			"tag": "续航",
			"body": "提升生命上限并立即回复生命。"
		},
		{
			"id": "blood_pact",
			"title": "血契赏金",
			"tag": "风险",
			"body": "立刻获得魂并提升伤害，但之后敌人更危险。"
		},
	]
	pool.shuffle()
	return pool.slice(0, 3)

func _on_fate_choice_selected(choice_id: String) -> void:
	_apply_fate_choice(choice_id)
	if _pending_post_wave_extraction:
		_pending_post_wave_extraction = false
		_present_extraction_choice()
	else:
		_continue_run("命运已生效")

func _apply_fate_choice(choice_id: String) -> void:
	var wt = _get_weapon_tree()
	var message := "命运已生效"
	match choice_id:
		"piercing_oath":
			if wt != null:
				wt.bullet_damage += 2 + int(current_wave / 3)
				message = "穿甲誓约：子弹伤害提升"
		"rapid_pulse":
			if wt != null:
				wt.fire_rate = min(wt.fire_rate * 1.16, 14.0)
				wt.reload_time = max(wt.reload_time * 0.92, 0.55)
				message = "急速脉冲：射速提升"
		"split_chamber":
			if wt != null:
				wt.projectile_count = mini(wt.projectile_count + 1, 5)
				wt.spread = min(wt.spread + 0.16, 0.72)
				message = "分裂枪膛：弹幕扩展"
		"field_mending":
			if player != null and is_instance_valid(player):
				player.max_hp += 15
				player.heal(30)
				message = "战地缝合：生命上限提升"
		"blood_pact":
			run_risk += 1
			_reward_multiplier += 0.18
			GameManager.add_currency(30 + current_wave * 8)
			if wt != null:
				wt.bullet_damage += 4
			message = "血契赏金：魂到账，风险上升"
	if wt != null:
		wt.ammo_changed.emit(wt.current_ammo, wt.magazine_size)
		wt.stats_changed.emit(wt.get_computed_stats())
	if ui_layer != null and ui_layer.has_method("show_fate_card_notification"):
		ui_layer.call("show_fate_card_notification", message)
	_update_ui()

func _present_extraction_choice() -> void:
	var choices: Array[Dictionary] = [
		{
			"id": "extract",
			"title": "立刻撤离",
			"tag": "保存",
			"body": "保存当前魂与战利品，结束本局。"
		},
		{
			"id": "continue",
			"title": "继续深入",
			"tag": "贪婪",
			"body": "下一段敌人更强，魂收益提高。"
		},
		{
			"id": "recover",
			"title": "整备后深入",
			"tag": "稳健",
			"body": "回复生命再进入下一波，但收益加成较低。"
		},
	]
	if ui_layer != null and ui_layer.has_method("show_run_choice_panel"):
		ui_layer.call(
			"show_run_choice_panel",
			"extraction",
			"撤离窗口",
			"搜打撤的核心选择：带着收益离开，或押上更高风险继续推进。",
			choices
		)
		_show_message("选择撤离或深入", 1.2)
	else:
		_on_extraction_choice_selected("continue")

func _on_extraction_choice_selected(choice_id: String) -> void:
	match choice_id:
		"extract":
			_complete_extraction()
		"recover":
			if player != null and is_instance_valid(player):
				player.heal(20)
			run_risk += 1
			_reward_multiplier += 0.14
			_continue_run("整备完成：继续深入")
		_:
			run_risk += 1
			_reward_multiplier += 0.25
			_continue_run("继续深入：收益与风险上升")

func _continue_run(message: String = "") -> void:
	if game_is_over:
		return
	_waiting_for_next_wave = false
	if message != "":
		_show_message(message, 0.9)
	_start_next_wave()

func begin_extraction(_etype: String = "STANDARD", countdown: float = 1.8) -> bool:
	if game_is_over:
		return false
	_waiting_for_next_wave = true
	wave_active = false
	_show_message("撤离读条中...", countdown)
	_run_extraction_countdown(countdown)
	return true

func _run_extraction_countdown(countdown: float) -> void:
	await get_tree().create_timer(maxf(0.2, countdown)).timeout
	if not game_is_over:
		_complete_extraction()

func _complete_extraction() -> void:
	if game_is_over:
		return
	extracted = true
	game_is_over = true
	wave_active = false
	_waiting_for_next_wave = true
	# 计算撤离收益（魂币 → extraction_points）
	var extracted_count := 0
	if inventory_module != null:
		extracted_count = inventory_module.get_used_slots()
	var currency := GameManager.currency
	if _base_manager != null and _base_manager.has_method("add_extraction_points"):
		var points := currency / 2
		_base_manager.call("add_extraction_points", points)
		print("[CoreCombatMode] 撤离成功：魂=%d → extraction_points=%d，保险格=%d 件" % [currency, points, insurance_module.get_used_slots() if insurance_module else 0])
	if ui_layer != null:
		if ui_layer.has_method("set_death_stats"):
			ui_layer.call("set_death_stats", {"score": score, "kills": kills, "floor": max(1, current_wave)})
		if ui_layer.has_method("set_loot_info"):
			ui_layer.call("set_loot_info", 0, 0)
		if ui_layer.has_method("show_run_extraction_success"):
			ui_layer.call("show_run_extraction_success", {
				"score": score,
				"kills": kills,
				"wave": current_wave,
				"currency": GameManager.currency,
				"risk": run_risk,
			})
		elif ui_layer.has_method("_show_extraction_success"):
			ui_layer.call("_show_extraction_success")

func _get_weapon_tree():
	if player != null and is_instance_valid(player) and player.has_method("get_weapon_tree"):
		return player.get_weapon_tree()
	return null

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
	if inventory_module != null and insurance_module != null:
		var death_mod := DeathSettlementModule.new()
		var result: Dictionary = death_mod.process_death_settlement(inventory_module, insurance_module)
		print("[CoreCombatMode] 死亡结算：掉落 %d 件，保险保住 %d 件" % [result.get("total_lost", 0), result.get("insurance_saved", []).size()])
	if ui_layer != null:
		if ui_layer.has_method("set_death_stats"):
			ui_layer.call("set_death_stats", {"score": score, "kills": kills, "floor": max(1, current_wave)})
		if ui_layer.has_method("set_loot_info"):
			ui_layer.call("set_loot_info", 0, 0)
	game_over.emit(reason)

func _on_currency_changed(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount


## crit_on_kill 命运卡片：每次击杀后通知武器树增加暴击堆栈
func _on_kill_for_crit_on_kill() -> void:
	if player != null:
		var wt: Node = player.get_weapon_tree()
		if wt != null and wt.has_method("add_crit_on_kill_stack"):
			wt.call("add_crit_on_kill_stack", 1)

## crit_stacks_changed 信号处理：更新 HUD 暴击计数显示
func _on_crit_stacks_changed(new_count: int) -> void:
	if ui_layer != null and ui_layer.has_method("update_crit_stacks"):
		ui_layer.call("update_crit_stacks", new_count)

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
	if ui_layer != null and ui_layer.has_method("show_currency_popup"):
		var pos := orb.global_position if orb != null and is_instance_valid(orb) else player.global_position
		ui_layer.call("show_currency_popup", amount, pos)

func get_inventory() -> InventoryModule:
	return inventory_module

func get_insurance() -> InsuranceModule:
	return insurance_module

func get_player() -> Player:
	return player

func get_map_manager():
	return null
