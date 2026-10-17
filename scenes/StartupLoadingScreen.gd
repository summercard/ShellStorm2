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
## 在此之上按主人要求叠一层**赛博色散**（粉/青 RGB 分离）。
## 色散是本屏唯一允许的"辉光类"效果，只服务于启动壳的压迫感，不进 HUD 体系。
##
## ⚠️ 无任何画面边缘特效。名字大到撑爆画幅、允许被屏幕边缘切掉 —— 那是构图，不是装饰。

const TARGET_SCENE := "res://scenes/TowerDescent3D.tscn"
const MIN_DISPLAY_SECONDS := 1.10

# ========== 版式常量（设计基准 1280×720，与 project.godot 的 viewport 一致） ==========
## ⚠️ 只用**统一缩放系数**，不做分轴缩放：旋转过的图形一旦按 x/y 分别缩放，
## 角度会被拉歪（宽屏上 -13° 就不会是 -13°）。等比缩放是保住角度不变形的唯一办法。
const DESIGN_SIZE := Vector2(1280.0, 720.0)

## 名字是屏幕上唯一的主角 —— **大到撑爆画面**。
## 260px 时旋转后的视觉包围盒约 1302×608，横向超出 1280 画幅约 22px：
## 左右各切掉约 11px（只有笔画边角出画），既撑满画幅又保住名字完整可读。
## 这是刻意的构图 —— 压满画幅才有压迫感；但**不能切到认不出名字**，
## 想更狠可推到 290（会真切掉字形），但那开始牺牲可读性 —— 这一步是分寸，不是极限。
const TITLE_TEXT := "弹壳风暴2"
const TITLE_FONT_SIZE := 260.0
## 整块名字的摆放角（度）。负值 = 逆时针 = 右端抬高。
## **进度条共用同一个角度** —— 主人要的是"名字和条一起歪"。
const TITLE_ROTATION_DEG := -13.0
## 字形自身的斜切（tan 值）。中文竖笔多，整块已经斜了，字形再斜一次会散，故留 0。
const TITLE_SKEW := 0.0
const TITLE_TRACKING := 8
## 旋转中心高度比例。字撑爆后必须**略高于正中**：
## 居中会让字块下沿顶到屏幕底，进度条无处安放。0.42 让标题顶部微出画（约 10px）、
## 底部留出约 66px 给进度条。
const TITLE_CENTER_RATIO := 0.42

## 进度条：跟着名字一起斜。
## 宽度是**字块宽度的比例**（不是屏宽）—— 挂屏宽时条会甩出字块右端，看着跟名字不是一体。
## 字撑爆后条不能用 0.72 长（会跟着斜出画）：0.34 且**锚字块下中**，
## 才能在斜置后的底部空带里完整可见、不被左右边缘切掉。
const BAR_WIDTH_OF_TEXT := 0.34
const BAR_HEIGHT := 8.0
## 条相对字块底沿的下沉距离（设计基准像素）。
## 字撑爆后紧贴字沿会把条"吸"进字里，36 才让它在底部空带里独立成立。
const BAR_GAP := 36.0

## 全屏底色：近黑，带一点冷调（棱镜深墨，但不是纯黑，保留屏幕质感）。
## 它只是**最底一层**；上面压着色块构成层（见 `_draw_scheme`）。
const BACKDROP_COLOR := Color(0.024, 0.032, 0.043, 1.0)

# ========== 色块构成背景（黑底 + 多方向碎切） ==========
## 主色四件套：玫红 / 绿 / 蓝 / 黑。**黑是主角**，占画面 65%；
## 彩色只负责"闪"，不负责"铺满"。形只切几刀，剩下全是空。
const SCHEME_PINK := Color(1.0, 0.176, 0.494, 1.0)
const SCHEME_GREEN := Color(0.008, 0.902, 0.463, 1.0)
const SCHEME_BLUE := Color(0.114, 0.416, 1.0, 1.0)
const SCHEME_BLACK := Color(0.024, 0.032, 0.043, 1.0)

