class_name FlashlightColorTweaker
extends PanelContainer
## 实时调参面板：顶部 tab 菜单在「调整灯光」与「后处理」之间切换，
## 留 2 个预留位。P 键整体切显隐。
##
## 灯光 tab：ForwardBeam / EnvironmentSpill / AvatarFrontFill 三盏灯
##   的 color + energy，通过 PlayerFlashlight3D 的公开 setter 同时写
##   export 变量与实时灯节点，toggle / 模块切换 / _apply_configuration
##   后保留新值。
##
## 后处理 tab：各向异性（glow_anisotropy_strength/expansion）+ 滤镜色彩
##   调整（adjustment_enabled + brightness/contrast/saturation）。所有
##   写入经 GraphicsSettingsManager.set_debug_postfx() 落到 in-memory
##   调试覆盖层，不污染玩家画质档和持久化 cfg。

const ENERGY_SLIDER_MIN := 0.0
const ENERGY_SLIDER_MAX := 16.0
const ENERGY_SLIDER_STEP := 0.05

const ANISO_STRENGTH_MIN := 0.0
const ANISO_STRENGTH_MAX := 16.0
const ANISO_STRENGTH_STEP := 0.05
const ANISO_EXPANSION_MIN := 0.0
const ANISO_EXPANSION_MAX := 1.0
const ANISO_EXPANSION_STEP := 0.01

const ADJ_BRIGHTNESS_MIN := 0.0
const ADJ_BRIGHTNESS_MAX := 2.0
const ADJ_BRIGHTNESS_STEP := 0.01
const ADJ_CONTRAST_MIN := 0.0
const ADJ_CONTRAST_MAX := 2.0
const ADJ_CONTRAST_STEP := 0.01
const ADJ_SATURATION_MIN := 0.0
const ADJ_SATURATION_MAX := 2.0
const ADJ_SATURATION_STEP := 0.01
const ADJ_HUE_MIN := 0.0
const ADJ_HUE_MAX := 1.0
const ADJ_HUE_STEP := 0.005

const GRAIN_STRENGTH_MIN := 0.0
const GRAIN_STRENGTH_MAX := 1.0
const GRAIN_STRENGTH_STEP := 0.01
const GRAIN_SIZE_MIN := 0.05
const GRAIN_SIZE_MAX := 3.0
const GRAIN_SIZE_STEP := 0.05

const TV_GLOW_ANISO_MIN := 0.0
const TV_GLOW_ANISO_MAX := 16.0
const TV_GLOW_ANISO_STEP := 0.05
const TV_GLOW_STRENGTH_MIN := 0.0
const TV_GLOW_STRENGTH_MAX := 2.0
const TV_GLOW_STRENGTH_STEP := 0.01
const TV_GLOW_HDR_THRESHOLD_MIN := 0.0
const TV_GLOW_HDR_THRESHOLD_MAX := 4.0
const TV_GLOW_HDR_THRESHOLD_STEP := 0.01
const TV_GLOW_HDR_SCALE_MIN := 0.0
const TV_GLOW_HDR_SCALE_MAX := 4.0
const TV_GLOW_HDR_SCALE_STEP := 0.01

enum TabId { LIGHT, POSTFX, RESERVED_2, RESERVED_3 }

const TAB_LABELS := {
	TabId.LIGHT: "调整灯光",
	TabId.POSTFX: "后处理",
	TabId.RESERVED_2: "预留",
	TabId.RESERVED_3: "预留",
}

var _flashlight: PlayerFlashlight3D
var _status_label: Label

# 灯光 tab 控件引用
var _beam_color: ColorPickerButton
var _beam_energy_slider: HSlider
var _beam_energy_label: Label
var _spill_color: ColorPickerButton
var _spill_energy_slider: HSlider
var _spill_energy_label: Label
var _fill_color: ColorPickerButton
var _fill_energy_slider: HSlider
var _fill_energy_label: Label

