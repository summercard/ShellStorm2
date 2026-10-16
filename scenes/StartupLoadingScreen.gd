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

const TARGET_SCENE := "res://scenes/TowerDescent3D.tscn"
const MIN_DISPLAY_SECONDS := 1.10
## 进度阶段文案：按**真实加载进度**分段，不再按时间分段 ——
## 时间分段会让进度条与文案在慢盘上互相矛盾。
const STEP_TEXTS: Array[String] = [
	"正在启动行动系统…",
	"正在连接运行环境…",
	"正在准备战区…",
	"即将进入行动…",
]

var _elapsed := 0.0
var _advanced := false
var _transition_requested := false
var _failed := false
var _progress: ProgressBar
var _step_label: Label
var _status_label: Label

var _load_requested := false
var _load_done := false
var _load_failed := false
var _load_progress := 0.0
var _target_scene: PackedScene


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if _should_skip_delay():
		_enter_game()
		return
	_request_target_load()


func _process(delta: float) -> void:
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
		push_error("[StartupLoadingScreen] 进入主场景失败: %s" % error_string(error))


func _update_ui() -> void:
	var time_ratio := clampf(_elapsed / MIN_DISPLAY_SECONDS, 0.0, 1.0)
	# 两个下限取大：加载慢时显示真实进度，加载快时按最短展示时间平滑推到 100%，
	# 两者都单调不减，进度条不会回跳。
	var ratio := maxf(_load_progress, time_ratio)
	if _progress != null:
		_progress.value = ratio * 100.0
	if _step_label != null and not STEP_TEXTS.is_empty():
		var step_index := clampi(
			int(ratio * float(STEP_TEXTS.size())), 0, STEP_TEXTS.size() - 1
		)
		_step_label.text = STEP_TEXTS[step_index]


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	# 启动壳是**全屏菜单**（不是压在实景上的 HUD），走棱镜模态底：
	# 深墨底 + 顶部 1px 次级白线，零辉光零渐变 —— 规范 §3.1。
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(
		UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 1.0
	)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var top_line := ColorRect.new()
	top_line.name = "TopLine"
	top_line.color = UIPalette.PRISM_LINE_SOFT
	top_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_line.offset_bottom = 1.0
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_line)

	var center := VBoxContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -300.0
	center.offset_top = -116.0
	center.offset_right = 300.0
	center.offset_bottom = 116.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 12)
	root.add_child(center)

	var eyebrow := Label.new()
	eyebrow.name = "Eyebrow"
	eyebrow.text = "SHELLSTORM 2  ·  OPERATION SYSTEM"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(eyebrow, "label", 6, 14)
	center.add_child(eyebrow)

	var title := Label.new()
	title.name = "Title"
	title.text = "弹壳风暴2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(title, "value", 4, 42)
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "正在准备你的行动"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(subtitle, "faint", 3, 17)
	center.add_child(subtitle)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size.y = 18.0
	center.add_child(spacer)

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(460.0, 12.0)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	# 进度槽 = 1px 白线空槽；填充 = 强调色实心条（棱镜里唯一的"面"，属语义件）。
	_progress.add_theme_stylebox_override("background", UIStyleFactory.make_prism_progress_background())
	_progress.add_theme_stylebox_override(
		"fill", UIStyleFactory.make_prism_progress_fill(UIPalette.PRISM_ACCENT)
	)
	center.add_child(_progress)

	_step_label = Label.new()
	_step_label.name = "Step"
	_step_label.text = STEP_TEXTS[0]
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(_step_label, "label", 2, 15)
	center.add_child(_step_label)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "请稍候"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(_status_label, "faint", 1, 13)
	center.add_child(_status_label)
