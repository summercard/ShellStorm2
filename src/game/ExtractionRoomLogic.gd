class_name ExtractionRoomLogic
extends Node2D
## 撤离房逻辑 — 撤离房氛围视觉
## 撤离读条由 RoomGameMode._activate_extraction_room 触发
## 此脚本负责撤离房的视觉元素（撤离光圈动画、门标记等）

signal extraction_activated()

## 状态
var _activation_started: bool = false

## 引用
var _extraction_circle: ColorRect = null
var _exit_markers: Array[ColorRect] = []
var _pulse_timer: float = 0.0

func _ready() -> void:
	_setup_extraction_room()
	_connect_signals()

func _process(delta: float) -> void:
	# 撤离光圈脉冲动画
	if _activation_started and _extraction_circle != null:
		_pulse_timer += delta
		var pulse: float = (sin(_pulse_timer * 2.5) * 0.5 + 0.5) * 0.15 + 0.08
		_extraction_circle.color = Color(0.10, 0.35, 0.70, pulse)

func _setup_extraction_room() -> void:
	# 查找撤离光圈
	_extraction_circle = get_node_or_null("ExtractionCircle") as ColorRect
	
	# 查找方向标记
	var marker_names: Array[String] = ["ExitMarker_N", "ExitMarker_S", "ExitMarker_W", "ExitMarker_E"]
	for name in marker_names:
		var marker: ColorRect = get_node_or_null(name) as ColorRect
		if marker != null:
			_exit_markers.append(marker)

func _connect_signals() -> void:
	pass

## 开始撤离激活（由 RoomGameMode 调用）
func activate_extraction() -> void:
	if _activation_started:
		return
	_activation_started = true
	extraction_activated.emit()
	
	# 高亮撤离光圈
	if _extraction_circle != null:
		_extraction_circle.color = Color(0.10, 0.35, 0.70, 0.12)
	
	# 强化方向标记可见性
	for marker in _exit_markers:
		marker.color = Color(0.15, 0.60, 1.0, 0.85)
	
	print("[ExtractionRoomLogic] 撤离房已激活，撤离读条开始")

## 获取激活状态
func is_activated() -> bool:
	return _activation_started