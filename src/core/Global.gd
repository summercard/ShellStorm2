extends Node

signal game_paused(paused: bool)
signal game_over()
signal wave_started(wave: int)

var is_paused: bool = false
var current_wave: int = 0
var player_hp: int = 100
var player_max_hp: int = 100

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()

func toggle_pause() -> void:
	is_paused = !is_paused
	get_tree().paused = is_paused
	game_paused.emit(is_paused)

func start_game() -> void:
	current_wave = 0
	player_hp = player_max_hp
	is_paused = false
	get_tree().paused = false

func trigger_game_over() -> void:
	game_over.emit()

func next_wave() -> void:
	current_wave += 1
	wave_started.emit(current_wave)