# 灯光 tab 初次打开时捕获的 export 默认值，供"复位"按钮使用。
var _initial_beam_color: Color
var _initial_beam_energy: float
var _initial_spill_color: Color
var _initial_spill_energy: float
var _initial_fill_color: Color
var _initial_fill_energy: float
var _has_initial := false

# 后处理 tab 控件引用
var _postfx_aniso_strength_slider: HSlider
var _postfx_aniso_strength_label: Label
var _postfx_aniso_expansion_slider: HSlider
var _postfx_aniso_expansion_label: Label
var _postfx_adjustment_toggle: CheckButton
var _postfx_hue_slider: HSlider
var _postfx_hue_label: Label
var _postfx_brightness_slider: HSlider
var _postfx_brightness_label: Label
var _postfx_contrast_slider: HSlider
var _postfx_contrast_label: Label
var _postfx_saturation_slider: HSlider
var _postfx_saturation_label: Label

# 噪点
var _postfx_grain_toggle: CheckButton
var _postfx_grain_strength_slider: HSlider
var _postfx_grain_strength_label: Label
var _postfx_grain_size_slider: HSlider
var _postfx_grain_size_label: Label

# 电视干扰
var _postfx_tv_toggle: CheckButton
var _postfx_tv_glow_aniso_slider: HSlider
var _postfx_tv_glow_aniso_label: Label
var _postfx_tv_glow_strength_slider: HSlider
var _postfx_tv_glow_strength_label: Label
var _postfx_tv_glow_hdr_threshold_slider: HSlider
var _postfx_tv_glow_hdr_threshold_label: Label
var _postfx_tv_glow_hdr_scale_slider: HSlider
var _postfx_tv_glow_hdr_scale_label: Label

# tab 容器 / 按钮
var _tab_buttons: Dictionary = {}
var _tab_pages: Dictionary = {}
var _active_tab: TabId = TabId.LIGHT

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2100
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 18.0
	offset_top = 18.0
	offset_right = 380.0
	offset_bottom = 820.0
	custom_minimum_size = Vector2(360, 0)
	_build_ui()
	UIStyleFactory.apply_tactical_tree(self)
	_resolve_flashlight()
	_select_tab(TabId.LIGHT)

# 沿父链向上找 Player3D，再拿到挂在它下面的 PlayerFlashlight3D。
# 节点未就绪时（早期 _ready 顺序）允许稍后重试。
func _resolve_flashlight() -> void:
	var node := get_parent()
	while node != null:
		if node is Player3D:
			_flashlight = node.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
			if _flashlight != null and not _has_initial:
				_initial_beam_color = _flashlight.get_beam_color()
				_initial_beam_energy = _flashlight.get_beam_energy()
				_initial_spill_color = _flashlight.get_spill_color()
				_initial_spill_energy = _flashlight.get_spill_energy()
				_initial_fill_color = _flashlight.get_front_fill_color()
				_initial_fill_energy = _flashlight.get_front_fill_energy()
				_has_initial = true
			_refresh_status_label()
			return
		node = node.get_parent()

func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode if key_event.keycode != 0 else key_event.physical_keycode
	if key != KEY_P:
		return
	visible = not visible
	if visible:
		if _flashlight == null:
			_resolve_flashlight()
		_sync_from_flashlight()
		_sync_postfx_from_manager()
	get_viewport().set_input_as_handled()

func _sync_from_flashlight() -> void:
	if _flashlight == null:
		_refresh_status_label()
		return
	_block_light_signals(true)
	_beam_color.color = _flashlight.get_beam_color()
	_beam_energy_slider.value = _flashlight.get_beam_energy()
	_spill_color.color = _flashlight.get_spill_color()
	_spill_energy_slider.value = _flashlight.get_spill_energy()
	_fill_color.color = _flashlight.get_front_fill_color()
	_fill_energy_slider.value = _flashlight.get_front_fill_energy()
	_block_light_signals(false)
	_refresh_value_labels()
	_refresh_status_label()

