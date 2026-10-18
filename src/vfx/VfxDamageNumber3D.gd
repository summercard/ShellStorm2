class_name VfxDamageNumber3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX02-01 / VFX-DAMAGE-NUMBER-3D 伤害数字飘字特效
##
## 视觉：Label3D + 漫画风超粗字形 + 粗勾边 + 颜色编码（普通暖白 / 元素色 / 暴击金）。
##       字体族、字重、字号分级、描边分级、世界像素比一律取 `DamageNumberStyle`
##       —— 本脚本**不得**再自行声明字体或字号（历史上两处口径就是这么漂移的）。
## 行为：基线 lifetime 0.56s × context.duration_scale；猛起步上升 + 超调弹出 + 渐显渐隐；billboarding。
##
## ⚠ 随机化纪律（vfx skill §5.5.3）：本脚本对同一 context **逐位可复现**，源码内不出现 `randf()`。
##    它是被逐帧断言驱动的对象，把随机埋进来会让验收变成随机红。
##    逐发随机的职责在调用方 `Enemy3D._spawn_damage_number()`，经 context 传入：
##      text_value      String  显示文本（数字，治疗为 "+N"）
##      magnitude       int     数值本身，供字号 / 描边分级（不解析字符串）
##      critical        bool    是否暴击（取暴击档字号 + 金色）
##      spawn_offset    Vector3 出生点抖动（米，可选）
##      rise_scale      float   上升距离倍率（可选，默认 1.0）
##      drift           Vector3 升到终点时的水平漂移（米，XZ，可选）
##      pop_scale       float   出生瞬间的弹出缩放（可选，默认 1.0）
##      duration_scale  float   时长倍率（可选，默认 1.0）

const Style := preload("res://src/vfx/DamageNumberStyle.gd")

## 基线时长。乘 `context.duration_scale` 后写入基类 `lifetime`。
const BASE_LIFETIME := Style.DAMAGE_LIFETIME
## 基线上升距离（米）。乘 `context.rise_scale`。
## 力度口径（业主 2026-10-16「飘起的力度感强一些」）= 位移曲线 + 距离两个手段一起给：
## 距离 0.60 → 0.90（+50%），曲线从 ease-out quad 换成 ease-out cubic（前 1/3 走完 70% 位移）。
const BASE_RISE_DISTANCE := Style.DAMAGE_RISE
## 弹出收束时长：出生瞬间放大到 `pop_scale`，再在这个时间内收到 1.0。
## 这是"打出来"的冲击感来源 —— 先过冲再收，比"从小长大"有力得多。
const POP_SETTLE_TIME := 0.14
## 弹出收束后再缓缩到的终值。避免飘到末尾还是满尺寸、像贴纸。
const SETTLED_SCALE := 0.90
## 渐显时长：快显（比旧版 0.15 更短），让数字"砸"出来而不是"浮"出来。
const FADE_IN_TIME := Style.DAMAGE_FADE_IN
## 开始渐隐的时间占寿命比例。
const FADE_OUT_START_RATIO := 0.62

var _label: Label3D
var _rise_distance: float = BASE_RISE_DISTANCE
var _drift: Vector3 = Vector3.ZERO
var _pop_scale: float = 1.0
## 出生点的**局部坐标**基准。`_on_tick` 是每帧重算姿态（不是增量），必须有个基准可依，
## 否则 `position = ...` 会把出生坐标整个覆盖掉。
var _origin_local: Vector3 = Vector3.ZERO