## 面积配额（主人指定基准）：鲜艳 30% / 撞色 5%。**这是 f0 那帧的基准值**，
## 不是所有帧的统一值 —— 主人要求"部分画面的比例可以鲜艳色彩降到 10% 以下"，
## 所以每帧的鲜艳占比在 0%~30% 之间浮动（见 `FRAME_SPECS`，每帧实测写在注释里）。
const VIVID_TARGET := 0.30
const CLASH_TARGET := 0.05

## 碎切形状池（设计基准 1280×720 坐标）。
##
## ⚠ **十块鲜艳形状 + 两块撞色形状，角度互不相同，且全部离开名字的 -13°**。
## 上一版让切线和名字同角度，结果是"速度线"——所有线平行，读起来是冲刺感。
## 这一版要的是**紊乱**：角度互相打断、大小悬殊、位置不构成任何韵律。
##
## 池化而不是每帧手写顶点：每帧用索引挑子集（见 `FRAME_SPECS`），
## 于是"更多帧"是加一行索引，不是复制一套坐标。
##
## 各块单独面积（鞋带公式，围绕 1280×720 全屏，`measure_area_share()` 可复算）：
##   0 A ~72°   9.77%      6 G ~+15°   1.35%
##   1 B ~-32°   8.33%      7 H ~-55°   0.74%
##   2 C ~-62°   2.66%      8 I ~+80°   0.57%
##   3 D ~+38°   1.60%      9 J ~-38°   0.66%
##   4 E ~-48°   1.45%     10 X ~-17°   3.82%（撞色专用，细长）
##   5 F ~-20°   1.24%     11 Y ~+72°   1.14%（撞色专用，陡块）
const PIECE_POOL: Array = [
	# 0 A 陡竖切 ~72°：最大的一块，从左上压下来。**宽度是按"不能让黑失去主体地位"定的** ——
	# 更宽的话满帧彩色会超过 30%，黑就被切成缝了（实测过 14% 版：视觉上黑反而不是主角）。
	[Vector2(0, 0), Vector2(90, 0), Vector2(186, 720), Vector2(26, 720)],
	# 1 B 缓横 ~-32°：横贯右下，与 A 几乎垂直
	[Vector2(760, 520), Vector2(1280, 368), Vector2(1280, 506), Vector2(812, 676)],
	# 2 C 陡对角 ~-62°：贴右上角切一刀
	[Vector2(1144, 0), Vector2(1280, 0), Vector2(1280, 258), Vector2(1222, 250)],
	# 3 D 反斜 ~+38°：方向是"反的"，专门打架
	[Vector2(486, 720), Vector2(710, 576), Vector2(774, 642), Vector2(556, 720)],
	# 4 E 三角 ~-48°：三角，破掉其余块的四边形节奏
	[Vector2(430, 0), Vector2(606, 0), Vector2(430, 152)],
	# 5 F 小块 ~-20°：孤立在右中，不让画面只靠边缘
	[Vector2(878, 118), Vector2(1016, 92), Vector2(1034, 172), Vector2(898, 198)],
	# 6 G 近乎水平 ~+15°：贴近底部的扁条
	[Vector2(120, 470), Vector2(360, 520), Vector2(352, 570), Vector2(112, 520)],
	# 7 H 陡竖 ~-55°：顶部小尖条
	[Vector2(700, 60), Vector2(760, 44), Vector2(790, 150), Vector2(730, 166)],
	# 8 I 近乎竖 ~+80°：底部右下的小方块
	[Vector2(960, 600), Vector2(1010, 596), Vector2(1024, 700), Vector2(974, 704)],
	# 9 J 斜 ~-38°：左中偏上
	[Vector2(200, 300), Vector2(330, 270), Vector2(342, 314), Vector2(212, 344)],
	# 10 X 撞色长条 ~-17°：横跨左中，能读成"一整刀"
	[Vector2(268, 250), Vector2(600, 168), Vector2(624, 268), Vector2(292, 350)],
	# 11 Y 撞色陡块 ~+72°：右下，与 X 不成平行
	[Vector2(1046, 392), Vector2(1128, 368), Vector2(1156, 488), Vector2(1074, 512)],
]

