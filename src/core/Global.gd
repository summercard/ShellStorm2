extends Node

signal game_paused(paused: bool)
signal game_over()
signal wave_started(wave: int)

var is_paused: bool = false
var current_wave: int = 0
var player_hp: int = 100
var player_max_hp: int = 100

## HitStop — 命中停顿（2-4帧短停顿，增强打击感）
## 正常游戏运行在 time_scale=1.0，命中时短暂降至0（几帧后恢复）
var hitstop_timer: float = 0.0
const HITSTOP_NORMAL: float = 1.0
## hitstop_duration: 普通命中停帧（约3帧@60fps）
## hitstop_crit_duration: 暴击停帧（约5帧@60fps）
const HITSTOP_DURATION: float = 0.050
const HITSTOP_CRIT_DURATION: float = 0.083

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	## HitStop：几帧停顿后自动恢复，不阻塞游戏逻辑
	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		if hitstop_timer <= 0.0:
			Engine.time_scale = HITSTOP_NORMAL

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

## 触发命中停顿（暴击时更久），自动恢复
func trigger_hitstop(is_crit: bool = false) -> void:
	if is_paused:
		return
	var dur := HITSTOP_CRIT_DURATION if is_crit else HITSTOP_DURATION
	if hitstop_timer < dur:
		hitstop_timer = dur
		Engine.time_scale = 0.0