extends Node2D

@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var ui: CanvasLayer = $UI

var player: Node2D

func _ready() -> void:
	_spawn_player()
	Global.start_game()
	Global.game_over.connect(_on_game_over)

func _spawn_player() -> void:
	var player_scene = preload("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)

func _on_game_over() -> void:
	if player and is_instance_valid(player):
		player.queue_free()