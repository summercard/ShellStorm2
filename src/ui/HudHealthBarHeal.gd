class_name HudHealthBarHeal
extends Control
## 血条「回血补条」（2026-11-10 主人要求④）。
##
## 主人原话：「血条扣血的时候有扣血的动画，但是加血的时候没有，补充一个，风格一致。」
##
## ## 与扣血动画是同一族，不是另一套
## 扣血的读感来自 `PlayerHealthBarDelayed`：真实红条**瞬间**落到新血量，白色延迟段
## 留在原处再慢慢收回去 —— 白段 = "刚刚失去的那一截"。
## 回血反过来：白段在**刚刚恢复的那一截**上从旧血量位置向右生长，长到头再淡出，
## 露出底下的红条。同一个白色（`Enemy3D.HEALTH_BAR_DELAY_COLOR`）、同一种"白段讲差值"
## 的语法，所以两者看起来是一套东西，不靠形状或配色区分。
##
## ## 为什么不做"红条自己慢慢涨"
## `hp_bar.value` 是**真实生命值**的投影，`verify_reference_hud_fate_visual` 与
## `get_player_vitals_bar_snapshot().actual_ratio` 都要求它当帧到位。让它缓动等于让血条
## 短暂撒谎 —— 玩家读到的是"还在 60%"而实际已经 80%，低血量暗角、阵亡判定全都对不上。
## 因此动画只能加在**叠加层**上：真实值立即写，视觉增量单独演。
##
## ## 生命周期
## 由 `Dungeon3D` 每帧 `tick(delta)` 推进（与底纹、震动同一节拍），自己不开 `_process`。
## 播完自行 `visible = false` 并归零，**不持有任何生命值**。

## 整段动画时长（秒）。比扣血白段的收回略短一点：回血是"补偿感"，拖长了会觉得黏。
const DURATION := 0.40
## 前沿推进占整段的比例，剩下的是"停住 + 淡出"。
const LEAD_PHASE_RATIO := 0.62
## 填充色 = 扣血白段同色（`Enemy3D.HEALTH_BAR_DELAY_COLOR`），略压 alpha 让它比扣血柔和。
const FILL_COLOR := Color(1.0, 1.0, 1.0, 0.82)
## 前沿竖线：比填充更亮，读成"正在往这里补"。
const EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.98)
## 前沿外发光（一圈更宽的竖线近似）。
const EDGE_GLOW_COLOR := Color(1.0, 1.0, 1.0, 0.20)
## 前沿竖线宽 ÷ 血条高度。
const EDGE_WIDTH_RATIO := 0.16

var _from_ratio := 0.0
var _to_ratio := 0.0
var _elapsed := 0.0
var _active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## 开始一次回血补条。`from_ratio` 是治疗前的血量比例（红条的旧值），
## `to_ratio` 是治疗后的比例。差值小于半个像素量级时直接忽略 ——
## 逐点回血（饰品、被动）会每帧调一次，不设底噪就会一直闪。
func play(from_ratio: float, to_ratio: float) -> void:
	var start := clampf(from_ratio, 0.0, 1.0)
	var target := clampf(to_ratio, 0.0, 1.0)
	if target - start <= 0.004:
		return
	_from_ratio = start
	_to_ratio = target
	_elapsed = 0.0
	_active = true
	visible = true
	queue_redraw()


func is_active() -> bool:
	return _active


## 由 `Dungeon3D` 每帧推进。
func tick(delta: float) -> void:
	if not _active:
		return
	_elapsed += maxf(0.0, delta)
	if _elapsed >= DURATION:
		_active = false
		_elapsed = 0.0
		visible = false
		queue_redraw()
		return
	queue_redraw()


## 白色前沿此刻所在的血量比例。`lead_ratio` 从 `from` 走到 `to`，
## 走完就停住，只让 alpha 衰减。
func get_lead_ratio() -> float:
	if not _active:
		return _to_ratio
	var lead_span := maxf(0.001, DURATION * LEAD_PHASE_RATIO)
	var progress := clampf(_elapsed / lead_span, 0.0, 1.0)
	# ease-out：起手快、收尾慢，读成"补上去了"而不是"匀速灌水"。
	var eased := 1.0 - pow(1.0 - progress, 2.0)
	return lerpf(_from_ratio, _to_ratio, eased)


## 当前整体透明度：前 55% 满亮，之后线性淡出。
func get_fade_alpha() -> float:
	if not _active:
		return 0.0
	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	if progress <= 0.55:
		return 1.0
	return clampf(1.0 - (progress - 0.55) / 0.45, 0.0, 1.0)


func get_snapshot() -> Dictionary:
	return {
		"active": _active,
		"visible": visible,
		"elapsed": _elapsed,
		"duration": DURATION,
		"from_ratio": _from_ratio,
		"to_ratio": _to_ratio,
		"lead_ratio": get_lead_ratio(),
		"fade_alpha": get_fade_alpha(),
		"size": size,
	}


func _draw() -> void:
	var bar_width := size.x
	var bar_height := size.y
	if not _active or bar_width <= 1.0 or bar_height <= 1.0:
		return
	var alpha := get_fade_alpha()
	if alpha <= 0.01:
		return
	var x_from := _from_ratio * bar_width
	var x_lead := get_lead_ratio() * bar_width
	if x_lead - x_from > 0.5:
		draw_rect(
			Rect2(Vector2(x_from, 0.0), Vector2(x_lead - x_from, bar_height)),
			Color(FILL_COLOR, FILL_COLOR.a * alpha),
			true
		)
	var edge_width := maxf(1.5, bar_height * EDGE_WIDTH_RATIO)
	draw_line(
		Vector2(x_lead, 0.0),
		Vector2(x_lead, bar_height),
		Color(EDGE_GLOW_COLOR, EDGE_GLOW_COLOR.a * alpha),
		edge_width * 3.0,
		true
	)
	draw_line(
		Vector2(x_lead, 0.0),
		Vector2(x_lead, bar_height),
		Color(EDGE_COLOR, EDGE_COLOR.a * alpha),
		edge_width,
		true
	)
