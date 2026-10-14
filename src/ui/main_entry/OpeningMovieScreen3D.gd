class_name OpeningMovieScreen3D
extends CanvasLayer
## 新档开场影片覆盖层：全屏播放开场动画（`assets/movie/opening_mv.ogv`），
## 播完渐黑交接给玩法 —— 不切场景、不复制角色、不读不写存档。
##
## 与 `MainEntryScreen3D` 的分工：两者都是「冷启动/显式主页」这一次入口的
## **互斥**出口，由 `TowerDescent3D._install_main_entry_screen()` 二选一。
## - 已有存档 → `MainEntryScreen3D`（近景角色 + 开始按钮，照旧）
## - 全新存档 → 本层（开场影片 → 直接落 98F 主人办公室，不进主页菜单）
##
## ⚠️ 两条硬约束（改本文件前必读）：
##   1. **headless 下绝不创建播放器**：实测 Godot 4.6 headless 里
##      `load()` 一个 `.ogv` 会**整个进程挂死**（不报错、不返回；
##      `ResourceLoader.exists()` 正常，只有真正解码时才卡）。所以本层在
##      `test_mode / headless` 下走 `_abort_in_headless()` 直接交接，
##      验收只允许验证判定与资源存在性，真实播放必须走真实渲染。
##   2. **交还所有权必须幂等**：`transition_finished` 只发一次；HUD 可见性、
##      玩家输入锁在 `_exit_tree()` 里同样收口，异常卸载不留半接管状态。

## 玩法**正式开始**对外只有一发 `transition_finished`：塔楼据此才发
## `gameplay_started`，开场剧情（`nar_tower_opening_01_wake`）挂在那上面。
signal transition_finished()
signal skipped()

const MOVIE_PATH := "res://assets/movie/opening_mv.ogv"
## 渐黑时长拆两段：先压黑盖住影片最后一帧，再在黑幕下把玩法交还并淡出。
const FADE_IN_BLACK_DURATION_S := 0.45
const FADE_OUT_BLACK_DURATION_S := 0.70
## 影片结束后额外停留，给最后一帧（兔子特写）留一拍呼吸。
const HOLD_AFTER_MOVIE_S := 0.35
const SKIP_HINT_TEXT := "按任意键跳过"
## 画面保持 16:9 letterbox，不按窗口比例拉伸变形。
const MOVIE_ASPECT_RATIO := 16.0 / 9.0

var auto_present_when_ready := true

var _root: Control
var _player: VideoStreamPlayer
var _fade_black: ColorRect
var _skip_hint: Label
var _status_label: Label
var _gameplay_hud: CanvasLayer = null
var _gameplay_hud_previous_visible := true
var _gameplay_hud_prepared := false
var _previous_input_locked := false
var _player_locked := false
var _finished := false
var _fading := false
var _fade_elapsed := 0.0
var _hold_elapsed := 0.0
var _movie_started := false
var _movie_ended := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	# 与主页同层：两者互斥，同一时刻只会存在一个。
	# 影片壳与跳过提示全部自绘，声明豁免避免被战术皮肤套上矩形描边。
	set_meta("ui_style_exempt", true)
	# ⚠️ headless 判定必须在 `_build_ui()` **之前**：本层连 VideoStreamPlayer 节点
	# 都不该在无视频驱动的环境里被创建（见文件头硬约束 1）。
	if _should_abort_immediately():
		_abort_in_headless()
		return
	_build_ui()
	if auto_present_when_ready:
		call_deferred("start_movie")


## headless / 编辑器内预览不得进入视频解码路径（见文件头硬约束 1）。
func _should_abort_immediately() -> bool:
	return DisplayServer.get_name() == "headless" or Engine.is_editor_hint()


func _abort_in_headless() -> void:
	# 不加载视频、不播动画：立刻把入口交还，让塔楼的 `_defer_gameplay_started()`
	# 拿到 `transition_finished` 后照常启动玩法。
	if _player != null:
		_player.stream = null
	_finish_transition()


func prepare_gameplay_hud(gameplay_hud: CanvasLayer) -> void:
	if gameplay_hud == null or not is_instance_valid(gameplay_hud):
		return
	_gameplay_hud = gameplay_hud
	if not _gameplay_hud_prepared:
		_gameplay_hud_previous_visible = gameplay_hud.visible
		_gameplay_hud_prepared = true
	gameplay_hud.visible = false


## 影片层始终持有画面与输入；塔楼的固定相机链、剧情摄影机查询都以此短路。
func is_camera_override_active() -> bool:
	return not _finished


func start_movie() -> bool:
	if _movie_started or _finished:
		return _movie_started
	if _player == null:
		_abort_in_headless()
		return false
	var stream := load(MOVIE_PATH) as VideoStream
	if stream == null:
		# 资源缺失不是玩法失败：记一条错误后照常进游戏，绝不把玩家卡在黑幕里。
		push_error("[OpeningMovieScreen3D] 开场影片加载失败：%s，直接进入玩法" % MOVIE_PATH)
		_abort_in_headless()
		return false
	_player.stream = stream
	_player.bus = _resolve_audio_bus()
	_lock_player()
	if _status_label != null:
		_status_label.visible = false
	if _skip_hint != null:
		_skip_hint.visible = true
	_player.play()
	_movie_started = true
	return true


## 开场影片的旁白/配乐属于音乐域，跟随音乐音量；无 Music 总线时退回 Master。
func _resolve_audio_bus() -> StringName:
	if AudioServer.get_bus_index("Music") >= 0:
		return &"Music"
	return &"Master"


