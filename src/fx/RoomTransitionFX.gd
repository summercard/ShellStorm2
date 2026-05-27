extends CanvasLayer
class_name RoomTransitionFX

# RoomTransitionFX — 房间切换黑幕过渡效果
# 挂载在 Main 节点下，覆盖全屏 ColorRect 执行淡入淡出
# 使用方式：调用 transition() 协程，或 connect_to_room_game_mode() 自动绑定

## 过渡参数
@export var fade_out_duration: float = 0.20   # 淡出到黑的时间（秒）
@export var fade_in_duration: float = 0.30     # 淡入（从黑恢复）的时间（秒）
@export var hold_duration: float = 0.05        # 黑屏保持时间（秒）

## 过渡是否进行中
var _is_transitioning: bool = false

## 黑幕节点
var _curtain: ColorRect = null

## Tween引用（用于中断）
var _current_tween: Tween = null

## 信号
signal transition_started
signal transition_finished


func _ready() -> void:
	_setup_curtain()


## 构建全屏黑幕 ColorRect
func _setup_curtain() -> void:
	_curtain = ColorRect.new()
	_curtain.name = "RoomTransitionCurtain"
	_curtain.anchors_preset = Control.PRESET_FULL_RECT
	_curtain.size = get_viewport().get_visible_rect().size
	_curtain.color = Color.BLACK
	_curtain.z_index = 500  # 最顶层
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.modulate.a = 0.0  # 默认透明（不遮挡）
	add_child(_curtain)


## 执行一次完整过渡（协程风格，调用方需 await）
## on_transitioning_callback: Callable，在"切换"时机调用（例如房间切换）
## 示例:
##   await room_transition.transition(do_room_switch_callback)
func transition(on_transitioning_callback: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	transition_started.emit()
	
	# 中断旧Tween
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	
	# 淡出：0 → 1（屏幕渐黑）
	_curtain.modulate.a = 0.0
	_current_tween = create_tween().set_parallel(true)
	_current_tween.tween_property(_curtain, "modulate:a", 1.0, fade_out_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_current_tween.chain().tween_interval(hold_duration)
	
	# 等待淡出完成
	await _current_tween
	
	# 执行房间切换回调（例如 RoomGameMode._enter_room_by_id 的后半段）
	if on_transitioning_callback.is_valid():
		on_transitioning_callback.call()
	
	# 淡入：1 → 0（屏幕渐亮）
	_current_tween = create_tween().set_parallel(true)
	_current_tween.tween_property(_curtain, "modulate:a", 0.0, fade_in_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_current_tween.chain().tween_callback(_on_transition_done)
	
	await _current_tween


## 立即中断过渡（恢复到完全透明）
func abort_transition() -> void:
	if not _is_transitioning:
		return
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	_curtain.modulate.a = 0.0
	_is_transitioning = false
	transition_finished.emit()


func _on_transition_done() -> void:
	_is_transitioning = false
	transition_finished.emit()


## 查询是否正在过渡
func is_transitioning() -> bool:
	return _is_transitioning


## 窗口大小变化时重设幕布尺寸
func _notification(what: int) -> void:
	if what == 43:  # NOTIFICATION_VISIBLE_RENDER_WORLD_2D
		if _curtain != null:
			_curtain.size = get_viewport().get_visible_rect().size