func _sync_postfx_from_manager() -> void:
	if not is_instance_valid(_postfx_aniso_strength_slider):
		return
	var snap := _get_debug_postfx_snapshot()
	_block_postfx_signals(true)
	_postfx_aniso_strength_slider.value = float(snap.get("debug_postfx_anisotropy_strength", 0.0))
	_postfx_aniso_expansion_slider.value = float(snap.get("debug_postfx_anisotropy_expansion", 0.0))
	_postfx_adjustment_toggle.button_pressed = bool(snap.get("debug_postfx_adjustment_enabled", true))
	_postfx_hue_slider.value = float(snap.get("debug_postfx_adjustment_hue", 0.0))
	_postfx_brightness_slider.value = float(snap.get("debug_postfx_adjustment_brightness", 1.0))
	_postfx_contrast_slider.value = float(snap.get("debug_postfx_adjustment_contrast", 1.0))
	_postfx_saturation_slider.value = float(snap.get("debug_postfx_adjustment_saturation", 1.0))
	_postfx_grain_toggle.button_pressed = bool(snap.get("debug_postfx_grain_enabled", false))
	_postfx_grain_strength_slider.value = float(snap.get("debug_postfx_grain_strength", 0.0))
	_postfx_grain_size_slider.value = float(snap.get("debug_postfx_grain_size", 1.0))
	_postfx_tv_toggle.button_pressed = bool(snap.get("debug_postfx_tv_distortion_enabled", false))
	_postfx_tv_glow_aniso_slider.value = float(snap.get("debug_postfx_tv_glow_anisotropy", 0.0))
	_postfx_tv_glow_strength_slider.value = float(snap.get("debug_postfx_tv_glow_strength", 0.92))
	_postfx_tv_glow_hdr_threshold_slider.value = float(snap.get("debug_postfx_tv_glow_hdr_threshold", 1.08))
	_postfx_tv_glow_hdr_scale_slider.value = float(snap.get("debug_postfx_tv_glow_hdr_scale", 1.65))
	_block_postfx_signals(false)
	_refresh_postfx_value_labels()
	_refresh_postfx_controls_enabled()

func _refresh_status_label() -> void:
	if _status_label == null:
		return
	if _flashlight == null:
		_status_label.text = "未连接 PlayerFlashlight3D"
	else:
		_status_label.text = "已连接 · 默认值已锁定为面板首次打开时的 export 值"

func _refresh_value_labels() -> void:
	_beam_energy_label.text = "%.2f" % _beam_energy_slider.value
	_spill_energy_label.text = "%.2f" % _spill_energy_slider.value
	_fill_energy_label.text = "%.2f" % _fill_energy_slider.value

func _refresh_postfx_value_labels() -> void:
	_postfx_aniso_strength_label.text = "%.2f" % _postfx_aniso_strength_slider.value
	_postfx_aniso_expansion_label.text = "%.2f" % _postfx_aniso_expansion_slider.value
	_postfx_hue_label.text = "%.3f" % _postfx_hue_slider.value
	_postfx_brightness_label.text = "%.2f" % _postfx_brightness_slider.value
	_postfx_contrast_label.text = "%.2f" % _postfx_contrast_slider.value
	_postfx_saturation_label.text = "%.2f" % _postfx_saturation_slider.value
	_postfx_grain_strength_label.text = "%.2f" % _postfx_grain_strength_slider.value
	_postfx_grain_size_label.text = "%.2f" % _postfx_grain_size_slider.value
	_postfx_tv_glow_aniso_label.text = "%.2f" % _postfx_tv_glow_aniso_slider.value
	_postfx_tv_glow_strength_label.text = "%.2f" % _postfx_tv_glow_strength_slider.value
	_postfx_tv_glow_hdr_threshold_label.text = "%.2f" % _postfx_tv_glow_hdr_threshold_slider.value
	_postfx_tv_glow_hdr_scale_label.text = "%.2f" % _postfx_tv_glow_hdr_scale_slider.value