func skip() -> void:
	if _finished or _fading:
		return
	skipped.emit()
	_begin_fade_out()


func get_entry_snapshot() -> Dictionary:
	return {
		"kind": "opening_movie",
		"movie_path": MOVIE_PATH,
		"started": _movie_started,
		"movie_ended": _movie_ended,
		"fading": _fading,
		"finished": _finished,
		"uses_live_player": false,
		"seamless_scene_change": true,
		"aborted_in_headless": _should_abort_immediately(),
		"gameplay_hud_hidden": _gameplay_hud != null and is_instance_valid(_gameplay_hud) and not _gameplay_hud.visible,
		"skip_hint_visible": _skip_hint != null and is_instance_valid(_skip_hint) and _skip_hint.visible,
		"player_input_locked": _player_locked,
		"fade_in_black_duration_s": FADE_IN_BLACK_DURATION_S,
		"fade_out_black_duration_s": FADE_OUT_BLACK_DURATION_S,
	}


func _process(delta: float) -> void:
	if _finished:
		return
	if _fading:
		_advance_fade(delta)
		return
	if not _movie_started or _player == null:
		return
	if _player.is_playing():
		return
	# 播放器停下有两种可能：正常播完，或解码失败后立刻停止。
	# 两者都按「影片结束」处理 —— 差一帧黑屏好过把玩家永久锁在覆盖层。
	_movie_ended = true
	_hold_elapsed += delta
	if _hold_elapsed >= HOLD_AFTER_MOVIE_S:
		_begin_fade_out()


func _input(event: InputEvent) -> void:
	if _finished or _fading or not _movie_started:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		skip()
		return
	if event is InputEventMouseButton and event.pressed:
		skip()
		return
	if event is InputEventJoypadButton and event.pressed:
		skip()
		return


func _begin_fade_out() -> void:
	_fading = true
	_fade_elapsed = 0.0
	if _player != null and _player.is_playing():
		_player.stop()
	if _skip_hint != null:
		_skip_hint.visible = false


func _advance_fade(delta: float) -> void:
	_fade_elapsed += delta
	if _fade_black == null:
		_finish_transition()
		return
	if _fade_elapsed <= FADE_IN_BLACK_DURATION_S:
		# 第一段：黑幕压上来，盖住影片最后一帧。
		_fade_black.color.a = clampf(_fade_elapsed / FADE_IN_BLACK_DURATION_S, 0.0, 1.0)
		return
	# 黑幕全黑之后再交还玩法，玩家看不到"世界突然跳了一下"。
	_release_player_input()
	var ratio := clampf((_fade_elapsed - FADE_IN_BLACK_DURATION_S) / FADE_OUT_BLACK_DURATION_S, 0.0, 1.0)
	_fade_black.color.a = 1.0 - ratio
	if ratio >= 1.0:
		_finish_transition()


func _finish_transition() -> void:
	if _finished:
		return
	_finished = true
	_fading = false
	if _player != null:
		_player.stop()
	_release_player_input()
	_restore_gameplay_hud()
	_remove_self()
	transition_finished.emit()


func _lock_player() -> void:
	if _player_locked:
		return
	var player := get_tree().get_first_node_in_group("player_3d") as Player3D
	if player == null:
		return
	_previous_input_locked = player.input_locked
	player.set_input_locked(true)
	_player_locked = true


func _release_player_input() -> void:
	if not _player_locked:
		return
	var player := get_tree().get_first_node_in_group("player_3d") as Player3D
	if player != null and is_instance_valid(player):
		player.set_input_locked(_previous_input_locked)
	_player_locked = false


func _restore_gameplay_hud() -> void:
	if _gameplay_hud != null and is_instance_valid(_gameplay_hud) and _gameplay_hud_prepared:
		_gameplay_hud.visible = _gameplay_hud_previous_visible
	_gameplay_hud_prepared = false


func _remove_self() -> void:
	if is_inside_tree():
		# 先藏后删：queue_free 到真正释放之间不能留一帧半透明残影。
		visible = false
		queue_free()


func _exit_tree() -> void:
	# 异常卸载（场景被换掉/被 queue_free）也必须收口，不留半锁状态。
	if _player != null and is_instance_valid(_player):
		_player.stop()
	_release_player_input()
	_restore_gameplay_hud()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var aspect := AspectRatioContainer.new()
	aspect.name = "Aspect"
	aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aspect.ratio = MOVIE_ASPECT_RATIO
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(aspect)

	_player = VideoStreamPlayer.new()
	_player.name = "Movie"
	_player.expand = true
	_player.autoplay = false
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.add_child(_player)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "正在载入开场档案…"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.62, 0.74, 0.78, 1.0))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status_label)

	_skip_hint = Label.new()
	_skip_hint.name = "SkipHint"
	_skip_hint.text = SKIP_HINT_TEXT
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -260.0
	_skip_hint.offset_top = -52.0
	_skip_hint.offset_right = -28.0
	_skip_hint.offset_bottom = -22.0
	_skip_hint.add_theme_font_size_override("font_size", 14)
	_skip_hint.add_theme_color_override("font_color", Color(0.70, 0.80, 0.84, 0.72))
	_skip_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_skip_hint.add_theme_constant_override("outline_size", 5)
	_skip_hint.visible = false
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_skip_hint)

	# 黑幕常驻在最上层，靠 alpha 控制 —— 不切 visible，避免渐黑第一帧跳一下。
	_fade_black = ColorRect.new()
	_fade_black.name = "FadeBlack"
	_fade_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade_black)
