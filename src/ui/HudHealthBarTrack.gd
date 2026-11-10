class_name HudHealthBarTrack
extends Control
## 玩家主界面血条的底纹槽（2026-11-10 主人要求③）。
##
## 主人原话：「血条的底部是透明的，所以看不见血条总量和扣血情况。在血条底部加上斜杆
## 半透明的带横向位移动画的 ui，灰色 暗一点不要抢眼。」
##
## ## 为什么需要这一层
## 在此之前 `PlayerHealthBarStack` 里只有两条 `ProgressBar`：白色延迟条（受击后追赶）
## 与红色真实条，两条的 `background` 都接近全透明。满血时看不出来；一旦掉血，空出来的
## 那一段**没有任何图形** —— 玩家只看到红条变短，读不出「总共多长、这一下掉了多少」。
## 本控件补的就是这段空槽。
##
## ## 视觉口径（刻意压到"看得见但不吸引视线"）
## · 底色：极暗冷蓝 slate，只把血条总长托出来，alpha 约 0.34；
## · 斜纹：45° 细线、灰白、alpha 0.13 —— 比底缘线更弱，是"织物纹理"不是"告警条纹"；
## · 横向位移：线族 `x + y = c` 整体只平移 `c`（等价于纯 X 方向平移），
##   读起来是缓缓流动，不是旋转、也不是上下滚；
## · 底缘 1px 弱白线：本控件唯一的"结构线"，把血条总长与身后实景分开。
##
## ## 为什么不用 `clip_contents`
## `Control.clip_contents` 只裁**子节点**，不裁自身 `_draw` 出来的图元。斜纹若整片旋转后的
## 矩形去画，线头会溢出到血条外面（血条无背板，溢出就是直接画在场景上）。
## 这里按直线族解出「与控件矩形求交后的两个端点」再画，天然不越界，也不需要 shader。

## 斜纹线宽 ÷ 控件高度。血条高约 21 canvas px ⇒ 线宽约 2.3 px。
const STRIPE_THICKNESS_RATIO := 0.11
## 相邻斜纹间距 ÷ 控件高度（约 9.6 px 一格）。
const STRIPE_PERIOD_RATIO := 0.46
## 横向流速：每秒移动「多少个控件高度」。0.55 ⇒ 约 11 px/s，慢到不抢注意力。
const SCROLL_SPEED_RATIO := 0.55
## 空槽底色。冷蓝 slate、半透，压在实景上仍能读出血条总长。
const BASE_COLOR := Color(0.070, 0.100, 0.138, 0.34)
## 斜纹色。灰白（不是纯白：纯白在暗场景里会跳出来）。
const STRIPE_COLOR := Color(0.760, 0.808, 0.886, 0.11)
## 底缘结构线。1 px，弱白。
const BASELINE_COLOR := Color(1.0, 1.0, 1.0, 0.16)

var _scroll := 0.0
var _motion_enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## 由 `Dungeon3D` 每帧推一次。本控件**不自建 `_process`**：
## HUD 的视觉节拍统一由场景主循环驱动，套件里 `set_process(false)` 冻场景时
## 底纹也必须冻结，否则截图与断言会随机器帧率漂。
func tick(delta: float) -> void:
	# 无障碍开关每帧现读：玩家在设置页里改完立刻生效，不必等重进关卡。
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		if _motion_enabled:
			_motion_enabled = false
			queue_redraw()
		return
	if not _motion_enabled:
		_motion_enabled = true
	if size.y <= 1.0:
		return
	var period := maxf(1.0, size.y * STRIPE_PERIOD_RATIO)
	_scroll = fmod(_scroll + delta * size.y * SCROLL_SPEED_RATIO, period)
	queue_redraw()


## 探针读数。几何量全部由 `size` 现算，不在别处再存一份。
func get_snapshot() -> Dictionary:
	var bar_height := maxf(1.0, size.y)
	return {
		"scroll_px": _scroll,
		"motion_enabled": _motion_enabled,
		"stripe_thickness_px": maxf(1.0, bar_height * STRIPE_THICKNESS_RATIO),
		"stripe_period_px": maxf(1.0, bar_height * STRIPE_PERIOD_RATIO),
		"scroll_speed_px_per_sec": bar_height * SCROLL_SPEED_RATIO,
		"base_color": BASE_COLOR,
		"stripe_color": STRIPE_COLOR,
		"baseline_color": BASELINE_COLOR,
		"size": size,
	}


func _draw() -> void:
	var bar_width := size.x
	var bar_height := size.y
	if bar_width <= 1.0 or bar_height <= 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BASE_COLOR, true)
	var thickness := maxf(1.0, bar_height * STRIPE_THICKNESS_RATIO)
	var period := maxf(thickness * 2.0, bar_height * STRIPE_PERIOD_RATIO)
	# 斜纹必须**完全**留在血条矩形内：`draw_line` 的宽度是沿法线向两侧铺开的，
	# 一条 45° 线在端点处会向外溢出约 `width × 0.7`。不减这个内缩量，
	# 纹理会从血条上沿和下沿「漏」到实景上（血条无背板，漏出去就是画在场景上）。
	# 2026-11-10 首版就漏了：截图里血条上方能看到一排斜纹尖。
	var inset := thickness * 0.75
	var y_min := inset
	var y_max := bar_height - inset
	if y_max - y_min < 1.0:
		return
	# 线族 x + y = c：`_scroll` 让整族沿 X 平移。两侧各多留一个周期，
	# 否则 `_scroll` 接近周期时右下一角会空出一条（斜纹本身是无限的，只是被裁到了）。
	var c := y_min - period + _scroll
	while c < bar_width + y_max + period:
		# 与矩形求交：0 ≤ x ≤ W ⇒ c − W ≤ y ≤ c；再夹到内缩后的 y 区间。
		var y_lo := maxf(y_min, c - bar_width)
		var y_hi := minf(y_max, c)
		if y_hi - y_lo >= 1.0:
			draw_line(
				Vector2(c - y_lo, y_lo),
				Vector2(c - y_hi, y_hi),
				STRIPE_COLOR,
				thickness,
				true
			)
		c += period
	draw_line(
		Vector2(0.0, bar_height - 0.5),
		Vector2(bar_width, bar_height - 0.5),
		BASELINE_COLOR,
		1.0,
		false
	)