func _refresh_postfx_controls_enabled() -> void:
	var color_on := _postfx_adjustment_toggle.button_pressed
	_postfx_hue_slider.editable = color_on
	_postfx_brightness_slider.editable = color_on
	_postfx_contrast_slider.editable = color_on
	_postfx_saturation_slider.editable = color_on

	var grain_on := _postfx_grain_toggle.button_pressed
	_postfx_grain_strength_slider.editable = grain_on
	_postfx_grain_size_slider.editable = grain_on

	var tv_on := _postfx_tv_toggle.button_pressed
	_postfx_tv_glow_aniso_slider.editable = tv_on
	_postfx_tv_glow_strength_slider.editable = tv_on
	_postfx_tv_glow_hdr_threshold_slider.editable = tv_on
	_postfx_tv_glow_hdr_scale_slider.editable = tv_on

func _block_light_signals(block: bool) -> void:
	_beam_color.set_block_signals(block)
	_beam_energy_slider.set_block_signals(block)
	_spill_color.set_block_signals(block)
	_spill_energy_slider.set_block_signals(block)
	_fill_color.set_block_signals(block)
	_fill_energy_slider.set_block_signals(block)

func _block_postfx_signals(block: bool) -> void:
	_postfx_aniso_strength_slider.set_block_signals(block)
	_postfx_aniso_expansion_slider.set_block_signals(block)
	_postfx_adjustment_toggle.set_block_signals(block)
	_postfx_hue_slider.set_block_signals(block)
	_postfx_brightness_slider.set_block_signals(block)
	_postfx_contrast_slider.set_block_signals(block)
	_postfx_saturation_slider.set_block_signals(block)
	_postfx_grain_toggle.set_block_signals(block)
	_postfx_grain_strength_slider.set_block_signals(block)
	_postfx_grain_size_slider.set_block_signals(block)
	_postfx_tv_toggle.set_block_signals(block)
	_postfx_tv_glow_aniso_slider.set_block_signals(block)
	_postfx_tv_glow_strength_slider.set_block_signals(block)
	_postfx_tv_glow_hdr_threshold_slider.set_block_signals(block)
	_postfx_tv_glow_hdr_scale_slider.set_block_signals(block)

func _get_debug_postfx_snapshot() -> Dictionary:
	if GraphicsSettingsManager != null and GraphicsSettingsManager.has_method("get_debug_postfx_snapshot"):
		return GraphicsSettingsManager.get_debug_postfx_snapshot()
	return {}

# ---------- UI 构造 ----------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_build_tab_bar(root)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "调试面板 · [P 切换]"
	root.add_child(title)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = ""
	root.add_child(_status_label)

	root.add_child(HSeparator.new())

	_build_light_page(root)
	_build_postfx_page(root)
	root.add_child(HSeparator.new())

	var reset_btn := Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "复位灯光为 export 默认值"
	reset_btn.pressed.connect(_on_reset_pressed)
	root.add_child(reset_btn)

	var clear_postfx_btn := Button.new()
	clear_postfx_btn.name = "ClearPostfxButton"
	clear_postfx_btn.text = "清除后处理调试覆盖"
	clear_postfx_btn.pressed.connect(_on_clear_postfx_pressed)
	root.add_child(clear_postfx_btn)

func _build_tab_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	bar.name = "TabBar"
	bar.add_theme_constant_override("separation", 6)
	parent.add_child(bar)
	for tab_id in [TabId.LIGHT, TabId.POSTFX, TabId.RESERVED_2, TabId.RESERVED_3]:
		var btn := Button.new()
		btn.name = "TabButton_%d" % int(tab_id)
		btn.text = TAB_LABELS[tab_id]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = tab_id == TabId.RESERVED_2 or tab_id == TabId.RESERVED_3
		btn.pressed.connect(_on_tab_button_pressed.bind(tab_id))
		bar.add_child(btn)
		_tab_buttons[tab_id] = btn

