class_name BaseStorageSlot
extends PanelContainer
## 基地保险柜/随身背包共用格。只负责显示和输入，所有权变更由 BaseManager 原子提交。

signal item_clicked(owner: String, source_index: int)
signal item_drop_requested(source_owner: String, source_index: int, target_owner: String)

const ITEM_ICON_SCENE := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root_v001.tscn")

var owner_id := ""
var source_index := -1
var item: Dictionary = {}


func configure(new_owner: String, new_index: int, new_item: Dictionary, slot_number: int) -> void:
	owner_id = new_owner
	source_index = new_index
	item = new_item.duplicate(true)
	custom_minimum_size = Vector2(126, 126)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not item.is_empty() else Control.CURSOR_ARROW
	add_theme_stylebox_override("panel", _slot_style(not item.is_empty()))
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 1)
	add_child(root)
	var number := Label.new()
	number.text = "%02d" % (slot_number + 1)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.add_theme_font_size_override("font_size", 10)
	number.add_theme_color_override("font_color", Color(0.32, 0.58, 0.64))
	root.add_child(number)
	if item.is_empty():
		var empty := Label.new()
		empty.text = "空格"
		empty.custom_minimum_size.y = 80
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.add_theme_color_override("font_color", Color(0.24, 0.40, 0.44))
		root.add_child(empty)
		tooltip_text = "可接收另一侧拖入的物品"
		return
	var icon := ITEM_ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.custom_minimum_size = Vector2(76, 72)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.configure(item)
	root.add_child(icon)
	var name_label := Label.new()
	name_label.text = str(item.get("name", item.get("id", "物品")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.80, 0.94, 0.97))
	root.add_child(name_label)
	var count := maxi(1, int(item.get("count", 1)))
	if count > 1:
		name_label.text = "%s  ×%d" % [name_label.text, count]
	tooltip_text = _tooltip_text()


func _gui_input(event: InputEvent) -> void:
	if item.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		item_clicked.emit(owner_id, source_index)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item.is_empty() or source_index < 0:
		return null
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(190, 44)
	preview.add_theme_stylebox_override("panel", _slot_style(true))
	var label := Label.new()
	label.text = "%s  →  %s" % [str(item.get("name", "物品")), "随身背包" if owner_id == "vault" else "保险柜"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "base_storage_item", "owner": owner_id, "index": source_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str(data.get("kind", "")) == "base_storage_item" and str(data.get("owner", "")) != owner_id


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(Vector2.ZERO, data):
		return
	item_drop_requested.emit(str(data.get("owner", "")), int(data.get("index", -1)), owner_id)


func _tooltip_text() -> String:
	var source_name := "长期保险柜" if owner_id == "vault" else "随身背包（下局带入）"
	var text := "%s\n来源：%s\n数量：%d\n单击移到另一侧，或拖拽到另一栏" % [
		str(item.get("name", "物品")), source_name, maxi(1, int(item.get("count", 1))),
	]
	var instance_id := str(item.get("weapon_instance_id", item.get("item_instance_id", "")))
	if not instance_id.is_empty():
		text += "\n实例：#%s" % instance_id.right(6).to_upper()
	return text


func _slot_style(occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.065, 0.078, 0.98) if occupied else Color(0.012, 0.030, 0.038, 0.92)
	style.border_color = Color(0.20, 0.78, 0.88, 0.94) if occupied else Color(0.10, 0.34, 0.40, 0.88)
	style.set_border_width_all(2 if occupied else 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
