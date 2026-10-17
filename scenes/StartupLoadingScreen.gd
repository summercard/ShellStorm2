extends CanvasLayer
class_name StartupLoadingScreen
## 启动外壳：先给玩家一个明确的启动画面，再把主场景推进去。
##
## 这里只负责视觉反馈与一次性切场景，不读取、不消费、不写入任何存档，
## 不参与 GameEntryFlow，也不改变目的场景的出生、恢复和开始菜单逻辑 ——
## 包括「新档要不要放开场影片」那个判断，那是 TowerDescent3D 的事。
##
## ⚠️ 为什么必须后台预加载而不是 `change_scene_to_file()` 直接切：
## 主场景在真实存档下的启动实测 8～12 秒（见 MODULE_INDEX 的启动卡顿诊断）。
## 同步切换会让进度条停在 100% 冻住十几秒，然后画面硬跳 —— 而新档开场影片
## 正是要接在这段之后，玩家会以为"卡死了、动画没了"。所以这里把加载搬到
## 后台线程，进度条读真实进度，加载与最短展示时间都满足才切。
##
## ⚠️ 版式（2026-10-17 主人指定）：
## **只有名字 + 进度条，纯黑底，零装饰。** 名字与进度条**同角度斜置**（-13°）。
##
## 视觉基调沿用主面板的棱镜线框语言 —— 近白字、深墨底、方角、无渐变、无卡片；
## 在此之上按主人要求叠一层**赛博色散**：粉/青 RGB 分离 + 边缘故障带。
## 色散是本屏唯一允许的"辉光类"效果，只服务于启动壳的压迫感，不进 HUD 体系。

const TARGET_SCENE := "res://scenes/TowerDescent3D.tscn"
const MIN_DISPLAY_SECONDS := 1.10

# ========== 版式常量（设计基准 1280×720，与 project.godot 的 viewport 一致） ==========
## ⚠️ 只用**统一缩放系数**，不做分轴缩放：旋转过的图形一旦按 x/y 分别缩放，
## 角度会被拉歪（宽屏上 -13° 就不会是 -13°）。等比缩放是保住角度不变形的唯一办法。
const DESIGN_SIZE := Vector2(1280.0, 720.0)

## 名字是屏幕上唯一的主角：140px ≈ 1/5 屏高。
const TITLE_TEXT := "弹壳风暴2"
const TITLE_FONT_SIZE := 140.0
## 整块名字的摆放角（度）。负值 = 逆时针 = 右端抬高。
## **进度条共用同一个角度** —— 主人要的是"名字和条一起歪"。
const TITLE_ROTATION_DEG := -13.0
## 字形自身的斜切（tan 值）。中文竖笔多，整块已经斜了，字形再斜一次会散，故留 0。
const TITLE_SKEW := 0.0
const TITLE_TRACKING := 8
## 旋转中心高度比例：略高于画面正中，上方留白多、视线自然下压到进度条。
const TITLE_CENTER_RATIO := 0.428

## 进度条：跟着名字一起斜。
## 宽度是**字块宽度的比例**（不是屏宽）—— 挂屏宽时条会甩出字块右端，看着跟名字不是一体。
const BAR_WIDTH_OF_TEXT := 0.72
const BAR_HEIGHT := 7.0
## 条相对字块底沿的下沉距离（设计基准像素）。
const BAR_GAP := 40.0

## 全屏底色：近黑，带一点冷调（棱镜深墨，但不是纯黑，保留屏幕质感）。
const BACKDROP_COLOR := Color(0.024, 0.032, 0.043, 1.0)

# ========== 赛博色散 ==========
## 品红 / 青 双色。经典 RGB split 的 R 与 B 通道替身。
const CHROMA_PINK := Color(1.0, 0.239, 0.616, 1.0)
const CHROMA_CYAN := Color(0.133, 0.902, 1.0, 1.0)
## 色散偏移（设计基准像素）。粉走左上、青走右下，形成对角分离。
const CHROMA_OFFSET := 4.2
## 色散层的 base alpha：太高会盖住白主体，太低看不见。
const CHROMA_ALPHA := 0.88