func _on_tab_button_pressed(tab_id: TabId) -> void:
	_select_tab(tab_id)

func _select_tab(tab_id: TabId) -> void:
	_active_tab = tab_id
	for key in _tab_buttons.keys():
		var btn := _tab_buttons[key] as Button
		if btn != null:
			btn.button_pressed = (key == tab_id)
	for key in _tab_pages.keys():
		var page := _tab_pages[key] as Control
		if page != null:
			page.visible = (key == tab_id)

func _build_light_page(parent: Container) -> void:
	var page := VBoxContainer.new()
	page.name = "LightPage"
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)
	_tab_pages[TabId.LIGHT] = page

	_build_light_section(page, "ForwardBeam · 前向主灯", "beam")
	page.add_child(HSeparator.new())
	_build_light_section(page, "EnvironmentSpill · 环境泛光", "spill")
	page.add_child(HSeparator.new())
	_build_light_section(page, "AvatarFrontFill · 角色补光", "fill")

func _build_postfx_page(parent: Container) -> void:
	var page := VBoxContainer.new()
	page.name = "PostfxPage"
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)
	_tab_pages[TabId.POSTFX] = page

	# —— 各向异性 ——
	var aniso_title := Label.new()
	aniso_title.text = "各向异性（glow_anisotropy_*）"
	page.add_child(aniso_title)

	_postfx_aniso_strength_slider = _add_slider_row(
		page, "强度", ANISO_STRENGTH_MIN, ANISO_STRENGTH_MAX, ANISO_STRENGTH_STEP
	)
	_postfx_aniso_strength_label = _find_value_label_for(_postfx_aniso_strength_slider)
	_postfx_aniso_strength_slider.value_changed.connect(_on_aniso_strength_changed)

	_postfx_aniso_expansion_slider = _add_slider_row(
		page, "扩散", ANISO_EXPANSION_MIN, ANISO_EXPANSION_MAX, ANISO_EXPANSION_STEP
	)
	_postfx_aniso_expansion_label = _find_value_label_for(_postfx_aniso_expansion_slider)
	_postfx_aniso_expansion_slider.value_changed.connect(_on_aniso_expansion_changed)

	page.add_child(HSeparator.new())

	# —— 滤镜色彩调整 ——
	var adj_title := Label.new()
	adj_title.text = "滤镜色彩调整（adjustment_*）"
	page.add_child(adj_title)

	_postfx_adjustment_toggle = CheckButton.new()
	_postfx_adjustment_toggle.text = "启用色彩调整"
	_postfx_adjustment_toggle.focus_mode = Control.FOCUS_NONE
	_postfx_adjustment_toggle.toggled.connect(_on_adjustment_toggle_changed)
	page.add_child(_postfx_adjustment_toggle)

	_postfx_hue_slider = _add_slider_row(
		page, "色相", ADJ_HUE_MIN, ADJ_HUE_MAX, ADJ_HUE_STEP
	)
	_postfx_hue_label = _find_value_label_for(_postfx_hue_slider)
	_postfx_hue_slider.value_changed.connect(_on_hue_changed)

	_postfx_brightness_slider = _add_slider_row(
		page, "亮度", ADJ_BRIGHTNESS_MIN, ADJ_BRIGHTNESS_MAX, ADJ_BRIGHTNESS_STEP
	)
	_postfx_brightness_label = _find_value_label_for(_postfx_brightness_slider)
	_postfx_brightness_slider.value_changed.connect(_on_brightness_changed)

	_postfx_contrast_slider = _add_slider_row(
		page, "对比", ADJ_CONTRAST_MIN, ADJ_CONTRAST_MAX, ADJ_CONTRAST_STEP
	)
	_postfx_contrast_label = _find_value_label_for(_postfx_contrast_slider)
	_postfx_contrast_slider.value_changed.connect(_on_contrast_changed)

	_postfx_saturation_slider = _add_slider_row(
		page, "饱和", ADJ_SATURATION_MIN, ADJ_SATURATION_MAX, ADJ_SATURATION_STEP
	)
	_postfx_saturation_label = _find_value_label_for(_postfx_saturation_slider)
	_postfx_saturation_slider.value_changed.connect(_on_saturation_changed)

	page.add_child(HSeparator.new())

	# —— 噪点效果 ——
	var grain_title := Label.new()
	grain_title.text = "噪点效果（grain_*）"
	page.add_child(grain_title)

	_postfx_grain_toggle = CheckButton.new()
	_postfx_grain_toggle.text = "启用噪点"
	_postfx_grain_toggle.focus_mode = Control.FOCUS_NONE
	_postfx_grain_toggle.toggled.connect(_on_grain_toggle_changed)
	page.add_child(_postfx_grain_toggle)

	_postfx_grain_strength_slider = _add_slider_row(
		page, "强度", GRAIN_STRENGTH_MIN, GRAIN_STRENGTH_MAX, GRAIN_STRENGTH_STEP
	)
	_postfx_grain_strength_label = _find_value_label_for(_postfx_grain_strength_slider)
	_postfx_grain_strength_slider.value_changed.connect(_on_grain_strength_changed)

	_postfx_grain_size_slider = _add_slider_row(
		page, "颗粒", GRAIN_SIZE_MIN, GRAIN_SIZE_MAX, GRAIN_SIZE_STEP
	)
	_postfx_grain_size_label = _find_value_label_for(_postfx_grain_size_slider)
	_postfx_grain_size_slider.value_changed.connect(_on_grain_size_changed)

	page.add_child(HSeparator.new())

	# —— 电视干扰 ——
	var tv_title := Label.new()
	tv_title.text = "电视干扰（glow_anisotropy + glow_strength/HDR）"
	page.add_child(tv_title)

	_postfx_tv_toggle = CheckButton.new()
	_postfx_tv_toggle.text = "启用电视干扰"
	_postfx_tv_toggle.focus_mode = Control.FOCUS_NONE
	_postfx_tv_toggle.toggled.connect(_on_tv_toggle_changed)
	page.add_child(_postfx_tv_toggle)

	_postfx_tv_glow_aniso_slider = _add_slider_row(
		page, "各向异性", TV_GLOW_ANISO_MIN, TV_GLOW_ANISO_MAX, TV_GLOW_ANISO_STEP
	)
	_postfx_tv_glow_aniso_label = _find_value_label_for(_postfx_tv_glow_aniso_slider)
	_postfx_tv_glow_aniso_slider.value_changed.connect(_on_tv_glow_aniso_changed)

	_postfx_tv_glow_strength_slider = _add_slider_row(
		page, "发光强度", TV_GLOW_STRENGTH_MIN, TV_GLOW_STRENGTH_MAX, TV_GLOW_STRENGTH_STEP
	)
	_postfx_tv_glow_strength_label = _find_value_label_for(_postfx_tv_glow_strength_slider)
	_postfx_tv_glow_strength_slider.value_changed.connect(_on_tv_glow_strength_changed)

	_postfx_tv_glow_hdr_threshold_slider = _add_slider_row(
		page, "HDR 阈值", TV_GLOW_HDR_THRESHOLD_MIN, TV_GLOW_HDR_THRESHOLD_MAX, TV_GLOW_HDR_THRESHOLD_STEP
	)
	_postfx_tv_glow_hdr_threshold_label = _find_value_label_for(_postfx_tv_glow_hdr_threshold_slider)
	_postfx_tv_glow_hdr_threshold_slider.value_changed.connect(_on_tv_glow_hdr_threshold_changed)

	_postfx_tv_glow_hdr_scale_slider = _add_slider_row(
		page, "HDR 缩放", TV_GLOW_HDR_SCALE_MIN, TV_GLOW_HDR_SCALE_MAX, TV_GLOW_HDR_SCALE_STEP
	)
	_postfx_tv_glow_hdr_scale_label = _find_value_label_for(_postfx_tv_glow_hdr_scale_slider)
	_postfx_tv_glow_hdr_scale_slider.value_changed.connect(_on_tv_glow_hdr_scale_changed)

