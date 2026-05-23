class_name VaultMenu
extends CanvasLayer

## 保险柜 — 基地建筑界面
## 保险柜中的物品跨局持久化（存储在 BaseManager），死亡不丢失，撤离成功自动转入
## 界面支持：查看已存物品、从背包存入、从保险柜取出

@onready var content: VBoxContainer = $Panel/VBox/Content
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

## 保险柜基础容量
const BASE_CAPACITY := 2

func _ready() -> void:
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	_build_vault_view()

func _get_vault_capacity() -> int:
	var vault_lvl: int = 0
	if BaseManager != null:
		vault_lvl = BaseManager.get_level(4)  # building type 4 = vault
	return BASE_CAPACITY + vault_lvl

func _get_vault_items() -> Array[Dictionary]:
	if BaseManager != null:
		return BaseManager.get_vault_items()
	return []

func _build_vault_view() -> void:
	if content == null:
		return
	for child in content.get_children():
		child.queue_free()
	
	var capacity: int = _get_vault_capacity()
	var vault_items: Array[Dictionary] = _get_vault_items()
	var used: int = vault_items.size()
	
	var title := Label.new()
	title.text = "保险柜"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	
	var summary := Label.new()
	summary.text = "保险格: %d / %d （存入的物品跨局保留，死亡不丢失）" % [used, capacity]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(summary)
	
	content.add_child(_make_hsep())
	
	# 已存入物品
	if vault_items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "当前无存入物品"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty_lbl)
	else:
		var hdr := Label.new()
		hdr.text = "—— 已存入物品 ——"
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(hdr)
		for i in vault_items.size():
			content.add_child(_make_vault_item_row(i, vault_items[i]))
	
	content.add_child(_make_hsep())
	
	# 从背包存入（仅展示，按钮点击才真正存入）
	if GameManager != null and GameManager.inventory != null:
		var inv: InventoryModule = GameManager.inventory
		var inv_slots: Array[Dictionary] = inv.get_all_slots()
		var has_items := false
		for slot in inv_slots:
			if not slot.is_empty():
				has_items = true
				break
		
		if has_items:
			var deposit_hdr := Label.new()
			deposit_hdr.text = "—— 从背包存入 ——"
			deposit_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			content.add_child(deposit_hdr)
			
			for idx in inv_slots.size():
				var slot_data: Dictionary = inv_slots[idx]
				if not slot_data.is_empty():
					content.add_child(_make_deposit_row(idx, slot_data, used, capacity))
		else:
			var no背包 := Label.new()
			no背包.text = "背包为空"
			no背包.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			content.add_child(no背包)
	
	content.add_child(_make_hsep())
	
	var upgrade_lbl := Label.new()
	upgrade_lbl.text = "升级保险柜建筑可增加容量（当前 %d 格）" % capacity
	content.add_child(upgrade_lbl)

func _make_vault_item_row(index: int, item_dict: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 44)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
	
	var name_lbl := Label.new()
	name_lbl.text = item_dict.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)
	
	var count_lbl := Label.new()
	count_lbl.text = "×%d" % item_dict.get("count", 1)
	hbox.add_child(count_lbl)
	
	var take_btn := Button.new()
	take_btn.text = "取出"
	take_btn.pressed.connect(_on_take_pressed.bind(index))
	hbox.add_child(take_btn)
	
	return panel

func _make_deposit_row(slot_index: int, slot_data: Dictionary, used: int, capacity: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 44)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
	
	var item: Dictionary = slot_data.get("item", {})
	var name_lbl := Label.new()
	name_lbl.text = "%s ×%d" % [item.get("name", "?"), slot_data.get("count", 1)]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)
	
	var deposit_btn := Button.new()
	
	if used >= capacity:
		deposit_btn.disabled = true
		deposit_btn.text = "格满"
	else:
		deposit_btn.text = "存入"
		deposit_btn.pressed.connect(_on_deposit_pressed.bind(slot_index))
	
	hbox.add_child(deposit_btn)
	return panel

func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 6)
	return sep

func _on_deposit_pressed(slot_index: int) -> void:
	if GameManager == null or GameManager.inventory == null:
		_update_status("当前无背包")
		return
	
	var capacity: int = _get_vault_capacity()
	var vault_items: Array[Dictionary] = _get_vault_items()
	if vault_items.size() >= capacity:
		_update_status("保险柜已满！")
		return
	
	var inv: InventoryModule = GameManager.inventory
	var slot_data: Dictionary = inv.get_slot(slot_index)
	if slot_data.is_empty():
		_update_status("背包格为空")
		return
	
	var item: Dictionary = slot_data.get("item", {})
	var count: int = slot_data.get("count", 1)
	
	# 从背包移除
	var removed: bool = inv.remove_from_slot(slot_index, count)
	if not removed:
		_update_status("存入失败")
		return
	
	# 存入 BaseManager 持久化保险柜
	var ok: bool = BaseManager.add_vault_item(item)
	if not ok:
		# 失败，回退到背包
		inv.add_item(item, count)
		_update_status("存入失败")
		return
	
	inv.notify_inventory_changed()
	_update_status("已存入保险柜")
	# 刷新视图
	_build_vault_view()

func _on_take_pressed(vault_index: int) -> void:
	var vault_items: Array[Dictionary] = _get_vault_items()
	if vault_index < 0 or vault_index >= vault_items.size():
		_update_status("取出失败")
		return
	
	var item: Dictionary = vault_items[vault_index]
	
	var added := false
	if GameManager != null and GameManager.inventory != null:
		added = GameManager.inventory.add_item(item)
	
	if added:
		BaseManager.remove_vault_item(vault_index)
		_update_status("已取回到背包")
		GameManager.inventory.notify_inventory_changed()
	else:
		_update_status("背包已满，无法取出")

func _update_status(msg: String) -> void:
	if status_label:
		status_label.text = msg

func _on_close_pressed() -> void:
	queue_free()