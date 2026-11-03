class_name SpecialItemHUD
extends PanelContainer
## Read-only projection; persistent counts and cooldown remain in controller/inventory.
const ICON := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
var controller: SpecialItemController3D
var _icon: ItemModelIcon3D
var _name_label: Label
var _info: Label
var _progress: ProgressBar
var _shown_id := "?"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UIStyleFactory.make_prism_bare_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_icon = ICON.instantiate() as ItemModelIcon3D
	_icon.custom_minimum_size = Vector2(62, 62)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)
	_name_label = Label.new()
	UIStyleFactory.apply_prism_label(_name_label, "value", 1, 16)
	column.add_child(_name_label)
	_info = Label.new()
	UIStyleFactory.apply_prism_label(_info, "faint", 0, 12)
	column.add_child(_info)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(170, 5)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background", UIStyleFactory.make_progress_background())
	_progress.add_theme_stylebox_override("fill", UIStyleFactory.make_progress_fill(Color(1.0, 0.67, 0.19)))
	column.add_child(_progress)
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
	_name_label.text = "[右键] %s" % state.get("name", "未装备特殊道具")
	if content_id.is_empty():
		_info.text = "I / Tab · 装备特殊道具"
		_progress.visible = false
		return
	var remaining := float(state.cooldown_remaining)
	var quantity := "剩余 %d" % int(state.count)
	if content_id == SpecialItemCatalog.GASOLINE:
		quantity = "油量 %d/%d · 备用 %d瓶" % [int(state.fuel_units), int(state.fuel_capacity), int(state.count)]
	var available := int(state.count) > 0 or (content_id == SpecialItemCatalog.GASOLINE and int(state.fuel_units) > 0)
	_info.text = "%s · %s" % [quantity, "冷却 %.1fs" % remaining if remaining > 0.01 else ("按住铺油" if content_id == SpecialItemCatalog.GASOLINE and available else ("可使用" if available else "已耗尽"))]
	_progress.visible = remaining > 0.01
	_progress.max_value = maxf(float(state.cooldown_total), 0.01)
	_progress.value = remaining

func get_ui_snapshot() -> Dictionary:
	return {"name": _name_label.text, "info": _info.text, "cooling": _progress.visible, "item_id": _shown_id}