# 生成一行：[标签] [HSlider] [数值]，返回 HSlider 引用；
# 数值 Label 用唯一名挂在 row 内，便于 _find_value_label_for 反查。
func _add_slider_row(parent: Container, label_text: String, min_v: float, max_v: float, step_v: float) -> HSlider:
	var row := HBoxContainer.new()
	row.name = "SliderRow_" + label_text
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(40, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = min_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.name = "Value"
	value_lbl.text = "%.2f" % min_v
	value_lbl.custom_minimum_size = Vector2(48, 0)
	row.add_child(value_lbl)
	return slider

func _find_value_label_for(slider: HSlider) -> Label:
	var row := slider.get_parent()
	if row == null:
		return null
	return row.get_node_or_null("Value") as Label

func _build_light_section(parent: Container, title_text: String, light_id: String) -> void:
	var box := VBoxContainer.new()
	box.name = light_id.capitalize() + "Section"
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)

	var section_title := Label.new()
	section_title.name = "SectionTitle"
	section_title.text = title_text
	box.add_child(section_title)

	# 第一行：颜色 + ColorPickerButton
	var color_row := HBoxContainer.new()
	color_row.name = "ColorRow"
	color_row.add_theme_constant_override("separation", 8)
	box.add_child(color_row)

	var color_lbl := Label.new()
	color_lbl.text = "颜色"
	color_lbl.custom_minimum_size = Vector2(40, 0)
	color_row.add_child(color_lbl)

	var picker := ColorPickerButton.new()
	picker.name = light_id.capitalize() + "Color"
	picker.custom_minimum_size = Vector2(48, 22)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(picker)

	# 第二行：能量 slider + 数值
	var energy_row := HBoxContainer.new()
	energy_row.name = "EnergyRow"
	energy_row.add_theme_constant_override("separation", 8)
	box.add_child(energy_row)

	var energy_lbl := Label.new()
	energy_lbl.text = "能量"
	energy_lbl.custom_minimum_size = Vector2(40, 0)
	energy_row.add_child(energy_lbl)

	var slider := HSlider.new()
	slider.name = light_id.capitalize() + "Energy"
	slider.min_value = ENERGY_SLIDER_MIN
	slider.max_value = ENERGY_SLIDER_MAX
	slider.step = ENERGY_SLIDER_STEP
	slider.value = 0.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	energy_row.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.name = light_id.capitalize() + "EnergyValue"
	value_lbl.text = "0.00"
	value_lbl.custom_minimum_size = Vector2(48, 0)
	energy_row.add_child(value_lbl)

	# 绑定到对应字段
	match light_id:
		"beam":
			_beam_color = picker
			_beam_energy_slider = slider
			_beam_energy_label = value_lbl
			picker.color_changed.connect(_on_beam_color_changed)
			slider.value_changed.connect(_on_beam_energy_changed)
		"spill":
			_spill_color = picker
			_spill_energy_slider = slider
			_spill_energy_label = value_lbl
			picker.color_changed.connect(_on_spill_color_changed)
			slider.value_changed.connect(_on_spill_energy_changed)
		"fill":
			_fill_color = picker
			_fill_energy_slider = slider
			_fill_energy_label = value_lbl
			picker.color_changed.connect(_on_fill_color_changed)
			slider.value_changed.connect(_on_fill_energy_changed)