## 边缘故障带参数。
const EDGE_BAND_PX := 54.0
const EDGE_BAND_ALPHA := 0.17
const EDGE_BAND_STEPS := 16
## 故障碎片刷新间隔（秒）；每次刷新自带随机数量/位置，避免机械节拍。
const GLITCH_INTERVAL := 0.46
const GLITCH_FRAG_MIN := 10
const GLITCH_FRAG_MAX := 18

var _elapsed := 0.0
var _advanced := false
var _transition_requested := false
var _failed := false
## 数据载体：**视觉已改为自绘斜条**，这个 ProgressBar 只保留数值与节点路径
## （`Root/Progress`），并 `visible = false` —— 任何按节点路径读进度的探针都不会坏。
var _progress: ProgressBar
## 只在启动失败时才显示 —— 正常路径上它是隐藏的，不占版面。
var _status_label: Label
var _title_art: Control
var _edge_art: Control

var _load_requested := false
var _load_done := false
var _load_failed := false
var _load_progress := 0.0
var _target_scene: PackedScene
var _title_font_cache: FontVariation

# 故障带状态
var _rng := RandomNumberGenerator.new()
var _glitch_timer := 0.0
var _glitch_frags: Array = []
var _scan_phase := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 0x5E115702
	_build_ui()
	_refresh_glitch()
	if _should_skip_delay():
		_enter_game()
		return
	_request_target_load()


func _process(delta: float) -> void:
	_animate_fx(delta)
	if _advanced or _failed:
		return
	_elapsed += delta
	_poll_target_load()
	_update_ui()
	if _load_failed:
		# 预加载失败不等于游戏起不来：退回同步切换，让目的场景自己报错。
		_transition_requested = true
		call_deferred("_change_to_target_scene")
		return
	if _load_done and _elapsed >= MIN_DISPLAY_SECONDS:
		_enter_game()


func _should_skip_delay() -> bool:
	return DisplayServer.get_name() == "headless" or Engine.is_editor_hint()


## 后台预加载主场景。
## ⚠️ `use_sub_threads` 必须为 **false**：传 true 时 `load_threaded_get` 拿到的
## PackedScene 在 `change_scene_to_packed()` 实例化阶段会报
## `Node './floor_01' was modified from inside an instance, but it has vanished`
## （主场景内含 5 个 floor 实例化子场景），并伴随引擎段错误 —— 实测基线
## 零警告零崩溃、开 sub-threads 后必崩，故这里只走「主线程后台加载」这一条安全路径。
func _request_target_load() -> void:
	var error: Error = ResourceLoader.load_threaded_request(TARGET_SCENE, "", false)
	if error != OK:
		push_warning(
			"[StartupLoadingScreen] 后台预加载不可用（%s），退回同步切换" % error_string(error)
		)
		_load_failed = true
		return
	_load_requested = true


