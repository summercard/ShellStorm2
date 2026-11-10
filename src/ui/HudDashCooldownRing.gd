class_name HudDashCooldownRing
extends Control
## 翻滚（冲刺）冷却环（2026-11-10 主人要求①）。
##
## 主人原话：「增加一个翻滚冷却的示意 hud，风格要和主界面一致，位置你找一些游戏参考，
## 不要用文字提醒，用图形或进度条形式。」
##
## ## 位置为什么在角色状态块里
## 参考两处成熟做法：① 守望先锋 / Warframe 的能力图标——小圆形图标 + 环形扫描，
## 冷却期间扫描填满、就绪瞬间提亮；② 哈迪斯的冲刺标记——挂在角色资源读数的旁边
## 而不是画面中心。本作 HUD 已经把左上角定为「玩家资源列」（血条 → 手电电量），
## 冲刺是同一类资源，因此放在**血条正下方、电芯那一行的左端**，
## 既不侵入画面中心（业主多次强调 HUD 不许吃视野），也不会和左下倒计时环、
## 右下武器栏抢位。
##
## ## 为什么不用 `CodeHUDGlyph` 的 dash 字形
## 那个字形按 64 px 设计（描边固定 +7/+3 px 的辉光），缩到 15 px 会糊成一团。
## 这里改画**两枚折角**（`»`）：与棱镜规范 §3.3 的下折角同一母题，笔画宽度按控件尺寸
## 现算，任意尺寸下都干净。
##
## ## 读数方向与换弹环 / 倒计时环一致
## 起点 12 点、顺时针。但本环填的是**已恢复量**（换弹环同口径），不是剩余量 ——
## 冷却越接近结束，弧越长；满圈 = 可以翻滚。与倒计时环（画剩余量）刻意相反：
## 倒计时的直觉是"这一圈在缩短"，而冷却的直觉是"这一圈在充满"。

## 环带线宽 ÷ 外半径。与 `HudReloadRing.THICKNESS_RATIO` 同值 —— 同为"操作反馈环"。
const THICKNESS_RATIO := 0.13
## 分段数。外径 25 canvas px 级，48 段已足够平滑，也不至于每帧生成过多顶点。
const SEGMENTS := 48
## 屏幕空间起点：12 点方向（屏幕 +Y 向下 ⇒ 12 点是 −90°；顺时针 = 角度递增）。
const START_ANGLE := -PI * 0.5
## 底轨。弱白，只表明"这里有一圈"。
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.13)
## 冷却中：天蓝强调（`UIPalette.PRISM_ACCENT`）压 alpha —— 语义是"进度填充"。
const FILL_COLOR := Color(0.310, 0.659, 1.0, 0.72)
## 就绪：近白（`UIPalette.PRISM_TEXT`）。蓝→白的切换本身就是"可用"的信号，
## 不需要文字，也不需要第二个图形。
## alpha 压到 0.78：这是个**常驻**控件，满圈常亮会把视线从血条上拉走。
const READY_COLOR := Color(0.949, 0.965, 0.984, 0.78)
const GLOW_COLOR := Color(0.200, 0.520, 0.900, 0.30)
const GLOW_WIDTH_RATIO := 1.7
## 就绪瞬间的一次外环提亮时长（秒）。是"反馈"不是"入场动画"，所以不做缩放与回弹。
const READY_FLASH_SEC := 0.24
## 环心图形尺寸（÷ 外半径）。
## 2026-11-10 实拍定了三版：① 0.44 的两枚折角在 22 px 环里糊成一个桃心斑；
## ② 1.02 的两枚折角又贴死在环带上。环内净空只有约 14 px（22.4 外径 − 两侧环带），
## 在里面塞两枚折角不可能干净 —— 现在改成**单枚空心飞镖**（`▶` 的线框版），
## 与棱镜的"线框语言"同源，且在 14 px 里仍是可辨的空心三角。
const GLYPH_WIDTH_RATIO := 0.56
const GLYPH_HEIGHT_RATIO := 0.66
## 飞镖笔画宽 ÷ 外半径。
const GLYPH_STROKE_RATIO := 0.115

## 冷却比例：1 = 刚翻滚完，0 = 已就绪。由 `Player3D.dash_cooldown_changed` 推入。
var cooldown_ratio := 0.0:
	set = set_cooldown_ratio