# ---------- 事件回调：灯光 ----------

func _on_beam_color_changed(color: Color) -> void:
	if _flashlight != null:
		_flashlight.set_beam_color(color)

func _on_beam_energy_changed(value: float) -> void:
	_beam_energy_label.text = "%.2f" % value
	if _flashlight != null:
		_flashlight.set_beam_energy(value)

func _on_spill_color_changed(color: Color) -> void:
	if _flashlight != null:
		_flashlight.set_spill_color(color)

func _on_spill_energy_changed(value: float) -> void:
	_spill_energy_label.text = "%.2f" % value
	if _flashlight != null:
		_flashlight.set_spill_energy(value)

func _on_fill_color_changed(color: Color) -> void:
	if _flashlight != null:
		_flashlight.set_front_fill_color(color)

func _on_fill_energy_changed(value: float) -> void:
	_fill_energy_label.text = "%.2f" % value
	if _flashlight != null:
		_flashlight.set_front_fill_energy(value)

func _on_reset_pressed() -> void:
	if _flashlight == null or not _has_initial:
		return
	# 写 export + 实时节点都覆盖一遍，避免模块倍率或关灯态残留
	_flashlight.set_beam_color(_initial_beam_color)
	_flashlight.set_beam_energy(_initial_beam_energy)
	_flashlight.set_spill_color(_initial_spill_color)
	_flashlight.set_spill_energy(_initial_spill_energy)
	_flashlight.set_front_fill_color(_initial_fill_color)
	_flashlight.set_front_fill_energy(_initial_fill_energy)
	_sync_from_flashlight()

