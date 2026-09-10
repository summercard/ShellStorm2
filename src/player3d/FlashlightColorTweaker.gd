class_name FlashlightColorTweaker
extends PanelContainer
## 灯光参数实时调参面板：只暴露 ForwardBeam / EnvironmentSpill / AvatarFrontFill
## 三盏灯的 color + energy。P 键开关；通过 PlayerFlashlight3D 的公开 setter
## 写入 export 变量与实时灯节点，toggle / 模块切换 / _apply_configuration
## 后保留新值。设计意图：临时调试工具，可在 Player3D.tscn 中移除
## FlashlightTweakerLayer 子节点即下线。

const ENERGY_SLIDER_MIN := 0.0
const ENERGY_SLIDER_MAX := 16.0
const ENERGY_SLIDER_STEP := 0.05

var _flashlight: PlayerFlashlight3D
var _status_label: Label
var _beam_color: ColorPickerButton
var _beam_energy_slider: HSlider
var _beam_energy_label: Label
var _spill_color: ColorPickerButton
var _spill_energy_slider: HSlider
var _spill_energy_label: Label
var _fill_color: ColorPickerButton
var _fill_energy_slider: HSlider
var _fill_energy_label: Label

# 初次打开面板时捕获的 export 默认值，供"复位"按钮使用。
var _initial_beam_color: Color
var _initial_beam_energy: float
var _initial_spill_color: Color
var _initial_spill_energy: float
var _initial_fill_color: Color
var _initial_fill_energy: float
var _has_initial := false

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
	offset_right = 360.0
	offset_bottom = 460.0
	custom_minimum_size = Vector2(342, 0)
	_build_ui()
	UIStyleFactory.apply_tactical_tree(self)
	_resolve_flashlight()

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
	get_viewport().set_input_as_handled()

func _sync_from_flashlight() -> void:
	if _flashlight == null:
		_refresh_status_label()
		return
	_block_signals(true)
	_beam_color.color = _flashlight.get_beam_color()
	_beam_energy_slider.value = _flashlight.get_beam_energy()
	_spill_color.color = _flashlight.get_spill_color()
	_spill_energy_slider.value = _flashlight.get_spill_energy()
	_fill_color.color = _flashlight.get_front_fill_color()
	_fill_energy_slider.value = _flashlight.get_front_fill_energy()
	_block_signals(false)
	_refresh_value_labels()
	_refresh_status_label()

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

func _block_signals(block: bool) -> void:
	_beam_color.set_block_signals(block)
	_beam_energy_slider.set_block_signals(block)
	_spill_color.set_block_signals(block)
	_spill_energy_slider.set_block_signals(block)
	_fill_color.set_block_signals(block)
	_fill_energy_slider.set_block_signals(block)

# ---------- UI 构造 ----------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "灯光调参 · [P 切换]"
	root.add_child(title)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = ""
	root.add_child(_status_label)

	root.add_child(HSeparator.new())

	_build_light_section(root, "ForwardBeam · 前向主灯", "beam")
	root.add_child(HSeparator.new())
	_build_light_section(root, "EnvironmentSpill · 环境泛光", "spill")
	root.add_child(HSeparator.new())
	_build_light_section(root, "AvatarFrontFill · 角色补光", "fill")
	root.add_child(HSeparator.new())

	var reset_btn := Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "复位为 export 默认值"
	reset_btn.pressed.connect(_on_reset_pressed)
	root.add_child(reset_btn)

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

# ---------- 事件回调 ----------

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
