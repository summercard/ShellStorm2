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
## ## 位置（2026-11-10 第二轮修订）
## 第一版落在左上角角色状态块里（血条下方），业主原话：「翻滚提示放在那个位置也太难看见了，
## 放到左下角来」。现在锚**屏幕左下角**，直径按业主标注的红框放大到 60 设计 px
## （×0.8 ⇒ 48 canvas px，原 22.4 ⇒ 是原来的 2.14 倍）。
##
## ## 读数方向与换弹环 / 倒计时环一致
## 起点 12 点、顺时针。但本环填的是**已恢复量**（换弹环同口径），不是剩余量 ——
## 冷却越接近结束，弧越长；满圈 = 可以翻滚。与倒计时环（画剩余量）刻意相反：
## 倒计时的直觉是"这一圈在缩短"，而冷却的直觉是"这一圈在充满"。

## 剪影形状来自真实角色翻滚帧，见该文件头。用 `preload` 而不是 `class_name`：
## 后者依赖全局类缓存，干净克隆/纯命令行下解析不到。
const HUD_DASH_GLYPH_SCRIPT := preload("res://src/ui/HudDashGlyph.gd")

## 环带线宽 ÷ 外半径。与 `HudReloadRing.THICKNESS_RATIO` 同值 —— 同为"操作反馈环"。
const THICKNESS_RATIO := 0.13
## 分段数。外径 48 canvas px 级，64 段足够平滑。
const SEGMENTS := 64
## 屏幕空间起点：12 点方向（屏幕 +Y 向下 ⇒ 12 点是 −90°；顺时针 = 角度递增）。
const START_ANGLE := -PI * 0.5
## 底轨。弱白，只表明"这里有一圈"。
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.13)
## 冷却中：天蓝强调（`UIPalette.PRISM_ACCENT`）压 alpha —— 语义是"进度填充"。
const FILL_COLOR := Color(0.310, 0.659, 1.0, 0.72)
## 就绪：近白（`UIPalette.PRISM_TEXT`）。蓝→白的切换本身就是"可用"的信号，
## 不需要文字，也不需要第二个图形。
const READY_COLOR := Color(0.949, 0.965, 0.984, 0.88)
const GLOW_COLOR := Color(0.200, 0.520, 0.900, 0.30)
const GLOW_WIDTH_RATIO := 1.7
## 就绪瞬间的一次外环提亮时长（秒）。是"反馈"不是"入场动画"，所以不做缩放与回弹。
const READY_FLASH_SEC := 0.24
## 环心兔子剪影：占**环直径**的比例。
## 上限由净空决定：环带内缘半径 = 0.5 × (1 − 0.13) = 0.435 直径，
## 剪影按最长边铺满 ⇒ 半宽最多 0.435 直径才能不碰环带，留 8% 余量取 0.66。
const GLYPH_FIT_RATIO := 0.66
## 冷却中剪影的亮度。业主原话是「**白色**剪影」，所以两种状态都白 ——
## 状态色只由外圈那道弧承担（天蓝 = 冷却中 / 近白 = 就绪）。
## 冷却时压到 0.58 让"还不能翻滚"读得出来，但形状本身仍是白的。
const GLYPH_COOL_COLOR := Color(0.949, 0.965, 0.984, 0.58)
const GLYPH_READY_COLOR := Color(0.949, 0.965, 0.984, 0.94)

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
	# 兔子剪影用自己那档色：冷却中是天蓝系（与弧同族、压暗，不抢弧的读数），
	# 就绪转近白。不直接用 `ring_color` —— 弧的 alpha 是给 1.46~3 px 细线调的，
	# 铺到一整块剪影上会显得过淡。
	_draw_dash_glyph(
		center, outer_radius, GLYPH_READY_COLOR if is_ready() else GLYPH_COOL_COLOR
	)


## 环心兔子剪影。形状来自真实角色翻滚帧（见 `HudDashGlyph.gd` 的文件头），
## 不是手画图标；这里是纯多边形填充，不用位图。
##
## ## 为什么要「填充 + 再描一圈抗锯齿边」
## `draw_colored_polygon` 走的是**硬边光栅化**，没有 `antialiased` 参数 ——
## 48 px 的环里贴一块 30 px 的剪影，边缘会是一排明显的台阶（实拍确认）。
## 在填充之后再沿同一条轮廓 `draw_polyline(..., antialiased = true)` 补一圈 1 px 的
## 同色描边，台阶就被半透明像素抹平了；成本是多一遍折线，形状与颜色完全一致。
func _draw_dash_glyph(center: Vector2, outer_radius: float, color: Color) -> void:
	var glyph_span := outer_radius * 2.0 * GLYPH_FIT_RATIO
	if glyph_span <= 3.0:
		return
	for polygon in HUD_DASH_GLYPH_SCRIPT.DASH_GLYPH_POLYGONS:
		var source := polygon as PackedVector2Array
		if source.size() < 3:
			continue
		# 描边要闭合，所以多留一个点放回首点。
		var points := PackedVector2Array()
		points.resize(source.size() + 1)
		for index in range(source.size()):
			points[index] = center + source[index] * glyph_span
		points[source.size()] = points[0]
		# 凹多边形必须走 `draw_colored_polygon`（内部三角剖分）；
		# `draw_polyline` 只能画线框，填不出剪影。
		draw_colored_polygon(points, color)
		draw_polyline(points, color, 1.0, true)
