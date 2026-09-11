class_name VfxDamageNumber3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX02-01 / VFX-DAMAGE-NUMBER-3D 伤害数字飘字特效
## 视觉：Label3D + 黑边 + 颜色编码（红/橙/暴击金）
## 行为：lifetime 0.72s；从命中点向上飘升 +0.6m；渐显→持续→渐隐；billboarding

@export var _rise_distance: float = 0.6
@export var _label_pixel_size: float = 0.010
@export var _label_outline_size: int = 6

var _label: Label3D

func _on_activate(_world_pos: Vector3, color: Color, _size: float, context: Dictionary) -> void:
	lifetime = 0.72
	if _label == null:
		_label = Label3D.new()
		_label.name = "DamageLabel"
		_label.pixel_size = _label_pixel_size
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.outline_size = _label_outline_size
		_label.modulate = Color(1, 1, 1, 1)
		add_child(_label)
	# 解析 context.text_value
	var text_value: String = str(context.get("text_value", "0"))
	_label.text = text_value
	# 颜色：调用方传入（红/橙/暴击金）
	_label.modulate = color
	# 初始 alpha 0
	_label.modulate.a = 0.0
	# 初始位置 = world_pos（基类已设 global_position）
	# 初始缩放略小（后续放大）
	_label.scale = Vector3.ONE * 0.85

func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	# 上升：从 0 到 _rise_distance，缓动
	var rise_t: float = ease_out_quad(t)
	position.y = rise_t * _rise_distance
	# 缩放：0.85→1.0（前 15% 完成）
	_label.scale = Vector3.ONE * (0.85 + 0.15 * clamp(elapsed / 0.15, 0.0, 1.0))
	# 透明度三段：渐显（0-0.15s）→ 持续（0.15-0.50s）→ 渐隐（0.50-0.72s）
	var alpha: float
	if elapsed < 0.15:
		alpha = elapsed / 0.15
	elif elapsed < 0.50:
		alpha = 1.0
	else:
		alpha = 1.0 - (elapsed - 0.50) / 0.22
	_label.modulate.a = clamp(alpha, 0.0, 1.0)

func ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