## 八个闪切帧。每帧 = {vivid: 形状索引数组, clash: 索引数组, colors: [鲜艳色, 撞色]}。
##
## **比例是逐帧不同的**，不是每帧都 30%。主人明确要求"部分画面的比例可以鲜艳色彩降到 10% 以下"，
## 并且"比例可以多一些" —— 八帧覆盖 0% / 6.66% / 8.33% / 11.79% / 12.58% / 15.37% / 19.44% / 25.05%。
## 由小到大、大、中、小、熄灯，观感是呼吸而不是匀速闪。
##
## 实测占比（`measure_area_share()` 会逐帧打印，以它为准）：
##   f0 鲜艳 25.05% + 撞色 4.96%  → 黑 70.00%   ← 最满的一帧
##   f1 鲜艳  8.33% + 撞色 3.82%  → 黑 87.85%   ← 降到 10% 以下
##   f2 鲜艳 15.37% + 撞色 1.14%  → 黑 83.49%
##   f3 鲜艳  6.66% + 撞色 4.96%  → 黑 88.38%   ← 降到 10% 以下
##   f4 鲜艳 19.44% + 撞色 3.82%  → 黑 76.74%
##   f5 鲜艳 12.58% + 撞色 3.82%  → 黑 83.61%
##   f6 鲜艳 11.79% + 撞色 1.14%  → 黑 87.07%
##   f7 鲜艳  0.00% + 撞色 1.14%  → 黑 98.86%   ← 黑场
## **黑每帧都在 70% 以上** —— 这是"主要颜色还是黑色"的可核对定义，不是形容词。
const FRAME_SPECS: Array = [
	{"vivid": [0, 1, 2, 3, 4, 5], "clash": [10, 11], "colors": [SCHEME_PINK, SCHEME_GREEN]},
	{"vivid": [1], "clash": [10], "colors": [SCHEME_BLUE, SCHEME_PINK]},
	{"vivid": [0, 2, 3, 6], "clash": [11], "colors": [SCHEME_GREEN, SCHEME_BLUE]},
	{"vivid": [2, 4, 5, 7, 8], "clash": [10, 11], "colors": [SCHEME_PINK, SCHEME_BLUE]},
	{"vivid": [0, 1, 6], "clash": [10], "colors": [SCHEME_BLUE, SCHEME_GREEN]},
	{"vivid": [1, 3, 5, 7, 9], "clash": [10], "colors": [SCHEME_GREEN, SCHEME_PINK]},
	{"vivid": [0, 4, 8], "clash": [11], "colors": [SCHEME_PINK, SCHEME_GREEN]},
	{"vivid": [], "clash": [11], "colors": [null, SCHEME_BLUE]},
]

## 单帧时长（秒）。主人指定 **0.1–0.2 s**，取 0.15。
##
## ⚠ 闪切已与律动拍**解耦**：律动仍是 138 BPM（每拍 0.435 s）驱动字的抖动，
## 背景换成 0.15 s 一帧。两者不再锁同一个时钟 —— 这是刻意的：
## 主人先要"跟着音乐切"，后又明确要"0.1–0.2 s、帧数更多"，
## 而 138 BPM 的一拍就是 0.435 s，物理上不可能又快又锁拍。
## 现在的观感是"字在按鼓点震、背景在更快的频率上闪"，两套节奏叠在一起更躁。
const FLASH_SECONDS := 0.15
## 帧数。八帧一轮 = 1.2 s。
const FRAME_COUNT := 8

## 每帧的镜像组合 `[flip_x, flip_y]`。
##
## ⚠ **形状不换、落点全换**：镜像不改变任何碎片的面积，所以每帧的比例恒定成立；
## 但同一组碎片的落点全变了，观感是"每次切法都不同"。
## 真去手写八套顶点，迟早有一套面积对不上，而且改起来是八倍工作量。
const FRAME_FLIPS: Array = [
	[false, false], [true, false], [false, true], [true, true],
	[false, false], [true, false], [false, true], [true, true],
]

