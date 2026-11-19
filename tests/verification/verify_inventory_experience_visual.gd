extends Node

var failures: Array[String] = []
var clicked := -1
var pointer := Vector2(640, 360)
var checks := 0
var pointer_held := false

func _ready() -> void:
	var focused := OS.get_environment("INVENTORY_QA_EQUIPMENT_FOCUSED") == "1"
	var isolated_data := OS.get_environment("INVENTORY_QA_APPDATA").replace("\\", "/").trim_suffix("/")
	var user_dir := ProjectSettings.globalize_path("user://").replace("\\", "/")
	if focused and (isolated_data.is_empty() or not user_dir.to_lower().begins_with(isolated_data.to_lower() + "/")):
		push_error("运行前必须设置隔离 APPDATA、LOCALAPPDATA 和 INVENTORY_QA_APPDATA。")
		get_tree().quit(2)
		return
	print("INVENTORY_QA_USER_DIR ", user_dir)
	get_window().position = Vector2i(100, 100)
	get_window().size = Vector2i(1280, 720)
	get_window().grab_focus()
	Input.use_accumulated_input = false
	var dungeon_scene := load("res://scenes/Dungeon3D.tscn") as PackedScene
	var dungeon := dungeon_scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	await frames(12)
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	var inventory := dungeon.get("_inventory") as InventoryModule
	inventory.restore_slots_snapshot([])
	inventory.set_capacity(24)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_rifle"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 3)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_pistol"), 1)
	ui.set_inventory_panel_open(true)
	await frames(30)
	if focused:
		# Frame count alone is not a wall-clock guarantee on fast renderers.
		await get_tree().create_timer(0.32, true).timeout
		check(is_equal_approx(float(dungeon.get("_hud_corner_progress")), 1.0), "截图前四角 HUD 已全部退场")
		var finished: Variant = await verify_equipment_focused(ui, inventory)
		check(finished == true, "装备页专项执行到结束")
		finish("INVENTORY_EQUIPMENT_FOCUSED")
		return
	verify_equipment_layout(ui)
	check(ui.inventory_panel.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x, "right panel bounds")
	check(ui.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "footer bounds")
	await capture("inventory_1280.png")
	if OS.get_environment("INVENTORY_QA_RENDER_ONLY") == "1":
		get_window().size = Vector2i(1920, 1080)
		await frames(15)
		await capture("inventory_1920.png")
		ui.set_inventory_panel_open(false)
		get_window().size = Vector2i(1280, 720)
		BaseManager.set_vault_items([ItemRegistry.get_instance().get_item("weapon_pistol"), ItemRegistry.get_instance().get_item("item_health_potion")])
		var storage := preload("res://scenes/VaultMenu.tscn").instantiate() as VaultMenu
		add_child(storage)
		storage.set_inventory_module(inventory)
		await frames(20)
		await capture("warehouse_1280.png")
		storage.queue_free()
		await frames(3)
		BaseManager.add_extraction_points(2000)
		var shop := preload("res://scenes/BaseVendingMenu.tscn").instantiate() as BaseVendingMenu
		add_child(shop)
		shop.set_inventory_module(inventory)
		shop._select_sell(4)
		await frames(20)
		await capture("vending_1280.png")
		print("INVENTORY_STORAGE_RENDER_OK")
		get_tree().quit(0)
		return
	ui.item_clicked.connect(func(index: int, _item: Dictionary) -> void: clicked = index)
	# Disconnect gameplay's click action for the hit-test assertion only.
	for connection in ui.item_clicked.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() != self:
			ui.item_clicked.disconnect(callback)
	var board := ui.inventory_grid as Control
	var tail := board.global_position + Vector2(175, 75)
	motion(tail)
	await frames(3)
	check(ui.item_hover_card.visible, "large item tail hover")
	mouse(tail, true)
	mouse(tail, false)
	await frames(2)
	check(clicked == 0, "large item tail click")
	mouse(tail, true)
	motion(tail + Vector2(12, 0), true)
	await frames(3)
	var target := board.global_position + Vector2(225, 75)
	motion(target, true)
	await frames(3)
	check(ui._drag_feedback_active, "large item tail starts native drag")
	await capture("inventory_drag.png")
	mouse(target, false)
	await frames(8)
	check(not inventory.get_slot(12).is_empty(), "native drag places at exact eight-column anchor")
	var before := JSON.stringify(inventory.get_slots_snapshot())
	var start := board.global_position + Vector2(375, 125)
	motion(start)
	await frames(2)
	mouse(start, true)
	motion(start + Vector2(12, 0), true)
	await frames(3)
	check(get_viewport().gui_is_dragging(), "second native drag active")
	key(KEY_R)
	await frames(2)
	check(ui._drag_rotation == 1, "R rotates ghost")
	key(KEY_ESCAPE)
	motion(board.global_position + Vector2(25, 25), true)
	await frames(2)
	mouse(board.global_position + Vector2(25, 25), false)
	await frames(3)
	check(JSON.stringify(inventory.get_slots_snapshot()) == before, "Esc cancels rotated drag without mutation")
	# Full-width weapon hit area also reaches the real equipment transaction.
	var weapon_id := str((inventory.get_slot(12).get("item", {}) as Dictionary).get("weapon_instance_id", ""))
	await drag_between(board.global_position + Vector2(375, 125), ui.equipment_weapon_slots[1].get_global_rect().get_center())
	check(str((ui.equipment_weapon_slots[1].get_meta("slot_item", {}) as Dictionary).get("weapon_instance_id", "")) == weapon_id, "native drag equips secondary weapon")
	await drag_between(ui.equipment_weapon_slots[1].get_global_rect().get_center(), board.global_position + Vector2(25, 25))
	check(inventory.find_weapon_instance_slot(weapon_id) == 0, "native drag unequips weapon to board")
	var before_sort := inventory.get_used_area()
	ui._on_sort_pressed()
	check(inventory.get_used_area() == before_sort and inventory.get_item_count("item_health_potion") == 3, "sort preserves area and stacks")
	var potion_slot := -1
	for entry in inventory.get_occupied_slots():
		if str(entry.item.id) == "item_health_potion":
			potion_slot = int(entry.slot)
	await drag_between(ui._slots[potion_slot].get_global_rect().get_center(), ui.quick_item_slots[0].get_global_rect().get_center())
	check(str((ui.quick_item_slots[0].get_meta("slot_item", {}) as Dictionary).get("id", "")) == "item_health_potion", "native quick assignment")
	var free_target := inventory.find_valid_placement(ItemRegistry.get_instance().get_item("item_health_potion"))
	var free_index := int(free_target.get("slot", -1))
	await drag_between(ui.quick_item_slots[0].get_global_rect().get_center(), board.global_position + board.call("get_cell_position", free_index) + Vector2(25, 25))
	check(inventory.get_item_count("item_health_potion") == 3, "native quick return preserves stack")
	await drag_between(ui._slots[free_index].get_global_rect().get_center(), ui._insurance_slots[1].get_global_rect().get_center())
	check(str((ui._insurance_slots[1].get_meta("slot_item", {}) as Dictionary).get("id", "")) == "item_health_potion", "native exact insurance slot")
	await drag_between(ui._insurance_slots[1].get_global_rect().get_center(), board.global_position + board.call("get_cell_position", free_index) + Vector2(25, 25))
	check(inventory.get_item_count("item_health_potion") == 3, "native insurance return preserves stack")
	check(ui.insurance_grid.columns == 8 and ui._insurance_slots.size() == 16, "insurance 8x2")
	check(ui.quick_item_slots[0].size == Vector2(50, 50), "quick slot shares grid size")
	check(absf(ui.inventory_panel.get_global_rect().position.y - (720 - ui.inventory_panel.get_global_rect().end.y)) <= 2, "equal vertical margins")
	check(dungeon.get("_inventory_close_button") == null, "single bottom close button")
	await drag_between(ui._slots[free_index].get_global_rect().get_center(), ui.drop_zone.get_global_rect().get_center())
	check(inventory.get_item_count("item_health_potion") == 0, "equipment bottom drop removes stack")
	inventory.set_capacity(72)
	await frames(8)
	ui.inventory_scroll.scroll_vertical = 300
	await frames(3)
	check(ui.inventory_scroll.scroll_vertical > 0, "expanded bag scrolls")
	check(ui.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "expanded footer remains visible")
	inventory.set_capacity(24)
	ui.inventory_scroll.scroll_vertical = 0
	get_window().size = Vector2i(1920, 1080)
	await frames(20)
	await capture("inventory_1920.png")
	key(KEY_ESCAPE)
	await frames(2)
	check(not ui.is_inventory_open(), "Esc closes inventory")
	get_window().size = Vector2i(1280, 720)
	BaseManager.set_vault_items([])
	var vault := preload("res://scenes/VaultMenu.tscn").instantiate() as VaultMenu
	add_child(vault)
	vault.set_inventory_module(inventory)
	await frames(20)
	var warehouse_board: Control = vault._boards["vault"]
	var carried_board: Control = vault._boards["inventory"]
	var carried_rifle := inventory.find_weapon_instance_slot(weapon_id)
	await drag_between(carried_board.global_position + carried_board.get_cell_position(carried_rifle) + Vector2(175, 75), warehouse_board.global_position + Vector2(225, 25))
	check(inventory.find_weapon_instance_slot(weapon_id) == -1, "warehouse transfer removes source")
	var warehouse_model := BaseManager.get_storage_grid("vault")
	check(str(warehouse_model.get_slot(4).get("item", {}).get("weapon_instance_id", "")) == weapon_id, "warehouse drop preserves exact anchor")
	await drag_between(warehouse_board.global_position + Vector2(375, 75), warehouse_board.global_position + Vector2(25, 25))
	warehouse_model = BaseManager.get_storage_grid("vault")
	check(warehouse_model.find_weapon_instance_slot(weapon_id) == 0, "warehouse same-board placement persists")
	await capture("warehouse_1280.png")
	await drag_between(warehouse_board.global_position + Vector2(175, 75), carried_board.global_position + Vector2(225, 75))
	check(inventory.find_weapon_instance_slot(weapon_id) == 12, "warehouse return exact inventory anchor")
	check(BaseManager.get_vault_items().is_empty(), "warehouse transfer no duplicate")
	check(vault._boards["inventory"].columns == 8, "warehouse same eight-column board")
	vault.queue_free()
	await frames(3)
	BaseManager.add_extraction_points(2000)
	var vending := preload("res://scenes/BaseVendingMenu.tscn").instantiate() as BaseVendingMenu
	add_child(vending)
	vending.set_inventory_module(inventory)
	await frames(30)
	var close := vending.find_child("CloseButton", true, false) as Control
	check(close.get_global_rect().end.y <= 720 and close.is_visible_in_tree(), "vending close visible")
	var funds := BaseManager.get_extraction_points()
	vending._on_buy_pressed("item_health_potion")
	await frames(8)
	check(inventory.get_item_count("item_health_potion") == 1 and BaseManager.get_extraction_points() < funds, "vending purchase commits item and funds")
	var purchase_anchor := -1
	for entry in inventory.get_occupied_slots():
		if entry.item.id == "item_health_potion": purchase_anchor = int(entry.slot)
	vending._select_sell(purchase_anchor)
	await frames(3)
	await capture("vending_1280.png")
	var sell_button := vending._sell_actions.get_child(1) as Button
	var funds_before_sale := BaseManager.get_extraction_points()
	sell_button.pressed.emit()
	await frames(8)
	check(inventory.get_item_count("item_health_potion") == 0 and BaseManager.get_extraction_points() > funds_before_sale, "vending sale commits item and funds")
	vending._select_sell(12)
	await frames(2)
	if vending._sell_actions.get_child_count() > 1:
		var weapon_sell := vending._sell_actions.get_child(1) as Button
		weapon_sell.pressed.emit()
		check(inventory.find_weapon_instance_slot(weapon_id) == 12 and weapon_sell.get_meta("confirm_sell", false), "weapon sale requires second confirmation")
	else:
		check(false, "weapon sale selection exists")
	check(vending._sell_board.columns == 8, "vending same eight-column board")
	vending.queue_free()
	await frames(3)
	finish("INVENTORY_EXPERIENCE_VISUAL")

