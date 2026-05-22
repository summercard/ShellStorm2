extends Node2D

# Main - 游戏主场景
# 管理玩家生成、敌人生成、UI 等

@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var ui: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar

var player: Node2D

func _ready() -> void:
	_spawn_player()
	Global.start_game()
	Global.game_over.connect(_on_game_over)
	GameManager.hp_changed.connect(_on_hp_changed)

	# 初始化HP条
	var max_hp = GameManager.max_hp
	hp_bar.max_value = max_hp
	hp_bar.value = GameManager.current_hp

func _spawn_player() -> void:
	var player_scene = preload("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)

func _on_hp_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current

func _on_game_over() -> void:
	if player and is_instance_valid(player):
		player.queue_free()