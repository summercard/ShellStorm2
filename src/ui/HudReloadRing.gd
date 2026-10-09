class_name HudReloadRing
extends Control
## 换弹进度环（HUD 版）：套在右下角**武器图标**上的一圈换弹进度。
##
## 2026-10-08（`0.2-PLAYER-001` 追记五）主人原话：
##   > 就是我换子弹的那个提示圈，帮我换到图片中的枪械图标的位置来，然后大小跟我红圈一样大。
## 于是环从**世界空间**（角色身侧，见 `PlayerAvatar3D` 的 `RELOAD_RING_*` 一族常量，
## 已由 `RELOAD_RING_IN_WORLD = false` 退役）搬到 **HUD 武器图标**上。
##
## 🔴 为什么必须是 HUD 控件，而不是"把 3D 环挪到屏幕右下角"：
##   `CanvasLayer` 恒在 3D 之上 —— 3D 环即便摆在图标的屏幕位置上，图标本体（不透明网格）
##   也会把它压在下面，只有漏在图标外的部分看得见。要"套在图标上"只能画在 HUD 层。
##
## ## 尺寸与位置的真源 = 主人的标注图
## 标注图 1280×720，而 `window/stretch/mode = canvas_items` + `aspect = expand` 在
## 1280×720 窗口下缩放因子恰为 **1.0** ⇒ 该图里 **canvas px == 屏幕 px**。实测：
##   · 红圈外径 **75 px**、圈心 **(1066.0, 675.5)**；
##   · 右下武器图标控件矩形 = 屏幕 x `1041.6 .. 1092.8`（内容右对齐反算）、
##     矩形中心 **(1067.2, 676.4)** —— 与红圈圈心差 1.2 px。
## ⇒ **环心 = 图标矩形中心**（取结构量、不取手绘像素：换分辨率/挪面板/改图标尺寸时自动跟随）。
## 本控件因此**不自己算位置**：由 `Dungeon3D._place_hud_reload_ring()` 每帧把中心对齐过去。
##
## ## 视觉语言与已退役的世界环同源（不许各画各的）
## · 几何：起点 12 点、顺时针推进 —— 与 `RingProgressGeometry.START_ANGLE` 同一口径
##   （那个文件是**3D mesh** 的唯一真源，本控件是**2D 画布**，两边的角度约定必须对齐，
##   否则"换弹环"和交互读条环会转反）。
## · 线宽比 `THICKNESS_RATIO` —— 按主人红笔实测标定，见下面的推导（**不再**沿用世界环的 0.2226）。
## · 颜色真源是 prefab 里 `MatReloadFill` 的 albedo / emission（世界环退役后，
##   那对材质仍是**颜色真源**，故此处逐字抄下并注明来源，不再各调一版绿）。

## 环带线宽 ÷ 外半径。
##
## 2026-10-09 主人返工（原话：「太粗了 细一点」）⇒ 由 **0.2226 下调到 0.13**。
##
## 0.13 不是手感值，是**把主人的红笔当标尺量出来的**：对标注图里那一圈红像素
## 按「到圈心的半径」分桶（1280×720 下 canvas px == 屏幕 px），得到
##
##   r = 34   35   36   37   38   39   40      ← 半径
##      56  120  204  220  164  112   27      ← 该半径上的红像素数
##
## ⇒ **核心亮带 = r 35..39 = 5 px**，按像素加权的平均半径 36.84（红笔圈的中径）。
## 主人圈的外半径按水平 span 取 37.5 ⇒ **笔宽/外半径 = 5 / 37.5 = 0.1333**。
##
## 取 0.13 ⇒ 本环线宽 = 37.5 × 0.13 = **4.875 px**，与红笔核心亮带 5 px 逐像素吻合。
## （改之前是 0.2226 ⇒ 8 px，`8 / 4.875 ≈ 1.64` —— 就是主人说的"太粗"。）
##
## ⚠️ 这个数**与世界环的 `PlayerAvatar3D.RELOAD_RING_THICKNESS_RATIO`(0.2226) 不再同值**，
## 这是有意的：世界环已退役（`RELOAD_RING_IN_WORLD = false`），现在**画面上只有本环**，
## 没有再对齐那个值的必要；而"和红笔一样细"是主人新给的口径，优先级更高。
## 那段历史（0.2226 出自交互读条环的 `0.059 / 0.265`）记在世界环那边，不动。
const THICKNESS_RATIO := 0.13
## 分段数。屏幕直径 75 px 的环，64 段足够看不出多边形边（与世界环取值一致）。
const SEGMENTS := 64
## 屏幕空间的起点：12 点方向。屏幕 +Y 向下，故 12 点是 −90°；顺时针 = 角度递增。
## 3D 环那边是 `START_ANGLE = +PI/2` 且角度递减（mesh 空间 +Y 向上）。
const START_ANGLE := -PI * 0.5
## 空槽（底轨）：留一点亮度，不然压在深蓝场景/暗面板上读不出"这里有一圈"。
const TRACK_COLOR := Color(0.55, 0.86, 0.92, 0.20)
## 填充色 = `chr_player_capsule01_root_top3d_v001.tscn` 的 `MatReloadFill.albedo_color`。
const FILL_COLOR := Color(0.22, 0.92, 0.76, 0.98)
## 外发光 = 同一材质的 `emission`。2D 画布里用一圈更宽更透的弧近似它。
##
## 2026-10-09 与线宽**同批**下调（原话「太粗了 细一点」）：`0.50 → 0.38`。
## 原因是"看着粗"有一半出在发光上而不是主干上 —— 旧参数下发光 = 主干 8 px × 2.6 = **20.8 px 宽**，
## 半透明绿铺开两倍多，人眼读到的是一条 20 px 的粗环，主干缩到 4.875 px 也救不回来。
## 现在 = 4.875 × 1.8 = **8.8 px**，alpha 也压下来，轮廓才干净。
const GLOW_COLOR := Color(0.08, 0.58, 0.48, 0.38)
## 外发光弧相对环带的宽度倍数（1.0 = 与主干同宽）。见 `GLOW_COLOR` 的说明。
const GLOW_WIDTH_RATIO := 1.8

