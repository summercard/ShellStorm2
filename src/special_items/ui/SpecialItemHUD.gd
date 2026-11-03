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
	root.custom_minimum_size = Vector2(62,62)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_icon = ICON.instantiate() as ItemModelIcon3D
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_icon)
	_info = Label.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyleFactory.apply_prism_label(_info,"value",0,13)
	root.add_child(_info)
	_refresh()
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