func verify_equipment_layout(ui: InventoryUI) -> void:
	var left := ui.equipment_panel.get_global_rect()
	var right := ui.inventory_panel.get_global_rect()
	check(absf(left.end.x - right.position.x) <= 1, "两窗贴合，无中央间隙")
	check(absf(left.size.x / (left.size.x + right.size.x) - 0.65) <= 0.025, "装备页宽约 65%%（%s / %s）" % [left.size.x, right.size.x])
	var columns := ui.find_child("EquipmentThreeColumns", true, false) as HBoxContainer
	var main := (columns.get_child(0) as Control).get_global_rect()
	var center := (columns.get_child(1) as Control).get_global_rect()
	var secondary := (columns.get_child(2) as Control).get_global_rect()
	check(main.end.x <= center.position.x and center.end.x <= secondary.position.x and absf(main.size.x - center.size.x) <= 2 and absf(center.size.x - secondary.size.x) <= 2, "三列等宽且顺序为主枪、角色、副枪")
	var special_button := ui.special_equipment_slot._button
	var backpack := ui.equipment_backpack_slot.get_global_rect()
	var special := special_button.get_global_rect()
	var quick := ui.quick_item_slots[0].get_global_rect()
	var moon := ui.equipment_moon_fate_row.get_parent() as ScrollContainer
	var drop := ui.drop_zone.get_global_rect()
	check(ui.character_preview.get_global_rect().end.y <= backpack.position.y and backpack.end.x <= special.position.x and absf(backpack.position.y - special.position.y) <= 2, "预览正下方左背包右特殊道具")
	check(special.end.y <= quick.position.y and quick.end.y <= moon.get_global_rect().position.y, "快捷格下一行，月牌置底")
	check(moon.get_global_rect().end.y <= drop.position.y and left.encloses(drop), "丢弃区独立，位于月卡之后且在装备窗内")
	var slots: Array[Control] = [ui.equipment_backpack_slot, special_button, ui.special_equipment_slot._icon]
	slots.append_array(ui.quick_item_slots)
	slots.append_array(ui.equipment_bullet_slots)
	for attachment_row: Array in ui.equipment_attachment_slots:
		for slot: Control in attachment_row:
			slots.append(slot)
	check(slots.all(func(slot: Control) -> bool: return slot.size == Vector2(50, 50)), "配件、弹药、背包、快捷、特殊按钮和图标容器均为 50×50")
	check(ui.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y and right.end.x <= get_viewport().get_visible_rect().end.x, "右窗与关闭按钮无越界")
	check(ui.insurance_grid.columns == 8 and ui._insurance_slots.size() == 16, "保险仍是 8×2")