func _poll_target_load() -> void:
	if not _load_requested or _load_done or _load_failed:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				_load_progress = clampf(float(progress[0]), 0.0, 1.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			_target_scene = ResourceLoader.load_threaded_get(TARGET_SCENE) as PackedScene
			if _target_scene == null:
				_load_failed = true
				return
			_load_progress = 1.0
			_load_done = true
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_load_failed = true


func _enter_game() -> void:
	if _advanced or _failed:
		return
	_advanced = true
	_transition_requested = true
	call_deferred("_change_to_target_scene")


func _change_to_target_scene() -> void:
	if not _transition_requested or _failed:
		return
	_transition_requested = false
	var error: Error = OK
	if _target_scene != null:
		error = get_tree().change_scene_to_packed(_target_scene)
	else:
		error = get_tree().change_scene_to_file(TARGET_SCENE)
	if error != OK:
		_failed = true
		if _status_label != null:
			_status_label.text = "启动失败：%s" % error_string(error)
			_status_label.visible = true
		push_error("[StartupLoadingScreen] 进入主场景失败: %s" % error_string(error))


func _update_ui() -> void:
	var time_ratio := clampf(_elapsed / MIN_DISPLAY_SECONDS, 0.0, 1.0)
	# 两个下限取大：加载慢时显示真实进度，加载快时按最短展示时间平滑推到 100%，
	# 两者都单调不减，进度条不会回跳。
	var ratio := maxf(_load_progress, time_ratio)
	if _progress != null:
		_progress.value = ratio * 100.0
	# 视觉条是自绘的，不吃 ProgressBar 的样式，所以数值变化后必须手动重绘。
	if _title_art != null:
		_title_art.queue_redraw()


# ========== 故障带动画 ==========

func _animate_fx(delta: float) -> void:
	_scan_phase = fmod(_scan_phase + delta * 0.22, 1.0)
	_glitch_timer += delta
	if _glitch_timer >= GLITCH_INTERVAL:
		_glitch_timer = 0.0
		_refresh_glitch()
	if _edge_art != null:
		_edge_art.queue_redraw()


## 重新掷一批故障碎片。RNG 用固定 seed，所以每次运行图案一致、可复现，
## 不会出现"这次特别花"的不稳定观感。
func _refresh_glitch() -> void:
	_glitch_frags.clear()
	var count := _rng.randi_range(GLITCH_FRAG_MIN, GLITCH_FRAG_MAX)
	for i in count:
		var side := _rng.randi_range(0, 3)
		var pink := _rng.randf() < 0.5
		var color := CHROMA_PINK if pink else CHROMA_CYAN
		# 四分之三给"细长撕裂"，四分之一给"厚短线"，制造粗细对比。
		var thin := _rng.randf() < 0.75
		var thickness := _rng.randf_range(1.0, 2.5) if thin else _rng.randf_range(3.0, 7.0)
		var length := _rng.randf_range(46.0, 280.0) if thin else _rng.randf_range(18.0, 70.0)
		var inset := _rng.randf_range(0.0, EDGE_BAND_PX)
		var t := _rng.randf_range(0.04, 0.96)
		var alpha := _rng.randf_range(0.30, 0.85)
		var rect := Rect2()
		match side:
			0:  # 左
				rect = Rect2(inset, t * DESIGN_SIZE.y, thickness, length)
			1:  # 右
				rect = Rect2(DESIGN_SIZE.x - inset - thickness, t * DESIGN_SIZE.y, thickness, length)
			2:  # 上
				rect = Rect2(t * DESIGN_SIZE.x, inset, length, thickness)
			_:  # 下
				rect = Rect2(t * DESIGN_SIZE.x, DESIGN_SIZE.y - inset - thickness, length, thickness)
		_glitch_frags.append({"rect": rect, "color": color, "alpha": alpha})


# ========== 构建 ==========

func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = BACKDROP_COLOR
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	# 边缘故障带压在字之下：它属于"屏幕本身的噪声"，不该盖住内容。
	_edge_art = Control.new()
	_edge_art.name = "EdgeFx"
	_edge_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_art.draw.connect(_draw_edge_fx.bind(_edge_art))
	_edge_art.resized.connect(_edge_art.queue_redraw)
	root.add_child(_edge_art)

	# 名字 + 进度条画在同一张自绘层里：它们共用一套旋转坐标系，
	# 分成两个节点反而要在两处重复算同一个变换，迟早对不齐。
	_title_art = Control.new()
	_title_art.name = "TitleArt"
	_title_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_art.draw.connect(_draw_title.bind(_title_art))
	_title_art.resized.connect(_title_art.queue_redraw)
	root.add_child(_title_art)

	# 数值载体。路径 `Root/Progress` 保持不变，但视觉不归它管。
	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.visible = false
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_progress)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.visible = false
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.anchor_left = 0.0
	_status_label.anchor_right = 1.0
	_status_label.anchor_top = 0.86
	_status_label.anchor_bottom = 0.86
	_status_label.offset_top = 0.0
	_status_label.offset_bottom = 26.0
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyleFactory.apply_prism_label(_status_label, "danger", 2, 15)
	root.add_child(_status_label)


# ========== 名字 + 进度条（同一套旋转坐标系） ==========

## 名字字形链。
## ⚠ 必须把**中文字体排在前面**：`SystemFont` 按 `font_names` 顺序取系统里第一个存在的族，
## 若把 Impact / Arial Black 放在前面，标题的「弹壳风暴」会落到没有中文字形的族上，
## 再靠逐字回退去补 —— 那样字重和字面宽度都会跟「2」不一致。所以这里先锁中文黑体。
func _title_font_families() -> PackedStringArray:
	return PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Source Han Sans SC",
		"Source Han Sans CN",
		"Noto Sans CJK SC",
		"Noto Sans SC",
		"PingFang SC",
		"Hiragino Sans GB",
		"sans-serif",
	])


