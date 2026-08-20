extends Node
## 全局权威时间源：20 个真实分钟推进一个完整游戏日。
## 场景只订阅快照，不自行累计小时；日期、太阳、基地能源都由同一累计值派生。

signal time_advanced(delta_game_seconds: float, snapshot: Dictionary)
signal minute_changed(snapshot: Dictionary)
signal day_changed(snapshot: Dictionary)
signal solar_state_changed(snapshot: Dictionary)
signal cycle_extension_tick(delta_game_seconds: float, snapshot: Dictionary)

const Domain = preload("res://src/core/WorldTimeDomain.gd")
const PROFILE_FLUSH_INTERVAL_REAL_SECONDS := 10.0

@export var clock_running := true
@export var advance_while_tree_paused := false

var _elapsed_game_seconds := 0.0
var _profile_flush_elapsed := 0.0
var _last_minute_key := -1
var _last_day_index := -1
var _cycle_extensions: Array[Callable] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if BaseManager != null:
		_elapsed_game_seconds = BaseManager.get_world_time_elapsed_game_seconds()
	var snapshot := get_time_snapshot()
	_last_minute_key = int(snapshot.get("minute_key", -1))
	_last_day_index = int(snapshot.get("day_index", -1))
	call_deferred("_emit_full_state")


func _process(delta: float) -> void:
	if not clock_running or (get_tree().paused and not advance_while_tree_paused):
		return
	advance_game_seconds(Domain.elapsed_from_real_seconds(delta), false)
	_profile_flush_elapsed += delta
	if _profile_flush_elapsed >= PROFILE_FLUSH_INTERVAL_REAL_SECONDS:
		flush_to_profile("world_time_interval")


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		flush_to_profile("world_time_application_boundary")


func set_clock_running(running: bool) -> void:
	clock_running = running


func advance_real_seconds(real_seconds: float, persist := false) -> Dictionary:
	return advance_game_seconds(Domain.elapsed_from_real_seconds(real_seconds), persist)


func advance_game_seconds(game_seconds: float, persist := false) -> Dictionary:
	var delta_seconds := maxf(0.0, game_seconds)
	if delta_seconds <= 0.0:
		return get_time_snapshot()
	_elapsed_game_seconds += delta_seconds
	if BaseManager != null:
		BaseManager.set_world_time_elapsed_game_seconds(_elapsed_game_seconds, false)
	var snapshot := get_time_snapshot()
	time_advanced.emit(delta_seconds, snapshot)
	cycle_extension_tick.emit(delta_seconds, snapshot)
	_tick_registered_extensions(delta_seconds, snapshot)
	var minute_key := int(snapshot.get("minute_key", -1))
	if minute_key != _last_minute_key:
		_last_minute_key = minute_key
		minute_changed.emit(snapshot)
	var day_index := int(snapshot.get("day_index", -1))
	if day_index != _last_day_index:
		_last_day_index = day_index
		day_changed.emit(snapshot)
	solar_state_changed.emit((snapshot.get("solar", {}) as Dictionary).duplicate(true))
	if persist:
		flush_to_profile("world_time_explicit_advance")
	return snapshot


func set_elapsed_game_seconds(value: float, persist := false) -> Dictionary:
	_elapsed_game_seconds = maxf(0.0, value)
	if BaseManager != null:
		BaseManager.set_world_time_elapsed_game_seconds(_elapsed_game_seconds, false)
	_emit_full_state()
	if persist:
		flush_to_profile("world_time_set")
	return get_time_snapshot()


func get_elapsed_game_seconds() -> float:
	return _elapsed_game_seconds


func get_time_snapshot() -> Dictionary:
	return Domain.get_snapshot(_elapsed_game_seconds)


func get_solar_snapshot() -> Dictionary:
	return (get_time_snapshot().get("solar", {}) as Dictionary).duplicate(true)


func get_persistence_snapshot() -> Dictionary:
	return {
		"elapsed_game_seconds": _elapsed_game_seconds,
		"clock_running": clock_running,
		"real_seconds_per_game_day": Domain.REAL_SECONDS_PER_GAME_DAY,
	}


func restore_from_persistence(snapshot: Dictionary, persist := false) -> Dictionary:
	clock_running = bool(snapshot.get("clock_running", clock_running))
	return set_elapsed_game_seconds(
		float(snapshot.get("elapsed_game_seconds", _elapsed_game_seconds)), persist
	)


func flush_to_profile(reason := "world_time_flush") -> bool:
	_profile_flush_elapsed = 0.0
	if BaseManager == null:
		return false
	BaseManager.set_world_time_elapsed_game_seconds(_elapsed_game_seconds, false)
	BaseManager.sync_base_energy_to_game_time(_elapsed_game_seconds, false)
	return BaseManager.save_base(reason)


## 扩展点用于天气、作物、设施产出等未来周期模块。Callable 必须接收
## (delta_game_seconds, time_snapshot)，注销后不会再持有对象。
func register_cycle_extension(callback: Callable) -> bool:
	if not callback.is_valid() or callback in _cycle_extensions:
		return false
	_cycle_extensions.append(callback)
	return true


func unregister_cycle_extension(callback: Callable) -> void:
	_cycle_extensions.erase(callback)


func _tick_registered_extensions(delta_game_seconds: float, snapshot: Dictionary) -> void:
	for index in range(_cycle_extensions.size() - 1, -1, -1):
		var callback := _cycle_extensions[index]
		if not callback.is_valid():
			_cycle_extensions.remove_at(index)
			continue
		callback.call(delta_game_seconds, snapshot)


func _emit_full_state() -> void:
	var snapshot := get_time_snapshot()
	_last_minute_key = int(snapshot.get("minute_key", -1))
	_last_day_index = int(snapshot.get("day_index", -1))
	minute_changed.emit(snapshot)
	day_changed.emit(snapshot)
	solar_state_changed.emit((snapshot.get("solar", {}) as Dictionary).duplicate(true))
