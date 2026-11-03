class_name SpecialItemHUD
extends PanelContainer
const ICON := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
var controller: SpecialItemController3D
var _icon: ItemModelIcon3D
var _info: Label
var _shown_id := "?"
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UIStyleFactory.make_prism_bare_style())
	var root := Control.new()
	root.custom_minimum_size = Vector2(96,62)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_icon = ICON.instantiate() as ItemModelIcon3D
	# Match the weapon icon's visual height and keep digits beside the model.
	_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_icon.offset_left = 0.0
	_icon.offset_top = -18.0
	_icon.offset_right = 36.0
	_icon.offset_bottom = 18.0
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_icon)
	_info = Label.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.offset_left = 40.0
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyleFactory.apply_prism_label(_info,"value",0,13)
	root.add_child(_info)
	_refresh()
func match_readout_style(reference: Label) -> void:
	if _info == null or reference == null:
		return
	_info.add_theme_font_override("font", reference.get_theme_font("font"))
	_info.add_theme_font_size_override("font_size", reference.get_theme_font_size("font_size"))
	_info.add_theme_color_override("font_color", reference.get_theme_color("font_color"))
	_info.add_theme_color_override("font_outline_color", reference.get_theme_color("font_outline_color"))
	_info.add_theme_constant_override("outline_size", reference.get_theme_constant("outline_size"))
func configure(value: SpecialItemController3D) -> void:
	if is_instance_valid(controller) and controller.changed.is_connected(_on_changed):
		controller.changed.disconnect(_on_changed)
	controller = value
	if is_instance_valid(controller):
		controller.changed.connect(_on_changed)
	_refresh()
func _on_changed(_snapshot: Dictionary) -> void:
	_refresh()
func _refresh() -> void:
	if _icon == null:
		return
	var state := controller.get_snapshot() if is_instance_valid(controller) else {}
	var content_id := str(state.get("item_id", ""))
	if content_id != _shown_id:
		_shown_id = content_id
		if content_id.is_empty():
			_icon.clear_model()
		else:
			_icon.configure(SpecialItemCatalog.get_item(content_id))
	_info.text = "" if content_id.is_empty() else "×%d" % int(state.count)
	if content_id == SpecialItemCatalog.GASOLINE:
		_info.text = "%d/%d\n×%d" % [int(state.fuel_units),int(state.fuel_capacity),int(state.count)]
func get_ui_snapshot() -> Dictionary:
	return {"name":"", "info":_info.text,"cooling":false,"item_id":_shown_id}