# ========== 赛博色散 ==========
## 品红 / 青 双色。经典 RGB split 的 R 与 B 通道替身。
const CHROMA_PINK := Color(1.0, 0.239, 0.616, 1.0)
const CHROMA_CYAN := Color(0.133, 0.902, 1.0, 1.0)
## 色散偏移（设计基准像素）。粉走左上、青走右下，形成对角分离。
const CHROMA_OFFSET := 3.6
## 色散层的 base alpha：太高会盖住白主体，太低看不见。
const CHROMA_ALPHA := 0.88

## 名字的深色描边宽度（设计基准像素）。
## 背景改成多色色块后，白字压亮色块会糊 —— 这层描边是可读性刚需，不是装饰。
## 取值：字高 260px 时 5px ≈ 2% 字高，够把轮廓抠出来又不至于变成"粗边字"。
const OUTLINE_PX := 5.0
## 描边色：比黑底更深的近黑（不是纯黑 —— 纯黑在多色背景上像"挖洞"）。
const OUTLINE_COLOR := Color(0.012, 0.016, 0.022, 1.0)

# ========== 朋克律动 ==========
## 名字不是静止的：它跟着一个**虚拟鼓点**在抖。
## 三层叠出来的"音乐颤抖"，从细到粗：
##   1. 常驻微颤 —— 设备通电的嗡鸣，恒定小幅、频率高，是底噪不是主角；
##   2. 节拍冲击 —— 每拍一次，方向按拍重新掷，幅度随拍内衰减，像被人一拳一拳顶；
##   3. 强拍重音 —— 每小节第一拍额外一次横向错位，色散同时炸开。
## 三层必须都故意错开频率（别用 2 的倍数），否则会合成一条规律的波浪，立刻变成"呼吸"
## 而不是"颤动"。这是这类效果最容易翻车的地方。
##
## 节拍速度 138 BPM ≈ 每拍 0.435 s：朋克/工业电子常见的中快速度，
## 既不会慢到像心跳，也不会快成闪烁。
const BEAT_BPM := 138.0
const BEAT_SECONDS := 60.0 / BEAT_BPM
## 每小节拍数。强拍落在每小节第一拍。
const BEATS_PER_BAR := 4
## 拍内衰减指数：越大越"干脆"（拍头砸完立刻收），越小越拖尾。
const BEAT_DECAY := 2.8

## 入场冲击：从 1.09 倍缩到 1.0，砸进正位。开场第一帧就在强拍上。
const INTRO_SECONDS := 0.30
const INTRO_SCALE := 1.09

## 常驻微颤（设计基准像素 / 度）
const TREMBLE_PX := 0.5
const TREMBLE_DEG := 0.10
## 节拍抖动
const SHAKE_PX := 2.4
const SHAKE_DEG := 0.45
## 强拍额外冲击
const ACCENT_PX := 4.2
const ACCENT_DEG := 0.75
## 每拍鼓一下的缩放脉动（0.016 = 1.6%）
const PULSE_SCALE := 0.016
## 色散在节拍 / 强拍上的附加扩散量
const CHROMA_BEAT_PX := 2.2
const CHROMA_ACCENT_PX := 2.8

var _elapsed := 0.0
## 律动专用时钟。**不能复用 `_elapsed`** —— 那个在 `_advanced` 之后就不再累加
## （它管的是"最短展示时长"），而动画要一直跑到节点被移除。
var _fx_time := 0.0
var _advanced := false
var _transition_requested := false
var _failed := false
## 数据载体：**视觉已改为自绘斜条**，这个 ProgressBar 只保留数值与节点路径
## （`Root/Progress`），并 `visible = false` —— 任何按节点路径读进度的探针都不会坏。
var _progress: ProgressBar
## 只在启动失败时才显示 —— 正常路径上它是隐藏的，不占版面。
var _status_label: Label
var _title_art: Control
var _scheme_art: Control

var _load_requested := false
var _load_done := false
var _load_failed := false
var _load_progress := 0.0
var _target_scene: PackedScene
var _title_font_cache: FontVariation


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if _should_skip_delay():
		_enter_game()
		return
	_request_target_load()


