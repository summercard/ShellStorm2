extends CanvasLayer
class_name ExpeditionLoadingScreen
## 远征情报室 →「远征关卡01」之间的读取界面。
##
## 职责刻意保持单一：不提交运行态检查点、不消费入口意图、不改动任何存档。
## 基地落盘与入口登记由 RogueMapSelectMenu 在切场景前完成；本界面只负责
## 把"正在读取关卡"这件事显式地画给玩家看，进度走满后切到正式关卡场景。
##
## 无头/编辑器环境直接跳过等待，保证验收脚本不会被过场拖住。

## 到达关卡路径**不在此处硬编码**：终点真源统一为 GameDesignConfig 的远征关卡清单。
## 本常量只是**默认终点**（远征关卡01）；实际去向由选关菜单写入的待进入关卡 id 决定，
## 见 `_destination_level_id()`。
const LEVEL_SCENE := GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D
## 过场总时长。只影响观感，不影响关卡数据；全部真实生成发生在关卡场景的 _ready()。
const TOTAL_DURATION_S := 1.35
const STEP_TEXTS: Array[String] = [
	"正在同步远征情报…",
	"正在规划房间序列…",
	"正在装配区块与门…",
	"正在生成敌对信号…",
	"读取完成，正在进入关卡",
]

var _elapsed := 0.0
var _advanced := false
var _progress: ProgressBar
var _step_label: Label
var _level_id := ""


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 一次性取走菜单登记的关卡：取值即清空，上一次的选择不会泄漏到下一次传送。
	# 验收脚本只 `_build_ui()` 不入树，那时本函数不跑，待进入态保持默认 —— 因此
	# 「默认关卡01」这条既有断言不受影响。
	_level_id = GameDesignConfig.peek_pending_expedition_level_id()
	_build_ui()
	if _should_skip_delay():
		_enter_level()


func _process(delta: float) -> void:
	if _advanced:
		return
	_elapsed += delta
	var ratio := clampf(_elapsed / TOTAL_DURATION_S, 0.0, 1.0)
	if _progress != null:
		_progress.value = ratio * 100.0
	if _step_label != null and not STEP_TEXTS.is_empty():
		var step_index := clampi(
			int(ratio * float(STEP_TEXTS.size())), 0, STEP_TEXTS.size() - 1
		)
		_step_label.text = STEP_TEXTS[step_index]
	if ratio >= 1.0:
		_enter_level()


## 无头验收与编辑器内不播放过场：直接进入关卡，避免慢测试与编辑器卡帧。
func _should_skip_delay() -> bool:
	return (
		DisplayServer.get_name() == "headless"
		or Engine.is_editor_hint()
	)


func _enter_level() -> void:
	if _advanced:
		return
	_advanced = true
	var error := get_tree().change_scene_to_file(_destination_scene())
	if error != OK:
		push_error(
			"[ExpeditionLoadingScreen] 进入远征关卡失败: %s" % error_string(error)
		)


## 本次要去的关卡 id。`_level_id` 为真源（_ready 时取），空则回退默认关卡。
func _destination_level_id() -> String:
	if _level_id.is_empty():
		return GameDesignConfig.default_expedition_level_id()
	return _level_id


## 本次要去的关卡场景。
func _destination_scene() -> String:
	return GameDesignConfig.expedition_level_scene(_destination_level_id())


## 本次要去的关卡展示名。关卡清单里没有该 id 时返回 id 本身，至少不说谎。
func _destination_display_name() -> String:
	var level_id := _destination_level_id()
	var display_name := GameDesignConfig.expedition_level_display_name(level_id)
	if display_name.is_empty():
		return level_id
	return display_name


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.012, 0.022, 0.032, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := VBoxContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -320.0
	center.offset_top = -140.0
	center.offset_right = 320.0
	center.offset_bottom = 140.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	root.add_child(center)

	var breadcrumb := Label.new()
	breadcrumb.name = "Breadcrumb"
	breadcrumb.text = "远征情报室  →  %s" % _destination_display_name()
	breadcrumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	breadcrumb.add_theme_font_size_override("font_size", 16)
	breadcrumb.add_theme_color_override("font_color", Color(0.32, 0.78, 0.92))
	center.add_child(breadcrumb)

	var title := Label.new()
	title.name = "Title"
	title.text = _destination_display_name()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.78, 0.96, 1.0))
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = GameDesignConfig.expedition_level_subtitle(_destination_level_id())
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.72, 0.78))
	center.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18.0
	center.add_child(spacer)

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(460.0, 16.0)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.05, 0.09, 0.12, 1.0)
	background.border_color = Color(0.16, 0.44, 0.52)
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	_progress.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.24, 0.86, 0.92, 1.0)
	fill.set_corner_radius_all(4)
	_progress.add_theme_stylebox_override("fill", fill)
	center.add_child(_progress)

	_step_label = Label.new()
	_step_label.name = "Step"
	_step_label.text = STEP_TEXTS[0]
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", 15)
	_step_label.add_theme_color_override("font_color", Color(0.72, 0.88, 0.90))
	center.add_child(_step_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "读取期间不会写入任何存档"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.40, 0.48, 0.52))
	center.add_child(hint)