# ---------- 事件回调：后处理 ----------

func _on_aniso_strength_changed(value: float) -> void:
	_postfx_aniso_strength_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_anisotropy_strength", value)

func _on_aniso_expansion_changed(value: float) -> void:
	_postfx_aniso_expansion_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_anisotropy_expansion", value)

func _on_adjustment_toggle_changed(pressed: bool) -> void:
	_refresh_postfx_controls_enabled()
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_adjustment_enabled", pressed)

func _on_hue_changed(value: float) -> void:
	_postfx_hue_label.text = "%.3f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_adjustment_hue", value)

func _on_brightness_changed(value: float) -> void:
	_postfx_brightness_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_adjustment_brightness", value)

func _on_contrast_changed(value: float) -> void:
	_postfx_contrast_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_adjustment_contrast", value)

func _on_saturation_changed(value: float) -> void:
	_postfx_saturation_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_adjustment_saturation", value)


# ---------- 噪点 —----------

func _on_grain_toggle_changed(pressed: bool) -> void:
	_refresh_postfx_controls_enabled()
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_grain_enabled", pressed)

func _on_grain_strength_changed(value: float) -> void:
	_postfx_grain_strength_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_grain_strength", value)

func _on_grain_size_changed(value: float) -> void:
	_postfx_grain_size_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_grain_size", value)


# ---------- 电视干扰 —----------

func _on_tv_toggle_changed(pressed: bool) -> void:
	_refresh_postfx_controls_enabled()
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_tv_distortion_enabled", pressed)

func _on_tv_glow_aniso_changed(value: float) -> void:
	_postfx_tv_glow_aniso_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_tv_glow_anisotropy", value)

func _on_tv_glow_strength_changed(value: float) -> void:
	_postfx_tv_glow_strength_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_tv_glow_strength", value)

func _on_tv_glow_hdr_threshold_changed(value: float) -> void:
	_postfx_tv_glow_hdr_threshold_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_tv_glow_hdr_threshold", value)

func _on_tv_glow_hdr_scale_changed(value: float) -> void:
	_postfx_tv_glow_hdr_scale_label.text = "%.2f" % value
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.set_debug_postfx("debug_postfx_tv_glow_hdr_scale", value)

func _on_clear_postfx_pressed() -> void:
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.clear_debug_postfx()
	_sync_postfx_from_manager()