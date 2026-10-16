class_name EncounterCountdownRing
extends Control
## 遭遇倒计时环（战局 HUD 右上角）。
##
## 业主 2026-10-16 原话：「放在画面的右上角，一个圈，然后中间有时间倒计时，
## 字体用下方的金币的字体。」⇒ 本控件只画**那一圈**；中间的时间文字是一个
## `Label`，由 `Dungeon3D._make_hud_label(...)` 造好后经 `bind_label()` 挂进来。
##
## ## 为什么文字不在这里 `draw_string`
## HUD 的文字体例（字号、描边、颜色）唯一真源是
## `Dungeon3D._make_hud_label()` + `_outline_labels()`，右下角金币读数就是这么造的。
## 若在这里再写一遍字号与描边，就会出现「同一个金币体出现两种描边」的漂移 ——
## 而这正是业主要求「用下方金币的字体」想避免的。
##
## ## 视觉口径与 `HudReloadRing` 同源
## 起点 12 点、顺时针推进（屏幕 +Y 向下 ⇒ 12 点是 −90°，顺时针 = 角度递增）、
## 底轨 + 外发光 + 主弧三层。但线宽**更细**：本环是背景信息，不是操作反馈，
## 不该抢换弹环的注意力。角度约定两边必须一致，否则两个环会转反。
##
## ## 环画的是**剩余量**，不是进度量
## 换弹环填的是"已经走了多少"，本环填的是"还剩多少" —— 弧越短，时间越少。
## 这是刻意的：倒计时的直觉是"这一圈在缩短"，看到弧变长会读成"又要来一波"。

## 环带线宽 ÷ 外半径。换弹环是 0.13；本环按「细一圈」取 0.075。
const THICKNESS_RATIO := 0.075
## 分段数。外径 86 px 级别下 96 段足够平滑。
const SEGMENTS := 96
## 屏幕空间起点：12 点方向。与 `HudReloadRing.START_ANGLE` 同一口径。
const START_ANGLE := -PI * 0.5
## 空槽（底轨）：留一点亮度，压在实景上仍要读得出"这里有一圈"。
const TRACK_COLOR := Color(0.98, 0.76, 0.30, 0.16)
## 主弧 = `Dungeon3D.RUN_COIN_READOUT_COLOR` 同色，只压了一点 alpha ——
## 环与中间的文字必须同色系，否则"金币字体"那句话就只落实了一半。
const FILL_COLOR := Color(1.0, 0.76, 0.26, 0.92)
## 外发光：同色系、更暗更透，用一圈更宽的弧近似。
const GLOW_COLOR := Color(0.62, 0.40, 0.06, 0.34)
## 外发光弧相对环带的宽度倍数（1.0 = 与主干同宽）。
const GLOW_WIDTH_RATIO := 1.9

## 剩余比例，1 = 刚触发（整圈），0 = 到点（空圈）。
var remaining_ratio := 1.0
## 剩余秒数（未取整的真值，供探针读）。
var remaining_sec := 0.0
var _label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## 注入中间那行时间。字体由 `Dungeon3D._make_hud_label()` 决定（见文件头）。
func bind_label(label: Label) -> void:
	_label = label
	if _label == null:
		return
	_label.name = "CountdownTimeLabel"
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _label.get_parent() != self:
		add_child(_label)


## 每帧写入。`remaining` / `duration` 都按秒；`duration <= 0` 视为整圈。
func set_time(remaining: float, duration: float) -> void:
	var safe_remaining := maxf(0.0, remaining)
	var ratio := clampf(safe_remaining / maxf(0.001, duration), 0.0, 1.0)
	# 早退必须在两处都判：只比秒数的话，`duration` 变了（关卡改时长）而剩余秒数
	# 恰好相同时，环的**长度**会错一帧。
	if is_equal_approx(ratio, remaining_ratio) and is_equal_approx(safe_remaining, remaining_sec):
		return
	remaining_ratio = ratio
	remaining_sec = safe_remaining
	if _label != null:
		# 秒数**上取整**：还剩 0.2 s 时显示 1 而不是 0 —— 显示 0 会读成"已经结束了"，
		# 而那时环上还剩一小段弧，两者会互相打脸。
		_label.text = format_time(maxi(0, int(ceil(safe_remaining))))
	queue_redraw()


## `M:SS`。刻意不用纯秒数：时长是关卡数据（可以被改到 60 s 以上），
## 纯秒数在长时长下会变成一串难读的数字。
static func format_time(total_seconds: int) -> String:
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


## 探针读数。几何量都由 `size` 现算，不在别处再存一份 —— 避免"读数和画面对不上"。
func get_snapshot() -> Dictionary:
	var outer_radius := minf(size.x, size.y) * 0.5
	var thickness := outer_radius * THICKNESS_RATIO
	return {
		"visible": visible,
		"remaining_ratio": remaining_ratio,
		"remaining_sec": remaining_sec,
		"text": _label.text if _label != null else "",
		"size": size,
		"center": global_position + size * 0.5,
		"outer_diameter_px": outer_radius * 2.0,
		"outer_radius_px": outer_radius,
		"stroke_radius_px": outer_radius - thickness * 0.5,
		"thickness_px": thickness,
		"thickness_ratio": THICKNESS_RATIO,
		"glow_width_px": thickness * GLOW_WIDTH_RATIO,
		"glow_width_ratio": GLOW_WIDTH_RATIO,
		"segments": SEGMENTS,
		"start_angle": START_ANGLE,
		"fill_color": FILL_COLOR,
		"track_color": TRACK_COLOR,
		"glow_color": GLOW_COLOR,
	}


func _draw() -> void:
	var outer_radius := minf(size.x, size.y) * 0.5
	if outer_radius <= 1.0:
		return
	var thickness := outer_radius * THICKNESS_RATIO
	# draw_arc 的 width 以弧线为中心向两侧铺开 ⇒ 取环带中径，两端才是 inner/outer。
	var stroke_radius := outer_radius - thickness * 0.5
	var center := size * 0.5
	# 底轨：整圈空槽。恒画，环整体显隐由外层管。
	draw_arc(center, stroke_radius, 0.0, TAU, SEGMENTS, TRACK_COLOR, thickness, true)
	if remaining_ratio <= 0.0:
		return
	var sweep := TAU * remaining_ratio
	# 弧头弧尾同亮、不做首尾淡出：这是"剩余量"，淡出会读成"没走完"，
	# 与 `HudReloadRing` 同一取舍。
	var points := maxi(2, int(ceil(float(SEGMENTS) * remaining_ratio)))
	draw_arc(
		center, stroke_radius, START_ANGLE, START_ANGLE + sweep, points,
		GLOW_COLOR, thickness * GLOW_WIDTH_RATIO, true
	)
	draw_arc(
		center, stroke_radius, START_ANGLE, START_ANGLE + sweep, points,
		FILL_COLOR, thickness, true
	)
