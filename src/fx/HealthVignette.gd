extends Control
class_name HealthVignette

# HealthVignette.gd — 低血量 Vignette 效果
# 挂在 GameUIManager 下，当玩家血量低于 30% 时叠加暗红色屏幕边缘渐变
# 血量越低越明显，归0时最强烈

## 血量阈值
const _WARNING_THRESHOLD: float = 0.30  # 30% 以下开始提示
const _CRITICAL_THRESHOLD: float = 0.15  # 15% 以下为危急

## 暗红色叠加层（ColorRect，带渐变）
var _vignette_color: ColorRect
var _vignette_gradient: Control  # 用 TextureRect + StyleBox 模拟边缘渐变

## 引用
var _player: Node = null
var _current_hp_ratio: float = 1.0
var _target_alpha: float = 0.0
var _current_alpha: float = 0.0
var _pulse_timer: float = 0.0
var _is_pulsing: bool = false

func _ready() -> void:
	_setup_vignette()
	# 监听玩家绑定
	if get_parent() and get_parent().has_method("set_player"):
		# GameUIManager 会在 set_player 时发送 hp_changed 信号
		# 但实际 HP 事件由 Player 直接发出，这里通过 GameUIManager 的 update_hp 感知
		pass

## 设置玩家引用（供外部调用以获取 hp 信号连接）
func set_player_ref(player: Node) -> void:
	_player = player
	if player and player.has_signal("hp_changed") and not player.hp_changed.is_connected(_on_hp_changed):
		player.hp_changed.connect(_on_hp_changed.bind())

## 监听 Player hp_changed 信号（格式：current_hp, max_hp）
func _on_hp_changed(current: int, maximum: int) -> void:
	if maximum <= 0:
		return
	_current_hp_ratio = float(current) / float(maximum)
	_update_vignette_target()

func _setup_vignette() -> void:
	# 创建暗红色叠加层（全屏，边缘渐变透明）
	_vignette_color = ColorRect.new()
	_vignette_color.name = "HealthVignetteLayer"
	_vignette_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_color.offset_left = 0
	_vignette_color.offset_top = 0
	_vignette_color.offset_right = 0
	_vignette_color.offset_bottom = 0
	_vignette_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_color.color = Color(0.8, 0.05, 0.05, 0.0)  # 深红，透明
	_vignette_color.z_index = 50  # 在普通 UI 之上
	add_child(_vignette_color)

	# 设置材质实现边缘渐变（使用 StyleBoxTexture 不依赖外部资源）
	# 用普通 ColorRect + process 动态更新透明度实现边缘视觉效果
	_vignette_color.modulate.a = 0.0

func _update_vignette_target() -> void:
	if _current_hp_ratio >= _WARNING_THRESHOLD:
		_target_alpha = 0.0
		_is_pulsing = false
	elif _current_hp_ratio >= _CRITICAL_THRESHOLD:
		# 轻度警告：0 ~ 0.35 透明度
		var ratio: float = (_WARNING_THRESHOLD - _current_hp_ratio) / _WARNING_THRESHOLD
		_target_alpha = ratio * 0.35
		_is_pulsing = false
	else:
		# 危急警告：0.35 ~ 0.6 透明度 + 脉冲
		var ratio: float = (_CRITICAL_THRESHOLD - _current_hp_ratio) / _CRITICAL_THRESHOLD
		_target_alpha = 0.35 + ratio * 0.25
		_is_pulsing = true

func _process(delta: float) -> void:
	# 透明度平滑过渡
	var speed: float = 3.0 if _is_pulsing else 2.0
	_current_alpha = lerp(_current_alpha, _target_alpha, speed * delta)

	# 危急时叠加脉冲效果（微微闪烁）
	if _is_pulsing:
		_pulse_timer += delta * 2.5
		var pulse: float = (sin(_pulse_timer * PI) * 0.5 + 0.5) * 0.15
		_current_alpha += pulse

	_current_alpha = clamp(_current_alpha, 0.0, 0.6)

	if _vignette_color:
		# 深红色调，透明度动态调整
		_vignette_color.modulate.a = _current_alpha

## 玩家死亡时隐藏
func _on_player_dead() -> void:
	_target_alpha = 0.0
	_current_alpha = 0.0
	if _vignette_color:
		_vignette_color.modulate.a = 0.0