func _title_font() -> FontVariation:
	if _title_font_cache != null:
		return _title_font_cache
	var system := SystemFont.new()
	system.font_names = _title_font_families()
	system.font_weight = 800
	var variation := FontVariation.new()
	variation.base_font = system
	variation.spacing_glyph = TITLE_TRACKING
	if not is_zero_approx(TITLE_SKEW):
		variation.variation_transform = Transform2D(
			Vector2(1.0, 0.0), Vector2(-TITLE_SKEW, 1.0), Vector2.ZERO
		)
	_title_font_cache = variation
	return _title_font_cache


## 统一缩放系数。只取各轴比值的**较小值**，保证旋转角度不被拉变形。
func _ui_scale(box: Vector2) -> float:
	if box.x < 1.0 or box.y < 1.0:
		return 0.0
	return minf(box.x / DESIGN_SIZE.x, box.y / DESIGN_SIZE.y)


## 画名字 + 进度条。
##
## ⚠ 斜着摆用 `draw_set_transform(中心, 角度, 1)` **绕字块中心旋转**，不是节点 `rotation`：
##   节点旋转会把子控件排版盒一起带走；绕中心旋转天然保持居中，不用补任何位移。
## ⚠ 进度条在同一旋转坐标系里画，所以它跟名字**严丝合缝地同角度**。
##   条在局部坐标里仍是水平矩形 —— 它是被坐标系带歪的，不是自己斜的。
## ⚠ 画完必须复位 transform，否则后续绘制会跟着歪。
func _draw_title(art: Control) -> void:
	var font := _title_font()
	if font == null:
		return
	var box := art.size
	var s := _ui_scale(box)
	if s <= 0.0:
		return
	var font_size := maxi(24, int(round(TITLE_FONT_SIZE * s)))
	var text_size := font.get_string_size(TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var center := Vector2(box.x * 0.5, box.y * TITLE_CENTER_RATIO)

	# 字块视觉中线在局部原点；baseline 在 +(ascent-descent)/2 处。
	var origin := Vector2(-text_size.x * 0.5, (ascent - descent) * 0.5)
	var block_bottom := (ascent + descent) * 0.5

	art.draw_set_transform(center, deg_to_rad(TITLE_ROTATION_DEG), Vector2.ONE)

	# ---- 名字：粉 / 青 色散 + 白色主体 ----
	# 粉走左上、青走右下；白主体居中压在两者之间。
	var offset := CHROMA_OFFSET * s
	art.draw_string(
		font, origin + Vector2(-offset, -offset * 0.42), TITLE_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(CHROMA_PINK.r, CHROMA_PINK.g, CHROMA_PINK.b, CHROMA_ALPHA)
	)
	art.draw_string(
		font, origin + Vector2(offset, offset * 0.42), TITLE_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(CHROMA_CYAN.r, CHROMA_CYAN.g, CHROMA_CYAN.b, CHROMA_ALPHA)
	)
	art.draw_string(
		font, origin, TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		UIPalette.PRISM_TEXT
	)

	# ---- 进度条：同一坐标系，同角度 ----
	# 左端与字块左缘对齐（而不是居中）：条是名字的"底座"，对齐才像一体。
	var bar_w := text_size.x * BAR_WIDTH_OF_TEXT
	var bar_h := BAR_HEIGHT * s
	var bar_top := block_bottom + BAR_GAP * s
	var bar_left := origin.x
	var ratio := 0.0
	if _progress != null and _progress.max_value > 0.0:
		ratio = clampf(_progress.value / _progress.max_value, 0.0, 1.0)

	# 空槽：极淡底 + 1px 白描边（棱镜语义件）。底要能看见，否则读不出"还剩多少"。
	art.draw_rect(Rect2(bar_left, bar_top, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.10), true)
	art.draw_rect(
		Rect2(bar_left, bar_top, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.34), false, 1.0 * s
	)

	var fill_w := bar_w * ratio
	if fill_w > 0.5:
		# 细长条上色散偏移减半 —— 用满偏移会把条缝成三条平行线，读不出进度。
		var bar_offset := CHROMA_OFFSET * 0.55 * s
		art.draw_rect(
			Rect2(bar_left + bar_offset, bar_top + bar_offset * 0.42, fill_w, bar_h),
			Color(CHROMA_PINK.r, CHROMA_PINK.g, CHROMA_PINK.b, CHROMA_ALPHA * 0.85), true
		)
		art.draw_rect(
			Rect2(bar_left - bar_offset, bar_top - bar_offset * 0.42, fill_w, bar_h),
			Color(CHROMA_CYAN.r, CHROMA_CYAN.g, CHROMA_CYAN.b, CHROMA_ALPHA * 0.85), true
		)
		art.draw_rect(Rect2(bar_left, bar_top, fill_w, bar_h), UIPalette.PRISM_TEXT, true)
		# 进度头：一小段纯白亮块，让"推进到哪"在斜条上一眼可读。
		var head_w := minf(6.0 * s, fill_w)
		art.draw_rect(
			Rect2(bar_left + fill_w - head_w, bar_top, head_w, bar_h),
			Color(1.0, 1.0, 1.0, 1.0), true
		)

	art.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ========== 边缘故障带 ==========

## 屏幕四周的赛博干扰。分三层：
##   1. 四边粉/青晕带：逐条细线叠出向内衰减的"渗色"，左粉右青、上下混色。
##   2. 随机故障碎片：拉扯的撕裂条，每 0.46s 重掷一批。
##   3. 下行扫描亮带：全屏 CRT 感，用 sin 在首尾淡出。
##
## 三层都压在内容之下，alpha 合计很低 —— 干扰是"屏在抖"，不是"画面糊了"。
func _draw_edge_fx(art: Control) -> void:
	var box := art.size
	var s := _ui_scale(box)
	if s <= 0.0:
		return
	var band := EDGE_BAND_PX * s
	var step := band / float(EDGE_BAND_STEPS)

	# 1) 边缘晕带。alpha 随内进距离二次衰减，边缘最浓、往里迅速散掉。
	for i in EDGE_BAND_STEPS:
		var t := float(i) / float(EDGE_BAND_STEPS)
		var a := EDGE_BAND_ALPHA * (1.0 - t) * (1.0 - t)
		var d := t * band
		# 左（粉）
		art.draw_rect(
			Rect2(d, 0.0, step, box.y),
			Color(CHROMA_PINK.r, CHROMA_PINK.g, CHROMA_PINK.b, a), true
		)
		# 右（青）
		art.draw_rect(
			Rect2(box.x - d - step, 0.0, step, box.y),
			Color(CHROMA_CYAN.r, CHROMA_CYAN.g, CHROMA_CYAN.b, a), true
		)
		# 上（青，弱一档）
		art.draw_rect(
			Rect2(0.0, d, box.x, step),
			Color(CHROMA_CYAN.r, CHROMA_CYAN.g, CHROMA_CYAN.b, a * 0.55), true
		)
		# 下（粉，弱一档）
		art.draw_rect(
			Rect2(0.0, box.y - d - step, box.x, step),
			Color(CHROMA_PINK.r, CHROMA_PINK.g, CHROMA_PINK.b, a * 0.55), true
		)

	# 2) 故障碎片
	for frag in _glitch_frags:
		var r: Rect2 = frag["rect"]
		var c: Color = frag["color"]
		var a: float = frag["alpha"]
		art.draw_rect(
			Rect2(r.position.x * s, r.position.y * s, r.size.x * s, r.size.y * s),
			Color(c.r, c.g, c.b, a), true
		)

	# 3) 下行扫描亮带
	var scan_y := _scan_phase * box.y
	var scan_h := 3.0 * s
	var fade := sin(_scan_phase * PI)
	art.draw_rect(
		Rect2(0.0, scan_y, box.x, scan_h),
		Color(CHROMA_CYAN.r, CHROMA_CYAN.g, CHROMA_CYAN.b, 0.10 * fade), true
	)
	art.draw_rect(
		Rect2(0.0, scan_y + scan_h, box.x, scan_h * 2.0),
		Color(CHROMA_PINK.r, CHROMA_PINK.g, CHROMA_PINK.b, 0.045 * fade), true
	)
