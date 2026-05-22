class_name ExtractionModule
## 撤离模块 — 管理撤离读条、结算、带入带出
## 与 ExtractionDirector 配合：ExtractionDirector 管点位，ExtractionModule 管读条和结算

signal extraction_countdown_started(type: String, duration: float)
signal extraction_progress_updated(progress: float)
signal extraction_completed(success: bool, loot: Array[Dictionary])
signal extraction_aborted()
signal extraction_failed(reason: String)

enum ExtractionStatus {
	IDLE,
	COUNTDOWN,
	COMPLETED,
	FAILED
}

var _status: ExtractionStatus = ExtractionStatus.IDLE
var _current_type: String = ""
var _countdown_duration: float = 5.0
var _countdown_remaining: float = 0.0
var _countdown_timer: float = 0.0

## 撤离成功后统计
var items_extracted: int = 0
var currency_extracted: int = 0
var xp_earned: int = 0

func _init() -> void:
	pass

## 开始撤离读条
## extraction_type: 撤离方式字符串
## duration: 读条秒数（默认5秒）
func start_extraction(extraction_type: String, duration: float = 5.0) -> bool:
	if _status != ExtractionStatus.IDLE:
		return false
	
	_current_type = extraction_type
	_countdown_duration = duration
	_countdown_remaining = duration
	_countdown_timer = 0.0
	_status = ExtractionStatus.COUNTDOWN
	
	extraction_countdown_started.emit(extraction_type, duration)
	return true

## 每帧调用（process模式）
func update(delta: float) -> void:
	if _status != ExtractionStatus.COUNTDOWN:
		return
	
	_countdown_timer += delta
	_countdown_remaining = max(0.0, _countdown_duration - _countdown_timer)
	
	var progress: float = 1.0 - (_countdown_remaining / _countdown_duration)
	extraction_progress_updated.emit(progress)
	
	if _countdown_remaining <= 0.0:
		_status = ExtractionStatus.COMPLETED
		extraction_completed.emit(true, _collect_loot())

## 中断撤离读条（受到攻击或超时）
func abort_extraction() -> void:
	if _status == ExtractionStatus.COUNTDOWN:
		_status = ExtractionStatus.IDLE
		_current_type = ""
		_countdown_remaining = 0.0
		_countdown_timer = 0.0
		extraction_aborted.emit()

## 直接完成撤离（跳过读条，常用于调试）
func force_complete() -> void:
	if _status == ExtractionStatus.COUNTDOWN:
		_status = ExtractionStatus.COMPLETED
		extraction_completed.emit(true, _collect_loot())

## 获取当前状态
func get_status() -> ExtractionStatus:
	return _status

## 获取当前撤离类型
func get_extraction_type() -> String:
	return _current_type

## 获取剩余时间
func get_remaining_time() -> float:
	return _countdown_remaining

## 获取读条进度（0.0 ~ 1.0）
func get_progress() -> float:
	if _status != ExtractionStatus.COUNTDOWN:
		return 0.0 if _status == ExtractionStatus.IDLE else 1.0
	return 1.0 - (_countdown_remaining / _countdown_duration)

## 撤离成功后收集战利品
func _collect_loot() -> Array[Dictionary]:
	var loot: Array[Dictionary] = []
	# 战利品收集由外部（GameManager / RoomGameMode）处理后传入
	# 这里只记录统计元数据
	return loot

## 重置（每局开始时调用）
func reset() -> void:
	_status = ExtractionStatus.IDLE
	_current_type = ""
	_countdown_remaining = 0.0
	_countdown_timer = 0.0
	items_extracted = 0
	currency_extracted = 0
	xp_earned = 0

## 调试状态
func debug_status() -> String:
	var status_strs := {
		ExtractionStatus.IDLE: "IDLE",
		ExtractionStatus.COUNTDOWN: "COUNTDOWN",
		ExtractionStatus.COMPLETED: "COMPLETED",
		ExtractionStatus.FAILED: "FAILED"
	}
	return "ExtractionModule [%s] type=%s time=%.1f/%.1f" % [
		status_strs[_status], _current_type, _countdown_remaining, _countdown_duration
	]