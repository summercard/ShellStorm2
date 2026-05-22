extends Node2D

# Main.gd — 游戏主场景（已整合地图系统）
# 使用 RoomGameMode 替代原来的占位敌人生成逻辑
# 管理玩家生成、地图系统启动、UI 等

@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var ui: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var score_label: Label = $UI/TopRightPanel/VBox/ScoreLabel
@onready var wave_label: Label = $UI/TopRightPanel/VBox/WaveLabel
@onready var currency_label: Label = $UI/CurrencyLabel

# 命运卡片选择 UI（Phase 4 T03）
@onready var fate_card_ui: Control = $FateCardUIController

var room_game_mode: Node2D
var player: Node2D

func _ready() -> void:
	# 初始化游戏管理器
	Global.start_game()
	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.currency_changed.connect(_on_currency_changed)
	
	# 生成玩家
	_spawn_player()
	
	# 初始化房间游戏模式
	_setup_room_game_mode()
	
	# 设置基础 UI
	hp_bar.max_value = GameManager.max_hp
	hp_bar.value = GameManager.current_hp
	_update_ui()

func _spawn_player() -> void:
	var player_scene = preload("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)

func _setup_room_game_mode() -> void:
	# RoomGameMode 整合了 MapManager + 房间切换 + 清理逻辑
	room_game_mode = RoomGameMode.new()
	room_game_mode.initial_floor = 1
	room_game_mode.map_seed = -1  # 随机种子
	add_child(room_game_mode)
	
	# 连接 RoomGameMode 信号
	room_game_mode.room_cleared.connect(_on_room_cleared)
	room_game_mode.game_over.connect(_on_game_over)
	room_game_mode.extraction_ready.connect(_on_extraction_ready)

## 房间清理完成回调
func _on_room_cleared(room_data: RoomData) -> void:
	score += _calculate_room_score(room_data)
	_update_ui()

## 计算房间清理得分
func _calculate_room_score(room_data: RoomData) -> int:
	match room_data.room_type:
		RoomData.RoomType.COMBAT: return 10 + room_data.floor * 5
		RoomData.RoomType.ELITE: return 50 + room_data.floor * 20
		RoomData.RoomType.BOSS: return 200 + room_data.floor * 50
		RoomData.RoomType.SCAVENGE: return 20 + room_data.floor * 10
		_: return 5

## 提取就绪（所有房间清理完）
func _on_extraction_ready() -> void:
	print("地图清理完成！可以撤离或前往下一层。")

func _process(delta: float) -> void:
	pass

func _on_hp_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current

func _on_currency_changed(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount

func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d" % score
	if wave_label and room_game_mode:
		wave_label.text = "Floor: %d" % room_game_mode.current_floor

func _on_game_over(reason: String) -> void:
	print("游戏结束: %s" % reason)
	if player and is_instance_valid(player):
		player.queue_free()