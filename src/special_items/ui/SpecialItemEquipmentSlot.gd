class_name SpecialItemEquipmentSlot
extends VBoxContainer
## A binding slot: accepting an inventory drag never transfers or clones its stock.
const ICON := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
var controller: SpecialItemController3D
var _button: Button
var _icon: ItemModelIcon3D
var _label: Label
var _shown_id := "?"

func _ready() -> void:
	name = "SpecialItemEquipmentSlot"
	custom_minimum_size = Vector2(100, 112)
	var title := Label.new()
	title.text = "特殊道具 · 右键"
	title.add_theme_color_override("font_color", UIPalette.TEXT_GOLD)
	title.add_theme_font_size_override("font_size", 12)
	add_child(title)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(84, 58)
	_button.add_theme_stylebox_override("normal", UIStyleFactory.make_inventory_surface(true))
	_button.tooltip_text = "拖入背包中的特殊道具装备；点击此格解除绑定。数量仍由背包管理。"
	_button.set_drag_forwarding(Callable(), _accepts, _receive)
	_button.pressed.connect(_unequip)
	add_child(_button)
	_icon = ICON.instantiate() as ItemModelIcon3D
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_refresh()

func configure(value: SpecialItemController3D) -> void:
	if is_instance_valid(controller) and controller.changed.is_connected(_on_changed):
		controller.changed.disconnect(_on_changed)
	controller = value
	if is_instance_valid(controller):
		controller.changed.connect(_on_changed)
	_refresh()

func _accepts(_at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not is_instance_valid(controller):
		return false
	var item := (data as Dictionary).get("item", {}) as Dictionary
	return str(data.get("source_kind", "")) == "inventory" and SpecialItemCatalog.contains(str(item.get("id", "")))

func _receive(at: Vector2, data: Variant) -> void:
	if _accepts(at, data):
		controller.equip(str(data.item.id))

func _unequip() -> void:
	if is_instance_valid(controller):
		controller.unequip()

func _on_changed(_state: Dictionary) -> void:
	_refresh()

func _refresh() -> void:
	if _label == null:
		return
	var state := controller.get_snapshot() if is_instance_valid(controller) else {}
	var content_id := str(state.get("item_id", ""))
	if content_id != _shown_id:
		_shown_id = content_id
		if content_id.is_empty():
			_icon.clear_model()
		else:
			_icon.configure(SpecialItemCatalog.get_item(content_id))
	_label.text = "拖入道具 / 点击背包道具" if content_id.is_empty() else "%s ×%d" % [state.name, state.count]
