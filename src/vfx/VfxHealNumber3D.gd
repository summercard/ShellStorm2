class_name VfxHealNumber3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX02-02 / VFX-HEAL-NUMBER-3D 治疗数字飘字特效
## 视觉：Label3D + 绿色调 + 白色描边；调用方提供 context.text_value（数字）
## 行为：lifetime 0.72s；从治疗点向上飘升 +0.5m；渐显→持续→渐隐；billboarding

@export var _rise_distance: float = 0.5
@export var _label_pixel_size: float = 0.010
@export var _label_outline_size: int = 6

var _label: Label3D

func _on_activate(_world_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = 0.72
	if _label == null:
		_label = Label3D.new()
		_label.name = "HealLabel"
		_label.pixel_size = _label_pixel_size
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.outline_size = _label_outline_size
		_label.modulate = Color(1, 1, 1, 1)
		add_child(_label)
	var text_value: String = str(context.get("text_value", "+0"))
	_label.text = text_value
	# 治疗色（不依赖调用方颜色，独立绿调 + 白描边）
	_label.modulate = Color(0.4, 1.0, 0.55, 1.0)
	_label.modulate.a = 0.0
	_label.scale = Vector3.ONE * 0.85

func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clamp(elapsed / total, 0.0, 1.0)
	var rise_t: float = 1.0 - (1.0 - t) * (1.0 - t)
	position.y = rise_t * _rise_distance
	_label.scale = Vector3.ONE * (0.85 + 0.15 * clamp(elapsed / 0.15, 0.0, 1.0))
	var alpha: float
	if elapsed < 0.15:
		alpha = elapsed / 0.15
	elif elapsed < 0.50:
		alpha = 1.0
	else:
		alpha = 1.0 - (elapsed - 0.50) / 0.22
	_label.modulate.a = clamp(alpha, 0.0, 1.0)
