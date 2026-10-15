extends GridInventoryBoard
## Shared storage presentation; transaction commands stay with the owning service.
func present(module: InventoryModule, owner: String) -> void:
	slot_kind = owner
	configure(module.get_capacity(), module.get_grid_columns())
	for cell in cells:
		cell.get_node("CountLabel").hide()
		var index := int(cell.get_meta("slot_index"))
		var entry := module.get_slot(index)
		cell.focus_mode = Control.FOCUS_ALL if not entry.is_empty() else Control.FOCUS_NONE
		if not entry.is_empty():
			cell.set_meta("drag_payload", entry.duplicate(true))
			cell.set_meta("slot_item", entry.item.duplicate(true))
			cell.tooltip_text = str(entry.item.get("name", "物品")) + "\n" + str(entry.item.get("description", ""))
		cell.gui_input.connect(func(event: InputEvent) -> void:
			if event.is_action_pressed("ui_accept"):
				slot_clicked.emit(index)
				cell.accept_event())
		cell.focus_entered.connect(_set_item_hover.bind(index, true))
		cell.focus_exited.connect(_set_item_hover.bind(index, false))
		cell.slot_clicked.connect(func(at: int) -> void: slot_clicked.emit(at))
		cell.slot_right_clicked.connect(func(at: int) -> void: slot_right_clicked.emit(at))
		cell.slot_drop_received.connect(func(a: int, b: int, c: String, d: String) -> void: slot_drop_received.emit(a, b, c, d))
		cell.slot_drag_started.connect(func(a: int, b: String, c: Dictionary) -> void: slot_drag_started.emit(a, b, c))
		cell.slot_drag_finished.connect(func(a: int, b: String, c: bool) -> void: slot_drag_finished.emit(a, b, c))
	render_items(module.get_occupied_slots())