## 换弹进度，0..1。写入即重绘；只在真的变了才重绘（换弹环每帧被推一次）。
var progress := 0.0:
	set = set_progress


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_progress(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, progress):
		return
	progress = clamped
	queue_redraw()


## 探针读数。几何量都由 `size` 现算，不在别处再存一份 —— 避免"读数和画面对不上"。
func get_snapshot() -> Dictionary:
	var outer_radius := minf(size.x, size.y) * 0.5
	var thickness := outer_radius * THICKNESS_RATIO
	return {
		"progress": progress,
		"visible": visible,
		"size": size,
		"center": global_position + size * 0.5,
		"outer_diameter_px": outer_radius * 2.0,
		"outer_radius_px": outer_radius,
		"stroke_radius_px": outer_radius - thickness * 0.5,
		"thickness_px": thickness,
		"thickness_ratio": THICKNESS_RATIO,
		# 发光是"看着粗不粗"的另一半，必须一起报出来：主干细了但发光铺得很开，
		# 观感上仍然是粗的（2026-10-09 返工的原因之一）。验收同时断这两条。
		"glow_width_px": thickness * GLOW_WIDTH_RATIO,
		"glow_width_ratio": GLOW_WIDTH_RATIO,
		"glow_color": GLOW_COLOR,
		"segments": SEGMENTS,
		"start_angle": START_ANGLE,
		"fill_color": FILL_COLOR,
		"track_color": TRACK_COLOR,
	}


func _draw() -> void:
	var outer_radius := minf(size.x, size.y) * 0.5
	if outer_radius <= 1.0:
		return
	var thickness := outer_radius * THICKNESS_RATIO
	# draw_arc 的 width 以弧线为中心向两侧铺开 ⇒ 取环带中径，两端才是 inner/outer。
	var stroke_radius := outer_radius - thickness * 0.5
	var center := size * 0.5
	# 底轨：整圈空槽。恒画，换弹未开始时该控件整体不可见（显隐由外层管）。
	draw_arc(center, stroke_radius, 0.0, TAU, SEGMENTS, TRACK_COLOR, thickness, true)
	if progress <= 0.0:
		return
	var sweep := TAU * progress
	# 弧头弧尾同亮、不做首尾淡出：这是"填充量"，淡出会读成"没走完"
	# （与 `RingProgressGeometry.build_arc(..., end_fade_ratio = 0)` 同一口径）。
	var points := maxi(2, int(ceil(float(SEGMENTS) * progress)))
	draw_arc(
		center, stroke_radius, START_ANGLE, START_ANGLE + sweep, points,
		GLOW_COLOR, thickness * GLOW_WIDTH_RATIO, true
	)
	draw_arc(
		center, stroke_radius, START_ANGLE, START_ANGLE + sweep, points,
		FILL_COLOR, thickness, true
	)
