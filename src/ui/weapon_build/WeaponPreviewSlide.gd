extends RefCounted

## 进度是画幅的倍数，不是正在变化的坐标。宿主负责用当前布局尺寸合成位移。
const LEG_DURATION := 0.18
var offset := 0.0
var requested_slot := -1
var _host: Control
var _apply_offset: Callable
var _show_slot: Callable
var _tween: Tween

func _init(host: Control, apply_offset: Callable, show_slot: Callable) -> void:
	_host = host
	_apply_offset = apply_offset
	_show_slot = show_slot

func request(slot: int, shown_slot: int, direction: int) -> void:
	_stop()
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		if slot != shown_slot:
			_show_slot.call(slot)
		_settle()
		return
	requested_slot = slot
	if slot == shown_slot:
		# 退场中反向选择当前页，直接回原点，不换内容、不从另一边重进。
		_enter()
		return
	_tween = _host.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var edge := 1.0 if direction > 0 else -1.0
	var duration := LEG_DURATION * maxf(0.15, absf(-edge - offset))
	_tween.tween_method(_set_offset, offset, -edge, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_swap.bind(slot, edge))

func reset() -> void:
	_stop()
	_settle()

func _stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _set_offset(value: float) -> void:
	offset = value
	_apply_offset.call()

func _swap(slot: int, edge: float) -> void:
	# 两边都在视口外时才替换 Board 内容。节点与焦点路径不另建副本。
	_set_offset(edge)
	_show_slot.call(slot)
	_enter()

func _enter() -> void:
	if is_zero_approx(offset):
		_settle()
		return
	_tween = _host.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_offset, offset, 0.0, LEG_DURATION * absf(offset)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_settle)

func _settle() -> void:
	requested_slot = -1
	_set_offset(0.0)