func verify_equipment_focused(ui: InventoryUI, inventory: InventoryModule) -> bool:
	var owner := ui._weapon_owner as Player3D
	var ids := ["weapon_rifle", "weapon_pistol"]
	var capacities := [8, 6]
	for i in 2:
		var weapon := WeaponInstance.from_item(ItemRegistry.get_instance().get_item(ids[i]))
		weapon.fate_slot_capacity = capacities[i]
		if i == 0:
			var upright := FateCardPresets.get_by_card_id("fate_overclock")
			var reversed := FateCardPresets.get_by_card_id("fate_living_bullet")
			reversed.set_orientation(FateCard.Orientation.REVERSED)
			check(weapon.append_fate_upgrade(upright).success and weapon.append_fate_upgrade(reversed).success, "用真实永久槽记录准备正逆位测试数据")
		check(owner.equip_weapon_item_to_slot(weapon.to_item_dictionary(), i).success, "装备真实枪械实例 %d" % i)
	var run_cards: Array[Dictionary] = []
	for id in ["fate_moon_vitality", "fate_moon_first_hit", "fate_sun_currency"]:
		var card := FateCardPresets.get_by_card_id(id)
		card.set_orientation(FateCard.Orientation.REVERSED if id == "fate_moon_first_hit" else FateCard.Orientation.UPRIGHT)
		var entry := card.get_orientation_snapshot()
		entry["stable_card_id"] = id
		run_cards.append(entry)
	check(FateCardGameBridge.import_fate_snapshot({"version": 1, "cards": run_cards, "pending": []}), "通过运行状态快照载入两月一日")
	inventory.add_item(SpecialItemCatalog.get_item(SpecialItemCatalog.GRENADE), 2)
	var controller := owner.get_special_item_controller()
	check(ui.special_equipment_slot.controller == controller, "首次构建即绑定真实特殊道具控制器")
	check(controller.equip(SpecialItemCatalog.GRENADE).success, "特殊道具图标使用实际背包库存")
	ui._refresh_equipment_ui()
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_window().size = resolution
		await frames(18)
		verify_equipment_layout(ui)
		await capture("equipment_%d.png" % resolution.x, resolution)
	var main_track := ui.equipment_fate_rows[0]
	var canvas := main_track.get_node("FateTrackCanvas") as Control
	check(canvas.get_child_count() == 9 and ui.equipment_fate_rows[1].get_node("FateTrackCanvas").get_child_count() == 7, "卡巢数量分别读取 8 和 6，不截成四格")
	var first := canvas.get_node("FateSocket01") as Control
	var second := canvas.get_node("FateSocket02") as Control
	var empty := canvas.get_node("FateSocket03") as Control
	var segments: Array = canvas.get_node("WeaponFateTrack").get("segments")
	check(first.position.y < second.position.y and second.position.y > empty.position.y and segments.size() == 8 and segments[1].active and not segments[2].active, "卡巢高低交错，走线仅在真实已装槽点亮")
	var back := empty.find_child("TarotCardBack", true, false) as TextureRect
	check(back != null and back.material is ShaderMaterial and (back.get_parent() as Control).modulate.a < 1.0, "空巢使用半透明暗色卡背")
	verify_card_socket(first, false)
	verify_card_socket(second, true)
	check(ui.equipment_moon_fate_row.get_child_count() == 2, "月牌只呈现实际已获得的月牌")
	verify_card_socket(ui.equipment_moon_fate_row.get_child(0) as Control, false)
	verify_card_socket(ui.equipment_moon_fate_row.get_child(1) as Control, true)
	var sun := ui.find_child("SunFateStatus", true, false) as MenuButton
	check(sun.focus_mode == Control.FOCUS_ALL and sun.get_popup().item_count == 1 and "太阳" in sun.accessibility_description, "太阳命运可查询、可键盘访问并提供读屏说明")
	for i in 2:
		var weapon_slot := ui.equipment_weapon_slots[i]
		var bullet := ui.equipment_bullet_slots[i]
		check(bullet.get_parent() == weapon_slot and weapon_slot.get_global_rect().encloses(bullet.get_global_rect()) and bullet.has_meta("slot_item") and not (bullet.get_node("CountLabel") as Label).visible, "弹药嵌在实际枪格内且无常驻文字")
	var column_width := (main_track.get_parent() as Control).size.x
	(canvas.get_node("FateSocket08") as Control).grab_focus()
	await frames(4)
	check(main_track.scroll_horizontal > 0 and (main_track.get_parent() as Control).size.x == column_width, "聚焦尾槽可横滚，轨道不撑列")
	if DisplayServer.get_name() != "headless":
		await capture("equipment_track_end_1920.png")
	else:
		get_window().size = Vector2i(1280, 720)
		await frames(8)
		var potion := ui._slots[4].get_global_rect().get_center()
		var before := JSON.stringify(inventory.get_slots_snapshot())
		var invalid: Array[Control] = [ui.equipment_weapon_slots[1], ui.equipment_bullet_slots[0], ui.equipment_backpack_slot, ui.special_equipment_slot._button, ui.equipment_attachment_slots[0][0], ui.equipment_moon_fate_row.get_child(0)]
		for target in invalid:
			await drag_between(potion, target.get_global_rect().get_center())
			check(JSON.stringify(inventory.get_slots_snapshot()) == before, "无效拖放不丢弃：%s" % target.name)
		await drag_between(potion, ui.drop_zone.get_global_rect().get_center())
		check(inventory.get_item_count("item_health_potion") == 0, "仅装备页底部空白热区执行丢弃")
	return true

