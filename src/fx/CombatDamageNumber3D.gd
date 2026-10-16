class_name CombatDamageNumber3D
extends Node3D
## 3D 战斗飘字的**独立兜底实例**（仅当 `VfxPool3D` 不在场景里时才被使用）。
## 正常路径见 `src/vfx/VfxDamageNumber3D.gd`（池化、FX02-01）。
##
## 字体与样式一律取 `src/vfx/DamageNumberStyle.gd` —— 本文件**禁止**再自行声明字体族或字号：
## 历史上正是这里写了一套等宽字体、而生效链路 `VfxDamageNumber3D` 从没设过字体，
## 导致实机飘字一直是 Label3D 默认字体，那套等宽字体只活在跑不到的兜底分支里。

const Style := preload("res://src/vfx/DamageNumberStyle.gd")

const NORMAL_COLOR := Color(1.0, 0.30, 0.26, 1.0)
const HEAVY_COLOR := Color(1.0, 0.53, 0.16, 1.0)
const CRITICAL_COLOR := Color(1.0, 0.88, 0.24, 1.0)

var _label: Label3D


func configure(amount: int, critical := false) -> void:
	if _label != null:
		return
	_label = Label3D.new()
	_label.name = "DamageText"
	_label.text = ("✦ " if critical else "") + str(maxi(1, amount))
	# 漫画风超粗字形 + 粗勾边，与池化链路同一真源。
	_label.font = Style.make_font()
	_label.font_size = Style.font_size_for(amount, critical)
	_label.outline_size = Style.outline_size_for(amount, critical)
	_label.outline_modulate = Style.OUTLINE_COLOR
	_label.modulate = _color_for(amount, critical)
	_label.pixel_size = Style.PIXEL_SIZE
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_start_animation(amount, critical)


func _color_for(amount: int, critical: bool) -> Color:
	if critical:
		return CRITICAL_COLOR
	if amount >= Style.HEAVY_AMOUNT_THRESHOLD:
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
	# Label3D 淡出必须走 transparency：只淡 modulate.a 会留下勾边残影（业主 2026-10-10）。
	tween.tween_property(_label, "transparency", 1.0, duration).set_delay(duration * 0.42).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(queue_free)
