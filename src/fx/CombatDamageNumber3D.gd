class_name CombatDamageNumber3D
extends Node3D
## 3D 战斗飘字：沿用 HUD 的冷青描边与暖色伤害语义，始终朝向镜头并短促弹出。

const NORMAL_COLOR := Color(1.0, 0.30, 0.26, 1.0)
const HEAVY_COLOR := Color(1.0, 0.53, 0.16, 1.0)
const CRITICAL_COLOR := Color(1.0, 0.88, 0.24, 1.0)
const OUTLINE_COLOR := Color(0.015, 0.055, 0.085, 0.96)
const TECH_FONT_FAMILIES := ["SF Mono", "Menlo", "monospace"]
const NORMAL_FONT_SIZE := 102
const HEAVY_FONT_SIZE := 114
const CRITICAL_FONT_SIZE := 129

var _label: Label3D


func configure(amount: int, critical := false) -> void:
	if _label != null:
		return
	_label = Label3D.new()
	_label.name = "DamageText"
	_label.text = ("✦ " if critical else "") + str(maxi(1, amount))
	# 等宽粗体数字让读数更像战术终端；按上一版的 1.5 倍放大，同时保持高分辨率字形。
	_label.font = _make_tech_font()
	# 固定屏幕尺寸会把低分辨率的 Label3D 字图强制拉大，导致马赛克；改用
	# 更高字形分辨率和较小世界像素比，让文字随镜头自然缩放且保持清晰。
	_label.font_size = CRITICAL_FONT_SIZE if critical else HEAVY_FONT_SIZE if amount >= 40 else NORMAL_FONT_SIZE
	_label.outline_size = 20 if critical else 15
	_label.modulate = _color_for(amount, critical)
	_label.outline_modulate = OUTLINE_COLOR
	_label.pixel_size = 0.0036
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_start_animation(amount, critical)


func _make_tech_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(TECH_FONT_FAMILIES)
	font.font_weight = 700
	font.multichannel_signed_distance_field = true
	font.msdf_size = 96
	return font


func _color_for(amount: int, critical: bool) -> Color:
	if critical:
		return CRITICAL_COLOR
	if amount >= 40:
		return HEAVY_COLOR
	return NORMAL_COLOR


func _start_animation(amount: int, critical: bool) -> void:
	var duration := clampf(0.58 + float(amount) * 0.003, 0.58, 0.82)
	var rise := 0.56 + minf(0.24, float(amount) * 0.006)
	var drift := (float(get_instance_id() % 7) - 3.0) * 0.055
	var pop_scale := 1.24 if critical else 1.12
	scale = Vector3.ONE * pop_scale
	var start_position := position
	var target_position := start_position + Vector3(drift, rise, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target_position, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE * 0.82, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_label, "modulate:a", 0.0, duration).set_delay(duration * 0.42).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(queue_free)
