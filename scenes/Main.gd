## Main.gd — 游戏主入口场景
## 只负责：生成玩家、初始化GameUIManager、连接GameManager信号
## 所有UI逻辑委托给 GameUIManager

extends Node2D

var player: Node2D
var ui_manager: CanvasLayer

func _ready() -> void:
	Global.start_game()

	# 实例化 GameUIManager（独立UI系统）
	var ui_scene := preload("res://scenes/GameUIManager.tscn")
	ui_manager = ui_scene.instantiate()
	add_child(ui_manager)

	# 连接 GameManager 信号
	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.currency_changed.connect(_on_currency_changed)

	# 生成玩家
	_spawn_player()

	# 通知 UI 初始化状态
	_on_hp_changed(GameManager.current_hp, GameManager.max_hp)
	_on_currency_changed(GameManager.currency)

func _spawn_player() -> void:
	var player_scene := preload("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	var spawn_marker: Marker2D = get_node_or_null("PlayerSpawn")
	if spawn_marker:
		player.global_position = spawn_marker.global_position
	else:
		player.global_position = Vector2(640, 360)
	add_child(player)

func _on_hp_changed(current: int, maximum: int) -> void:
	if ui_manager and ui_manager.has_method("update_hp"):
		ui_manager.update_hp(current, maximum)

func _on_currency_changed(amount: int) -> void:
	if ui_manager and ui_manager.has_method("update_currency"):
		ui_manager.update_currency(amount)

func _process(_delta: float) -> void:
	pass