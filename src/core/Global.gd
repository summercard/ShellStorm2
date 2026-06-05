extends Node

signal game_paused(paused: bool)
signal game_over()
signal wave_started(wave: int)

var is_paused: bool = false
var _pause_reasons: Dictionary = {}
var current_wave: int = 0
var player_hp: int = 100
var player_max_hp: int = 100

## HitStop — 命中停顿（2-4帧短停顿，增强打击感）
## 正常游戏运行在 time_scale=1.0，命中时短暂降至0（几帧后恢复）
var hitstop_timer: float = 0.0
var _hitstop_until_msec: int = 0
const HITSTOP_NORMAL: float = 1.0
## hitstop_duration: 普通命中停帧（约3帧@60fps）
## hitstop_crit_duration: 暴击停帧（约5帧@60fps）
const HITSTOP_DURATION: float = 0.050
const HITSTOP_CRIT_DURATION: float = 0.083

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	## HitStop：几帧停顿后自动恢复，不阻塞游戏逻辑
	if hitstop_timer > 0.0 and Time.get_ticks_msec() >= _hitstop_until_msec:
		hitstop_timer = 0.0
		_hitstop_until_msec = 0
		Engine.time_scale = HITSTOP_NORMAL

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not _pause_reasons.is_empty() and not has_pause_reason("manual"):
			return
		toggle_pause()

func toggle_pause() -> void:
	if has_pause_reason("manual"):
		release_pause("manual")
	else:
		acquire_pause("manual")

func acquire_pause(reason: String) -> void:
	if reason.is_empty():
		return
	_pause_reasons[reason] = true
	_sync_pause_state()

func release_pause(reason: String) -> void:
	if reason.is_empty():
		return
	_pause_reasons.erase(reason)
	_sync_pause_state()

func clear_pause_reasons() -> void:
	_pause_reasons.clear()
	_sync_pause_state()

func has_pause_reason(reason: String) -> bool:
	return _pause_reasons.has(reason)

func _sync_pause_state() -> void:
	var should_pause := not _pause_reasons.is_empty()
	var changed := is_paused != should_pause
	is_paused = should_pause
	get_tree().paused = should_pause
	if changed:
		game_paused.emit(should_pause)

func start_game() -> void:
	current_wave = 0
	player_hp = player_max_hp
	hitstop_timer = 0.0
	_hitstop_until_msec = 0
	Engine.time_scale = HITSTOP_NORMAL
	clear_pause_reasons()

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
		_hitstop_until_msec = maxi(_hitstop_until_msec, Time.get_ticks_msec() + ceili(dur * 1000.0))
		Engine.time_scale = 0.0
