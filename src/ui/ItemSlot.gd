## ItemSlot — 物品格子UI组件
## 配合 InventoryUI 使用，显示物品图标、叠加数量

class_name ItemSlot
extends TextureRect

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)
signal slot_drop_received(source_index: int, target_index: int, source_kind: String, target_kind: String)
signal slot_drag_ended_outside(source_index: int, source_kind: String)
signal slot_drag_started(source_index: int, source_kind: String, item: Dictionary)
signal slot_drag_finished(source_index: int, source_kind: String, successful: bool)

var slot_index: int = -1
var _hovered: bool = false
var _drag_started := false
var _left_pressed := false
var _suppress_click_release := false
var _drag_feedback_active := false
var _drag_feedback_source := false
var _drag_feedback_valid := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var count_label := get_node_or_null("CountLabel") as Control
	if count_label != null:
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_slot_index(idx: int) -> void:
	slot_index = idx

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_pressed = true
			else:
				if _left_pressed and not _suppress_click_release:
					slot_clicked.emit(slot_index)
				_left_pressed = false
				_suppress_click_release = false
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				slot_right_clicked.emit(slot_index)
				accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if bool(get_meta("drag_disabled", false)) or not has_meta("drag_payload"):
		return null
	var payload := (get_meta("drag_payload") as Dictionary).duplicate(true)
	if payload.is_empty():
		return null
	payload["inventory_drag"] = true
	payload["source_index"] = slot_index
	payload["source_kind"] = str(get_meta("slot_kind", "inventory"))
	var item := payload.get("item", {}) as Dictionary
	var preview := PanelContainer.new()
	preview.name = "InventoryDragPreview"
	preview.custom_minimum_size = Vector2(220, 66)
	preview.add_theme_stylebox_override(
		"panel", UIStyleFactory.make_panel_with_border(2, UIPalette.BORDER_FOCUS, 5, 2)
	)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	preview.add_child(margin)
	var text_box := VBoxContainer.new()
	margin.add_child(text_box)
	var title := Label.new()
	title.text = "正在拖拽 · %s" % str(item.get("name", "物品"))
	title.add_theme_color_override("font_color", Color(0.50, 0.94, 1.0))
	text_box.add_child(title)
	var hint := Label.new()
	hint.text = "释放到高亮格位 · 红区丢弃"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	text_box.add_child(hint)
	set_drag_preview(preview)
	_drag_started = true
	_suppress_click_release = true
	slot_drag_started.emit(slot_index, str(get_meta("slot_kind", "inventory")), item.duplicate(true))
	return payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not bool((data as Dictionary).get("inventory_drag", false)):
		return false
	var target_kind := str(get_meta("slot_kind", "inventory"))
	var source_kind := str((data as Dictionary).get("source_kind", "inventory"))
	var item := (data as Dictionary).get("item", {}) as Dictionary
	var carried_source := source_kind in ["inventory", "insurance"]
	if target_kind.begins_with("attachment_"):
		return (
			carried_source
			and str(item.get("type", "")) == "attachment"
			and not bool(get_meta("slot_disabled", false))
			and str(item.get("subtype", "")) == str(get_meta("accepted_subtype", ""))
		)
	if target_kind.begins_with("weapon_"):
		return carried_source and str(item.get("type", "")) == "weapon"
	if target_kind == "backpack":
		return (
			carried_source
			and str(item.get("type", "")) == "equipment"
			and str(item.get("subtype", "")) == "backpack"
		)
	if target_kind.begins_with("quick_"):
		return carried_source and not str(item.get("use_action", "")).is_empty()
	# 保险只描述物品当前所在集合的离场保护，不是锁定。主动拖出后，
	# 保险物与普通背包物一样可装备、绑定快捷栏或丢弃。
	if source_kind == "insurance":
		return target_kind == "drop" or target_kind == "inventory" and not has_meta("slot_item")
	if target_kind == "insurance":
		return source_kind == "inventory" and not has_meta("slot_item")
	if target_kind == "inventory" and (
		source_kind.begins_with("weapon_")
		or source_kind.begins_with("attachment_")
		or source_kind == "backpack"
	):
		return not has_meta("slot_item")
	return target_kind in ["inventory", "drop"]


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var source_index := int((data as Dictionary).get("source_index", -1))
	var source_kind := str((data as Dictionary).get("source_kind", "inventory"))
	var target_kind := str(get_meta("slot_kind", "inventory"))
	slot_drop_received.emit(source_index, slot_index, source_kind, target_kind)


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _drag_started:
		return
	_drag_started = false
	var successful := get_viewport().gui_is_drag_successful()
	slot_drag_finished.emit(slot_index, str(get_meta("slot_kind", "inventory")), successful)
	if not successful:
		slot_drag_ended_outside.emit(slot_index, str(get_meta("slot_kind", "inventory")))


func set_drag_feedback(active: bool, is_source: bool, dragged_item: Dictionary = {}, source_kind := "inventory") -> void:
	_drag_feedback_active = active
	_drag_feedback_source = active and is_source
	var target_kind := str(get_meta("slot_kind", "inventory"))
	_drag_feedback_valid = active and (
		target_kind == "drop"
		or target_kind == "inventory" and (
			source_kind == "inventory"
			or source_kind == "insurance" and not has_meta("slot_item")
			or (source_kind.begins_with("weapon_") or source_kind.begins_with("attachment_") or source_kind == "backpack") and not has_meta("slot_item")
		)
		or target_kind == "insurance" and source_kind == "inventory" and not has_meta("slot_item")
		or target_kind.begins_with("attachment_") and source_kind in ["inventory", "insurance"] and str(dragged_item.get("type", "")) == "attachment" and not bool(get_meta("slot_disabled", false)) and str(dragged_item.get("subtype", "")) == str(get_meta("accepted_subtype", ""))
		or target_kind.begins_with("weapon_") and source_kind in ["inventory", "insurance"] and str(dragged_item.get("type", "")) == "weapon"
		or target_kind == "backpack" and source_kind in ["inventory", "insurance"] and str(dragged_item.get("type", "")) == "equipment" and str(dragged_item.get("subtype", "")) == "backpack"
		or target_kind.begins_with("quick_") and source_kind in ["inventory", "insurance"] and not str(dragged_item.get("use_action", "")).is_empty()
	)
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _draw() -> void:
	var border_color := Color(0.34, 0.39, 0.48, 0.75)
	var border_width := 1.0
	if _drag_feedback_active:
		if _drag_feedback_source:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.76, 0.20, 0.14), true)
			border_color = Color(1.0, 0.76, 0.20, 1.0)
			border_width = 3.0
		elif _drag_feedback_valid:
			var target_kind := str(get_meta("slot_kind", "inventory"))
			border_color = Color(1.0, 0.25, 0.22, 1.0) if target_kind == "drop" else Color(1.0, 0.78, 0.25, 1.0) if target_kind == "insurance" else Color(0.25, 0.95, 0.72, 1.0) if target_kind.begins_with("weapon_") or target_kind.begins_with("quick_") or target_kind == "backpack" else Color(0.30, 0.86, 1.0, 0.95)
			draw_rect(Rect2(Vector2.ZERO, size), Color(border_color.r, border_color.g, border_color.b, 0.10), true)
			border_width = 2.0
	if _hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.56, 0.82, 0.18), true)
		border_color = Color(0.72, 0.82, 1.0, 1.0)
		border_width = maxf(border_width, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, border_width)