func _on_activate(_world_pos: Vector3, color: Color, _size: float, context: Dictionary) -> void:
	var duration_scale: float = _context_float(context, "duration_scale", 1.0)
	lifetime = BASE_LIFETIME * clampf(duration_scale, 0.5, 2.0)
	_rise_distance = BASE_RISE_DISTANCE * maxf(0.0, _context_float(context, "rise_scale", 1.0))
	_drift = _context_vector(context, "drift")
	_pop_scale = maxf(1.0, _context_float(context, "pop_scale", 1.0))
	var magnitude: int = _context_int(context, "magnitude", 0)
	var critical: bool = bool(context.get("critical", false))

	if _label == null:
		_label = Label3D.new()
		_label.name = "DamageLabel"
		_label.pixel_size = Style.PIXEL_SIZE
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.font = Style.make_font()
		_label.outline_modulate = Style.OUTLINE_COLOR
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)

	_label.text = str(context.get("text_value", "0"))
	_label.font_size = Style.font_size_for(magnitude, critical)
	_label.outline_size = Style.outline_size_for(magnitude, critical)
	# 颜色：调用方按 DamageNumberStyle 传入（暖白 / 元素色 / 暴击金）。基色 alpha 归一为 1，透明度全部由 transparency 承载
	# —— Label3D 淡出必须走 transparency：描边不吃 modulate 的 alpha，只淡正文会留下勾边残影
	#    （业主 2026-10-10）。`transparency = 1 - alpha` 与旧 `modulate.a = alpha` 逐值等价。
	_label.modulate = Color(color.r, color.g, color.b, 1.0)
	_label.transparency = 1.0
	# 出生即弹出尺寸（不是从小长大）。
	_label.scale = Vector3.ONE * _pop_scale
	# 出生点抖动：基类已设好 global_position，这里叠加调用方给的抖动。
	# 抖动必须施加在**世界空间**（不是 local）—— 飘字不绑 follow，两者等价，但写世界空间
	# 能保证将来若有人给飘字绑上 follow 也不会把抖动方向带歪。
	global_position += _context_vector(context, "spawn_offset")
	# ⚠ 存下出生点：`_on_tick` 需要它做基准。不存就会出现下面这段历史事故 ——
	#   2026-09-11 池化迁移起，`_on_tick` 里的 `position.y = rise_t * _rise_distance`
	#   是**赋值**而不是叠加，于是出生坐标在第一帧就被清零，实机所有飘字都跑到
	#   世界原点上方不到 1 米处（跟怪物所在楼层毫无关系，98F 尤甚）。
	#   2026-10-16 实测确认并修复：`position = _origin_local + 偏移`。
	_origin_local = position


func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clampf(elapsed / maxf(total, 0.0001), 0.0, 1.0)
	# 上升：ease-out cubic ⇒ 起步猛、尾段缓，"力度"集中在前 1/3。
	var rise_t: float = 1.0 - pow(1.0 - t, 3.0)
	# 位移必须**叠加在出生点基准上**（`_origin_local + 偏移`），不能直接赋值 position.y ——
	# 赋值会把出生坐标（怪物头顶那一处）整个丢掉，飘字会落到池原点附近。
	# 水平漂移同样叠加，制造"被打散"的落点散布（而不是所有数字排成一竖列）。
	position = _origin_local + Vector3(_drift.x * rise_t, rise_t * _rise_distance, _drift.z * rise_t)
	# 弹出 → 收束 → 缓缩。两段必须分开：前段是"过冲回收"，后段是"整体缩小"，
	# 合成一条曲线会让出生瞬间的冲击感消失。缓缩进度必须从 POP_SETTLE_TIME **起算** ——
	# 若直接从 0 起算，收束完成的那一帧 scale 已经被缩掉一截，永远收不到 1.0。
	var glyph_scale: float
	if elapsed < POP_SETTLE_TIME:
		var settle: float = clampf(elapsed / POP_SETTLE_TIME, 0.0, 1.0)
		glyph_scale = lerpf(_pop_scale, 1.0, 1.0 - pow(1.0 - settle, 2.0))
	else:
		var shrink: float = clampf((elapsed - POP_SETTLE_TIME) / maxf(total - POP_SETTLE_TIME, 0.0001), 0.0, 1.0)
		glyph_scale = lerpf(1.0, SETTLED_SCALE, shrink)
	_label.scale = Vector3.ONE * glyph_scale
	# 透明度三段：快显（0 → FADE_IN）→ 保持 → 渐隐（FADE_OUT_START_RATIO → 寿命末尾）。
	var fade_out_start: float = total * FADE_OUT_START_RATIO
	var alpha: float
	if elapsed < FADE_IN_TIME:
		alpha = elapsed / FADE_IN_TIME
	elif elapsed < fade_out_start:
		alpha = 1.0
	else:
		alpha = 1.0 - (elapsed - fade_out_start) / maxf(total - fade_out_start, 0.0001)
	_label.transparency = 1.0 - clampf(alpha, 0.0, 1.0)


## 读可选 float 参数。缺省 / 类型不符时回落 fallback，绝不把 Variant 直接参与算术
## （本仓开「警告即错误」，隐式 Variant 算术会编译失败）。
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
