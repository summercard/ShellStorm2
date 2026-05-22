extends Node2D

# Main - 游戏主场景
# 管理玩家生成、敌人生成、UI 等

@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var ui: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var score_label: Label = $UI/TopRightPanel/VBox/ScoreLabel
@onready var wave_label: Label = $UI/TopRightPanel/VBox/WaveLabel
@onready var currency_label: Label = $UI/CurrencyLabel

# 命运卡片选择 UI（由 T03 添加）
@onready var fate_card_ui: Control = $FateCardUIController

var player: Node2D
var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
var spawn_timer: float = 0.0
var spawn_interval: float = 2.0
var score: int = 0
var wave: int = 1

func _ready() -> void:
	_spawn_player()
	Global.start_game()
	Global.game_over.connect(_on_game_over)
	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.currency_changed.connect(_on_currency_changed)

	hp_bar.max_value = GameManager.max_hp
	hp_bar.value = GameManager.current_hp
	_update_ui()

	# Phase 4 T03: 玩家生成后显示命运卡片选择界面
	# 延迟一帧确保 Player 节点完全初始化
	await get_tree().process_frame
	_show_initial_card_selection()

func _process(delta: float) -> void:
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_enemies()
		if randf() < 0.1:  # 10% chance each spawn to increase difficulty
			spawn_interval = max(0.5, spawn_interval - 0.05)

func _spawn_player() -> void:
	var player_scene = preload("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)

## Phase 4 T03: 初始命运卡片选择
func _show_initial_card_selection() -> void:
	# 等待 FateCardGameBridge 连接到玩家 weapon_tree
	await get_tree().create_timer(0.2).timeout
	
	if fate_card_ui and fate_card_ui.has_method("show_card_selection"):
		fate_card_ui.show_card_selection()

func _spawn_enemies() -> void:
	var count = randi() % 3 + 1
	var vp = get_viewport_rect()

	for i in range(count):
		var enemy = enemy_scene.instantiate()
		enemy.enemy_died.connect(_on_enemy_died)
		var side = randi() % 4
		match side:
			0: enemy.global_position = Vector2(randf_range(0, vp.size.x), -30)
			1: enemy.global_position = Vector2(randf_range(0, vp.size.x), vp.size.y + 30)
			2: enemy.global_position = Vector2(-30, randf_range(0, vp.size.y))
			3: enemy.global_position = Vector2(vp.size.x + 30, randf_range(0, vp.size.y))
		add_child(enemy)

func _on_enemy_died() -> void:
	score += 10
	GameManager.add_currency(10)
	_update_ui()

func _on_hp_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current

func _on_currency_changed(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount

func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d" % score
	if wave_label:
		wave_label.text = "Wave: %d" % wave

func _on_game_over() -> void:
	if player and is_instance_valid(player):
		player.queue_free()