class_name VfxHealNumber3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX02-02 / VFX-HEAL-NUMBER-3D 治疗数字飘字特效
##
## 视觉：Label3D + 漫画风超粗字形 + 粗勾边 + 治疗绿（颜色独立于伤害三色，不由调用方指定）。
##       字体族 / 字重 / 字号 / 描边一律取 `DamageNumberStyle` —— 与伤害飘字同一真源，
##       否则同屏会出现两种字形（历史问题：伤害飘字与治疗飘字各用一套默认/等宽字体）。
## 行为：与 FX02-01 同一套力度曲线（猛起步上升 + 超调弹出），保证同屏观感统一。
##
## ⚠ 随机化纪律同 FX02-01：本脚本对同一 context 逐位可复现，随机数只活在调用方
##    `Enemy3D._spawn_heal_number()`。context 键与伤害飘字完全一致（见 VfxDamageNumber3D 头注）。

const Style := preload("res://src/vfx/DamageNumberStyle.gd")

## 治疗绿。治疗飘字刻意不取调用方传入的 effect_color —— 绿色是"这是回血不是掉血"的
## 唯一视觉标签，交给调用方指定迟早会被某个调用点写错。
const HEAL_COLOR := Color(0.4, 1.0, 0.55, 1.0)

const BASE_LIFETIME := 0.70
const BASE_RISE_DISTANCE := 0.90
const POP_SETTLE_TIME := 0.14
const SETTLED_SCALE := 0.90
const FADE_IN_TIME := 0.08
const FADE_OUT_START_RATIO := 0.62

var _label: Label3D
var _rise_distance: float = BASE_RISE_DISTANCE
var _drift: Vector3 = Vector3.ZERO
var _pop_scale: float = 1.0
## 出生点局部坐标基准。口径与事故经过见 `VfxDamageNumber3D._origin_local` 的注释：
## 少了这个基准，`_on_tick` 的赋值会把飘字从出生点打回池原点。
var _origin_local: Vector3 = Vector3.ZERO


func _on_activate(_world_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	var duration_scale: float = _context_float(context, "duration_scale", 1.0)
	lifetime = BASE_LIFETIME * clampf(duration_scale, 0.5, 2.0)
	_rise_distance = BASE_RISE_DISTANCE * maxf(0.0, _context_float(context, "rise_scale", 1.0))
	_drift = _context_vector(context, "drift")
	_pop_scale = maxf(1.0, _context_float(context, "pop_scale", 1.0))
	var magnitude: int = _context_int(context, "magnitude", 0)

	if _label == null:
		_label = Label3D.new()
		_label.name = "HealLabel"
		_label.pixel_size = Style.PIXEL_SIZE
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.font = Style.make_font()
		_label.outline_modulate = Style.OUTLINE_COLOR
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)

	_label.text = str(context.get("text_value", "+0"))
	# 治疗无暴击档，一律走普通档字号；分级口径与伤害飘字同一处（Style）。
	_label.font_size = Style.font_size_for(magnitude, false)
	_label.outline_size = Style.outline_size_for(magnitude, false)
	# 淡出走 transparency（勾边不吃 modulate 的 alpha），口径同 FX02-01。
	_label.modulate = Color(HEAL_COLOR.r, HEAL_COLOR.g, HEAL_COLOR.b, 1.0)
	_label.transparency = 1.0
	_label.scale = Vector3.ONE * _pop_scale
	global_position += _context_vector(context, "spawn_offset")
	_origin_local = position


func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clampf(elapsed / maxf(total, 0.0001), 0.0, 1.0)
	var rise_t: float = 1.0 - pow(1.0 - t, 3.0)
	# 位移叠加在出生点基准上（不是赋值），口径同 FX02-01。
	position = _origin_local + Vector3(_drift.x * rise_t, rise_t * _rise_distance, _drift.z * rise_t)
	# 弹出 → 收束 → 缓缩。缓缩进度从 POP_SETTLE_TIME 起算（口径同 FX02-01）。
	var glyph_scale: float
	if elapsed < POP_SETTLE_TIME:
		var settle: float = clampf(elapsed / POP_SETTLE_TIME, 0.0, 1.0)
		glyph_scale = lerpf(_pop_scale, 1.0, 1.0 - pow(1.0 - settle, 2.0))
	else:
		var shrink: float = clampf((elapsed - POP_SETTLE_TIME) / maxf(total - POP_SETTLE_TIME, 0.0001), 0.0, 1.0)
		glyph_scale = lerpf(1.0, SETTLED_SCALE, shrink)
	_label.scale = Vector3.ONE * glyph_scale
	var fade_out_start: float = total * FADE_OUT_START_RATIO
	var alpha: float
	if elapsed < FADE_IN_TIME:
		alpha = elapsed / FADE_IN_TIME
	elif elapsed < fade_out_start:
		alpha = 1.0
	else:
		alpha = 1.0 - (elapsed - fade_out_start) / maxf(total - fade_out_start, 0.0001)
	_label.transparency = 1.0 - clampf(alpha, 0.0, 1.0)


func _context_float(context: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = context.get(key)
	if value is float or value is int:
		return float(value)
	return fallback


func _context_int(context: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = context.get(key)
	if value is int or value is float:
		return int(value)
	return fallback


func _context_vector(context: Dictionary, key: String) -> Vector3:
	var value: Variant = context.get(key)
	if value is Vector3:
		return value
	return Vector3.ZERO