var _ready_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## 写入冷却比例。只在真的变了才重绘 —— 信号每物理帧推一次，冷却走完后比例恒为 0，
## 不设这道早退就会每帧无条件重绘一个没人看的环。
func set_cooldown_ratio(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	var was_ready := cooldown_ratio <= 0.0001
	var now_ready := clamped <= 0.0001
	var changed := not is_equal_approx(clamped, cooldown_ratio)
	cooldown_ratio = clamped
	if not changed:
		return
	# 由"未就绪"跨到"就绪"的那一帧起闪光；同时重绘让满圈立刻变白。
	if now_ready and not was_ready:
		_ready_flash = READY_FLASH_SEC
	queue_redraw()


## 由 `Dungeon3D` 每帧推进（只用来衰减就绪闪光）。
func tick(delta: float) -> void:
	if _ready_flash <= 0.0:
		return
	_ready_flash = maxf(0.0, _ready_flash - maxf(0.0, delta))
	queue_redraw()


func is_ready() -> bool:
	return cooldown_ratio <= 0.0001


func get_snapshot() -> Dictionary:
	var outer_radius := minf(size.x, size.y) * 0.5
	var thickness := outer_radius * THICKNESS_RATIO
	return {
		"cooldown_ratio": cooldown_ratio,
		"ready_ratio": 1.0 - cooldown_ratio,
		"ready": is_ready(),
		"ready_flash_sec": _ready_flash,
		"size": size,
		"center": global_position + size * 0.5,
		"outer_diameter_px": outer_radius * 2.0,
		"stroke_radius_px": outer_radius - thickness * 0.5,
		"thickness_px": thickness,
		"thickness_ratio": THICKNESS_RATIO,
		"segments": SEGMENTS,
		"start_angle": START_ANGLE,
		"track_color": TRACK_COLOR,
		"fill_color": FILL_COLOR,
		"ready_color": READY_COLOR,
	}


func _draw() -> void:
	var outer_radius := minf(size.x, size.y) * 0.5
	if outer_radius <= 1.0:
		return
	var thickness := outer_radius * THICKNESS_RATIO
	# draw_arc 的 width 以弧线为中心向两侧铺开 ⇒ 取环带中径，两端才是 inner/outer。
	var stroke_radius := outer_radius - thickness * 0.5
	var center := size * 0.5
	draw_arc(center, stroke_radius, 0.0, TAU, SEGMENTS, TRACK_COLOR, thickness, true)
	var ready_ratio := 1.0 - cooldown_ratio
	var ring_color := READY_COLOR if is_ready() else FILL_COLOR
	if ready_ratio > 0.0:
		var sweep := TAU * ready_ratio
		var points := maxi(2, int(ceil(float(SEGMENTS) * ready_ratio)))
		draw_arc(
			center, stroke_radius, START_ANGLE, START_ANGLE + sweep, points,
			GLOW_COLOR, thickness * GLOW_WIDTH_RATIO, true
		)
		draw_arc(
			center, stroke_radius, START_ANGLE, START_ANGLE + sweep, points,
			ring_color, thickness, true
		)
	if _ready_flash > 0.0:
		var flash := clampf(_ready_flash / READY_FLASH_SEC, 0.0, 1.0)
		draw_arc(
			center, stroke_radius, 0.0, TAU, SEGMENTS,
			Color(READY_COLOR, 0.45 * flash),
			thickness * GLOW_WIDTH_RATIO * 1.7, true
		)
	_draw_dash_glyph(center, outer_radius, Color(ring_color, 0.92 if is_ready() else 0.70))


## 环心图形：单枚右向空心飞镖（`▶` 的线框版）。
## 几何全部按"外半径的比例"解出，且**以环心对称** —— 首版按折角拼，两枚的包围盒
## 中心落在 −1.75 px，实拍里明显偏左。这里三点的平均值恒为 (0, 0)，不可能偏心。
func _draw_dash_glyph(center: Vector2, outer_radius: float, color: Color) -> void:
	var half_w := outer_radius * GLYPH_WIDTH_RATIO * 0.5
	var half_h := outer_radius * GLYPH_HEIGHT_RATIO * 0.5
	if half_w <= 1.5 or half_h <= 1.5:
		return
	var stroke := maxf(1.2, outer_radius * GLYPH_STROKE_RATIO)
	# 闭合三角形：左上 → 右尖 → 左下 → 左上。
	var points := PackedVector2Array([
		center + Vector2(-half_w, -half_h),
		center + Vector2(half_w, 0.0),
		center + Vector2(-half_w, half_h),
		center + Vector2(-half_w, -half_h),
	])
	draw_polyline(points, color, stroke, true)