func _process(delta: float) -> void:
	# 律动时钟无条件推进 + 无条件重绘：动画必须在 `_advanced` 之后依然活着，
	# 否则加载卡在最后一段时字会突然僵住，比不做动画更难看。
	_fx_time += delta
	if _title_art != null:
		_title_art.queue_redraw()
	# 背景闪切跟着同一个时钟走：每拍换一套配色，换色点和鼓点严格对齐。
	if _scheme_art != null:
		_scheme_art.queue_redraw()
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


# ========== 律动 ==========

## 拍内脉冲：拍头 1.0，按 BEAT_DECAY 衰减到拍尾 0。
func _beat_pulse() -> float:
	var phase := fmod(_fx_time, BEAT_SECONDS) / BEAT_SECONDS
	return pow(1.0 - phase, BEAT_DECAY)


## 强拍脉冲：每小节第一拍才有值，其余拍返回 0。
func _accent_pulse() -> float:
	var beat_index := int(floor(_fx_time / BEAT_SECONDS))
	if beat_index % BEATS_PER_BAR != 0:
		return 0.0
	return _beat_pulse()


## 确定性哈希 → [-1, 1]。
## 用它而不是 `RandomNumberGenerator`：抖动方向要"每拍换一次、拍内保持不变"。
## 每帧真随机会让字变成一坨噪点闪烁，而不是"在震"——这两者的观感差别极大。
static func _hash_unit(n: int) -> float:
	var x := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0


## 本拍的方向种子。同一拍内所有帧拿到同一个值，跨拍才换。
func _beat_seed() -> int:
	return int(floor(_fx_time / BEAT_SECONDS))


## 名字这一帧的完整律动姿态。集中在一处算，`_draw_title` 只负责用。
func _rhythm_pose(s: float) -> Dictionary:
	var pulse := _beat_pulse()
	var accent := _accent_pulse()
	# 衰减再平方一次：让"砸下去"的瞬间更尖，收尾更软。
	var hit := pulse * pulse
	var seed := _beat_seed()

	# 三个不互约的高频正弦 = 非周期微颤（设备嗡鸣感）。
	var fine := sin(_fx_time * 73.0) + sin(_fx_time * 113.0) * 0.6
	var fine_rot := sin(_fx_time * 97.0) * 0.7 + sin(_fx_time * 149.0) * 0.3

	# 位移：强拍以横向为主（像音波从侧面顶一下），节拍拍以纵向为主。
	var amp_x := SHAKE_PX * hit + ACCENT_PX * accent
	var amp_y := SHAKE_PX * hit * 0.55 + ACCENT_PX * accent * 0.35
	var offset := Vector2(
		_hash_unit(seed * 7 + 1) * amp_x + fine * TREMBLE_PX,
		_hash_unit(seed * 13 + 5) * amp_y + sin(_fx_time * 131.0) * TREMBLE_PX
	) * s

	var deg := TITLE_ROTATION_DEG
	deg += _hash_unit(seed * 29 + 11) * (SHAKE_DEG * hit + ACCENT_DEG * accent)
	deg += fine_rot * TREMBLE_DEG

	# 入场：从 1.09 砸回 1.0。
	var intro := clampf(_fx_time / INTRO_SECONDS, 0.0, 1.0)
	var intro_ease := 1.0 - pow(1.0 - intro, 3.0)
	var scale := lerpf(INTRO_SCALE, 1.0, intro_ease)
	# 每拍鼓一下（强拍鼓得更多）。
	scale *= 1.0 + PULSE_SCALE * pulse + 0.012 * accent

	# 色散跟着节拍炸开：平时 4.2px，节拍 +2.8，强拍再 +3.6。
	var chroma := CHROMA_OFFSET + CHROMA_BEAT_PX * pulse + CHROMA_ACCENT_PX * accent

	return {
		"offset": offset,
		"degrees": deg,
		"scale": scale,
		"chroma": chroma * s,
		"accent": accent,
	}


# ========== 色块构成背景 ==========

## 当前帧号。0.15 s 一帧，八帧一轮（1.2 s）。
func _frame_index() -> int:
	return int(floor(_fx_time / FLASH_SECONDS)) % FRAME_COUNT


