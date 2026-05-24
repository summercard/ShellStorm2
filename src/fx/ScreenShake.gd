extends Node
class_name ScreenShake

# ScreenShake.gd — 屏幕震动效果
# 通过操作 Camera2D 的 offset 实现震屏
# 挂载在 Main 或相机节点下使用

## 震动参数
@export var enabled: bool = true
@export var shake_intensity: float = 8.0   # 震动幅度（像素）
@export var shake_duration: float = 0.15    # 震动持续时间（秒）
@export var shake_frequency: float = 60.0   # 震动频率（Hz）

var _camera: Camera2D = null
var _is_shaking: bool = false
var _shake_timer: float = 0.0
var _shake_elapsed: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# 查找 Camera2D
	_camera = get_tree().root.get_node_or_null("Main/Camera2D")
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	if not _camera:
		push_warning("[ScreenShake] No Camera2D found — shake will not render")

## 主震动方法 — 从任意位置调用（被击中时）
func trigger(intensity: float = 8.0, duration: float = 0.15) -> void:
	if not enabled:
		return
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	shake_intensity = intensity
	shake_duration = duration
	_is_shaking = true
	_shake_timer = duration
	_shake_elapsed = 0.0

## 屏幕闪白 — Boss死亡/重大事件时全屏短暂白闪
## hex_color: 闪白颜色（默认白色）；duration: 持续时间（秒）
func screen_flash(hex_color: Color = Color(1.0, 1.0, 1.0, 0.7), duration: float = 0.12) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	if not _camera:
		return
	
	# 创建临时白闪覆盖层（置于相机子节点）
	var flash := ColorRect.new()
	flash.name = "ScreenFlash"
	flash.custom_minimum_size = Vector2(9999, 9999)
	flash.size = Vector2(9999, 9999)
	flash.color = hex_color
	flash.z_index = 9999
	flash.modulate.a = 0.0
	_camera.add_child(flash)
	
	# 白闪动画：快速亮起 → 快速淡出
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", hex_color.a, duration * 0.3)
	await tween.finished
	tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, duration * 0.7)
	await tween.finished
	flash.queue_free()

## Boss死亡专用的强烈震屏（全屏震动 + 震幅衰减）
func screen_shake_death() -> void:
	if not enabled:
		return
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	# 强烈震屏：高频 + 快速衰减
	var intensity := 20.0
	var duration := 0.6
	shake_intensity = intensity
	shake_duration = duration
	shake_frequency = 45.0
	_is_shaking = true
	_shake_timer = duration
	_shake_elapsed = 0.0

## 内部震动更新
func _process(delta: float) -> void:
	if not _is_shaking:
		return

	_shake_timer -= delta
	_shake_elapsed += delta

	if _shake_timer <= 0:
		_is_shaking = false
		_shake_offset = Vector2.ZERO
		_apply_offset(Vector2.ZERO)
		return

	# 按正弦波衰减震动
	var progress := _shake_timer / shake_duration  # 1→0
	var current_intensity := shake_intensity * progress
	var angle := _shake_elapsed * shake_frequency * 2.0 * PI
	var offset := Vector2(
		cos(angle) * current_intensity,
		sin(angle) * current_intensity
	)
	_apply_offset(offset)

func _apply_offset(offset: Vector2) -> void:
	if _camera:
		_camera.offset = offset