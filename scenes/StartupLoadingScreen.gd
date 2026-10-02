extends CanvasLayer
class_name StartupLoadingScreen
## 启动外壳：先给玩家一个明确的启动画面，再进入原有 TowerDescent3D。
##
## 这里只负责视觉反馈与一次性切场景，不读取、不消费、不写入任何存档，
## 不参与 GameEntryFlow，也不改变目的场景的出生、恢复和开始菜单逻辑。

const TARGET_SCENE := "res://scenes/TowerDescent3D.tscn"
const MIN_DISPLAY_SECONDS := 1.10
const STEP_DURATION_SECONDS := 0.55
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


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if _should_skip_delay():
		_enter_game()


func _process(delta: float) -> void:
	if _advanced or _failed:
		return
	_elapsed += delta
	_update_ui()
	if _elapsed >= MIN_DISPLAY_SECONDS:
		_enter_game()


func _should_skip_delay() -> bool:
	return DisplayServer.get_name() == "headless" or Engine.is_editor_hint()


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
	var error: Error = get_tree().change_scene_to_file(TARGET_SCENE)
	if error != OK:
		_failed = true
		if _status_label != null:
			_status_label.text = "启动失败：%s" % error_string(error)
		push_error("[StartupLoadingScreen] 进入主场景失败: %s" % error_string(error))


func _update_ui() -> void:
	var ratio := clampf(_elapsed / MIN_DISPLAY_SECONDS, 0.0, 1.0)
	if _progress != null:
		_progress.value = ratio * 100.0
	if _step_label != null and not STEP_TEXTS.is_empty():
		var step_index := clampi(
			int(_elapsed / STEP_DURATION_SECONDS), 0, STEP_TEXTS.size() - 1
		)
		_step_label.text = STEP_TEXTS[step_index]


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.008, 0.014, 0.022, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var top_line := ColorRect.new()
	top_line.name = "TopLine"
	top_line.color = Color(0.18, 0.72, 0.82, 1.0)
	top_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_line.offset_bottom = 2.0
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
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Color(0.28, 0.78, 0.86, 1.0))
	center.add_child(eyebrow)

	var title := Label.new()
	title.name = "Title"
	title.text = "弹壳风暴2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.84, 0.96, 1.0, 1.0))
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "正在准备你的行动"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.52, 0.68, 0.73, 1.0))
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
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.075, 0.10, 1.0)
	background.border_color = Color(0.12, 0.38, 0.45, 1.0)
	background.set_border_width_all(1)
	background.set_corner_radius_all(3)
	_progress.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.20, 0.76, 0.84, 1.0)
	fill.set_corner_radius_all(3)
	_progress.add_theme_stylebox_override("fill", fill)
	center.add_child(_progress)

	_step_label = Label.new()
	_step_label.name = "Step"
	_step_label.text = STEP_TEXTS[0]
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", 15)
	_step_label.add_theme_color_override("font_color", Color(0.70, 0.84, 0.86, 1.0))
	center.add_child(_step_label)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "请稍候"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.38, 0.52, 0.56, 1.0))
	center.add_child(_status_label)