func verify_card_socket(socket: Control, reversed: bool) -> void:
	var face := socket.find_child("SocketFace", true, false) as TextureRect
	var brief := socket.get_node("EffectBrief") as Label
	check(face != null and face.texture != null and is_equal_approx(absf(face.rotation), PI if reversed else 0.0), "真实牌图与正逆位确切对应")
	check(brief.visible and brief.text.length() >= 1 and brief.text.length() <= 5 and is_zero_approx(brief.rotation), "效果摘要不超过五字，且不随牌图旋转")

func finish(result_name: String) -> void:
	for failure in failures:
		push_error(failure)
	print("%s_%s checks=%d" % [result_name, "OK" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	checks += 1
	print("CHECK %s %s" % [label, value])
	if not value:
		failures.append(label)

func frames(count: int) -> void:
	for i in count:
		Input.warp_mouse(pointer)
		await get_tree().process_frame

func capture(file: String, expected_size := Vector2i.ZERO) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("INVENTORY_QA_OUTPUT")
	if output.is_empty():
		output = "user://inventory_qa"
	DirAccess.make_dir_recursive_absolute(output)
	var image := get_viewport().get_texture().get_image()
	if expected_size != Vector2i.ZERO:
		check(image.get_size() == expected_size, "截图像素等于目标分辨率（%s）" % image.get_size())
	check(image.save_png(output.path_join(file)) == OK, file)

func motion(point: Vector2, held := false) -> void:
	pointer = point
	pointer_held = held
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(12, 0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)

func mouse(point: Vector2, pressed: bool) -> void:
	pointer = point
	pointer_held = pressed
	Input.warp_mouse(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)

func drag_between(start: Vector2, target: Vector2) -> void:
	motion(start)
	await frames(3)
	mouse(start, true)
	motion(start + Vector2(12, 0), true)
	await frames(3)
	motion(target, true)
	await frames(6)
	mouse(target, false)
	await frames(8)