## 把碎片顶点按镜像组合变换一次。
func _mirror_points(points: Array, flip_x: bool, flip_y: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		var p: Vector2 = points[i]
		out[i] = Vector2(
			DESIGN_SIZE.x - p.x if flip_x else p.x,
			DESIGN_SIZE.y - p.y if flip_y else p.y
		)
	return out


## 鞋带公式算多边形面积。返回**占全屏比例**（0~1）。
## 只在 `measure_area_share()` 里用来核对配额，运行时不调用。
static func _polygon_share(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var acc := 0.0
	var n := points.size()
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		acc += a.x * b.y - b.x * a.y
	return absf(acc) * 0.5 / (DESIGN_SIZE.x * DESIGN_SIZE.y)


## 面积自检：返回每帧的 {index, vivid, clash, black}。
##
## 这是"注释里的百分比到底真不真"的唯一凭据 —— 顶点或索引表被改动后，
## 探针会在这里立刻暴露配额漂移，而不是等肉眼发现"这帧怎么这么满"。
## 镜像不改变面积，所以这里只按原样算一次即可覆盖该帧所有镜像。
func measure_area_share() -> Array:
	var frames: Array = []
	for i in FRAME_SPECS.size():
		var spec: Dictionary = FRAME_SPECS[i]
		var vivid := 0.0
		var clash := 0.0
		for idx in spec["vivid"]:
			vivid += _polygon_share(_mirror_points(PIECE_POOL[idx], false, false))
		for idx in spec["clash"]:
			clash += _polygon_share(_mirror_points(PIECE_POOL[idx], false, false))
		frames.append({
			"index": i,
			"vivid": vivid,
			"clash": clash,
			"black": maxf(0.0, 1.0 - vivid - clash),
		})
	return frames


## 画色块构成背景。
##
## 只有一件事：把当帧挑出的几块**方向互相打架**的碎片切到画布上，其余全留黑。
## 不铺满、不加边框、不做渐变 —— 黑色是主体，彩色是刀口。
func _draw_scheme(art: Control) -> void:
	var box := art.size
	var s := _ui_scale(box)
	if s <= 0.0:
		return
	# 统一缩放的画布：用 transform 把设计基准 1280×720 映射到实际尺寸，
	# 之后的坐标全部按基准写，不再逐处乘 s。
	art.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))

	var index := _frame_index()
	var spec: Dictionary = FRAME_SPECS[index]
	var flip: Array = FRAME_FLIPS[index]
	var colors: Array = spec["colors"]
	var vivid_color = colors[0]
	var clash_color: Color = colors[1]

	# 先后顺序有讲究：鲜艳色先铺、撞色后压。
	# 反过来的话，撞色会被鲜艳色整块盖掉 —— 撞色配额直接归零。
	if vivid_color != null:
		for piece_index in spec["vivid"]:
			art.draw_colored_polygon(
				_mirror_points(PIECE_POOL[piece_index], flip[0], flip[1]), vivid_color
			)
	for piece_index in spec["clash"]:
		art.draw_colored_polygon(
			_mirror_points(PIECE_POOL[piece_index], flip[0], flip[1]), clash_color
		)

	# 强拍闪白：整屏提亮 4% 再回落。
	# 黑色占主体后不能给太多 —— 白闪过高会把黑场冲成灰，黑就不黑了。
	var accent := _accent_pulse()
	if accent > 0.01:
		art.draw_rect(
			Rect2(Vector2.ZERO, DESIGN_SIZE),
			Color(1.0, 1.0, 1.0, 0.04 * accent),
			true
		)

	art.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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

	# 色块构成层：压在最底的黑底之上、名字之下。
	# 它自带全屏填充，所以必须排在 Backdrop 之后，否则会被黑底盖掉。
	_scheme_art = Control.new()
	_scheme_art.name = "SchemeArt"
	_scheme_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scheme_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scheme_art.draw.connect(_draw_scheme.bind(_scheme_art))
	_scheme_art.resized.connect(_scheme_art.queue_redraw)
	root.add_child(_scheme_art)

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
## ⚠ **字抖，条不抖。** 两段各用一套 transform：
##   名字吃律动姿态（位移/角度/缩放全带抖动），进度条用干净坐标系。
##   条是读进度的功能件 —— 跟着鼓点跳会让读数发飘，还显得廉价。
##   这不是妥协：动感归表现，准确归功能，分得越清两者都成立。
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

	var pose := _rhythm_pose(s)
	var shake: Vector2 = pose["offset"]
	var title_scale: float = pose["scale"]

	# ---- 名字：律动坐标系（位移 + 抖动角 + 脉动缩放）----
	# 抖动位移加在**屏幕坐标**上（不是旋转后的局部坐标）：横向抖动就该是屏幕横向，
	# 不然斜了 13° 之后"横抖"会变成斜向抖，物理上不对。
	art.draw_set_transform(
		center + shake,
		deg_to_rad(float(pose["degrees"])),
		Vector2(title_scale, title_scale)
	)

	var offset: float = pose["chroma"]
	# 强拍时色散方向翻转一次，制造"信号被打断又接回"的错觉。
	var accent: float = pose["accent"]
	var flip := -1.0 if accent > 0.45 else 1.0

	# ---- 底层：近黑描边 ----
	# ⚠ 背景现在是玫红/绿/蓝色块，白字压在亮色块上（尤其绿色 #02E676）会直接糊掉。
	# 所以必须先刷一层**比黑底更深的描边**：8 个方向各偏一点，
	# 把字的轮廓从任意底色上"抠"出来。这一层不是装饰，是背景变多色后的可读性刚需。
	var outline_px := OUTLINE_PX * s * title_scale
	var outline_color := OUTLINE_COLOR
	for dir in [
		Vector2(-1.0, -1.0), Vector2(0.0, -1.0), Vector2(1.0, -1.0),
		Vector2(-1.0, 0.0), Vector2(1.0, 0.0),
		Vector2(-1.0, 1.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0),
	]:
		art.draw_string(
			font, origin + dir * outline_px, TITLE_TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color
		)

	# ---- 中层：粉 / 青 色散 ----
	# 粉走左上、青走右下；白主体居中压在两者之间。
	art.draw_string(
		font, origin + Vector2(-offset, -offset * 0.42) * flip, TITLE_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(CHROMA_PINK.r, CHROMA_PINK.g, CHROMA_PINK.b, CHROMA_ALPHA)
	)
	art.draw_string(
		font, origin + Vector2(offset, offset * 0.42) * flip, TITLE_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(CHROMA_CYAN.r, CHROMA_CYAN.g, CHROMA_CYAN.b, CHROMA_ALPHA)
	)

	# ---- 顶层：白主体 ----
	art.draw_string(
		font, origin, TITLE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		UIPalette.PRISM_TEXT
	)

	# ---- 进度条：干净坐标系，只保留基础旋转 ----
	art.draw_set_transform(center, deg_to_rad(TITLE_ROTATION_DEG), Vector2.ONE)

	var bar_w := text_size.x * BAR_WIDTH_OF_TEXT
	var bar_h := BAR_HEIGHT * s
	var bar_top := block_bottom + BAR_GAP * s
	var bar_left := -bar_w * 0.5
	var ratio := 0.0
	if _progress != null and _progress.max_value > 0.0:
		ratio = clampf(_progress.value / _progress.max_value, 0.0, 1.0)

	# 空槽：**深色衬底** + 白描边。
	# ⚠ 原来是"10% 白底"，那是给纯黑背景设计的。现在背景是亮玫红/亮绿/亮蓝，
	# 半透明白底会直接消失 —— 读不出"还剩多少"，进度条就废了。
	# 所以改成不透明近黑衬底 + 加粗到 2px 的白边：深底压住任何亮色块，白边再把它框出来。
	var bar_backing := OUTLINE_COLOR
	bar_backing.a = 0.88
	art.draw_rect(Rect2(bar_left, bar_top, bar_w, bar_h), bar_backing, true)
	art.draw_rect(
		Rect2(bar_left, bar_top, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.72), false, 2.0 * s
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
